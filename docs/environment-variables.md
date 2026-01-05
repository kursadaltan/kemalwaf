# Environment Variables - kemal-korur WAF

Bu doküman, kemal-korur WAF için kullanılabilen tüm environment variable'ları içerir.

## 📋 Hızlı Referans

### Temel Konfigürasyon
- `RULE_DIR` - Kural dosyalarının bulunduğu dizin
- `UPSTREAM` - Upstream backend URL'i
- `UPSTREAM_HOST_HEADER` - Upstream için özel Host header
- `PRESERVE_ORIGINAL_HOST` - Orijinal Host header'ını koru
- `OBSERVE` - Gözlem modu (engelleme yapmadan loglama)
- `BODY_LIMIT_BYTES` - İstek gövdesi boyut limiti
- `RELOAD_INTERVAL_SEC` - Kural yeniden yükleme aralığı

### Logging
- `LOG_DIR` - Log dosyalarının dizini
- `LOG_MAX_SIZE_MB` - Log dosyası maksimum boyutu
- `LOG_RETENTION_DAYS` - Log saklama süresi
- `AUDIT_LOG_MAX_SIZE_MB` - Audit log maksimum boyutu
- `AUDIT_LOG_RETENTION_DAYS` - Audit log saklama süresi
- `LOG_ENABLE_AUDIT` - Audit log'u etkinleştir
- `LOG_QUEUE_SIZE` - Log queue boyutu
- `LOG_BATCH_SIZE` - Log batch boyutu
- `LOG_FLUSH_INTERVAL_MS` - Log flush aralığı

### Rate Limiting
- `RATE_LIMIT_ENABLED` - Rate limiting'i etkinleştir
- `RATE_LIMIT_DEFAULT` - Varsayılan rate limit
- `RATE_LIMIT_WINDOW_SEC` - Rate limit pencere süresi
- `RATE_LIMIT_BLOCK_DURATION_SEC` - IP bloklama süresi

### IP Filtering
- `IP_FILTER_ENABLED` - IP filtering'i etkinleştir
- `IP_WHITELIST_FILE` - IP whitelist dosyası yolu
- `IP_BLACKLIST_FILE` - IP blacklist dosyası yolu

### GeoIP Filtering
- `GEOIP_ENABLED` - GeoIP filtering'i etkinleştir
- `GEOIP_MMDB_FILE` - MMDB dosyası yolu (ZORUNLU)
- `GEOIP_BLOCKED_COUNTRIES` - Engellenecek ülkeler
- `GEOIP_ALLOWED_COUNTRIES` - İzin verilecek ülkeler

---

## 📝 Detaylı Açıklamalar

### Temel Konfigürasyon

#### `RULE_DIR`
- **Açıklama:** WAF kurallarının bulunduğu dizin
- **Varsayılan:** `rules`
- **Örnek:** `export RULE_DIR=/etc/kemal-waf/rules`

#### `UPSTREAM`
- **Açıklama:** İsteklerin yönlendirileceği backend URL
- **Varsayılan:** `http://localhost:8080`
- **Örnek:** `export UPSTREAM=http://backend:8080`

