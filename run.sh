#!/bin/zsh
# Starts the game. Use "./run.sh edit" to open the project in the Godot editor instead.
HERE="${0:A:h}"
if [[ "$1" == "edit" ]]; then
  exec godot -e --path "$HERE/game"
fi
if [[ "$1" == "test" ]]; then
  # Two suites: the wall grid needs no autoloads and runs as a plain script, the rest needs
  # them and so runs as a scene. Both are quiet when everything passes.
  godot --headless --path "$HERE/game" --script res://tests/test_walls.gd || exit 1
  godot --headless --path "$HERE/game" --script res://tests/test_formation.gd || exit 1
  godot --headless --path "$HERE/game" res://tests/test_game.tscn || exit 1
  exec godot --headless --path "$HERE/game" res://tests/test_units.tscn
fi
exec godot --path "$HERE/game"
