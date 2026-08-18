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

It is a small, dependency-free Bash script. macOS-first (uses `launchd` for the
background timer); the sync/mirror commands themselves are plain POSIX-ish shell
and Git.

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
  machine's, fast-forward only. It runs on a `launchd` timer and on demand. This
  is the only step that crosses the network for bare history, so replication does
  not need every machine awake at once.

Each machine has a short name (e.g. `desktop`, `laptop`). Every repo gets one
remote per machine, named after it; the one pointing at *this* machine's bare
directory is the required, local remote.

## Install

```sh
git clone <this repo> ~/src/tandem
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
tandem install    # launchd timer: `tandem mirror` every 5 minutes
tandem mirror     # or run it by hand
tandem status --bares   # what each local mirror currently holds
```

### Letting a peer pull from this machine

For another machine to *pull* your bares, add its key to `~/.ssh/authorized_keys`
restricted to replication only:

```
restrict,command="/home/you/.local/bin/tandem serve" ssh-ed25519 AAAA... peer-key
```

`tandem serve` permits only `git-upload-pack`, `git-receive-pack`, and
`tandem list`, each confined to a bare repo directly under `bare_dir`.

## Commands

| Command | What it does |
| --- | --- |
| `tandem sync` | Sync the current working repo with every machine's remote |
| `tandem mirror` | Pull every peer's bare repos into this machine's, ff-only |
| `tandem adopt` | (Re)point this repo's remotes at the machine it sits on |
| `tandem status [--all\|--bares]` | This repo's remotes / every synced repo / local bares |
| `tandem serve` | SSH forced command for an `authorized_keys` replication key |
| `tandem install` / `uninstall` | Manage the `launchd` mirror timer |
| `tandem init` | Write a starter config |

Environment: `TANDEM_CONFIG` (config path), `TANDEM_NO_ADOPT` (skip the
auto-adopt check). Per-remote `git config remote.<name>.sshCommand` is honored.

## Safety model

- **Fast-forward only.** Bare replication uses `refs/heads/*:refs/heads/*` with no
  leading `+` and no prune. A diverged or rewound branch is rejected and reported
  (`DIVERGED — left for review`), never forced.
- **`tandem sync`** refuses to fast-forward a dirty tree and refuses diverged
  histories; it never force-pushes.
- **`tandem serve`** only ever runs the three replication verbs, only under
  `bare_dir`, and rejects path traversal.

## Limitations

- The background timer is macOS/`launchd` only. `sync`/`mirror`/`serve` work on
  any Unix with Bash and Git; a systemd timer equivalent is left as an exercise.
- Assumes the same `bare_dir` path on every machine (override with
  `remote_bare_dir`).
- New *repositories* are discovered from peers automatically; brand-new
  *branches* replicate, but branch *deletions* do not (by design — nothing is
  pruned).

## License

MIT — see [LICENSE](LICENSE).
