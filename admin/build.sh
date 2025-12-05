#!/bin/bash

set -e

echo "🔨 Building Kemal WAF Admin Panel..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Build frontend
echo -e "${YELLOW}📦 Building frontend...${NC}"
cd "$PROJECT_ROOT/admin-ui"

if [ ! -d "node_modules" ]; then
    echo "Installing npm dependencies..."
    npm install
fi

npm run build

echo -e "${GREEN}✅ Frontend built successfully${NC}"

# Build backend
echo -e "${YELLOW}🔧 Building backend...${NC}"
cd "$SCRIPT_DIR"

if [ ! -d "lib" ]; then
    echo "Installing Crystal dependencies..."
    shards install
fi

# Build options
BUILD_FLAGS="--release"

if [ "$1" == "--static" ]; then
    echo "Building static binary..."
    BUILD_FLAGS="$BUILD_FLAGS --static"
fi

if [ "$1" == "--debug" ]; then
    echo "Building debug binary..."
    BUILD_FLAGS=""
fi

mkdir -p bin

crystal build src/admin.cr -o bin/kemal-waf-admin $BUILD_FLAGS

echo -e "${GREEN}✅ Backend built successfully${NC}"
echo -e "${GREEN}✅ Binary: admin/bin/kemal-waf-admin${NC}"
echo ""
echo -e "To run: ${YELLOW}cd admin && ./bin/kemal-waf-admin${NC}"
echo -e "Or use: ${YELLOW}make admin-run${NC}"

