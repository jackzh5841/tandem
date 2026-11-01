#!/usr/bin/env bash
# tests/mirror.sh — scenarios for `tandem mirror`: a peer that is this machine
# is skipped and refused by install; a run holds one SSH connection; on
# battery a run waits; a run fetches only what moved on the peer; the names
# a peer answers with stay under bare_dir; `refs` and `serve` keep their
# shapes.
#
# Every command tandem asks about the world — ssh, scutil, hostname, ifconfig,
# pmset, launchctl — is a fake on PATH, so no network is touched and no timer
# is loaded; HOME is a temporary directory. The peer is a folder of real bare
# repositories served by the real `tandem serve`, reached through the fake
# ssh. Run with the Bash you ship on: `bash tests/mirror.sh` and
# `/bin/bash tests/mirror.sh` (3.2 on macOS). Exit status is the number of
# failed checks.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TANDEM="${TANDEM_UNDER_TEST:-$HERE/../tandem}"   # a mutant, for tests/mutations
PASSED=0; FAILED=0; CURRENT=''

check() {  # check <what> <command...>: the command's success is the claim
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then PASSED=$((PASSED + 1)); return; fi
    FAILED=$((FAILED + 1)); printf 'FAIL  %s: %s\n' "$CURRENT" "$what" >&2
    if [ -n "${DEBUG:-}" ]; then
        printf -- '--- output\n' >&2; cat "$OUT" >&2
        printf -- '--- connections\n' >&2; connections >&2
    fi
}
saw()     { grep -q -- "$1" "$OUT"; }           # saw <text>: in the run's output
not_saw() { ! grep -q -- "$1" "$OUT"; }
no_call() { ! grep -q -- "$1" "$LOG" 2>/dev/null; }   # no_call <text>: no fake was asked that
count_is() { [ "$(printf '%s' "$2" | grep -c .)" -eq "$1" ]; }

# ---------------------------------------------------------------- fakes
FAKE_SSH='#!/bin/bash
printf "ssh %s\n" "$*" >> "$FAKE_LOG"
op= control=
while [ $# -gt 0 ]; do
    case "$1" in
        -G) op=G; shift ;;
        -O) op=O; shift 2 ;;
        -o) case "$2" in ControlPath=*) control="${2#ControlPath=}" ;; esac; shift 2 ;;
        -*) shift ;;
        *)  break ;;
    esac
done
host="$1"; shift
if [ "$op" = G ]; then
    [ -n "${FAKE_SSH_CONFIG_BROKEN:-}" ] && exit 255
    resolved="${host##*@}"
    for pair in ${FAKE_HOSTNAMES:-}; do
        [ "${pair%%=*}" = "$resolved" ] && { resolved="${pair#*=}"; break; }
    done
    printf "host %s\nuser someone\nhostname %s\nport 22\n" "$host" "$resolved"; exit 0
fi
[ "$op" = O ] && exit 0
case "$*" in
    true)
        [ -n "${FAKE_UNREACHABLE:-}" ] && exit 255
        # Bind a socket where a master would, from inside its folder: a
        # socket path holds 104 bytes.
        if [ -n "$control" ]; then
            (cd "${control%/*}" && python3 -c "import socket; socket.socket(socket.AF_UNIX).bind(\"fakehash\")")
        fi
        exit 0 ;;
esac
# A peer that serves: each request goes to the real `tandem serve` with the
# peer'"'"'s own config, as an authorized_keys command sends it. FAKE_OLD_PEER
# refuses `refs` the way an older serve does; FAKE_REFS_FORGED answers it
# with that text instead of the truth; FAKE_NAMES answers `list` directly.
if [ -n "${FAKE_PEER_CONFIG:-}" ]; then
    case "$*" in
        "tandem refs")
            [ -n "${FAKE_OLD_PEER:-}" ] && { echo "This key is restricted to Git replication." >&2; exit 126; }
            [ -n "${FAKE_REFS_FORGED:-}" ] && { printf "%s\n" "$FAKE_REFS_FORGED"; exit 0; } ;;
        "tandem list")
            [ -n "${FAKE_NAMES:-}" ] && { printf "%s\n" $FAKE_NAMES; exit 0; } ;;
    esac
    TANDEM_CONFIG="$FAKE_PEER_CONFIG" SSH_ORIGINAL_COMMAND="$*" exec "$FAKE_TANDEM" serve
