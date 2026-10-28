"""Render the supplied MIDI tracks for native Godot playback; stdlib + installed JDK/FFmpeg."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jar', type=Path, default=ROOT / 'allods_360x640_bluetooth_rus.jar')
    parser.add_argument('--jdk', type=Path, default=Path('F:/apps/Java'))
    parser.add_argument('--ffmpeg', type=Path, default=Path('F:/apps/ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe'))
    parser.add_argument('--out', type=Path, default=ROOT / 'godot/data/audio')
    args = parser.parse_args()
    build = ROOT / 'build/music'
    build.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'tools/MidiRender.java'
    subprocess.run([str(args.jdk / 'bin/javac.exe'), '--add-exports', 'java.desktop/com.sun.media.sound=ALL-UNNAMED', '-d', str(build), str(source)], check=True)
    tracks = []
    with zipfile.ZipFile(args.jar) as archive:
        for name in ['bgsound', 'bgsound1']:
            payload = archive.read(f'res/{name}.mid')
            if not payload.startswith(b'MThd'): raise ValueError(f'Invalid MIDI: {name}')
            midi = build / f'{name}.mid'
            wave = build / f'{name}.wav'
            midi.write_bytes(payload)
            subprocess.run([str(args.jdk / 'bin/java.exe'), '--add-exports', 'java.desktop/com.sun.media.sound=ALL-UNNAMED', '-cp', str(build), 'MidiRender', str(midi), str(wave)], check=True)
            destination = args.out / f'{name}.ogg'
            subprocess.run([str(args.ffmpeg), '-hide_banner', '-loglevel', 'error', '-y', '-i', str(wave), '-c:a', 'libvorbis', '-q:a', '4', str(destination)], check=True)
            shutil.copyfile(midi, args.out / midi.name)
            tracks.append({'source': midi.name, 'source_sha256': hashlib.sha256(payload).hexdigest(), 'stream': destination.name, 'bytes': destination.stat().st_size})
    (args.out / 'manifest.json').write_text(json.dumps({'renderer': 'JDK Gervill General MIDI', 'tracks': tracks}, indent=2) + '\n', encoding='utf-8')
    print('PASS: rendered both original MIDI tracks for Godot')

if __name__ == '__main__': main()
