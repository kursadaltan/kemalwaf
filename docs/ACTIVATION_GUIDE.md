# GitHub Pages ve Wiki Aktivasyon Rehberi

Bu rehber, kemal-waf dokümantasyonunu GitHub Pages ve Wiki'de aktifleştirmek için adım adım talimatlar içerir. **Wiki tamamen GitHub Actions ile senkronize edilir; elle wiki repo oluşturmanıza gerek yok.**

---

## 1. GitHub Pages

1. Repo **Settings** → **Pages**
2. **Source:** Branch `main`, Folder **/docs**
3. **Save**
4. Birkaç dakika sonra: **https://kursadaltan.github.io/kemalwaf/**

---

## 2. GitHub Wiki (sadece Actions, elle repo yok)

### Adım 1: Wikis’i aç

1. Repo **Settings** → **General**
2. **Features** bölümünde **Wikis** işaretle
3. **Save**

### Adım 2: Wiki’yi ilk kez oluştur

Wiki repo’nun oluşması için GitHub’da en az bir sayfa gerekir:

1. Repo ana sayfasında **Wiki** sekmesine tıkla  
   veya: **https://github.com/kursadaltan/kemalwaf/wiki**
2. **Create the first page** (veya “New Page”)
3. Başlık: `Home`, içerik: `# Welcome` (veya boş)
4. **Save Page**

Böylece `kemalwaf.wiki` repo’su oluşur. İçeriği elle doldurmayın; Actions dolduracak.

### Adım 3: Secret ekle (Actions’ın wiki’ye yazması için)

1. GitHub’da **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. **Generate new token (classic)**
3. İsim: `Wiki Sync`, süre: istediğiniz
4. İzin: **repo** (Full control of private repositories)
5. **Generate token** → token’ı kopyala (bir daha gösterilmez)
6. Repo’ya dön: **Settings** → **Secrets and variables** → **Actions**
7. **New repository secret**
8. Name: **`WIKI_GITHUB_TOKEN`**  
   Value: az önce kopyaladığınız token
9. **Add secret**

### Adım 4: Workflow’u tetikle

- **Seçenek A:** `docs/` içinde bir değişiklik yapıp `main`’e push edin → “Sync Docs to Wiki” workflow’u otomatik çalışır.
- **Seçenek B:** **Actions** → **Sync Docs to Wiki** → **Run workflow** → **Run workflow**

İlk çalışmada Actions, `docs/` içeriğini wiki’ye kopyalayıp günceller. Sonraki her `docs/` değişikliğinde wiki otomatik güncellenir.

---

## Özet

| Ne yapacaksınız | Nerede |
|-----------------|--------|
| Wikis’i açmak | Settings → General → Features → Wikis |
| İlk wiki sayfası (Home) | Wiki sekmesi → Create the first page |
| Secret `WIKI_GITHUB_TOKEN` | Settings → Secrets and variables → Actions |
| Wiki içeriğini doldurmak | **Hiçbir şey** – GitHub Actions yapar |

Elle wiki repo clone etmeniz veya lokal script çalıştırmanız gerekmez.

---

## Kontrol listesi

### GitHub Pages
- [ ] Settings → Pages: Branch `main`, Folder `/docs`
- [ ] https://kursadaltan.github.io/kemalwaf/ açılıyor

### GitHub Wiki
- [ ] Settings → Features → Wikis işaretli
- [ ] Wiki’de “Create the first page” ile bir sayfa oluşturuldu
- [ ] Secret: **WIKI_GITHUB_TOKEN** eklendi
- [ ] Actions’ta “Sync Docs to Wiki” bir kez başarıyla çalıştı
- [ ] https://github.com/kursadaltan/kemalwaf/wiki dolu ve güncel

---

## Sorun giderme

### “WIKI_GITHUB_TOKEN secret tanımlı değil”
- Repo **Settings** → **Secrets and variables** → **Actions**
- Secret adı tam olarak **`WIKI_GITHUB_TOKEN`** olmalı
- Değer: `repo` yetkili Personal Access Token

### “Wiki clone edilemedi”
- Wikis açık mı? (Settings → General → Features → Wikis)
- Wiki’de en az bir sayfa var mı? (Wiki → Create the first page / New Page)
- Sayfa kaydettikten sonra workflow’u tekrar çalıştırın.

### Wiki güncellenmiyor
- **Actions** sekmesinde “Sync Docs to Wiki” son çalıştırmasına bakın
- Hata varsa log’u inceleyin
- `docs/` değişikliği yapıp push ettiğinizde workflow tetiklenir; path filtresi `docs/**` ve `sync-wiki.yml` değişikliklerini içerir.

---

## Erişim linkleri

- **GitHub Pages:** https://kursadaltan.github.io/kemalwaf/
- **GitHub Wiki:** https://github.com/kursadaltan/kemalwaf/wiki
- **Repo docs:** https://github.com/kursadaltan/kemalwaf/tree/main/docs
