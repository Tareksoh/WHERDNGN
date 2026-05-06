# B-Rules-03: `R.DetectMelds` review (v0.10.2, post-X5/R5)

**Scope:** `R.DetectMelds` in `Rules.lua` lines 220-290 (constant + carré branch). Comparison melds against `R.CompareMelds` (lines 292-353) and Belote handling in `R.ScoreRound` (lines 684-746) for cross-cutting questions. Cross-checked against:
- Video #32 transcript `oEJjzIlMPeQ_32_melds_detailed.ar-orig.txt` (lines 22-130, 195-247).
- Video #38 transcript `9hJEA_McqOA_38_melds_intro.ar-orig.txt` (lines 9-67).
- PDF "نظام لعبة البلوت األساسي" → `02_playing_system.txt` lines 94-141.
- `tests/test_rules.lua` Section E (lines 321-388).

---

## Summary verdict

**`R.DetectMelds` itself is correct post-X5/R5.** Sequences, suit-confinement, K.RANK_INDEX ordering, Carré rank gating via `K.CARRE_RANKS`, contract-aware Carré-A value, and the X5 `else` branch all match the canonical Saudi sources. Belote is intentionally **not** emitted by `DetectMelds` — it's separately detected at scoring time in `R.ScoreRound` from played-card history, which is the right architecture but its **declaration semantics diverge from canonical Saudi convention** (see Finding F-04).

**However**, an important consistency bug exists in a sibling code path: `S.ApplyMeld` in `State.lua:1149-1189` was NOT updated alongside the X5 fix and still drops the Hokm Carré-A meld silently. Detailed in Finding F-01.

---

## Findings

### F-01 — `S.ApplyMeld` cascade: X5 fix is INCOMPLETE (HIGH severity)

**File:** `C:\CLAUDE\WHEREDNGN\State.lua:1171-1183`

**Bug:** `S.ApplyMeld` (the wire-side meld applier called by `Net._OnMeld` at `Net.lua:1372` and the bot self-meld path at `Bot.lua:3436` / `Bot.lua:4079`) computes `value` for carrés like this:

```lua
elseif kind == "carre" then
    if K.CARRE_RANKS[top] then
        if top == "A" then
            if s.contract and s.contract.type == K.BID_SUN then
                value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
            end
            -- Hokm 4-Aces: doesn't score (per Pagat-strict)  -- ← STALE COMMENT
        else
            value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
        end
    end
end
if not value then return end
```

In Hokm with `top == "A"`, neither inner `if` matches, `value` stays `nil`, and the guard `if not value then return end` at line 1184 silently drops the meld — exactly the symptom that v0.10.0 X5 fixed in `R.DetectMelds`. The stale comment "Hokm 4-Aces: doesn't score (per Pagat-strict)" even contradicts the X5 fix's rationale.

**Cascade impact (mirrors original X5 cascade described at `Rules.lua:260-267`):**
- `Net._OnMeld → S.ApplyMeld`: any wire frame announcing a Hokm carré-A vanishes silently. The four-Aces-in-Hokm holder can never get +100 onto the wire.
- `Bot.lua:3436` and `Bot.lua:4079` (bot auto-meld loops): `R.DetectMelds` emits a `kind="carre", top="A", value=100` (correct post-X5), `N.SendMeld` ships it, the host's `_OnMeld → ApplyMeld` swallows it. Bots with four Aces in Hokm score 0 instead of 100.
- Local declarations via UI: `Bot.lua:2377` calls `S.ApplyMeld` directly before `N.SendMeld`. The local seat's own `meldsByTeam` never receives the carré-A meld.
- `R.ScoreRound`'s Belote-cancellation predicate at `Rules.lua:738-746` walks `meldsByTeam[belote]`. If the Hokm carré-A holder also holds K+Q of trump, the carré never makes it into `meldsByTeam`, the cancellation check finds no `m.value >= 100`, Belote stands. **Net effect: silent +20 over-scoring on the Belote bonus** — the exact secondary cascade that motivated the X5 fix in the first place.

**Repro vector:** A bot deals into a Hokm contract holding all four Aces. With `R.DetectMelds` correctly emitting 100, `Bot.PickMelds` returns it, `N.SendMeld` broadcasts it, the host's `S.ApplyMeld` drops it. No log line. No error. No score.