fi
case "$*" in
    "tandem list") printf "%s\n" ${FAKE_NAMES:-}; exit 0 ;;
esac
exit 255
'
FAKE_SCUTIL='#!/bin/bash
if [ "$*" = "--get LocalHostName" ] && [ -n "${FAKE_LOCALHOSTNAME:-}" ]; then printf "%s\n" "$FAKE_LOCALHOSTNAME"; exit 0; fi
exit 1
'
FAKE_HOSTNAME='#!/bin/bash
if [ "${1:-}" = -s ]; then printf "%s\n" "${FAKE_HOSTNAME%%.*}"; else printf "%s\n" "$FAKE_HOSTNAME"; fi
'
# The shapes macOS prints: a zone on link-local addresses, and Tailscale's
# point-to-point utun with its 100.x and fd7a: addresses.
FAKE_IFCONFIG='#!/bin/bash
cat <<IFCONFIG
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
	inet 127.0.0.1 netmask 0xff000000
	inet6 ::1 prefixlen 128
	inet6 fe80::1%lo0 prefixlen 64 scopeid 0x1
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet6 fe80::1c2d:3e4f:5a6b:7c8d%en0 prefixlen 64 secured scopeid 0xe
	inet 192.168.1.42 netmask 0xffffff00 broadcast 192.168.1.255
utun4: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1280
	inet 100.64.0.7 --> 100.64.0.7 netmask 0xffffffff
	inet6 fd7a:115c:a1e0::7 prefixlen 48
IFCONFIG
'
FAKE_PMSET='#!/bin/bash
[ -n "${FAKE_POWER:-}" ] || exit 1
printf "Now drawing from '"'"'%s'"'"'\n" "$FAKE_POWER"
[ "$FAKE_POWER" = "Battery Power" ] && printf " -InternalBattery-0 (id=1)\t44%%; discharging; 2:21 remaining present: true\n"
exit 0
'
FAKE_LAUNCHCTL='#!/bin/bash
printf "launchctl %s\n" "$*" >> "$FAKE_LOG"
'

