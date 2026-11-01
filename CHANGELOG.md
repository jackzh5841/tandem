# Changelog

All notable changes to tandem are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [0.4.0] — 2026-11-01

### Added

- `tandem refs`: every local bare's heads and tags, one line each, which
  `tandem serve` now permits alongside `list`. A peer's `mirror` compares it
  with its own copies and fetches only the repositories that moved; a quiet
  run fetches nothing (`unchanged=N` in the summary). A peer that cannot answer
  — an older tandem, a key restricted by an older `serve` — has every
  repository fetched as before, and the log says so.
- `battery_interval` (config, default 1800 seconds): on battery, a mirror run
  waits this long after the previous one began instead of running at the
  timer's every tick. Stretched, not stopped — a laptop's bares are its travel
  copy. Read from `pmset`, so macOS only; elsewhere the timer's interval is
  the only one. `0` disables it.
- `tests/mirror.sh`: the mirror scenarios as a shell suite, with every command
  that touches the world faked and the peer served by the real `tandem serve`.

### Changed

- `mirror` holds one SSH connection per peer per run (`ControlMaster`), shared
  by the probe, the listing, the refs and every fetch. A run over 24
  repositories went from one handshake each to one in all.
- `install` refuses a peer line that names the machine it is on, and `mirror`
  skips one, saying which line to remove. A laptop ran a timer naming itself
  every five minutes for two months with nothing in the log but
  "unavailable".
- A mirror that is merely ahead of its peer is no longer fetched, and so no
  longer reported `DIVERGED` run after run until the peer caught up.
- A repository that fails is named in the summary with git's first line; a
  name from the peer that is not one path component (`../x.git`, `.x.git`)
  is refused rather than made.
- The README states the platforms plainly: macOS tested, Linux with caution,
  Windows not supported.

## [0.3.1] — 2026-08-21

### Fixed

- `mirror` no longer reports a healthy peer as unavailable when its SSH key is
  restricted to `tandem serve`. The reachability probe ran `true` on the peer,
  which a replication-only key refuses; now only ssh's own failure (exit 255)
  counts as unreachable.
- `adopt` removes a leftover `origin` that duplicates one of the machine
  remotes it just set — the remnant of cloning a bare directly. An `origin`
  pointing anywhere else (e.g. a hosting provider) is never touched.

## [0.3.0] — 2026-08-19

### Added

- Colored outcome messages: success prints green, warnings (an unreachable
  peer, a diverged or skipped branch, a partial sync) yellow, and errors red.
  The `mirror` summary line is colored by its worst outcome. Color is applied
  only when the stream is a terminal, so timer logs and pipes stay plain, and
  setting `NO_COLOR` disables it everywhere. Message text, streams, and exit
  codes are unchanged.

## [0.2.2] — 2026-08-18

### Changed

- Clearer message when `sync` is run in a repository that has remotes but none
  are tandem machines. Instead of "none of these machine remotes… run adopt", it
  now says the repository is hosted elsewhere and suggests `git push` (with
  `tandem adopt` offered only as the way to deliberately add it to tandem). A
  repository with no remotes at all still points you to `tandem adopt`.

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

[0.4.0]: https://github.com/jackzh5841/tandem/releases/tag/v0.4.0
[0.3.1]: https://github.com/jackzh5841/tandem/releases/tag/v0.3.1
[0.3.0]: https://github.com/jackzh5841/tandem/releases/tag/v0.3.0
[0.2.2]: https://github.com/jackzh5841/tandem/releases/tag/v0.2.2
[0.2.1]: https://github.com/jackzh5841/tandem/releases/tag/v0.2.1
[0.2.0]: https://github.com/jackzh5841/tandem/releases/tag/v0.2.0
[0.1.0]: https://github.com/jackzh5841/tandem/releases/tag/v0.1.0
