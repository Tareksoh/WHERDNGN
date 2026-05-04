# 33_melds_and_qaid — extracted rules

**Source:** https://www.youtube.com/watch?v=IV8CpRfq7pk
**Title (Arabic):** المشاريع والقيد في البلوت (Melds + Qaid in Baloot)
**Topic:** Five Q&A on the meld–Qaid interaction: who scores opponent's melds on Qaid, sequence-laying order, double-meld laying, undeclared meld, and declared-but-unlaid meld.

---

## 1. New / refined glossary terms

| Arabic | Pronunciation | Meaning | Code touchpoint |
|---|---|---|---|
| مجموعة اللعب | majmooʕat al-laʕb | "round total" — sum of trick points (raw) plus melds for the round (e.g., 26 in Sun, 30 with a sirah). Used to argue whether Qaid score should equal the would-be total. | `R.ScoreRound` flat-Qaid path |
| الخسارة | al-khasaarah | "the loss" — points the bidder team forfeits by losing the round on points. **Speaker explicitly distinguishes Qaid ≠ khasaarah** — Qaid is a procedural penalty, not a point-loss. | (rule-rationale only) |
| لعب مشدود / لعب عسكري / صالم | laʕb mashdood / ʕaskari / saalim | "tight / military / strict play" — strict-rules table mode where every breach = Qaid. Opposite of حبي (friendly). | bot meta-policy: strict-mode = always Qaid, friendly-mode = relaxed |
| لعب حبي | laʕb hubbi | "friendly play" — relaxed-rules table mode; small breaches (e.g., un-laid sirah) walked, larger ones (50/100) still Qaid'd. | bot meta-policy |
| النازل | an-naazil | "the descending one" — first non-dealer to act; tiebreak winner on equal-strength melds (per #32). Reused here to resolve tied-50 dispute. | `R.DetectMelds` tiebreak |
| فضحت نفسك | fadahta nafsak | "you exposed yourself" — verbalizing an undeclared meld during play turns a no-Qaid scenario into a Qaid'able one. | call-validity gate |
| توضيح لعب | tawdeeh laʕb | "play-clarification" — speaking about your hand mid-round (telling partner what you held). Always Qaid'able in strict play. | (informational; meta-policy) |
| الجلسة / الجلسات | al-jalsah / al-jalasaat | "the session / the sessions" — house rules; final arbiter on disputed cases. Same usage as #36. | informational |

---

## 2. Bidding rules

*No bidding rules in this video.*

---

## 3. Trick-play / signal rules

| WHEN | RULE | SOURCE |
|---|---|---|
| Strict (mashdood/ʕaskari) play, you declared a meld in trick 1 | You **must lay it** in trick 2 in proper sequence-order; failure = Qaid. | 33 |
| Friendly (hubbi) play, you declared a sirah (SEQ3) but forgot to lay it | Often walked (no Qaid). 50/100 melds still Qaid'd even in friendly play. | 33 |
| You declared "50" but actually have no valid meld (mistake/lie); opponent has higher meld (e.g., 100) | **No Qaid risk** — opponent's higher meld lays down; yours never gets shown; you escape automatically. | 33 |
| You declared "50"; opponent also declared "50" and asks "إيش خمسينتك" ("which 50 is yours?") | **Best practice:** answer with the **lowest possible 50** (T-9-8-7 — "خمسينتي عشرة"). Opponent likely concedes since they expect to win the tiebreak. Avoid admitting "غلط" (mistake) unless forced — admitting = Qaid risk. | 33 |
| Same scenario, but opponent also has the lowest 50 (T-9-8-7); you are An-Nazil (act first) | **An-Nazil tiebreak makes you win** if equal — but you'd then be obliged to lay, and your meld is fake → forced to admit "غلط" → Qaid risk. **Some tables walk this; most strict tables Qaid.** | 33 |
| You hold an undeclared meld (e.g., sirah) and never mentioned it | **No Qaid** — opponent has no way to know. The unlaid meld simply doesn't score. | 33 |
| Same as above, but mid-round you blurt "والله كان عندي مية" ("I had a 100") | **Qaid is now valid** ("فضحت نفسك" / play-clarification). Strict play = always Qaid; friendly play = still Qaid because of tawdeeh laʕb. | 33 |
| You hold two melds covering all 8 cards (e.g., SEQ5 + SEQ3, or 400 + Carré-100) | Speaker's view: **lay both**, no rule against it. Some tables prefer "lay one only" to avoid full-hand reveal — house-dependent. | 33 |

---

## 4. Decision-tree rules (WHEN / RULE / WHY / MAPS-TO / CONFIDENCE / SOURCES)

### Section: Meld–Qaid interaction (the central question of this video)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Qaid is valid AND the **Qaid'd team had a meld** | **Two valid camps exist:** (a) caller's team takes opponent's melds (so total = round total, e.g., 30 instead of 26 in Sun-with-sirah); (b) caller's team scores only the flat Qaid (26 Sun / 16 Hokm) and opponent's melds simply forfeit. **Speaker's preference: camp (b)** — Qaid is a procedural penalty, not equivalent to losing the round on points (الخسارة ≠ القيد). | Camp (a) reasoning: round total must always be split between teams. Camp (b) rebuttal: round total is not fixed (changes with Kaboot 44, with bidder's own melds, with mis-declared melds), so "split-the-total" axiom is false. | `R.ScoreRound` Qaid path: **default to camp (b)** (flat 16/26 + caller's melds; opponent's melds zeroed but NOT given to caller). Add config flag `R.QAID_TAKES_OPP_MELDS` for camp (a) houses. `(not yet wired)` | Common (single source explicit; #36 stated forfeit-but-not-transfer, this video debates the transfer) | 33 |
| Same scenario but the round was Kaboot (44 raw bonus) | **Both camps agree:** caller does NOT take opponent's melds. Camp (a) breaks down here — speaker uses this as the proof that opponent's melds aren't always transferred. | If even camp (a) refuses to transfer melds in Kaboot, the "round total must split" axiom is internally inconsistent. Validates camp (b) as the cleaner rule. | Same as above; this is the corner case proving camp (b) correctness. | Definite | 33 |
| You declared a meld and want to lay it in trick 2 (strict play) | **Must lay in sequence-order** — for a SEQ4 (Walad-T-9-8): J first, then T, then 9, then 8. For a Carré-100 of figures: alternate suits (red-black-red-black or vice versa) per the convention. Out-of-order laying = Qaid risk in strict tables. | Procedural standard; protects against ambiguous claims. | `R.DetectMelds` should ANNOTATE expected lay order; `Bot.PickMelds` (when wired) must lay accordingly. | Common | 33 |
| Friendly (hubbi) play, you mis-laid sequence order on a sirah | **Usually walked** — lowest meld, low stakes. But 50 and 100 still Qaid'd even in friendly games. | Severity scaling: bigger meld = stricter enforcement. | Bot meta-policy: in friendly mode, suppress Qaid call for SEQ3 mis-laying only. | Common | 33 |
| You hold meld but never declared it; round plays out | **No Qaid** — opponent cannot prove what's hidden. You simply lose the meld points (don't score). | Information rule: a hidden meld is a non-event from the table's perspective. | `R.ScoreRound`: undeclared melds award 0; no penalty path. **Already correct in code** (melds only score if claimed). | Definite | 33 |
| You hold meld, never declared it, but **mid-round you verbally reveal it** | **Qaid is now valid** under "fadahta nafsak / tawdeeh laʕb" — exposing yourself is a procedural breach. | Speaking about hand-content is a separate offense even from non-declaration. | `Net.lua`: no auto-detect; player-initiated only. Bot meta-policy: bots NEVER speak about their hand mid-round. | Definite | 33 |
| You declared a meld and forgot to lay it in trick 2 (strict play, ANY meld size) | **Qaid valid** — declared-but-unlaid is the canonical undeclared-meld inverse. | Symmetry with #36's "declared 100 but didn't show" trigger. | `R.DetectMelds` + scoring path: enforce lay-by-trick-2 deadline; missed = `K.MSG_TAKWEESH_OUT` trigger. `(not yet wired)` | Definite | 33 + 36 |
| You declared a fake/mistaken meld; opponent also declared the same meld type at equal strength; opponent challenges ("which is yours?") | **Lie down** — claim the **lowest variant** of that meld type to push the opponent to lay first (since they expect to win). If opponent is also at the lowest variant AND you are An-Nazil, you cannot escape — admit and accept Qaid OR hope for friendly-table walk. | Game-theoretic dodge: opponent assumes their meld wins and lays without further check. | `Bot.PickMelds` defensive sub-routine for mis-declared melds; very rare path. **Bots should never declare fake melds** so this branch is mostly defensive (anti-exploit by humans). | Common | 33 |
| You hold two melds covering all 8 cards (full-hand reveal) | **Speaker's view: lay both.** No rule prohibits it. Some house-rules prefer single-meld lay to avoid full-hand exposure. | Information-leakage trade-off: full reveal hands strategy info to opponents. House-rule decides. | `Bot.PickMelds`: prefer the higher-scoring meld alone if cumulative-meld-points are equal under either choice; lay both when total ≠. | Sometimes | 33 |

