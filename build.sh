#!/usr/bin/env bash
#
# build.sh — build TWRP recovery for DJI RC RM330 (msm8953, Android 10 base)
#
# RUN THIS ON LINUX ONLY (WSL2 Ubuntu 20.04, VMware/other Linux VM, or a remote
# Linux host). It does not run on Windows/Git Bash.
#
# Typical use:
#   ./build.sh --check                 # environment/disk checks only
#   ./build.sh --sync --yes            # repo init + sync (~25-35 GB), then build
#   ./build.sh                         # build from an already-synced tree
#
# Assumptions:
#   * The TWRP 10.0 minimal manifest branch is `twrp-10.0-deprecated`
#     (verified via GitHub API; the README still says `twrp-10.0`).
#   * Source dir defaults to $HOME/twrp10. Override with --src /path.
#   * No ccache (small disk). Enable yourself if you have room.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_TREE_SRC="$SCRIPT_DIR/device/dji/rm330"
MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git"
MANIFEST_BRANCH="twrp-10.0-deprecated"
FALLBACK_BRANCH="twrp-10.0"
LUNCH_TARGET="twrp_rm330-eng"
RECOVERY_PART_SIZE=67108864
MIN_FREE_GB=70

SRC_DIR="${SRC_DIR:-$HOME/twrp10}"
JOBS="${JOBS:-$(nproc --all 2>/dev/null || echo 4)}"
DO_SYNC=0
ASSUME_YES=0
CHECK_ONLY=0
FORCE_COPY=0
COPY_OUT=1

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --sync) DO_SYNC=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --check) CHECK_ONLY=1 ;;
        --force) FORCE_COPY=1 ;;
        --no-copy) COPY_OUT=0 ;;
        --src) shift; SRC_DIR="${1:?--src needs a path}" ;;
        --jobs|-j) shift; JOBS="${1:?--jobs needs a number}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

confess_download() {
    echo "This step downloads the TWRP 10.0 source tree (~25-35 GB) into:"
    echo "    $SRC_DIR"
    echo "Free space needed: >= ${MIN_FREE_GB} GB (source + out + headroom)."
    echo "Estimated time: 20-60 min sync, 30-90 min first build (4-8 cores)."
    if [ "$ASSUME_YES" -ne 1 ]; then
        printf 'Continue? [y/N] '
        read -r ans
        case "$ans" in y|Y|yes|YES) ;; *) die "aborted by user (no download started)" ;; esac
    fi
}

check_host() {
    say "Host checks"
    [ "$(uname -s)" = "Linux" ] || die "not Linux (uname=$(uname -s)). Use WSL2/VM/remote Linux."
    echo "kernel : $(uname -r)"
    echo "distro : $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
    echo "cpus   : $(nproc --all 2>/dev/null || echo '?')"
    echo "ram    : $(free -h 2>/dev/null | awk '/^Mem:/{print $2}')"
    echo "python3: $(python3 --version 2>&1 || echo MISSING)"
    if command -v python2 >/dev/null 2>&1; then
        echo "python2: $(python2 --version 2>&1)"
    else
        warn "python2 not found; a few AOSP 10 legacy scripts may need it (apt install python2)."
    fi
    if command -v javac >/dev/null 2>&1; then
        JV="$(javac -version 2>&1 | awk '{print $2}')"
        echo "javac  : $JV"
        case "$JV" in
            1.8*|8*|9*) : ;;
            *) warn "AOSP 10 expects OpenJDK 8/9; javac $JV (e.g. 21) will fail. Install openjdk-8-jdk and set JAVA_HOME." ;;
        esac
    else
        warn "javac not found (apt install openjdk-8-jdk)."
    fi
    if ! command -v repo >/dev/null 2>&1; then
        warn "repo not found. Install: mkdir -p ~/bin && curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo && chmod +x ~/bin/repo"
    fi
    command -v git >/dev/null 2>&1 && echo "git    : $(git --version)" || warn "git missing"

    say "Disk checks for $SRC_DIR"
    mkdir -p "$SRC_DIR" 2>/dev/null || die "cannot create $SRC_DIR"
    FREE_GB=$(df -Pk "$SRC_DIR" | awk 'NR==2{printf "%d", $4/1024/1024}')
    echo "free   : ${FREE_GB} GB at $(df -Pk "$SRC_DIR" | awk 'NR==2{print $6}')"
    if [ "$FREE_GB" -lt "$MIN_FREE_GB" ]; then
        warn "only ${FREE_GB} GB free; ${MIN_FREE_GB} GB recommended. A clean TWRP 10 tree + out is ~40-50 GB."
    fi

    say "Device tree checks"
    [ -f "$DEVICE_TREE_SRC/BoardConfig.mk" ] || die "missing $DEVICE_TREE_SRC/BoardConfig.mk"
    [ -f "$DEVICE_TREE_SRC/prebuilt/zImage" ] || die "missing prebuilt kernel"
    ( cd "$DEVICE_TREE_SRC/prebuilt" && sha256sum -c zImage.sha256 ) \
        || die "prebuilt zImage hash mismatch"
    echo "device tree OK: $DEVICE_TREE_SRC"
}

