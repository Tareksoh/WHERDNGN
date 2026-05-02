"""
Generate Arabic voice cues for bidding events using edge-tts. Voice is
ar-SA-HamedNeural (Saudi Arabic male) so the announcements match the
kammelna feel. Output goes through ffmpeg to land as small OGG files.

Usage (PowerShell):
    python sounds/_make_voice.py                          # regenerate ALL
    python sounds/_make_voice.py triple four gahwa aka    # specific cues

Output (in sounds/, overwrites previous):
    hokm.ogg     "حُكُمْ"  — someone bid Hokm
    sun.ogg      "صنّ"    — someone bid Sun
    ashkal.ogg   "أشكَل"   — someone bid Ashkal
    pass.ogg     "بسْ"    — round-1 pass
    wla.ogg      "ولا"     — round-2 pass
    awal.ogg     "أوَل"    — round-1 bidding start
    thany.ogg    "ثآني"   — round-2 bidding start
    triple.ogg   "ثري"    — Triple (×3) escalation
    four.ogg     "فور"    — Four (×4) escalation
    gahwa.ogg    "قْهوه"   — Gahwa (match-win) escalation
    aka.ogg      "إِكَه"   — AKA partner-coordination signal
"""
import asyncio
import os
import subprocess
import sys
import tempfile

import edge_tts

DST = os.path.dirname(os.path.abspath(__file__))
VOICE = "ar-SA-HamedNeural"

# Slightly faster + slightly higher pitch reads more like a game-show
# announcer than the default conversational delivery.
RATE  = "+10%"
PITCH = "+3Hz"

CUES = {
    "hokm":   "حُكُمْ",
    "sun":    "صنّ",
    "ashkal": "أشكَل",
    "pass":   "بسْ",
    "wla":    "ولا",
    "awal":   "أوَل",
    "thany":  "ثآني",
    "triple": "ثري",
    "four":   "فور",
    "gahwa":  "قْهوه",
    "aka":    "إِكَه",
}


def _selected_cues():
    """If invoked with positional args, only generate those cues —
    handy for regenerating the 4 odd-sounding files without touching
    the consistent ones. e.g.:
        python sounds/_make_voice.py triple four gahwa aka
    """
    if len(sys.argv) > 1:
        return {k: v for k, v in CUES.items() if k in sys.argv[1:]}
    return CUES


async def synth_one(text, mp3_path):
    comm = edge_tts.Communicate(text, VOICE, rate=RATE, pitch=PITCH)
    await comm.save(mp3_path)


def to_ogg(mp3_path, ogg_path, quality=4):
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", mp3_path,
        "-c:a", "libvorbis", "-q:a", str(quality),
        "-ac", "1",            # mono — half the bytes, fine for VO
        "-ar", "44100",
        ogg_path,
    ]
    subprocess.run(cmd, check=True)


async def main():
    for name, text in _selected_cues().items():
        with tempfile.NamedTemporaryFile(
                suffix=".mp3", delete=False) as tmp:
            mp3 = tmp.name
        try:
            await synth_one(text, mp3)
            ogg = os.path.join(DST, f"{name}.ogg")
            to_ogg(mp3, ogg)
            size = os.path.getsize(ogg)
            print(f"  {name:7s} {text:8s} {size:6d} bytes")
        finally:
            try:
                os.unlink(mp3)
            except OSError:
                pass
    print("done.")


if __name__ == "__main__":
    asyncio.run(main())
