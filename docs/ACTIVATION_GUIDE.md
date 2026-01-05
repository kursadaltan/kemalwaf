# GitHub Pages ve Wiki Aktivasyon Rehberi

Bu rehber, kemal-waf dokümantasyonunu GitHub Pages ve Wiki'de aktifleştirmek için adım adım talimatlar içerir.

## 🚀 Hızlı Başlangıç

### 1. GitHub Pages'i Aktifleştirme

1. GitHub repo'nuzda **Settings** sekmesine gidin
   - URL: `https://github.com/kursadaltan/kemalwaf/settings`

2. Sol menüden **Pages** seçeneğine tıklayın

3. **Source** bölümünde:
   - **Branch:** `main` (veya `master`) seçin
   - **Folder:** `/docs` seçin

4. **Save** butonuna tıklayın

5. Birkaç dakika bekleyin (ilk yayınlama 5-10 dakika sürebilir)

6. Site şu adreste yayınlanacak:
   ```
   https://kursadaltan.github.io/kemalwaf/
   ```

✅ **GitHub Pages aktif!**

### 2. GitHub Wiki'yi Aktifleştirme

1. GitHub repo'nuzda **Settings** sekmesine gidin
   - URL: `https://github.com/kursadaltan/kemalwaf/settings`

2. Sol menüden **General** sekmesine gidin

3. **Features** bölümünde:
   - **Wikis** checkbox'ını işaretleyin

4. **Save** butonuna tıklayın

5. Wiki'yi ilk kez doldurmak için aşağıdaki adımları izleyin

✅ **GitHub Wiki aktif!**

## 📋 Wiki'yi İlk Kez Doldurma

### Yöntem 1: Otomatik Script (Önerilen)

```bash
# Script'i çalıştır
./scripts/sync-wiki.sh
```

Bu script:
- Wiki repository'sini clone eder
- Tüm dokümantasyon dosyalarını kopyalar
- Linkleri wiki formatına çevirir
- Otomatik commit ve push yapar

### Yöntem 2: Manuel Kopyalama

```bash
# 1. Wiki repository'sini clone et
git clone https://github.com/kursadaltan/kemalwaf.wiki.git
cd kemalwaf.wiki

# 2. Dokümantasyon dosyalarını kopyala
cp ../docs/README.md Home.md
cp ../docs/installation.md Installation.md
cp ../docs/configuration.md Configuration.md
cp ../docs/rules.md Rules.md
cp ../docs/deployment.md Deployment.md
cp ../docs/nginx-setup.md Nginx-Setup.md
cp ../docs/tls-https.md TLS-HTTPS.md
cp ../docs/api.md API-Reference.md
cp ../docs/environment-variables.md Environment-Variables.md
cp ../docs/geoip.md GeoIP-Filtering.md

# 3. Sidebar oluştur
cat > _Sidebar.md << 'EOF'
## Getting Started
- [[Home]]
- [[Installation]]
- [[Configuration]]

## Guides
- [[Rules]]
- [[Deployment]]
- [[Nginx-Setup]]
- [[TLS-HTTPS]]

## Reference
- [[API-Reference]]
- [[Environment-Variables]]
- [[GeoIP-Filtering]]
EOF

# 4. Commit ve push
git add .
git commit -m "Initial documentation"
git push origin master
```

### Yöntem 3: GitHub Web UI

1. Wiki sekmesine gidin: `https://github.com/kursadaltan/kemalwaf/wiki`
2. **Create the first page** butonuna tıklayın
3. Sayfa adı: `Home`
4. İçeriği `docs/README.md` dosyasından kopyalayın
5. **Save Page** butonuna tıklayın
6. Diğer sayfalar için **New Page** butonunu kullanın

## 🔄 Otomatik Senkronizasyon

### GitHub Actions ile Otomatik Sync

`.github/workflows/sync-wiki.yml` dosyası zaten hazır! Bu workflow:

- `docs/` klasöründeki değişiklikleri otomatik algılar
- Wiki'yi otomatik günceller
- Her commit'te çalışır

**Not:** İlk çalıştırmada GitHub Actions'ın wiki repository'sine yazma izni olması gerekir. Bu genellikle otomatik olarak ayarlanır.

