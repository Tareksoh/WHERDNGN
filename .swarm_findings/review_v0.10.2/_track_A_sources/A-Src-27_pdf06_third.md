# A-Src-27 — PDF 06 الثالث (The Third) — Pre-emption Rule Re-extraction

**Source PDF (extracted text):** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\06_third.txt`
**Original PDF:** `الثالث.pdf` (1 page)
**Slug:** `06_third`
**Re-extracted:** 2026-05-05 for v0.10.2 review (per Phase-1 source_K K-39 to K-48).
**Cross-reference:** `review_v0.10.0/_phase1_sources/source_K_pdf_basic_rules.md` rules K-39..K-48.

---

## Headline findings

| Question | Verdict | Confidence |
|---|---|---|
| Q1 Definition of "الثالث" | The "Third" = a *pre-emption right* held by an earlier-seat player to take a Sun-on-Ace contract from a later-seat buyer. Phrased as «الكة لها ثالث» — "The Ace has a Third." | High |
| Q2 Eligibility | **Seats 1 & 2 only**. Triggered ONLY when bid card (الورقة المكشوفة) = Ace AND the buy is **Sun, not Hokm**. | High |
| Q3 Never on partner | Verbatim final note: «ما لك ثالث على خويك» — "you have no Third over your partner." | High |
| Q4 Round-2 vs round-1 | Round-1: Player 1 may pre-empt Player 2 or Player 4. Round-2 (without Ace upcard): NO Third — only two bid rounds total. With Ace upcard: same Third applies in round 2 of buying. | High |
| Q5 Pre-emption mechanic | Word spoken: «قبلك» ("before you"). The pre-empter announces this to claim the contract from the later buyer. | High |
| Q6 vs Ashkal | **Different mechanic.** Ashkal = 3rd/4th-position bid that *hands Sun to partner* (`K.BID_ASHKAL`). Third = earlier seat *takes the contract from* a later buyer. Different actors, different direction. | High |
| Q7 Ground-card semantics | Bid card stays as the trick-1 lead the bidder must play; pre-emption only changes WHO the declarer is. Type stays SUN. | High (inferred from reassign-only logic + saudi-rules.md) |
| Q8 Worked example | PDF gives counter-example: «معاك ٣ اولاد والورقة المكشوفة الولد الرابع وتبغى تحكم ثاني» — 3 Jacks + Jack upcard, do NOT Hokm round 2 (trap). Not directly a Third example but illustrates round-2 Hokm-flip mechanics. | Medium (illustrative, not direct) |
| Q9 Constants.lua match | `K.PHASE_PREEMPT = "preempt"` with comment «round-2 Sun on Ace bid card: earlier seats may pre-empt (الثالث)» — **matches the PDF rule** including the round-2 + Sun + Ace gates. | High |
| Q10 Code path | `Bot.PickPreempt` (Bot.lua:3686) gates on Sun-strength threshold `K.BOT_PREEMPT_TH=75`; `Net._OnPreempt` (Net.lua:962) handles network claim; trigger in `Net._HostStepBid` (Net.lua:1535-1574) requires `bidRound==2 && type==SUN && bidRank=="A"`. **Code matches PDF.** | High |

---

## Per-question verbatim findings

### Q1 — Definition of "الثالث"

**PDF source line (≤15 words):**
> «الكة لها ثاااالث»

**English:** "The Ace has a Third [right]."

**Context:** Opening line of the PDF — the term `الثالث` is defined in usage rather than as a dictionary entry. The Third is a contractual right that *attaches to the Ace as bid card*. When the upcard turned face-up in dealing is an Ace, that Ace has — bound to it — a "Third" privilege that earlier-seat players may exercise. The privilege is to **claim the Sun contract before** ("قبلك" = "before you") a later seat who tried to buy it.

**Confidence:** High.

**Cross-ref:** Matches `Constants.lua:123` comment "round-2 Sun on Ace bid card: earlier seats may pre-empt (الثالث)" and `Constants.lua:211-218` for `K.MSG_PREEMPT` documentation: "an earlier seat (in bidding order) claims a Sun bid when the bid card is an Ace and a later seat already bought it."

---

### Q2 — Eligibility (seats 1 & 2 only? Ace only? Sun only?)

**PDF source line (≤15 words):**
> «شرط الثالث يكون لالعب الول والالعب الثاني فقط»

**English:** "The Third condition belongs only to Player 1 and Player 2."

**Sun-only restriction (PDF, ≤15 words):**
> «اذا أشتراها الالعب الثاني او الرابع حكم فليس له ثالث»

**English:** "If Player 2 or Player 4 buys it as Hokm, there's no Third [against him]."

**Ace-only restriction (PDF, ≤15 words):**
> «أما اذا كانت الورقة المكشوفة ماهي اكة ... مافي ثالث هنا»

**English:** "If the upcard is anything other than an Ace ... there's no Third here."

**Synthesis:**
- **Eligibility holders:** Seats 1 and 2 only (per K-40 reaffirmation).
- **Bid card requirement:** Must be an **Ace**. Anything else (Jack, Queen, King, etc.) — no Third, only two bid rounds total with no preemption.
- **Buy type requirement:** Buyer must declare **Sun** (صن). If buyer declared **Hokm** (حكم), no Third — because once Hokm-locked, the upcard cannot be flipped to Sun (cf. K-35 — Ace can't be flipped to Sun once Hokm'd).

**Confidence:** High. All three gates verbatim in PDF.

**Code match:** `Net.lua:1535-1538`:
```
if enablePreempt
   and S.s.bidRound == 2
   and payload.type == K.BID_SUN
   and bidRank == "A" then