# ---------------------------------------------------------------- sandbox
# This machine is Laptop; `laptop` reaches it and `desktop` the other.
setup() {  # setup <scenario name>
    CURRENT="$1"
    [ -n "${TMP:-}" ] && rm -rf "$TMP"
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/tandem-test.XXXXXX")"
    HOME_DIR="$TMP/home"; BARES="$TMP/GitRemotes"; PROJECTS="$TMP/Projects"
    BIN="$TMP/bin"; LOG="$TMP/calls.log"; OUT="$TMP/out"; PEER="$TMP/peer"
    mkdir -p "$HOME_DIR" "$PROJECTS" "$BIN" "$PEER"
    local name
    for name in ssh scutil hostname ifconfig pmset launchctl; do
        eval "printf '%s' \"\$FAKE_$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')\"" > "$BIN/$name"
        chmod 700 "$BIN/$name"
    done
    export HOME="$HOME_DIR" PATH="$BIN:$ORIGINAL_PATH" NO_COLOR=1
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    export TANDEM_CONFIG="$TMP/config" TANDEM_CONTROL_ROOT="$TMP"
    export FAKE_LOG="$LOG" FAKE_TANDEM="$TANDEM" FAKE_PEER_CONFIG="$TMP/peer-config"
    export FAKE_LOCALHOSTNAME=Laptop FAKE_HOSTNAME=Laptop.local
    export FAKE_HOSTNAMES="laptop=laptop desktop=desktop"
    export FAKE_POWER="AC Power" FAKE_NAMES="" FAKE_UNREACHABLE="" FAKE_OLD_PEER="" FAKE_REFS_FORGED=""
    unset FAKE_SSH_CONFIG_BROKEN
    config "peer studio = desktop"
    # The peer's own config, read by the real serve the fake ssh runs.
    printf 'machine = studio\nbare_dir = %s\nprojects_dir = %s/none\n' "$PEER" "$PEER" > "$TMP/peer-config"
    STAMP="$HOME_DIR/.local/state/tandem/mirror-studio.began"
}
config() {  # config <extra lines...>: this machine's config, bares at $BARES
    {
        printf 'machine = macbook\nbare_dir = %s\nprojects_dir = %s\ntimeout = 1\nremote_bare_dir = %s\n' \
            "$BARES" "$PROJECTS" "$PEER"
        printf '%s\n' "$@"
    } > "$TMP/config"
}
run() {  # run <args...>: tandem, output in $OUT, status in $STATUS
    "$TANDEM" "$@" > "$OUT" 2>&1; STATUS=$?
}
fresh_log() { rm -f "$LOG"; }
connections() {  # ssh calls that reach a host: not -G (reads config), not -O (a local master)
    [ -f "$LOG" ] || return 0
    grep '^ssh ' "$LOG" | grep -v -- ' -G ' | grep -v -- ' -O '
}
probed()  { connections | grep -q ' desktop true$'; }
fetched() {  # the bares this run fetched from, by the path each fetch asked for
    connections | grep 'git-upload-pack' | sed "s/.*git-upload-pack '//; s/'\$//" | xargs -n1 basename 2>/dev/null | sort | tr '\n' ' '
}
control_paths() { connections | tr ' ' '\n' | grep '^ControlPath=' | sed 's/ControlPath=//' | sort -u; }

sha_of() { git -C "$1" rev-parse --verify -q "$2" 2>/dev/null; }
MADE=0
commit() {  # commit <bare> [<ref>]: a new commit on <ref> of the bare, made if absent
    local repo="$1" ref="${2:-refs/heads/main}" tree parent new
    [ -d "$repo" ] || git init --quiet --bare --initial-branch=main "$repo"
    MADE=$((MADE + 1))
    tree="$(git -C "$repo" mktree </dev/null)"
    parent="$(sha_of "$repo" "$ref")"
    if [ -n "$parent" ]; then new="$(git -C "$repo" commit-tree "$tree" -p "$parent" -m "commit $MADE")"
    else new="$(git -C "$repo" commit-tree "$tree" -m "commit $MADE")"; fi
    git -C "$repo" update-ref "$ref" "$new"
    printf '%s' "$new"
}
began() {  # began <seconds ago>: the battery stamp with that age
    mkdir -p "$(dirname "$STAMP")"; touch "$STAMP"
    python3 -c 'import os,sys,time; t=time.time()-float(sys.argv[2]); os.utime(sys.argv[1],(t,t))' "$STAMP" "$1"
}
stamp_fresh() { [ "$(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP") ))" -lt 60 ]; }

ORIGINAL_PATH="$PATH"

# ---------------------------------------------------------------- this machine
setup "install refuses a peer that is this machine"
for host in laptop LAPTOP localhost 192.168.1.42 100.64.0.7 fd7a:115c:a1e0::7; do
    config "peer me = $host"; fresh_log
    run install
    check "install refuses $host" [ "$STATUS" -eq 2 ]
    check "says it is this machine ($host)" saw "is this machine (Laptop)"
    check "names the peer line ($host)" saw "peer me = $host"
    check "loads no timer ($host)" no_call launchctl
