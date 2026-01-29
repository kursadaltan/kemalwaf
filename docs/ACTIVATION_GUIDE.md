# GitHub Pages & Wiki Setup

How to turn on the docs site (GitHub Pages) and the wiki. **The wiki is updated automatically by GitHub Actions—you don’t create or edit the wiki repo by hand.**

---

## 1. GitHub Pages (docs site)

1. Repo **Settings** → **Pages**
2. **Source:** Branch `main`, Folder **/docs**
3. **Save**
4. In a few minutes the site is live at: **https://kursadaltan.github.io/kemalwaf/**

---

## 2. GitHub Wiki (auto-synced from docs)

### Turn on Wikis

1. Repo **Settings** → **General**
2. Under **Features**, check **Wikis**
3. **Save**

### Create the first wiki page

GitHub only creates the wiki repo after at least one page exists:

1. Open the **Wiki** tab (or go to **https://github.com/kursadaltan/kemalwaf/wiki**)
2. Click **Create the first page**
3. Title: `Home`, body: `# Welcome` (or leave empty)
4. **Save Page**

That creates the wiki repo. Don’t add content by hand—the Actions workflow will fill it from `docs/`.

### Add a secret so Actions can push

1. GitHub **Settings** (your account) → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. **Generate new token (classic)**
3. Name: `Wiki Sync`, expiration: your choice
4. Scope: **repo**
5. **Generate token** and copy it (you won’t see it again)
6. Back in the repo: **Settings** → **Secrets and variables** → **Actions**
7. **New repository secret**
8. Name: **`WIKI_GITHUB_TOKEN`**, Value: the token you copied
9. **Add secret**

### Run the workflow

- **A:** Change something in `docs/` and push to `main` → the “Sync Docs to Wiki” workflow runs on its own.
- **B:** **Actions** → **Sync Docs to Wiki** → **Run workflow**

The first run copies `docs/` into the wiki. After that, any push that touches `docs/` updates the wiki automatically.

---

## Summary

| Step | Where |
|------|--------|
| Enable Wikis | Settings → General → Features → Wikis |
| Create first page | Wiki tab → Create the first page |
| Add secret | Settings → Secrets and variables → Actions → `WIKI_GITHUB_TOKEN` |
| Wiki content | Handled by GitHub Actions |

No need to clone the wiki repo or run scripts locally.

---

## Checklist

**Pages**

- [ ] Settings → Pages: Branch `main`, Folder `/docs`
- [ ] https://kursadaltan.github.io/kemalwaf/ works

**Wiki**

- [ ] Wikis enabled in Settings → Features
- [ ] At least one page created on the Wiki tab
- [ ] Secret `WIKI_GITHUB_TOKEN` added
- [ ] “Sync Docs to Wiki” has run once successfully
- [ ] https://github.com/kursadaltan/kemalwaf/wiki has content

---

## Troubleshooting

**“WIKI_GITHUB_TOKEN secret is not set”**  
Add it under repo **Settings** → **Secrets and variables** → **Actions**. Name must be exactly `WIKI_GITHUB_TOKEN`. Use a Personal Access Token with **repo** scope.

**“Wiki clone failed”**  
Make sure Wikis is enabled and you’ve created at least one page on the Wiki tab. Then run the workflow again.

**Wiki not updating**  
Check the **Actions** tab for “Sync Docs to Wiki.” If it failed, look at the logs. The workflow runs when you push changes under `docs/` or the workflow file.

---

## Links

- **GitHub Pages:** https://kursadaltan.github.io/kemalwaf/
- **Wiki:** https://github.com/kursadaltan/kemalwaf/wiki
- **Repo docs:** https://github.com/kursadaltan/kemalwaf/tree/main/docs