check_only() {
    echo
    echo "Check-only mode. To build:"
    echo "  $0 --sync --yes --src \"$SRC_DIR\""
}

sync_tree() {
    command -v repo >/dev/null 2>&1 || die "repo not installed (see message above)"
    mkdir -p "$SRC_DIR"
    cd "$SRC_DIR"
    if [ ! -d .repo ]; then
        say "repo init ($MANIFEST_BRANCH)"
        if ! repo init --depth=1 -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" >/tmp/repo_init.log 2>&1; then
            tail -20 /tmp/repo_init.log >&2 || true
            warn "branch $MANIFEST_BRANCH failed; retrying $FALLBACK_BRANCH"
            repo init --depth=1 -u "$MANIFEST_URL" -b "$FALLBACK_BRANCH"
        fi
    else
        echo "existing .repo found — reusing $SRC_DIR"
    fi
    say "repo sync -j$JOBS (this is the long download)"
    repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
}

install_device_tree() {
    local dst="$SRC_DIR/device/dji/rm330"
    say "Installing device tree -> $dst"
    if [ -d "$dst" ] && [ "$FORCE_COPY" -ne 1 ]; then
        if diff -qr "$DEVICE_TREE_SRC" "$dst" >/dev/null 2>&1; then
            echo "device tree already up to date"
        else
            die "$dst exists and differs; re-run with --force to overwrite"
        fi
    else
        mkdir -p "$(dirname "$dst")"
        rm -rf "$dst"
        cp -a "$DEVICE_TREE_SRC" "$dst"
    fi
    ( cd "$dst/prebuilt" && sha256sum -c zImage.sha256 )
}

build_recovery() {
    cd "$SRC_DIR"
    [ -f build/envsetup.sh ] || die "$SRC_DIR is not an Android source tree"
    say "envsetup + lunch $LUNCH_TARGET"
    export ALLOW_MISSING_DEPENDENCIES=true
    # shellcheck disable=SC1091
    . build/envsetup.sh
    lunch "$LUNCH_TARGET"
    say "mka recoveryimage (jobs=$JOBS)"
    mka recoveryimage -j"$JOBS" || die "build failed; inspect the first error above, do not paste the whole log"

    local out="out/target/product/rm330/recovery.img"
    [ -f "$out" ] || die "build finished but $out is missing"
    local size sha
    size=$(stat -c %s "$out")
    sha=$(sha256sum "$out" | awk '{print $1}')
    echo
    echo "recovery.img : $(pwd)/$out"
    echo "size         : $size bytes ($((size/1024/1024)) MiB)"
    echo "sha256       : $sha"
    if [ "$size" -gt "$RECOVERY_PART_SIZE" ]; then
        die "image exceeds the 64 MiB recovery partition ($RECOVERY_PART_SIZE). Disable TW_INCLUDE_NTFS_3G, drop extra languages, or build with TW_THEME minimal."
    fi
    if [ "$COPY_OUT" -eq 1 ]; then
        mkdir -p "$SCRIPT_DIR/out"
        cp -f "$out" "$SCRIPT_DIR/out/recovery-rm330.img"
        cp -f "$out" "$SCRIPT_DIR/out/recovery-rm330-$(date +%Y%m%d-%H%M).img"
        echo "copied       : $SCRIPT_DIR/out/recovery-rm330.img"
    fi
}

main() {
    check_host
    if [ "$CHECK_ONLY" -eq 1 ]; then check_only; exit 0; fi

    if [ ! -d "$SRC_DIR/.repo" ] && [ ! -f "$SRC_DIR/build/envsetup.sh" ]; then
        if [ "$DO_SYNC" -ne 1 ]; then
            die "no source tree at $SRC_DIR. Re-run with --sync --yes (downloads ~25-35 GB) or point --src at an existing tree."
        fi
        confess_download
        sync_tree
    else
        if [ "$DO_SYNC" -eq 1 ]; then
            confess_download
            sync_tree
        else
            echo "using existing source tree: $SRC_DIR"
        fi
    fi

    install_device_tree
    build_recovery
    say "Done. Flash only the recovery partition; see README-BUILD.md risk/rollback section."
}

main "$@"
