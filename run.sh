#!/bin/bash
# macOS için run script

set -e

echo "🚀 kemal-korur Başlatılıyor..."
echo "=============================="
echo ""

# Binary var mı kontrol et
if [ ! -f "bin/kemal-waf" ]; then
    echo "❌ Binary bulunamadı: bin/kemal-waf"
    echo ""
    echo "Önce build alın:"
    echo "  ./build.sh"
    echo ""
    exit 1
fi

# .env dosyası var mı kontrol et
if [ ! -f ".env" ]; then
    echo "❌ .env dosyası bulunamadı!"
    echo ""
    echo "Önce .env dosyasını oluşturun:"
    echo "  cp .env.example .env"
    echo ""
    exit 1
fi

# .env dosyasını yükle ve export et
# Yorum satırlarını ve boş satırları atla, sadece KEY=VALUE formatındaki satırları al
while IFS= read -r line || [ -n "$line" ]; do
    # Yorum satırlarını ve boş satırları atla
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    # KEY=VALUE formatını kontrol et ve export et
    if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]// /}"
        value="${BASH_REMATCH[2]}"
        
        # Değerin sonundaki yorumları kaldır (# ile başlayan kısım)
        # Ama # işareti tırnak içindeyse koru
        if [[ "$value" =~ ^([^#]*)# ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        
        # Başındaki ve sonundaki boşlukları temizle
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        
        # Değerin başındaki ve sonundaki tırnak işaretlerini kaldır
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        
        export "$key=$value"
    fi
done < .env

# Rules dizini var mı kontrol et
if [ ! -d "$RULE_DIR" ]; then
    echo "⚠️  Uyarı: $RULE_DIR dizini bulunamadı!"
    echo ""
fi

# Environment variable'ları göster (debug için)
if [ "${DEBUG:-false}" = "true" ]; then
    echo "📋 Environment Variables:"
    echo "   UPSTREAM: ${UPSTREAM:-not set}"
    echo "   PRESERVE_ORIGINAL_HOST: ${PRESERVE_ORIGINAL_HOST:-not set}"
    echo "   OBSERVE: ${OBSERVE:-not set}"
    echo ""
fi

echo "🌐 WAF http://localhost:3000 adresinde başlatılıyor..."
echo "   Durdurmak için: Ctrl+C"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Binary'yi çalıştır (environment variable'lar otomatik aktarılır)
./bin/kemal-waf

