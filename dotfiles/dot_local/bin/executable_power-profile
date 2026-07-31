#!/usr/bin/env bash
# Waybar custom module: shows current power profile as an icon.
# Called with --menu to open the profile selector via fuzzel.
# Icons use ANSI-C quoting ($'\uXXXX') — look up codepoints at nerdfonts.com/cheat-sheet.

icon() {
    case "$1" in
        power-saver)  printf $'\uf06c' ;;
        balanced)     printf $'\uf0e7' ;;
        performance)  printf $'\uf135' ;;
        *)            printf '?' ;;
    esac
}

if [[ "$1" == "--menu" ]]; then
    profile="$(printf $'\uf06c Power Saver\n\uf0e7 Balanced\n\uf135 Performance\n' \
        | fuzzel --dmenu --hide-prompt --mesg "Power Profile")"
    case "$profile" in
        *"Power Saver")  powerprofilesctl set power-saver  && notify-send "Power Profile" "Power Saver active" ;;
        *"Balanced")     powerprofilesctl set balanced      && notify-send "Power Profile" "Balanced active" ;;
        *"Performance")  powerprofilesctl set performance   && notify-send "Power Profile" "Performance active" ;;
    esac
else
    current="$(powerprofilesctl get)"
    printf '{"text":"%s","tooltip":"Profile: %s","class":"%s"}\n' \
        "$(icon "$current")" "$current" "$current"
fi
