# HD menu background v1

`title-v1.png` is the unchanged text-free red-hood painting from
`../../concepts/hd-menu-v1/01-main-menu-background-v1.png`.
It is active with HD mode enabled. Size: 1672×941, opaque RGB.
The original generation prompts are retained in `prompts.json`;
`manifest.json` records the actual SHA-256, source and display role.

Godot draws the title and every interactive button separately with the project
bitmap font and original stone frame. No generated lettering sheet is used.
Layout: 1280×800 with window scaling. The figure stays to the right of the menu.
Painting filtering is linear; UI filtering is nearest. The original Java ME
title remains available when HD is off or this local background is missing.

Run `tests/run_hd_menu_checks.gd` with `-- --capture` for native GPU previews
in `build/hd-menu-*.png`. Game maps, tile IDs and gameplay footprints are unaffected.
