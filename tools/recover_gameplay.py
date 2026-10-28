"""Recover reviewed stage-one constants from the optional CFR reference sources.

Run after decompilation. The resulting legacy_gameplay.json is checked in, so a
normal resource export does not require Java or the decompiled sources.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def recover():
    source = (ROOT / 'analysis/decompiled/m.java').read_text(encoding='utf-8')
    method = source.split('public final void b(int n2, int n3) {', 1)[1].split('public final void c(n n2)', 1)[0]
    # Isolate each switch block, retaining the Java assignment order.
    masks = {}
    for match in re.finditer(r'((?:\s*case \d+:)+)\s*\{(.*?)(?=\n            case |\n        \})', method, re.S):
        ids = re.findall(r'case (\d+):', match[1])
        cells = []
        for cell in re.finditer(r'var_byte_arr_arr_c\[n2([ +\-0-9]*)\]\[n3([ +\-0-9]*)\] = 1;', match[2]):
            cells.append([int(part.replace(' ', '') or '0') for part in (cell[2], cell[1])])
        for image in ids:
            masks[image] = cells
    flags_b = [1] * 169
    for index in [10, 7, 9, 3, 4, 11, 15, 12, 23, 19, 18, 22, 21, 37, 39, 43, 59, 57, *range(73, 100), 137, *range(160, 169)]:
        flags_b[index] = 2
    flags_d = [1] * 50
    for index in [0, 1, 5, 3, 4, 7, 9, 10, 17, 19, 49, 20, 48, 34, 21, 22, 25, 23, 24, 29, 27, 28, 30, 31, 32, 33]:
        flags_d[index] = 0
    graphics = json.loads((ROOT / 'tools/legacy_graphics.json').read_text(encoding='utf-8'))
    sprite_source = (ROOT / 'analysis/decompiled/s.java').read_text(encoding='utf-8')
    sprite_table = re.search(r'var_int_arr_arr_e = new int\[\]\[\](\{.*?\});', sprite_source)[1]
    sprite_table = json.loads(sprite_table.replace('{', '[').replace('}', ']'))
    dialogue_speakers = re.search(r'var_int_arr_arr_f = new int\[\]\[\](\{.*?\});', sprite_source)[1]
    portrait_images = re.search(r'var_int_arr_e = new int\[\](\{.*?\});', sprite_source)[1]
    action_table = re.search(r'var_int_arr_arr_a = new int\[\]\[\](\{.*?\});', sprite_source)[1]
    action_table = json.loads(action_table.replace('{', '[').replace('}', ']'))
    prices = json.loads(re.search(r'var_int_arr_f = new int\[\](\{.*?\});', sprite_source)[1].replace('{', '[').replace('}', ']'))
    unlocks = json.loads(re.search(r'var_int_arr_g = new int\[\](\{.*?\});', sprite_source)[1].replace('{', '[').replace('}', ']'))
    pickup_literal = re.search(r'this.var_int_arr_arr_arr_f = new int\[\]\[\]\[\](\{.*?\});', source)[1]
    pickup_literal = re.sub(r'new int\[0\](?:\[\])?', '[]', pickup_literal).replace('new int[][]', '')
    pickup_rows = json.loads(pickup_literal.replace('{', '[').replace('}', ']'))
    opcode_lengths = json.loads(re.search(r'var_int_arr_b = new int\[\](\{.*?\});', sprite_source)[1].replace('{', '[').replace('}', ']'))
    def int_table(field, dimensions=2):
        literal = re.search(r'this\.' + field + r' = new int' + r'\[\]' * dimensions + r'(\{.*?\});', source)[1]
        literal = re.sub(r'new int\[0\](?:\[\])?', '[]', literal).replace('new int[][]', '')
        return json.loads(literal.replace('{', '[').replace('}', ']'))
    entries = []
    for name in ['T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'aa', 'ab', 'ac', 'ad', 'ae']:
        body = source.split(f'public final void {name}()', 1)[1].split('\n    public ', 1)[0]
        locations = []
        for entry, x, y, facing in re.findall(r'case (\d+):\s*\{\s*this.ai = (\d+);\s*this.aj = (\d+);\s*this.var_byte_a = (?:\(byte\))?(\d+);', body):
            locations.append(dict(entry=int(entry), position_pixels=[int(x) * 16, int(y) * 16], facing=int(facing)))
        entries.append(locations)
    travel = {'entries': entries, 'opcode_lengths': opcode_lengths, 'dungeon_specs': [dict(room_rows=row[0], room_columns=row[1], minimum_rooms=row[2], unused=row[3]) for row in int_table('var_int_arr_arr_k')[:12]], 'dungeon_exits': int_table('var_int_arr_arr_l')[:12], 'dungeon_population': [[dict(chance=row[i], unit_type=row[i+1]) for i in range(0, len(row), 2)] for row in int_table('var_int_arr_arr_m')[:12]], 'dungeon_scripts': int_table('var_int_arr_arr_arr_e', 3), 'group_death_hooks': int_table('var_int_arr_arr_j')}
    screen_source = (ROOT / 'analysis/decompiled/g.java').read_text(encoding='utf-8')
    world_nodes = json.loads(re.search(r'var_int_arr_arr_h = new int\[\]\[\](\{.*?\});', screen_source)[1].replace('{', '[').replace('}', ']'))
    travel['world_nodes'] = [dict(world_index=i, position=row[:2], entry=row[2]) for i, row in enumerate(world_nodes)]
    offers = []
    for flag, body in re.findall(r'if \(g.var_m_a.var_byte_arr_b\[(\d+)\] == 1\)\s*\{(.*?)\}', screen_source, re.S):
        if not 159 <= int(flag) <= 168: continue
        quest = re.search(r'var_byte_arr_a\[(\d+)\] = 1', body)
        dialogue = re.search(r'this.var_int_t = (\d+)', body)
        unlock = re.search(r'var_byte_arr_e\[(\d+)\] = 1', body)
        gift = re.search(r'new ab\((\d+)\)', body)
        if quest and dialogue and unlock: offers.append(dict(trigger=int(flag), quest=int(quest[1]), dialogue_id=int(dialogue[1]), unlock=int(unlock[1]), gift=int(gift[1]) if gift else -1))
    travel['tavern_offers'] = offers
    return {
        'source_sha256': 'b64126c1fa29a0cd75e4f48f23be28fb9fcb5f1c6c99c4dca59d57a7331ffd2a',
        'corpse_images': [row[8] for row in sprite_table],
        'dialogue_speakers': json.loads(dialogue_speakers.replace('{', '[').replace('}', ']')),
        'portrait_images': json.loads(portrait_images.replace('{', '[').replace('}', ']')),
        'action_table': action_table,
        'travel': travel,
        'economy': {
            'items': [dict(definition_id=i, kind=0 if i < 12 else 1 if i < 36 else 2, hero_type=i // 3 if i < 12 else (i - 12) // 6 if i < 36 else -1, socket_count=i % 3 + 1 if i < 36 else 0, price=prices[i], unlock_progress=unlocks[i]) for i in range(41)],
            'pickups': [[dict(pickup_id=row[0], position_pixels=row[1:3], script_id=row[3], gold=sum(-v for v in row[4:] if v < 0), items=[v for v in row[4:] if v >= 0]) for row in rows] for rows in pickup_rows],
            'max_school_rank': 25,
        },
        'spell_definitions': [dict(spell_id=i, payload_kind=row[0], base_power=row[1], base_mana=row[2], school_stat=row[3], rank_step=row[4], area_target=bool(row[5]), target_flags=row[6]) for i, row in enumerate(action_table[2:])],
        'unit_notice_images': [row[10] for row in sprite_table],
        'unit_portrait_images': [row[9] for row in sprite_table],
        'source_methods': ['m.b(int,int):5001', 'm.P():4212', 'm.T():4746', 'n.a(...):74', 'n.i():699', 'm.g(int):4680', 'n.void_b():476', 'n.void_d():570', 'n.b(n):588', 'n.g():639', 'n.boolean_a(int,int):792', 'm.s():1347', 'm.D():2114', 'm.G():2177', 'm.J():2367', 'n.boolean_a():1016', 'n.o():1020'],
        'exploration': {
            'tick_ms': 62, 'pixels_per_tick': 4, 'history_length': 10,
            'unit_half_extents': [[10, 10] if i in [0, 1, 2, 3, 16] else [20, 10] if i == 5 else [33, 10] for i in range(18)],
            'units': [{key: unit[key] for key in ['frame_sizes', 'origins', 'frame_ticks', 'frame_columns', 'idle_frame']} for unit in graphics['units']],
        },
        'battle': {'tick_ms': 62, 'move_ticks_per_cell': 6, 'defense_delay_ms': 500, 'arena_margin': 2, 'legacy_view_cells': [10, 12], 'legacy_camera_offset': [79, 95], 'sides': [0, 1]},
        'collision_image_masks': masks,
        'collision_notes': {'48': 'row 0 only when anchor y>0; row -1 only when anchor y>1', '35': 'Java try/catch stops at the first out-of-bounds write; preserve assignment order', '42': 'raw source ID 42 blocks its anchor even though rendered as image 26'},
        'unit_footprints': [[1, 1] if i in [0, 1, 2, 3, 5, 16] else [3, 3] if i in [4, 17] else [2, 2] for i in range(18)],
        'starting_equipment': [{'armor': i * 3, 'weapon': 12 + i * 6} for i in range(4)],
        'map_1_entries': [{'entry': 0, 'position_pixels': [544, 384], 'facing': 0}, {'entry': 1, 'position_pixels': [352, 80], 'facing': 3}, {'entry': 2, 'position_pixels': [48, 384], 'facing': 1}],
        'new_game': {'map': '1', 'entry': 0, 'hero': {'instance_id': 1, 'unit_type': 0, 'story_group': 0, 'spawn_flag': 1, 'side_id': 0}, 'flags': {'a': [1] + [0] * 23, 'b': flags_b, 'c': [0] * 27, 'd': flags_d, 'e': [1, 1, 1] + [0] * 10, 'f': [0] * 20}, 'dungeon_seeds': [0] * 12},
    }


if __name__ == '__main__':
    output = ROOT / 'tools/legacy_gameplay.json'
    output.write_text(json.dumps(recover(), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(output)
