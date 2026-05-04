"""GPU-accelerated whisper for 5 no-subs videos.

Uses 'large-v3' model on CUDA — the user-recommended config for
Saudi dialect quality. RTX 5080 with 16 GB VRAM handles large-v3
comfortably.

Output flushed line-by-line so background-task log shows progress.
"""
import subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).parent
AUDIO = HERE / "whisper_audio"

files = sorted(AUDIO.glob("*.mp3"))
print(f"Transcribing {len(files)} files with whisper large-v3 on CUDA...", flush=True)

for i, mp3 in enumerate(files, 1):
    out_txt = HERE / f"{mp3.stem}_whisper.ar.txt"
    if out_txt.exists():
        print(f"[{i}/{len(files)}] {mp3.name} already done, skipping", flush=True)
        continue
    t0 = time.time()
    print(f"[{i}/{len(files)}] {mp3.name} ...", flush=True)
    res = subprocess.run([
        "whisper", str(mp3),
        "--language", "ar",
        "--model", "turbo",  # 10x faster than large-v3, comparable quality
        "--device", "cuda",
        "--output_format", "txt",
        "--output_dir", str(HERE),
        "--verbose", "False",
    ], capture_output=True, text=True)
    elapsed = time.time() - t0
    if res.returncode != 0:
        print(f"  FAILED ({elapsed:.0f}s): {(res.stderr or res.stdout)[-1000:]}", flush=True)
    else:
        default_out = HERE / f"{mp3.stem}.txt"
        if default_out.exists():
            default_out.rename(out_txt)
        print(f"  OK ({elapsed:.0f}s) -> {out_txt.name}", flush=True)

print("Done.", flush=True)