done
export FAKE_HOSTNAMES="laptop=laptop desktop=desktop mbp=Laptop.local."
config "peer me = mbp"; run install
check "a config alias resolving here, with a trailing dot, is this machine" [ "$STATUS" -eq 2 ]
export FAKE_HOSTNAMES="laptop=laptop desktop=desktop"
config "peer other = laptop2"; fresh_log; run install
check "a name that contains this machine's is another machine" grep -q 'launchctl load' "$LOG"
config "peer studio = desktop"; fresh_log; run install
check "install names the other machine" grep -q 'launchctl load' "$LOG"
check "install says the battery interval" saw "on battery, at most every 1800s"
export FAKE_SSH_CONFIG_BROKEN=1
config "peer me = laptop"; run install
check "a config ssh cannot read is judged by the host as given" [ "$STATUS" -eq 2 ]
unset FAKE_SSH_CONFIG_BROKEN

setup "mirror from this machine connects to nothing"
config "peer me = laptop"
run mirror
check "exits 0" [ "$STATUS" -eq 0 ]
check "says it is this machine" saw "me         is this machine (Laptop); nothing to mirror."
check "names the line to remove" saw 'Remove `peer me = laptop` from'
check "no connection" [ -z "$(connections)" ]

# ---------------------------------------------------------------- one connection
setup "one connection per run"
export FAKE_PEER_CONFIG=""   # no serving peer: list answers names, fetches fail
export FAKE_NAMES="alpha.git beta.git"
git init --quiet "$PROJECTS/alpha" && git -C "$PROJECTS/alpha" remote add studio "desktop:$PEER/alpha.git"
run mirror
reached="$(connections)"
check "probe, list, refs, two bare fetches and the tree's fetch" [ "$(printf '%s\n' "$reached" | grep -c .)" -ge 6 ]
check "three fetches" [ "$(printf '%s\n' "$reached" | grep -c git-upload-pack)" -eq 3 ]
check "one control path" count_is 1 "$(control_paths)"
check "a control path ending in %C" grep -q '/%C$' <<< "$(control_paths)"
check "inside this run's own folder under the control root" grep -q "^$TMP/tandem\." <<< "$(control_paths)"
check "every connection is a ControlMaster session" [ "$(printf '%s\n' "$reached" | grep -vc 'ControlMaster=auto')" -eq 0 ]
dir="$(control_paths | sed 's,/%C$,,')"
check "the master is closed once" [ "$(grep -c -- ' -O exit ' "$LOG")" -eq 1 ]
check "closed through its socket" grep -q "ControlPath=$dir/fakehash -O exit desktop" "$LOG"
check "and its directory removed" [ ! -e "$dir" ]
check "the summary names the failed repos" saw "FAILED — alpha.git:"
export FAKE_UNREACHABLE=1; fresh_log
run mirror
check "an unreachable peer is skipped" saw "studio     unavailable; skipped."
check "after one connection" count_is 1 "$(connections)"
check "leaving no directory" [ -z "$(ls -d "$TMP"/tandem.* 2>/dev/null)" ]

# ---------------------------------------------------------------- battery
setup "on battery a run waits"
export FAKE_PEER_CONFIG="" FAKE_POWER="Battery Power"
run mirror
check "the first run on battery goes ahead" probed
check "and leaves a stamp" [ -f "$STAMP" ]
fresh_log; began 600; run mirror
check "a run within the interval exits 0" [ "$STATUS" -eq 0 ]
check "says why it waits" saw "studio     on battery: the last mirror began 10m ago; the next waits for 30m."
check "and connects to nothing" [ -z "$(connections)" ]
fresh_log; began 1900; run mirror
check "a run after the interval goes ahead" probed
check "and refreshes the stamp" stamp_fresh
fresh_log; began 60; config "peer studio = desktop" "battery_interval = 30"; run mirror
check "a configured interval is the one that counts" probed
fresh_log; began 60; config "peer studio = desktop" "battery_interval = 0"; run mirror
check "battery_interval = 0 disables the wait" probed
config "peer studio = desktop" "battery_interval = soon"; run mirror
check "a battery_interval that is not seconds is refused" [ "$STATUS" -eq 2 ]
check "and named" saw "battery_interval must be a whole number of seconds"
config "peer studio = desktop"
export FAKE_POWER="AC Power"; fresh_log; began 60; run mirror
check "on mains power nothing waits" probed
export FAKE_POWER=""; fresh_log; began 60; run mirror
check "without pmset this is mains power" probed
export FAKE_POWER="Battery Power"; fresh_log; began -3600; run mirror
check "a clock set back does not hold runs off" probed
fresh_log; rm -f "$STAMP"; mkdir -p "$(dirname "$STAMP")"; chmod 500 "$(dirname "$STAMP")"; run mirror
check "a stamp that cannot be written does not stop the run" probed
chmod 700 "$(dirname "$STAMP")"

