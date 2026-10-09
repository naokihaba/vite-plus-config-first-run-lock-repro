# Vite+ First-Run Config Lock Reproduction

Run the first Vite+ configuration command at the same time in the worktrees of a new Git repository to check for Git config lock failures.

Related issue: [voidzero-dev/vite-plus#2849](https://github.com/voidzero-dev/vite-plus/issues/2849)

Issue #2849 is about runs that change nothing. This reproduction is about the first run, which must write the Git config. The fix for #2849 does not change the first run.

## Run the reproduction

You need Node.js, Git, Bash, and pnpm. This reproduction was tested on macOS.

```sh
pnpm install --ignore-scripts
pnpm repro
```

To use another Vite+ build, supply the path to its local CLI:

```sh
bash reproduce.sh /path/to/vite-plus/packages/cli/bin/vp
```

This command uses the version at the supplied path.

## Run the global CLI

Use an existing global Vite+ installation:

```sh
bash reproduce.sh --global
```

The default global binary is `$HOME/.vite-plus/bin/vp`. To use another location:

```sh
bash reproduce.sh --global /path/to/global/vp
```

You can also run `pnpm repro:global`.

## Options

Set these environment variables to change the test:

| Variable | Default | Meaning |
| --- | --- | --- |
| `REPRO_WORKTREES` | `2` | Number of worktrees in each round, including the main worktree |
| `REPRO_ROUNDS` | `20` | Number of rounds |
| `REPRO_NODE_VERSION` | `24.21.0` | Exact Node.js version written to `.node-version` in each worktree |

```sh
REPRO_WORKTREES=4 REPRO_ROUNDS=15 bash reproduce.sh
```

The global CLI uses `.node-version` to select its runtime. An exact installed version prevents a version-index request, which can delay startup and change the timing between commands. Local mode uses `node` from PATH; `.node-version` does not change that process's runtime.

## Read the results

In each round, the script creates a new repository and its linked worktrees in a temporary directory. It then runs one configuration command in each worktree at the same time. Each command is a first run, because the repository is new. The script does not change existing repositories.

The temporary directory contains, for each round, the logs, the exit codes, and the Git config values after the round. It also contains `summary.json`.

The script returns these exit codes:

- `0`: At least one Git config lock failure occurred.
- `2`: No Git config lock failure occurred.
- `1`: A run failed for another reason.

A lock failure produces this error:

```text
error: could not lock config file .git/config: File exists
```

`rounds_with_incomplete_config` in `summary.json` counts the rounds in which the shared Git config did not contain all three values after the round. A value of `0` shows that a successful run wrote each value, also when other runs failed.

The number of failures can change between runs because the failures depend on process timing.

See [REPORT.md](REPORT.md) for the results and test scope. Saved logs are in [evidence](evidence).
