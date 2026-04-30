"""
Generate Arabic voice cues using ElevenLabs.

Reads the API key from the ELEVENLABS_API_KEY environment variable.
DO NOT hard-code the key in this file or pass it on the command line —
keys are sensitive credentials and should stay in the user's env / a
.env file the user manages.

Usage (PowerShell):
    $env:ELEVENLABS_API_KEY = "<your-key>"
    python sounds/_make_voice_eleven.py

Voice ID is provided as VOICE_ID below — change it to swap the voice.
The default points at the user-selected voice from the chat.

Output (in sounds/, overwrites previous attempts):
    hokm.ogg     "حكم"
    sun.ogg      "صن"
    ashkal.ogg   "أشكال"
    awal.ogg     "أوّل"
    pass.ogg     "باس"
"""
import os
import subprocess
import sys
import tempfile

from elevenlabs.client import ElevenLabs

DST = os.path.dirname(os.path.abspath(__file__))

# Voice ID. "Saud - deep voice" (3nav5pHC1EYvWOd5LmnA) is the user's
# preferred professional library voice — requires a paid ElevenLabs
# plan. Override via ELEVENLABS_VOICE_ID env var if you want a different
# voice without editing this file.
VOICE_ID = os.environ.get("ELEVENLABS_VOICE_ID") or "3nav5pHC1EYvWOd5LmnA"

# eleven_multilingual_v2 supports Arabic and is the highest-quality
# tier for non-English content. eleven_turbo_v2_5 is faster but slightly
# lower fidelity — fine for short bid cues if the v2 quality drops.
MODEL_ID = "eleven_multilingual_v2"

CUES = {
    "hokm":   "حكم",
    "ashkal": "أشكَل",
    "sun":    "صَنْ",
    "pass":   "بَسْ",
    "awal":   "أوَل",
}


def to_ogg(mp3_path, ogg_path, quality=4):
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", mp3_path,
        "-c:a", "libvorbis", "-q:a", str(quality),
        "-ac", "1",
        "-ar", "44100",
        ogg_path,
    ]
    subprocess.run(cmd, check=True)


def main():
    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        print("error: ELEVENLABS_API_KEY env var is not set", file=sys.stderr)
        sys.exit(2)

    client = ElevenLabs(api_key=api_key)

    for name, text in CUES.items():
        with tempfile.NamedTemporaryFile(
                suffix=".mp3", delete=False) as tmp:
            mp3 = tmp.name
        try:
            audio_iter = client.text_to_speech.convert(
                voice_id=VOICE_ID,
                model_id=MODEL_ID,
                text=text,
                output_format="mp3_44100_128",
            )
            with open(mp3, "wb") as f:
                for chunk in audio_iter:
                    if chunk:
                        f.write(chunk)
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
    main()
