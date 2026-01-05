# Wiki Sync Sorun Giderme

Wiki'ye push yaparken permission hatası alıyorsanız, bu rehberi takip edin.

## Hata: Permission Denied (403)

```
remote: Permission to kursadaltan/kemalwaf.wiki.git denied
fatal: unable to access 'https://github.com/...': The requested URL returned error: 403
```

## Çözüm 1: Personal Access Token Kullanma (Önerilen)

### 1. GitHub'da Token Oluşturma

1. GitHub'da sağ üst köşeden **Settings** > **Developer settings**
2. **Personal access tokens** > **Tokens (classic)**
3. **Generate new token (classic)**
4. İzinler:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `write:packages` (opsiyonel)
5. **Generate token** ve token'ı kopyalayın

### 2. Token ile Script Çalıştırma

```bash
# Token'ı environment variable olarak ayarla
export GITHUB_TOKEN=ghp_your_token_here

# Script'i çalıştır
./scripts/sync-wiki.sh
```

### 3. Token'ı Kalıcı Yapma (Opsiyonel)

```bash
# ~/.zshrc veya ~/.bashrc dosyasına ekle
export GITHUB_TOKEN=ghp_your_token_here

# Veya güvenli saklama için
echo 'export GITHUB_TOKEN=ghp_your_token_here' >> ~/.zshrc
source ~/.zshrc
```

## Çözüm 2: SSH Kullanma

### 1. SSH Key Kontrolü

```bash
# SSH key'iniz var mı kontrol edin
ls -la ~/.ssh/id_rsa.pub
```

### 2. SSH Key Yoksa Oluşturma

```bash
# SSH key oluştur
ssh-keygen -t ed25519 -C "your_email@example.com"

# Public key'i kopyala
cat ~/.ssh/id_ed25519.pub
```

### 3. GitHub'a SSH Key Ekleme

1. GitHub'da **Settings** > **SSH and GPG keys**
2. **New SSH key**
3. Public key'i yapıştırın
4. **Add SSH key**

### 4. SSH ile Test

```bash
# SSH bağlantısını test et
ssh -T git@github.com

# Başarılı olursa şunu görürsünüz:
# Hi kursadaltan! You've successfully authenticated...
```

### 5. Script'i SSH ile Çalıştırma

Script otomatik olarak SSH kullanacaktır. Eğer kullanmıyorsa:

```bash
# SSH URL'i manuel ayarla
cd kemalwaf.wiki
git remote set-url origin git@github.com:kursadaltan/kemalwaf.wiki.git
git push origin master
```

## Çözüm 3: GitHub CLI Kullanma

### 1. GitHub CLI Kurulumu

```bash
# macOS
brew install gh

# Linux
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
```

### 2. GitHub CLI ile Login

```bash
gh auth login

# Seçenekler:
# - GitHub.com
# - HTTPS
# - Login with a web browser
```

### 3. Script'i Çalıştırma

GitHub CLI login olduktan sonra script normal çalışacaktır.

## Çözüm 4: Manuel Push

Eğer script çalışmıyorsa, manuel olarak push yapabilirsiniz:

```bash
cd kemalwaf.wiki

# Değişiklikleri kontrol et
git status

# Commit (eğer yapılmadıysa)
git add .
git commit -m "Update documentation"

# Push
# Token ile:
git push https://YOUR_TOKEN@github.com/kursadaltan/kemalwaf.wiki.git master

# Veya SSH ile:
git push git@github.com:kursadaltan/kemalwaf.wiki.git master
```

## Çözüm 5: GitHub Web UI Kullanma

En kolay yöntem GitHub web arayüzünü kullanmak:

1. Wiki sayfasına gidin: `https://github.com/kursadaltan/kemalwaf/wiki`
2. Her sayfayı manuel olarak oluşturun/düzenleyin
3. **New Page** butonunu kullanın

## Hızlı Kontrol

```bash
# 1. Git config kontrolü
git config --global user.name
git config --global user.email

# 2. SSH bağlantı testi
ssh -T git@github.com

# 3. GitHub CLI login kontrolü
gh auth status

# 4. Token kontrolü (eğer ayarladıysanız)
echo $GITHUB_TOKEN
```

## Önerilen Yöntem

**En kolay ve güvenli yöntem:** Personal Access Token

```bash
# 1. Token oluştur (GitHub web'den)
# 2. Token'ı ayarla
export GITHUB_TOKEN=ghp_your_token_here

# 3. Script'i çalıştır
./scripts/sync-wiki.sh
```

## Sorun Devam Ediyorsa

1. **Wiki aktif mi kontrol edin:**
   - Settings > Features > Wikis checkbox işaretli mi?

2. **Repository erişimi:**
   - Wiki repository'sine erişim izniniz var mı?
   - `https://github.com/kursadaltan/kemalwaf.wiki` adresine erişebiliyor musunuz?

3. **GitHub Actions kullanın:**
   - Manuel sync yerine GitHub Actions workflow'unu kullanın
   - `.github/workflows/sync-wiki.yml` otomatik çalışacaktır

## GitHub Actions ile Otomatik Sync

Manuel sync yerine GitHub Actions kullanabilirsiniz:

1. `docs/` klasöründeki dosyaları commit edin
2. Push yapın
3. GitHub Actions otomatik olarak wiki'yi güncelleyecektir

Bu yöntem için ekstra yapılandırma gerekmez, otomatik çalışır!

