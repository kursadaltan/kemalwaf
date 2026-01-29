#!/bin/bash

# OPSIYONEL: Wiki'yi yerelde senkronize eder.
# Asıl yöntem GitHub Actions'tır (elle repo oluşturmanız gerekmez).
# Bkz: docs/ACTIVATION_GUIDE.md
#
# Usage: ./scripts/sync-wiki.sh
# Environment variables:
#   GITHUB_TOKEN - Personal Access Token (for HTTPS)
#   GITHUB_USER  - GitHub username (default: kursadaltan)

set -e

REPO_NAME="kemalwaf"
WIKI_REPO="kemalwaf.wiki"
GITHUB_USER="${GITHUB_USER:-kursadaltan}"

# Determine which URL to use
if [ -n "$GITHUB_TOKEN" ]; then
    # Use HTTPS with token
    WIKI_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${WIKI_REPO}.git"
    PUSH_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${WIKI_REPO}.git"
elif git ls-remote "git@github.com:${GITHUB_USER}/${WIKI_REPO}.git" &>/dev/null; then
    # Use SSH if available
    WIKI_URL="git@github.com:${GITHUB_USER}/${WIKI_REPO}.git"
    PUSH_URL="git@github.com:${GITHUB_USER}/${WIKI_REPO}.git"
else
    # Fallback to HTTPS (will prompt for credentials)
    WIKI_URL="https://github.com/${GITHUB_USER}/${WIKI_REPO}.git"
    PUSH_URL="https://github.com/${GITHUB_USER}/${WIKI_REPO}.git"
fi

echo "🚀 Syncing documentation to GitHub Wiki..."

# Check if wiki repo exists locally
if [ ! -d "$WIKI_REPO" ]; then
    echo "📦 Cloning wiki repository..."
    git clone "$WIKI_URL" "$WIKI_REPO"
else
    echo "📥 Updating wiki repository..."
    cd "$WIKI_REPO"
    git pull origin master
    cd ..
fi

# Copy documentation files
echo "📋 Copying documentation files..."

# Main pages
cp docs/README.md "$WIKI_REPO/Home.md"
cp docs/installation.md "$WIKI_REPO/Installation.md"
cp docs/configuration.md "$WIKI_REPO/Configuration.md"
cp docs/rules.md "$WIKI_REPO/Rules.md"
cp docs/deployment.md "$WIKI_REPO/Deployment.md"
cp docs/nginx-setup.md "$WIKI_REPO/Nginx-Setup.md"
cp docs/tls-https.md "$WIKI_REPO/TLS-HTTPS.md"
cp docs/api.md "$WIKI_REPO/API-Reference.md"
cp docs/environment-variables.md "$WIKI_REPO/Environment-Variables.md"
cp docs/geoip.md "$WIKI_REPO/GeoIP-Filtering.md"

# Create sidebar
cat > "$WIKI_REPO/_Sidebar.md" << 'EOF'
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

# Update Home.md with wiki-style links
echo "🔗 Updating links for wiki format..."
cd "$WIKI_REPO"

# Convert markdown links to wiki format
sed -i '' 's|\.github/docs/||g' Home.md
sed -i '' 's|docs/||g' Home.md
sed -i '' 's|(installation\.md)|(Installation)|g' Home.md
sed -i '' 's|(configuration\.md)|(Configuration)|g' Home.md
sed -i '' 's|(rules\.md)|(Rules)|g' Home.md
sed -i '' 's|(deployment\.md)|(Deployment)|g' Home.md
sed -i '' 's|(nginx-setup\.md)|(Nginx-Setup)|g' Home.md
sed -i '' 's|(tls-https\.md)|(TLS-HTTPS)|g' Home.md
sed -i '' 's|(api\.md)|(API-Reference)|g' Home.md
sed -i '' 's|(environment-variables\.md)|(Environment-Variables)|g' Home.md
sed -i '' 's|(geoip\.md)|(GeoIP-Filtering)|g' Home.md

# Commit and push
echo "💾 Committing changes..."
git add .
git diff --quiet && git diff --staged --quiet && echo "✅ No changes to commit" || {
    git commit -m "Auto-sync docs from main repo - $(date +%Y-%m-%d)"
    echo "📤 Pushing to GitHub..."
    
    # Set remote URL for push
    git remote set-url origin "$PUSH_URL"
    
    # Push
    if git push origin master; then
        echo "✅ Wiki updated successfully!"
    else
        echo "❌ Push failed!"
        echo ""
        echo "💡 Solutions:"
        echo "   1. Use SSH: Set up SSH keys and use git@github.com URL"
        echo "   2. Use Personal Access Token:"
        echo "      export GITHUB_TOKEN=your_token_here"
        echo "      ./scripts/sync-wiki.sh"
        echo "   3. Use GitHub CLI: gh auth login"
        echo ""
        exit 1
    fi
}

cd ..

echo "🎉 Done! Wiki is now synced with main repository."
echo "📖 View at: https://github.com/kursadaltan/${REPO_NAME}/wiki"

