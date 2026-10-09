#!/usr/bin/env bash
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd)
cd "$script_dir"
mode=local
if [ "${1:-}" = --global ]; then
  mode=global
  cli="${2:-$HOME/.vite-plus/bin/vp}"
else
  cli="${1:-}"
  if [ -z "$cli" ]; then
    cli=$(node -p 'require("node:path").resolve(require("node:path").dirname(require.resolve("vite-plus")), "../bin/vp")')
  fi
fi
if [ ! -f "$cli" ]; then
  echo "CLI file not found: $cli" >&2
  exit 1
fi
cli=$(cd "$(dirname "$cli")" && pwd)/$(basename "$cli")
if [ "$mode" = global ]; then
  cli_command=("$cli")
else
  cli_command=(node "$cli")
fi
worktrees="${REPRO_WORKTREES:-2}"
rounds="${REPRO_ROUNDS:-20}"
node_version="${REPRO_NODE_VERSION:-24.21.0}"
if [[ ! "$worktrees" =~ ^[0-9]+$ ]] || [ "$worktrees" -lt 2 ]; then
  echo "REPRO_WORKTREES must be an integer of 2 or more." >&2
  exit 1
fi
if [[ ! "$rounds" =~ ^[0-9]+$ ]] || [ "$rounds" -lt 1 ]; then
  echo "REPRO_ROUNDS must be an integer of 1 or more." >&2
  exit 1
fi
if [[ ! "$node_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "REPRO_NODE_VERSION must be an exact version, such as 24.21.0." >&2
  exit 1
fi

repro_dir=$(mktemp -d "${TMPDIR:-/tmp}/vp-first-run.XXXXXX")
echo "Logs: $repro_dir"
echo "Mode: $mode; worktrees: $worktrees; rounds: $rounds; .node-version: $node_version"
expected_config=$(printf '.vite-hooks/_\n.vite-hooks\n.')

run_config() {
  local round_dir="$1" tree="$2" code=0
  (cd "$round_dir/tree-$tree" && "${cli_command[@]}" config --no-agent) > "$round_dir/tree-$tree.log" 2>&1 || code=$?
  echo "$code" > "$round_dir/tree-$tree.status"
}

incomplete=0
for ((round=1; round<=rounds; round++)); do
  round_dir="$repro_dir/round-$round"
  mkdir "$round_dir"
  # A new repository in each round makes each configuration command a first run.
  git init -q "$round_dir/tree-1"
  git -C "$round_dir/tree-1" -c user.name=Repro -c user.email=repro@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m init
  for ((tree=2; tree<=worktrees; tree++)); do
    git -C "$round_dir/tree-1" -c core.hooksPath=/dev/null worktree add -q --detach "$round_dir/tree-$tree" HEAD
  done
  for ((tree=1; tree<=worktrees; tree++)); do
    # An exact version avoids version-index requests before global CLI delegation.
    printf '%s\n' "$node_version" > "$round_dir/tree-$tree/.node-version"
  done
  for ((tree=1; tree<=worktrees; tree++)); do
    run_config "$round_dir" "$tree" &
  done
  wait
  {
    git -C "$round_dir/tree-1" config --local core.hooksPath || true
    git -C "$round_dir/tree-1" config --local vp.hooks.dir || true
    git -C "$round_dir/tree-1" config --local vp.hooks.prefix || true
  } > "$round_dir/config-after.txt"
  if [ "$(cat "$round_dir/config-after.txt")" != "$expected_config" ]; then
    incomplete=$((incomplete + 1))
  fi
  # Keep the logs and remove the repositories.
  for ((tree=worktrees; tree>=1; tree--)); do
    rm -rf "$round_dir/tree-$tree"
  done
done

runs=$((worktrees * rounds))
failed=0
lock_failed=0
for result in "$repro_dir"/round-*/*.status; do
  if [ "$(cat "$result")" != 0 ]; then
    failed=$((failed + 1))
    if grep -q 'could not lock config file' "${result%.status}.log"; then
      lock_failed=$((lock_failed + 1))
    fi
  fi
done
printf '{"mode":"%s","worktrees":%s,"rounds":%s,"runs":%s,"failures":%s,"lock_failures":%s,"rounds_with_incomplete_config":%s}\n' \
  "$mode" "$worktrees" "$rounds" "$runs" "$failed" "$lock_failed" "$incomplete" > "$repro_dir/summary.json"
cat "$repro_dir/summary.json"
if [ "$failed" -ne "$lock_failed" ]; then
  echo "A run failed for a reason other than a Git config lock." >&2
  exit 1
fi
if [ "$lock_failed" -eq 0 ]; then
  echo "No lock failure occurred. Run the script again." >&2
  exit 2
fi
