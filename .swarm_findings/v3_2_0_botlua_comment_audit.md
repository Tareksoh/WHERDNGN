# Bot.lua Inline Comment Audit (v3.2.0 design pass)

**Repo:** `C:\CLAUDE\WHEREDNGN`
**Main / origin main:** `674de22` (clean)
**Last shipped tag:** `v3.1.14`
**Scope:** design / inventory only — no runtime or test edits.

---

## TL;DR

- **383 contiguous comment blocks** scanned in `Bot.lua`.
- **24 comment-text strings** are pinned by `tests/test_state_bot.lua`
  via `botSrc:find(...)`; touching them breaks the harness even though
  no behaviour changes.
- The single highest-value, lowest-risk cleanup target is **stale
  absolute line references** introduced before Batches 5C / 8 / 9
  (e.g. `Bot.lua:4842+`, `Bot.lua:4886+` in the L800-830 Bargiya
  block — those line numbers no longer point at the cited code).
- Most large blocks are **rule-intent prose** that should stay near
  the code; the bulk that should leave is **audit-version metadata**
  (`v1.5.3 swarm`, `audit follow-up agent #N`, ...) and one-time
  refactor breadcrumbs.
- **Recommendation: B** — a small comment-only cleanup batch that
  fixes stale extraction breadcrumbs and trims audit-version preamble,
  with a hard exclusion list for the 24 pinned strings. Larger
  doc-migration is option C and is feasible but only justified if we
  also retarget the pinned tests, which is a separate harness change.

---

## §0 Stats (regenerated from current `Bot.lua`)

| Metric | Value |
|---|---|
| Total lines | 6,078 |
| Comment lines | 2,919 (~48%) |
| Contiguous comment blocks | 383 |
| Blocks ≥ 10 lines | 121 |
| Blocks ≥ 20 lines | 21 |
| Blocks ≥ 30 lines | 2 |
| `botSrc:find(...)` call sites in `tests/test_state_bot.lua` | 111 |
| Distinct literal substrings present in current `Bot.lua` | 79 |
| ...of those, code-line pins | 55 (some duplicates) → 48 unique |
| ...of those, **comment-line pins** | **24 unique** |

Block scan reproducer (see Appendix A) was re-run at the start of this
audit; numbers match exactly.

---

## §1 Comment Taxonomy

Seven categories. Each is illustrated with a real line range from
current `Bot.lua`.

### 1.1 RULE-INTENT — stays inline, do not touch

Comments that state *what Saudi-Baloot rule the code is encoding*.
Short, near the code, often quoting `decision-trees.md` row numbers.

> **Example: L1149-1156** — "Bottom-up signal: lowest-from-3+ no-A no-T."
> Compact, rule-named, codifies a video-sourced convention. Removing or
> shortening makes the picker arm unreadable to a future reviewer.

These are the smallest comments by count and **must stay verbatim**.
The cleanup loss-cost vs. ergonomic-gain ratio is bad.

### 1.2 NON-OBVIOUS TACTICAL HEURISTICS — keep, optionally trim

Multi-line prose that explains why a heuristic chose its specific
threshold (`6%`, `0.10 per factor`, `8% deception swap`, etc.).

> **Example: L3176-3200** — Faranka 5-factor framework. Prose explains
> the F1..F5 enumeration, base 0.50, clamp to [0.05, 0.95]. The
> *enumeration* is rule-intent and stays; the *historical justification*
> ("Pre-v1.5.0: flat 30%...") could move to `docs/strategy/signals.md`.

Trim opportunity: typically 4-8 lines of pre-version comparison at
the top of each block.

### 1.3 HISTORICAL AUDIT / VERSION NOTES — best move to docs

Lines like `-- v1.6.0 CS-03 (audit v1.5.3 swarm — predictability fix):`
or `-- v1.0.4 (agent #6): touching-honors signal`. These were valuable
at the time of merge as PR-style change rationale, but the information
is duplicated in:

- `CHANGELOG.md` (version history)
- `.swarm_findings/v1_5_3_*.md` (audit reports)
- `docs/strategy/*.md` (rule sources)

