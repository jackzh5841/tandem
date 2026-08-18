# Changelog

All notable changes to tandem are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [0.2.1] — 2026-08-18

### Fixed

- `sync` no longer auto-adopts a repository that is hosted elsewhere. The
  auto-adopt check claimed any repo under `projects_dir`, so running
  `tandem sync` inside a project that only had an external `origin` (e.g. a
  GitHub clone) swept it into the mesh — adding remotes and creating a stray
  bare. It now claims only a *fresh* repo with no remotes at all; a repo that
  already has an origin is left alone unless `tandem adopt` is run explicitly.

## [0.2.0] — 2026-08-18

### Added

- Linux support for the background timer: `tandem install` / `tandem uninstall`
  now write a `systemd --user` timer on Linux and the `launchd` agent on macOS,
  selected by platform. On other systems they explain how to schedule
  `tandem mirror` from cron.

### Fixed

- `mirror` peer discovery: the `find` fallback used to list a peer's bares was
  missing its `-exec ... \;` terminator, so it failed on peers reached through a
  plain shell (the primary `tandem list` path was unaffected).

## [0.1.0] — 2026-08-18

Initial release.

### Added

- `tandem sync` — synchronize the current working repository with every machine's
  remote. The remote on the local filesystem is required; network peers are best
  effort. Fast-forwards a clean tree, refuses a dirty tree or a diverged history,
  never force-pushes. Auto-adopts a checkout that came from another machine.
- `tandem mirror` — replicate each peer's bare repositories into this machine's,
  fast-forward only. A diverged history is reported and left untouched, never
  force-updated or pruned.
- `tandem adopt` — (re)point a repository's remotes at the machine it sits on:
  the local bare becomes required, the other machines best-effort peers.
- `tandem serve` — an SSH forced command for an `authorized_keys` replication
  key, confined to `git-upload-pack`, `git-receive-pack`, and `tandem list`
  under `bare_dir`.
- `tandem status` (`--all`, `--bares`), `tandem list`, `tandem init`.
- `tandem install` / `tandem uninstall` — a `launchd` timer running
  `tandem mirror` (macOS).
- Config-driven for any number of machines via `~/.config/tandem/config`.

[0.2.1]: https://github.com/jackzh5841/tandem/releases/tag/v0.2.1
[0.2.0]: https://github.com/jackzh5841/tandem/releases/tag/v0.2.0
[0.1.0]: https://github.com/jackzh5841/tandem/releases/tag/v0.1.0
