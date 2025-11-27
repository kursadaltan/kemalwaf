#!/bin/bash
# kemal-waf setup script
# This script prepares the necessary files to run kemal-waf

set -e

echo "🚀 kemal-waf Setup Script"
echo "========================="
echo ""

# GitHub repo URL
REPO_URL="https://github.com/kursadaltan/kemalwaf"
REPO_RAW="https://raw.githubusercontent.com/kursadaltan/kemalwaf/main"

# Create rules directory
echo "📁 Creating rules directory..."
mkdir -p rules

# Create config directory
echo "📁 Creating config directory..."
mkdir -p config

# Download rules from GitHub
echo "📥 Downloading rules files from GitHub..."
if command -v git &> /dev/null; then
    # If git is available, clone temporarily and copy rules
    TEMP_DIR=$(mktemp -d)
    git clone --depth 1 --filter=blob:none --sparse $REPO_URL $TEMP_DIR 2>/dev/null || {
        # If git clone fails, download with curl
        echo "   Git clone failed, using alternative method..."
        curl -L "${REPO_URL}/archive/main.zip" -o /tmp/kemalwaf.zip 2>/dev/null || {
            echo "❌ Failed to download rules files. Please check your internet connection."
            exit 1
        }
        unzip -q /tmp/kemalwaf.zip -d /tmp/ 2>/dev/null || {
            echo "❌ Failed to extract ZIP file."
            exit 1
        }
        cp -r /tmp/kemalwaf-main/rules/* rules/ 2>/dev/null || {
            echo "⚠️  Some rules files could not be copied, continuing..."
        }
        rm -rf /tmp/kemalwaf.zip /tmp/kemalwaf-main
    }
    
    if [ -d "$TEMP_DIR" ] && [ -d "$TEMP_DIR/rules" ]; then
        git -C $TEMP_DIR sparse-checkout set rules 2>/dev/null || true
        cp -r $TEMP_DIR/rules/* rules/ 2>/dev/null || {
            echo "⚠️  Some rules files could not be copied, continuing..."
        }
        rm -rf $TEMP_DIR
    fi
else
    # If git is not available, download ZIP with curl
    echo "   Git not found, downloading ZIP file..."
    curl -L "${REPO_URL}/archive/main.zip" -o /tmp/kemalwaf.zip 2>/dev/null || {
        echo "❌ Failed to download rules files. Please check your internet connection."
        exit 1
    }
    unzip -q /tmp/kemalwaf.zip -d /tmp/ 2>/dev/null || {
        echo "❌ Failed to extract ZIP file."
        exit 1
    }
    cp -r /tmp/kemalwaf-main/rules/* rules/ 2>/dev/null || {
        echo "⚠️  Some rules files could not be copied, continuing..."
    }
    rm -rf /tmp/kemalwaf.zip /tmp/kemalwaf-main
fi

# Copy config example (if it doesn't exist)
if [ ! -f config/waf.yml ]; then
    echo "📋 Creating config file example..."
    curl -L "${REPO_RAW}/config/waf.yml.example" -o config/waf.yml.example 2>/dev/null || {
        echo "⚠️  Config example could not be downloaded, creating empty config file..."
        cat > config/waf.yml << 'EOF'
# Kemal WAF Configuration File
waf:
  mode: enforce
  upstream:
    url: http://localhost:8080
    timeout: 30s
    retry: 3
  rules:
    directory: rules/
    reload_interval: 5s
EOF
    }
    
    if [ -f config/waf.yml.example ]; then
        cp config/waf.yml.example config/waf.yml
        echo "⚠️  Don't forget to edit config/waf.yml file!"
    fi
else
    echo "✅ config/waf.yml already exists, skipping..."
fi

# Copy IP whitelist/blacklist examples
if [ ! -f config/ip_whitelist.txt ]; then
    echo "📋 Creating IP whitelist example..."
    curl -L "${REPO_RAW}/config/ip_whitelist.txt.example" -o config/ip_whitelist.txt.example 2>/dev/null || true
    if [ -f config/ip_whitelist.txt.example ]; then
        cp config/ip_whitelist.txt.example config/ip_whitelist.txt
    fi
fi

if [ ! -f config/ip_blacklist.txt ]; then
    echo "📋 Creating IP blacklist example..."
    curl -L "${REPO_RAW}/config/ip_blacklist.txt.example" -o config/ip_blacklist.txt.example 2>/dev/null || true
    if [ -f config/ip_blacklist.txt.example ]; then
        cp config/ip_blacklist.txt.example config/ip_blacklist.txt
    fi
fi

echo ""
echo "✅ Setup completed!"
echo ""
echo "📁 Created files:"
echo "   - rules/ (WAF rules)"
echo "   - config/waf.yml (WAF configuration)"
echo ""
echo "🚀 To run:"
echo ""
echo "   # Minimal run (with default rules - without volume mount)"
echo "   docker run -d \\"
echo "     -p 3030:3030 \\"
echo "     -v \$(pwd)/config/waf.yml:/app/config/waf.yml:ro \\"
echo "     kursadaltan/kemalwaf:latest"
echo ""
echo "   # Run with custom rules (with volume mount)"
echo "   docker run -d \\"
echo "     -p 3030:3030 \\"
echo "     -v \$(pwd)/config/waf.yml:/app/config/waf.yml:ro \\"
echo "     -v \$(pwd)/rules:/app/rules:ro \\"
echo "     kursadaltan/kemalwaf:latest"
echo ""

