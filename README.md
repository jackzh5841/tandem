# tandem

Keep your own Git repositories in step across your own machines — a laptop and a
desktop, say — with **no third-party host** and **no chance of silently losing
unsynced work**.

Each machine keeps its repositories' *bare* copies under one directory. `tandem`
replicates those bares between machines over SSH, and syncs your working trees
against them. It is deliberately conservative: every fetch is **fast-forward
only**, so a history that has diverged is reported for you to resolve rather than
force-overwritten, and a machine that is asleep or off the network is treated as
"away," never as an error.

It is a small, dependency-free Bash script, developed and tested on macOS.
Linux is supported with caution and Windows not at all; see
[Platforms](#platforms).

## Why this exists

The bare-repo-over-SSH pattern is well known (see
[alexwlchan](https://alexwlchan.net/2026/bare-git/) and countless blog posts).
tandem packages it with an opinion, and fills a gap the existing tools leave:

- **Offline-first, two-way, for personal machines.** Unlike server-oriented
  mirrors such as [RalfJung/git-mirror](https://www.ralfj.de/projects/git-mirror/)
  (post-receive hooks between always-on hosts), tandem assumes machines come and
  go, and each pulls from the others when it can.
- **Git history, not files.** Unlike [Syncthing](https://syncthing.net/) a
  folder of bares, or file-level laptop/desktop mirrors like
  [stephenh/mirror](https://github.com/stephenh/mirror), tandem lets Git resolve
  Git — no file-level conflicts on `.git` internals.
- **Safety as the default.** Fast-forward only, no pruning of branches, refuses
  to touch a dirty tree, and never force-pushes. Divergence is surfaced, not
  resolved behind your back.

It is not a hosted forge (use [Gitea](https://about.gitea.com/) /
[Forgejo](https://forgejo.org/) for that) and not a one-way pull-into-a-directory
tool (that is Kubernetes'
[git-sync](https://github.com/kubernetes/git-sync)).

## How it works

```
   working repo  ──tandem sync──▶  local bare  ──tandem mirror──▶  peer's bare
   (your edits)   ◀──────────────  (this machine)  ◀────────────   (other machine)
```

- **`tandem sync`** synchronizes the *working repo* you are in with every
  machine's remote. It classifies each remote by URL: the one on the local
  filesystem is **required**, the ones reached over the network are **best
  effort**. So the same command is local-first on every machine.
- **`tandem mirror`** replicates the *bare* repositories from each peer into this
  machine's, fast-forward only. It runs on a timer and on demand. This is the
  only step that crosses the network for bare history, so replication does not
  need every machine awake at once. A run holds one SSH connection per peer,
  asks the peer which refs it has (`tandem refs`), and fetches only the
  repositories that moved there, so a quiet run fetches nothing.

Each machine has a short name (e.g. `desktop`, `laptop`). Every repo gets one
remote per machine, named after it; the one pointing at *this* machine's bare
directory is the required, local remote.

## Install

```sh
git clone https://github.com/jackzh5841/tandem ~/src/tandem
ln -s ~/src/tandem/tandem ~/.local/bin/tandem   # anywhere on your PATH
tandem init                                     # writes ~/.config/tandem/config
$EDITOR ~/.config/tandem/config
```

Minimal config on the machine named `desktop`, with a laptop peer:

```ini
machine = desktop
bare_dir = ~/GitRemotes
projects_dir = ~/Projects
peer laptop = laptop.local
```

On the laptop, the same file with `machine = laptop` and `peer desktop = ...`.
A peer line must name another machine, never the one the file is on; `install`
refuses one that does, and `mirror` skips it and says so. On a laptop,
`battery_interval = 1800` (the default, in seconds) is how long a mirror run
waits after the previous one while on battery; `0` disables the wait. Every key
is described in [config.example](config.example).

## Use

In a project, once per machine:

```sh
tandem adopt      # point the repo's remotes at this machine (local) + peers
tandem sync       # fetch, fast-forward if safe, push to every reachable remote
```

`tandem sync` auto-runs `adopt` when it notices a checkout that came from another
machine, so day to day it is just `git commit` then `tandem sync`.

Keep the bares flowing between machines automatically:

```sh
tandem install    # background timer: `tandem mirror` every 5 minutes
                  # (launchd on macOS, systemd --user timer on Linux);
                  # on battery (macOS), at most every 30 minutes
tandem mirror     # or run it by hand
tandem status --bares   # what each local mirror currently holds
```

On Linux, view the timer's output with `journalctl --user -u tandem-mirror`, and
run `loginctl enable-linger "$USER"` if you want it to run while you're logged out.

### Letting a peer pull from this machine

For another machine to *pull* your bares, add its key to `~/.ssh/authorized_keys`
restricted to replication only:

```
restrict,command="/home/you/.local/bin/tandem serve" ssh-ed25519 AAAA... peer-key
```

`tandem serve` permits only `git-upload-pack`, `git-receive-pack`,
`tandem list` and `tandem refs`, each confined to a bare repo directly under
`bare_dir`. A peer that cannot answer `tandem refs` — an older tandem, a key
restricted by an older `serve`, no `tandem` on its PATH — is still mirrored:
every repository is fetched, as before 0.4.0, and the log says so.

## Commands

| Command | What it does |
| --- | --- |
| `tandem sync` | Sync the current working repo with every machine's remote |
| `tandem mirror` | Pull every peer's bare repos into this machine's, ff-only |
| `tandem adopt` | (Re)point this repo's remotes at the machine it sits on |
| `tandem status [--all\|--bares]` | This repo's remotes / every synced repo / local bares |
| `tandem list` / `tandem refs` | This machine's bare names / their heads and tags, for a peer's `mirror` |
| `tandem serve` | SSH forced command for an `authorized_keys` replication key |
| `tandem install` / `uninstall` | Manage the mirror timer (`launchd` or `systemd --user`) |
| `tandem init` | Write a starter config |

Environment: `TANDEM_CONFIG` (config path), `TANDEM_NO_ADOPT` (skip the
auto-adopt check). Per-remote `git config remote.<name>.sshCommand` is honored.

## Safety model

- **Fast-forward only.** Bare replication uses `refs/heads/*:refs/heads/*` with no
  leading `+` and no prune. A diverged or rewound branch is rejected and reported
  (`DIVERGED — left for review`), never forced.
- **`tandem sync`** refuses to fast-forward a dirty tree and refuses diverged
  histories; it never force-pushes.
- **`tandem serve`** only ever runs the four replication verbs, only under
  `bare_dir`, and rejects path traversal.
- **A skip needs positive evidence.** `mirror` leaves a repository unfetched
  only when the peer's own `refs` answer shows nothing moved; a repository the
  peer did not read, a line it cannot parse, or a local read that failed is
  fetched. A bare that is merely *ahead* of the peer is not fetched either,
  since the peer takes that on its own run — it used to be reported as
  `DIVERGED` every run until the peer caught up.

## Platforms

- **macOS** is where tandem is developed and tested. Every release is run
  between two Macs, and the scenarios in `tests/mirror.sh` run under the
  system Bash 3.2.
- **Linux: use with caution.** The `systemd --user` timer (since 0.2.0) is
  believed to work, but 0.4.0 has not been run on Linux. Two of its features
  are macOS-shaped by construction: the battery wait reads `pmset`, so on
  Linux a mirror run always goes ahead at the timer's interval; and the check
  that a peer line names this machine reads `ifconfig` for its addresses, so
  on a Linux without it only this machine's *names* are recognised, and a
  peer given as its own IP address is tried every run, as before, and fails
  harmlessly.
- **Windows** is not supported and has never been tried. Under WSL, tandem is
  a Linux program.
- Anything else with Bash, Git and SSH should run `sync`, `mirror` and
  `serve`; schedule `tandem mirror` from cron. Ports to other schedulers are
  welcome — the OS-specific code is isolated to `install`/`uninstall`; see
  [CONTRIBUTING.md](CONTRIBUTING.md).

## Limitations

- Assumes the same `bare_dir` path on every machine (override with
  `remote_bare_dir`).
- New *repositories* are discovered from peers automatically; brand-new
  *branches* replicate, but branch *deletions* do not (by design — nothing is
  pruned).

## Contributing

Ports to other platforms and other help are welcome — the one rule is that a
change must never be able to lose unsynced work or auto-resolve a conflict. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the invariants, the code style (single
Bash script, bash 3.2), and how to test.

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Jack Zhang.
