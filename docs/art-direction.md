# Pixel art workflow

Current direction: keep the recovered Java ME graphics while rebuilding the map
viewer and, later, game mechanics. Generate replacements when the user requests
them. The original assets remain the working visual reference.

Lightning follows the supplied original-game screenshot: a tall white bolt with
fine yellow branches. Preserve image 192 (39×94) at native scale. As in
`analysis/decompiled/i.java`, stack two copies above the target cell center,
offset them horizontally by +12 and +6 pixels, and reveal them downward in
47-pixel steps every 100 ms. The full column is 188 pixels high; do not squash
it into the generic 24×32 spell rectangle. Preview in Godot with
`-- --capture-lightning` (output: `build/stage6-lightning.png`).

Blessing uses original image 201: a 48×32 foot section with its top 48×23
strip repeated upward to the viewport edge, at 7/15 opacity. The user approved
the continuous white-and-gold column in the Godot preview; retain it without
gaps despite the segmented reference screenshot. Follow `x.java` for the
expanding and contracting horizontal clip over 2.5 seconds. Preview with
`-- --capture-blessing` (output: `build/stage6-blessing.png`).

Project skill: `.agents/skills/allods-pixel-art/SKILL.md`.

Meteor follows the supplied falling-rock and debris screenshots. Preserve the
27×40 image 195 and 12×13 image 196. As in `ag.java`, the large stone falls
vertically from 190 pixels above its landing height, accelerates by two pixels
per source tick, and hits after 14 ticks. Ten source shards then scatter,
bounce and briefly rest, following `h.java`; their visual randomness must not
advance combat RNG. Preview both phases with `-- --capture-meteor` and
`-- --capture-meteor-shards` (`build/stage6-meteor*.png`).

Fire Arrow retains the four original 20×20 frames of image 190, selected by
the axis/diagonal direction rules in `w.java`. Reconstruct its original 40×40
orange radial glow from `m.t()` and surround it with small yellow sparks, as
in the supplied screenshot. Preview with `-- --capture-spell`
(`build/stage6-spell.png`). No replacement raster artwork is required.

Frost gains a soft blue glow at the user's request, using the same radial
falloff as Fire Arrow in a cold blue palette with 75% peak opacity. Draw the
48×56 halo behind the existing ice sprite so its pale center remains readable.
Preview with `-- --capture-frost` (`build/stage6-frost.png`).

Ordinary management screens follow the supplied original-game menu references:
the frozen world becomes monochrome at 45% brightness, while green bitmap text,
portraits, items and the gold pointer retain their color. Avoid desktop item
lists, dropdowns and debug statistics in these flows. Inventory starts with a
party list and then a per-item carousel, including blue comparison arrows and
equip/remove actions. Character uses portrait arrows, base/effective attributes,
an XP bar for progress within the current level, and contextual training hints.
Journal uses a quest list and a scrollable full description in the same style.
Keep the original atlas assets; the older management panel is a DEV tool.

| Role | Responsibility | Handoff |
| --- | --- | --- |
| Art director | Maintain the visual language: palette, pixel density, perspective, lighting, silhouettes and scale. | A concise style brief and one representative reference set. |
| Sprite artist / animator | Produce terrain, objects, characters and consistent animation frames from that brief. | Versioned PNGs plus frame layout, anchors and generation prompts. |
| Technical artist / asset QA | Check alpha, frame sizes, foot anchors, atlas crops, Godot filtering, layering and in-engine appearance. | Integration metadata, engine preview and a record of checks. |

These are reusable role briefs within one project skill, not persistent running
workers. Roles can be handled in sequence; separate agents can use the same briefs
when delegated work is requested.

The shared asset contract is described in the skill's `references/roles.md`.
The existing `tools/legacy_graphics.json` records original dimensions and origins;
`godot/data/legacy/graphics.json` adds exported texture paths. The 16-pixel logical
grid does not mean every image is 16×16: terrain objects span multiple cells and
character frame sizes vary by type and direction.

Do not replace an atlas blindly with a generated sheet. Check the actual PNG
dimensions and frame layout, then make a Godot preview. Generated pixel art can
require cleanup; consistency and seamless animation are verified outcomes.

HD portrait and spell icons are now optional through Settings. Active derived
resources live in godot/data/hd/icons, next to the legacy export, as requested.
Use the existing concept sheets as masters; preserve their original IDs and
record actual crop rectangles in the production manifest. World sprites, map
art and spell animations retain their original Java ME graphics.

Character portraits now fit the available slot uniformly and remain centered;
the 40×52 portrait canvas is no longer stretched into a 48×52 slot. The existing
HD source sheets are retained. Desktop-theme cursors from Allods I/II are decoded
with their original 32×32 alpha masks and hotspots; combat combines the gold
pointer with the selected action/spell icon in a 48×48 canvas. Source mappings
are in data/hd/cursors/manifest.json. No new cursor artwork was generated.

Optional CRT now uses a pronounced aperture-grille treatment at the user's
request for a RetroArch-style effect: brightness-dependent scanline beams,
visible RGB phosphor stripes, gamma-correct glow and edge darkening. Integer
output-pixel pitch scales with viewport height. Preserve square pixel geometry
and exact mouse alignment; screen UVs remain unchanged. No temporal flicker.
The setting starts off and persists independently of saves.
Visual reference: https://docs.libretro.com/shader/crt/ (CRT-aperture).
The shader is an original implementation, not a port of a RetroArch preset.
In-engine QA captures: build/portrait-li-fixed.png, cursor-spell.png, crt-off.png,
crt-on.png and settings-crt.png (tests/capture_interaction.gd).
