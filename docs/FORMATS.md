# Rise & Fall: Civilizations at War – file formats

Everything below was reverse-engineered from a retail installation and verified against the
files the converter reads. Offsets are decimal; all integers are little-endian. Where
something is a working hypothesis rather than a verified fact, it says so.

The engine is a descendant of the *Empire Earth* engine (same studio), which shows in the
database tables: every `db*.dat` table has its own hand-written parser inside the executable,
there is no generic schema.

---

## 1. `.ssa` archives

```
"rass" | u32 version | u32 reserved (0) | u32 fatSize
```

### Version 1 (campaign archives)

The directory is plain, right after the header, one entry per file:

```
u32 nameLength | name (nameLength bytes, NUL padded)
u32 dataStart | u32 dataEnd (inclusive) | u32 size
```

### Version 3 (`Data/data.ssa`, ~12,150 files)

The directory is obfuscated and compressed:

1. XOR the **first 32 bytes** of the directory with a fixed 32-byte key that lives in
   `LowLevelEngine.dll` (RVA `0x1c35f4`):
   `64 34 68 82 55 87 49 32 d3 02 01 b2 12 73 13 ff 59 21 39 57 54 30 ef a3 56 23 99 48 98 b1 a9 48`
2. The decrypted directory then starts with `u32 compressedLength`, followed by a standard
   zlib stream. Inflating it yields the plain directory.

Directory entry (after inflating):

```
u32 nameLength (including NUL)
    name (nameLength bytes, NUL terminated, 0xFF padded in front)
u32 start      (absolute offset of the raw data in data.ssa)
u32 end        (start + size on disk)
u32 rawSize    (size hint, not reliably the decompressed size)
u32 key[8]     (32-byte XOR key for *this* file only)
```

File contents:

1. Read `end - start` bytes at `start`.
2. XOR the first `min(size, 32)` bytes with that entry's own key.
3. Look at the first four bytes:
   * `"ZL01"` → `u64 rawSize` at offset 4, zlib stream from offset 12.
   * `"PK01"` → reported as compressed by the engine but never actually handled; unused.
   * anything else → the file is stored uncompressed.

`ZL01` blocks also appear standalone inside `.scn` and `.ees` files:

```
u32 blockSize (12 + deflate length) | "ZL01" | u64 rawSize | deflate stream
```

**Loose files win over the archive.** `FSPath::FindFile` walks the registered directories
first and returns as soon as it finds a file on disk, so dropping an uncompressed,
unencrypted file at the same relative path under the data directory overrides the archived
one – handy for experiments with the original game.

---

## 2. Models and animations: `.gr2` (Granny3D)

Granny 2.4/2.5 files, 32-bit, little-endian, format 6.

```
Header:   magic[4 x u32] | sizeWithSectors u32 | format u32 (0) | extra[8]
FileInfo: format i32 (6) | totalSize u32 | crc32 u32 | fileInfoSize u32 (56)
          | sectorCount u32 | type {sector, position} | root {sector, position}
          | tag u32 | extra[16]
Sector table: sectorCount x 44 bytes (compressType, dataOffset, compressedLength,
          decompressedLength, alignment, oodleStop0, oodleStop1, fixupOffset, fixupSize,
          marshallOffset, marshallSize - each u32)
```

Sectors are decompressed (type 0 = raw, type 2 = Oodle1) and concatenated into one flat
buffer. Then the per-sector **fixup** lists (triples of `srcOffset, dstSector, dstOffset`,
12 bytes each, located at `fixupOffset` in the *raw* file) turn every internal pointer into an
absolute offset into that buffer. No marshalling is needed for little-endian files.

The content is described by a self-describing **type tree**: 32-byte entries of
`type u32 | nameOffset u32 | childrenOffset u32 | arraySize i32 | extra[12] | extra4 u32`,
terminated by `type == 0`. Container types (INLINE, REFERENCE\*, \*ARRAY\*) point at another
type tree through `childrenOffset`; primitives read `arraySize` values from the data cursor.

