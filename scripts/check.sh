#!/usr/bin/env bash
# Validate this profile against one frappe-nix (spec §1.3 item P, §6.4):
#
#   1. `frappe-nix profile validate profile.toml`;
#   2. `frappe-nix profile show --format json` of a copy of frappe-nix's fixture app that
#      selects this profile, compared with the committed resolved.snapshot.json, so a
#      frappe-nix release that would change any value of ours fails here first;
#   3. an offline `frappe-nix sync --write` of that copy (the profile in-repo), then
#      `sync --check`: every managed file renders with our values;
#   4. fleet.json against the profile (scripts/check_fleet.py).
#
# Usage: scripts/check.sh [--update]
#   --update  rewrite resolved.snapshot.json instead of comparing it
#
# Environment:
#   FRAPPE_NIX      the frappe-nix CLI to use (default: the one flake.lock pins, built with nix)
#   FRAPPE_NIX_SRC  the matching frappe-nix source tree (default: the one flake.lock pins)
#
# Before frappe-nix v1.0.0 exists, the pinned frappe-nix-tools reports 0.0.0, which
# `requires-frappe-nix = ">=1.0,<2"` excludes (exit 3). Against such an unreleased build
# the checks run on a copy without that one line, with a warning; against any release the
# file is checked exactly as committed.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

update=0
case "${1:-}" in
  --update) update=1 ;;
  "") ;;
  *) echo "usage: scripts/check.sh [--update]" >&2; exit 2 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ -z "${FRAPPE_NIX:-}" ]; then
  nix build .#frappe-nix --out-link "$work/frappe-nix"
  FRAPPE_NIX="$work/frappe-nix/bin/frappe-nix"
fi
if [ -z "${FRAPPE_NIX_SRC:-}" ]; then
  FRAPPE_NIX_SRC="$(nix eval --raw .#lib.frappe-nix-src)"
fi
fixture="$FRAPPE_NIX_SRC/tests/fixtures/standards-app"
[ -f "$fixture/pyproject.toml" ] || { echo "error: no fixture app at $fixture" >&2; exit 2; }

# A repository of its own for each copy: none of the user's git configuration applies.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=profile-check GIT_AUTHOR_EMAIL=profile-check@example.org
export GIT_COMMITTER_NAME=profile-check GIT_COMMITTER_EMAIL=profile-check@example.org

version="$("$FRAPPE_NIX" --version)"
echo "frappe-nix-tools $version (fixture from $FRAPPE_NIX_SRC)"

# The profile directory every check reads.
profile="$work/profile"
mkdir -p "$profile"
if [ "$version" = "0.0.0" ]; then
  msg="frappe-nix-tools $version is an unreleased build: checking profile.toml without its requires-frappe-nix line"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::$msg"; else echo "warning: $msg" >&2; fi
  grep -v '^requires-frappe-nix[[:space:]]*=' profile.toml > "$profile/profile.toml"
else
  cp profile.toml "$profile/profile.toml"
fi
if [ -d templates ]; then
  cp -r templates "$profile/templates"
fi

echo "== profile validate"
"$FRAPPE_NIX" profile validate "$profile/profile.toml"

echo "== resolved configuration of the fixture app"
cp -r "$fixture" "$work/app"
chmod -R u+w "$work/app"
sed -i 's#^profile = .*$#profile = "github:Avunu/frappe-standards-profile/v1"#' "$work/app/pyproject.toml"
grep -qx 'profile = "github:Avunu/frappe-standards-profile/v1"' "$work/app/pyproject.toml" || {
  echo "error: the fixture's pyproject.toml has no profile line to point at this profile" >&2
  exit 2
}
git -C "$work/app" init -q
git -C "$work/app" add -A
(cd "$work/app" && "$FRAPPE_NIX" profile show --format json --profile-path "$profile") > "$work/resolved.json"
if [ "$update" = 1 ]; then
  cp "$work/resolved.json" resolved.snapshot.json
  echo "wrote resolved.snapshot.json"
elif ! diff -u resolved.snapshot.json "$work/resolved.json"; then
  echo "error: the resolved configuration differs from resolved.snapshot.json (diff above)." >&2
  echo "If the change is intended, run scripts/check.sh --update and commit the result." >&2
  exit 1
else
  echo "matches resolved.snapshot.json"
fi

echo "== offline sync of the fixture app"
cp -r "$fixture" "$work/sync"
chmod -R u+w "$work/sync"
cp -r "$profile" "$work/sync/.standards-profile"
sed -i 's#^profile = .*$#profile = "./.standards-profile"#' "$work/sync/pyproject.toml"
git -C "$work/sync" init -q
git -C "$work/sync" add -A
git -C "$work/sync" commit -qm fixture
# The fixture pins this same frappe-nix only by flake.lock; skew is expected here.
(cd "$work/sync" && FRAPPE_NIX_ALLOW_SKEW=1 "$FRAPPE_NIX" sync --write --offline)
git -C "$work/sync" add -A
(cd "$work/sync" && FRAPPE_NIX_ALLOW_SKEW=1 "$FRAPPE_NIX" sync --check)

echo "== fleet.json"
python3 -I "$root/scripts/check_fleet.py" "$root/fleet.json" "$root/profile.toml"