# ---------------------------------------------------------------- only what moved
setup "a run fetches only what moved"
commit "$PEER/alpha.git" >/dev/null
beta="$(commit "$PEER/beta.git")"; git -C "$PEER/beta.git" tag v0 "$beta"
run mirror
check "the first run exits 0" [ "$STATUS" -eq 0 ]
check "fetched both" [ "$(fetched)" = "alpha.git beta.git " ]
check "and created both" saw "updated=2 unchanged=0 created=2 diverged=0 failed=0"
check "alpha arrived" [ "$(sha_of "$BARES/alpha.git" main)" = "$(sha_of "$PEER/alpha.git" main)" ]
check "beta's tag arrived" [ "$(sha_of "$BARES/beta.git" v0)" = "$beta" ]
fresh_log; run mirror
check "a quiet peer is not fetched from" [ -z "$(fetched)" ]
check "and counted as unchanged" saw "updated=0 unchanged=2 created=0"
fresh_log; new="$(commit "$PEER/alpha.git")"; run mirror
check "only the repo that moved is fetched" [ "$(fetched)" = "alpha.git " ]
check "and lands" [ "$(sha_of "$BARES/alpha.git" main)" = "$new" ]
fresh_log; commit "$PEER/beta.git" refs/heads/topic >/dev/null; run mirror
check "a new branch on the peer is fetched" [ "$(fetched)" = "beta.git " ]
check "and lands" [ -n "$(sha_of "$BARES/beta.git" topic)" ]
fresh_log; git -C "$PEER/alpha.git" tag v1 main; run mirror
check "a new tag on the peer is fetched" [ "$(fetched)" = "alpha.git " ]
check "and lands" [ -n "$(sha_of "$BARES/alpha.git" v1)" ]
fresh_log; commit "$BARES/alpha.git" >/dev/null; run mirror
check "this machine ahead of the peer is not fetched" [ -z "$(fetched)" ]
check "and not diverged" not_saw DIVERGED
fresh_log; git -C "$PEER/alpha.git" update-ref refs/heads/main "$(sha_of "$PEER/alpha.git" main~1)"
commit "$PEER/alpha.git" >/dev/null; run mirror
check "a real divergence is fetched" [ "$(fetched)" = "alpha.git " ]
check "and left for review" saw "DIVERGED — left for review, not fetched: alpha.git"
check "with the mirror untouched" [ "$(sha_of "$BARES/alpha.git" main)" != "$(sha_of "$PEER/alpha.git" main)" ]
git -C "$BARES/alpha.git" update-ref refs/heads/main "$(sha_of "$PEER/alpha.git" main)"   # resolved by hand
fresh_log; export FAKE_OLD_PEER=1; run mirror
check "a peer that does not answer refs has every repo fetched" [ "$(fetched)" = "alpha.git beta.git " ]
check "and the log says so" saw 'studio     did not answer `tandem refs`; fetching every repo.'
export FAKE_OLD_PEER=""
fresh_log; git init --quiet --bare --initial-branch=main "$PEER/empty.git"; run mirror
check "an empty bare on the peer is created here" [ -d "$BARES/empty.git" ]
check "and not fetched" [ -z "$(fetched)" ]
check "counted as created" saw "created=1"
fresh_log; mkdir "$PEER/notarepo.git"; run mirror
check "a folder the peer could not read as a repo is fetched" grep -q notarepo.git <<< "$(fetched)"
check "and named as failed with git's reason" saw "FAILED — notarepo.git:"
check "which fails the run" [ "$STATUS" -eq 1 ]
rm -rf "$PEER/notarepo.git" "$BARES/notarepo.git"

