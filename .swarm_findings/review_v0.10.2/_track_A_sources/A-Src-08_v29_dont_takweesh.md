# A-Src-08 — Re-extraction of video #29 "Don't Takweesh Your Partner"

**Source:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\ePJkUJu8kfg_29_dont_takweesh.ar-orig.srt`
**Title:** لا تكوِّش في البلوت 🤝 (Don't Takweesh in Baloot)
**Length:** ~46 s, 19 lines, single-speaker monologue
**Purpose:** Verify B-Bot-10-5 (LOW NEW) — `Bot.PickKawesh` ignores Phase 1 H-34.9
"partner bought Hokm → NEVER kasho". Per Phase 1 `source_H_bidding_penalty.md`,
video #29 was claimed to disambiguate "don't takweesh your partner" as
**suppression of the KASHO call (pre-bid table-flip)** when partner is the buyer.

This re-extraction confirms the Phase 1 H reading and **flags a contradiction**
with the previously-written extraction
`C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\29_dont_takweesh_extracted.md`,
which interpreted the same video as "bid-override" (Takweesh-A). The actual
transcript content rules out the bid-override reading.

---

## Headline finding

**Phase 1 H is correct.** Video #29 is about **kasho-suppression** — when partner
has bought (Sun or Hokm) and you happen to be holding a kasho-eligible (5×{7,8,9})
hand, the default play is to **suppress the kasho** (`تكوش`) and let partner
play their contract. The verb `تكوش` here is the table-flip / redeal-no-points
mechanic (same root as `K.MSG_TAKWEESH` in pre-bid mode), NOT a bid-override.

The earlier extraction `29_dont_takweesh_extracted.md` mis-classified this as
"Takweesh-A bid-override" — it should be re-classified as "Takweesh-B kasho
suppression". B-Bot-10-5 stands as a real LOW bug seed against `Bot.PickKawesh`.

---

## Per-question answers

### Q1 — Default suppression rule (verbatim Arabic)

| Field | Value |
|---|---|
| Arabic (≤15 words) | `الافضل انك ما تكوش الا في حاله واحده` |
| English | "The best is that you do NOT kasho except in one (single) case." |
| Timestamp | 00:05.749 — 00:07.789 (SRT cue 5) |
| Confidence | **High** (verbatim, central thesis sentence of the entire video) |

**Surrounding context (cues 1–5):**
> خويك اشترى سنه وحكم **وعندك ورق كوشه** هل تكوش ولا تخلي خويك يكمل حكمه
> واوصله طبعا الافضل انك ما تكوش الا في حاله واحده

> "Your partner bought Sun and Hokm and you have **kasho cards** (`ورق كوشه`),
> do you kasho or let your partner complete his Hokm and (help him) get there?
> Of course, the best is that you do NOT kasho except in one single case."

The phrase **`ورق كوشه`** at cue 1 is load-bearing: it identifies the hand-shape
as the standard kasho-eligible hand (all 5 cards ∈ {7, 8, 9}, per H-34.3). The
verb `تكوش` therefore = "call kasho", not "override partner's bid".

### Q2 — Exception conditions: partner hesitated + Sun + early game (verbatim)

| Field | Value |
|---|---|
| Arabic (≤15 words) | `شفت خويك متردد واخذ صن وكان في بدايه اللعب` |
| English | "You saw your partner hesitate, and he took Sun, and the game was in its early phase." |
| Timestamp | 00:07.799 — 00:10.080 (SRT cue 7) |
| Confidence | **High** (single-source but stated emphatically as the ONLY exception) |

**All three conditions are conjunctive (AND-joined):**
1. `متردد` — partner showed hesitation when bidding
2. `واخذ صن` — partner took **Sun specifically** (NOT Hokm)
3. `في بدايه اللعب` — game is in its early phase

**Continuation (cue 9, 00:10–00:13):**
> وانت تكون عارف انه خويك ممكن يشتري صنعاء على اي شيء

> "and you know that your partner could buy Sun on anything (i.e. weak Sun)."

This is the rationale: partner-hesitation + early-Sun = no concrete project to
disrupt; partner could have bid Sun on almost any hand, so kasho is less
destructive. Outside this narrow case the suppression default holds.

### Q3 — Hokm-vs-Sun distinction: if partner bought Hokm, NEVER kasho?

**#29 alone does NOT make the Hokm-vs-Sun categorical distinction explicit.**
It states the exception is **Sun-specific** (`واخذ صن` in Q2) — which
**implies** Hokm has no exception, but #29 does not say "NEVER kasho on partner
Hokm" verbatim.

The categorical "NEVER kasho on partner Hokm" rule comes from **video #34**
(H-34.9), which states it explicitly:

| Field | Value |
|---|---|
| Source | #34 cue 224–229 (`p0svUm6THvA_34_takweesh_basics.ar-orig.srt`) |
| Arabic (≤15 words) | `في حاله خويك شاله حكم هذي ما انصحك تكوش ابدا` |
| English | "In the case where your partner bought Hokm, I do NOT recommend that you kasho — ever." |
| Timestamp | 00:05:33.71 — 00:05:36.12 (#34) |
| Confidence | **High** (verbatim, with reinforcement) |

**Reinforcement at #34 cue 227–229 (00:05:36–00:05:43):**
> سواء الجيم حامي ولا مثلا جيم لسه بدايته سواء عندك حكم ولا ما عندك حكم
> الافضل انك ما تكونش

> "Whether the game is hot (close-finish) or just at its beginning, whether you
> hold trump or do not hold trump, the best is for you not to kasho."

So **#29 IMPLIES** the Sun-only-exception (by listing Sun as the only
exception). **#34 STATES** the categorical NEVER-on-partner-Hokm rule.
Together they triangulate: partner-Hokm → never kasho; partner-Sun → suppress
kasho except in the narrow hesitated-AND-early-game case.

**Confidence: High** for the joint reading; **Med** for treating #29 alone as
the canonical source for the partner-Hokm rule.

### Q4 — Self-trigger override (kasho hand + ground card J/T/A → buy Hokm): does #29 cover this?

**No. #29 does NOT mention self-trigger overrides at all.** The transcript is
46 seconds, 19 lines, and contains zero references to ground-card values, the
J/T/A self-buy override, or the bidder-side decision tree.

The Phase 1 H claim that "#29 confirms" the self-trigger override is **incorrect
attribution**. The self-trigger override is documented exclusively in **#34**
(H-34.10 ground-J → buy Hokm at cue ~00:05:57–00:06:35; H-34.11 ground-10 → buy
Hokm at cue ~00:06:35–00:06:50; H-34.12 ground-Aka → may buy at cue
~00:06:50–00:07:01).

**Verdict:** Phase 1 H's claim that #29 confirms self-trigger override is **a
mis-cite**. #34 is the sole source. (#29 only addresses the partner-bought
side of the kasho decision.)

**Confidence: High** that #29 is silent on self-trigger override.

### Q5 — Bot.PickKawesh code is unconditional. Is that wrong per the speaker?

**Yes.** `Bot.PickKawesh` (Bot.lua:3801–3806) returns `true` whenever
`IsKaweshHand(hand)` is true and the phase is `K.PHASE_DEAL1`. It performs
**no check** for whether partner has already bid Sun or Hokm. Per the speaker
of #29 (and #34), this is **wrong** in three concrete repro scenarios:

| Scenario | Speaker's rule | Bot's behavior |
|---|---|---|
| Partner bought Hokm + bot has kasho-shape | #29 (implied via Sun-only exception) + #34 H-34.9 verbatim: NEVER kasho | Bot calls kasho → wipes partner's contract |
| Partner bought Sun confidently + bot has kasho-shape | #29: suppress (default) | Bot calls kasho → wipes partner's contract |
| Partner bought Sun, game is late (no early-game flag) | #29: suppress (early-game condition fails) | Bot calls kasho → wipes partner's contract |

**Verbatim verdict (#29 cue 5):**
> `الافضل انك ما تكوش الا في حاله واحده`
> "The best is that you do NOT kasho except in one single case."

The bot does the opposite of "the best": it kashos in **every** case where the
hand-shape qualifies. **B-Bot-10-5 is a real LOW bug seed** matching the
Phase 1 H interpretation.

**Confidence: High** (rule is verbatim, code is one-shot inspection).

### Q6 — Disambiguation from "bid-takweesh" (overbidding partner)

**The verb `تكوش` in #29 is NOT bid-overbidding.** Two textual proofs:

**Proof 1 — the question framing (cue 1–3):**
> هل تكوش **ولا تخلي خويك يكمل حكمه** واوصله

> "Do you kasho **OR let your partner complete his Hokm** and (help him) get
> there?"

The alternative to `تكوش` here is "let partner **complete** (`يكمل`) his
Hokm" — i.e. let the contract proceed to **play**. If `تكوش` meant
"bid-override", the alternative would be "let partner's bid stand" — but the
speaker says "complete his Hokm", which only makes sense if the alternative is
"the contract goes to play" vs "the deal is annulled" (= kasho mechanic).

**Proof 2 — the hand-shape label (cue 1):**
> `وعندك ورق كوشه` — "and you have **kasho cards**"

`ورق كوشه` is the standard label for the all-{7,8,9} hand-shape (per #34
H-34.3). The label `ورق تكويش` ("takweesh-worthy paper" used as bid-override
shorthand) does NOT appear at cue 1; it appears later at cue 19 (00:20.939–
00:23.810) as a synonym for the same hand. The speaker uses `كوشه` and
`تكويش` interchangeably for the same hand-type label in this video — they are
**semantic synonyms within #29**, both referring to the kasho-eligible hand.

**Verbatim from cue 19:**
> `لانه اصلا خويك ما يعرف انه عندك ورق تكويش`
> "...because your partner doesn't even know that you have takweesh cards."

This is the asymmetric-blame argument (H-29.5): partner can't see your hand,
so suppressing the kasho is socially safe; calling it visibly destroys
partner's contract. The argument only makes sense in the kasho-mechanic
reading. (If `تكوش` were bid-override, partner WOULD see it — bid-overrides
are public. The "خويك ما يعرف" / "partner doesn't know" framing is incoherent
under the bid-override reading.)

**Confidence: High** that `تكوش` in #29 = kasho mechanic, NOT bid-override.

### Q7 — Disambiguation from K.MSG_TAKWEESH penalty-call

**The verb `تكوش` in #29 IS the same root as `K.MSG_TAKWEESH`** (both = call
the takweesh/kasho table-flip), but the **trigger** is different:

| Aspect | #29 use | `K.MSG_TAKWEESH` (per #30 / #34 / #36) |
|---|---|---|
| Phase | Pre-bid (deal phase) | Pre-bid for Kasho variant; post-bid for Qaid variant |
| Trigger type | **Self-trigger from hand-shape** (5×{7,8,9}) | Hand-shape OR rule violation by another player |
| Output | Annul + redeal, no points (Kasho) | Kasho (no points) OR Qaid (16/26 points to caller) |
| Code path | `Bot.PickKawesh` (Bot.lua:3801) → calls Kawesh in `K.PHASE_DEAL1` | `K.MSG_TAKWEESH` networking message family |

**Both are the SAME mechanic** at the call layer. The disambiguation in #29 is
**not** "kasho vs penalty-call", it is "**when** to call kasho" — the speaker's
discipline rule is "if your hand qualifies AND partner has bought, suppress".

**No verbatim quote in #29 explicitly distinguishes the two senses** because
both are the same word/action; #29 only addresses the strategic discipline of
WHEN to call it.

The Phase 1 H disambiguation framing (penalty vs hand-shape kasho) is correct
across the cluster (#29 ∪ #30 ∪ #34 ∪ #36), but **video #29 alone does not
contain the Qaid distinction**; it stays at the kasho-suppression layer.

**Confidence: High** that #29 covers ONLY the kasho-mechanic side of the
takweesh family; the Qaid penalty-call is out-of-scope for this video.

### Q8 — Cross-check with #34 (takweesh basics) and #36 (qaid all)

**Cross-check #34 (`p0svUm6THvA_34_takweesh_basics.ar-orig.srt`):**

#34 is the **comprehensive** version of #29's lesson; #29 is its **short
summary companion**. #34 covers the full decision-matrix:

| #34 rule | #29 coverage |
|---|---|
| H-34.1 Definition of kasho mechanic | NOT in #29 (assumed background) |
| H-34.2 Trigger discipline | NOT in #29 |
| H-34.3 Canonical 5×{7,8,9} hand-shape | NOT explicitly defined in #29 (referred to as `ورق كوشه`) |
| H-34.4 Sessional same-suit-7-8-9 disallowed | NOT in #29 |
| H-34.5 Opponent bought → DEFAULT KASHO | NOT in #29 (out of scope: #29 is partner-only) |
| **H-34.6 Partner bought → DEFAULT NO KASHO** | **EXACTLY #29's central rule** (cue 5) |
| H-34.7 Opponent bought Sun → ALWAYS kasho | NOT in #29 |
| H-34.8 Opponent Hokm + game close-to-finish → may kasho | NOT in #29 |
| **H-34.9 Partner Hokm → NEVER kasho** | IMPLIED (by Sun-only exception) but not verbatim in #29; #34 states it verbatim at cue 224 |
| H-34.10/11/12 Self-trigger override (J/T/A on ground) | NOT in #29 |

**#29 = restricted projection of #34** onto the partner-bought sub-case.
Phase 1 H correctly attributed H-34.9 to #34, not #29. The B-Bot-10-5 finding
chain is sound.

**Cross-check #36 (`IEdE-FMXQ00_36_qaid_all.ar-orig.srt`):**

#36 covers the post-bid Qaid penalty-call family (failed-follow-suit,
failed-ruff, failed-overtrump, undeclared meld, observed cheat, soft triggers).
#36 does **NOT** address the pre-bid kasho-suppression decision, so it is
**not relevant** to B-Bot-10-5 verification.

The only #36 cross-cut to #29 is at the **terminology level** (H-30.10 / H-36
implicit): pre-bid kasho ≠ post-bid Qaid. #29 is purely pre-bid. Confirmed.

**Confidence: High** for both cross-checks.

---

## Aggregate confidence summary per question

| Q | Topic | Confidence |
|---|---|---|
| Q1 | Default suppression verbatim | **High** |
| Q2 | Exception conditions verbatim | **High** |
| Q3 | Hokm-vs-Sun distinction (#29 implies, #34 states verbatim) | **High** for joint; **Med** for #29-alone |
| Q4 | Self-trigger override coverage in #29 | **High** that #29 does NOT cover it |
| Q5 | Bot.PickKawesh code is wrong per speaker | **High** |
| Q6 | Disambig from bid-takweesh | **High** |
| Q7 | Disambig from K.MSG_TAKWEESH | **High** (same call layer, different trigger taxonomy) |
| Q8 | Cross-check #34 (full coverage) + #36 (orthogonal) | **High** |

---

## Verification verdict on B-Bot-10-5

**B-Bot-10-5 is CONFIRMED.** `Bot.PickKawesh` (Bot.lua:3801–3806) is
**unconditional** when `IsKaweshHand(hand)` returns true and phase is
`K.PHASE_DEAL1`. Per video #29 (cue 5: "الافضل انك ما تكوش الا في حاله
واحده") and video #34 (cue 224–229: "في حاله خويك شاله حكم هذي ما انصحك
تكوش ابدا"), this unconditional behavior **violates** the partner-Hokm-NEVER-
kasho discipline (H-34.9) and the partner-Sun-default-suppress discipline
(H-29.2 / H-34.6).

**Repro scenario (per B-Bot-10-5):**
1. Round 1, seat 1 (bot, advanced) is dealt 7♠ 8♠ 9♠ 7♥ 8♥ (kasho-shape).
2. Partner (seat 3) is to-bid earlier than seat 1 and bid Hokm-trump=♠ first.
3. Seat 1 reaches its bid turn. `Bot.PickKawesh(1)` returns `true` because
   `IsKaweshHand(hand1)` is true.
4. Bot calls Kawesh, deal annuls, **partner's Hokm bid is wiped along with it**.

This is exactly the failure mode described by both speakers (#29 cue 11–13:
"خربت عليه" / "you destroyed it on him"; "تخرب على خويك مشروع" / "you
destroy your partner's project") and contradicts the explicit advice.

**Severity assessment (unchanged):** LOW — bot still produces a legal call,
partner's loss is bounded by the redeal-no-points outcome (kasho yields zero
points and zero meld credit per H-30.7 / H-34.1). But the strategic damage
**eliminates a partner contract that would otherwise have scored**, which is
the core of the speaker's complaint at cue 11–13. The fix is a one-liner gate
on `S.s.bids[partner]` for partner-bought-anything-but-narrow-exception.

---

## Disambiguation flag (extraction-quality issue)

The previously-written extraction
`C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\29_dont_takweesh_extracted.md`
**mis-classifies** video #29 as "Takweesh-A bid-override" when the actual
content is "Takweesh-B kasho suppression". The mis-classification is visible
at lines 11–35 of that extraction (the "Terminology disambiguation" section),
which incorrectly reads `ورق تكويش` (cue 19) as defining a NEW bid-override
sense distinct from the kasho-call sense.

**Why the mis-classification is wrong:**
- Cue 1's question is "do you kasho **or let partner complete his Hokm**"
  (`ولا تخلي خويك يكمل حكمه`) — "complete his Hokm" only makes sense vs. an
  annulment, not vs. a bid-override.
- Cue 19's "خويك ما يعرف انه عندك ورق تكويش" ("partner doesn't know you have
  takweesh cards") is the asymmetric-blame argument, which only makes sense
  if the alternative action is **invisible** to partner (kasho-suppression);
  bid-overrides are public so "partner doesn't know" is incoherent.
- Cue 1's hand-label `ورق كوشه` is the canonical 5×{7,8,9} kasho-eligible
  hand label per #34 H-34.3, not a "strong takweesh-worthy" hand.

**Recommended downstream action (NOT executed here per task scope, but
flagged):** the `29_dont_takweesh_extracted.md` "Section 1 — Decision rules"
table should be re-keyed from `Bot.PickBid` / `Bot.PickAshkal` to
`Bot.PickKawesh`. The `Bot.PickAshkal` cross-link in that extraction is a
red herring — Ashkal (per H-27.7 / H-27.8) is a third/fourth-seat bid-phase
mechanic, completely separate from the kasho-suppression discipline.

---

## Source paths

- **Re-extracted SRT:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\ePJkUJu8kfg_29_dont_takweesh.ar-orig.srt`
- **Re-extracted plain text:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\ePJkUJu8kfg_29_dont_takweesh.ar-orig.txt`
- **Cross-check #34 SRT:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\p0svUm6THvA_34_takweesh_basics.ar-orig.srt`
- **Cross-check #36 SRT:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\IEdE-FMXQ00_36_qaid_all.ar-orig.srt`
- **Phase 1 source under review:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_H_bidding_penalty.md` (sections H-29.1 through H-29.6 and H-34.9)
- **Mis-classified prior extraction:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\29_dont_takweesh_extracted.md`
- **Bot code under audit:** `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 3801–3806 (`Bot.PickKawesh`)
- **B-Bot-10-5 finding:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Bot-10_pickSWA_pickKawesh.md` lines 329–397
