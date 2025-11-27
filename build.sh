#!/bin/bash
# macOS için build script

set -e

echo "🔨 kemal-korur Build Script"
echo "============================"
echo ""

# Crystal'in yüklü olup olmadığını kontrol et
if ! command -v crystal &> /dev/null; then
    echo "❌ Crystal bulunamadı!"
    echo ""
    echo "Crystal'i yüklemek için:"
    echo "  brew install crystal"
    echo ""
    exit 1
fi

CRYSTAL_VERSION=$(crystal --version | head -1 | awk '{print $2}')
echo "✅ Crystal versiyonu: $CRYSTAL_VERSION"
echo ""

# Shards yüklü mü kontrol et
if ! command -v shards &> /dev/null; then
    echo "❌ Shards bulunamadı!"
    echo "Crystal ile birlikte gelmeli. Lütfen Crystal'i yeniden yükleyin."
    exit 1
fi

echo "📦 Bağımlılıkları yüklüyorum..."
shards install

# LibInjection kontrolü
LIBINJECTION_FOUND=false
LIBINJECTION_FLAGS=""

if [ -f "lib/libinjection/libinjection.a" ]; then
    echo "✅ LibInjection static library bulundu (lib/libinjection/libinjection.a)"
    LIBINJECTION_FOUND=true
    LIBINJECTION_FLAGS="-L./lib/libinjection -linjection"
elif pkg-config --exists libinjection 2>/dev/null; then
    echo "✅ LibInjection sistem kütüphanesi bulundu"
    LIBINJECTION_FOUND=true
    LIBINJECTION_FLAGS=$(pkg-config --libs --cflags libinjection)
elif [ -f "/usr/local/lib/libinjection.a" ] || [ -f "/usr/local/lib/libinjection.dylib" ]; then
    echo "✅ LibInjection /usr/local/lib'de bulundu"
    LIBINJECTION_FOUND=true
    LIBINJECTION_FLAGS="-L/usr/local/lib -linjection"
else
    echo "⚠️  LibInjection bulunamadı!"
    echo ""
    echo "LibInjection olmadan build devam edecek, ancak libinjection_sqli"
    echo "ve libinjection_xss operator'ları çalışmayacak!"
    echo ""
    echo "LibInjection'ı eklemek için:"
    echo "  1. lib/libinjection/libinjection.a dosyasının mevcut olduğundan emin olun"
    echo "  2. Veya sistem kütüphanesi olarak kurun"
    echo ""
fi

echo ""
echo "📁 bin dizinini oluşturuyorum..."
mkdir -p bin

echo ""
echo "🔨 Uygulamayı derliyorum..."

# LibInjection varsa link et
if [ "$LIBINJECTION_FOUND" = true ]; then
    # Absolute path kullan
    ABS_LIB_PATH="$(cd "$(dirname "$0")" && pwd)/lib/libinjection"
    crystal build --release --no-debug --link-flags "-L$ABS_LIB_PATH -linjection" src/waf.cr -o bin/kemal-waf
else
    crystal build --release --no-debug src/waf.cr -o bin/kemal-waf
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build başarılı!"
    echo "📦 Binary: bin/kemal-waf"
    echo ""
    ls -lh bin/kemal-waf
    echo ""
    echo "🚀 Çalıştırmak için: ./run.sh"
else
    echo ""
    echo "❌ Build başarısız!"
    exit 1
fi

