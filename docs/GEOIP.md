# GeoIP Filtering - MaxMind MMDB Entegrasyonu

WAF, MaxMind MMDB dosyası ile ülke bazlı erişim kontrolü sağlar.

## Özellikler

- **MaxMind MMDB dosyası** desteği (GeoLite2 veya GeoIP2)
- **Ülke bazlı engelleme** (blocked countries)
- **Ülke bazlı izin verme** (allowed countries - whitelist)
- **Cache mekanizması** (1 saat TTL, otomatik cleanup)
- **Thread-safe** implementasyon
- **Yerel dosya okuma** (hızlı, rate limit yok, internet gerektirmez)

## Konfigürasyon

### Environment Variables

```bash
# GeoIP'i etkinleştir
export GEOIP_ENABLED=true

# MMDB dosyası yolu (ÖNERİLEN - en hızlı, rate limit yok)
export GEOIP_MMDB_FILE=/path/to/GeoLite2-Country.mmdb

# Engellenecek ülkeler (ISO 3166-1 alpha-2 kodları, virgülle ayrılmış)
export GEOIP_BLOCKED_COUNTRIES=CN,RU,KP

# İzin verilecek ülkeler (whitelist - sadece bu ülkelerden erişim)
export GEOIP_ALLOWED_COUNTRIES=US,GB,DE,FR
```

### MMDB Dosyası Kurulumu

1. **MMDB dosyasını indirin:**
   - MaxMind GeoLite2: https://dev.maxmind.com/geoip/geoip2/geolite2/
   - Veya internetten ücretsiz MMDB dosyaları bulabilirsiniz

2. **mmdblookup aracını yükleyin:**
   ```bash
   # macOS
   brew install libmaxminddb
   
   # Ubuntu/Debian
   sudo apt-get install mmdb-bin
   
   # veya MaxMind'in resmi installer'ını kullanın
   # https://github.com/maxmind/libmaxminddb
   ```

3. **MMDB dosyasını projeye kopyalayın:**
   ```bash
   mkdir -p data
   cp /path/to/GeoLite2-Country.mmdb data/
   ```

4. **Environment variable'ı ayarlayın:**
   ```bash
   export GEOIP_MMDB_FILE=data/GeoLite2-Country.mmdb
   ```

### Kullanım Örnekleri

#### 1. MMDB Dosyası ile Kullanım (ÖNERİLEN)

```bash
# MMDB dosyasını indirip ayarla
export GEOIP_ENABLED=true
export GEOIP_MMDB_FILE=data/GeoLite2-Country.mmdb
export GEOIP_BLOCKED_COUNTRIES=CN,RU,KP

./bin/kemal-waf
```

**Avantajları:**
- ✅ En hızlı (yerel dosya okuma)
- ✅ Rate limit yok
- ✅ İnternet bağlantısı gerektirmez
- ✅ Ücretsiz (GeoLite2)

#### 2. Belirli Ülkeleri Engelleme (MMDB ile)

```bash
export GEOIP_ENABLED=true
export GEOIP_MMDB_FILE=data/GeoLite2-Country.mmdb
export GEOIP_BLOCKED_COUNTRIES=CN,RU,KP

./bin/kemal-waf
```

Bu ayarla, Çin, Rusya ve Kuzey Kore'den gelen istekler engellenir.

#### 3. Sadece Belirli Ülkelerden İzin Verme (Whitelist)

```bash
export GEOIP_ENABLED=true
export GEOIP_MMDB_FILE=data/GeoLite2-Country.mmdb
export GEOIP_ALLOWED_COUNTRIES=US,GB,DE,FR

./bin/kemal-waf
```

Bu ayarla, sadece ABD, İngiltere, Almanya ve Fransa'dan gelen istekler kabul edilir.


## Öncelik Sırası

1. **IP Whitelist** (en yüksek öncelik)
2. **IP Blacklist**
3. **GeoIP Allowed Countries** (whitelist)
4. **GeoIP Blocked Countries** (blacklist)
5. **Rate Limiting**
6. **WAF Rules**

## Cache

GeoIP lookup sonuçları 1 saat süreyle cache'lenir. Bu sayede:
- Aynı IP için tekrar lookup yapılmaz
- API rate limit'leri korunur
- Performans artar

Cache otomatik olarak temizlenir (1 saatte bir).

## MMDB Dosyası

### Özellikler
- **Ücretsiz** (GeoLite2)
- **En hızlı** (yerel dosya okuma, ~5-20ms)
- **Rate limit yok**
- **İnternet bağlantısı gerektirmez**
- **Offline çalışır**
- `mmdblookup` komut satırı aracı gerektirir

### MMDB Dosyası İndirme
- **GeoLite2 (Ücretsiz):** https://dev.maxmind.com/geoip/geoip2/geolite2/
- **GeoIP2 (Ücretli):** MaxMind hesabından indirilebilir
- İnternetten ücretsiz MMDB dosyaları da bulunabilir

## Ülke Kodları

ISO 3166-1 alpha-2 formatında ülke kodları kullanılır:

- `US` - Amerika Birleşik Devletleri
- `GB` - Birleşik Krallık
- `DE` - Almanya
- `FR` - Fransa
- `CN` - Çin
- `RU` - Rusya
- `TR` - Türkiye
- vb.

Tüm ülke kodları: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2

## Logging

GeoIP engellemeleri structured log ve audit log'a yazılır:

```json
{
  "timestamp": "2025-11-11T12:00:00Z",
  "event_type": "waf_request",
  "client_ip": "1.2.3.4",
  "blocked": true,
  "rule_message": "GeoIP blocked: Country CN (China) is blocked",
  "source": "geoip"
}
```

## Performans

- **MMDB lookup**: ~5-20ms (yerel dosya okuma) ⚡
- **Cache hit**: ~0.1ms

**MMDB dosyası kullanımı çok hızlıdır!** Cache ile birlikte kullanıldığında performans daha da artar.

## Notlar

- MMDB dosyası yoksa veya `mmdblookup` aracı yüklü değilse, GeoIP lookup yapılamaz ve istek varsayılan olarak izin verilir
- Private IP'ler (192.168.x.x, 10.x.x.x, vb.) için GeoIP lookup yapılamaz
- MMDB dosyası güncel tutulmalıdır (aylık güncelleme önerilir)
- Cache kullanımı performansı önemli ölçüde artırır

