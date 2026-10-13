#!/usr/bin/env bash
# Fails if a renamed package's old name (navigation_engine_<service>) is
# still used anywhere but in CHANGELOG history. Usage: tool/old_names_check.sh
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
# The tail `($|[^[:alnum:]])` is a word boundary written without `\b`, which
# macOS git grep silently never matches. It lets `_` follow, so the old
# `navigation_engine_<service>_example` is caught too.
old='navigation_engine_(google_maps|mapbox|maplibre|flutter_map|osrm|vietmap|goong|geolocator|google_routes|mapbox_directions)($|[^[:alnum:]])'
# git grep exits 1 when nothing matches; anything above 1 is a real error.
set +e
hits="$(cd "$repo" && git grep -nIE "$old" -- . ':!**/CHANGELOG.md' ':!tool/old_names_check.sh' \
  ':!**/*.iml' ':!**/ios/**' ':!**/android/**' ':!**/macos/**' ':!**/linux/**' ':!**/windows/**' ':!**/web/**')"
grep_status=$?
set -e
if [ "$grep_status" -gt 1 ]; then
  echo "git grep failed ($grep_status)" >&2
  exit "$grep_status"
fi
# Files git does not track yet (git grep above only sees tracked ones): every
# text file (-I skips binaries) under packages, tool and .github, plus any
# top-level file. The native platform folders keep their app ids by design;
# .idea is gitignored IDE state, rewritten by the IDE.
untracked="$(cd "$repo" && {
  grep -rnIE "$old" packages tool .github \
    --exclude-dir=build --exclude-dir=.dart_tool --exclude-dir=.idea --exclude-dir=ios --exclude-dir=android \
    --exclude-dir=macos --exclude-dir=linux --exclude-dir=windows --exclude-dir=web \
    --exclude=CHANGELOG.md --exclude=old_names_check.sh --exclude='*.iml' 2> /dev/null || true
  find . -maxdepth 1 -type f ! -name CHANGELOG.md ! -name '*.iml' -exec grep -nIE "$old" {} + 2> /dev/null | sed 's|^\./||' || true
} | grep -vE '^\./' || true)"
if [ -n "$hits$untracked" ]; then
  printf '%s\n%s\n' "$hits" "$untracked" | sort -u | sed '/^$/d'
  echo "old package names found" >&2
  exit 1
fi
