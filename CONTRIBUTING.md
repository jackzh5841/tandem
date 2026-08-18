# Contributing to tandem

Thanks for your interest. tandem is a small, deliberately conservative tool, so
contributions are weighed against one rule above all: **never lose unsynced work
and never auto-resolve a conflict.** A change that could force-update, prune, or
silently discard history will not be merged, however convenient.

## Porting to other platforms — please do

tandem is macOS-first only in one place: the background timer. **You are very
welcome to branch and port it to other platforms** — a Linux/systemd version is
the most obvious and wanted.

The OS-specific seam is tiny and isolated:

- `cmd_install` / `cmd_uninstall` — write and load the periodic job. On macOS
  this is a `launchd` plist calling `tandem mirror`. A Linux port adds a
  `systemd --user` timer + service (or a cron entry) doing the same, selected by
  detecting the platform.
- `mtime()` already handles both BSD (`stat -f`) and GNU (`stat -c`) `stat`.

Everything else — `sync`, `mirror`, `adopt`, `serve`, `list`, `status` — is plain
Bash + Git + SSH and should run unchanged on any Unix. If you find a
non-portable construct outside the timer code, that's a bug worth a PR on its
own.

Ways to contribute a port:

- Open a PR that adds the platform branch behind a runtime check, keeping macOS
  working. This is preferred if the change is small and self-contained.
- Or maintain a platform branch (e.g. `linux-systemd`) and open an issue linking
  it, so others can find it while it stabilizes.

## Invariants a change must preserve

- **Fast-forward only.** Bare replication fetches `refs/heads/*` and
  `refs/tags/*` with no leading `+` and no `--prune`. Divergence is reported
  (`DIVERGED — left for review`), never forced.
- **Local is required, network is best effort.** A remote on the local
  filesystem must succeed; a remote over the network may be away. A run that
  reaches nothing fails (exit 4); it never reports a false success.
- **`serve` stays confined.** It may only run `git-upload-pack`,
  `git-receive-pack`, or `tandem list`, each against a bare repo directly under
  `bare_dir`, and must reject path traversal.
- **`sync` never touches a dirty tree or a diverged history**, and never
  force-pushes.

## Code style

- A single dependency-free Bash script. Target **bash 3.2** (the macOS system
  Bash): indexed arrays only (no associative arrays), guard empty-array
  expansions as `${arr[@]+"${arr[@]}"}`.
- Dependencies are limited to `git`, `ssh`, and standard `awk`/`sed`/coreutils.
- Keep functions small and side effects visible; match the surrounding style.

## Testing

There is no framework; tests are shell scenarios run against sandbox `HOME`s and
local bare repos. Before opening a PR, exercise at least:

- `tandem init`, `tandem adopt`, and `tandem sync` with one reachable local
  remote and one unreachable peer (expect "N of M remotes", exit 0).
- The `serve` filter: it allows the three replication verbs under `bare_dir` and
  rejects traversal, out-of-scope paths, and arbitrary commands.
- The fast-forward guarantee: a mirror with a local-only commit must be left
  untouched when the peer has diverged.

Run the script under `/bin/bash` (3.2) as well as your everyday Bash to catch
version-specific issues.

## Submitting

Keep PRs focused. Explain what changed, why, and what you verified — including
which platforms you tested on.
