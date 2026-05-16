# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A fork of [Hummingbot](https://hummingbot.org) (open-source algorithmic trading framework) with a custom **WEEX exchange connector** and two custom trading strategies:
- `scripts/weex_vcc_pmm.py` — Multi-level market making for VCC-USDT
- `scripts/weex_volume_generator.py` — Daily volume generation via batch orders

The upstream Hummingbot framework is largely unchanged. Primary development focus is the WEEX connector and these two scripts.

## Commands

### Source Installation (Conda)
```bash
make install          # Create/update conda env, build Cython extensions
make run              # Start Hummingbot CLI (conda run)
make uninstall        # Remove conda env
```

### Running Tests
```bash
make test             # Full test suite (excludes some ignored dirs)
# Run a specific connector test:
conda run -n hummingbot pytest test/hummingbot/connector/exchange/weex/ -v
# Run a single test file:
conda run -n hummingbot pytest test/hummingbot/connector/exchange/weex/test_weex_exchange.py -v
```

### Docker Deployment
```bash
make setup            # Prompts whether to include Gateway, writes .compose.env
make deploy           # docker compose up -d
make down             # Stop all services including gateway

# Production targets delegate to Makefile.prod:
make prod-check       # Check service status
```

### Monitoring / Operations
```bash
./deploy.sh           # Full deploy with directory setup
./monitor.sh          # View service status
./stop.sh             # Stop services
./backup.sh           # Backup data
./preflight.sh        # Validate environment before deploy
```

## WEEX Connector Architecture

The connector lives in `hummingbot/connector/exchange/weex/` and extends `ExchangePyBase` (the standard Hummingbot Python connector base class).

### Key Files
| File | Purpose |
|------|---------|
| `weex_exchange.py` | Main connector class (`WeexExchange`) |
| `weex_auth.py` | HMAC-SHA256 request signing |
| `weex_constants.py` | API URLs, rate limits, order state mappings |
| `weex_web_utils.py` | URL builders, throttler/factory factory |
| `weex_api_order_book_data_source.py` | Public WS + REST order book |
| `weex_api_user_stream_data_source.py` | Private WS for orders/fills/balances |
| `weex_utils.py` | `WeexConfigMap` (credentials), default fees |
| `weex_order_book.py` | Order book message parsing |

### Critical Design Decisions

**REST order polling is disabled.** WEEX enforces a dual-tier rate limit (500 weight/10s + 50 weight/1s burst). With 8+ open orders, polling each one via REST exceeds the burst limit. The connector sets:
```python
UPDATE_ORDER_STATUS_MIN_INTERVAL = float('inf')  # disabled
SHORT_POLL_INTERVAL = 300.0                       # balance check every 5 min
```
All real-time order/fill/account updates come through the **private WebSocket** instead.

**Batch API usage.** `batch_order_create` and `batch_order_cancel` use WEEX's batch endpoints (`/api/v2/trade/batch-orders`, `/api/v2/trade/cancel-batch-orders`) to reduce weight consumption (10 weight vs. 8×5=40 weight for individual orders).

**WEEX symbol format.** Exchange uses `VCCUSDT-SPBL`; Hummingbot uses `VCC-USDT`. `weex_symbol_to_hb_pair()` strips the `-SPBL` suffix and splits on known quote currencies. `_initialize_trading_pair_symbols_from_exchange_info()` builds the bidict mapping from exchange info.

**REST polling toggle.** The env var `WEEX_DISABLE_REST_ORDER_POLLING=1` controls whether REST polling is active (default: disabled). Useful for debugging/testing without risking rate limit bans.

### Authentication

HMAC-SHA256, base64-encoded. Signature payload: `timestamp_ms + METHOD + path + ?query + body`.

Required headers: `ACCESS-KEY`, `ACCESS-TIMESTAMP`, `ACCESS-SIGN`, `ACCESS-PASSPHRASE` (if set).

WS private authentication uses the same signing but over a fixed path (`/v2/ws/private`) and is sent as connection headers (no listen-key system like Binance).

### Rate Limits (weex_constants.py)
- Global pool: 500 weight / 10 seconds
- Burst: 50 weight / 1 second
- Key endpoint weights: create order=5, cancel order=3, batch ops=10, account=5, order status=2

## Connector Configuration

Credentials are stored in `conf/connectors/weex.yml` and referenced via `WeexConfigMap` (fields: `weex_api_key`, `weex_api_secret`, `weex_api_passphrase`).

Strategy configs live in `conf/scripts/*.yml` and are loaded when running scripts from the Hummingbot CLI.

## Hummingbot Framework Patterns

When modifying or extending the connector, these abstract methods from `ExchangePyBase` must be respected:
- `_place_order` / `_place_cancel` — single order REST calls
- `_format_trading_rules` — parse exchange info into `TradingRule` objects
- `_update_balances` — fetch and update balance state
- `_user_stream_event_listener` — consume private WS messages and emit `OrderUpdate` / `TradeUpdate`
- `_request_order_status` — REST fallback for order status

Scripts extend `ScriptStrategyBase` and define a `on_tick()` method. Config is a Pydantic `BaseClientModel` class defined in the same file.

## Monitoring Dashboard

`monitor_dashboard.py` is a Streamlit app (`docker-compose.yml` exposes it on port 8501). It reads bot logs and displays health/activity. `monitor_dashboard.py` and `hummingbot_agent.py` are standalone files not part of the core Hummingbot package.
