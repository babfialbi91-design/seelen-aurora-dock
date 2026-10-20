#!/usr/bin/env python3
"""Package the aurora-dock theme folder into a portable .slu resource.

A .slu file is:
    8-byte header (0x02 'S' 'L' 'U' 0 0 0 0) + base64(UTF-8 YAML)

The YAML mirrors Seelen's resource schema (version/resource/data) and inlines
the compiled CSS of every widget style, which is what the app expects.
"""

import base64
import datetime
import re
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME = ROOT / "aurora-dock"
OUT = ROOT / "dist" / "aurora-dock.slu"

SASS = "npx --yes sass@1.77.8 --no-source-map --style=expanded"
NS = uuid.UUID("6f9619ff-8b86-d011-b42d-00c04fc964ff")
HEADER = bytes([0x02, 0x53, 0x4C, 0x55, 0x00, 0x00, 0x00, 0x00])


def indent(text: str, width: int) -> str:
    pad = " " * width
    return "\n".join(pad + line if line.strip() else "" for line in text.splitlines())


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def compile_scss(rel: str, cache: dict) -> str:
    if rel in cache:
        return cache[rel]
    src = THEME / rel
    if not src.exists():
        sys.exit(f"missing style file: {src}")
    result = subprocess.run(
        f'{SASS} "{src}"', capture_output=True, text=True, shell=True
    )
    if result.returncode != 0:
        sys.exit(f"sass failed for {rel}:\n{result.stderr}")
    cache[rel] = result.stdout
    return result.stdout


def main() -> None:
    meta = (THEME / "metadata.yml").read_text(encoding="utf-8")

    styles = {
        m.group(1): m.group(2)
        for m in re.finditer(
            r'^\s*"(@seelen/[^"]+)":\s*!include\s+(\S+)\s*$', meta, re.M
        )
    }
    if not styles:
        sys.exit("no widget styles found in metadata.yml")

    meta_match = re.search(r"^metadata:\n(.*?)(?=^styles:)", meta, re.M | re.S)
    settings_match = re.search(r"^settings:\n(.*)$", meta, re.M | re.S)
    if not meta_match or not settings_match:
        sys.exit("metadata.yml must contain metadata: and settings: blocks")

    metadata_block = meta_match.group(1).rstrip("\n")
    settings_block = settings_match.group(1).rstrip("\n")

    cache: dict = {}
    style_lines = []
    for key, rel in styles.items():
        css = compile_scss(rel, cache).replace("\r\n", "\n").rstrip("\n")
        style_lines.append(f"    '{key}': |")
        style_lines.append(indent(css, 6))

    rid = str(uuid.uuid5(NS, "aurora-dock"))
    did = str(uuid.uuid5(NS, "aurora-dock:data"))
    cid = str(uuid.uuid5(NS, "asfkep"))
    stamp = now()

    doc = f"""version: 1
resource:
  id: {rid}
  dataId: {did}
  creatorId: {cid}
  kind: Theme
  slug: aurora-dock
  metadata:
{indent(metadata_block, 4)}
  createdAt: {stamp}
  updatedAt: {stamp}
  status: Published
  rejectedReason: null
  reviewedAt: null
  reviewedBy: null
  deletedAt: null
  attributes: []
  version: 1
  stars: 0
  downloads: 0
  pendingUpdate: null
  rejectedPendingReason: null
  friendlyId: {rid}
data:
  accentOverride: null
  settings:
{indent(settings_block, 4)}
  sharedStyles: ''
  styles:
{chr(10).join(style_lines)}
  tokens: null
  tokensDark: null
"""

    payload = base64.b64encode(doc.encode("utf-8"))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(HEADER + payload)

    check = base64.b64decode(OUT.read_bytes()[8:]).decode("utf-8")
    if not check.startswith("version: 1") or "data:" not in check:
        sys.exit("self-check failed: generated payload is not valid")

    print(f"built {OUT} ({OUT.stat().st_size:,} bytes, {len(styles)} widget styles)")


if __name__ == "__main__":
    main()
