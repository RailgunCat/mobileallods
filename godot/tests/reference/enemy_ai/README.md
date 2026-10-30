# Original enemy magic selection oracle

`EnemyAIReference.java` embeds the unmodified recovered `m.boolean_b()` method
from `analysis/decompiled/m.java`, plus the original `s` action table.
The minimal surrounding types supply unit stats, side, position, death state,
Manhattan range and mana cost. They record commands without rendering or damage.
This harness does not execute the complete MIDlet or prove pathfinding parity.

Recovered `m.java` SHA-256:
`dd9e934c8035faaf85ca7b7368dcb2fd2e10e3ae7351cadb4c3654e7ab001307`.

Embedded method SHA-256 (UTF-8, beginning at its declaration, trailing whitespace removed):
`9614077f301c4fa8be2e2f08b744c27efb10d10c8eeec2479b013d19fd107716`.

`cases.json` contains 42 independently executed Java cases: seven situations
with six seeds each. It records success/failure, selected spell, selected target
and the next random integer, so tests verify both policy and random draw order.
Situations cover all offensive schools, low mana, the AI's equality threshold,
unknown schools, targets out of range, dead opponents and friendly-only targets.

Regenerate from the workspace root with the installed JDK:

```powershell
& 'F:/apps/Java/bin/javac.exe' -d build/enemy-ai-reference godot/tests/reference/enemy_ai/EnemyAIReference.java
& 'F:/apps/Java/bin/java.exe' -cp build/enemy-ai-reference EnemyAIReference F:/Projects/my/mobileallods/godot/tests/reference/enemy_ai/cases.json
```

Run the Godot comparisons with:

```powershell
& 'F:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' --headless --path godot --script res://tests/run_enemy_ai_checks.gd
```

`enemy_ai_checks.gd` also checks fighter priorities, multiple physical targets,
caster movement with no mana, actual execution at the original AI threshold,
fresh normal battle seeds and explicitly pinned replay seeds.
