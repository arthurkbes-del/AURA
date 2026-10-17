#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Inspect the actual local .app; never sign, upload or distribute it."""
import hashlib
import json
import plistlib
from pathlib import Path
import re
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def verify(app):
    app = app.resolve(strict=True)
    root = Path(__file__).resolve().parents[1]
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    required = {"arm64", "x86_64"}
    architectures = set(run("lipo", "-archs", str(executable)).split())
    if architectures != required:
        raise ValueError(f"Expected arm64 + x86_64; found {sorted(architectures)}")
    if info.get("LSMinimumSystemVersion") != "15.0":
        raise ValueError("Bundle deployment minimum differs from macOS 15.0")
    magic = {bytes.fromhex(value) for value in ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
    binaries = []
    for path in sorted((app / "Contents").rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open("rb") as stream:
            header = stream.read(4)
        if header not in magic:
            continue
        slices = set(run("lipo", "-archs", str(path)).split())
        if slices != required:
            raise ValueError(f"Non-universal bundled code: {path.relative_to(app)}: {sorted(slices)}")
        minimums = {}
        for architecture in sorted(required):
            load_commands = run("xcrun", "vtool", "-arch", architecture, "-show-build", str(path))
            match = re.search(r"\bminos\s+(\S+)", load_commands)
            if not match or match.group(1) != "15.0":
                raise ValueError(f"Unexpected minimum OS in {path.name}/{architecture}: {load_commands}")
            minimums[architecture] = match.group(1)
        binaries.append({"path": str(path.relative_to(app)), "architectures": sorted(slices), "minimumOS": minimums})
    if not binaries:
        raise ValueError("No Mach-O code inspected")
    for name in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
        if (app / "Contents/Resources" / name).read_bytes() != (root / name).read_bytes():
            raise ValueError(f"Bundle notice differs from source: {name}")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True, capture_output=True)
    signature = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], check=True, capture_output=True, text=True).stderr
    if "Signature=adhoc" not in signature:
        raise ValueError("Expected local ad hoc development signature")
    return {"status": "PASS", "bundle": str(app), "architectures": sorted(architectures),
            "bundleMinimumOS": info["LSMinimumSystemVersion"], "binaries": binaries,
            "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest(),
            "signing": "ad hoc development only; not Developer ID or notarized",
            "license": "GPL-3.0-or-later; bundled notices match project",
            "intelHardwareRuntime": "not established by binary inspection"}


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: verify-universal.py /absolute/path/AURA.app")
        print(json.dumps(verify(Path(sys.argv[1])), indent=2))
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f"UNIVERSAL VERIFICATION FAILED: {error}", file=sys.stderr)
        sys.exit(1)
