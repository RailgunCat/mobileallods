"""Shared plumbing for executing recovered Java reference methods.

The harnesses and expected values stay independent of the Godot implementation.
"""
from pathlib import Path
import subprocess


def method(source, declaration):
    start = source.index(declaration)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def run_reference(jdk, folder, class_name, *arguments):
    """Compile a prepared harness, then return its stdout or propagate failure."""
    binaries = Path(jdk) / 'bin'
    subprocess.run([str(binaries / 'javac.exe'), class_name + '.java'],
                   cwd=folder, check=True, timeout=30)
    return subprocess.run([str(binaries / 'java.exe'), '-cp', '.', class_name, *arguments],
                          cwd=folder, check=True, capture_output=True,
                          text=True, timeout=30).stdout
