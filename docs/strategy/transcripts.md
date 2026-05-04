# YouTube transcript workflow

Pipeline: **video → transcript → structured strategy notes → topic
files in this folder**.

This file documents the *how*. The actual strategy lives in
`bidding.md`, `escalation.md`, etc. Each topic file has a "Source
video log" table at the bottom — fill it in as you process videos.

---

## Tools you need

```bash
pip install yt-dlp openai-whisper
# or for Whisper specifically (recommended for Arabic):
pip install -U openai-whisper
```

`yt-dlp` ≥ 2024.x and `whisper` (OpenAI) ≥ 20240930 work well.

---

## Step 1 — Pull the transcript

### Path A — auto-captions (fast, sometimes garbage)

```bash
yt-dlp --write-auto-subs --skip-download \
       --sub-lang ar,en --convert-subs srt \
       "https://youtu.be/VIDEO_ID"
```

Outputs: `{title}.ar.srt` and/or `{title}.en.srt`. For Saudi Baloot
videos the Arabic auto-caps are usually OK for slow educational
content but break down on fast tournament commentary.

### Path B — Whisper (slower, much better)

```bash
yt-dlp -x --audio-format mp3 -o "video.%(ext)s" \
       "https://youtu.be/VIDEO_ID"
whisper video.mp3 --language ar --model medium --output_format srt
```

Models: `tiny` < `base` < `small` < `medium` < `large`. Use
`medium` for Arabic — `small` misses too many idiomatic terms;
`large` is overkill unless tournament commentary is very fast.

If you have a GPU, add `--device cuda` (massive speedup).

### Path C — manual export from YouTube Studio

If the video has hand-corrected captions, the YouTube studio
"transcript" panel often outputs cleaner text. Copy-paste into a
`.txt` file and skip the SRT step.

---

## Step 2 — Convert SRT → plain text (optional)

For feeding to Claude, you usually want the text without
timestamps:

```bash
# crude but effective:
sed -E 's/^[0-9]+$//; s/^[0-9:,. ]+-->[0-9:,. ]+$//; /^$/d' \
    video.ar.srt > video.ar.txt
```

Or just keep the SRT — Claude handles either.

---

## Step 3 — Hand the transcript to Claude

Paste the transcript (or the file path if local) and ask:

> Extract Saudi Baloot strategy from this transcript. Output as
> structured notes for `docs/strategy/{topic}.md`. Use the
> identifiers from `docs/strategy/glossary.md` — DO NOT invent
> new terms. If the video covers multiple topics, output a
> separate section per topic. Preserve Arabic terms in parentheses
> (e.g., "Hokm (حكم)") since they appear in our codebase.
> If the transcript contradicts `saudi-rules.md`, flag the
> contradiction explicitly — do not silently accept the video as
> truth.

This prompt is also good for **`/loop` invocations** if you batch-
process multiple videos.

---

## Step 4 — Merge into the topic file

Claude's output is a *draft section*, not a finished doc. Edit:

1. Place the section in the right topic file
   (`bidding.md`, `escalation.md`, …).
2. Add the source row to that file's "Source video log" table at
   the bottom.
3. Cross-reference any new code identifier — if the video introduces
   a concept the code doesn't have, *don't* add a new identifier
   speculatively. Add it to the file's "TODO from videos" list and
   come back to it when you have multiple corroborating sources.

**Bias check:** one video is anecdote. Two videos agreeing is
signal. Three+ videos agreeing is convention. Don't change bot
thresholds based on one source.

---

## Step 5 — Wire findings into bot logic (later, deliberate)

Once a topic file accumulates ≥3 corroborating sources for a
strategy element, that's grounds for a code change:

- Pick the file in `Bot.lua` / `BotMaster.lua` that owns the
  decision.
- Reference the topic doc in your commit message.
- If it's a threshold tweak, update the relevant `K.BOT_*_TH`
  constant.
- If it's a new heuristic, add it to the appropriate picker.
- **Always ship as its own commit** with a CHANGELOG entry —
  don't bundle multiple bot-logic changes from different videos.

---

## Recommended starting videos

> **You'll fill this in.** When you find a video worth
> processing, add it here so the next person picking up the
> work knows where to start. Suggested format:

| URL | Title | Length | Difficulty | Topics covered |
|---|---|---|---|---|
| _(empty — add as you go)_ | | | | |

---

## Quality control — how to know a transcript is usable

A transcript is **usable** if:

- ≥ 80% of card names render correctly (J/Q/K/A/9 — Arabic
  numerals + transliterated face cards).
- The escalation terminology is consistent (الحكم, الصن, الفور,
  القهوة).
- Player turn-taking is parseable from context.

If a transcript fails any of these, re-run with Whisper `large`
or skip the video.
