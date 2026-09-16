#!/bin/zsh
# Starts the game. Use "./run.sh edit" to open the project in the Godot editor instead.
HERE="${0:A:h}"
if [[ "$1" == "edit" ]]; then
  exec godot -e --path "$HERE/game"
fi
exec godot --path "$HERE/game"
