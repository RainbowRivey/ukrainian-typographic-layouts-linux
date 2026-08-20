#!/bin/sh

set -eu

PACKAGE_NAME="ukrainian-typographic"

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

FILES="
symbols/typo-uk
symbols/typo-ru-ukrainian
rules/evdev.xml
"


# =============================================================================
# Helpers
# =============================================================================

die() {
    echo "Error: $*" >&2
    exit 1
}


run_install_cmd() {
    if [ "$USE_SUDO" -eq 1 ]; then
        sudo "$@"
    else
        "$@"
    fi
}


can_write_target() {
    path=$1

    if [ -e "$path" ]; then
        [ -w "$path" ]
        return
    fi

    parent=$(dirname "$path")

    while [ ! -e "$parent" ]; do
        next=$(dirname "$parent")

        if [ "$next" = "$parent" ]; then
            return 1
        fi

        parent=$next
    done

    [ -w "$parent" ]
}


get_user_xkb_dir() {
    printf '%s\n' "${XDG_CONFIG_HOME:-"$HOME/.config"}/xkb"
}


get_xkbcommon_version() {
    pkg-config --modversion xkbcommon
}


get_extension_root() {
    if [ -n "${XKB_CONFIG_UNVERSIONED_EXTENSIONS_PATH:-}" ]; then
        printf '%s\n' "$XKB_CONFIG_UNVERSIONED_EXTENSIONS_PATH"
        return
    fi

    for package in xkeyboard-config xkbcommon; do
        if pkg-config --exists "$package" 2>/dev/null; then
            path=$(
                pkg-config \
                    --variable=xkb_unversioned_extensions_path \
                    "$package" 2>/dev/null ||
                true
            )

            if [ -n "$path" ]; then
                printf '%s\n' "$path"
                return
            fi
        fi
    done

    return 1
}


has_extension_support() {
    pkg-config --atleast-version=1.13 xkbcommon &&
    pkg-config --exists xkeyboard-config &&
    pkg-config --atleast-version=2.45 xkeyboard-config &&
    get_extension_root >/dev/null 2>&1
}


# =============================================================================
# Initial checks
# =============================================================================

if [ "$(id -u)" -eq 0 ]; then
    die "Do not run this installer with sudo. Run './install-linux.sh' as your normal user."
fi

if ! command -v pkg-config >/dev/null 2>&1; then
    die "pkg-config is required to detect libxkbcommon."
fi

if ! pkg-config --exists xkbcommon; then
    die "libxkbcommon was not found."
fi

if ! pkg-config --atleast-version=0.10 xkbcommon; then
    version=$(get_xkbcommon_version)
    die "libxkbcommon >= 0.10.0 is required (found $version)."
fi

for file in $FILES; do
    [ -f "$SCRIPT_DIR/$file" ] ||
        die "Missing repository file: $SCRIPT_DIR/$file"
done

USER_TARGET=$(get_user_xkb_dir)


# =============================================================================
# Installation path
# =============================================================================

if has_extension_support && EXT_ROOT=$(get_extension_root); then
    EXT_TARGET="$EXT_ROOT/$PACKAGE_NAME"

    echo "Select installation location:"
    echo
    echo "  1) XKB extension directory (recommended)"
    echo "     $EXT_TARGET"
    echo
    echo "  2) Current user"
    echo "     $USER_TARGET"
    echo
    printf "Enter a number [1]: "

    read -r choice

    case "${choice:-1}" in
        1)
            TARGET="$EXT_TARGET"
            ;;
        2)
            TARGET="$USER_TARGET"
            ;;
        *)
            die "Invalid selection."
            ;;
    esac
else
    TARGET="$USER_TARGET"

    echo "Using the current user's XKB configuration:"
    echo
    echo "  $TARGET"
fi


# =============================================================================
# Privileges
# =============================================================================

if can_write_target "$TARGET"; then
    USE_SUDO=0
else
    USE_SUDO=1

    echo
    echo "Writing to:"
    echo "  $TARGET"
    echo
    echo "requires elevated privileges."

    sudo -v
fi


# =============================================================================
# Detect conflicts
# =============================================================================

CONFLICTS=""

for file in $FILES; do
    src="$SCRIPT_DIR/$file"
    dst="$TARGET/$file"

    if [ -e "$dst" ]; then
        if [ ! -f "$dst" ]; then
            die "Destination exists but is not a regular file: $dst"
        fi

        if ! cmp -s "$src" "$dst"; then
            CONFLICTS="${CONFLICTS}${file}
"
        fi
    fi
done


# =============================================================================
# Confirm overwrites
# =============================================================================

if [ -n "$CONFLICTS" ]; then
    echo
    echo "The following existing files differ and will be overwritten:"
    echo

    printf '%s' "$CONFLICTS" |
    while IFS= read -r file; do
        [ -n "$file" ] &&
            printf '  %s\n' "$TARGET/$file"
    done

    echo
    echo "The existing versions will be backed up first."
    echo
    printf "Continue? [y/N] "

    read -r answer

    case "$answer" in
        y|Y|yes|YES|Yes)
            ;;
        *)
            echo "Installation cancelled."
            exit 0
            ;;
    esac
fi


# =============================================================================
# Backup
# =============================================================================

if [ -n "$CONFLICTS" ]; then
    timestamp=$(date '+%Y%m%d-%H%M%S')
    BACKUP_ROOT="${TARGET}.backup-${timestamp}"

    echo
    echo "Creating backup:"
    echo "  $BACKUP_ROOT"

    printf '%s' "$CONFLICTS" |
    while IFS= read -r file; do
        [ -n "$file" ] || continue

        src="$TARGET/$file"
        dst="$BACKUP_ROOT/$file"

        run_install_cmd mkdir -p "$(dirname "$dst")"
        run_install_cmd cp -p "$src" "$dst"
    done
fi


# =============================================================================
# Install
# =============================================================================

echo
echo "Installing..."

for file in $FILES; do
    src="$SCRIPT_DIR/$file"
    dst="$TARGET/$file"

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        echo "  Unchanged: $file"
        continue
    fi

    run_install_cmd mkdir -p "$(dirname "$dst")"
    run_install_cmd install -m 644 "$src" "$dst"

    echo "  Installed: $file"
done


# =============================================================================
# Result
# =============================================================================

echo
echo "Installation complete."
echo
echo "Installed to:"
echo "  $TARGET"

if [ -n "${BACKUP_ROOT:-}" ]; then
    echo
    echo "Previous files backed up to:"
    echo "  $BACKUP_ROOT"
fi

echo
echo "Installed layouts:"
echo "  typo-uk"
echo "  typo-uk (variant: typo-uk-russian)"
echo "  typo-ru-ukrainian"
echo
echo "You may need to restart your session before all applications"
echo "discover the new layouts."