**Verdict:** The X5 patch was applied to `R.DetectMelds` only. `S.ApplyMeld` is the authoritative writer into `meldsByTeam` and reproduces the same bug.

**Confidence:** High. Direct read of both code paths plus the routing in `Net.lua:1372`, `Bot.lua:2377`, `Bot.lua:3436`, `Bot.lua:4079`. No tests exercise the wire path for Hokm carré-A — Section E tests only the detection function.

**Severity:** **HIGH** — silent meld loss + silent Belote over-scoring. Identical class to the original X5 cascade.

---

### F-02 — Sequence detection: CORRECT (no severity)

**File:** `Rules.lua:224-252`

Per video #32 lines 22-26, 56-65, 67-73 and video #38 lines 41-58 and PDF page 2 lines 94-101:
- Tierce / سرى = 3 consecutive same-suit cards = 20.
- Quarte / خمسين = 4 consecutive same-suit = 50.
- Quinte / مئة (sequence) = 5 consecutive same-suit = 100.
- 6/7/8-card runs are still scored as 100 ("ميه عادي") with the showing-rule of laying down only the top 5 (video #32 lines 73-83). The code emits ONE seq5 with `len=runLen` and `top` = highest card; this is correct because `bestMeld` and `meldRank` already use `top` for tie-break, and the 5-card slice is implicit in valuation.

Suit-confinement is enforced by the per-suit `bySuit[s]` partition at lines 225-230. Rank ordering follows `K.RANK_INDEX` 7=1 → A=8 (`Constants.lua:13`), which matches video #32 line 15 ("اكه شايب بنت ولد عشره تسعه ثمانيه سبعه" — A K Q J T 9 8 7) and explicitly deviates from Sun's trick-rank order (video #32 lines 17-19, 41-43). The code's use of natural-rank for sequences and trick-rank for trick winners is the correct Saudi reading.

**7-8-9-T-J = 5-seq edge case:** Yes, this is detected as `seq5` value=100. Test at `tests/test_rules.lua:336-342` covers exactly this hand. Matches video #38 line 47 ("شاي بنت ولد عشره تسعه خمسه اوراق ميه" — five-card sequence including 7).

**Confidence:** High.

---

### F-03 — سيكل (sykl, 9-8-7) tierce: CORRECT (no severity)

**File:** `Rules.lua:242` (`runLen == 3 → kind="seq3", value=K.MELD_SEQ3=20`).

Video #32 lines 263-269 and video #38 lines 56-59 both note that 9-8-7 has the slang name "سيكل" (sykl) but is **the same value as any other tierce** — 20 raw. The PDF page 2 line 96 ("أكبر سرى هو سرى الكه وأصغرها سرى التسعة" — biggest tierce is the A-tierce, smallest is the 9-tierce) confirms 9-tierce IS a tierce, just lowest-ranked.

Code emits a plain `seq3` with `top="9"` and value=20. The naming is purely cosmetic — no special handling required. `meldRank` correctly ranks higher tierces above the 9-tierce by `topIdx`. Test at `tests/test_rules.lua:323-333` covers a T-J-Q tierce; no specific 9-8-7 test exists but the run detector treats it identically.

**Verdict:** Correct. The Arabic name "sykl" is a folk label, not a separate meld type.

**Confidence:** High.

---

### F-04 — Carré detection: CORRECT post-X5/R5 (no severity)

**File:** `Rules.lua:268-287`

- Rank gating via `K.CARRE_RANKS = { A=true, T=true, K=true, Q=true, J=true }` at `Constants.lua:109`. 9 / 8 / 7 carrés never score — confirmed by video #38 lines 19-22 ("اربع تسعات … اربع ثمانيات … اربع سبعات برضو ما يعتبر المش") and tested at `tests/test_rules.lua:382-388`.
- T / K / Q / J: value=`K.MELD_CARRE_OTHER`=100. Confirmed by video #32 lines 89-101 and video #38 lines 13-19. Tested at lines 344-354.
- A in Sun: value=`K.MELD_CARRE_A_SUN`=400 (post-R5 raw direct). Confirmed by video #32 lines 117-126 ("اكبر مشروع في اللعبه اللي هو 400 الاربعميه"), video #38 lines 13-16, PDF page 2 line 106 ("اما الربع مئة فهي الربع اكك" — Four-Hundred is four Aces). Tested at lines 356-363.
- A in Hokm: value=`K.MELD_CARRE_OTHER`=100 (post-X5 `else` branch). Confirmed by video #32 lines 121-124 ("في الحكم لو جاتك اربع عكك تعتبر ميه تعامل معامله المياه" — in Hokm, four Aces is a hundred, treated like any other hundred), video #38 lines 28-32. Tested at lines 365-380.

The `K.MELD_CARRE_A_SUN = 400` value in `Constants.lua:95` is the raw direct value (no later ×2 multiplier on top of an internal 200 — the R5 fix collapsed that). `R.SumMeldValue` will sum it raw and `R.ScoreRound` lines 730-746 use raw `m.value` for cancellation comparison; both paths consume the 400 figure directly.

**Confidence:** High.

---

### F-05 — Carré-A in Hokm cancels Belote: CORRECT (no severity)

**File:** `Rules.lua:738-746` (cancellation check), reading from `meldsByTeam`.

Post-X5 `R.DetectMelds` emits the Hokm carré-A with `value=100`. The cancellation walk at line 741 (`if (m.value or 0) >= 100`) catches it. **Provided** the meld actually reaches `meldsByTeam` — which it does in two paths:

1. **Bot host-side direct mutation:** Tests typically construct `meldsByTeam` directly and the score path never goes through `S.ApplyMeld`. Tests pass.
2. **Wire-routed declaration (real game):** `R.DetectMelds → Bot.PickMelds → N.SendMeld → N._OnMeld → S.ApplyMeld → meldsByTeam`. Here Finding F-01's `S.ApplyMeld` bug intercepts: the meld is dropped, `meldsByTeam` never sees the carré-A, the cancellation walk finds nothing, **Belote is NOT cancelled**, and Saudi rule "100-meld subsumes Belote" silently fails for the hokm-carré-A case.

So: the *intent* of X5 is met inside `R.ScoreRound`, but Finding F-01 means the cancellation only triggers in unit-tested direct-mutation scenarios, not in real wire play. The X5 cascade is patched in the detection function but reopens at the persistence boundary.

**Confidence:** High.

**Severity if standalone:** OK in `R.ScoreRound`. Effective severity is bundled into F-01.

---

### F-06 — Edge case: 5-seq AND Carré of one of those ranks (LOW severity, by design)

**File:** `Rules.lua:220-289`

Example hand: J♠ T♠ 9♠ 8♠ 7♠ + J♥ J♦ J♣ + (any 8th card).

`R.DetectMelds` emits BOTH:
- `seq5` of spades, top=J, value=100 (lines 244-248, runLen=5).
- `carre` of J, value=100 (lines 273-286).

Both go into `out`. `R.SumMeldValue` will sum them = **200** for that team. Compared to the Saudi convention as documented in video #32 lines 81-87 ("نزل اكبر خمسه اوراق فقط عشان لا يتقيد عليك" — only lay down the top five so you don't get penalized), this is the addon's deliberate auto-detect-everything stance. Code's `R.ScoreRound` does sum both team melds via `R.SumMeldValue` at line 680-681.

This double-counts in the **raw sum**, but `R.CompareMelds` only consults the *best* meld via `bestMeld` (line 343-353), so for the strict-majority threshold and for the meld-tier-winner determination, only the highest-value meld matters and double-counting doesn't tilt that comparison.

However, in `R.ScoreRound` the meld VALUE that gets booked to the winning team's score is `meldA` / `meldB` from `R.SumMeldValue` (line 680, summing ALL emitted melds for the comparison-winning team). So a J-quinte+J-carré team gets +200 booked, where Saudi convention gives them only +100 (the higher of the two; or per video #32 lines 215-228 the player picks one when they conflict — typically the carré).

**Saudi-canonical reading from video #32 lines 215-228:** when the same physical card appears in two melds (e.g. K is both the sequence-top and a carré member), the player must announce one. The code doesn't enforce that the J in J-carré is "consumed" by the J in J-spades-quinte — both melds emit independently because Detection works rank-only for carrés and suit-only for sequences.

The PDF page 2 line 110-119 ("مالحظة مهمة عند ذكر سرى من الفريقين فاليحق لالعب التالي الفصاح عن سراه" — players from same team must announce only the highest meld) reinforces that human players self-select; the addon's auto-detection bypasses this.

**Verdict:** **Possible over-scoring** in pathological hands. Concretely it requires holding all 4 Js + 4 spades 7-J — a 12-card subset of an 8-card hand, which is mathematically impossible because each J is one of 4 cards in the rank, and a J-spades is in BOTH the 4-card carré-J set and the J-T-9-8-7-spades sequence. So the *J specifically* always overlaps in this construction. This means the over-scoring case is unavoidable when the "best" carré rank coincides with a 5-seq end card.

A realistic 8-card hand: J♠ T♠ 9♠ 8♠ 7♠ J♥ J♦ J♣ — 8 cards, both melds, J-of-spades shared.

**Confidence:** Medium-high on the over-scoring claim. Cross-track reviewers may want to either (a) deduplicate at detection (subtract the lower meld whenever a card appears in both) or (b) document this as an intentional Saudi-house variant. Decision belongs to the strategy/rules track, not to detection.

**Severity:** **LOW** — affects a constructible 8-card pattern, score swing of up to 100 raw. Ought to be confirmed as either intentional or worth a separate ticket.

---

### F-07 — Belote detection: NOT in `DetectMelds`, separately scored (no severity, but timing concern)

**File:** Belote detection lives at `Rules.lua:692-709`, scored at lines 758-766 and again at 908-911 (raw application after multiplier).

`R.DetectMelds` correctly emits no Belote — it's not a "meld" in the comparison sense (it's a +20 raw bonus, multiplier-immune per `Rules.lua:898-911` and `CLAUDE.md` "Belote (K+Q of trump, +20) is multiplier-immune").

