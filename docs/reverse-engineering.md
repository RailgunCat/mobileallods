# Recovered formats and gameplay reference

## Scope and provenance

Input: `allods_360x640_bluetooth_rus.jar`, 473,810 bytes.

SHA-256: `b64126c1fa29a0cd75e4f48f23be28fb9fcb5f1c6c99c4dca59d57a7331ffd2a`.

The manifest declares `Container.GameMIDlet`, CLDC 1.0 / MIDP 2.0, version 1.0,
vendor Nival Interactive, original display 176×208 and target display 360×640.
The title and wrapper contain distributor/modifier strings. These identify this
particular file; they do not establish how closely it matches an original release.

Findings below come from the supplied bytes and CFR output. Format roundtrips are
verified. Gameplay semantics are static analysis, awaiting comparison with the
running original. CFR has renamed duplicate members for readability; source
locations/method names refer to `analysis/decompiled/`.

## Code navigation

| Class | Observed responsibilities / useful entry points |
| --- | --- |
| `Container/GameMIDlet` | MIDlet lifecycle and startup into `m` |
| `m` | Main canvas, rendering/input, map loading, pathfinding, turns, campaign interpreter, saves; `g(int)` loads scenes, `M()` dispatches scene opcodes |
| `g` | Large state/menu controller, resource streaming, dialogue, quests, character/inventory screens, multiplayer states |
| `n` | Unit/entity construction, type, equipment, stat references, coordinates, AI/movement and serialization |
| `q` | 57-slot stat vectors; base/equipment/crystal aggregation, derived stats, timed effects, damage, regeneration |
| `ab` | Items/equipment, sockets, copying and serialization |
| `s` | Static tables: action descriptors, opcode lengths, animation/image mappings, unit names, prices and other constants |
| `j` | XOR resource-pack reader |
| `ae` | Bitmap-font loading/drawing and Java UTF record utilities |
| `aj` | Structured groups from `common.utf` |
| `c`, `e`, `l`, `t` | Bluetooth L2CAP connection, server, discovery and discovery callbacks |
| `com/hellomoto/fullscreen/FullCn` | Full-screen GameCanvas adapter, key remapping and touch handling |

The class letters have no semantic meaning. Java ME, Nokia drawing APIs and
Bluetooth classes are platform dependencies, not bundled source. Some decompiled
expressions are clearly unreliable (duplicate iterator advancement, reconstructed
types and cross-package references); confirm important rules against bytecode or
the running original before reproducing quirks.

## Image packs: `res/res0.pak` … `res/res4.pak`

```
u32 big endian: entry_count
u32 big endian[entry_count]: payload lengths
byte[length[0]]: entry 0 XOR 0x53
byte[length[1]]: entry 1 XOR 0x53
...
```

There are no filenames or compressed payloads in this container. The surrounding
JAR provides ZIP compression. `j.a(String, byte, Class)` reads the size table;
`j.byte_arr_a()` applies XOR; `g` passes key 83 (`0x53`).

| Pack | Entries | Global IDs |
| --- | ---: | --- |
| res0 | 54 | 0–53 |
| res1 | 41 | 54–94 |
| res2 | 53 | 95–147 |
| res3 | 57 | 148–204 |
| res4 | 75 | 205–279 |

Global ID 2 is a font descriptor with five Java UTF records: character set,
cell width, height, another layout parameter, and space-separated glyph widths.
`ae.void_a(DataInputStream)` defines their use. All other 279 packed entries are
PNGs. The separate `res/icon.png` is an additional PNG outside these packs.
The extractor validates signatures and every PNG chunk CRC, and preserves order.

## Maps: `res/*.map`

```
u16 little endian: width
u16 little endian: height
u8[height][width]: encoded source tile ID, row-major
source_tile_id = byte - 128
render_image_id = tile_image_ids[source_tile_id]
```

All 18 files match `4 + width*height` exactly. Source IDs range from 0 to 45.
Each cell is 16 original game pixels. The mapping is in `m`'s constructor and
exported as `constants.json.tile_image_ids`.

