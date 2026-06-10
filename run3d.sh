#!/bin/bash
cd "$(dirname "$0")"
script -q lldb-session.log lldb --batch -o run -k 'thread backtrace all' -k 'frame variable' -k quit ./prog3d
printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l'
stty sane
