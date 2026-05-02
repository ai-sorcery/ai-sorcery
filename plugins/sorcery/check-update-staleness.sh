#!/usr/bin/env bash
#
# check-update-staleness — refuse a commit when any lockfile in the repo has
# not been touched in more than STALE_DAYS (default 7). The intent is to nudge
# the next dependency-refresh sweep into happening before drift turns into a
# debugging session.
#
# Self-contained: nothing outside the repository is referenced, so the hook
# works for any dev who activates it — no dependency on the sorcery plugin
# being installed.
#
# Bypass:
#   git commit --no-verify ...           # skip this hook (and any others)
#   STALE_DAYS=14 git commit ...         # widen the threshold for one commit
#   touch <lockfile>                     # I checked, nothing to update
#
# Reset clock the right way:
#   <package-manager> update             # bump deps; lockfile mtime moves

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
threshold_days="${STALE_DAYS:-7}"

if ! [[ "$threshold_days" =~ ^[0-9]+$ ]]; then
    echo "[periodic-upgrades] STALE_DAYS must be a non-negative integer (got '$threshold_days')" >&2
    exit 2
fi

# Lockfiles by ecosystem. Add to this list when a new one matters; the script
# silently no-ops in any repo where none of these are present.
candidates=(
    bun.lock bun.lockb
    package-lock.json yarn.lock pnpm-lock.yaml
    Cargo.lock
    go.sum
    Gemfile.lock
    poetry.lock uv.lock Pipfile.lock
    composer.lock
    Package.resolved
    mix.lock
)

# macOS stat differs from GNU stat — pick the right flag once up front rather
# than branching per call.
if stat -f "%m" / >/dev/null 2>&1; then
    stat_mtime() { stat -f "%m" "$1"; }
else
    stat_mtime() { stat -c "%Y" "$1"; }
fi

now=$(date +%s)
threshold_seconds=$((threshold_days * 86400))

stale_lines=()
found_any=0
for name in "${candidates[@]}"; do
    path="$repo_root/$name"
    [ -f "$path" ] || continue
    found_any=1

    mtime=$(stat_mtime "$path")
    age_seconds=$((now - mtime))
    if (( age_seconds <= threshold_seconds )); then
        continue
    fi
    age_days=$((age_seconds / 86400))
    stale_lines+=("  $name — last touched $age_days days ago")
done

if [ "$found_any" -eq 0 ]; then
    # No recognised lockfile in this repo. Nothing to enforce.
    exit 0
fi

if [ "${#stale_lines[@]}" -eq 0 ]; then
    exit 0
fi

cat >&2 <<MSG

==================================================================
[periodic-upgrades] Stale dependencies detected
==================================================================
The following lockfile(s) have not been touched in more than $threshold_days days:

$(printf '%s\n' "${stale_lines[@]}")

Run an upgrade sweep — invoke the enforcing-periodic-upgrades skill,
or follow the quick path for the package manager(s) in use:

  bun          bun upgrade && bun update
  npm          npm update
  yarn         yarn upgrade
  pnpm         pnpm update
  cargo        cargo update
  go           go get -u ./... && go mod tidy
  bundler      bundle update
  poetry       poetry update
  uv           uv lock --upgrade
  pipenv       pipenv update
  composer     composer update
  swiftpm      swift package update
  mix          mix deps.update --all

Then run your tests, stage the lockfile, and commit again — this hook
will pass because the lockfile mtime is now fresh.

If you have a real reason to skip (emergency hotfix, hand-edited dep):
  git commit --no-verify ...

If everything is current and the lockfile mtime is just stale:
  touch <lockfile>
==================================================================
MSG
exit 1