#### `UPSTREAM_HOST_HEADER`
- **Açıklama:** Upstream'e gönderilecek özel Host header değeri
- **Varsayılan:** `""` (boş - upstream URI'den alınır)
- **Örnek:** `export UPSTREAM_HOST_HEADER=api.example.com`

#### `PRESERVE_ORIGINAL_HOST`
- **Açıklama:** Orijinal request'teki Host header'ını koru
- **Varsayılan:** `false`
- **Değerler:** `true` veya `false`
- **Örnek:** `export PRESERVE_ORIGINAL_HOST=true`

#### `OBSERVE`
- **Açıklama:** Gözlem modu - kuralları test etmek için engelleme yapmadan loglama
- **Varsayılan:** `false`
- **Değerler:** `true` veya `false`
- **Örnek:** `export OBSERVE=true`

#### `BODY_LIMIT_BYTES`
- **Açıklama:** İstek gövdesi için maksimum boyut (byte)
- **Varsayılan:** `1048576` (1 MB)
- **Örnek:** `export BODY_LIMIT_BYTES=2097152` (2 MB)

#### `RELOAD_INTERVAL_SEC`
- **Açıklama:** Kural dosyalarını kontrol etme ve yeniden yükleme aralığı (saniye)
- **Varsayılan:** `5`
- **Örnek:** `export RELOAD_INTERVAL_SEC=10`

---

### Logging Konfigürasyonu

#### `LOG_DIR`
- **Açıklama:** Log dosyalarının yazılacağı dizin
- **Varsayılan:** `logs`
- **Örnek:** `export LOG_DIR=/var/log/kemal-waf`

#### `LOG_MAX_SIZE_MB`
- **Açıklama:** Log dosyası maksimum boyutu (MB)
- **Varsayılan:** `100`
- **Örnek:** `export LOG_MAX_SIZE_MB=200`

#### `LOG_RETENTION_DAYS`
- **Açıklama:** Log dosyalarının saklanacağı süre (gün)
- **Varsayılan:** `30`
- **Örnek:** `export LOG_RETENTION_DAYS=90`

#### `AUDIT_LOG_MAX_SIZE_MB`
- **Açıklama:** Audit log dosyası maksimum boyutu (MB)
- **Varsayılan:** `50`
- **Örnek:** `export AUDIT_LOG_MAX_SIZE_MB=100`

#### `AUDIT_LOG_RETENTION_DAYS`
- **Açıklama:** Audit log dosyalarının saklanacağı süre (gün)
- **Varsayılan:** `90`
- **Örnek:** `export AUDIT_LOG_RETENTION_DAYS=180`

#### `LOG_ENABLE_AUDIT`
- **Açıklama:** Audit log'u etkinleştir
- **Varsayılan:** `true`
- **Değerler:** `true` veya `false`
- **Örnek:** `export LOG_ENABLE_AUDIT=true`

#### `LOG_QUEUE_SIZE`
- **Açıklama:** Asenkron log queue boyutu
- **Varsayılan:** `10000`
- **Örnek:** `export LOG_QUEUE_SIZE=20000`

#### `LOG_BATCH_SIZE`
- **Açıklama:** Log batch boyutu (kaç log bir arada yazılacak)
- **Varsayılan:** `100`
- **Örnek:** `export LOG_BATCH_SIZE=200`

#### `LOG_FLUSH_INTERVAL_MS`
- **Açıklama:** Log flush aralığı (milisaniye)
- **Varsayılan:** `1000` (1 saniye)
- **Örnek:** `export LOG_FLUSH_INTERVAL_MS=500`

---

### Rate Limiting

#### `RATE_LIMIT_ENABLED`
- **Açıklama:** Rate limiting'i etkinleştir
- **Varsayılan:** `true`
- **Değerler:** `true` veya `false`
- **Örnek:** `export RATE_LIMIT_ENABLED=true`

#### `RATE_LIMIT_DEFAULT`
- **Açıklama:** Varsayılan rate limit (istek sayısı)
- **Varsayılan:** `100`
- **Örnek:** `export RATE_LIMIT_DEFAULT=200`

#### `RATE_LIMIT_WINDOW_SEC`
- **Açıklama:** Rate limit pencere süresi (saniye)
- **Varsayılan:** `60` (1 dakika)
- **Örnek:** `export RATE_LIMIT_WINDOW_SEC=120` (2 dakika)

#### `RATE_LIMIT_BLOCK_DURATION_SEC`
- **Açıklama:** Rate limit aşıldığında IP'nin bloklanacağı süre (saniye)
- **Varsayılan:** `300` (5 dakika)
- **Örnek:** `export RATE_LIMIT_BLOCK_DURATION_SEC=600` (10 dakika)

---

### IP Filtering

#### `IP_FILTER_ENABLED`
- **Açıklama:** IP filtering'i etkinleştir
- **Varsayılan:** `true`
- **Değerler:** `true` veya `false`
- **Örnek:** `export IP_FILTER_ENABLED=true`

#### `IP_WHITELIST_FILE`
- **Açıklama:** IP whitelist dosyası yolu (her satırda bir IP veya CIDR)
- **Varsayılan:** `""` (boş)
- **Örnek:** `export IP_WHITELIST_FILE=config/ip_whitelist.txt`

#### `IP_BLACKLIST_FILE`
- **Açıklama:** IP blacklist dosyası yolu (her satırda bir IP veya CIDR)
- **Varsayılan:** `""` (boş)
- **Örnek:** `export IP_BLACKLIST_FILE=config/ip_blacklist.txt`

**IP List Dosya Formatı:**
```
# Yorum satırları # ile başlar
192.168.1.100
10.0.0.0/24
# IPv6 desteği
2001:db8::/32
```

---

### GeoIP Filtering

#### `GEOIP_ENABLED`
- **Açıklama:** GeoIP filtering'i etkinleştir
- **Varsayılan:** `false`
- **Değerler:** `true` veya `false`
- **Örnek:** `export GEOIP_ENABLED=true`

#### `GEOIP_MMDB_FILE`
- **Açıklama:** MaxMind MMDB dosyası yolu (ZORUNLU - GeoIP için MMDB dosyası gerekli)
- **Varsayılan:** `""` (boş)
- **Örnek:** `export GEOIP_MMDB_FILE=data/GeoLite2-Country.mmdb`
- **Not:** `mmdblookup` aracı gerektirir (`brew install libmaxminddb`)
- **Not:** MMDB dosyası yoksa GeoIP çalışmaz

#### `GEOIP_BLOCKED_COUNTRIES`
- **Açıklama:** Engellenecek ülkeler (ISO 3166-1 alpha-2 kodları, virgülle ayrılmış)
- **Varsayılan:** `""` (boş)
- **Örnek:** `export GEOIP_BLOCKED_COUNTRIES=CN,RU,KP`

#### `GEOIP_ALLOWED_COUNTRIES`
- **Açıklama:** İzin verilecek ülkeler - whitelist (sadece bu ülkelerden erişim)
- **Varsayılan:** `""` (boş)
- **Örnek:** `export GEOIP_ALLOWED_COUNTRIES=US,GB,DE,FR`
- **Not:** Allowed countries ayarlanırsa, sadece bu ülkelerden erişim izin verilir

**GeoIP Gereksinimleri:**
- MMDB dosyası (GeoLite2 veya GeoIP2)
- `mmdblookup` komut satırı aracı (`brew install libmaxminddb`)

---

## 🚀 Örnek Konfigürasyonlar

### Minimal Konfigürasyon
```bash
export UPSTREAM=http://backend:8080
./bin/kemal-waf
```

### Production Konfigürasyonu
```bash
# Temel
export UPSTREAM=http://backend:8080
export RULE_DIR=/etc/kemal-waf/rules
export OBSERVE=false

# Logging
export LOG_DIR=/var/log/kemal-waf
export LOG_RETENTION_DAYS=90
export AUDIT_LOG_RETENTION_DAYS=180

# Rate Limiting
export RATE_LIMIT_ENABLED=true
export RATE_LIMIT_DEFAULT=200
export RATE_LIMIT_WINDOW_SEC=60

# IP Filtering
export IP_FILTER_ENABLED=true
export IP_WHITELIST_FILE=/etc/kemal-waf/whitelist.txt
export IP_BLACKLIST_FILE=/etc/kemal-waf/blacklist.txt

# GeoIP
export GEOIP_ENABLED=true
export GEOIP_MMDB_FILE=/etc/kemal-waf/GeoLite2-Country.mmdb
export GEOIP_BLOCKED_COUNTRIES=CN,RU,KP

./bin/kemal-waf
```

### Test/Development Konfigürasyonu
```bash
export UPSTREAM=http://localhost:8080
export OBSERVE=true
export LOG_DIR=logs
export RATE_LIMIT_ENABLED=false
export IP_FILTER_ENABLED=false
export GEOIP_ENABLED=false

./bin/kemal-waf
```

### Yüksek Güvenlik Konfigürasyonu
```bash
# Strict IP filtering
export IP_FILTER_ENABLED=true
export IP_WHITELIST_FILE=/etc/kemal-waf/whitelist.txt

# GeoIP whitelist (sadece belirli ülkeler)
export GEOIP_ENABLED=true
export GEOIP_MMDB_FILE=/etc/kemal-waf/GeoLite2-Country.mmdb
export GEOIP_ALLOWED_COUNTRIES=US,GB,DE,FR,TR

# Strict rate limiting
export RATE_LIMIT_ENABLED=true
export RATE_LIMIT_DEFAULT=50
export RATE_LIMIT_WINDOW_SEC=60
export RATE_LIMIT_BLOCK_DURATION_SEC=600

# Extended logging
export LOG_RETENTION_DAYS=180
export AUDIT_LOG_RETENTION_DAYS=365

./bin/kemal-waf
```

---

## 📊 Öncelik Sırası

WAF istekleri şu sırayla kontrol eder:

1. **IP Whitelist** (en yüksek öncelik - direkt izin)
2. **IP Blacklist** (direkt engelleme)
3. **GeoIP Allowed Countries** (whitelist)
4. **GeoIP Blocked Countries** (blacklist)
5. **Rate Limiting** (istek sayısı kontrolü)
6. **WAF Rules** (OWASP CRS kuralları)

---

## 🔍 Environment Variable Kontrolü

Tüm environment variable'ları kontrol etmek için:

```bash
# WAF başlatıldığında log'larda görünecek
./bin/kemal-waf

# Veya manuel kontrol
env | grep -E "(RULE_DIR|UPSTREAM|GEOIP|IP_FILTER|RATE_LIMIT|LOG_)"
```

---

## 📝 Notlar

- Tüm boolean değerler: `true` veya `false` (string olarak)
- Sayısal değerler: integer olarak
- Dosya yolları: absolute veya relative path
- Ülke kodları: ISO 3166-1 alpha-2 formatında (örn: `US`, `TR`, `GB`)
- Environment variable'lar WAF başlatıldığında okunur, runtime'da değiştirilemez
- Hot-reload sadece kural dosyaları için geçerlidir

---

**Son Güncelleme:** 2025-11-11