```
Matches PDF gates: round-2 (post round-1 pass cycle), Sun type, Ace bid-card. Eligibility restriction (seats 1 & 2) is computed in `S.PreemptEligibleSeats` (State.lua:1873) by walking the bidding order from dealer+1 forward and stopping at the buyer — naturally only earlier-seat players appear in the list.

---

### Q3 — Never on partner

**PDF source line — final boxed note (≤15 words):**
> «ما لك ثالث على خويك»

**English:** "You have no Third over your partner."

**Context:** This is set off as a `مالحظة:` (note) at the very end of the document, after the worked Round-2 trap example. It is the load-bearing partnership exclusion: even though the PDF lists "seats 1 and 2 have Third on seat 3 / seat 4" in the body, the *partner* of the player exercising Third is excluded from the targets. So seat 1 can pre-empt seat 4 (opponent), but cannot pre-empt seat 3 (partner). Seat 2 can pre-empt seat 3 (opponent), but cannot pre-empt seat 4 (partner).

**Confidence:** Very high. Verbatim, set off as a separate note for emphasis.

**Code match:** `State.lua:1885-1888`:
```
local partnerOfBuyer = R.Partner(buyerSeat)
for _, seat in ipairs(order) do
    if seat == buyerSeat then break end
    if seat ~= partnerOfBuyer then