> **Example: L4266-4292** — pos-2 deception re-intro. The first 7 lines
> are a v1.4.6→v1.5.3→v1.6.0 trail of agent reasoning. The actual rule
> ("8% chance, swap down to next-lower same-suit winner, Hokm only,
> not trump, not Sun, etc.") is 4 lines in the middle.

Net win: ~50% line reduction on this category, with no behaviour or
review-traceability loss (the swarm-agent IDs and audit IDs survive
in the git log and `.swarm_findings/`).

### 1.4 VIDEO / PROVENANCE QUOTES — best move to docs

Verbatim Arabic phrases sourced from tournament videos, e.g.
`«راح اعطيك خمس عوامل رئيسيه»` ("I'll give you five main factors"),
along with `Sources: decision-trees.md Section 8 (Definite, videos 01, 03).`

> **Example: L3493-3501** — Tahreeb sender source attribution.

These are duplicated 1:1 in `docs/strategy/*.md` and
`docs/saudi-rules.md`. The inline `Sources: …` footer is genuinely
useful when reading code; the verbatim Arabic quote can be reduced to
a `video #N` shorthand and the full quote stays in the strategy doc.

### 1.5 STALE EXTRACTION BREADCRUMBS — **safe to fix now**

Comments that name a code location that has since moved due to
Batches 5C / 8 / 9. The biggest offender is in `Bot.lua` itself.

> **L823**: `--   (b) T-4 dump-larger sender (Bot.lua:4886+):`
> **L819**: `--   (a) bottom-up "want" sender (Bot.lua:4842+):`
>
> Bot.lua had ~8,428 lines pre-cleanup; pickLead/pickFollow lived
> at ~4,842 / ~4,886. After Batches 5C/8 extractions, the T-4
> dump-larger sender is now at **Bot.lua:3489** (Tahreeb prose) and
> the live arm sits at **Bot.lua:3646**, not 4886. The line numbers
> in the L800-830 block are wrong by ~1,200 lines.

Same stale anchor reappears in `Bot/PlayPrimitives.lua:294` — same
fix pattern applies there.

These are the **safest comments to touch**: they are factually wrong,
no test pins them, fixing them is a documentation-correctness win.

### 1.6 SOURCE-PIN PROTECTED — DO NOT TOUCH

Comment-shaped text that `tests/test_state_bot.lua` greps for via
`botSrc:find(...)`. Full list in §2.

### 1.7 OBVIOUS NOISE — judgement call, not high-value

Single-line comments that just restate the next statement:
`-- Check if Ace of this suit has been played.` (L1995).

These are ~3-5% of comment lines and are **not worth a batch on their
own**. They could be opportunistically dropped during an unrelated
refactor.

---

## §2 Source-Pin Safety Inventory

`tests/test_state_bot.lua` contains 111 `botSrc:find(...)` call sites.
After de-Lua-escaping (`%X` → `X`) and intersecting with current
`Bot.lua`, the 24 unique strings whose **first** matching line is a
comment (starts with `--`) are:

| # | First Bot.lua line | Pinned substring | Category |
|---|---|---|---|
| 1 | L287  | `v3.1.2 (IM-6` | audit ID |
| 2 | L1231 | `v1.0.0 ultra-audit H2 follow-up` | audit ID |
| 3 | L1317 | `v3.1.2 (TR-1` | audit ID |
| 4 | L1589 | `Bargiya receiver phase-split` | rule name |
| 5 | L1611 | `v3.0.3 GAP-05` | audit ID |
| 6 | L1833 | `v1.0.0 Cluster 1 (meld awareness): if PARTNER declared` | rule name |
| 7 | L1859 | `v1.0.0 Cluster 2 F3 (defender play): topTouchSignal READ-side` | rule name |
| 8 | L2141 | `v1.0.0 Cluster 1 (meld awareness) + ultra-audit H1 fix` | rule name |
| 9 | L2199 | `v3.0.3 GAP-03` | audit ID |
| 10 | L2368 | `v3.1.2 (Q4 Fix #1)` | audit ID |
| 11 | L2423 | `v1.0.0 Cluster 2 F4 (defender play): partner-void-suit ruff` | rule name |
| 12 | L2650 | `tPlusLowDoubletonSuit` | code identifier (also pinned in code) |
| 13 | L3063 | `v3.1.2 (IM-4` | audit ID |
| 14 | L3687 | `biggest mistake in Baloot` | video quote |
| 15 | L3743 | `v3.1.9 (partner-trump-led-fragile-lock)` | audit ID |
| 16 | L3795 | `minimum-sufficient lock` | rule name |
| 17 | L4023 | `Defender J/9 trump-burn protection on bidder` | rule name |
| 18 | L4100 | `v1.0.4 (agent #1): urgency-aware swing` | audit ID |
| 19 | L4127 | `v1.0.6 (N1): partner-meld-pin guard` | audit ID |
| 20 | L4646 | `R.CompareMelds` | API name (also pinned in code) |
| 21 | L4744 | `v1.0.4 (agent #7): M5 defender mirror` | audit ID |
| 22 | L5090 | `Mathlooth K-tripled (Sun, video #17` | rule name + video |
| 23 | L5256 | `v3.0.3 GAP-09` | audit ID |
| 24 | L5301 | `v3.1.2 (HK-5` | audit ID |

**Cleanup rule:** any candidate edit that would change one of these
24 substrings **must** be paired with a matching edit to the
corresponding `botSrc:find(...)` line in `tests/test_state_bot.lua`.
Such an edit is a "pin retarget" and turns the change from
comment-only into harness-touching, which doubles the review surface.

For a "comment-only, no harness changes" batch, exclude all 24.

---

## §3 Top 20 Comment Blocks Ranked

Ranking criterion: information density / stickiness vs. line count.
Blocks where the prose duplicates a doc, names a stale extraction
position, or recites pre-version history rank highest for cleanup.

Risk: **L** = low (no pin, no rule-intent loss); **M** = medium
(rule-intent partly inline, partly refactorable); **H** = high
(pinned by tests, or rule-intent inline).

| # | Lines | Size | Subject | Risk | Recommendation |
|---|---|---|---|---|---|
| 1 | L800-830 | 32 | Bargiya `lenAtFirstDiscard` capture; **contains stale `Bot.lua:4842+` / `Bot.lua:4886+` refs** | **L** | **SHORTEN INLINE** — fix the stale line refs (replace numeric anchors with named subsystem refs, e.g. `(see Tahreeb sender below in pickFollow)`), trim the v3.0.6 GAP-01 backstory to 1 line. |
| 2 | L5619-5648 | 31 | `perturbLeadSuit` predictability fix prose | **L** | **SHORTEN INLINE** — the carve-out list (trump leads, A/J leads, singletons) stays; the 8-line "forward-decl pattern in Lua 5.1" rationale and the "pre-v1.5.3 audit" lineage can compress to 2-3 lines. |
| 3 | L4266-4292 | 28 | pos-2 deception re-intro (v1.6.0) | **L** | **MOVE DETAIL TO DOC** — v1.4.6→v1.5.3 lineage to `.swarm_findings/v1_5_3_*.md`; inline keeps the carve-out list + trigger condition (~8 lines). |
| 4 | L1604-1628 | 26 | Bargiya phase-split phase-rationale | **H** | **DO NOT TOUCH YET** — pinned by `v3.0.3 GAP-05` and `Bargiya receiver phase-split`. Compresses to ~10 lines after pin retarget. |
| 5 | L3176-3200 | 26 | Faranka 5-factor framework | **M** | **SHORTEN INLINE** — F1..F5 enumeration is rule-intent (keep). Trim the "Pre-v1.5.0: flat 30%..." lead-in (~6 lines). Quote `«راح اعطيك خمس عوامل رئيسيه»` moves to `docs/strategy/signals.md`. |
| 6 | L3477-3501 | 26 | Tahreeb sender (Section 8) | **L** | **SHORTEN INLINE** — keep T-1 Bargiya / T-4 Dump-ordering subsection headers; cut redundant "When neither rule fires..." footer (the lowestByRank fallback is visible in code). |
| 7 | L4786-4809 | 25 | `deceptiveOverplay` v1.1.0 HIGH-2 | **L** | **MOVE DETAIL TO DOC** — audit-rationale-heavy; keep the 4-line "what does it actually do" summary. |
| 8 | L3098-3120 | 24 | Sun pos-4 Faranka (Section 5) | **L** | **SHORTEN INLINE** — section header + 2 carve-outs; trim the source-video preamble. |
| 9 | L4370-4392 | 24 | Takbeer/Tasgheer certainty (v1.4.1 Concern 4) | **L** | **SHORTEN INLINE** — the caveats list (`Sun-only`, `Pos-4 void`, `Skip if A/T`) is the high-density bit; the "Behavior is not off" gate paragraph repeats what the `if` condition encodes. |
| 10 | L5149-5171 | 24 | N-1 Tanfeer sender (Section 9) | **L** | **SHORTEN INLINE** — N-2 default semantics paragraph is one sentence in `decision-trees.md`; quote it once and link rather than rewriting inline. |
| 11 | L3020-3041 | 23 | M4 receiver-relief upstream change (v0.10.2) | **L** | **MOVE DETAIL TO DOC** — describes an *upstream call-site contract*; that belongs in `docs/strategy/decision-trees.md` more than in a picker comment. |
| 12 | L3743-3763 | 22 | partner-trump-led-fragile-lock (v3.1.9) | **H** | **DO NOT TOUCH YET** — pinned (`v3.1.9 (partner-trump-led-fragile-lock)` and `minimum-sufficient lock`). |
| 13 | L4422-4442 | 22 | pos-3 hold-back psychological bait (v1.4.4) | **M** | **SHORTEN INLINE** — video #20 quote moves to docs; the bait threshold + carve-outs stay. |
| 14 | L1797-1816 | 21 | H-12 Fzloky BOT-vs-BOT signal | **M** | **SHORTEN INLINE** — Audit Tier 3 preamble can compress to one line; the actual signal definition (4-5 lines) stays. |
| 15 | L2256-2275 | 21 | Defender / bidder's-partner / Sun lead don't-burn-high | **L** | **SHORTEN INLINE** — well-written; the "history of how we got here" header is the only excess. |
| 16 | L2632-2651 | 21 | Adjacent-to-T anti-rule (v1.4.3, video #2) | **L** | **SHORTEN INLINE** — video #2 source moves to docs; the "if hold T and adj+1" rule stays inline (~4 lines). |
| 17 | L3348-3367 | 21 | Touching-honors signal in pickFollow (v1.0.4 agent #6) | **L** | **SHORTEN INLINE** — agent #N attribution drops; rule stays. |
| 18 | L5256-5275 | 21 | v3.0.3 GAP-09 (DEFERRED v1.4.1) | **H** | **DO NOT TOUCH YET** — pinned (`v3.0.3 GAP-09`). Otherwise SHORTEN. |
| 19 | L1995-2013 | 20 | "Check if Ace of this suit has been played" | **L** | **SHORTEN INLINE** — first line is restate-the-code noise; the rest is useful state-machine prose. Drop the first 4 lines. |
| 20 | L2515-2533 | 20 | v1.4.3 Sun establishing «مسك اللون» + round-end T deferral | **L** | **SHORTEN INLINE** — Arabic quote stays (rule name); "round-end T deferral" prose moves to `docs/strategy/endgame.md`. |

**Counts by recommendation in the top 20:**

- KEEP inline as-is: 0
- SHORTEN INLINE: 14
- MOVE DETAIL TO DOC: 3
- DO NOT TOUCH YET (pinned): 3

---

## §4 Before / After Example Rewrites (NOT applied)

Each example preserves the tactical claim and removes audit-story
prose. Line numbers refer to the **current** `Bot.lua` (post-Batch 9).
Diffs are illustrative — they are not committed.

### Example 1 — Stale extraction breadcrumbs (L800-830, 32 → ~14 lines)

**Before** (excerpt):

```lua
-- v0.10.2 M7 — Bargiya canonical FN: محشور بلون
-- واحد (cornered in one suit, video #14 rule 2)
-- promotes a single-event A discard from
-- bargiya_hint to confirmed bargiya WITHOUT a
-- second event. The classifier needs the sender's
-- pre-discard length-in-suit for that suit; capture
-- it host-side from S.s.hostHands (host has all
-- hands; non-host clients can't observe sender
-- shape). Stored as `list.lenAtAce` to keep the
-- numeric array of ranks backward-compatible.
-- Computed BEFORE the rank append so #list reads
-- the pre-record count for the Ace-first guard.
--
-- v3.0.6 follow-up to GAP-01 receiver fix: also
-- record `lenAtFirstDiscard` for ANY rank on the
-- first event in a suit. The v3.0.3 single-low
-- "want_hint" rule fires for any single 7/8/9
-- discard, but the bot SENDER emits low cards
-- through TWO distinct paths:
--   (a) bottom-up "want" sender (Bot.lua:4842+):
--       lowest from a 3+ no-A no-T suit. Intent:
--       "want this suit, no Ace." Single event
--       reads as "want_hint" — correct.
--   (b) T-4 dump-larger sender (Bot.lua:4886+):
--       LARGER first from a 2-card no-honor
--       doubleton. Intent: "descending = dontwant."
--       Single event of 9 (or 8 from 8+7) would
--       be mis-read as "want_hint" — sender's
--       suit-size was 2, not 3+.
-- Stash `lenAtFirstDiscard` so the classifier can
-- distinguish: only return "want_hint" when
-- sender held ≥3 cards in the suit at discard time.
```

**After** (proposed):

```lua
-- Bargiya canonical capture (محشور بلون واحد, video #14 rule 2).
-- For a single-event Ace discard, also stash the sender's
-- pre-discard length in the suit (`lenAtFirstDiscard`) so the
-- classifier can disambiguate between:
--   • bottom-up "want" sender — 3+ card no-A no-T suit, lowest
--     card. Single event → "want_hint" (correct).
--   • T-4 dump-larger sender — 2-card no-honor doubleton, LARGER
--     card first. Single event would otherwise be mis-read as a
--     positive want_hint. Guard: only return want_hint when
--     sender held ≥3 cards in the suit at discard time.
-- Capture is host-only (S.s.hostHands required for shape read);
-- `lenAtAce` is kept for backward compatibility with old rows.
```

Wins:

- 32 → 14 lines.
- Stale `Bot.lua:4842+` / `Bot.lua:4886+` line refs **removed**
  (they are wrong now, and replacing them with new absolute line
  refs would just stale again at the next refactor).
- v0.10.2 M7 / v3.0.6 GAP-01 lineage moves to git log + CHANGELOG.

### Example 2 — Forward-decl rationale (L5619-5648, 31 → ~14 lines)

**Before** (last 4 lines of the block):

```lua
-- Defined as a forward-decl-style local function so PickPlay can
-- reference it on the line above. Must come AFTER PickPlay since
-- Lua 5.1 needs the upvalue captured before the call site, but
-- since perturbLeadSuit is itself local, declaring it ABOVE PickPlay
-- (with a forward-decl pattern) is the cleanest fix.
```

**After**:

```lua
-- Forward-declared above PickPlay so the call site captures the
-- upvalue (Lua 5.1 scoping).
```

Wins: 5 → 2 lines on a single rationale; this pattern repeats in
~6-8 blocks where Lua 5.1 forward-decl shows up.

### Example 3 — Audit-version preamble (L4266-4292, 28 → ~12 lines)

**Before** (first 11 lines):

```lua
-- v1.6.0 (audit v1.5.3 swarm — pos-2 deception re-intro):
-- v1.4.6 fully removed the probabilistic pos-2 breaker
-- on the basis that v1.4.5's pure-probability deviation
-- read as «غلط» (beginner mistake) to a Saudi observer.
-- The v1.5.3 audit (variance gap, agent 4) found that
-- removal went too far for HUMAN-target play: pos-2 is
-- the most-read position in Saudi Baloot, and a fully
-- deterministic pos-2 makes the bot strictly readable.
-- Per video #22 R3, pros DO deviate at pos-2 — but on
-- HAND-SHAPE TRIGGERS, not pure probability.
--
```

**After**:

```lua
-- pos-2 deception (hand-shape triggered, not pure-probability).
-- Saudi pros DO deviate at pos-2 (video #22 R3), but only on
-- specific hand shapes — pure-probability deviation reads as
-- «غلط» (beginner mistake).
--
```

Wins: 11 → 4 lines. The v1.4.6→v1.5.3 lineage is recoverable
from git log + `.swarm_findings/v1_5_3_*.md`.

### Example 4 — Faranka 5-factor framework header (L3176-3200)

**Before** (lines L3176-3185, 10 lines):

```lua
-- v1.5.0 (audit follow-up — Faranka 5-factor framework).
-- Sources: video #06 (faranka_in_sun) — explicit 5-factor
-- framework + video #20 (control) — weak-partner inversion.
--
-- Pre-v1.5.0: flat 30% capture / 70% Faranka, with a
-- v1.3.0 weak-partner inversion to 70% capture. The flat
-- rate didn't reflect video #06's stated 5-factor
-- gradient («راح اعطيك خمس عوامل رئيسيه» — "I'll give you
-- five main factors"). Pros don't Faranka uniformly —
-- they evaluate factors and adjust.
```

**After**:

```lua
-- Faranka 5-factor framework (video #06, faranka_in_sun).
-- Each factor that favors Faranka decreases the capture
-- rate by 0.10 (more duck). Base 0.50, clamped to
-- [0.05, 0.95]. Weak-partner inversion: +0.40 capture
-- (video #20, strong-hand-grabs-tempo).
```

Wins: 10 → 5 lines. F1..F5 enumeration stays untouched directly
below.

### Example 5 — Obvious-noise lead-in (L1995-2013, first 4 lines)

**Before**:

```lua
-- Check if Ace of this suit has been played.
-- This is the discardPile semantics check, not a hand
-- check. discardPile is indexed by suit; entries are
-- card identifiers including rank.
```

**After**:

```lua
-- Has the Ace of this suit been played?
-- (discardPile is indexed by suit; entries are full card IDs.)
```

Wins: 4 → 2 lines. Restate-the-next-line opening removed.

### Example 6 — Source-attribution footer (L3501-3502)

**Before**:

```lua
-- When neither rule fires, fall through to lowestByRank.
-- Sources: decision-trees.md Section 8 (Definite, videos 01, 03).
```

**After**:

```lua
-- (Otherwise: lowestByRank. See decision-trees.md §8.)
```

Wins: 2 → 1 line. Pattern repeats across ~15-20 footer blocks.

### Example 7 — Pos-3 hold-back caveats (L4422-4442 excerpt)

**Before** (caveats footer, ~6 lines of "what video this came from"):

```lua
-- Video #20 captures the pattern at 14:32 — pos-3 holds
-- back the K with a confirmed J, lets the trick run, then
-- crushes on a later trick. The bait works against humans
-- who infer "if pos-3 had K they'd play it"; against bots
-- with perfect memory it has zero EV, hence the carve-out
-- below.
```

**After**:

```lua
-- (Source: video #20 @14:32. Bait targets humans; bots see
--  through it, hence the IsHuman carve-out below.)
```

Wins: 6 → 2 lines. Video timestamp preserved.

### Example 8 — Caveats-as-bullets condensation (L4370-4392 excerpt)

**Before**:

```lua
-- Caveats per videos:
--   * Sun-only (Hokm trump-led has different conventions)
--   * Pos-4 void verified via Bot._memory[pos4].void
--   * Skip if we're a STRONG suit holder ourselves
--     (don't burn our own future winners). Heuristic:
--     skip the donate if our highest card is A or T.
--
-- "Behavior is not off" gate: this fires ONLY when the
-- existing winners-based Takbeer can't (no winners),
-- so it's a pure addition to previously-default-low
-- behavior. Doesn't override the existing logic.
```

**After**:

```lua
-- Caveats: Sun-only; pos-4 void verified via
-- Bot._memory[pos4].void; skip if our highest is A or T
-- (don't donate future winners).
-- Pure-addition gate: this fires only when winners-based
-- Takbeer can't (no winners), so it never overrides.
```

Wins: 11 → 6 lines.

---

## §5 Safety Plan (future-batch shape, if approved)

If we proceed with **Recommendation B** (small cleanup batch), the
shape is:

1. **Branch:** `botlua-comment-cleanup-v3.2.0` off `674de22`.
2. **Scope rules:**
   - Edit `Bot.lua` only (no `BotMaster.lua`, no `Bot/*.lua` yet —
     each is a separate batch).
   - Zero runtime logic changes. No code line is added, removed, or
     reordered. Only `--` lines are touched.
   - No `tests/*.lua` edits in this batch.
   - The 24 pinned substrings from §2 are **not** changed.
3. **Per-block workflow:**
   - Identify candidate block (start with the top 5 safest from §3).
   - Verify no `botSrc:find(...)` pin overlaps the block lines.
   - Apply the rewrite. Re-run `python tests/run.py` — must be
     177/177 pass.
   - Commit per-block: `cleanup(Bot.lua): trim Lxxxx-yyyy <subject>`.
4. **Exit criteria:**
   - At most ~6-10 blocks per batch (capped so the diff stays
     reviewable).
   - Bot.lua line count drops by 80-150 net comment lines.
   - All 177 tests pass.
5. **Harness retargets are a SEPARATE batch:** if we later want to
   touch the 24 pinned substrings, that batch first edits
   `tests/test_state_bot.lua` to update each `botSrc:find('...')`
   to the new substring, then edits `Bot.lua`. Pin retargets are
   reviewable on their own.
6. **No release tag from this batch.** The next user-visible
   release is the trigger for a single combined hygiene tag (per
   the v3.2.0 release-readiness checkpoint, recommendation A.2).

Risk classes for a B-shaped batch: **LOW**. The harness catches any
accidental code-line edit; the pin exclusion list catches any
accidental pin breakage; the per-block commits keep the blast radius
of a bad rewrite to a single revert.

---

## §6 Recommendation

**B — small comment-only cleanup batch, limited to unpinned stale
and audit-version comments.**

Reasoning:

- Option **A** (do nothing) leaves the stale `Bot.lua:4842+` /
  `Bot.lua:4886+` line references in place. Those are factually
  wrong and will confuse the next reader looking at the Bargiya
  capture site; fixing them costs little.
- Option **C** (larger doc migration after pin inventory) is
  feasible — the pin inventory is in §2 of this doc — but it
  requires harness changes to retarget the 24 pinned substrings,
  which doubles the review surface and crosses the
  "no test edits this batch" line that has kept Batches 5C/8/9
  reviewable.
- Option **D** (defer until next user-visible release) is the
  *safe* default but misses an opportunity: comment cleanup is
  exactly the kind of "good hygiene during a quiet window" change
  that becomes harder once a new feature lands. The current state
  (clean tree, all extractions landed, `674de22`) is a near-ideal
  moment.

**Concretely, propose Batch 10:**

- Top 5 candidates (see §6.1 below) — all category 1.5 (stale
  extraction breadcrumbs) or 1.3 (audit-version preamble).
- ~80-100 net line reduction.
- Zero pin changes.
- Single design-review pass before commit.

### §6.1 Top 5 safest cleanup candidates

| Rank | Block | Lines | Risk | Why safe |
|---|---|---|---|---|
| 1 | L800-830 (Bargiya `lenAtFirstDiscard`) | 32 | L | Contains stale `Bot.lua:4842+/4886+` refs. No pin in range. Fix is doc-correctness. |
| 2 | L5619-5648 (`perturbLeadSuit` Lua 5.1 forward-decl rationale) | 31 | L | Lua-syntax-pattern explanation, no rule-intent, no pin. |
| 3 | L4266-4292 (pos-2 deception v1.4.6→v1.6.0 lineage) | 28 | L | Lineage prose only; carve-out list and 8% threshold stay. No pin. |
| 4 | L1995-2013 (Ace-of-suit discardPile check) | 20 | L | First lines are restate-the-next-statement noise; no pin, no rule loss. |
| 5 | L3098-3120 (Sun pos-4 Faranka Section 5) | 24 | L | Source-video preamble compressible; rule body stays. No pin. |

Cumulative: ~135 comment lines compressed to ~60 = -75 net lines.

### §6.2 Top 5 comments to AVOID touching

| Rank | Block | Lines | Why off-limits |
|---|---|---|---|
| 1 | L1604-1628 (Bargiya phase-split) | 26 | Pinned: `v3.0.3 GAP-05`, `Bargiya receiver phase-split`. |
| 2 | L3743-3763 (partner-trump-led-fragile-lock) | 22 | Pinned: `v3.1.9 (partner-trump-led-fragile-lock)`, `minimum-sufficient lock`. |
| 3 | L5256-5275 (v3.0.3 GAP-09 DEFERRED v1.4.1) | 21 | Pinned: `v3.0.3 GAP-09`. |
| 4 | L3682-3699 (v0.7.2 Section 4 rule 1B — "biggest mistake") | 19 | Pinned: `biggest mistake in Baloot`. |
| 5 | L5085-… (Mathlooth K-tripled, Sun, video #17) | varies | Pinned: `Mathlooth K-tripled (Sun, video #17`. |

Any cleanup that grazes any of these must first retarget the
corresponding `botSrc:find(...)` line in
`tests/test_state_bot.lua`, which is out of scope for a
comment-only batch.

---

## Appendix A — Scan reproducer

The block scan and pin-classification used the same Python script
that produced §0 stats:

```python
import re
with open('Bot.lua','r',encoding='utf-8') as f:
    lines = f.read().splitlines()
blocks = []
i = 0
while i < len(lines):
    if lines[i].lstrip().startswith('--'):
        j = i
        while j < len(lines) and lines[j].lstrip().startswith('--'):
            j += 1
        blocks.append((i+1, j, j-i))
        i = j
    else:
        i += 1
# blocks: list of (start_line, end_line_exclusive, size)
```

Pin classification:

```python
with open('tests/test_state_bot.lua','r',encoding='utf-8') as f:
    tlines = f.read().splitlines()
with open('Bot.lua','r',encoding='utf-8') as f:
    bot = f.read()
    bot_lines = bot.splitlines()
pats = []
for t in tlines:
    if 'botSrc:find' in t:
        m = re.search(r"botSrc:find\(\s*(['\"])(.*?)\1", t)
        if m: pats.append(m.group(2))
def deluap(s): return re.sub(r'%(.)', r'\1', s)
comment_pins, code_pins, seen = [], [], set()
for p in pats:
    lit = deluap(p)
    if lit in bot:
        for i,bl in enumerate(bot_lines,1):
            if lit in bl:
                bucket = comment_pins if bl.lstrip().startswith('--') else code_pins
                if lit not in seen:
                    bucket.append((lit, i)); seen.add(lit)
                break
```

Re-running these against the post-Batch-9 working tree reproduces
the numbers in §0 and the 24-row table in §2.

---

## Final report (per prompt)

- **Doc path:** `.swarm_findings/v3_2_0_botlua_comment_audit.md`
- **Recommendation:** **B** (small comment-only cleanup batch,
  limited to unpinned stale/extraction comments)
- **Number of comment blocks inspected:** 383 (all of `Bot.lua`;
  top-25 sampled in detail)
- **Number of source-pin-protected comment markers found:** **24**
  (full list in §2)
- **Top 5 safest cleanup candidates:** §6.1 — L800-830, L5619-5648,
  L4266-4292, L1995-2013, L3098-3120
- **Top 5 comments to avoid touching:** §6.2 — L1604-1628,
  L3743-3763, L5256-5275, L3682-3699, Mathlooth K-tripled block
- **Working tree status:** clean on `main` at `674de22`; no edits
  to runtime code, tests, or `.toc`. Only this design doc was
  written.
