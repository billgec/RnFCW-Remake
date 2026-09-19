# Rise & Fall – Remake (Godot)

A from-scratch remake of the 2006 RTS *Rise & Fall: Civilizations at War*, running natively
on macOS/Linux/Windows in Godot 4. Models, textures, animations and gameplay values are read
from an installed copy of the original game and converted into open formats (glTF, PNG, JSON)
by a small Java tool.

**No game content is included in this repository.** You need your own installation of the
original game; the converter reads its `Data/data.ssa` archive and writes everything into
`game/assets/original/`, which is git-ignored.

## Requirements

* [Godot 4.4+](https://godotengine.org/) (`godot` on your `PATH`)
* A JDK 21+ (`javac`, `java`) for the asset converter
* An installed copy of *Rise & Fall: Civilizations at War*

## Getting started

```bash
export RNF_DATA_SSA="/path/to/Rise And Fall/Data/data.ssa"   # optional, see convert.sh
./convert.sh      # extract + convert the assets the game needs
./run.sh          # play
./run.sh edit     # open the project in the Godot editor
```

`convert.sh` expects the original installation next to this folder by default; set
`RNF_DATA_SSA` to point somewhere else. Re-run it after changing the converter.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys / mouse at screen edge | pan the camera |
| Mouse wheel · Q/E · middle mouse drag | zoom · rotate |
| Left click / drag a box | select (Shift adds to the selection) |
| Click a unit of a group, its banner, or drag a box over part of it | select the whole group |
| Double click a unit | select every visible unit of that type |
| Right click | move · attack a unit or building · citizens: gather wood/gold, help build or repair · with a building selected: set the rally point |
| Cmd/Ctrl + right click | attack-move |
| Hold Option/Alt | show hit point bars |
| Space · + / − · speed buttons | pause · game speed (0.5x to 3x, any time) |
| Buttons bottom right | buildings: train units · citizens: found buildings (left click places, right click/Esc cancels) |
| H, or the hero's button | enter hero mode · Esc or H leaves it |
| F5 | graphics quality: low · medium · high (saved) |
| Minimap: left click/drag · right click | move the camera · send the selection there |

### Hero mode

| Input | Action |
|---|---|
| WASD | run (the hero always faces the camera and strafes sideways) |
| Mouse | look around · wheel: camera distance |
| Left click | attack - repeated clicks chain into a combo |
| Right click | raise the shield: much less damage taken, slower movement |
| Space | special attack: sweeps everyone around the hero, then needs to recharge |

## What works

* Reading the original `data.ssa` archive directly (encryption and compression)
* Units and buildings as skinned glTF including every animation their definition references
* Player colour from the skin's alpha channel; modern lighting (shadows, SSAO, SSIL, AgX)
* RTS camera, selection, formation movement, navmesh pathing around buildings
* Combat with the original values (hit points, damage, range, sight, rate, speed), melee and
  projectiles, death animations, automatic target acquisition
* Class bonuses via `game/data/bonuses.json` (spears beat cavalry, …), freely editable
* Economy with all three of the original's resources: citizens gather gold and wood, glory
  comes from kills, own losses, finished buildings and glory statues; training uses the
  original build lists, icons, costs and times; soldiers come in groups (3+, one more per
  settlement, shown in the resource bar)
* Hero levels and upgrades exactly as in the original: the hero spends glory to level up,
  which gates everything else; unit upgrades (researched in the building's top row, paid for
  in glory) then unlock the next of the five levels of that unit line, and units already in
  the field are replaced by their veteran version
* Groups: 9 to 64 identical soldiers standing together form a formation under the original
  banner, freshly trained troops gathering at a rally point among them. A group is selected
  as a whole and marches as a block - the formation is laid out facing the way it travels,
  everyone gets the slot nearest to where they stand, and the block waits for stragglers
  instead of tearing apart. A group also fights as a group: when an enemy comes within
  sight the whole block advances on it, and single soldiers only strike what comes into
  their own reach instead of peeling off one by one
* A computer opponent that gathers, trains and attacks in waves
* The original mouse pointers, switching with context (attack, wood, gold, build, repair, …)
* A minimap built the way the original built its own: the map is shown as a diamond inside
  the game's own stone frame, the terrain is a real top-down render of the ground and
  everything owned by a player is stamped over it as coarse squares in their colour
* Hero mode: take direct third-person control of the hero, with the original's third-person
  animation set (directional runs, shield, combo swings, special attack); the soldiers around
  him become a retinue and follow him, and a fallen hero returns at his town center

Not there yet: armour values, terrain/maps, the other three civilizations.

## Performance

The game draws at the window's real resolution, which on a high density display is around
three times the 1920x1080 the project asks for. At that size the screen space effects cost
far more than the simulation does - measured with 60 units on screen: units, pathing and
combat together take about 3 ms per frame, while screen space indirect lighting alone took
about 50 ms. Quality is therefore a real setting, cycled with **F5** and remembered:

| Level | Effects | Measured |
|---|---|---|
| high | indirect lighting, ambient occlusion, glow, 4x MSAA, 8192 shadows | ~20 fps |
| medium (default) | ambient occlusion, glow, 2x MSAA, 4096 shadows | ~35 fps |
| low | no screen space effects, FXAA, 2048 shadows, 80% render scale | 60 fps (capped) |

Run with `-- --perf=2` to print the frame budget (frames per second, script, physics and
render time, draw calls) every two seconds.

## Layout

```
converter/        Java: reads data.ssa, converts .gr2 -> glTF (mesh, skeleton, animations)
                  and .dds/.sst -> PNG, exports unit/building data as JSON
game/             the Godot project
  assets/original/   generated by convert.sh (git-ignored, never edit by hand)
  assets/overrides/  your own replacement art - takes precedence, see the README there
  assets/nature/     CC0 tree models ("Stylized Nature MegaKit" by Quaternius)
  data/bonuses.json  class bonus table
  scripts/           GDScript (units, buildings, AI, HUD, selection, …)
  shaders/           player colour, terrain, selection rings
docs/FORMATS.md   reverse-engineered file format reference
```

## Working on it

Open the repository folder in your editor; `.vscode/` recommends the **godot-tools** and
**Java** extensions and provides tasks for running, editing and converting. Scenes, materials
and lighting are easiest to edit in the Godot editor itself (`./run.sh edit`).

Gameplay lives in `game/scripts/*.gd`, balance in `game/data/bonuses.json`, the asset
pipeline in `converter/src/com/rnf/`.

## Credits and licensing

* Trees and rocks: *Stylized Nature MegaKit* by [Quaternius](https://quaternius.com),
  CC0 (license file in `game/assets/nature/`).
* Interface icons (resources, game speed): [game-icons.net](https://game-icons.net),
  CC BY 3.0 - see `game/assets/icons/NOTICE.md` for the individual authors.
* Everything under `game/assets/original/` is generated from your own copy of the original
  game and is **not** distributed here. *Rise & Fall: Civilizations at War* is © Midway.