One correction over the common open-source readers: for `REFERENCE_TO_VARIANT_ARRAY` and
`VARIANT_REFERENCE` the static `childrenOffset` is always 0. The real layout pointer is the
*third* field read while parsing that node (the `offset` member of the C struct); treating it
as a plain byte offset leaves vertex data empty.

Relevant structures:

* `ArtToolInfo.UnitsPerMeter` – 0.3281 in these files, i.e. **one file unit is 3.048 m**.
  Divide positions by it to get metres.
* `ArtToolInfo.UpVector = (0,0,1)`, `RightVector = (1,0,0)`, `BackVector = (0,-1,0)` – 3ds Max
  Z-up. Converting to a Y-up engine is `(x, y, z) -> (x, z, -y)`.
* `Meshes[].PrimaryVertexData.Vertices` – per vertex `Position` (3x REAL32), `Normal`,
  `TextureCoordinates0`, `BoneWeights` (4x NORMAL_UINT8), `BoneIndices` (4x UINT8).
* `Meshes[].BoneBindings[]` – vertex `BoneIndices` index into *this* list, not into the
  skeleton; map through `BoneBinding.BoneName`.
* `Skeletons[].Bones[]` – `Name`, `ParentIndex`, `Transform` (flags, position, quaternion,
  3x3 scale/shear) and `InverseWorldTransform` (4x4). That matrix has the same flat layout as
  a glTF inverse bind matrix and can be copied verbatim.
* Helper models named `-tag xyz` (`hpbar`, `attack`, `weapon_mount_01`, `impact_01`…) are
  marker bones the engine uses as attachment points.

Animation files contain no meshes, only `TrackGroups[].TransformTracks[]` with
`PositionCurve`, `OrientationCurve` and `ScaleShearCurve`. These use the old uncompressed
curve format: `Degree`, `Knots[]` (times in seconds) and `Controls[]` (one control per knot,
3 values for positions, 4 for quaternions, 9 for scale/shear). Degree 0 is a step curve.
Degree-2 curves are B-splines, but with knots every one or two frames the control points sit
practically on the curve, so emitting them as linear keyframes is visually indistinguishable.

Tracks are matched to bones by name; animation rigs often carry extra bones (fingers, toes)
that a given model does not have.

Effect models (rally flag, formation banner) are rigged and only take their real shape once
an animation plays – their bind pose has the flag pole lying flat. Convert them together with
their animation.

---

## 3. Textures

* `.dds` – standard DXT1/3/5, plus uncompressed surfaces (fourCC 0) where the channel masks
  in the pixel-format block describe the layout.
* `.sst` – two variants seen:
  1. a 15-byte header (`u8`, `u8 mipCount`, `u16`, `u16 0`, `u32 width`, `u32 height`, `u8`)
     followed by a complete, ordinary DDS file;
  2. the same header followed by an **uncompressed TGA** (type 2, 24/32 bpp, top-left origin)
     and its smaller mip levels – this is what the mouse pointers use.
* `.tga` – plain uncompressed true-colour Targa.

**The alpha channel of unit and building skins is the player-colour mask.** Fully opaque
texels keep the painted colour; where alpha is lower the player colour shows through, and the
alpha gradient carries that garment's shading (masked areas are painted near-black on
purpose). Units whose skin is DXT1 (1-bit alpha) cannot be player-coloured at all.

Trees are SpeedTree `.spt` files – procedural descriptions rather than meshes, so they cannot
be converted directly; only stumps and trunks exist as `.gr2`.

---

## 4. Object definitions: `.udf` / `.edf`

Tagged binary, magic `"USTRB\0"` for units and buildings, `"ESTR"` for effects. The leading
strings appear in a fixed order and are enough to resolve a unit's art:

```
"USTRB\0" | u32 0 | u32 nameLength | name
   then repeatedly: u32 ? | u32 ? | u32 ? | u32 subNameLength | subName | values...
```

* string 1 – the object name
* the first string containing `MODEL` – the model, i.e. `models\<name>.gr2`
* the string right after it – the skin, i.e. `textures\<name>.dds`
* further down, animation references as `<folder>\<animation>`, resolving to
  `animations\<folder>\<animation>.gr2`

The naming is not regular enough to guess from – e.g. `men_yMladderguy_MODEL_02` uses the skin
`men_yMsiegecrew_02T` – so always read the definition. Ambient objects such as the gold mine
name their model after the definition itself and have no `MODEL` string.

The record layout beyond those leading strings has not been decoded.

---

## 5. Database tables (`db\*.dat`)

Every table is `u32 recordCount` followed by fixed-size records. Strings inside a record are
NUL-terminated ASCII at fixed offsets.

### `dbobjects.dat` – 2012 bytes per record

| Offset | Type | Meaning |
|---|---|---|
| +104 | u32 | family index into `dbfamily.dat` |
| +120 | u32 | hit points |
| +196 | u32 | attack damage |
| +296 | u32 | display-name string id (resource string in `Language2.dll`) |
| +300 | u32 | button index into `dbButtons.dat` |
| +304 | u32 | graphics index into `dbgraphics.dat` |
| +908 | u32 | number of build-list entries the engine reads |
| +912 | u32 | this object's id (what build lists and the tech tree reference) |
| +1212 | u32[] | build list (object ids), `-1` padded |

The developer name is stored as the longest ASCII run inside the record
(`"A - Inf01 - Sword Infantry (Level 1 Greek)"`). Note that `+908` must be kept in sync when
adding build-list entries – the engine only reads that many slots.

Working hypotheses, consistent across sword/spear/archer/cavalry/citizen/hero/building
records but not confirmed in code. Distances are in game units (one unit = 3.048 m):

| Offset | Type | Meaning | Examples |
|---|---|---|---|
| +132 | f32 | attack range | melee 0.6 · cavalry 0.8 · archer 8 · javelin 10 |
| +136 | f32 | line of sight | 8–10 |
| +140 | f32 | attack interval (s) | sword 1.8 · spear 2.1 · archer 4.0 · cavalry 1.0 |
| +148 | f32 | movement speed | archer/spear 0.8 · sword 1.0 · cavalry 1.4 |
| +156/+160 | f32 | turn rate (rad/s)? | 12.2 / 14.0, cavalry 7.0 |
| +192 | u32 | attack type | 0 melee · 1 ranged · 2 cavalry · 3 building · 5 citizen |
| +560…+572 | u32 | impact/sound effect groups, **not** bonuses | sword 4/4/4/4 · archer 24 · every building 26/20 |
| +580 | u32 | armour? | infantry 15–20 · archer 16 · cavalry 43 · buildings 61 |
| +712/+716 | f32 | footprint | infantry 0.45 · cavalry 0.75 x 0.95 |

There is **no civilization field** in the object record; the only discriminator available is
the developer name, which spells it out ("(Level 1 Greek)").

### `dbtechtree.dat`

One 44 x u32 entry per trainable unit, research or building, recognisable by `[2] == 14`. The
100 bytes in front of an entry hold its name.

| Field | Meaning |
|---|---|
| `[0]` | object id (matches `dbobjects +912`) |
| `[1]` | category (5 = unit/building, ≥6 research, 4 = scenery) |
| `[3]`, `[4]` | `-1` on working entries |
| `[5]` | wood cost *(hypothesis)* |
| `[7]` | build/training time in quarter seconds *(hypothesis)* |
| `[10]` | gold cost x1000 *(hypothesis)* |
| `[11]` | prerequisite id (0 = available immediately) |
| `[15]` | record index in `dbobjects.dat` |
| `[16]` | button index |
| `[18]` | name string id |
| `[29]` | UI class |