---

## 5. Non-rule observations

**Meld-Qaid interaction rules** — five specific Qaid scenarios involving melds:
1. **Declared-but-unlaid meld** (forgot to فرش in trick 2) → Qaid valid in strict play; sirah may walk in friendly play.
2. **Undeclared meld** held silently → no Qaid (no proof).
3. **Verbal slip mid-round** revealing an undeclared meld → Qaid valid (fadahta nafsak).
4. **Mis-declared meld** (claimed 50, didn't really have one) → Qaid valid only if opponent challenges and you're forced to lay; dodgeable by claiming lowest variant of the type.
5. **Two melds covering full hand** → not a Qaid trigger; lay-both is permitted (house-rule may prefer single).

**Meld-claim discipline** — speaker confirms #32's strict timing (announce in trick 1, lay in trick 2) and adds: **mis-laying sequence order = Qaid in strict play**. SEQ4 must lay J→T→9→8 (high to low along meld-rank); Carré-100 of figures lays alternating colors. The **3–5 second display window** from #32 is implicit (not restated). The cardinal new addition is **"fadahta nafsak"** — verbally exposing your held meld mid-round is itself a Qaid'able offense, *separate* from the declare/lay rules.

**Cross-check vs videos #32 + #36:**
- **Corroborates #32** — declaration timing, sequence-order lay, An-Nazil tiebreak, lay-both-on-trick-2.
- **Corroborates #36** — declared-without-laying = explicit Qaid trigger; jalasaat-dependence for ambiguous cases; flat-score Qaid path.
- **Adds beyond #32 + #36** — the **Qaid-takes-opponent-melds-or-not** debate is novel here (camps a/b). #36 stated "Qaid'd team's melds are forfeit" but did NOT clarify whether forfeit = transfer-to-caller or simply zeroed. This video resolves it: **most likely zeroed, NOT transferred**. Kaboot proof point is decisive.
- **Refutes #36 implicit assumption?** — #36 wrote "Caller's team **adds their own melds** to the qaid score" + "Qaid'd team's melds are **forfeit**". This video confirms the "add own melds" half (camp b agrees) but explicitly debates whether "forfeit" includes transfer. **Speaker's verdict: forfeit ≠ transfer.** No hard contradiction with #36, but the docs should clarify.
- **No contradictions on Hokm/Sun flat-score values** (16/26) — speaker doesn't restate them but uses an example with Sun-26 + sirah-30 implicitly accepting #36's numbers.

**Score-impact** — declaring vs not declaring a meld changes Qaid behavior:
- **Caller's own meld**: declared & laid → adds to Qaid score. Undeclared → lost (no add).
- **Opponent's (Qaid'd team's) meld**: declared & laid → forfeit (zeroed) per camp (b); under camp (a) → transferred to caller. Undeclared → never scored anyway, no impact.
- **Recommendation for `R.ScoreRound`**: implement camp (b) as default (`opp_melds_on_qaid = 0`); expose `K.QAID_TRANSFERS_OPP_MELDS = false` constant for house-rule toggle. Caller's own melds always add (`+ meldsForTeam(callerTeam)`). Multiplier (×2 Bel, ×3 Bel-x2) applies to flat-score AND caller's melds, per #36.

**Meta-policy note** — the speaker repeats #36's central thesis: most edge cases resolve by `الجلسة` (house rules). Bot meta-policy implication: **default to the conservative-strict camp (b)** for Qaid scoring (don't grab opp melds), and for Qaid *triggering*, restrict to explicit triggers (failed-follow, failed-Hokm-ruff, failed-over-cut, undeclared-meld-then-revealed, declared-but-unlaid meld). Same restraint as #36 recommends.

**Rule-correctness flags for the codebase:**
1. `R.ScoreRound` Qaid path **`(not yet wired)`** per #36 still applies. When wiring, default to camp (b) per this video's evidence.
2. `K.MELD_*` constants are correct (no value changes needed); the open question is the **transfer-or-zero** behavior on the Qaid path.
3. **No `R.CanBel`-style legality predicate** for "this meld declaration is valid in this contract" — `R.DetectMelds` already gates Belote on Hokm-only and 400 on Sun-only; no new gates from this video.
4. `Bot.PickMelds` (when wired) should **never** declare a meld it doesn't hold, and never speak about its hand mid-round. Both are explicit Qaid risks per this video.

---

## 6. Source confidence

- **Single source.** Same Q&A-format channel as #32, #36; consistent voice, internally coherent.
- **Strengths:** Direct cross-link to #32 (timing/An-Nazil) and #36 (Qaid mechanics). The Kaboot-44 corner-case argument is well-structured and rigorous. The "fadahta nafsak" addition is novel and clearly sourced.
- **Limitations:** The camp (a) vs (b) "take-opp-melds" question is acknowledged as **unresolved at the table level** — speaker's preference is camp (b) but admits both are common. **Cross-check with #38 (Sun melds 400/200) and any future video on Qaid scoring before locking the wire-up**.
- **Confidence levels:**
  - Declared-but-unlaid = Qaid: **Definite** (corroborated by #36).
  - Undeclared meld = no Qaid: **Definite**.
  - Verbal slip (fadahta nafsak) = Qaid: **Definite**.
  - Camp-(b) preference (no transfer of opp melds): **Common** (single source explicit + Kaboot proof; recommend wiring as default with toggle).
  - Mis-declared-meld dodge ("claim lowest variant"): **Common** (single source, narrow path).
  - Lay-both vs lay-one on full-hand-meld: **Sometimes** (house-rule).
