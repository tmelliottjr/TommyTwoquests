#!/usr/bin/env bash
set -euo pipefail

TOC_FILE="TommyTwoquests/TommyTwoquests.toc"

# --- Parse arguments ---
BUMP_TYPE="${1:-}"

if [[ -z "$BUMP_TYPE" ]]; then
  echo "Usage: ./release.sh <patch|minor|major>"
  exit 1
fi

if [[ "$BUMP_TYPE" != "patch" && "$BUMP_TYPE" != "minor" && "$BUMP_TYPE" != "major" ]]; then
  echo "Error: bump type must be 'patch', 'minor', or 'major'"
  exit 1
fi

# --- Read current version from .toc ---
CURRENT=$(grep -oP '## Version:\s*\K[\d.]+' "$TOC_FILE")
if [[ -z "$CURRENT" ]]; then
  echo "Error: could not read version from $TOC_FILE"
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

# --- Compute next version ---
case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEXT="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${NEXT}"

echo "Current version: $CURRENT"
echo "Next version:    $NEXT"
echo ""

# --- Check CHANGELOG.md has an entry for this version ---
if grep -qP "^## Unreleased(\s|$)" CHANGELOG.md 2>/dev/null; then
  # Rename "Unreleased" to the new version
  sed -i "s/^## Unreleased.*/## v${NEXT}/" CHANGELOG.md
  echo "Updated CHANGELOG.md: Unreleased → v${NEXT}"
elif ! grep -qP "^## v${NEXT}(\s|$)" CHANGELOG.md 2>/dev/null; then
  echo "Warning: CHANGELOG.md has no '## Unreleased' or '## v${NEXT}' section."
  echo "Add your release notes before releasing."
  read -rp "Continue anyway? (y/N) " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted. Update CHANGELOG.md and try again."
    exit 1
  fi
fi

# --- Check for uncommitted changes ---
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: you have uncommitted changes. Commit or stash them first."
  exit 1
fi

# --- Check tag doesn't already exist ---
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Error: tag $TAG already exists"
  exit 1
fi

# --- Update .toc ---
sed -i "s/^## Version: .*/## Version: ${NEXT}/" "$TOC_FILE"
echo "Updated $TOC_FILE → $NEXT"

# --- Commit, tag, push ---
git add "$TOC_FILE" CHANGELOG.md
git commit -m "chore: bump version to ${NEXT}"
git tag "$TAG"
git push && git push origin "$TAG"

echo ""
echo "Released $TAG"
echo "GitHub Actions will now build the release at:"
echo "  https://github.com/tmelliottjr/TommyTwoquests/actions"