### Manuel Sync

Dokümantasyonu güncelledikten sonra:

```bash
./scripts/sync-wiki.sh
```

## ✅ Kontrol Listesi

### GitHub Pages
- [ ] Settings > Pages'te source ayarlandı (`main` branch, `/docs` folder)
- [ ] Site yayınlandı: `https://kursadaltan.github.io/kemalwaf/`
- [ ] Ana sayfa görünüyor
- [ ] Linkler çalışıyor

### GitHub Wiki
- [ ] Settings > Features'te Wikis aktif
- [ ] Wiki sayfası açılıyor: `https://github.com/kursadaltan/kemalwaf/wiki`
- [ ] Home.md sayfası var
- [ ] Tüm dokümantasyon sayfaları kopyalandı
- [ ] Sidebar görünüyor
- [ ] Linkler çalışıyor

### Otomatik Sync
- [ ] GitHub Actions workflow aktif
- [ ] `docs/` klasöründeki değişiklikler wiki'ye sync oluyor

## 🔗 Erişim Linkleri

Aktifleştirme sonrası:

- **GitHub Pages:** https://kursadaltan.github.io/kemalwaf/
- **GitHub Wiki:** https://github.com/kursadaltan/kemalwaf/wiki
- **Repository Docs:** https://github.com/kursadaltan/kemalwaf/tree/main/docs

## 📝 README Güncellemesi

README.md dosyası zaten güncellenmiş durumda. Şu linkler eklendi:

```markdown
## Documentation

📚 **Full Documentation Available:**

- 🌐 **[GitHub Pages](https://kursadaltan.github.io/kemalwaf/)** - Online documentation site
- 📖 **[GitHub Wiki](https://github.com/kursadaltan/kemalwaf/wiki)** - Wiki documentation
- 📁 **[Local Docs](docs/)** - Documentation files in repository
```

## 🐛 Sorun Giderme

### GitHub Pages Görünmüyor

1. **Settings kontrolü:**
   - Settings > Pages'te source doğru mu?
   - Branch `main` seçili mi?
   - Folder `/docs` seçili mi?

2. **Bekleme süresi:**
   - İlk yayınlama 5-10 dakika sürebilir
   - Birkaç dakika bekleyin ve sayfayı yenileyin

3. **Repository durumu:**
   - Repository public mi? (Private repo'lar için GitHub Pro gerekir)

4. **Build hataları:**
   - Actions sekmesinde build loglarını kontrol edin
   - `_config.yml` dosyasında syntax hatası var mı?

### Wiki Görünmüyor

1. **Settings kontrolü:**
   - Settings > Features'te Wikis aktif mi?

2. **İlk sayfa:**
   - Wiki'de en az bir sayfa olmalı (Home.md)

3. **Repository erişimi:**
   - Wiki repository'sine erişim izniniz var mı?
   - `https://github.com/kursadaltan/kemalwaf.wiki` adresine erişebiliyor musunuz?

### Otomatik Sync Çalışmıyor

1. **GitHub Actions:**
   - Actions sekmesinde workflow çalışıyor mu?
   - Hata mesajları var mı?

2. **Token izinleri:**
   - `GITHUB_TOKEN` otomatik olarak ayarlanır
   - Eğer çalışmıyorsa, Personal Access Token ekleyebilirsiniz

3. **Manuel sync:**
   - `./scripts/sync-wiki.sh` scriptini manuel çalıştırın

## 🎉 Tamamlandı!

Her şey hazır! Artık dokümantasyonunuz:

1. ✅ **GitHub Pages'te** yayınlanıyor
2. ✅ **GitHub Wiki'de** erişilebilir
3. ✅ **Otomatik senkronize** oluyor

Her `docs/` klasöründeki değişiklik otomatik olarak:
- GitHub Pages'e yansır (birkaç dakika içinde)
- GitHub Wiki'ye sync olur (GitHub Actions ile)

## 📚 Ek Kaynaklar

- [GitHub Pages Documentation](https://docs.github.com/en/pages)
- [GitHub Wiki Documentation](https://docs.github.com/en/communities/documenting-your-project-with-wikis)
- [Jekyll Themes](https://jekyllthemes.io/)