`1.map` … `12.map` correspond to zero-based campaign scene IDs 0–11.
Five `net*.map` files are network maps. `101.map` is also present: 18×38 tiles, mostly grass with a vertical road turning right, rocks along the top and
water along the bottom. Its role is unconfirmed. Script 15 requests
map 100 (asset 101), but `m.P()` initializes `b[15]=2` and no recovered scene
script enables it. The explorer displays it without a campaign scene.

Important for new graphics: several tile IDs anchor larger decorative objects.
The original `m.b(int,int)` marks multi-cell collision footprints, including cells
above/left of an anchor. A source tile is not always an independent square of
walkable terrain. The Godot viewer now renders original ground, large objects,
sprites, and foreground crowns in separate passes with their recovered offsets.
Collision, visibility and dynamic-object simulation still need to be restored.

## Russian text: Java `DataInputStream.readUTF`

Each file is a sequence of records, without an initial count:

```
u16 big endian: encoded byte length (not number of characters)
byte[length]: Java modified UTF-8
repeat until EOF
```

Modified UTF-8 encodes NUL as `C0 80` and supplementary characters through UTF-16
surrogate pairs. The toolkit implements this format rather than assuming ordinary
UTF-8. Empty strings are structural separators. JSON preserves them and all
record positions; plain `.txt` exports are reading aids.

Nine files contain 1,461 records: `1.utf`, `2.utf`, `common.utf`, `dialogs0.utf`,
`dialogs1.utf`, `messages.utf`, `quests.utf`, `rumours.utf`, `skills.utf`.

`aj` reads named UI/name groups from `common.utf`, skipping comment records.
`g` selects `dialogs[t / 55].utf`; helpers in `ae` use empty-record boundaries to
select blocks. Preserve separator conventions when porting dialogue IDs.

## Ability and reward tables

Both files are tab-separated text with CRLF, `//` comment rows and a leading
label column (empty in abilities). Row position is a game ID. The extractor keeps
numeric values as indexed arrays because the headers contain duplicate names.

- `abilities.txt`: 148 rows, **56 explicit numeric columns**. `q` allocates 57
  integers per stat vector. The legacy parser asks for 57 values, consuming CR/LF
  as delimiters; the last slot remains zero for these rows. Keep that distinction
  when importing into Godot. JSON stores the 56 explicit values only.
- `rewards.txt`: 18 rows, labels such as `swordsman`, `arch`, `heal`, then 44
  numeric columns: experience, minimum/maximum gold and item-related values.
  Precise item probability/scaling semantics need further tracing.

Observed ability row groups from `q` lookups and table comments:

| Rows | Use |
| --- | --- |
| 0–14 | Crystals in armor, 3 tiers × 5 elements |
| 15–89 | Crystals in weapons, weapon-family/tier/element combinations |
| 90–107 | 18 unit archetypes, indexed by `90 + unit_type` |
| 108–111 | Additional special ability rows; trace call sites before naming |
| 112–147 | Equipment bases, indexed by `112 + item_id` |

Stat slots from the original header (retain its spelling when mapping data):

| Slots | Meaning |
| --- | --- |
| 0–8 | current HP, MP, movement, poison, stun, stone, dead, XP, level |
| 9–13 | constitution, intelligence, strength, dexterity, luck |
| 14–20 | max HP/MP, movement, sight, attack range, HP/MP regeneration |
| 21–26 | physical/black/white resistance and absolute resistance |
| 27–32 | physical/black/white bonuses and absolute damage/bonuses |
| 33–39 | speed/sight/range attack modifiers, poison, stun, vampiric, pierce |
| 40–45 | attack, defense, tactics, shooting, kill, athletics |
| 46–50 | five elemental columns (fire/earth/water/air/astral) |
| 51–55 | second elemental group; distinguish its role by action call sites |
| 56 | implicit zero slot in these data rows |

## Confirmed examples of calculations

`q.a(n, ab, ab)` aggregates base stats, equipment and socket crystals, then calls
`q.void_b()` and `q.void_c()` to derive and clamp values. Java integer division
truncates toward zero: reproduce it explicitly, especially for negative effects.