Detection method: scan ALL tricks at round-end for the trump K and trump Q played-by seats; if same seat, that team gets Belote. This means **the addon auto-detects Belote retroactively from the trick history**, not from any player-side declaration.

**Saudi convention (video #32 lines 192-204):** Belote is announced verbally:
- At the time the player plays the SECOND of K/Q (typically the K — line 200 "لما تجي تلعب الشايب تقول بلوت").
- Or at scoring time (line 202-204 "بعد ما تخلصوا الحلات كلها والاكلات … تقول معايا بلوت").

Critically, line 192-194 says: "البلوت ما ينقال الا لما تلعب ثاني ورقه" — Belote can ONLY be declared when the second card is played. Declaring it at trick 1 is a Qaid (penalty).

**Code reality:** The addon never asks any player to declare Belote. It auto-credits at scoring. This is **functionally equivalent** to "always declared at scoring time" (which Saudi convention permits per line 202-204) but has these implications:
- A player cannot voluntarily skip Belote (no incentive case exists in the code, but per Saudi convention it's the player's option not to declare).
- A player cannot Qaid by mis-timing (the addon eliminates that failure mode entirely).
- The +20 is awarded based on which seat played the K and Q — **not** based on which seat HELD them. If the K-Q-of-trump holder gets force-played (must-overcut, must-trump rules), code attributes Belote to whoever's seat played the cards. Since must-trump only applies to your own hand, the K and Q can only be played by their holder, so this collapses to "same hand owned both" which is the canonical rule. Safe.

**Verdict:** Functionally correct for scoring, but the canonical Saudi declaration timing (verbal at trick 2 / second-K-or-Q) is **not represented**. This is a UX / convention divergence, not a math bug. Documented in `CLAUDE.md` and prior reviews as an intentional simplification. Per `review_v0.10.0/REVIEW.md:307` and the X5 cross-ref doc, auto-detect-at-scoring matches what Saudi tournaments treat as the practical fall-back.

**Confidence:** High.

**Severity:** None (intentional simplification).

---

### F-08 — Meld duplication: K-Q-J-T (4-seq) AND J-carré (LOW severity, by design)

**File:** `Rules.lua:220-289`

Hand: K♠ Q♠ J♠ T♠ + J♥ J♦ J♣ + 1 extra.

`R.DetectMelds` emits BOTH:
- `seq4` of spades, top=K, len=4, value=50.
- `carre` of J, top=J, value=100.

Both go to `out`. `R.SumMeldValue` total = 150.

`R.CompareMelds → bestMeld → meldRank`:
- Carré J: 1000 + 100 + (rankBonus from trick rank of J trump) = ~1100.
- Seq4 K: 4*10 + 7 + (trump bonus 0.5 if spades is trump) = ~47-48.
Carré wins comparison. Effective meld booked to winner is from `R.SumMeldValue` (line 680) which is the team's full sum — both melds count.

So a winning team booking 150, where strict Saudi (video #32 lines 215-228) would have the player nominate a single best meld and announce only that. Same pattern as F-06 — independent emissions sum correctly per the addon's auto-detect contract but exceed strict-Saudi single-nominate scoring.

**Verdict:** Same call as F-06: either intentional house variant or documentation gap. No new bug.

**Confidence:** Medium.

**Severity:** **LOW**.

---

### F-09 — Sun Belote (ملكي): correctly OMITTED (no severity)

**File:** `Rules.lua:694` (`if contract.type == K.BID_HOKM and contract.trump then`).

Sun Belote / "سراء ملكي" is gated to Hokm only by the contract-type check at the top of the Belote scan. In Sun the entire detection block is skipped. Confirmed by `xref_X5_meld_coverage.md:32` and `review_v0.10.0/REVIEW.md:307`. Sources for why: Saudi convention does not pay K+Q-meld in Sun — the Sun bidder's bonus structure doesn't include Belote (PDF page 2 lines 127-141 describes Belote with explicit reference to "بنت وشايب الحكم" = J and Q of HOKM — not Sun).

The Bot.lua references at lines 835 and 1221 to "سراء ملكي" use the term as Saudi slang for "K+Q meld" in the context of bidding heuristics and bonuses — those are bidding-side incentives, not scoring-side credits. The scoring side correctly does NOT pay this in Sun.

**Verdict:** Correct. Confirmed.

**Confidence:** High.

---

## Cross-cutting observation

**The `R.DetectMelds` ↔ `S.ApplyMeld` value-derivation drift (F-01) is a structural risk.** Both functions independently compute the same meld values. The `S.ApplyMeld` comment block at `State.lua:1164-1167` even acknowledges "Mirror R.DetectMelds value derivation" — the mirror is now broken. Suggested fix lane (out of scope here): centralize meld-value derivation into a small helper like `R.MeldValue(kind, top, contract)` and have both `DetectMelds` and `ApplyMeld` call it. This isn't required to fix the bug (a literal port of the X5 `else` branch into `S.ApplyMeld` works), but it would prevent the next divergence.

---

## Coverage gap (test recommendation, no severity ranking)

`tests/test_rules.lua` Section E covers `R.DetectMelds` thoroughly but does NOT exercise the wire round-trip via `S.ApplyMeld`. A test that hands a Hokm carré-A through `S.ApplyMeld` and asserts `s.meldsByTeam.A` contains the meld would have caught F-01. Recommend a Section adjacent to E that tests `S.ApplyMeld` value derivation against the same hand fixtures.

---

## Verdict

- `R.DetectMelds`: **CORRECT** post-X5/R5 fixes. Sequence, carré, and contract-aware Carré-A all match canonical Saudi sources (videos #32, #38, PDF 02).
- The X5 fix is **NOT yet propagated** to `S.ApplyMeld` (Finding F-01) — high-severity wire-side regression of the same X5 cascade.
- Belote is correctly outside `DetectMelds` and correctly Hokm-only.
- Sun Belote (ملكي) is correctly absent.
- Two low-severity over-scoring patterns (F-06, F-08) when overlapping melds emit independently — likely intentional house variant, but worth a confirmation ticket.

**Overall confidence: High** on the core scope; **Medium-high** on F-06/F-08 because the Saudi sources are explicit about player-nomination but silent on auto-detection systems' obligations.
