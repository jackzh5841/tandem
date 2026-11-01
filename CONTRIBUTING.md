# Contributing to tandem

Thanks for your interest. tandem is a small, deliberately conservative tool, so
contributions are weighed against one rule above all: **never lose unsynced work
and never auto-resolve a conflict.** A change that could force-update, prune, or
silently discard history will not be merged, however convenient.

## Porting to other platforms — please do

tandem is developed and tested on macOS; Linux has a `systemd --user` timer
since 0.2.0 but 0.4.0 has not been run there, and Windows has never been tried.
**You are very welcome to branch and port it** — a Linux run of
`tests/mirror.sh`, and the two Linux halves below, are the most wanted.

The OS-specific seams are small and isolated:

- `cmd_install` / `cmd_uninstall` — write and load the periodic job: a
  `launchd` plist on macOS, a `systemd --user` timer and service on Linux,
  selected by `uname -s`.
- `on_battery()` reads `pmset`, which is macOS's. A Linux port reads
  `/sys/class/power_supply/*/status`; without one, Linux always reads as mains
  power, which is the safe direction (the run goes ahead).
- `this_machine()` lists this machine's addresses with `ifconfig`. A Linux
  port adds `ip -o addr`; without one, only this machine's names are known.
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
  `git-receive-pack`, `tandem list` or `tandem refs`, each against a bare repo
  directly under `bare_dir`, and must reject path traversal.
- **A skip needs positive evidence.** `mirror` may leave a repository
  unfetched only when the peer's `refs` answer shows nothing moved; anything it
  cannot tell — a repository the peer did not read, a line that is not a sha
  and a well-formed head or tag, a local read that failed, a peer that did not
  answer — is fetched, with the fast-forward-only globs. The peer's words are
  checked before they become a revision or a refspec.
- **Nothing the peer names leaves `bare_dir`.** A name with a slash or a
  leading dot is refused, not made.
- **`sync` never touches a dirty tree or a diverged history**, and never
  force-pushes.

## Code style

- A single dependency-free Bash script. Target **bash 3.2** (the macOS system
  Bash): indexed arrays only (no associative arrays), guard empty-array
  expansions as `${arr[@]+"${arr[@]}"}`.
- Dependencies are limited to `git`, `ssh`, and standard `awk`/`sed`/coreutils.
- Keep functions small and side effects visible; match the surrounding style.

## Testing

`tests/mirror.sh` holds the `mirror` scenarios: a peer that is this machine,
one connection per run, the battery wait, fetching only what moved, the
checks on what the peer says, working trees, `refs`, `serve`, and names that
would escape `bare_dir`. Every command tandem asks about the world — `ssh`,
`scutil`, `hostname`, `ifconfig`, `pmset`, `launchctl` — is a fake on `PATH`,
`HOME` is a temporary directory, and the peer is a folder of real bares served
by the real `tandem serve`; no network is touched and no timer is loaded.

```sh
bash tests/mirror.sh            # your everyday Bash
/bin/bash tests/mirror.sh       # macOS's 3.2, which the script must still run under
DEBUG=1 bash tests/mirror.sh    # a failure prints the run's output and its ssh calls
```

The exit status is the number of failed checks. `TANDEM_UNDER_TEST=<path>`
runs the suite against another copy of the script: before trusting a new
assertion, break the code it guards in a copy and watch it fail. The release
of 0.4.0 did that with fifteen such copies.

`sync`, `adopt` and `init` have no suite yet. Before opening a PR that touches
them, exercise at least, in a sandbox `HOME` with local bare repos:

- `tandem init`, `tandem adopt`, and `tandem sync` with one reachable local
  remote and one unreachable peer (expect "N of M remotes", exit 0).
- The fast-forward guarantee: a mirror with a local-only commit must be left
  untouched when the peer has diverged.

Say which platforms you ran on; a Linux run of the suite is itself a
contribution.

## Submitting

Keep PRs focused. Explain what changed, why, and what you verified — including
which platforms you tested on.
