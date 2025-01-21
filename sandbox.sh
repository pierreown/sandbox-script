#!/bin/sh

randomx() { head -c "$1" /dev/urandom | md5sum | head -c "$1"; }

reset_env() {
    keep_vars="$1"

    {
        if [ -z "$keep_vars" ]; then
            while read -r item; do
                item="${item#export }"
                item="${item%%=*}"
                unset "$item"
            done
        else
            while read -r item; do
                item="${item#export }"
                item="${item%%=*}"
                case ",$keep_vars," in
                *,"$item",*) ;;
                *) unset "$item" ;;
                esac
            done
        fi
    } <<EOF
$(sh -c 'export -p')
EOF
}

step_pre() {
    sb_prefix="${SB_PREFIX:?}"
    sb_base_dir="${SB_BASE_DIR:?}"
    sb_home_dir="${SB_HOME_DIR:?}"
    sb_rootless="${SB_ROOTLESS:-0}"

    # Create root overlay directory
    sb_root_dir="$sb_base_dir/root" sb_root_upper="$sb_base_dir/upper" sb_root_work="$sb_base_dir/work" sb_root_null="$sb_base_dir/null"
    mkdir -p "$sb_root_dir" "$sb_root_upper" "$sb_root_work" "$sb_root_null"

    # Bind right user home directory
    mount -o bind "$sb_home_dir" "/root"
    mount -o bind "$sb_root_null" "/home"

    # Mount root overlay file system
    if [ "$sb_rootless" = 1 ]; then
        fuse-overlayfs -o "lowerdir=/,upperdir=$sb_root_upper,workdir=$sb_root_work" "$sb_root_dir" 2>/dev/null
    else
        mount -t overlay overlay -o "lowerdir=/,upperdir=$sb_root_upper,workdir=$sb_root_work,userxattr" "$sb_root_dir" 2>/dev/null
    fi

    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        echo "Failed to mount root overlay file system" >&2
        exit 1
    fi

    # Export variables for next step
    export SB_ROOT_DIR="$sb_root_dir"

    # Next step
    SB_STEP="RUN" exec unshare -p -f --kill-child unshare -u -i -C -m --mount-proc --propagation slave -- "$0" "$@"
}

step_run() {
    sb_hostname="${SB_HOSTNAME:?}"
    sb_root_dir="${SB_ROOT_DIR:?}"
    sb_work_dir="${SB_WORK_DIR:-/}"
    sb_path_org="${SB_PATH_ORG:-}"
    sb_mount_wsl="${SB_MOUNT_WSL:-0}"
    sb_mount_extra="${SB_MOUNT_EXTRA:-}"

    # Mount system directories
    mount -t proc proc "$sb_root_dir/proc" -o nosuid,nodev,noexec
    mount -o rbind "/sys" "$sb_root_dir/sys"
    mount -o rbind "/dev" "$sb_root_dir/dev"
    mount -o rbind "/run" "$sb_root_dir/run"

    mount -t binfmt_misc binfmt_misc "$sb_root_dir/proc/sys/fs/binfmt_misc" -o nosuid,nodev,noexec >/dev/null 2>&1 || true

    # Add WSL support directories to extra mounts
    if [ "$sb_mount_wsl" = 1 ]; then
        sb_mount_extra="/mnt,/usr/lib/wsl,/tmp/.X11-unix"
    fi

    # Mount extra directories
    if [ -n "$sb_mount_extra" ]; then
        echo "$sb_mount_extra" | tr ',' '\n' | while read -r item; do
            [ -d "$item" ] || continue
            mount -o rbind "$item" "$sb_root_dir$item" >/dev/null 2>&1 || true
        done
    fi

    # Change root directory
    sb_root_org="/.root.org"
    mkdir -p "$sb_root_dir$sb_root_org"
    pivot_root "$sb_root_dir" "$sb_root_dir$sb_root_org"
    umount -l "$sb_root_org" && rm -rf "$sb_root_org" # Hide original root

    # Change work directory
    [ -d "$sb_work_dir" ] || sb_work_dir="/"
    cd "$sb_work_dir" || true

    # System Settings
    hostname "$sb_hostname"

    # Clean up environment variables
    unset SB_STEP

    unset SB_PREFIX
    unset SB_HOSTNAME
    unset SB_BASE_DIR
    unset SB_ROOT_DIR
    unset SB_HOME_DIR
    unset SB_WORK_DIR
    unset SB_ROOTLESS
    unset SB_PATH_ORG
    unset SB_MOUNT_WSL
    unset SB_MOUNT_EXTRA

    unset OLDPWD SHLVL

    # Reset environment
    [ -n "$sb_path_org" ] &&
        export PATH="$sb_path_org"

    # Execute command
    exec "$@"
}