Examples for the cost reading: swordsman 19000/0, spearman 24000/25, archer 28000/30,
cavalry 42000/0, citizen 25000/0, barracks 50000/325, town centre 60000/350.

#### Upgrades

Every unit line exists five times, once per level, each as its own object with its own name
(Greek swordsmen: *Hypaspist → Improved Hypaspist → Companion → Improved Companion → Royal
Guard*). `[1] - 4` is that level, and `[11]` names the research that unlocks it. The research
entries themselves look the same and are recognised by the fact that no object carries their
id; their name sits in the 100 bytes in front of the entry, and their player-facing name is
the string id in `[18]`.

A research entry carries an appendix at **entry + 348**:

```
u32 count | count x u32   dbobjects record indices of the buildings offering the research
u32 count | count x u32   what it unlocks: unit object ids and follow-up research ids
```

Example, *UP - Inf Sword 2 (Greek)*: 8 buildings (the barracks of all four civilizations in
their MP and SP variants) and `[UP Sword 3, 8425, Sword Infantry Level 2]`. The appendix has
variable length, so values can be swapped safely but lists cannot be extended in place.

A research enters a building's panel exactly like a unit: its id is in the building's build
list, its button is `[16]`, and that button's `+216` decides the slot. The upper row (0–6)
holds the upgrade for the unit directly below it (slot N over slot N+7).

Research entries have no build time of their own (`[7] == 0`); the original presumably
derives it elsewhere.

#### Hero levels ("epoch" techs) and glory

The hero's own build list holds the entries `ACTION - LEVEL 02` … `ACTION - LEVEL 10`: the
hero is where you spend glory to level up, and each level unlocks the next tier of everything
else. `LEVEL 02` unlocks 27 entries for the Greeks (among them the ballista research and the
Spartan Academy), `LEVEL 05` unlocks the fire raiser.

That makes `[1] - 4` a **requirement** as well as a level: an entry becomes available when its
prerequisite research is done *and* the hero has reached that level.

Costs split by currency: units and buildings are paid for with `[10]` gold (x1000) and `[5]`
wood; researches - unit upgrades and hero levels alike - are paid for with glory, again
`[10]` x1000 (unit upgrade 40, hero levels 60/70/80/90). Glory itself is earned for kills,
for your own losses, for finished buildings and from glory statues; the rates are not in the
data files (only techs that *increase* them are: "Tech - Glory Killing Increase",
"Tech - Glory Losses Increase", "Tech - Glory Building Construction Increase", advisors).

### `dbButtons.dat` – 232 bytes per record

`+100` icon path (without extension), `+204` own index, `+216` panel slot. The command panel
has 14 slots: 0–6 upgrades (top row), 7–13 units (bottom row); slot N sits above slot N+7.
A slot of 0 means "no fixed slot" rather than "slot 0": such entries go into the first free
cell of the row their kind belongs to, and only upgrades are auto-placed that way.

### `dbgraphics.dat` – 212 bytes per record

`+0` object name, `+100` definition name – i.e. `units\<name>.udf`, **not** the model. That is
one indirection more than expected: object → `+304` → graphics → `.udf` → `.gr2` + `.dds`.

### `dbfamily.dat` – 412 bytes per record, 81 families

`+0` name (100 bytes), then a string id, the family's own id and 77 `u32` percentages. This is
the Empire-Earth-style effectiveness matrix (families such as `Human Sword`, `Human Spear`,
`Lancer`, `Human Archer`, `Chariot`, `War Elephant`, `Towers`, `Building`, `Citizen`).
`dbweapontohit.dat` complements it with six weapon classes (Shock, Arrow, Pierce, Gun, Laser,
Missile), all of which are 100 in the shipped data.

