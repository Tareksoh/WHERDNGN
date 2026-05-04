# Saudi Baloot strategy reference

Topic-organized notes distilled from real Saudi tournament videos
and commentary. Used by Claude Code when modifying bot decision
logic in `Bot.lua` / `BotMaster.lua`.

---

## Quick navigation

**Always start here:**

- [`glossary.md`](./glossary.md) — Arabic terms ↔ code identifiers
  (with line-number cross-refs into Bot.lua / BotMaster.lua).
  *Always check here before adding a new term.*
- [`saudi-rules.md`](./saudi-rules.md) — rule deltas vs French
  Belote. The non-obvious differences.
- [`decision-trees.md`](./decision-trees.md) — operational
  WHEN/RULE/MAPS-TO chains. **The file Claude Code translates
  directly into bot logic.** Topic docs are descriptive;
  decision-trees is operational.

**Decision-by-phase:**

- [`bidding.md`](./bidding.md) — Hokm vs Sun vs Ashkal vs Pass.
- [`escalation.md`](./escalation.md) — Bel / Bel x2 / Four / Gahwa
  chain.
- [`opening-leads.md`](./opening-leads.md) — trick-1 leads.
- [`signals.md`](./signals.md) — AKA, partner conventions, implicit
  signaling.
- [`endgame.md`](./endgame.md) — last 3 tricks, SWA, Al-Kaboot.

**Bot personality:**

- [`bot-personalities.md`](./bot-personalities.md) — what
  distinguishes Basic / Advanced / M3lm / Fzloky / Saudi Master
  tiers.

**Workflow:**

- [`transcripts.md`](./transcripts.md) — how to pull YouTube
  transcripts and turn them into notes.

---

## How to use these files

### When modifying bot logic

1. Identify the picker you're touching (`Bot.PickBid`,
   `Bot.PickDouble`, `pickFollow`, etc.).
2. Open the matching topic file. Read the "What this file
   informs" section at the top — it lists the exact code
   identifiers that file owns.
3. Read the strategy notes; check the source video log to confirm
   the rule has multiple corroborating sources (or note that it's
   a single-source heuristic).
4. Make the code change; in your commit message reference the
   topic doc and the corroborating videos.

### When adding new strategy notes

1. **Check `glossary.md` first** — does the Arabic term you're
   about to introduce already have a code identifier? Use the
   existing one.
2. Add notes under the right topic file (not a new file).
3. Add a row to that file's "Source video log" table.
4. If the note implies a rule that disagrees with `saudi-rules.md`
   or `Rules.lua`, **flag the discrepancy**, don't silently update
   either side.

### When you're not sure where a note belongs

The decision tree:

- **Is it about declaring intent at the start of the round?** →
  `bidding.md` (Hokm/Sun/Ashkal) or `escalation.md` (Bel/Bel-x2/
  Four/Gahwa).
- **Is it about which card to lead?** → `opening-leads.md` for
  trick-1; `endgame.md` for trick-6+; otherwise inline in the
  relevant tier doc in `bot-personalities.md`.
- **Is it about reading partner?** → `signals.md`.
- **Is it about a specific Saudi rule that French Belote doesn't
  have?** → `saudi-rules.md`.
- **Is it about a tier-distinguishing playstyle?** →
  `bot-personalities.md`.

When genuinely unclear, `bot-personalities.md` is the fallback —
notes about playstyle differentiation.

---

## Status

**Heavily populated** as of latest video-batch session. ~22k words
across 11 strategy docs, distilled from **40+ Saudi Baloot tutorial
videos** processed via auto-captions + whisper-large-v3 (RTX 5080).

### What's in here

- **Operational rules** in `decision-trees.md` — ~140 WHEN/RULE/MAPS-
  TO rows across 11 sections, with confidence ratings (Definite /
  Common / Sometimes).
- **Authoritative term mappings** in `glossary.md` — Tahreeb /
  Tanfeer / Faranka / Bargiya / Takbeer / Tasgheer / al-Kaboot
  fully defined; family-trio card naming (شايب=K, بنت=Q, ولد=J)
  authoritative.
- **Rule-correctness verifications** in `saudi-rules.md` — most
  Saudi-specific rules already implemented in `Rules.lua` /
  `Net.lua` (Bel-100 gate, pos-4 ruff-relief, must-overcut-not-
  partner, Sun ×2 multiplier, Ashkal seat eligibility); open
  questions flagged with code locations.

### Recent major findings (highlights)

- **Tahreeb is richer than initially assumed** — 5 forms,
  direction-encoded discards, 70/25/5 receiver prior, 90% on
  two-trick confirmation, 100% on small-to-big sequence.
- **Tanfeer is the parent class; Tahreeb is the intent-bearing
  subset** (taxonomic correction from video #12).
- **Faranka inverts default** between Sun (default YES, 5-factor
  scoring) and Hokm (default NO, 5 narrow exceptions).
- **Sun-Bel-100 legality gate** — already in `N._SunBelAllowed`
  (Net.lua:68); enforces "team ≥101 forbidden from Bel" exactly.
- **Implicit AKA via bare-Ace lead** — extends v0.5.1 H-5
  receiver convention.
- **Early-trigger Al-Kaboot pursuit at trick 3** (not 8) when
  hand-shape feasible — bot currently only triggers at trick 8.
- **The "smart move"** (J/T sacrifice for deception) — has no
  settled Saudi name; Saudi-Master tier signature move.

### What's still open

1. **Score-rounding direction** — code rounds 65 DOWN to 60;
   one video said UP to 70. Verify.
2. **Sun Belote (ملكي)** — single-source claim of K+Q meld in Sun;
   currently Hokm-only in code.
3. **سيكل (sykl)** — possible 9-8-7 sequence meld; unconfirmed.
4. **Bel hand-strength thresholds** — no video covered specific
   numerical thresholds for *when* to call Bel; remaining gap.

The empirical baseline
(`.swarm_findings/bot_baseline_metrics.json`) showed
Bel/Bel-x2/Four/Gahwa firing at 0% in symmetric pure-bot play
prior to this video-batch update. The new strategy notes provide
the calibration inputs needed to fix that.
