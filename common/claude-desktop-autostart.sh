#!/usr/bin/env bash
# Turn starting Claude Desktop at login on or off (XDG autostart).
# With the app already running, opening it from the launcher only
# raises the existing window, which is the fastest way to "open" it.

set -euo pipefail

dir="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
file="$dir/claude-desktop.desktop"

case "${1:-status}" in
    on|enable)
        mkdir -p "$dir"
        # Reuse the app's own icon name if its desktop entry is installed.
        icon=""
        IFS=: read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
        for d in "${XDG_DATA_HOME:-$HOME/.local/share}" "${data_dirs[@]}"; do
            for entry in "$d"/applications/*laude*.desktop; do
                [[ -f $entry ]] || continue
                icon=$(sed -n 's/^Icon=//p' "$entry" | head -n 1)
                [[ -n $icon ]] && break 2
            done
        done
        cat > "$file" <<EOF
[Desktop Entry]
Type=Application
Name=Claude
Comment=Start Claude Desktop at login
Exec=claude-desktop
Icon=${icon:-claude-desktop}
Terminal=false
X-GNOME-Autostart-enabled=true
X-KDE-autostart-after=panel
EOF
        echo "Autostart enabled: $file"
        ;;
    off|disable)
        rm -f "$file"
        echo "Autostart disabled"
        ;;
    status)
        if [[ -f $file ]]; then echo "Autostart: on"; else echo "Autostart: off"; fi
        ;;
    *)
        echo "usage: claude-desktop-autostart [on|off|status]" >&2
        exit 2
        ;;
esac
