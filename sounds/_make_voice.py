"""
Generate Arabic voice cues for bidding events using edge-tts. Voice is
ar-SA-HamedNeural (Saudi Arabic male) so the announcements match the
kammelna feel. Output goes through ffmpeg to land as small OGG files.

Output (in sounds/):
    hokm.ogg     "حكم"   — someone bid Hokm
    sun.ogg      "صن"    — someone bid Sun
    ashkal.ogg   "أشكال" — someone bid Ashkal
    awal.ogg     "أوّل"   — first bidder announcement (round start)
    pass.ogg     "باس"   — someone passed
"""
import asyncio
import os
import subprocess
import tempfile

import edge_tts

DST = os.path.dirname(os.path.abspath(__file__))
VOICE = "ar-SA-HamedNeural"

# Slightly faster + slightly higher pitch reads more like a game-show
# announcer than the default conversational delivery.
RATE  = "+10%"
PITCH = "+3Hz"

CUES = {
    "hokm":   "حكم",
    "sun":    "صن",
    "ashkal": "أشكال",
    "awal":   "أوّل",
    "pass":   "باس",
}


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
    for name, text in CUES.items():
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
