"""Extract and rebuild the supplied Allods Java ME data. Python 3.10+, stdlib only."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile
import zlib

KNOWN_SHA256 = "b64126c1fa29a0cd75e4f48f23be28fb9fcb5f1c6c99c4dca59d57a7331ffd2a"
PNG = b"\x89PNG\r\n\x1a\n"
# m constructor and s static initializer, recovered from this specific build.
TILE_IMAGES = [26,44,46,33,47,48,27,28,29,30,31,36,37,38,39,40,41,42,43,36,37,38,39,40,41,42,43,49,50,51,60,61,52,53,55,32,56,45,36,58,54,59,26,57,35,34]
OPCODE_LENGTHS = [3,3,8,2,2,2,4,2,1,1,1,3,3,3,3,2,3,1,3,4,3,2,1]
OPCODE_OPERANDS = {
    0: ('flag', 'state'), 1: ('quest', 'state'),
    2: ('group', 'relative_group', 'axis', 'tile_x', 'tile_y', 'ticks_per_cell', 'options'),
    3: ('dialogue_id',), 4: ('duration_units',), 5: ('group',),
    6: ('bank', 'flag', 'state'), 7: ('group',), 11: ('map', 'entry'),
    12: ('spawn_flag', 'state'), 13: ('item_flag', 'state'), 14: ('progress_flag', 'state'),
    15: ('tutorial_id',), 16: ('group', 'direction'), 18: ('tile_x', 'tile_y'),
}
UNIT_NAMES = ["swordsman", "archer lady", "healer", "wizard", "troll", "hermit", "orc", "dragon", "", "Goblin", "mage", "skeleton", "bat", "skeleton", "evil squirrel", "turtle", "guard", "poisoned troll"]


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def safe_path(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f"Path escapes output directory: {name}")
    return path


def decode_mutf8(data):
    # Java readUTF encodes UTF-16 code units, including surrogate pairs and C0 80 NUL.
    units = bytearray()
    i = 0
    while i < len(data):
        a = data[i]
        i += 1
        if 0 < a < 128:
            code = a
        elif a & 0xE0 == 0xC0:
            if i >= len(data) or data[i] & 0xC0 != 0x80:
                raise ValueError("Invalid modified UTF-8 continuation")
            code = ((a & 31) << 6) | (data[i] & 63)
            i += 1
            if code < 128 and not (a == 0xC0 and code == 0):
                raise ValueError("Overlong modified UTF-8")
        elif a & 0xF0 == 0xE0:
            if i + 1 >= len(data) or any(x & 0xC0 != 0x80 for x in data[i:i+2]):
                raise ValueError("Invalid modified UTF-8 continuation")
            code = ((a & 15) << 12) | ((data[i] & 63) << 6) | (data[i+1] & 63)
            i += 2
            if code < 2048:
                raise ValueError("Overlong modified UTF-8")
        else:
            raise ValueError("Invalid modified UTF-8 lead byte")
        units.extend(struct.pack(">H", code))
    return units.decode("utf-16-be", errors="surrogatepass")


def encode_mutf8(text):
    data = bytearray()
    units = text.encode("utf-16-be", errors="surrogatepass")
    for (code,) in struct.iter_unpack(">H", units):
        if 0 < code < 128:
            data.append(code)
        elif code < 2048:
            data.extend((0xC0 | (code >> 6), 0x80 | (code & 63)))
        else:
            data.extend((0xE0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63)))
    if len(data) > 65535:
        raise ValueError("Java UTF record exceeds 65535 bytes")
    return bytes(data)


def unpack_utf(data):
    records = []
    pos = 0
    while pos < len(data):
        if pos + 2 > len(data):
            raise ValueError("Truncated UTF length")
        size = struct.unpack_from(">H", data, pos)[0]
        pos += 2
        if pos + size > len(data):
            raise ValueError("Truncated UTF record")
        records.append(decode_mutf8(data[pos:pos+size]))
        pos += size
    return records


def pack_utf(records):
    parts = [encode_mutf8(record) for record in records]
    return b"".join(struct.pack(">H", len(part)) + part for part in parts)


def unpack_pak(data):
    if len(data) < 4:
        raise ValueError("Truncated PAK header")
    count = struct.unpack_from(">I", data)[0]
    pos = 4 + 4 * count
    if pos > len(data):
        raise ValueError("Truncated PAK size table")
    sizes = struct.unpack_from(f">{count}I", data, 4)
    if pos + sum(sizes) != len(data):
        raise ValueError("PAK sizes do not match payload")
    entries = []
    for size in sizes:
        entries.append(bytes(x ^ 0x53 for x in data[pos:pos+size]))
        pos += size
    return entries


def pack_pak(entries):
    return struct.pack(">I", len(entries)) + b"".join(struct.pack(">I", len(e)) for e in entries) + b"".join(bytes(x ^ 0x53 for x in e) for e in entries)


def unpack_map(data):
    width, height = struct.unpack_from("<HH", data)
    if len(data) != 4 + width * height or not width or not height:
        raise ValueError("Invalid map dimensions/payload")
    ids = [x - 128 for x in data[4:]]
    return {"width": width, "height": height, "source_tile_ids": [ids[y*width:(y+1)*width] for y in range(height)]}


def pack_map(value):
    w, h = value["width"], value["height"]
    rows = value["source_tile_ids"]
    if not w or not h or len(rows) != h or any(len(row) != w for row in rows):
        raise ValueError("Map rows must match dimensions")
    if any(type(t) is not int or not 0 <= t < len(TILE_IMAGES) for row in rows for t in row):
        raise ValueError("Unknown source tile ID")
    return struct.pack("<HH", w, h) + bytes(t + 128 for row in rows for t in row)


def unpack_scenes(data):
    pos = 0
    def read():
        nonlocal pos
        if pos + 4 > len(data):
            raise ValueError("Truncated scene")
        value = struct.unpack_from(">i", data, pos)[0]
        pos += 4
        return value
    def count():
        value = read()
        if value < 0 or value > (len(data) - pos) // 4:
            raise ValueError("Invalid scene array length")
        return value
    scenes = []
    while pos < len(data):
        scene = {}
        for key in ("scripts", "triggers", "units"):
            scene[key] = [[read() for _ in range(count())] for _ in range(count())]
        scenes.append(scene)
    return scenes


def pack_scenes(scenes):
    values = []
    for scene in scenes:
        for key in ("scripts", "triggers", "units"):
            rows = scene[key]
            values.append(len(rows))
            for row in rows:
                values.extend([len(row), *row])
    return b"".join(struct.pack(">i", v) for v in values)


def disassemble_scenes(scenes):
    result = []
    for scene_id, scene in enumerate(scenes):
        scripts = []
        for row in scene["scripts"]:
            instructions = []
            pos = 1
            while pos < len(row):
                opcode = row[pos]
                if not 0 <= opcode < len(OPCODE_LENGTHS):
                    raise ValueError(f"Unknown scene opcode {opcode}")
                end = pos + OPCODE_LENGTHS[opcode]
                if end > len(row):
                    raise ValueError("Truncated scene instruction")
                args = row[pos+1:end]
                instructions.append({"offset": pos, "opcode": opcode, "args": args, "operands": dict(zip(OPCODE_OPERANDS.get(opcode, ()), args))})
                pos = end
            scripts.append({"script_id": row[0], "instructions": instructions})
        result.append({"scene_id": scene_id, "scripts": scripts})
    return result


def unpack_table(data):
    lines = data.decode("utf-8").splitlines()
    columns = lines[0].split("\t")[1:]
    rows = []
    for line_number, line in enumerate(lines):
        if not line or line.startswith("//"):
            continue
        fields = line.split("\t")
        rows.append({"row_id": len(rows), "source_line": line_number, "label": fields[0], "values": [int(v) for v in fields[1:]]})
    return {"columns": [{"index": i, "name": c} for i, c in enumerate(columns)], "rows": rows}


def pack_table(value, original):
    baseline = unpack_table(original)
    if len(value["rows"]) != len(baseline["rows"]):
        raise ValueError("Keep table row count and order: game code uses numeric row IDs")
    lines = original.decode("utf-8").splitlines(keepends=True)
    for row, old in zip(value["rows"], baseline["rows"]):
        if row["source_line"] != old["source_line"] or row["row_id"] != old["row_id"]:
            raise ValueError("Keep table row IDs/source_line unchanged")
        if len(row["values"]) != len(old["values"]) or any(type(v) is not int or not -(2**31) <= v < 2**31 for v in row["values"]):
            raise ValueError("Keep table width and signed 32-bit integer values")
        if any(c in row["label"] for c in "\r\n\t") or row["label"].startswith("//"):
            raise ValueError("Invalid table label")
        if row != old:
            lines[row["source_line"]] = row["label"] + "\t" + "\t".join(map(str, row["values"])) + "\r\n"
    return "".join(lines).encode("utf-8")


def png_dimensions(data):
    if not data.startswith(PNG):
        raise ValueError("Invalid PNG signature")
    pos = 8
    while pos < len(data):
        if pos + 12 > len(data):
            raise ValueError("Truncated PNG chunk")
        size = struct.unpack_from(">I", data, pos)[0]
        end = pos + 12 + size
        if end > len(data):
            raise ValueError("Truncated PNG data")
        chunk = data[pos+4:pos+8+size]
        if zlib.crc32(chunk) != struct.unpack_from(">I", data, pos+8+size)[0]:
            raise ValueError("PNG CRC mismatch")
        if data[pos+4:pos+8] == b"IEND":
            if end != len(data):
                raise ValueError("Trailing PNG data")
            return struct.unpack_from(">II", data, 16)
        pos = end
    raise ValueError("Missing PNG IEND")


def extract(jar, out):
    if out.exists() and any(out.iterdir()):
        raise ValueError("Use a new or empty output directory")
    out.mkdir(parents=True, exist_ok=True)
    index = {"source_name": jar.name, "source_sha256": hashlib.sha256(jar.read_bytes()).hexdigest(), "entries": [], "packs": []}
    global_id = 0
    images = []
    with zipfile.ZipFile(jar) as archive:
        for info in archive.infolist():
            target = safe_path(out / "raw", info.filename)
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            data = archive.read(info)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            index["entries"].append({"name": info.filename, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
            name = Path(info.filename).name
            if info.filename.startswith("res/res") and name.endswith(".pak"):
                pack = {"source": info.filename, "entries": []}
                for local_id, payload in enumerate(unpack_pak(data)):
                    is_png = payload.startswith(PNG)
                    asset = f"assets/{Path(name).stem}/{global_id:03d}.{'png' if is_png else 'bin'}"
                    dest = out / asset
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(payload)
                    entry = {"global_id": global_id, "local_id": local_id, "path": asset, "size": len(payload)}
                    if is_png:
                        entry["width"], entry["height"] = png_dimensions(payload)
                        images.append(entry)
                    else:
                        save_json(dest.with_suffix(".json"), {"records": unpack_utf(payload)})
                    pack["entries"].append(entry)
                    global_id += 1
                index["packs"].append(pack)
            elif name.endswith(".utf"):
                records = unpack_utf(data)
                save_json(out / "text" / (name + ".json"), {"records": records})
                (out / "text" / (name + ".txt")).write_text("\n".join(records), encoding="utf-8")
            elif name.endswith(".map"):
                save_json(out / "maps" / (name + ".json"), unpack_map(data))
            elif name == "scenes.pak":
                save_json(out / "scenes.json", {"scenes": unpack_scenes(data)})
            elif name in ("abilities.txt", "rewards.txt"):
                save_json(out / "tables" / (name + ".json"), unpack_table(data))
    index["packs"].sort(key=lambda p: p["source"])
    save_json(out / "index.json", index)
    save_json(out / "constants.json", {"verified_build_sha256": KNOWN_SHA256, "tile_image_ids": TILE_IMAGES, "scene_opcode_lengths": OPCODE_LENGTHS, "unit_names": UNIT_NAMES})
    cards = "\n".join(f'<figure><img loading="lazy" src="{e["path"]}"><figcaption>#{e["global_id"]} · {e["width"]}×{e["height"]}</figcaption></figure>' for e in images)
    (out / "gallery.html").write_text('<!doctype html><meta charset="utf-8"><title>Allods recovered assets</title><style>body{background:#172124;color:#e7e4d7;font:15px sans-serif;padding:24px}main{display:flex;flex-wrap:wrap;gap:12px}figure{margin:0;padding:12px;background:#28383b;min-width:90px}img{image-rendering:pixelated;max-width:480px;min-width:32px}figcaption{margin-top:10px}</style><h1>Allods recovered assets</h1><p>Global IDs follow the game loader. Reference art from the supplied JAR.</p><main>' + cards + '</main>', encoding="utf-8")
    print(f"Extracted {len(index['entries'])} files, {len(images)} PNGs, {global_id-len(images)} other packed assets to {out}")
    if index["source_sha256"] != KNOWN_SHA256:
        print("Warning: constants are verified only for the documented input build.")


def rebuild(jar, project, output):
    index = load_json(project / "index.json")
    if hashlib.sha256(jar.read_bytes()).hexdigest() != index["source_sha256"]:
        raise ValueError("Source JAR differs from extraction")
    if output.resolve() == jar.resolve():
        raise ValueError("Choose a separate output JAR; preserve the original")
    packs = {p["source"]: p for p in index["packs"]}
    output.parent.mkdir(parents=True, exist_ok=True)
    changes = []
    with zipfile.ZipFile(jar) as source, zipfile.ZipFile(output, "w") as dest:
        dest.comment = source.comment
        for info in source.infolist():
            if info.is_dir():
                dest.writestr(info, b"")
                continue
            data = safe_path(project / "raw", info.filename).read_bytes()
            name = Path(info.filename).name
            if info.filename in packs:
                entries = []
                for entry in packs[info.filename]["entries"]:
                    path = safe_path(project, entry["path"])
                    if path.suffix == ".bin" and path.with_suffix(".json").exists():
                        payload = pack_utf(load_json(path.with_suffix(".json"))["records"])
                    else:
                        payload = path.read_bytes()
                        png_dimensions(payload)
                    entries.append(payload)
                data = pack_pak(entries)
            elif name.endswith(".utf"):
                data = pack_utf(load_json(project / "text" / (name + ".json"))["records"])
            elif name.endswith(".map"):
                data = pack_map(load_json(project / "maps" / (name + ".json")))
            elif name == "scenes.pak":
                data = pack_scenes(load_json(project / "scenes.json")["scenes"])
            elif name in ("abilities.txt", "rewards.txt"):
                data = pack_table(load_json(project / "tables" / (name + ".json")), data)
            if data != source.read(info):
                changes.append(info.filename)
            dest.writestr(info, data)
    print(f"Rebuilt {output}; changed payloads: {changes}")


def verify(original, rebuilt):
    with zipfile.ZipFile(original) as a, zipfile.ZipFile(rebuilt) as b:
        if a.namelist() != b.namelist():
            raise ValueError("Archive entries/order changed")
        changed = [name for name in a.namelist() if a.read(name) != b.read(name)]
        if changed:
            raise ValueError(f"Payloads differ: {changed}")
        print(f"PASS: all {len(a.namelist())} archive payloads match byte for byte")


def split_text_blocks(records, empty_count=2):
    """ae.java_lang_String_arr_a uses two empty UTF records between dialogues."""
    blocks, current, empties = [], [], 0
    for record in records:
        if record == "":
            empties += 1
            if empties == empty_count:
                blocks.append(current)
                current, empties = [], 0
        else:
            empties = 0
            current.append(record)
    if current:
        blocks.append(current)
    return blocks


def export_campaign(project, gameplay, scenes):
    records = [record for record in load_json(project / "text/common.utf.json")["records"] if not record.startswith("//")]
    groups, cursor = [], 0
    for _ in range(28):  # aj reads exactly a..B; the trailing eof marker is not data.
        size = int(records[cursor])
        groups.append(records[cursor + 1:cursor + 1 + size])
        cursor += size + 1
    dialogues = []
    for file_index in range(2):
        blocks = split_text_blocks(load_json(project / f"text/dialogs{file_index}.utf.json")["records"])
        for block_index, lines in enumerate(blocks):
            dialogue_id = file_index * 55 + block_index
            speakers = gameplay["dialogue_speakers"][dialogue_id]
            if len(speakers) > len(lines):
                raise ValueError(f"Dialogue {dialogue_id}: missing text for a speaker")
            pages = [{"speaker_id": speaker, "speaker": groups[15][speaker], "portrait": gameplay["portrait_images"][speaker], "text": text} for speaker, text in zip(speakers, lines)]
            # g advances only while index < s.dialogue_speakers[id].length.
            # The supplied dialogue 24 contains one extra, unreachable line.
            dialogues.append({"dialogue_id": dialogue_id, "pages": pages, "unspoken_tail": lines[len(speakers):]})
    tutorials = ["\n".join(block) for block in split_text_blocks(load_json(project / "text/messages.utf.json")["records"], 1)]
    quests = split_text_blocks(load_json(project / "text/quests.utf.json")["records"])[1:]
    # Add localized economy metadata before export_godot writes gameplay.json.
    gameplay["economy"]["item_names"] = groups[26]
    gameplay["economy"]["crystal_descriptions"] = groups[27]
    gameplay["economy"]["stat_names"] = groups[25]
    gameplay["economy"]["skill_help"] = load_json(project / "text/skills.utf.json")["records"]
    gameplay["travel"]["location_names"] = groups[9]
    gameplay["travel"]["rumours"] = ["\n".join(block) for block in split_text_blocks(load_json(project / "text/rumours.utf.json")["records"], 1)]
    font = load_json(project / "assets/res0/002.json")["records"]
    gameplay["legacy_ui"] = {"font": {"characters": font[0], "cell_width": int(font[1]), "cell_height": int(font[2]), "columns": int(font[3]), "widths": list(map(int, font[4].split()))}, "help": "\n".join(load_json(project / "text/2.utf.json")["records"])}
    return {"source_sha256": gameplay["source_sha256"], "dialogues": dialogues, "tutorials": tutorials, "quests": [{"id": i, "title": block[0], "text": "\n".join(block[1:])} for i, block in enumerate(quests)], "unit_names": groups[2], "battle_ui": {"actions": groups[0], "spells": groups[1], "notices": groups[3], "encounters": [{"title": groups[3][i * 2], "description": groups[3][i * 2 + 1]} for i in range(len(groups[2]))], "mana_suffix": groups[1][15], "received": groups[4][7], "gold": groups[4][8], "xp": groups[4][9]}, "scenes": disassemble_scenes(scenes)}


def export_godot(project, out):
    # Export original PNGs unchanged; rendering metadata describes their anchors/frames.
    index = load_json(project / "index.json")
    graphics = load_json(Path(__file__).with_name("legacy_graphics.json"))
    gameplay = load_json(Path(__file__).with_name("legacy_gameplay.json"))
    gameplay["trig"] = {key: list(struct.unpack(">90h", (project / f"raw/sincos/{key}.int").read_bytes())) for key in ["sin", "cos"]}
    if index["source_sha256"] != graphics["source_sha256"]:
        raise ValueError("Legacy graphics metadata is verified only for the documented source JAR")
    if index["source_sha256"] != gameplay["source_sha256"]:
        raise ValueError("Gameplay metadata is verified only for the documented source JAR")
    out.mkdir(parents=True, exist_ok=True)
    maps = []
    for path in sorted((project / "maps").glob("*.json")):
        maps.append({"name": path.name.removesuffix(".map.json"), **load_json(path)})
    scenes = load_json(project / "scenes.json")["scenes"]
    save_json(out / "world.json", {"maps": maps, "scenes": scenes, "constants": load_json(project / "constants.json")})
    save_json(out / "scene_scripts.json", {"scenes": disassemble_scenes(scenes)})
    save_json(out / "campaign.json", export_campaign(project, gameplay, scenes))
    save_json(out / "legacy/gameplay.json", gameplay)
    save_json(out / "legacy/gameplay_reference.json", load_json(Path(__file__).with_name("legacy_gameplay_reference.json")))
    save_json(out / "legacy/battle_reference.json", load_json(Path(__file__).with_name("legacy_battle_reference.json")))
    save_json(out / "legacy/combat_reference.json", load_json(Path(__file__).with_name("legacy_combat_reference.json")))
    save_json(out / "legacy/magic_reference.json", load_json(Path(__file__).with_name("legacy_magic_reference.json")))
    save_json(out / "legacy/economy_reference.json", load_json(Path(__file__).with_name("legacy_economy_reference.json")))
    save_json(out / "legacy/travel_reference.json", load_json(Path(__file__).with_name("legacy_travel_reference.json")))
    for folder in ("text", "tables"):
        for path in (project / folder).glob("*.json"):
            data = load_json(path)
            if folder == "tables" and path.name == "rewards.txt.json":
                for row in data["rows"]:
                    row["reward"] = dict(zip(("base_experience", "minimum_gold", "maximum_gold"), row["values"][:3]))
                    row["reward"]["drops"] = [{"definition_id": i, "chance": chance} for i, chance in enumerate(row["values"][3:])]
            save_json(out / folder / path.name, data)
    images = {}
    for pack in index["packs"]:
        for entry in pack["entries"]:
            if not entry["path"].endswith(".png"):
                continue
            payload = safe_path(project, entry["path"]).read_bytes()
            width, height = png_dimensions(payload)
            relative = f"legacy/images/{entry['global_id']:03d}.png"
            destination = out / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(payload)
            images[str(entry["global_id"])] = {"path": relative, "width": width, "height": height}
    save_json(out / "legacy/graphics.json", {**graphics, "images": images, "corpse_images": gameplay["corpse_images"]})
    print(f"Exported Godot data to {out}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name, args in {"extract": ["jar", "out"], "rebuild": ["jar", "project", "output"], "verify": ["original", "rebuilt"], "export-godot": ["project", "out"]}.items():
        command = commands.add_parser(name)
        for arg in args:
            command.add_argument(arg, type=Path)
    args = vars(parser.parse_args())
    command = args.pop("command").replace("-", "_")
    try:
        globals()[command](**args)
    except (ValueError, OSError, KeyError, struct.error, zipfile.BadZipFile) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
