# Extracted from 07_baloot_strategies
**Video:** استراتيجيات البلوت
**URL:** https://www.youtube.com/watch?v=b7EJYg7vpJo

This is a high-level primer (≈4 KB transcript) defining what "strategy"
means in Baloot. The speaker frames **four** strategies grouped into
two states — when you are the bidder (مشتري) and when you are the
defender (غير مشتري). The video is intentionally example-free; the
speaker promises follow-up videos with concrete tactics.

---

## 1. Decision rules

### Section 1 — Bidding (`Bot.PickBid` Bot.lua:725)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| You / partner are deciding whether to bid (Hokm, Sun, or Ashkal) | A bid implicitly commits you to *one of two* outcomes: (a) make the contract so opponents do not "win on you" (يخسرون عليك), or (b) sweep all 8 tricks (Kaboot). The bidder must hold a hand consistent with at least one of those outcomes. | The video frames bidding as goal-setting: a bid without a path to either outcome is undisciplined. | `Bot.PickBid` (Bot.lua:725) — strength threshold already encodes (a); Kaboot pursuit is in `pickLead` trick-8 branch (Bot.lua:953). | Sometimes | Restates existing bot logic at high level; no new threshold. |

### Section 2 — Escalation (`Bot.PickDouble` 1787, etc.)

*No prescriptive rules in this video.* Escalation chain is not discussed.

### Section 7 — Endgame / Al-Kaboot (`pickLead` trick-8 branch, Bot.lua:953)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| You are the bidder team and the round is on track to make | Promote the secondary goal of Kaboot (sweeping all 8 tricks) because Kaboot points are higher in **both** Hokm and Sun. | Speaker explicitly: نقاط الكبوت اكثر سواء في الصلاه والحكم. | `pickLead` trick-8 / Al-Kaboot pursuit (Bot.lua:953); constants `K.AL_KABOOT_HOKM=250`, `K.AL_KABOOT_SUN=220`. | Common | Aligns with current `K.AL_KABOOT_*` thresholds — bot already prefers Kaboot when reachable. |

### Section 5/4 — Defender play (`pickFollow` Bot.lua:1457)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| You are a defender (one of the two non-bidder seats) | **Primary defender goal #1:** prevent Kaboot. Even winning a single trick is a "first success" against the bidder team — كسرت كبوت. | Removes the +250 / +220 bonus risk. | `pickFollow` (Bot.lua:1457) — defenders already prioritize taking ≥1 trick when Kaboot is threatened, but the rule is implicit; could be made an explicit guard in an "anti-Kaboot mode". | Common | The "single trick breaks Kaboot" framing is concrete enough to lift into a defender heuristic flag. |
| You are a defender and the round is mid-flight | **Primary defender goal #2:** force the bidder to *fail* (تخسرها على المشتري) by accumulating more trick-points than the bidder team — يجيبوا النقاط اعلى من نقاطكم. Capitalize on bidder errors (اكلات فيها اغلاط). | A failed bid hands all trick points to defenders (per `R.ScoreRound`); this is strictly better than merely limiting Kaboot. | `pickFollow` defender branches (Bot.lua:1457); `scoreUrgency` (Bot.lua:588) already tracks point-race urgency. | Common | Existing `scoreUrgency` matches the spirit; rule reinforces that defender pickers should weight *capturing high-value tricks* over *saving low cards*. |

---

## 2. New terms encountered

None outside the existing glossary. The speaker uses standard terms:
- **مشتري / غير مشتري** (mushtari / ghair mushtari) — bidder / non-bidder.
  Worth adding as a glossary alias for "bidder team" / "defender team"
  if a future doc references the Arabic phrasing.
- **استراتيجيه vs تكتيك** (strategy vs tactics) — the speaker's
  framing distinction; not a code term but useful conceptually:
  *strategy* = goal selection (make / Kaboot / break-Kaboot / fail-them);
  *tactics* = how you execute (تهرب, تفهم خويك, تتوقع الحله).
- **اكلات / حلات** — synonyms for "tricks" colloquially.

## 3. Contradictions

None. Video is high-level and consistent with `saudi-rules.md` and
existing bot logic.

## 4. Non-rule observations

- The video is the **first in a series** ("هنكمل لسه ان شاء الله في
  المقاطع الجايه") — explicitly defers concrete examples to later
  videos. Treat its rule output as scaffolding for the topic-specific
  videos (#1 tahreeb, #4/#6 faranka, etc.).
- The four-strategy taxonomy itself is the most useful artifact:
  | Role | Goal #1 | Goal #2 |
  |---|---|---|
  | Bidder team | Make the contract (don't let opponents win on you) | Pursue Kaboot |
  | Defender team | Break Kaboot (steal ≥1 trick) | Make bidder fail (out-score them) |
  This pairs cleanly with the bidder/defender split already in
  `pickFollow` and could be cited in `decision-trees.md` Section 7
  as the rationale for Kaboot pursuit + anti-Kaboot defense.
- Speaker mentions tactics-list (تهرب / تفهم خويك / تتوقع / هل تلعب
  قوتك) which previews **tahreeb (تهريب)**, partner-reading, and
  strength-management as the next videos' content. No rules to extract
  here, but worth noting that the speaker treats tahreeb as a tactical
  primitive — supports the glossary's current entry.

## 5. Quality notes

- **Length:** ~4 KB / ~1 minute of speech. Overview-only.
- **Prescription density:** very low. Speaker explicitly disclaims
  examples (معلش ما في امثله ولا حاجه). Almost everything is
  framing/definition.
- **Confidence ceiling:** `Common` at best for the rules above; most
  are restatements of well-known Saudi conventions rather than
  novel prescriptions. None reach `Definite` from this video alone.
- **Transcription:** auto-captioned Arabic with minor typos
  (البلوتوث for البلوت, الصلاه for الصن probably, خويه for خويك,
  استحوال for اشكال maybe). Meaning is recoverable from context.
- **Recommendation:** when adding rows to `decision-trees.md`, cite
  this video only as a *secondary* source (`07_baloot_strategies`)
  alongside a tactics-specific transcript that supplies the WHEN
  predicates. This video supplies the *WHY* but not the *WHEN*.
