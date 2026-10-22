#!/bin/zsh
# Starts the game. Use "./run.sh edit" to open the project in the Godot editor instead.
HERE="${0:A:h}"
if [[ "$1" == "edit" ]]; then
  exec godot -e --path "$HERE/game"
fi
if [[ "$1" == "test" ]]; then
  exec godot --headless --path "$HERE/game" --script res://tests/test_walls.gd
fi
exec godot --path "$HERE/game"
