# Mage loot reference

`MageLootReference.java` independently runs the drop loop from recovered
`analysis/decompiled/m.java` (victory, around lines 1294–1317) and its `int_d`
map scaling. Inputs are the real mage reward row (11) and original item tiers.
`cases.json` contains 24 Java executions: map 7, campaign progress 7, seeds 0–7,
and summed party luck 0, 60, 165. Each records ordered items, gold and next RNG.

The real save has summed party luck 165. These eight seeds yield 5–9 items;
luck 0 yields 3–6. The video showing three items is not an original item cap.
Production drop rules are unchanged. The arena regression separately verifies
that the fight contains one mage and excludes distant labyrinth enemy waves.

Regenerate input from `gameplay.json` item `unlock_progress` and reward row 11:
minimum gold, maximum gold, 41 tiers, then 41 drop chances, space separated.
Compile with the installed Java compiler and run `MageLootReference INPUT`.
The extracted input is also saved as `input.txt`. The JSON stdout becomes
`cases.json`. Bounded draws use the original `abs(nextInt() % bound)`, rather
than Java's different `nextInt(bound)`. Checks run in `mage_encounter_checks.gd`.