```
The eligibility builder excludes the buyer's partner. **Subtle correctness check:** PDF says "no Third *over* your partner" (Third-holder's partner is excluded as a target). Code excludes the *buyer's* partner. These are equivalent because of partnership symmetry: if seat 1 (Third-holder) and seat 3 (partner of 1) are partners, then seat 1 cannot Third-attack seat 3 — equivalently, seat 3 (buyer) cannot have his partner (seat 1) appear as an eligible Third-holder. ✓ Same constraint.

---

### Q4 — Round-2 vs round-1 distinction

**PDF source — round-1 mechanics (≤15 words):**
> «الالعب الول اذا قال بس بالجولة الولى والثانية وأشتراها الالعب الثاني أو الرابع صن»

**English:** "If Player 1 said pass in rounds 1 and 2, and Player 2 or Player 4 bought it Sun..."

**PDF source — round-2 mechanics (≤15 words, the round-2 Hokm-flip rule):**
> «اذا حكم الالعب الول بالجولة الثانية وماأحد أخذها صن فيحق له بان يقلب حكمه الى صن»

**English:** "If Player 1 calls Hokm in round 2 and no one [else] took it Sun, he has the right to flip his Hokm to Sun."

**PDF source — limitation on round-2 Hokm-flip (≤15 words):**
> «ولكن بمجرد مايقول غيره صن خالص راحت عليه الجولتين»

**English:** "But the moment another player says Sun, both rounds are gone for him."

**PDF source — non-Ace upcard exclusion (≤15 words):**
> «أما اذا كانت الورقة المكشوفة ماهي اكة ... مافي ثالث هنا واللعب يكون جولتين فقط»

**English:** "But if the upcard isn't an Ace ... there is no Third here, and play is only two rounds."

**Synthesis:**
- **Ace upcard** → 2 bidding rounds + Third pre-emption window. Player 1 may say "قبلك" to take Sun back from a later Sun-buyer, in either round.
- **Non-Ace upcard** → 2 bidding rounds, **no Third**. After round 2 a contract is finalized irrevocably.
- **Round-2 Hokm-to-Sun flip (related, K-46):** if Player 1 declares Hokm in round 2 and no opponent takes it as Sun, Player 1 may flip his own Hokm → Sun. Once anyone else has said Sun, this is gone.

**Confidence:** High.

**Code match:** `Net.lua:1535-1538` — preempt gates on `bidRound == 2`. ✓ Matches the round-2 Sun-on-Ace trigger. The round-2 Hokm-flip (PDF K-46) is a *separate* mechanic implemented as Sun-overcall (`K.PHASE_OVERCALL`) — see `Constants.lua:124-127`.

**Subtle finding:** PDF distinguishes between "Player 1 passed both rounds, then opponent buys Sun" (Third applies) and "Player 1 Hokm'd round 2 with no Sun takers" (Hokm-flip applies). Both are expressed in the codebase but as **two distinct phases**: `PHASE_PREEMPT` for the Third (Sun-on-Ace pre-emption) and `PHASE_OVERCALL` for the round-2 Hokm-flip.

---

### Q5 — Pre-emption mechanic (PHASE_PREEMPT)

**PDF source — the spoken word (≤15 words):**
> «نفس الكلام يحق له ياخذها قبله اذا أخذها صن فقط فيقول قبلك»

**English:** "Same applies — he may take it before [his] [opponent], if [opponent] took it Sun only, and says 'before you' (قبلك)."

**Mechanic:**
1. Bid card turns Ace.
2. Round 1 cycle completes (with Player 1 passing).
3. Round 2: a later seat (Player 2 or 4 against Player 1; Player 3 against Player 2) declares Sun.
4. Earlier eligible seat says **«قبلك»** ("before you") — the contract is reassigned to the earlier seat as a Sun bid.
5. Buyer's original Sun contract is voided. The earlier seat is now declarer at Sun, with the same upcard / bid-card as trick-1 lead.

**Confidence:** High.

**Code match:**
- `Constants.lua:123` — `K.PHASE_PREEMPT = "preempt"` with explicit comment matching the PDF gate.
- `Constants.lua:211-218` — `K.MSG_PREEMPT = "@"` payload + comment "Triple-on-Ace pre-emption (الثالث): an earlier seat (in bidding order) claims a Sun bid when the bid card is an Ace and a later seat already bought it."
- `Net.lua:1535-1574` — host opens window: when round-2 Sun-on-Ace happens, builds eligibility list, broadcasts `MSG_PREEMPT_PASS` with seat=0 + CSV of eligible seats, sets `S.s.phase = K.PHASE_PREEMPT`.
- `Net.lua:962-991` — `_OnPreempt`: receives claim, validates seat is in eligibility list, applies `S.ApplyPreempt(seat)` then re-bids at `K.BID_SUN` for the new declarer.
- `State.lua:1900-1907` — `S.ApplyPreempt`: clears existing contract, clears eligibility list, sets `S.s.phase = K.PHASE_DEAL2BID` (signals re-bid is in progress), plays Sun voice cue.

**Verdict:** Implementation matches PDF rule.

---

### Q6 — Comparison to Ashkal (different mechanic?)

**Different mechanic — but related concept (both convert Hokm-or-late buys to Sun under partnership coordination).**

| Dimension | الثالث (Third / pre-empt) | أشكال (Ashkal) |
|---|---|---|
| Who acts | Earlier seat (1 or 2) — typically opponent of buyer | Partner of Hokm-bidder (3rd/4th seat) |
| Trigger | Later seat buys SUN on Ace upcard | Hokm-bidder partner has Sun-strong hand |
| Outcome | Earlier seat *takes the contract* from the buyer | Partner *converts* bidder's Hokm-side contract to Sun (gives Sun TO partner) |
| Direction | "قبلك" (before you) — adversarial pre-emption | Partner-cooperative bid type |
| Code | `K.PHASE_PREEMPT`, `K.MSG_PREEMPT`, `Bot.PickPreempt` | `K.BID_ASHKAL = "ASHKAL"`, `K.BOT_ASHKAL_TH = 65`, Ashkal branch in `Bot.PickBid` |
| Threshold | `K.BOT_PREEMPT_TH = 75` (Sun-strength gate) | `K.BOT_ASHKAL_TH = 65` |
| Saudi term | الثالث | أشكال |

**Verdict:** **Different mechanics.** They share the *spirit* of "earlier-seat / partner-side has a route to Sun even when a later/different seat bought first" but the actor, trigger, and direction differ. They are NOT alternative names for the same rule.

**PDF text on Third:** Does NOT mention Ashkal anywhere. The PDF only addresses the Third privilege.

**Confidence:** High.

---

### Q7 — Ground-card semantics — what happens to the bid card?

**PDF text:** Does NOT directly answer this. The PDF discusses *who declares* and *what type* but is silent on bid-card lead semantics post-pre-empt.

**Inference from saudi-rules.md and code:**
The bid card (الورقة المكشوفة, the upcard turned face-up after the deal) becomes the lead card of trick 1 — the *bidder* must play it as their first lead. Saudi convention: the bidder cannot keep the upcard hidden in hand; it must be played opened on trick-1. When pre-emption reassigns the declarer to an earlier seat, the bid card stays on the trick-1 lead — but **the new declarer plays it** rather than the original buyer. (The Ace is in the new declarer's hand because the upcard is the original dealing-up card from the deck, picked into the new declarer's hand at confirm.)

**Code path verification:**
- `S.ApplyPreempt` (State.lua:1900-1907) — clears `s.contract`, sets phase back to `PHASE_DEAL2BID`. **Critical:** this does NOT itself reassign `s.bidCard` ownership — that happens in the subsequent `S.ApplyContract(seat, K.BID_SUN, nil)` call inside `Net._OnPreempt:977` and `_FinalizePreempt:1044`.
- `Net._OnPreempt:977` re-issues `K.BID_SUN` for the new declarer.

**Findings on PDF silence:** Implementation matches French Belote convention here (bid card → bidder's hand → bidder leads it on trick 1) and Saudi practice as documented elsewhere in the codebase. The PDF is silent because the rule is general bidding/dealing convention, not specific to the Third.

**Confidence:** Medium for "what happens to bid card" (inferred, not verbatim); High for "type stays SUN" (verbatim from PDF Q1+Q5 quotes — pre-empter takes it as Sun).

---

### Q8 — Worked examples (quote)

**PDF only worked example (≤15 words):**
> «مثال معاك ٣ اولاد والورقة المكشوفة الولد الرابع وتبغى تحكم ثاني»

**English:** "Example: you have 3 Jacks (الأولاد) and the upcard is the 4th Jack and you want to Hokm in round 2."

**Context:** This is the round-2 Hokm-trap example (also captured as K-47). The PDF's tactical warning — do NOT Hokm round 2 in this position because if any opponent calls Sun afterwards, you cannot reclaim it. (This is illustrative of round-2 Hokm-flip limitation, NOT of the Third pre-emption per se. The PDF body uses this as the "do-it-and-you'll-regret-it" cautionary tale.)

**PDF — pre-emption pseudo-example (within rule body, ≤15 words):**
> «الالعب الول اذا قال بس بالجولة الولى والثانية وأشتراها الالعب الثاني أو الرابع صن»

**English:** "If Player 1 said pass in rounds 1 and 2, and Player 2 or Player 4 bought it Sun..."

**Reading:** The PDF presents the Third as a rule-statement with embedded conditional examples ("if A then B may say قبلك"), not as a separate worked-example block. The only fully-worked example is the 3-Jacks Hokm trap.

**Confidence:** High that no other worked example exists in the PDF; Medium that the 3-Jacks trap example is *for the Third* (it's actually about the related Hokm-flip rule, but in the same document so PDF authors may have grouped them).

---

### Q9 — PHASE_PREEMPT implementation in Constants.lua matches PDF rule

**Constants.lua:123:**
```lua
K.PHASE_PREEMPT  = "preempt"     -- round-2 Sun on Ace bid card: earlier seats may pre-empt (الثالث)
```

**PDF gate verification:**

| Gate | PDF text | Constants.lua / Net.lua match |
|---|---|---|
| Round 2 | «وماأحد أخذها صن» / round-2 buy progression | ✓ `bidRound == 2` (Net.lua:1536) |
| Sun bid type | «اذا أخذها صن فقط» — "Sun only" | ✓ `payload.type == K.BID_SUN` (Net.lua:1537) |
| Ace bid card | «اذا كانت الورقة المكشوفة اكة» | ✓ `bidRank == "A"` (Net.lua:1538) |
| Earlier seats only | seats 1 & 2 (i.e., earlier in bid order than buyer) | ✓ `S.PreemptEligibleSeats` walks dealer+1 forward, stops at buyer (State.lua:1880-1888) |
| No partner | «ما لك ثالث على خويك» | ✓ `if seat ~= partnerOfBuyer` (State.lua:1888) |
| "قبلك" — claim message | spoken word | ✓ `K.MSG_PREEMPT = "@"` with seat payload (Constants.lua:211-218) |
| Earlier-seat may also pass | implied (if you don't claim, original buyer keeps it) | ✓ `K.MSG_PREEMPT_PASS = "%"` (Constants.lua:219), `_FinalizePreempt` (Net.lua:1038-1044) finalizes original buyer if all eligibility passes |

**Verdict:** **Matches.** All six PDF gates are encoded in the implementation.

**Subtle quirk to flag:** PDF doesn't mention any *threshold* for whether to invoke pre-emption (it's a binary right). Bot decision-side adds `K.BOT_PREEMPT_TH = 75` (Constants.lua:310) as a Sun-strength minimum for bots to actually claim — humans get the button regardless of hand. This is *bot strategy*, not rule legality. Threshold is correctly outside the rule-engine.

**Confidence:** High.

---

### Q10 — Triple-on-Ace pre-emption code path: Bot.PickPreempt + Net._OnPreempt

**Bot.PickPreempt (Bot.lua:3686-3727):**

Function logic:
1. Pull bot's hand for the eligible seat.
2. Compute `sunStrength(hand)`.
3. **+12 bonus** if bot holds Ace of bid suit (raised from +8 in 13th-bot-audit; Codex+Claude consensus rationale: Ace = ~11 points + tempo + guaranteed first-trick).
4. Partner-bid signal adjustment:
   - Partner passed: `-6` (bot partner) / `-3` (human partner — halved per Audit Tier 3 to avoid over-suppression on human overcaution)
   - Partner Sun: `+8` (Sun cover already declared)
   - Partner Hokm: `+5` (bot) / `+3` (human; halved due to higher Hokm-bid variance for humans)
5. Add `scoreUrgency(team) + matchPointUrgency(team)`.
6. Compare against `K.BOT_PREEMPT_TH = 75` ± `BEL_JITTER` (probabilistic to avoid robotic perfection).

**Verdict on Bot.PickPreempt vs PDF:** PDF doesn't speak to bot strategy. Bot logic is layered correctly: it never violates a PDF gate (eligibility is enforced in `S.PreemptEligibleSeats` and `_OnPreempt`). The bot only chooses *whether to exercise* a legally-available pre-emption.

**Net._OnPreempt (Net.lua:962-991):**

Validation steps:
1. `fromSelf(sender)` — drop self-loops.
2. `seat` parameter must be present.
3. `S.s.phase == K.PHASE_PREEMPT` — must be in pre-emption window.
4. `S.s.preemptEligible` table must exist.
5. `seat` must be in `S.s.preemptEligible` (linear scan).
6. `authorizeSeat(seat, sender)` — sender must own that seat.
7. Apply `S.ApplyPreempt(seat)` (clears contract + sets phase to PHASE_DEAL2BID).
8. Host-only: clear `pendingPreemptContract`, call `S.ApplyContract(seat, K.BID_SUN, nil)`, broadcast `N.SendContract(seat, K.BID_SUN, "")`, then check Sun-Bel allowed (the 14th-audit fix: Sun-Bel restricted to BEHIND team + bidder team past 100).

**Verdict on Net._OnPreempt vs PDF:** Network handler enforces the eligibility check (which is the PDF's "seats 1 & 2, never partner" + "Sun-on-Ace" rule). Reassignment of declarer to the new seat as Sun matches PDF Q1 ("الكة لها ثالث") + Q5 ("قبلك"). ✓ Matches.

**Window opening — Net._HostStepBid (Net.lua:1521-1577):**

When a contract resolution happens:
1. Read `bidRank` from `S.s.bidCard`.
2. Check toggleable `WHEREDNGNDB.preemptOnAce` (default ON in v0.2.0+; can be disabled).
3. Gate: `bidRound == 2 && type == K.BID_SUN && bidRank == "A"`.
4. Build eligibility via `S.PreemptEligibleSeats(payload.bidder, payload.bidder)` — note both args are the buyer, since the buyer is also the bidder in this round-2 path.
5. If eligibility list is non-empty:
   - Stash contract in `S.s.pendingPreemptContract`.
   - Set `S.s.phase = K.PHASE_PREEMPT`.
   - Broadcast `MSG_PREEMPT_PASS` with seat=0 + CSV of eligible seats (the "window-open" frame; seat=0 is the host's open marker).
   - Arm local pre-warn (`StartLocalWarn("preempt")`).
   - Dispatch bots (`MaybeRunBot`).
   - Refresh UI.

**Subtle correctness check:** The host uses `MSG_PREEMPT_PASS` (seat=0) as the "window-open" broadcast — this was a 7th-audit fix to ensure remote clients also enter PHASE_PREEMPT and seed their `preemptEligible` list. Without the CSV, remote humans never saw their claim button.

**Code-vs-PDF: full chain matches.**

**Confidence:** High.

---

## Summary

| Area | Verdict |
|---|---|
| PDF rule clarity | High — every gate is explicit, ≤15-word verbatim Arabic for each main gate. |
| Phase-1 source_K (K-39 to K-48) accuracy | Faithful re-extraction confirms K-19, K-40, K-41, K-42, K-43, K-44, K-45, K-46, K-47, K-48 all match PDF text. |
| Constants.lua match | `K.PHASE_PREEMPT`, `K.MSG_PREEMPT`, `K.MSG_PREEMPT_PASS`, `K.BOT_PREEMPT_TH = 75` — all correctly named, scoped, and commented. |
| Bot.PickPreempt | Correctly layered above the legality engine. Threshold = 75 with jitter; Ace-of-bid-suit bonus = +12; partner-bid signal adjustments are tier-aware (human vs bot partner halved). |
| Net._OnPreempt + Net._HostStepBid | All six PDF gates encoded; eligibility list construction in State.PreemptEligibleSeats correctly excludes buyer, buyer's partner, and seats with no recorded bid. |
| Comparison to Ashkal | Different mechanic. Third = adversarial pre-emption; Ashkal = partner-cooperative bid that *gives* Sun to partner. No conflation in the codebase. |
| Round-2 Hokm-flip vs Third | Two separate mechanics in the codebase (`PHASE_OVERCALL` vs `PHASE_PREEMPT`); PDF discusses both but the Third proper is only the Sun-on-Ace pre-emption. |
| Bid-card semantics post pre-empt | Inferred from `S.ApplyPreempt` + `S.ApplyContract(seat, K.BID_SUN)`: bid card lead-on-trick-1 obligation transfers to new declarer; type stays SUN. PDF is silent here but the implementation is consistent with general Saudi bid-card convention. |

**Overall:** PDF 06 الثالث rule is **correctly implemented** in Constants.lua, State.lua, Net.lua, and Bot.lua. No discrepancy found between the verbatim Arabic source and the code's `PHASE_PREEMPT` gate set. No code modifications required by this re-extraction.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\06_third.txt` — extracted PDF text (1 page, 116 lines).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_K_pdf_basic_rules.md` — Phase-1 K-39..K-48.
- `C:\CLAUDE\WHEREDNGN\Constants.lua:115-135, 211-219, 305-310` — phase + message + threshold constants.
- `C:\CLAUDE\WHEREDNGN\Bot.lua:3682-3727` — `Bot.PickPreempt` decision function.
- `C:\CLAUDE\WHEREDNGN\Net.lua:962-1033, 1038-1050, 1521-1577, 1923-1965` — pre-empt network handlers and host trigger.
- `C:\CLAUDE\WHEREDNGN\State.lua:1873-1919` — `PreemptEligibleSeats`, `ApplyPreempt`, `ApplyPreemptPass`.
- `C:\CLAUDE\WHEREDNGN\docs\strategy\glossary.md:22` — Ashkal entry confirming separate mechanic.
