#!/usr/bin/env bash
# Publish the current work to ALL FOUR live targets.
#
#   1. Railway  banner     https://wiom-mbg-kamai-kavach-production.up.railway.app/
#   2. Railway  dashboard  https://wiom-mbg-kamai-kavach-production.up.railway.app/analytics-dashboard/
#        -> both served from the ORG repo  Wiom-using-AI/wiom-mbg-kamai-kavach
#           (banner at root, dashboard in analytics-dashboard/)
#   3. Pages    banner     https://vikaswiom.github.io/wiom-mbg-kamai-kavach/
#        -> personal repo  Vikaswiom/wiom-mbg-kamai-kavach            (remote: personal)
#   4. Pages    dashboard  https://vikaswiom.github.io/wiom-mbg-banner-dashboard/
#        -> personal repo  Vikaswiom/wiom-mbg-banner-dashboard        (separate clone)
#
# Every target auto-refreshes its own data (GitHub Actions / the Railway server), so
# data.json and data.js drift constantly and CONFLICT on every merge. They are
# generated files — the conflict is meaningless, so we always resolve it by taking the
# remote's copy and letting the next refresh regenerate.
#
# Usage:  ./sync-all.sh
set -uo pipefail

BANNER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASH="${DASH_REPO:-/c/Users/Vikas Diwaker/wiom-mbg-banner-dashboard}"
GIT_ID=(-c user.name=Vikaswiom -c user.email=design.3@wiom.in)

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# Merge a remote, auto-resolving the generated data files.
merge_remote() {
  local remote="$1"
  git -C "$BANNER" fetch "$remote" main -q
  if ! git -C "$BANNER" "${GIT_ID[@]}" merge --no-edit "$remote/main" -q 2>/dev/null; then
    for f in data.json analytics-dashboard/data.js; do
      if git -C "$BANNER" status --porcelain -- "$f" | grep -qE '^(UU|AA)'; then
        git -C "$BANNER" checkout --theirs -- "$f" 2>/dev/null
        git -C "$BANNER" add -- "$f"
        echo "   resolved generated file: $f"
      fi
    done
    git -C "$BANNER" "${GIT_ID[@]}" commit -q --no-edit || {
      echo "   !! unresolved conflict — fix by hand, then re-run"; exit 1; }
  fi
}

say "1/4  reconcile banner repo with org + personal"
merge_remote origin
merge_remote personal

say "2/4  push banner -> ORG (Railway) and PERSONAL (Pages)"
git -C "$BANNER" push origin   main
git -C "$BANNER" push personal main

say "3/4  mirror dashboard content -> standalone personal dashboard repo"
git -C "$DASH" fetch origin main -q
git -C "$DASH" reset --hard origin/main -q
# data.js is excluded on purpose: each repo regenerates its own on its own schedule.
for f in index.html server.py nixpacks.toml refresh.py \
         query_csp_funnel.sql query_efficiency.sql \
         query_segment_funnel.sql query_enrolled_roster.sql; do
  cp "$BANNER/analytics-dashboard/$f" "$DASH/$f"
done

say "4/4  push dashboard -> PERSONAL (Pages)"
if [ -n "$(git -C "$DASH" status --porcelain)" ]; then
  git -C "$DASH" add -A
  git -C "$DASH" "${GIT_ID[@]}" commit -q -m "sync: mirror dashboard from the Railway monorepo"
  git -C "$DASH" push origin main
else
  echo "   already up to date"
fi

say "done — all four targets published"
