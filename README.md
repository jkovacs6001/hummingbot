# WEEX VCC-USDT Trading Bot

Hummingbot fork with a custom [WEEX](https://www.weex.com) exchange connector and two automated trading strategies for the VCC-USDT market.

## Strategies

| Script | Config | Purpose |
|--------|--------|---------|
| `scripts/weex_vcc_pmm.py` | `conf/scripts/weex_vcc_pmm.yml` | Multi-level passive market making (15 levels per side, 0.4–6% spreads) |
| `scripts/weex_volume_generator.py` | `conf/scripts/weex_volume_generator.yml` | Active volume generation — crosses the spread to hit MM orders and maintain daily volume target |

Both strategies use Hummingbot's `ScriptStrategyBase`. Config is a Pydantic model defined in the same file as the strategy.

## Quick Start

### Prerequisites

- Docker + Docker Compose
- WEEX API key, secret, and passphrase (from your WEEX account settings)

### 1. Configure credentials

Add your API credentials to `conf/connectors/weex.yml` via the Hummingbot CLI (`connect weex`) or by encrypting and pasting them directly.

### 2. Deploy

```bash
make setup    # prompts whether to include DEX Gateway (usually N)
make deploy   # docker compose up -d
```

Attach to the running bot:
```bash
docker attach hummingbot
```

### 3. Start a strategy

Inside the Hummingbot CLI:
```
start --script weex_vcc_pmm.py --conf conf_weex_vcc_pmm.yml
```

## Operations

```bash
./preflight.sh   # validate environment before deploying
./deploy.sh      # deploy with directory setup
./monitor.sh     # view service status
./stop.sh        # stop all services
./backup.sh      # backup data directory
./update.sh      # pull latest and redeploy
```

## Configuration

### Market Maker (`conf/scripts/weex_vcc_pmm.yml`)

Key parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `number_of_orders` | 15 | Order levels per side |
| `order_refresh_time` | 60 | Seconds between full refresh |
| `use_dynamic_levels` | true | Randomize order amounts ±15% each cycle |
| `kill_switch_rate` | -0.03 | Stop if portfolio drops 3% from start |
| `immediate_replenishment` | true | Replace filled orders immediately |

### Volume Generator (`conf/scripts/weex_volume_generator.yml`)

Key parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `daily_volume_target_usdt` | 12000 | Target USDT volume per day |
| `order_size_usdt` | 30 | Per-trade size before randomization |
| `trade_interval_seconds` | 216 | Base interval between trades (±40% jitter) |
| `order_type` | `limit_cross_spread` | Cross the spread to ensure fill |
| `rebalance_threshold` | 500000 VCC | Inventory deviation before forcing rebalance |

**Cost estimate:** ~0.4–0.6% of volume in fees (0.2% maker/taker + spread crossing).

**Balance requirements at ~$0.00015/VCC:** ~$200 USDT + ~1,000,000 VCC (2–3× minimum recommended).

## WEEX Connector

Located at `hummingbot/connector/exchange/weex/`. Built on `ExchangePyBase`.

**Rate limit design:** REST order polling is disabled (`UPDATE_ORDER_STATUS_MIN_INTERVAL = inf`). All order/fill/account updates come from the private WebSocket. WEEX enforces a 500 weight/10s pool and a 50 weight/1s burst limit — polling 8+ open orders via REST would exceed the burst limit. Batch order APIs are used wherever possible (10 weight vs. 40 weight for 8 individual orders).

**Authentication:** HMAC-SHA256, base64-encoded. Signature: `timestamp + METHOD + path + query + body`. Headers: `ACCESS-KEY`, `ACCESS-TIMESTAMP`, `ACCESS-SIGN`, `ACCESS-PASSPHRASE`.

**Symbol format:** WEEX uses `VCCUSDT-SPBL`; Hummingbot uses `VCC-USDT`.

## Development (Source)

Requires Conda.

```bash
make install   # create conda env, build Cython extensions
make run       # start Hummingbot CLI from source

# Run connector tests
conda run -n hummingbot pytest test/hummingbot/connector/exchange/weex/ -v

# Full test suite
make test
```

## Project Structure

```
hummingbot/connector/exchange/weex/   # WEEX exchange connector
scripts/weex_vcc_pmm.py               # Market making strategy
scripts/weex_volume_generator.py      # Volume generation strategy
conf/connectors/weex.yml              # Encrypted API credentials
conf/scripts/                         # Strategy YAML configs
monitor_dashboard.py                  # Streamlit monitoring UI (port 8501)
```

## License

Apache 2.0 — based on [Hummingbot](https://github.com/hummingbot/hummingbot).