usage() {
    echo "Usage: $0 [options] [-- command [args...]]"
    echo
    echo "Options:"
    echo "  -n, --name=string               Set sandbox name"
    echo "  -w, --work-dir=string           Set working directory"
    echo "  -E, --preserve-env              Preserve environment variables"
    echo "      --preserve-env=list         Preserve environment variables in list, separated by commas"
    echo "                                  Note: NAME,USER,LOGNAME,HOME are always reset"
    echo "      --mount-wsl                 Mount WSL support directories"
    echo "      --mount-extra=list          Mount extra directories, separated by commas"
    echo "  -h, --help                      Show usage"
    echo
    echo "Examples:"
    echo "  $0 -- /bin/bash -l"
    echo
}

main() {
    sb_home_dir="${HOME:?}"
    sb_work_dir="${PWD:-/}"
    sb_path_org="$PATH"

    sb_rootless=0
    sb_prefix="${HOME:?}/.sandbox"

    sb_hostname=""
    sb_keep_env=""
    sb_mount_wsl=0
    sb_mount_extra=""

    SB_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export PATH=$SB_PATH

    # Check run mode
    if [ "$(id -u)" -eq 0 ]; then
        sb_rootless=0
    elif type fuse-overlayfs >/dev/null 2>&1; then
        sb_rootless=1
    else
        echo "Please run as root or install fuse-overlayfs for rootless" >&2
        exit 1
    fi

    # Parse options
    eval set -- "$(getopt -o ':n:w:Eh' --long 'name:,work-dir:,preserve-env::,mount-wsl,mount-extra:,help' -- "$@")"
    while true; do
        case "$1" in
        --) shift && break ;;
        -n | --name) shift && sb_hostname="$1" ;;
        -w | --work-dir) shift && sb_work_dir="$1" ;;
        -E) sb_keep_env=1 ;;
        --preserve-env) shift && sb_keep_env="${1:-1}" ;;
        --mount-wsl) sb_mount_wsl=1 ;;
        --mount-extra) shift && sb_mount_extra="$1" ;;
        -h | --help) usage && exit ;;
        esac
        shift
    done

    # Set default executable, fallback to shell
    if [ $# -eq 0 ]; then
        set -- "${SHELL:-/bin/sh}"
    fi

    # Generate random sandbox name
    sb_name="" sb_base_dir=""
    while true; do
        sb_name="$(randomx 16)"
        sb_base_dir="$sb_prefix/sbox.$sb_name"
        [ ! -e "$sb_base_dir" ] && break
    done
    : "${sb_hostname:=$sb_name}"

    # Setting the cleanup handler
    cleanup() {
        if [ -n "$sb_base_dir" ] && [ -e "$sb_base_dir" ]; then
            rm -rf "$sb_base_dir"
        fi
    }
    trap 'cleanup' EXIT
    trap 'exit 0' INT TERM

    mkdir -p "$sb_base_dir"

    # Reset environment variables
    if [ "$sb_keep_env" != 1 ]; then
        reset_env "$sb_keep_env"
        if [ ! "${PATH-}" ]; then
            sb_path_org=""
        fi
    fi

    # Reset user variables
    export NAME="$sb_hostname"
    export USER="root"
    export LOGNAME="root"
    export HOME="/root"
    export PATH="$SB_PATH"

    # Export variables for next step
    export SB_PREFIX="$sb_prefix"
    export SB_HOSTNAME="$sb_hostname"
    export SB_BASE_DIR="$sb_base_dir"
    export SB_HOME_DIR="$sb_home_dir"
    export SB_WORK_DIR="$sb_work_dir"
    export SB_ROOTLESS="$sb_rootless"
    export SB_PATH_ORG="$sb_path_org"
    export SB_MOUNT_WSL="$sb_mount_wsl"
    export SB_MOUNT_EXTRA="$sb_mount_extra"

    # Temp sandbox needs cleanup by trap, cannot use 'exec'
    if [ "$sb_rootless" = 1 ]; then
        SB_STEP="PRE" unshare -m --propagation slave -r -- "$0" "$@"
    else
        SB_STEP="PRE" unshare -m --propagation slave -- "$0" "$@"
    fi
}

case "$SB_STEP" in
RUN) step_run "$@" ;;
PRE) step_pre "$@" ;;
*) main "$@" ;;
esac
