# 43 — Video #19 Six-Factor Opp-Tanfeer Re-Verify @ HEAD

**HEAD:** `83717be` (v0.9.1, one ahead of v0.9.0; no Section-11 deltas)
**Source:** `docs/strategy/_transcripts/19_discover_via_tahreeb_extracted.md`
**Earlier audit:** `audit_v0.7.1/AUDIT_REPORT.md:173` (item 11)
**Cross-ref:** `audit_v0.9.0/23_section11_now.md:31-33` already flagged as STILL MISSING

## Verdict matrix

| Question | Answer |
|---|---|
| 1. Still NOT-WIRED at HEAD? | **YES — fully unimplemented.** |
| 2. Any partial / single-factor heuristic? | **NO.** |
| 3. Added to decision-trees Section 11 as a rule? | **NO.** |
| 4. Should this be wired? | **YES — meaningful Saudi Master uplift.** |

## Code-side evidence (NOT WIRED)

`grep tanfeerWeight\|tanfeerSeen\|tanfeerAbsent\|tanfeerSwitchedTo` across `Bot.lua`, `BotMaster.lua`, `State.lua`, `Constants.lua` returns **zero hits**. The proposed ledger keys from the transcript (`tanfeerSeen[suit]`, `tanfeerAbsent[suit]`, `tanfeerSwitchedTo[suit]`, helper `tanfeerWeight(seat, suit)`) do not exist anywhere.

`Bot.lua:209` `emptyStyle()` has no per-opp `tanfeerSeen` table. `Bot.OnPlayObserved` (Bot.lua:267) the obvious WRITE-site never opens an opp-discard branch. `pickLead` (Bot.lua:953) has no opp-tanfeer avoid-suit gate. The only "Tanfeer" symbols in Lua are the Section-9 SENDER (Bot.lua:2891-2911) — that emits OUR tanfeer, not the **READER** for opponents.

## Doc-side evidence (NOT in Section 11)

`decision-trees.md:258-271` Section 11 has 8 rows. None reference video #19, opp-Tanfeer, or any six-factor scaling. The transcript itself at line 155 explicitly recommends cross-promotion to "Section 11 (reads/inference)" — never executed.

`signals.md:126-136` is the **only** doc-side surface: a 12-line summary of the six factors, no rule rows, no MAPS-TO, no `(not yet wired)` table-row format. Doc-side gap mostly persists.

`bot-personalities.md:179` lists the video as Fzloky+/Master tier deferred work — confirming intentional non-implementation, not oversight.

## Why this is worth wiring

The six-factor reader is the **only opponent-side reading framework** in the corpus. Every other Section-11 rule reads PARTNER. With no opp model, M3lm/Fzloky/Master tiers play partial-info games half-blind: ISMCTS sampler has no bias on opp K/T-of-suit holdings beyond what `meldPins` captures. Bargiya-from-opp (rule 2.2 row 3) alone would unlock SWA-counter heuristics absent everywhere.

Lift estimate: per audit_v0.7.1, this was tagged "would meaningfully advance Saudi Master tier reads." Confirmed at HEAD; no progress.

## Recommended sequencing

1. Doc-side first: add 6 rows to `decision-trees.md` Section 11 mapping the six factors with `(not yet wired)`.
2. Add `Bot._partnerStyle[oppSeat].tanfeerSeen[suit]` to `emptyStyle()`.
3. Wire WRITE in `Bot.OnPlayObserved` opp-not-winning branch.
4. Wire READ in `pickLead` and ISMCTS sampler bias.
