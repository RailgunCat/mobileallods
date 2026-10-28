"""Codec and real-archive roundtrip checks; no external dependencies."""
import copy
from pathlib import Path
import tempfile
import unittest
import zipfile

import allods_tool as tool

ROOT = Path(__file__).resolve().parents[1]
JAR = ROOT / 'allods_360x640_bluetooth_rus.jar'


class Codecs(unittest.TestCase):
    def test_java_utf_edge_cases(self):
        records = ['', 'Allods', 'Аллоды', 'a\0b', '😀', '\ud800']
        self.assertEqual(tool.unpack_utf(tool.pack_utf(records)), records)
        self.assertEqual(tool.encode_mutf8('\0'), b'\xc0\x80')
        for bad in [b'\x00', b'\xc0', b'\xc1\x81', b'\xf0\x9f\x98\x80']:
            with self.assertRaises(ValueError):
                tool.decode_mutf8(bad)
        with self.assertRaises(ValueError):
            tool.unpack_utf(b'\x00\x05abc')

    def test_pak_rejects_bad_lengths(self):
        entries = [b'abc', b'', bytes(range(256))]
        encoded = tool.pack_pak(entries)
        self.assertEqual(tool.unpack_pak(encoded), entries)
        for bad in [b'', encoded[:-1], encoded + b'x']:
            with self.assertRaises(ValueError):
                tool.unpack_pak(bad)

    def test_map_shape_and_tile_ids(self):
        value = {'width': 2, 'height': 1, 'source_tile_ids': [[0, 45]]}
        self.assertEqual(tool.unpack_map(tool.pack_map(value)), value)
        for rows in [[[0]], [[0, 46]], [[-1, 0]]]:
            with self.assertRaises(ValueError):
                tool.pack_map({**value, 'source_tile_ids': rows})

    def test_path_traversal(self):
        with self.assertRaises(ValueError):
            tool.safe_path(ROOT, '../escaped')

    def test_story_block_separators(self):
        self.assertEqual(tool.split_text_blocks(['a', '', '', 'b', 'c', '', '']), [['a'], ['b', 'c']])
        self.assertEqual(tool.split_text_blocks(['a', '', 'b', '', ''], 1), [['a'], ['b'], []])

    @unittest.skipUnless(JAR.exists(), 'User-supplied JAR required')
    def test_real_data_roundtrip_and_edits(self):
        (ROOT / 'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as temporary:
            folder = Path(temporary)
            project = folder / 'extracted'
            tool.extract(JAR, project)
            rebuilt = folder / 'rebuilt.jar'
            tool.rebuild(JAR, project, rebuilt)
            tool.verify(JAR, rebuilt)
            scenes = tool.load_json(project / 'scenes.json')['scenes']
            scripts = tool.disassemble_scenes(scenes)
            self.assertEqual(sum(len(s['scripts']) for s in scripts), 147)
            self.assertEqual(sum(len(r['instructions']) for s in scripts for r in s['scripts']), 450)
            godot_data = folder / 'godot-data'
            tool.export_godot(project, godot_data)
            graphics = tool.load_json(godot_data / 'legacy/graphics.json')
            gameplay = tool.load_json(godot_data / 'legacy/gameplay.json')
            self.assertEqual(gameplay['source_sha256'], graphics['source_sha256'])
            self.assertEqual(gameplay['new_game']['hero']['unit_type'], 0)
            self.assertEqual(len(tool.load_json(godot_data / 'legacy/gameplay_reference.json')['maps']), 18)
            battle_reference = tool.load_json(godot_data / 'legacy/battle_reference.json')
            self.assertEqual(battle_reference['source_sha256'], gameplay['source_sha256'])
            self.assertEqual(len(battle_reference['cases']), 4)
            combat_reference = tool.load_json(godot_data / 'legacy/combat_reference.json')
            self.assertEqual(combat_reference['source_sha256'], gameplay['source_sha256'])
            self.assertEqual(len(combat_reference['cases']), 7)
            magic_reference = tool.load_json(godot_data / 'legacy/magic_reference.json')
            self.assertEqual(magic_reference['source_sha256'], gameplay['source_sha256'])
            self.assertEqual(len(magic_reference['payloads']), 42)
            self.assertEqual(len(magic_reference['damage']), 13)
            self.assertEqual(len(magic_reference['walls']), 64)
            self.assertEqual(len(magic_reference['roots']), 80)
            self.assertEqual(len(gameplay['action_table']), 17)
            self.assertEqual(len(gameplay['trig']['sin']), 90)
            self.assertEqual(len(gameplay['trig']['cos']), 90)
            self.assertEqual(len(gameplay['economy']['items']), 41)
            self.assertEqual(len(gameplay['economy']['item_names']), 41)
            self.assertEqual(gameplay['economy']['pickups'][0][0]['items'], [21, 39])
            economy_reference = tool.load_json(godot_data / 'legacy/economy_reference.json')
            self.assertEqual(len(economy_reference['items']), 246)
            self.assertEqual(len(economy_reference['equipment']), 120)
            travel_reference = tool.load_json(godot_data / 'legacy/travel_reference.json')
            self.assertEqual(len(travel_reference['dungeons']), 36)
            self.assertEqual(len(gameplay['travel']['entries']), 12)
            self.assertEqual(len(gameplay['travel']['tavern_offers']), 10)
            self.assertEqual(len(gameplay['travel']['world_nodes']), 13)
            campaign = tool.load_json(godot_data / 'campaign.json')
            self.assertEqual(campaign['source_sha256'], gameplay['source_sha256'])
            self.assertEqual(len(campaign['dialogues']), 95)
            self.assertEqual(len(campaign['tutorials']), 20)
            self.assertEqual(len(campaign['quests']), 24)
            self.assertEqual(campaign['unit_names'][:2], ['Тагрим', 'Ли'])
            self.assertEqual(campaign['battle_ui']['actions'], ['Атаковать', 'Идти', 'Защищаться', 'Назад', 'Колдовать', 'Стрелять'])
            self.assertEqual(len(campaign['battle_ui']['spells']), 16)
            self.assertEqual(len(campaign['battle_ui']['notices']), 36)
            self.assertEqual(len(campaign['dialogues'][24]['pages']), 11)
            self.assertEqual(len(campaign['dialogues'][24]['unspoken_tail']), 1)
            self.assertEqual([p['speaker_id'] for p in campaign['dialogues'][13]['pages']], [0, 2, 0, 2, 0])
            self.assertEqual([p['portrait'] for p in campaign['dialogues'][13]['pages']], [16, 18, 16, 18, 16])
            self.assertEqual(campaign['scenes'][0], scripts[0])
            self.assertEqual(len(graphics['corpse_images']), 18)
            self.assertEqual(len(graphics['images']), 279)
            self.assertEqual(len(graphics['units']), 18)
            index = tool.load_json(project / 'index.json')
            for pack in index['packs']:
                for entry in pack['entries']:
                    if entry['path'].endswith('.png'):
                        exported = godot_data / graphics['images'][str(entry['global_id'])]['path']
                        self.assertEqual(exported.read_bytes(), (project / entry['path']).read_bytes())
            # Logical frames vary by direction. A few sheets trim transparent
            # trailing pixels, so every crop must intersect rather than fit in
            # the PNG. The renderer must clip these regions without scaling.
            for unit in graphics['units']:
                for direction in range(4):
                    image = graphics['images'][str(unit['images'][direction])]
                    width, height = unit['frame_sizes'][direction]
                    for x, y in zip(unit['frame_columns'][direction], unit['frame_rows'][direction]):
                        self.assertLess(x * width, image['width'])
                        self.assertLess(y * height, image['height'])
            edits = {
                'maps/1.map.json': lambda v: v['source_tile_ids'][0].__setitem__(0, 1),
                'text/1.utf.json': lambda v: v['records'].__setitem__(0, 'Тест 😀'),
                'tables/abilities.txt.json': lambda v: v['rows'][0]['values'].__setitem__(14, 123),
                'scenes.json': lambda v: v['scenes'][0]['units'][0].__setitem__(1, 42),
            }
            expected = {}
            for name, change in edits.items():
                value = tool.load_json(project / name)
                change(value)
                expected[name] = copy.deepcopy(value)
                tool.save_json(project / name, value)
            tool.rebuild(JAR, project, rebuilt)
            second = folder / 'reextracted'
            tool.extract(rebuilt, second)
            for name, value in expected.items():
                self.assertEqual(tool.load_json(second / name), value)
            with zipfile.ZipFile(JAR) as a, zipfile.ZipFile(rebuilt) as b:
                changed = [n for n in a.namelist() if a.read(n) != b.read(n)]
                self.assertEqual(set(changed), {'res/1.map', 'res/1.utf', 'res/abilities.txt', 'res/scenes.pak'})


if __name__ == '__main__':
    unittest.main()
