#!/usr/bin/env bash
#
# Cuts a Dowey release in one command.
#
#   Tools/release.sh                      # patch bump: 1.4.1 -> 1.4.2
#   Tools/release.sh minor "new thing"    # 1.4.2 -> 1.5.0, titled "Dowey 1.5.0 - new thing"
#   Tools/release.sh 2.0.0 "big change"   # explicit version
#
# Day to day, just commit to main and add a line under "## [Unreleased]" in
# CHANGELOG.md. Run this when you want people to get what has piled up.
#
# What it does: checks the tree, runs the tests, sets MARKETING_VERSION, turns
# [Unreleased] into the dated version heading, builds and signs Release, zips
# it into dist/, commits, tags, pushes, publishes the GitHub release, and
# installs the new build into /Applications.

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM="${DOWEY_TEAM:-U93G326S9Q}"
REPO="aarontran321/dowey"
PBXPROJ="Dowey.xcodeproj/project.pbxproj"
BUMP="${1:-patch}"
SUMMARY="${2:-}"

die() { echo "release: $*" >&2; exit 1; }

# --- Preconditions ---------------------------------------------------------

[[ "$(git branch --show-current)" == "main" ]] || die "not on main"
[[ -z "$(git status --porcelain)" ]] || die "working tree is not clean; commit first"
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" || \
   "$(git merge-base HEAD origin/main)" == "$(git rev-parse origin/main)" ]] \
    || die "origin/main has commits you do not; pull first"
gh auth status >/dev/null 2>&1 || die "gh is not signed in"

CURRENT="$(grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" | sed -E 's/.*= ([0-9.]+);/\1/')"
IFS=. read -r MAJ MIN PAT <<<"$CURRENT"
case "$BUMP" in
    patch) VERSION="$MAJ.$MIN.$((PAT + 1))" ;;
    minor) VERSION="$MAJ.$((MIN + 1)).0" ;;
    major) VERSION="$((MAJ + 1)).0.0" ;;
    [0-9]*.[0-9]*.[0-9]*) VERSION="$BUMP" ;;
    *) die "first argument must be patch, minor, major or X.Y.Z" ;;
esac
TAG="v$VERSION"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "$TAG already exists"

NOTES_BODY="$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md | sed '/./,$!d')"
[[ -n "${NOTES_BODY//[[:space:]]/}" ]] || die "CHANGELOG.md has nothing under ## [Unreleased]"

TITLE="Dowey $VERSION"
[[ -n "$SUMMARY" ]] && TITLE="$TITLE - $SUMMARY"

echo "Releasing $CURRENT -> $VERSION  ($TITLE)"

# --- Test, bump, build -----------------------------------------------------

xcodebuild -project Dowey.xcodeproj -scheme Dowey -configuration Debug \
    -derivedDataPath build/test CODE_SIGNING_ALLOWED=NO test -quiet \
    || die "tests failed"

sed -i '' "s/MARKETING_VERSION = $CURRENT;/MARKETING_VERSION = $VERSION;/" "$PBXPROJ"
sed -i '' "s/^## \[Unreleased\]\$/## [$VERSION] — $(date +%Y-%m-%d)/" CHANGELOG.md

xcodebuild -project Dowey.xcodeproj -scheme Dowey -configuration Release \
    -derivedDataPath build DEVELOPMENT_TEAM="$TEAM" -quiet \
    || { git checkout -- "$PBXPROJ" CHANGELOG.md; die "release build failed"; }

APP="build/Build/Products/Release/Dowey.app"
BUILT="$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"
[[ "$BUILT" == "$VERSION" ]] || die "built app reports $BUILT, expected $VERSION"
codesign --verify --deep --strict "$APP" || die "signature does not verify"

mkdir -p dist
ZIP="dist/Dowey-$VERSION.zip"
NOTES="dist/release-notes-$VERSION.md"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
printf '%s\n' "$NOTES_BODY" > "$NOTES"

# --- Commit, tag, publish --------------------------------------------------

MSG="chore: release $VERSION"
git add "$PBXPROJ" CHANGELOG.md
git commit -q -m "$MSG"

# Releases carry no co-author or tool attribution. Checked on the commit as
# written, so nothing a hook or template added can slip through.
if git log -1 --format='%an%n%ae%n%cn%n%ce%n%B' | grep -qiE 'claude|anthropic|co-authored-by|generated with'; then
    git reset -q --soft HEAD~1
    die "release commit carries attribution; left unstaged for you to inspect"
fi
if grep -qiE 'claude|anthropic|co-authored-by' "$NOTES"; then
    die "release notes carry attribution"
fi

git tag -a "$TAG" -m "$TITLE"
git push -q origin main
git push -q origin "$TAG"
gh release create "$TAG" "$ZIP" -R "$REPO" -t "$TITLE" -F "$NOTES"

# --- Install locally -------------------------------------------------------

pkill -x Dowey 2>/dev/null || true
sleep 1
rm -rf /Applications/Dowey.app
cp -R "$APP" /Applications/
open /Applications/Dowey.app || { sleep 1; open /Applications/Dowey.app; }

echo "Released $TITLE: https://github.com/$REPO/releases/tag/$TAG"
