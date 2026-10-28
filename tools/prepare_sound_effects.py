"""Extract Allods 2 SFX as data; prepare the selected PCM clips for Godot."""
from pathlib import Path, PurePosixPath
import hashlib
import io
import json
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "analysis/audio/allods2/source/sfx.res"
STAGING = ROOT / "analysis/audio/allods2/wav"
OUTPUT = ROOT / "godot/data/hd/audio/sfx"
SOURCE_URL = "https://vamp.allods2.eu/allods/files/sfx.exe"
FOOTSTEPS = {"surface": ["town/shop/step1.wav", "town/shop/step2.wav"],
             "dungeon": ["town_kaarg/ksteps1.wav", "town_kaarg/ksteps2.wav"]}

def extract(data):
    magic, start, count, flags, fat, total = struct.unpack_from("<6I", data)
    if magic != 0x31415926 or flags != 1 or fat + total * 32 != len(data):
        raise ValueError("Unsupported RES header")
    seen, files = set(), {}
    def walk(first, length, prefix=""):
        if not 0 <= first <= first + length <= total:
            raise ValueError("Invalid directory range")
        for index in range(first, first + length):
            if index in seen:
                raise ValueError("Repeated RES entry")
            seen.add(index)
            _, offset, size, kind, raw = struct.unpack_from("<IIII16s", data, fat + index * 32)
            name = raw.split(b"\0")[0].decode("cp1251")
            if not name or name in (".", "..") or any(c in name for c in "/\\:"):
                raise ValueError("Invalid RES name")
            path = prefix + name
            if kind == 1:
                walk(offset, size, path + "/")
            elif kind == 0 and 24 <= offset <= offset + size <= fat:
                if path in files:
                    raise ValueError("Duplicate file")
                files[path] = data[offset:offset + size]
            else:
                raise ValueError("Invalid RES file range or type")
    walk(start, count)
    if len(seen) != total:
        raise ValueError("Unreachable RES entries")
    return files

def prepare(data):
    with wave.open(io.BytesIO(data), "rb") as reader:
        channels, width, rate, frames, comp, _ = reader.getparams()
        raw = reader.readframes(frames)
    if channels != 1 or width != 2 or comp != "NONE" or len(raw) != frames * 2:
        raise ValueError("Expected complete mono PCM16 WAV")
    if not frames:
        return None, 0, rate
    samples = list(struct.unpack("<%dh" % frames, raw))
    peak = max(abs(v) for v in samples)
    gain = min(2.0, 22000 / max(1, peak))
    fade = min(int(rate * .003), frames // 2)
    for i, value in enumerate(samples):
        edge = min(1.0, i / max(1, fade), (frames - 1 - i) / max(1, fade))
        samples[i] = round(value * gain * edge)
    output = io.BytesIO()
    with wave.open(output, "wb") as writer:
        writer.setparams((1, 2, rate, frames, "NONE", "not compressed"))
        writer.writeframes(struct.pack("<%dh" % frames, *samples))
    return output.getvalue(), frames / rate, rate

def main():
    data = SOURCE.read_bytes()
    files = extract(data)
    clips, empty = {}, []
    for name, original in sorted(files.items()):
        if PurePosixPath(name).suffix != ".wav":
            continue
        target = STAGING / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(original)
        prepared, duration, rate = prepare(original)
        if prepared is None:
            empty.append(name)
            continue
        group = name.split("/")[0] if "/" in name else "ui"
        footsteps = [clip for pair in FOOTSTEPS.values() for clip in pair]
        if group not in ("ui", "units", "magic", "monsters") and name not in footsteps:
            continue
        target = OUTPUT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(prepared)
        clips[name] = {"file": name, "seconds": round(duration, 6), "sample_rate": rate,
                       "source_sha256": hashlib.sha256(original).hexdigest(),
                       "sha256": hashlib.sha256(prepared).hexdigest()}
    manifest = {"source_game": "Allods 2: Necromancer", "source_url": SOURCE_URL,
                "source_sha256": hashlib.sha256(data).hexdigest(),
                "source_wav_count": sum(n.endswith(".wav") for n in files),
                "empty_source_clips": empty,
                "processing": "PCM16 mono; peak <= 22000; max gain 2; 3ms edge fades",
                "footsteps": FOOTSTEPS,
                "clips": clips}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Audio prepared: %d clips; %d source WAVs; %d empty excluded" %
          (len(clips), manifest["source_wav_count"], len(empty)))

if __name__ == "__main__":
    main()
