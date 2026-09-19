#!/bin/zsh
# Rebuilds the Java converter and converts original assets from data.ssa into game/assets/original.
# Usage: ./convert.sh [unit ids...]   (without arguments: the default prototype set)
set -e
HERE="${0:A:h}"
DATA_SSA="${RNF_DATA_SSA:-$HERE/../Rise And Fall/Data/data.ssa}"
OUT="$HERE/game/assets/original"
CLASSES="$HERE/converter/build/classes"

mkdir -p "$CLASSES"
javac -d "$CLASSES" ${(f)"$(find "$HERE/converter/src" -name "*.java")"}

UNITS=("$@")
if (( ${#UNITS} == 0 )); then
  UNITS=(men_ymjavelin men_ymarcher_02 men_ymalexandermelee_02 cav_ymspear_l1 men_ymworker_02 men_yminfantry_l1_02 men_ymspear_l1_02
         bld_ymbarracks_02 bld_ymtowncenter_02)
fi
java -cp "$CLASSES" com.rnf.tools.Convert unit "$DATA_SSA" "$OUT" "${UNITS[@]}"
java -cp "$CLASSES" com.rnf.tools.Convert texture "$DATA_SSA" "$OUT" \
  'textures\trn_ybasegrasst.dds' 'textures\trn_ybasegrassdirtt.dds' 'textures\trn_ybasedirt.dds'

java -cp "$CLASSES" com.rnf.tools.ExportCiv "$DATA_SSA" "$OUT" Greek "A - Cit - Citizen (Greek)" \
  "A - Inf00 - Alexander Melee - RTS mode (Greek)" \
  "A - b  Statue Glory (Greek)" "A - b  Settlement (MP) (Tent) (Greek)" "A - b  Town Center (MP) (Greek)" "A - b  Barracks (MP) (Greek)" \
  "A - b  Archery Range (MP) (Greek)" "A - b  Stable (MP) (Greek)" "A - b  Spartan Academy (MP) (Greek)" \
  "A - b  Tower 1x1 (Greek)" "A - b  Market (Greek)" "A - b  Government Center (MP) (Greek)"
java -cp "$CLASSES" com.rnf.tools.ExportPointers "$DATA_SSA" "$OUT"
java -cp "$CLASSES" com.rnf.tools.Convert unit "$DATA_SSA" "$OUT" amb_ygoldmine_01
java -cp "$CLASSES" com.rnf.tools.Convert texture "$DATA_SSA" "$OUT" \
  'textures\sfx_ybaseformationflags_t.dds' 'textures\sfx_ymrallyflag_t.dds' \
  'textures\ui_ymrtst.dds'
java -cp "$CLASSES" com.rnf.tools.Convert model "$DATA_SSA" "$OUT" 'models\sfx_ymbaseformationflags_model.gr2'
java -cp "$CLASSES" com.rnf.tools.ConvertEffect "$DATA_SSA" "$OUT" 'models\sfx_ymrallyflag.gr2' \
  'textures\sfx_ymrallyflag_t.dds' 'animations\miscellaneous\sfx_yrallyflag_anim.gr2'
mkdir -p "$OUT/fonts" && cp "$HERE/../Rise And Fall/RAFC.ttf" "$OUT/fonts/rafc.ttf"

# Let Godot import the new files (and refresh its class registry).
godot --headless --path "$HERE/game" --import >/dev/null 2>&1 || true
echo "done."