setup "what the peer says is checked"
commit "$PEER/alpha.git" >/dev/null; run mirror; fresh_log
sha="$(sha_of "$PEER/alpha.git" main)"
for forged in "alpha.git	HEAD refs/heads/main" "alpha.git	${sha:0:12} refs/heads/main" \
              "alpha.git	$sha +refs/heads/main" "alpha.git	$sha refs/heads/a..b"; do
    fresh_log; export FAKE_REFS_FORGED="alpha.git
$forged"
    run mirror
    check "a forged line is fetched rather than trusted: ${forged#alpha.git	}" [ "$(fetched)" = "alpha.git " ]
done
export FAKE_REFS_FORGED=""

# ---------------------------------------------------------------- working trees
setup "a current working tree is not fetched"
commit "$PEER/alpha.git" >/dev/null
git init --quiet "$PROJECTS/alpha" && git -C "$PROJECTS/alpha" remote add studio "desktop:$PEER/alpha.git"
run mirror
check "the first run fetched the tree" [ "$(connections | grep -c "upload-pack '$PEER/alpha.git'")" -eq 2 ]
check "and its tracking ref" [ -n "$(sha_of "$PROJECTS/alpha" studio/main)" ]
fresh_log; run mirror
check "a tree already current is not fetched" [ -z "$(fetched)" ]
fresh_log; commit "$PEER/alpha.git" >/dev/null; run mirror
check "a tree is fetched when its repo moved" [ "$(connections | grep -c "upload-pack '$PEER/alpha.git'")" -eq 2 ]
fresh_log; git -C "$PROJECTS/alpha" remote set-url studio "elsewhere:/x/alpha.git"; run mirror
check "a remote in another shape is fetched as before" connections | grep -q "elsewhere"

# ---------------------------------------------------------------- refs and serve
setup "refs and serve"
a="$(commit "$BARES/alpha.git")"; git -C "$BARES/alpha.git" tag v0 "$a"
git init --quiet --bare --initial-branch=main "$BARES/empty.git"
run refs
check "each bare is its name, then a line per head and tag" [ "$(cat "$OUT")" = "alpha.git
alpha.git	$a refs/heads/main
alpha.git	$a refs/tags/v0
empty.git" ]
mkdir "$BARES/broken.git"; run refs
check "a bare that cannot be read is left out" not_saw broken.git
SSH_ORIGINAL_COMMAND="tandem refs" run serve
check "serve answers refs" saw "alpha.git	$a refs/heads/main"
SSH_ORIGINAL_COMMAND="tandem refs extra" run serve
check "serve refuses anything longer" [ "$STATUS" -eq 126 ]
SSH_ORIGINAL_COMMAND="tandem list" run serve
check "serve still answers list" saw "^alpha.git$"

setup "a peer's names stay under bare_dir"
export FAKE_PEER_CONFIG="" FAKE_NAMES="../escaped.git .hidden.git plain.git"
run mirror
check "a name with a slash is refused" saw "FAILED — ../escaped.git: not a bare repo name, refused"
check "and makes nothing outside bare_dir" [ ! -e "$TMP/escaped.git" ]
check "a dot name is refused" saw "FAILED — .hidden.git: not a bare repo name"
check "a plain name gets a bare under bare_dir" [ -d "$BARES/plain.git" ]

# ---------------------------------------------------------------- done
rm -rf "$TMP"
printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
exit "$FAILED"
