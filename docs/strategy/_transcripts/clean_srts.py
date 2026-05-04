"""Clean SRT files into plain-text transcripts.

Strips:
- cue numbers
- timestamp lines
- the rolling-window duplication YouTube auto-caps emit

Outputs: {original_name_without_ext}.txt next to each .srt.
"""
import re
from pathlib import Path

HERE = Path(__file__).parent

TS_RE = re.compile(r"^\d{2}:\d{2}:\d{2}[,\.]\d{3} --> \d{2}:\d{2}:\d{2}[,\.]\d{3}\s*$")
CUE_RE = re.compile(r"^\d+\s*$")

for srt in sorted(HERE.glob("*.srt")):
    raw = srt.read_text(encoding="utf-8", errors="replace")
    lines = raw.splitlines()
    cleaned = []
    last = None
    for line in lines:
        s = line.strip()
        if not s:
            continue
        if TS_RE.match(s) or CUE_RE.match(s):
            continue
        # Skip if identical to last emitted line (rolling-window dedup).
        if s == last:
            continue
        cleaned.append(s)
        last = s
    out = srt.with_suffix(".txt")
    out.write_text("\n".join(cleaned) + "\n", encoding="utf-8")
    print(f"{srt.name}: {len(cleaned)} unique lines -> {out.name}")
