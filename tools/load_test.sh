#!/bin/bash
# WAF Load Test Script - kemal-korur
# Vegeta ile yük testi (ana araç) + diğer araçlar

set -e

WAF_URL="${WAF_URL:-http://localhost:3000}"
WAF_HOST="${WAF_HOST:-localhost}"
TEST_DURATION="${TEST_DURATION:-30s}"
RATE="${RATE:-100}"
TIMEOUT="${TIMEOUT:-5s}"
TARGETS_FILE="${TARGETS_FILE:-/tmp/vegeta_targets.txt}"

# IPv4 zorla (IPv6 connection refused hatalarını önlemek için)
# localhost yerine 127.0.0.1 kullan
WAF_URL_IPV4=$(echo "$WAF_URL" | sed 's/localhost/127.0.0.1/g')

echo "🔥 WAF Load Test - kemal-korur (Vegeta)"
echo "========================================"
echo ""
echo "WAF URL: $WAF_URL (using IPv4: $WAF_URL_IPV4)"
echo "Test Duration: $TEST_DURATION"
echo "Rate: $RATE requests/sec"
echo "Timeout: $TIMEOUT"
echo ""

# Health check
echo "📋 Health Check..."
if ! curl -s -f "$WAF_URL/health" > /dev/null; then
    echo "❌ WAF is not responding at $WAF_URL"
    exit 1
fi
echo "✅ WAF is healthy"
echo ""

# Vegeta targets dosyası oluştur (IPv4 kullan)
cat > "$TARGETS_FILE" << EOF
GET $WAF_URL_IPV4/?test=normal
GET $WAF_URL_IPV4/?page=home&user=test
GET $WAF_URL_IPV4/?search=hello+world
EOF

# Test 1: Vegeta - Normal istekler
if command -v vegeta &> /dev/null; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Test 1: Vegeta - Normal Requests"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "GET $WAF_URL_IPV4/?test=normal" | vegeta attack -rate=$RATE -duration=$TEST_DURATION -timeout=$TIMEOUT -header="Host:$WAF_HOST" | vegeta report
    echo ""
    
    # Detaylı histogram
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Test 1b: Vegeta - Latency Histogram"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "GET $WAF_URL_IPV4/?test=normal" | vegeta attack -rate=$RATE -duration=$TEST_DURATION -timeout=$TIMEOUT -header="Host:$WAF_HOST" | vegeta report -type=hist[0,2ms,5ms,10ms,20ms,50ms,100ms,200ms,500ms]
    echo ""
    
    # JSON output (opsiyonel)
    if [ "${VEGETA_JSON:-false}" = "true" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📊 Test 1c: Vegeta - JSON Output (saved to /tmp/vegeta_results.json)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "GET $WAF_URL_IPV4/?test=normal" | vegeta attack -rate=$RATE -duration=$TEST_DURATION -timeout=$TIMEOUT -header="Host:$WAF_HOST" | vegeta encode > /tmp/vegeta_results.bin
        vegeta report -type=json < /tmp/vegeta_results.bin > /tmp/vegeta_results.json
        echo "✅ Results saved to /tmp/vegeta_results.json"
        echo ""
    fi
else
    echo "⚠️  Vegeta not found. Install with: brew install vegeta"
    echo ""
fi

# Test 2: Vegeta - Saldırı payload'ları ile (WAF blocking test)
if command -v vegeta &> /dev/null; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Test 2: Vegeta - Attack Payloads (WAF Blocking Test)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # SQL Injection payload
    echo "GET $WAF_URL_IPV4/?id=1%27%20OR%20%271%27%3D%271" | vegeta attack -rate=50 -duration=10s -timeout=$TIMEOUT -header="Host:$WAF_HOST" | vegeta report
    echo ""
    
    # XSS payload
    echo "GET $WAF_URL_IPV4/?q=%3Cscript%3Ealert(1)%3C/script%3E" | vegeta attack -rate=50 -duration=10s -timeout=$TIMEOUT -header="Host:$WAF_HOST" | vegeta report
    echo ""
fi

# Test 3: Vegeta - Karışık yük (normal + saldırı)
if command -v vegeta &> /dev/null && [ -f "$TARGETS_FILE" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Test 3: Vegeta - Mixed Load (from targets file)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    vegeta attack -rate=$RATE -duration=$TEST_DURATION -timeout=$TIMEOUT -targets="$TARGETS_FILE" -header="Host:$WAF_HOST" | vegeta report
    echo ""
fi

# Test 4: wrk - Karşılaştırma için (opsiyonel)
if command -v wrk &> /dev/null && [ "${RUN_WRK:-false}" = "true" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Test 4: wrk (Comparison)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    wrk -t4 -c50 -d$TEST_DURATION --latency "$WAF_URL_IPV4/?test=normal" -H "Host:$WAF_HOST"
    echo ""
fi

# Metrics summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 WAF Metrics Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s "$WAF_URL/metrics" | grep -E "(waf_requests_total|waf_blocked_total|waf_rules_loaded|waf_observed_total)" | head -6
echo ""

echo "✅ Load test completed!"
echo ""
echo "💡 Tips:"
echo "  - JSON output için: VEGETA_JSON=true ./tools/load_test.sh"
echo "  - Düşük yük testi: RATE=50 TEST_DURATION=30s ./tools/load_test.sh"
echo "  - Orta yük testi: RATE=100 TEST_DURATION=30s ./tools/load_test.sh"
echo "  - Yüksek yük testi: RATE=200 TEST_DURATION=60s ./tools/load_test.sh"
echo "  - Timeout ayarla: TIMEOUT=10s RATE=100 ./tools/load_test.sh"
echo "  - wrk karşılaştırması: RUN_WRK=true ./tools/load_test.sh"
echo ""
echo "⚠️  Not: 500 req/s çok yüksek, connection hatalarına neden olabilir!"
echo "   Başlangıç için 50-100 req/s önerilir."