In `m.int_d(level)`, start with 100, and repeat `scale = scale * 11 / 10` once
per level. This performs rounding at **each iteration**.

Examples from `q.void_b()` (values on the right are the accumulated inputs):

```
max_hp = (max_hp + constitution) * level_scale / 100
max_mp = max_mp + intelligence + level
mana_regeneration += 1 + level
movement += dexterity / 15 + level / 5
```

`q.void_c()` adds skill effects and clamps movement to 1–20 and mana regeneration
to at most 30. `q.a(n, ab, ab)` retains current HP/MP while recalculating the stat
vector and handles remaining movement. `q.d()` advances timed effects, applies
poison, replenishes mana up to max MP, and heals by `max_hp * hp_regeneration / 100`
when positive, then caps HP at max HP.

`q.a(q)` applies attacks to its receiver. It contains randomized physical damage,
resistance division, blocks/dodges, critical/kill-like checks, status application,
and black/white effects including healing/revival in some cases. Port this as a
tested simulation after establishing original RNG behavior. Do not replace it
with a generic RPG damage formula and assume parity.

## Scene format: `res/scenes.pak`

This file uses a different format from image packs, with **no XOR**. It contains
12 consecutive scenes; there is no leading scene count. Each scene has three
groups in order: scripts, trigger rectangles, unit records.

```
for each scene:
    for group in [scripts, triggers, units]:
        i32 big endian: row_count
        repeat row_count:
            i32 big endian: row_length
            i32 big endian[row_length]: values
```

`m.g(int)` parses this structure. All 17,884 bytes are consumed exactly.

Triggers are five integers: `[script_id, min_x, min_y, max_x, max_y]`, with
inclusive comparisons in `m` and original pixel coordinates. Unit records are
9 or 10 integers: `[spawn_id, x, y, unit_type, group, ai_flag, p6, p7, p8,
optional_direction]`. The constructor maps `p6/p7/p8` to `n.x/y/z`; their full
meaning remains unconfirmed. Avoid renaming `ai_flag` to a faction without tracing
the combat/party code. Unit type names come from `s` and are exported as metadata.

Script rows start with a script ID, then instructions whose lengths include the
opcode. `s.var_int_arr_b` supplies lengths; `m.void_d(int)` indexes instruction
boundaries; `m.M()` executes them. All 147 scripts decode fully to 450 instructions
using this table. `godot/data/scene_scripts.json` provides a derived disassembly;
edit `analysis/extracted/scenes.json` and re-export to regenerate it.

| Opcode | Length | Observed behavior / current interpretation |
| --- | ---: | --- |
| 0 | 3 | Set script/trigger state flag |
| 1 | 3 | Set quest-like state; refresh notification state |
| 2 | 8 | Scripted unit movement with relative target and flags |
| 3 | 2 | Show dialogue block |
| 4 | 2 | Timed screen shake/effect |
| 5 | 2 | Recruit unit selected by group |
| 6 | 4 | Conditional comparison of a flag array entry |
| 7 | 2 | Remove party member into world units |
| 8 | 1 | Clear current script activation flag |
| 9 | 1 | Conditional end marker |
| 10 | 1 | Map-completion state transition |
| 11 | 3 | Change map/entry parameters |
| 12 | 3 | Set unit state by spawn ID; state 2 removes it |
| 13 | 3 | Set another flag array; exact meaning unconfirmed |
| 14 | 3 | Set another flag array; exact meaning unconfirmed |
| 15 | 2 | Show one-time help/message via `m.boolean_a(int)` |
| 16 | 3 | Set unit direction |
| 17 | 1 | Else-like skip to end marker |
| 18 | 3 | Reposition party to pixel coordinates |
| 19 | 4 | Set/clear group collision via `n.k()` / `n.j()`; optionally include shattered bodies |
| 20 | 3 | Reset dead/shattered flags by group; optionally include shattered bodies |
| 21 | 2 | Mark group for an encounter and store notice unit type |
| 22 | 1 | Request forced encounter after the script |