**Open:** which column corresponds to which family could not be settled from the bytes alone
(candidate offsets 0 or 2). Suspicious: nearly every row has 75 at the `Citizen`/`Tree` column
and 5000 at the `Mounted Spear`/`Medieval Field Weapon` column – 5000 does not fit a plain
multiplier, so a row may mix multipliers with something else.

### `dbmousepointer.dat` – 224 bytes per record, 63 records

`+0` pointer name (100 bytes), `+100` texture path (100 bytes), then six `u32` (running numbers
and two string ids). There is **no hotspot column**. States include Normal, Attack, Attack
Move, Invalid Target, Wood, Mining, Build, Repair, Heal, Garrison, RallyPoint, Patrol.

### `dbmusic.dat` – 216 bytes per record

References plain MP3 files under the music folder by name (`+8` folder, `+108` file name).
The bytes at +198…+205 select which civilizations a track belongs to; the two values at +208
and +212 are a byte window into the MP3 (start/end) that the engine uses to cut tracks – 0/0
means "play the whole file".

### Table registry

Ids as used by the loader: 1 music, 2 objects, 3 graphics, 5 buttons, 6 techtree, 9 family,
11 aiunittargeting, 12 terrain, 15 world, 16 randommap, 17 civilization, 20 weapontohit,
21 calamity, 22 unitset, 23 areaeffect, 25 upgrade, 26 cpbehavior, 28 animals,
29 unitbehavior, 30 startingresources, 31 gamevariant, 32 premadecivs, 34 civpowers,
40 civspecificunitdefines, 52 civspecai, 53 crewedunitdetails, 55 soundgroups, 58 flora.

---

## 6. Scenarios and saved games

`.scn` (scenarios) and `.ees` (saved games) share one format: an uncompressed header with
readable strings (name, description, player list, timestamp, map name) followed by several
`ZL01` blocks. In a typical saved game, block 1 is the terrain/tile grid (starting with
`u32 width, u32 height`), block 2 holds triggers with plain-text names, block 5 the unit and
object state, block 6 effects.

---

## 7. Other content

* UI layouts are plain XML (`user interface\*.xml`): forms, controls, colours and coordinates
  on a 1600x1200 design canvas.
* AI behaviour scripts (`.tai`) are plain-text state machines: a state name on its own line,
  then indented `Condition[(param)] true(NextState)` lines, `allof(...)` to combine
  conditions, `//` for comments.
* Random map scripts (`.rmv`) are plain text as well.
* Sounds are ordinary WAV and MP3; cut-scenes are Bink video (`.bik`).
* Display names live in `Language2.dll` as ordinary Win32 `RT_STRING` resources (4631 of
  them), referenced by `dbobjects +296`.
* Graphics options are stored in the Windows registry, not in a config file.

### The minimap

Worth knowing if you rebuild one, because the assets give the recipe away:

* Every ground texture has a small twin for the map: `textures\ui_x<terrain>.sst`, 64x64
  uncompressed RGBA with a full mip chain (`ui_xbasegrass_00`, `ui_xdeepwater_00`,
  `ui_xforestdesiduous`, …). The map is painted from those, which is why it looks like the
  real terrain rather than a colour key.
* Everything that belongs to a player is stamped on top as a plain white square,
  `textures\ui_square.sst` (64x64, DXT), tinted with the player colour - hence the coarse
  pixel blocks for buildings.
* `textures\sfx_xradar.sst` holds the green view wedge, `sfx_xminimaparrow(s).sst` the
  arrows that point at events off screen, and `effects\sfx_*minimap*.edf` drive the flare
  and "under attack" markers.
* The frame is a 3D model like the rest of the interface (`models\ui_ymminimap_model.gr2`,
  `units\ui_ymminimap.udf`), textured from the civilization's interface atlas
  `textures\ui_ymrtst.dds` (1024x512). The stone diamond sits at (53, 0) and is 312x308
  pixels; its middle is painted black - that is the hole the map is drawn into.
