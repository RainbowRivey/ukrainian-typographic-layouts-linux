#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)


# =============================================================================
# Initial checks
# =============================================================================

if [ "$(id -u)" -eq 0 ]; then
    echo "Please do not run this installer with sudo."
    echo "Run './install-ubuntu-legacy.sh' as your normal user."
    exit 1
fi


# =============================================================================
# Find system XKB root
# =============================================================================

if [ -n "${XKB_CONFIG_ROOT:-}" ]; then
    XKB_ROOT="$XKB_CONFIG_ROOT"

elif command -v xkbcli >/dev/null 2>&1; then
    XKB_ROOT=$(
        xkbcli info 2>/dev/null |
        sed -n 's/^[[:space:]]*XKB_CONFIG_ROOT:[[:space:]]*//p' |
        head -n 1
    )

    [ -n "$XKB_ROOT" ] || XKB_ROOT="/usr/share/X11/xkb"

else
    XKB_ROOT="/usr/share/X11/xkb"
fi

SYMBOLS_DIR="$XKB_ROOT/symbols"
RULES_DIR="$XKB_ROOT/rules"
EVDEV_LST="$RULES_DIR/evdev.lst"
EVDEV_XML="$RULES_DIR/evdev.xml"
SOURCE_XML="$SCRIPT_DIR/rules/evdev.xml"

if [ ! -d "$SYMBOLS_DIR" ] || [ ! -d "$RULES_DIR" ]; then
    echo "Could not find a valid XKB installation at:"
    echo "  $XKB_ROOT"
    exit 1
fi

if [ ! -f "$EVDEV_LST" ] || [ ! -f "$EVDEV_XML" ]; then
    echo "Could not find evdev rules in:"
    echo "  $RULES_DIR"
    exit 1
fi

echo "Using XKB directory:"
echo "  $XKB_ROOT"
echo
echo "Installing layouts into the system XKB configuration requires root privileges."

sudo -v


# =============================================================================
# Temporary files
# =============================================================================

TMP_LST=$(mktemp)
TMP_LAYOUTS=$(mktemp)
TMP_XML_CLEAN=$(mktemp)
TMP_XML_FINAL=$(mktemp)

trap 'rm -f "$TMP_LST" "$TMP_LAYOUTS" "$TMP_XML_CLEAN" "$TMP_XML_FINAL"' EXIT


# =============================================================================
# Install symbols
# =============================================================================

sudo install -m 644 \
    "$SCRIPT_DIR/symbols/typo-uk" \
    "$SYMBOLS_DIR/typo-uk"

sudo install -m 644 \
    "$SCRIPT_DIR/symbols/typo-ru-ukrainian" \
    "$SYMBOLS_DIR/typo-ru-ukrainian"


# =============================================================================
# Update evdev.lst
# =============================================================================

sed -E \
    -e '/^[[:space:]]*typo-uk[[:space:]]/d' \
    -e '/^[[:space:]]*typo-ru-ukrainian[[:space:]]/d' \
    -e '/^[[:space:]]*typo-uk-russian[[:space:]]/d' \
    "$EVDEV_LST" |
awk '
    /^! layout[[:space:]]*$/ {
        print
        print "  typo-uk                 Ukrainian (Typographic)"
        print "  typo-ru-ukrainian       Russian (Typographic + Ukrainian)"
        next
    }

    /^! variant[[:space:]]*$/ {
        print
        print "  typo-uk-russian         typo-uk: Ukrainian (Typographic + Russian)"
        next
    }

    {
        print
    }
' > "$TMP_LST"

sudo install -m 644 "$TMP_LST" "$EVDEV_LST"


# =============================================================================
# Update evdev.xml
# =============================================================================

awk '
    /<layoutList>/ {
        inside = 1
        next
    }

    /<\/layoutList>/ {
        inside = 0
        next
    }

    inside {
        print
    }
' "$SOURCE_XML" > "$TMP_LAYOUTS"


awk '
    BEGIN {
        block = ""
        in_layout = 0
    }

    !in_layout && /<layout>/ {
        in_layout = 1
        block = $0 ORS
        next
    }

    in_layout {
        block = block $0 ORS

        if (/<\/layout>/) {
            if (block !~ /<name>typo-uk<\/name>/ &&
                block !~ /<name>typo-ru-ukrainian<\/name>/) {
                printf "%s", block
            }

            block = ""
            in_layout = 0
        }

        next
    }

    {
        print
    }
' "$EVDEV_XML" > "$TMP_XML_CLEAN"


awk -v layouts="$TMP_LAYOUTS" '
    /<\/layoutList>/ {
        while ((getline line < layouts) > 0)
            print line

        close(layouts)
    }

    {
        print
    }
' "$TMP_XML_CLEAN" > "$TMP_XML_FINAL"

sudo install -m 644 "$TMP_XML_FINAL" "$EVDEV_XML"


# =============================================================================
# Enable AltGr for the current GNOME user
# =============================================================================

if command -v gsettings >/dev/null 2>&1 &&
   [ "$(
       gsettings writable \
           org.gnome.desktop.input-sources \
           xkb-options 2>/dev/null
   )" = "true" ]
then
    current_options=$(
        gsettings get \
            org.gnome.desktop.input-sources \
            xkb-options
    )

    case "$current_options" in
        *"'lv3:ralt_switch'"*)
            echo "AltGr is already enabled."
            ;;

        "@as []"|"[]")
            gsettings set \
                org.gnome.desktop.input-sources \
                xkb-options \
                "['lv3:ralt_switch']"

            echo "Enabled Right Alt as AltGr."
            ;;

        *)
            new_options=$(
                printf '%s\n' "$current_options" |
                sed "s/]$/, 'lv3:ralt_switch']/"
            )

            gsettings set \
                org.gnome.desktop.input-sources \
                xkb-options \
                "$new_options"

            echo "Added Right Alt as AltGr."
            ;;
    esac
else
    echo
    echo "GNOME GSettings is not available."
    echo "Enable the XKB option 'lv3:ralt_switch' manually if needed."
fi


# =============================================================================
# Done
# =============================================================================

echo
echo "Installation complete."
echo
echo "Please log out and log in again, then enable the Typographic layouts"
echo "in your desktop environment's keyboard settings."