## Saves and Bluetooth

`m.N()` writes seven RMS records per save slot; `m.O()` and adjacent methods read
them. Other RMS stores include `system` and `net`. These saves are runtime data;
there are no user save files embedded in the JAR. Godot uses a separate version-1
JSON format with five slots, full numeric precision, checksums and backups.
Loading validates a detached world before replacing the live session; RMS import
is not implemented. Integer serialization helpers
near `m.c(byte[],int)` use little endian, unlike scene/PACK integers.

Bluetooth uses JSR-82 L2CAP with 512-byte requested MTUs, service name
`RageOfMages`, and UUID `123430405060308090C0B0C0D0E0F011`. Game-level send/receive
branches are in `g` and `m`. The protocol is not yet documented or implemented in
Godot.

## Verification and next uncertainties

Verified: PNG chunk CRCs; all resource decoder/encoder roundtrips; byte-for-byte
equality of all 79 unchanged JAR payloads; an edited map/string/table/scene surviving
rebuild and extraction; 450 script instruction boundaries; loading/drawing all
18 maps in Godot 4.7.2 with original artwork, input and zoom; unchanged export of
all 279 packed PNGs; original atlas metadata and trimmed-edge handling; rendered
previews of maps 1, 7 and 12.

Remaining: emulator baseline; exact collision/visibility and dynamic-object rules;
full script parameter names and campaign state semantics; stat slot 56 usage;
RNG equivalence; original rendering/animation alignment; reward scaling; save and
multiplayer protocols. The Godot viewer displays original artwork and source
spawns; it does not simulate these systems. Constructor-randomized unit directions
use a deterministic left-facing preview unless the scene supplies a direction;
the hermit retains its constructor's down-facing default.

## Original-art rendering in Godot

`tools/legacy_graphics.json` records the observed `m.g/j/k(Graphics)` draw offsets
and `s` unit frame sizes, origins, image IDs, frame columns/rows and idle indices.
`export-godot` copies packed PNG bytes unchanged and adds paths in
`data/legacy/graphics.json`. Re-exporting requires the documented source JAR build.

`legacy_map_view.gd` draws repeating image 26, ground/decorations, unit shadows,
objects and units ordered by their original anchor cells, and foreground crowns.
Water cycles through images 36–43 using the original 62ms loop interval. Walking
and attack animations are not played as idle motion; bats retain their ambient
cycle. A few atlases trim blank trailing pixels; source regions are intersected
with the real image before drawing instead of stretching edge texels.

The map viewer shows all raw unit records, including mutually exclusive scripted
spawns. Party progression, scripts, pickups, fog and runtime effects are outside
this viewing milestone. PNG previews are not claims of running-game parity.


## Presentation checks from source and video

`m.o(Graphics)` selects the original overlays 202/203 for remaining-AP fields;
shooting/spells use the green image within Manhattan range. `v` text effects rise
one pixel and live twenty draw steps. Godot moves that clock out of drawing and
queues separate messages. `m.java:655` omits portrait MP bars for types 0/1;
other casters have independent green HP/blue MP indicators.

`ad`/`a` implement rain: five new streaks per draw layer, +4/+8 pixel displacement,
then image 63 on blocked ground. Entry methods V/W/Z/aa/ab/ae create persistent
rain layers; opcode 4 adds 180-second rain after the quake. The Godot visual hash
is intentionally separate from simulation RNG, so density/timing is an explicit
presentation approximation.

Scene 2 script 22 recruits group 2 (Kurt), completes quest 14 and enables city
exit 23. This is the unlock condition for the world map and city. Town tutorial
15 is shown once. `bgsound.mid` and `bgsound1.mid` are unencrypted ordinary SMF
resources; `tools/render_music.py` prepares native OGG playback through the installed
JDK General MIDI synthesizer and FFmpeg while retaining both source MIDI files.
Detailed battle/progression storyboards and caveats are in
[walkthrough-notes.md](walkthrough-notes.md).
