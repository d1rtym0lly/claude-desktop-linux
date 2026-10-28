#!/usr/bin/env bash
# Launcher for Claude Desktop on non-Debian distributions.
#
# Starts the official binary with flags that suit the current session:
#   * keyring backend, so the sign-in survives restarts on any desktop;
#   * native Wayland when the session is Wayland;
#   * extra flags from ~/.config/claude-desktop-flags.conf.
#
# Environment overrides:
#   CLAUDE_PASSWORD_STORE=<backend>  force a backend (gnome-libsecret, kwallet6, basic, ...)
#   CLAUDE_NO_WAYLAND=1              run through XWayland (e.g. NVIDIA issues)
#   CLAUDE_LAUNCHER_DEBUG=1          print the final command line

APP="@APP@"

flags=()

# Electron picks a keyring only on GNOME-like desktops and KDE. Elsewhere
# (Hyprland, Sway, niri, i3, ...) it falls back to plain text and the app
# asks to sign in on every start, so point it at the Secret Service.
if [[ -n ${CLAUDE_PASSWORD_STORE:-} ]]; then
    flags+=("--password-store=$CLAUDE_PASSWORD_STORE")
else
    case "${XDG_CURRENT_DESKTOP:-}" in
        *KDE*|*GNOME*|*Unity*|*Cinnamon*|*XFCE*|*MATE*|*Budgie*|*Pantheon*|*Deepin*) ;;
        *) flags+=("--password-store=gnome-libsecret") ;;
    esac
fi

if [[ -z ${CLAUDE_NO_WAYLAND:-} && ( ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ) ]]; then
    flags+=(
        "--ozone-platform-hint=auto"
        "--enable-features=WaylandWindowDecorations"
        "--enable-wayland-ime"
    )
fi

conf="${XDG_CONFIG_HOME:-$HOME/.config}/claude-desktop-flags.conf"
if [[ -r $conf ]]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n $line ]] && flags+=("$line")
    done < "$conf"
fi

if [[ -n ${CLAUDE_LAUNCHER_DEBUG:-} ]]; then
    printf '%q ' "$APP" "${flags[@]}" "$@" >&2
    echo >&2
fi

exec "$APP" "${flags[@]}" "$@"
