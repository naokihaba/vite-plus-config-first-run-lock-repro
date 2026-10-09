# Reproduction Results for First-Run Config Lock Failures

The first `vp config` run failed with Git config lock errors when it ran at the same time in the worktrees of a new repository. Vite+ 1.0.0 and a local build with the fix for #2849 both failed.

## Test environment

| Item | Value |
| --- | --- |
| OS | macOS 27.0, arm64 |
| Git | 2.55.0 |
| Node.js | v24.20.0 from PATH in local mode; v24.21.0 in global mode |
| Vite+ | 1.0.0, and a local build with the fix for #2849 |
| Command | `vp config --no-agent` |

## Reproduction steps

1. Create a repository with an empty commit.
2. Add linked worktrees.
3. Run the configuration command at the same time in all worktrees. No worktree has run the command before.
4. Check the exit code and log for each command, and the Git config values after the round.
5. Do steps 1 to 4 again with a new repository for each round.

Use [reproduce.sh](reproduce.sh) to run these steps. See [README.md](README.md) for dependency installation instructions.

## Results

| Execution | Worktrees | Rounds | Commands | Lock failures | Rounds with incomplete config |
| --- | ---: | ---: | ---: | ---: | ---: |
| Local CLI, Vite+ 1.0.0 | 2 | 20 | 40 | 7 | 0 |
| Local CLI, Vite+ 1.0.0 | 4 | 15 | 60 | 40 | 0 |
| Global CLI, Vite+ 1.0.0 | 2 | 20 | 40 | 10 | 0 |
| Local CLI, build with the fix for #2849 | 2 | 20 | 40 | 12 | 0 |
| Local CLI, build with the fix for #2849 | 4 | 15 | 60 | 33 | 0 |

All failures were Git config lock failures:

```text
error: could not lock config file .git/config: File exists
```

Commands in a linked worktree produced errors that named the shared config file in the main worktree:

```text
error: could not lock config file /private/tmp/vp-first-run.XXXXXX/round-N/tree-1/.git/config: File exists
```

The evidence for each execution is in [evidence](evidence). Each directory contains `summary.json` and one directory for each round.

These are individual test results. They do not establish a fixed failure rate, and they do not compare the failure rates of the builds.

## The Git config was complete after each round

After each round, the script read these values from the shared Git config:

```text
core.hooksPath = .vite-hooks/_
vp.hooks.dir = .vite-hooks
vp.hooks.prefix = .
```

All three values were present after each round of each execution. In each round, the commands write the same values. Thus, when a command failed on the lock, a different command wrote the value.

The failed commands did not need to write. They failed because Git does not wait for `config.lock`.

## Relation to issue #2849

Issue #2849 reports that `vp config` writes the Git config on each run, also when no value changes. The fix for that issue reads the local value before each write and skips a write that changes nothing.

The first run in a new repository changes the values, so it must write. The fix for #2849 does not remove those writes. The results for the build with that fix show that concurrent first runs continue to fail.

## Test scope

These tests confirm Git config lock failures and configuration command failures for concurrent first runs. They do not test pnpm installation failures through a `prepare` script, a global CLI build with the fix for #2849, or a fix for the first run.

The build with the fix for #2849 was a local, unpublished build of the Vite+ repository.

A fresh dependency installation was tested with `pnpm install --ignore-scripts`.
