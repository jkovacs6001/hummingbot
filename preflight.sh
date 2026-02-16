#!/bin/bash
# Pre-flight Check for WEEX Production Deployment
# Verifies all requirements are met before deployment

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}WEEX Production Deployment Pre-flight${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Function to check command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "✅ $1 is installed"
        return 0
    else
        echo -e "${RED}❌ $1 is NOT installed${NC}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Function to check version
check_version() {
    local cmd=$1
    local min_version=$2
    local current_version

    case $cmd in
        docker)
            current_version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
            ;;
        "docker compose")
            current_version=$(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)
            ;;
    esac

    if [ -n "$current_version" ]; then
        echo -e "   Version: $current_version (minimum: $min_version)"
    fi
}

# Check essential commands
echo -e "${YELLOW}Checking required software...${NC}"
check_command docker && check_version docker "20.10.0"
if docker compose version &> /dev/null; then
    echo -e "✅ docker compose is installed"
    echo -e "   Version: $(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1) (minimum: 2.0.0)"
else
    echo -e "${RED}❌ docker compose is NOT installed${NC}"
    ERRORS=$((ERRORS + 1))
fi
check_command git
check_command tar
check_command curl
echo ""

# Check Docker daemon
echo -e "${YELLOW}Checking Docker daemon...${NC}"
if docker info &> /dev/null; then
    echo -e "✅ Docker daemon is running"
else
    echo -e "${RED}❌ Docker daemon is NOT running${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check environment file
echo -e "${YELLOW}Checking environment configuration...${NC}"
if [ -f .env ]; then
    echo -e "✅ .env file exists"

    # Check for required variables
    required_vars=(
        "WEEX_MM_API_KEY"
        "WEEX_MM_API_SECRET"
        "WEEX_MM_PASSPHRASE"
        "WEEX_VOL_API_KEY"
        "WEEX_VOL_API_SECRET"
        "WEEX_VOL_PASSPHRASE"
    )

    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=.\+" .env; then
            echo -e "   ✅ $var is set"
        else
            echo -e "   ${RED}❌ $var is NOT set or empty${NC}"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo -e "${RED}❌ .env file NOT found${NC}"
    echo -e "   Run: cp .env.example .env"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check directory structure
echo -e "${YELLOW}Checking directory structure...${NC}"
required_dirs=(
    "conf"
    "conf/connectors"
    "conf/scripts"
    "scripts"
    "hummingbot"
)

for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "✅ $dir/ exists"
    else
        echo -e "${RED}❌ $dir/ NOT found${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# Check required files
echo -e "${YELLOW}Checking required files...${NC}"
required_files=(
    "docker-compose.prod.yml"
    "Dockerfile"
    "Dockerfile.monitor"
    "deploy.sh"
    "stop.sh"
    "monitor.sh"
    "scripts/weex_vcc_pmm.py"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "✅ $file exists"
    else
        echo -e "${YELLOW}⚠️  $file NOT found${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo ""

# Check system resources
echo -e "${YELLOW}Checking system resources...${NC}"

# Memory
total_mem=$(free -g | awk '/^Mem:/{print $2}')
if [ "$total_mem" -ge 4 ]; then
    echo -e "✅ Memory: ${total_mem}GB (minimum: 4GB)"
else
    echo -e "${YELLOW}⚠️  Memory: ${total_mem}GB (recommended: 4GB or more)${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Disk space
available_disk=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$available_disk" -ge 20 ]; then
    echo -e "✅ Disk space: ${available_disk}GB available (minimum: 20GB)"
else
    echo -e "${YELLOW}⚠️  Disk space: ${available_disk}GB available (recommended: 20GB or more)${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# CPU cores
cpu_cores=$(nproc)
if [ "$cpu_cores" -ge 2 ]; then
    echo -e "✅ CPU cores: $cpu_cores (minimum: 2)"
else
    echo -e "${YELLOW}⚠️  CPU cores: $cpu_cores (recommended: 2 or more)${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# Check network connectivity
echo -e "${YELLOW}Checking network connectivity...${NC}"
if curl -s --connect-timeout 5 https://api-spot.weex.com > /dev/null 2>&1; then
    echo -e "✅ Can reach WEEX API"
else
    echo -e "${RED}❌ Cannot reach WEEX API${NC}"
    ERRORS=$((ERRORS + 1))
fi

if curl -s --connect-timeout 5 https://hub.docker.com > /dev/null 2>&1; then
    echo -e "✅ Can reach Docker Hub"
else
    echo -e "${YELLOW}⚠️  Cannot reach Docker Hub (might affect image pulls)${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# Check ports
echo -e "${YELLOW}Checking port availability...${NC}"
if ! netstat -tuln 2>/dev/null | grep -q ':8501 '; then
    echo -e "✅ Port 8501 (Dashboard) is available"
else
    echo -e "${YELLOW}⚠️  Port 8501 is already in use${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Pre-flight Check Summary${NC}"
echo -e "${GREEN}========================================${NC}"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo -e "${GREEN}You are ready to deploy.${NC}"
    echo ""
    echo -e "Run: ${YELLOW}./deploy.sh${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Pre-flight check completed with $WARNINGS warning(s)${NC}"
    echo -e "${YELLOW}You can proceed, but review warnings above.${NC}"
    echo ""
    echo -e "Run: ${YELLOW}./deploy.sh${NC}"
    exit 0
else
    echo -e "${RED}❌ Pre-flight check failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo -e "${RED}Please fix the errors above before deploying.${NC}"
    exit 1
fi
