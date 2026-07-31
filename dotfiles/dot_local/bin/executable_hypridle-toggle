#!/usr/bin/env bash
if pidof hypridle > /dev/null; then
    pkill hypridle
else
    hypridle &
fi
pkill -SIGRTMIN+8 waybar
