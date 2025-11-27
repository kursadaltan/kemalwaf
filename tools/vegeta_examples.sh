#!/bin/bash
# Vegeta Load Test Examples - kemal-korur WAF
# Hızlı referans için örnek komutlar

  echo "GET http://localhost:3000/echo" | \
  vegeta attack \
  -insecure \
  -header="Host: www.cloudapplicationsecurity.tr" \
  -header="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -header="Accept: application/json" \
  -header="Accept-Encoding: gzip, deflate, br" \
  -header="Connection: keepalive" \
  -header="Accept-Language: en-US,en;q=0.9" \
  -header="X-Forwarded-For: 185.230.16.100" \
  -duration=30s -rate=5 -keepalive=true -timeout=30s | \
  vegeta report


WAF_URL="${WAF_URL:-http://localhost:3000}"
WAF_HOST="${WAF_HOST:-www.cloudapplicationsecurity.tr}"

echo "🔥 Vegeta Load Test Examples - kemal-korur"
echo "==========================================="
echo ""

echo "📋 Basic Examples:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Basit yük testi (100 req/s, 30 saniye):"
echo "   echo 'GET $WAF_URL/?test=normal' | vegeta attack -header='Host:$WAF_HOST' -rate=100 -duration=30s | vegeta report"
echo ""
echo "2. Daha agresif test (500 req/s, 60 saniye):"
echo "   echo 'GET $WAF_URL/?test=normal' | vegeta attack -header='Host:$WAF_HOST' -rate=500 -duration=60s | vegeta report"
echo ""
echo "3. Latency histogram ile:"
echo "   echo 'GET $WAF_URL/?test=normal' | vegeta attack -header='Host:$WAF_HOST' -rate=100 -duration=30s | vegeta report -type=hist[0,2ms,5ms,10ms,20ms,50ms,100ms]"
echo ""
echo "4. JSON output (detaylı analiz için):"
echo "   echo 'GET $WAF_URL/?test=normal' | vegeta attack -header='Host:$WAF_HOST' -rate=100 -duration=30s | vegeta encode > results.bin"
echo "   vegeta report -type=json < results.bin > results.json"
echo ""

echo "📋 Attack Payload Tests:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "5. SQL Injection payload testi:"
echo "   echo 'GET $WAF_URL/?id=1%27%20OR%20%271%27%3D%271' | vegeta attack -header='Host:$WAF_HOST' -rate=50 -duration=10s | vegeta report"
echo ""
echo "6. XSS payload testi:"
echo "   echo 'GET $WAF_URL/?q=%3Cscript%3Ealert(1)%3C/script%3E' | vegeta attack -header='Host:$WAF_HOST' -rate=50 -duration=10s | vegeta report"
echo ""
echo "7. Path Traversal testi:"
echo "   echo 'GET $WAF_URL/?file=../../../etc/passwd' | vegeta attack -header='Host:$WAF_HOST' -rate=50 -duration=10s | vegeta report"
echo ""

echo "📋 Advanced Examples:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "8. Multiple targets (targets.txt dosyasından):"
echo "   cat > targets.txt << EOF"
echo "   GET $WAF_URL/?test=1"
echo "   GET $WAF_URL/?test=2"
echo "   GET $WAF_URL/?test=3"
echo "   EOF"
echo "   vegeta attack -header='Host:$WAF_HOST' -rate=100 -duration=30s -targets=targets.txt | vegeta report"
echo ""
echo "9. POST request testi:"
echo "   echo 'POST $WAF_URL/api/login' | vegeta attack -header='Host:$WAF_HOST' -rate=50 -duration=10s -body='{\"user\":\"test\"}' | vegeta report"
echo ""
echo "10. Custom headers ile:"
echo "    echo 'GET $WAF_URL/?test=normal' | vegeta attack -header='Host:$WAF_HOST' -rate=100 -duration=30s -header='User-Agent: TestBot' | vegeta report"
echo ""

echo "📋 Real-time Monitoring:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "11. Real-time plot (vegeta plot için):"
echo "    echo 'GET $WAF_URL/?test=normal' | vegeta attack -header='Host:$WAF_HOST' -rate=100 -duration=30s | vegeta encode > results.bin"
echo "    vegeta plot < results.bin > plot.html"
echo "    # plot.html dosyasını tarayıcıda aç"
echo ""
echo "12. Real-time report (her 1 saniyede bir):"
echo "    echo 'GET $WAF_URL/?test=normal' | vegeta attack -header='Host:$WAF_HOST' -rate=100 -duration=30s | vegeta report -every=1s"
echo ""

echo "📋 Status Code Analysis:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "13. Status code dağılımını görmek için:"
echo "    echo 'GET $WAF_URL/?test=normal' | vegeta attack -header='Host:$WAF_HOST' -rate=100 -duration=30s | vegeta report | grep -A 10 'Status'"
echo ""

echo "💡 Pro Tips:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  • Rate'i yavaşça artırın: 10 → 50 → 100 → 200 → 500"
echo "  • Duration'ı kısa tutarak başlayın: 10s → 30s → 60s"
echo "  • WAF metrics'i izleyin: watch -n 1 'curl -s $WAF_URL/metrics | grep waf_'"
echo "  • Sonuçları kaydedin: vegeta encode > results.bin (daha sonra analiz için)"
echo "  • Plot ile görselleştirin: vegeta plot < results.bin > plot.html"
echo ""

