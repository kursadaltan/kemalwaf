# GitHub Wiki Setup Guide

Bu rehber, kemal-waf dokümantasyonunu GitHub Wiki'de yayınlamak için adımları içerir.

## GitHub Wiki Nedir?

GitHub Wiki, projeniz için ayrı bir dokümantasyon alanı sağlar. Wiki'ler ayrı bir Git repository olarak çalışır ve GitHub Pages'ten farklıdır.

## Wiki'yi Aktifleştirme

1. GitHub repo'nuzda **Settings** sekmesine gidin
2. **Features** bölümünde **Wikis** seçeneğini bulun
3. **Wikis** checkbox'ını işaretleyin
4. **Save** butonuna tıklayın

## Wiki Repository'sini Clone Etme

Wiki aktifleştirildikten sonra, wiki repository'sini clone edebilirsiniz:

```bash
# Wiki repository URL'i genellikle şu formattadır:
# https://github.com/kursadaltan/kemalwaf.wiki.git

git clone https://github.com/kursadaltan/kemalwaf.wiki.git
cd kemalwaf.wiki
```

## Dokümantasyon Dosyalarını Wiki'ye Kopyalama

### Otomatik Kopyalama Scripti

```bash
#!/bin/bash
# copy-docs-to-wiki.sh

# Wiki repository'sini clone et (eğer yoksa)
if [ ! -d "kemalwaf.wiki" ]; then
    git clone https://github.com/kursadaltan/kemalwaf.wiki.git
fi

# Ana repo'dan wiki'ye kopyala
cp docs/*.md kemalwaf.wiki/

# Wiki repository'sine git
cd kemalwaf.wiki

# Değişiklikleri commit et
git add .
git commit -m "Update documentation from main repo"
git push origin master

echo "Documentation copied to wiki successfully!"
```

### Manuel Kopyalama

```bash
# Ana repo'dan wiki klasörüne
cp docs/installation.md kemalwaf.wiki/Installation.md
cp docs/configuration.md kemalwaf.wiki/Configuration.md
cp docs/rules.md kemalwaf.wiki/Rules.md
cp docs/deployment.md kemalwaf.wiki/Deployment.md
cp docs/nginx-setup.md kemalwaf.wiki/Nginx-Setup.md
cp docs/tls-https.md kemalwaf.wiki/TLS-HTTPS.md
cp docs/api.md kemalwaf.wiki/API-Reference.md
cp docs/environment-variables.md kemalwaf.wiki/Environment-Variables.md
cp docs/geoip.md kemalwaf.wiki/GeoIP-Filtering.md

# Home page oluştur
cp docs/README.md kemalwaf.wiki/Home.md
```

## Wiki Home Page

Wiki'nin ana sayfası `Home.md` dosyasıdır. Örnek bir Home.md:

```markdown
# kemal-waf Documentation

Welcome to kemal-waf documentation!

## Quick Start

- [Installation](Installation)
- [Configuration](Configuration)
- [Quick Start Guide](Installation#quick-start-with-docker-compose)

## Core Documentation

### Setup & Configuration
- [Installation](Installation) - Installation methods
- [Configuration](Configuration) - WAF configuration
- [Environment Variables](Environment-Variables) - All environment variables
- [Rule Format](Rules) - How to write rules

### Security & TLS
- [TLS/HTTPS Setup](TLS-HTTPS) - SSL/TLS configuration
- [GeoIP Filtering](GeoIP-Filtering) - Country-based blocking

### Deployment
- [Deployment Guide](Deployment) - Production deployment
- [Nginx Setup](Nginx-Setup) - Reverse proxy configuration
- [API Reference](API-Reference) - API endpoints

## External Links

- [GitHub Repository](https://github.com/kursadaltan/kemalwaf)
- [GitHub Pages Documentation](https://kursadaltan.github.io/kemalwaf/)
- [Issues](https://github.com/kursadaltan/kemalwaf/issues)
```

## Wiki Link Formatı

Wiki'de sayfalar arası linkler için özel format kullanılır:

```markdown
# Köşeli parantez kullan (parantez içinde boşluk yerine tire)
[Installation](Installation)
[Configuration Guide](Configuration)

# Başlık linki
[Quick Start](Installation#quick-start-with-docker-compose)
```

## Wiki vs GitHub Pages

### GitHub Wiki
- ✅ GitHub içinde entegre
- ✅ Kolay düzenleme (web UI)
- ✅ Ayrı repository
- ❌ Özelleştirme sınırlı
- ❌ Custom domain yok

### GitHub Pages
- ✅ Tam kontrol (HTML/CSS/JS)
- ✅ Custom domain desteği
- ✅ SEO dostu
- ✅ Modern görünüm
- ❌ Daha fazla setup gerektirir

## Otomatik Senkronizasyon

Wiki'yi ana repo ile senkronize tutmak için GitHub Actions kullanabilirsiniz:

```yaml
# .github/workflows/sync-wiki.yml
name: Sync Docs to Wiki

on:
  push:
    paths:
      - 'docs/**'
    branches:
      - main

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Clone Wiki
        run: |
          git clone https://github.com/kursadaltan/kemalwaf.wiki.git wiki
          
      - name: Copy Docs
        run: |
          cp docs/*.md wiki/
          cp docs/README.md wiki/Home.md
          
      - name: Commit and Push
        run: |
          cd wiki
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add .
          git diff --quiet && git diff --staged --quiet || (git commit -m "Auto-sync docs from main repo" && git push)
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Not:** Bu workflow için `GITHUB_TOKEN`'ın wiki repository'sine yazma izni olması gerekir.

## Wiki'yi Güncelleme

Wiki'yi güncellemek için:

```bash
cd kemalwaf.wiki
git pull origin master  # Son değişiklikleri al
# Dosyaları düzenle
git add .
git commit -m "Update documentation"
git push origin master
```

## Wiki Erişimi

Wiki'ye erişmek için:
- GitHub repo sayfasında **Wiki** sekmesine tıklayın
- Veya direkt URL: `https://github.com/kursadaltan/kemalwaf/wiki`

## İpuçları

1. **Dosya İsimleri:** Wiki'de dosya isimleri boşluk içerebilir, ancak linklerde tire kullanın
2. **Home Page:** `Home.md` veya `_Sidebar.md` dosyası wiki'nin ana sayfasıdır
3. **Sidebar:** `_Sidebar.md` dosyası ile özel sidebar oluşturabilirsiniz
4. **Footer:** `_Footer.md` dosyası ile footer ekleyebilirsiniz

## Örnek _Sidebar.md

```markdown
## Getting Started
- [[Home]]
- [[Installation]]
- [[Configuration]]

## Guides
- [[Rules]]
- [[Deployment]]
- [[Nginx-Setup]]

## Reference
- [[API-Reference]]
- [[Environment-Variables]]
- [[GeoIP-Filtering]]
```

## Sorun Giderme

### Wiki Görünmüyor
- Settings'te Wiki'nin aktif olduğundan emin olun
- Wiki repository'sinin clone edildiğini kontrol edin

### Linkler Çalışmıyor
- Wiki link formatını kullandığınızdan emin olun
- Dosya isimlerinin doğru olduğunu kontrol edin

### Push Hatası
- Wiki repository'sine yazma izniniz olduğundan emin olun
- Personal access token kullanmanız gerekebilir

