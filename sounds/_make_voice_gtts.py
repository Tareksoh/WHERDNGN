"""
Generate Arabic voice cues using Google's gTTS (the public Translate
voice). Fallback if edge-tts dialects sound off — gTTS uses a single
Arabic voice that's closer to MSA / news-anchor delivery.

Output (in sounds/, overwrites edge-tts versions):
    hokm.ogg     "حكم"
    sun.ogg      "صن"
    ashkal.ogg   "أشكال"
    awal.ogg     "أوّل"
    pass.ogg     "باس"
"""
import os
import subprocess
import tempfile

from gtts import gTTS

DST = os.path.dirname(os.path.abspath(__file__))

CUES = {
    "hokm":   "حكم",
    "sun":    "صن",
    "ashkal": "أشكال",
    "awal":   "أوّل",
    "pass":   "باس",
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
    for name, text in CUES.items():
        with tempfile.NamedTemporaryFile(
                suffix=".mp3", delete=False) as tmp:
            mp3 = tmp.name
        try:
            # tld='com.sa' nudges Google toward Saudi-accent delivery
            # where supported. Arabic gTTS doesn't actually expose
            # per-region accents the way English does, but passing
            # 'com.sa' is a no-op on unsupported locales.
            gTTS(text=text, lang="ar", tld="com.sa", slow=False).save(mp3)
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
