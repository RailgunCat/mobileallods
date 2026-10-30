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

HD battle portraits resolve creature identity through unit_portrait_images,
not the shared dialogue portrait table. Bat/vampire type 12 uses image 212;
squirrel, goblin, skeleton and other creatures use their own unit portrait IDs.
Hero portraits retain the established dialogue portraits. With HD off, creatures
use their original unit portraits as requested, so bats and skeletons retain
their identity in both modes. A missing HD creature portrait falls back to the original
unit portrait, and all HUD portraits fit their slots without stretching.
During the enemy turn, the lower combat HUD keeps the acting enemy's identity;
recent hit feedback must not replace it with the allied victim's portrait.
Real enemy-turn captures before/after impact: build/bat-enemy-turn-start.png and
bat-enemy-turn-after-hit.png (tests/capture_bat_portrait.gd).

HD tavern and shop now reuse the generated interiors from hd-menu-v1 (original
image IDs 278 and 276). Active versioned copies live in godot/art/ui/hd-town-v1,
with the original generation prompts and a SHA-256 manifest. These are opaque
1672×940 / 1672×941 background paintings, not tile or animation sheets; logical
map footprints and anchors do not apply. No new image generation was needed.
User approved the prototype and requested the project's existing fonts and
frames for both tavern and merchant. Use LegacyTheme's original bitmap font,
stone atlas frame and button styles; do not introduce a separate serif font or
replace the frame with generated decorations. Interior art is linearly filtered;
original items and UI retain nearest filtering. Canvas layout is 1280×800 with
the existing viewport stretch. The generated host remains visible to the right.
The HD setting now reads “HD-режим” and includes these screens. Missing local
backgrounds fall back to the legacy screen; town/world map stay in legacy style.
Rumours, jobs, real item stock, prices, comparison and confirmation continue to
use the existing controllers and rules. QA: tests/hd_town_checks.gd checks mouse
transactions, modal input, dialogue scroll, HD toggle and resized window input;
build/hd-town-*.png contains the in-engine previews.

Firewall uses the original flame PNG with independently swaying vertical strips,
a breathing glow and rising pixel embers; keep its feet anchored to the hazard
cell. It samples presentation time without consuming combat RNG. Green movement
route dots are visible in ordinary battle movement mode, including hover preview.
In-engine QA captures: build/portrait-li-fixed.png, cursor-spell.png, crt-off.png,
crt-on.png and settings-crt.png (tests/capture_interaction.gd).

Inventory and character-training proposals v2 are saved under
`godot/art/concepts/hd-management-v2`; see `docs/inventory-character-concept.md`
for the checked rule constraints and interaction brief. They are static visual
proposals, not active screens. Keep separate attribute/skill budgets, the displayed
skill cap of 24 (internal base value 25), and only weapon/armor equipment slots.
The user requested a doll that changes with equipment: plan separate body,
armor, weapon and hand/occlusion layers plus a clearly marked try-on preview.
The current composite illustrations do not yet supply those layers. At integration,
use the project's real font/theme and compute bars/comparisons from game state.

Magic presentation pass: retain the Java ME spell sprites and add code-drawn
pixel trails, motes, rings and palette glows in `spell_vfx.gd`. Ten casts now
have distinct motion; all fifteen spells have bounded impact feedback. Keep the
existing lightning, meteor, fire-arrow, frost and blessing cores. Sample visual
time at the source 62 ms interval, without drawing from the combat RNG.
AOE previews show the shared gameplay geometry: amber affected cells, pale blue
possible frost cells, red allied danger cells. Hide the movement range while
showing an AOE so the two overlays remain readable.
Technical QA: `tests/spell_presentation_checks.gd` and native GPU captures from
`tests/capture_spell_effects.gd`; galleries `build/spells-after-cast.png` and
`build/spells-after-impact.png`, individual `build/aoe-*.png`. The capture also
checks that the ten enhanced casts change pixels over time and leave the battle
snapshot unchanged. This pass does not introduce replacement raster art.

HD management windows now use a 1280×800 code-built layout inspired by the v2
inventory/training proposals: deep green panels, muted gold, the project bitmap
font, original stone frames and shared button styles. Inventory has a shared
16-item paged bag, class compatibility, equipment comparison and a modal socket
picker. Character development keeps separate attribute/skill budgets. Journal
uses a quest list and a reflowed description. HD portraits and original item icons
remain the active artwork; no composite concept PNG with baked labels is used as
an interactive screen. A full-body equipment doll still needs separate layers.
Switching off HD restores the Java ME management screens. Actual GPU previews
are `build/hd-management-*.png`, produced by `tests/run_hd_management_checks.gd`
with `-- --capture`; mouse tests also cover a 1600×900 resized window.

HD menu integration reuses the existing text-free red-hood painting from
`art/concepts/hd-menu-v1/01-main-menu-background-v1.png` as the versioned active
`art/ui/hd-menu-v1/title-v1.png` (1672×941, opaque RGB, SHA-256 in its manifest;
original generation prompts copied alongside). No new raster generation or
edits were needed. Preserve the figure on the right and keep the title buttons
in the quiet left area. The canvas is 1280×800; only the painting uses linear
filtering. Titles, menus, settings, help and save slots use the project bitmap
font, stone frame and button styles. Pause overlays the frozen game; title
settings and loading retain the painting. Network remains explicitly unavailable.
HD off and a missing title painting use the original title presentation.
GPU previews: `build/hd-menu-title.png`, `hd-menu-pause.png`, `hd-menu-settings.png`,
`hd-menu-load.png`, `hd-menu-save.png`, `hd-menu-controls.png`, `hd-menu-combat.png`
and `hd-menu-resized.png`; generated by `tests/run_hd_menu_checks.gd -- --capture`.

The remaining HD screens share the same 1280×800 menu surface: city, world map,
pickup receipt and battle intro/victory/defeat. The city reuses original-277's
text-free HD concept as `art/ui/hd-town-v1/town-v1.png` (1672×941 opaque RGB;
source, SHA-256 and original prompts retained alongside). The world menu keeps
the original 158×163 map geography with nearest filtering and adds large numbered
markers and an open-destination list; it does not invent new map terrain or IDs.
Loot groups repeated definitions by count and pages at eight rows, with a fixed
Continue button. The legacy victory window also has a scrolling body so long
loot cannot push Continue off screen. QA captures are `build/hd-extra-*.png`.
