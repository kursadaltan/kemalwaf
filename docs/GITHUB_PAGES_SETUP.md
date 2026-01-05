# GitHub Pages Setup Guide

Bu rehber, kemal-waf dokümantasyonunu GitHub Pages'te yayınlamak için adımları içerir.

## GitHub Pages Nedir?

GitHub Pages, GitHub repository'lerinizden statik web siteleri yayınlamanıza olanak sağlar. `docs/` klasörünüzü kullanarak dokümantasyonunuzu otomatik olarak yayınlayabilirsiniz.

## Kurulum Adımları

### 1. Repository Settings

1. GitHub repo'nuzda **Settings** sekmesine gidin
2. Sol menüden **Pages** seçeneğine tıklayın
3. **Source** bölümünde:
   - **Branch:** `main` (veya `master`) seçin
   - **Folder:** `/docs` seçin
4. **Save** butonuna tıklayın

### 2. Dokümantasyon Klasörü

`docs/` klasörü zaten hazır! İçinde şu dosyalar var:
- `README.md` - Ana sayfa
- `installation.md`
- `configuration.md`
- `rules.md`
- `deployment.md`
- `nginx-setup.md`
- `tls-https.md`
- `api.md`
- `environment-variables.md`
- `geoip.md`

### 3. İlk Yayınlama

GitHub Pages genellikle birkaç dakika içinde aktif olur. Site şu adreste yayınlanır:

```
https://kursadaltan.github.io/kemalwaf/
```

**Not:** İlk yayınlama 5-10 dakika sürebilir.

## Dokümantasyon Yapısı

```
docs/
├── README.md (Ana sayfa - index)
├── installation.md
├── configuration.md
├── rules.md
├── deployment.md
├── nginx-setup.md
├── tls-https.md
├── api.md
├── environment-variables.md
├── geoip.md
└── ENTERPRISE_ROADMAP.md
```

## Markdown Link Formatı

GitHub Pages'te sayfalar arası linkler:

```markdown
[Installation Guide](installation.md)
[Configuration](configuration.md)
[Quick Start](installation.md#quick-start-with-docker-compose)
```

## Jekyll Yapılandırması (Opsiyonel)

GitHub Pages Jekyll kullanır. Özel yapılandırma için `docs/_config.yml` oluşturun:

```yaml
# _config.yml
title: kemal-waf Documentation
description: Web Application Firewall built with Kemal
theme: jekyll-theme-minimal

# Navigation
nav:
  - title: Home
    url: /
  - title: Installation
    url: /installation.html
  - title: Configuration
    url: /configuration.html
  - title: Rules
    url: /rules.html
  - title: Deployment
    url: /deployment.html
```

## Custom Domain (Opsiyonel)

Özel domain kullanmak için:

1. `docs/CNAME` dosyası oluşturun:
   ```
   docs.yourdomain.com
   ```

2. DNS ayarlarını yapın:
   - A record: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
   - Veya CNAME: `kursadaltan.github.io`

3. GitHub Pages Settings'te custom domain'i ekleyin

## Güncelleme

Dokümantasyonu güncellemek için:

```bash
# docs/ klasöründeki dosyaları düzenle
git add docs/
git commit -m "Update documentation"
git push origin main
```

GitHub Pages otomatik olarak güncellenecektir (birkaç dakika sürebilir).

## GitHub Actions ile Otomatik Build (Gelişmiş)

Jekyll theme kullanıyorsanız, GitHub Actions ile build edebilirsiniz:

```yaml
# .github/workflows/pages.yml
name: Build and Deploy Docs

on:
  push:
    branches:
      - main
    paths:
      - 'docs/**'

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/configure-pages@v2
      - uses: actions/upload-pages-artifact@v1
        with:
          path: docs/
      - uses: actions/deploy-pages@v1
```

## Dokümantasyon Görünümü

GitHub Pages'te dokümantasyon şu şekilde görünecek:

- **Ana Sayfa:** `https://kursadaltan.github.io/kemalwaf/`
- **Installation:** `https://kursadaltan.github.io/kemalwaf/installation.html`
- **Configuration:** `https://kursadaltan.github.io/kemalwaf/configuration.html`

## README.md'yi Ana Sayfa Yapma

`docs/README.md` dosyası otomatik olarak `index.html` olarak yayınlanır.

## Jekyll Theme Kullanımı

Daha iyi görünüm için Jekyll theme kullanabilirsiniz:

### Minimal Theme

```yaml
# docs/_config.yml
theme: jekyll-theme-minimal
```

### Cayman Theme

```yaml
# docs/_config.yml
theme: jekyll-theme-cayman
```

### Custom Layout

```html
<!-- docs/_layouts/default.html -->
<!DOCTYPE html>
<html>
<head>
  <title>{{ page.title }}</title>
</head>
<body>
  <nav>
    <a href="/">Home</a>
    <a href="/installation.html">Installation</a>
    <a href="/configuration.html">Configuration</a>
  </nav>
  <main>
    {{ content }}
  </main>
</body>
</html>
```

## Sorun Giderme

### Site Görünmüyor
- Settings > Pages'te source'un doğru seçildiğinden emin olun
- Birkaç dakika bekleyin (ilk yayınlama zaman alabilir)
- Repository'nin public olduğundan emin olun

### Linkler Çalışmıyor
- Markdown link formatını kontrol edin
- Dosya isimlerinin doğru olduğundan emin olun
- `.html` uzantısı eklemeyi deneyin

### Jekyll Build Hatası
- `_config.yml` dosyasını kontrol edin
- Syntax hatalarını kontrol edin
- GitHub Actions logs'larına bakın

## GitHub Pages vs Wiki

### GitHub Pages
- ✅ Modern görünüm
- ✅ Custom domain
- ✅ SEO dostu
- ✅ Jekyll themes
- ✅ HTML/CSS/JS desteği

### GitHub Wiki
- ✅ GitHub içinde entegre
- ✅ Kolay düzenleme
- ✅ Ayrı repository
- ❌ Sınırlı özelleştirme

## Önerilen Yaklaşım

Her ikisini de kullanabilirsiniz:
- **GitHub Pages:** Ana dokümantasyon sitesi (https://kursadaltan.github.io/kemalwaf/)
- **GitHub Wiki:** Hızlı referans ve GitHub içi erişim

## README'de Link Ekleme

Ana README.md'de GitHub Pages linkini ekleyin:

```markdown
## Documentation

📚 **[Full Documentation](https://kursadaltan.github.io/kemalwaf/)**

- [Installation Guide](https://kursadaltan.github.io/kemalwaf/installation.html)
- [Configuration](https://kursadaltan.github.io/kemalwaf/configuration.html)
- [API Reference](https://kursadaltan.github.io/kemalwaf/api.html)
```

## Sonuç

GitHub Pages kurulumu tamamlandıktan sonra:
- Dokümantasyonunuz `https://kursadaltan.github.io/kemalwaf/` adresinde yayınlanır
- Her commit'te otomatik olarak güncellenir
- Custom domain ekleyebilirsiniz
- Jekyll themes ile özelleştirebilirsiniz

