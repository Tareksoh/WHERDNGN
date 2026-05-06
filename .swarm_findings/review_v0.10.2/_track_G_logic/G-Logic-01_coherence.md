# G-Logic-01 — Coherence audit across rule engine + bot strategy + scoring pipeline

**Scope:** v0.10.2 + v0.10.3 in-tree fixes (uncommitted). Read-only.
**Files audited:**
- `C:\CLAUDE\WHEREDNGN\Bot.lua` (3,900 lines)
- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` (~900 lines)
- `C:\CLAUDE\WHEREDNGN\Rules.lua` (~950 lines)
- `C:\CLAUDE\WHEREDNGN\State.lua` (~2,000 lines, focused reads)
- `C:\CLAUDE\WHEREDNGN\Cards.lua` (full)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` (full)
- `C:\CLAUDE\WHEREDNGN\Net.lua` (HostResolveTakweesh + HostResolveSWA branches)
- A-Src-29 (Faranka cross-source) and A-Src-30 (Tahreeb cross-source) for canonical reading

**Method:** for each of the 7 questions, traced the relevant code paths
end-to-end, re-derived expected behavior on representative hand shapes,
and looked for fall-through / silent-drop / ownership-confusion edges.

---

## Section 1 — Faranka decision tree coherence (Bot.lua:2880-3052)

**Verdict: COHERENT-with-one-MED gap.**

### 1.1 Trace of the four exceptions

The Hokm Faranka block (Bot.lua:2896-3052) is gated by:
- `Bot.IsM3lm()` AND
- `contract.type == K.BID_HOKM` AND
- `contract.trump` non-nil AND
- `trick.leadSuit` non-nil AND
- `#winners > 0` (we hold at least one winner).

Inside, four pro-Faranka conditions ladder OR-style into a single
`farankaTriggered` flag, then a single anti-rule (Q-led + J+8) and an
F-16 K-required veto can clear it.

| # | Site | Pro/anti | Gate | Bidder-team gated? |
|---|---|---|---|---|
| #2 | 2916 | pro | `myTrumpCount == 2` | Yes (v0.9.2 #49) |
| #3 | 2938-2948 | pro | `J dead AND we hold 9` | Yes (v0.10.0 X3) |
| #4 | 2960-2974 | pro | both opps observed-void in trump | Yes |
| anti rule 7 | 3006-3024 | clears | opp bidder led trump-Q AND we hold J+8 | n/a |
| F-16 veto | 2995-3003 | clears | not on `oppsVoidPath` AND no K-of-trump | n/a |

### 1.2 Compositional check on representative hands

**Hand A — bidder-team, weak 2-trump + no K, opps unknown trump:**
hand `{JS, 9S, AH, KH, QH, AD, KD, QC}` (trump = ♠), partner is bidder.
- `myTrumpCount == 2` → triggers Exception #2 ✓
- Exception #3 `S.HighestUnplayedRank(♠) == "9"` only fires if J is
  observed dead; assume J is in opp hand (live) → NOT triggered.
- Exception #4 needs both opps observed void in trump — not yet
  observed → NOT triggered.
- `oppsVoidPath = false`.
- F-16 veto: we don't hold K of trump → veto fires → `farankaTriggered = false`.
- Verdict: Faranka SUPPRESSED, natural play (winners). Coherent with
  A-Src-29 §Q9: F-16 still applies on Exception #2 because the threat
  model (opp A-of-trump punishing the withhold) is live.

**Hand B — bidder, J dead + 9 of trump only, K live in opp:**
hand `{9S, AH, KH, QH, AD, KD, QC, 7C}` (trump = ♠), JS observed
played in prior trick.
- `myTrumpCount == 1` → Exception #2 not triggered (need 2).
- `S.HighestUnplayedRank(♠) == "9"` (J=8 dead, A and T not in trump
  rank 7 actually — A=6, T=5, 9=7 — so 9 is highest live), we hold 9
  → Exception #3 triggered ✓
- F-16 veto: no K of trump → veto fires (`oppsVoidPath = false`).
- Verdict: Faranka SUPPRESSED. Coherent with F-16's threat model
  (opp may hold A — 6 in rank — which would punish the withhold; A is
  not the "next in line", but it's live and ranked above K=4, so the
  withheld 9 would still need K for cover-of-cover).
  Actually here cover concern is different — but the structural rule
  ("F-16 is applicable when threat model live") holds.

**Hand C — bidder + both opps void in trump (Exception #4 fires):**
hand `{KS, AH, KH, AD, KD, QC, JC, 7C}` (trump = ♠), opps known void
in trump via observation.
- `myTrumpCount == 1` → not Exception #2.
- `S.HighestUnplayedRank(♠) == "K"` (J, 9, A, T already played) — we
  hold K → does not match the "9" condition → Exception #3 not fired.
- Exception #4: both opps observed void → fires; `oppsVoidPath = true`.
- F-16 veto: `not oppsVoidPath` is FALSE → veto SKIPPED (v0.10.3 fix #2).
- Verdict: Faranka FIRES (correct per A-Src-29 §Q2 — F-16's threat
  model is structurally extinct under `oppTrumpExhausted == true`).

**Hand D — bidder, opps void in trump, but we have K-of-trump:**
hand `{KS, JS, AH, KH, AD, KD, QC, JC}` (trump = ♠), opps void.
- `myTrumpCount == 2` → Exception #2 triggered ✓.
- Even if it weren't, Exception #4 would fire (`oppsVoidPath = true`).
- F-16 veto: hold K → veto NOT fired → Faranka FIRES.
- Verdict: Faranka FIRES.

**Hand E — bidder partner (NOT bidder), opps void in trump:**
hand `{8S, AH, KH, QH, AD, KD, QC, 7C}` (trump = ♠), opps void.
- Bidder-team membership → onBidderTeam = true.
- Exception #2: only 1 trump → not triggered.
- Exception #3: needs us to hold 9 of trump → not triggered.
- Exception #4: opps void → fires; `oppsVoidPath = true`.
- F-16 veto: skipped.
- Verdict: Faranka FIRES on bidder-partner. Coherent with v0.10.0 X3
  fix (relaxed `contract.bidder == seat` to bidder-team).

### 1.3 Fall-through hands that should-but-don't fire (gap candidates)

**Gap #1 — F-30 trump-exhausted but only ONE opp observed void:**
A-Src-01 §Q4 reading of F-30: "تخلصت الاحكام من ايادي اللاعبين"
(trumps exhausted from players' hands) is sometimes inferable when
trump-J + trump-9 + trump-A + trump-T have all been observed played,
even if `Bot._memory[oppSeat].void[trump]` hasn't been positively
set on both opps yet. Current code requires both opps' `void[trump]`
flags individually — a structurally-extinct trump pool gives the
SAME risk-free Faranka, but one-or-both opps may not have void
flagged because they haven't yet had a non-trump-led trick to
discard from.

Severity: **MED**. Mitigation suggestion (deferred): add a global
`S.HighestUnplayedRank(contract.trump) == nil` short-circuit as a
secondary `oppsVoidPath` trigger.

**Gap #2 — Exception #1 / #5 deferred (per code comment line 2887):**
Sweep-track detection (#1) and partner-extra-trump style ledger (#5)
are explicitly noted as deferred. These are documentation/scope
issues rather than coherence issues. Severity: **LOW**.

**Verdict: Section 1 = COHERENT.** All four exceptions compose on
representative hands. Gap #1 is a missed pro-Faranka, not a wrong
firing — it errs toward the canonical "no Faranka in Hokm" default,
which is conservative.

---

## Section 2 — Tahreeb / Tanfeer / Tamtheel taxonomy in code

**Verdict: PARTIALLY-INCOHERENT (matches REVIEW.md §4.2 backlog).**

Per A-Src-30 (definitive):
- **Outer axis** (Bargiya vs ascending Tahreeb) = **event-count** ✓
- **Inner axis** (Bargiya invite vs Bargiya defensive shed) =
  **hand-shape (محشور)**, NOT event-count.

### 2.1 Code state at Bot.lua:1638-1701 (`tahreebClassify`)

The classifier composition:

```
outer:  signals[1] == "A" → "bargiya class"
        signals[1] != "A" → ascending/descending Tahreeb (event-count)

inner (when bargiya class):
  IF lenAtAce >= 5             → "bargiya"        (محشور proxy ✓)
  ELIF #signals >= 2 AND
       rank(signals[2]) >= T   → "bargiya"        (cover-grade gate)
  ELSE                          → "bargiya_hint"   (defensive-shed fallback)
```

### 2.2 Coherence check vs A-Src-30 §Q3b

**Outer axis match:** YES. `signals[1] == "A"` → Bargiya class;
otherwise event-count direction-encoding. Matches A-Src-30 Rule #3
(canonical from #10).

**Inner axis match:** PARTIAL.
- The `lenAtAce >= 5` proxy IS a hand-shape signal (the holder is
  محشور-likely BECAUSE they have a long single-suit cluster). This is
  source-aligned with A-Src-30 Rule #4 "محشور بلون واحد proxy at
  recorder-time".
- BUT: the cover-grade gate (rank ≥ T) on the second event is
  EVENT-COUNT-axis, not hand-shape. Per A-Src-30 §Q10: "the cheap
  '2nd-rank ≥ T' fix is **NOT sufficient**. A recorder-time
  محشور-detection signal is needed".
- A-Src-30 recommends: distinct-suits-touched-count proxy (if
  partner has only touched 1-2 distinct suits across all tricks so
  far → محشور-likely → single-event Bargiya = invite). Code does
  not implement this.

### 2.3 Concrete worked example where the misalignment fires

**Example A — single-event A-discard, partner held 4-card single-suit:**
- Sender holds `{AH, 9H, 8H, 7H, KS, QD, 7D, JC}` at start; partner
  wins a trick, sender discards AH.
- `lenAtAce = 4` (only 4 H cards at the moment of A-discard, since
  the discard counts as part of the 4).
- 4 < 5 → fails the `lenAtAce >= 5` gate.
- Single event → fails the cover-grade gate.
- Result: classifier returns `"bargiya_hint"` → score = 1 in
  pickLead's bias score (vs `"bargiya" = 3`).
- Per A-Src-30 §Q3b: with sender having touched only 2 distinct
  suits so far (e.g., partner saw their plays in H and S only), the
  محشور signal IS active. Single-event Bargiya should be a CONFIRMED
  invite. The 4-card single-suit cluster is enough محشور-shape per
  P1B Rule 9 ("بلون واحد او بلونين" — one or two suits).

**Example B — 2-event with low cover-rank, partner is محشور:**
- Sender discards A then 9 of same suit while partner wins. Same
  suit length 5+ at moment of A-discard (e.g., AH+9H+8H+7H + one
  other H since-played).
- `lenAtAce >= 5` → fires; returns "bargiya" ✓. (5+ gate covers this.)
- BUT note: per A-Src-30 §Q4d, the phase boundary is 5-cards-or-more
  at start vs 4-or-fewer at end-game. If we're in END-GAME, the
  same lenAtAce numeric threshold catches a different hand-shape —
  late-game Bargiya is `≤4` cards remaining and the receiver's
  "eat 1-2 captures first" timing flip is on the END side. Code
  doesn't differentiate phase boundary.

### 2.4 Severity

**HIGH** for the inner-axis misalignment (A-Src-30 §Q10 explicitly
flags this as "the single most important code-side audit finding").
Already in REVIEW.md §4.2 deferred list as "Bargiya inner-discriminator
axis flip (event-count → hand-shape)".

---

## Section 3 — AKA + Mathlooth + Touching-honors interaction

**Verdict: INCOHERENT-MED for Sun-Mathlooth case.**

The audit asks: when partner leads with AKA on a Mathlooth (K-tripled
in Sun) suit, does the receiver's pickFollow correctly honour
AKA-receiver relief AND maintain Mathlooth-aware play (small-card-first
across tricks 1-2)?

### 3.1 AKA in Sun is impossible by construction

Trace:
- `K.MSG_AKA` is broadcast only by `N.LocalAKA` (Net.lua:2344).
- Line 2347: `if not S.s.contract or S.s.contract.type ~= K.BID_HOKM
  then return end`.
- `S.s.akaCalled` therefore can only be set when contract is Hokm.
- pickFollow's AKA-receiver relief at Bot.lua:2562: gated on
  `contract.type == K.BID_HOKM` — never fires in Sun.
- Implicit-AKA branch at Bot.lua:2537: also gated on Hokm.

So **AKA in Sun is structurally absent** — no AKA-receiver relief
needed because there's no must-trump-ruff in Sun to relieve.

### 3.2 Mathlooth-aware play in Sun pickFollow

A-Src-06 §Q4: "المثلوث يعتبر قوه والقوه دائما الواحد يحافظ عليها"
(Mathlooth is a power, preserve it). The K-tripled holder must NOT
play K in tricks 1-2 (when A and T fall) — the K becomes the live
boss in trick 3 once A and T are spent.

**Code state for Sun pos-2/pos-3 partner-winning + we hold K of led suit:**
- pickFollow line 2631+ (`if partnerWinning`).
- `feedSafe` true (Sun, no trump-led restriction).
- Smother branch (line 2648-2679): collects all `pointCards` of led
  suit (A, T, K, Q, J), donates HIGHEST.

**Concrete hand — Sun, partner leads AH (trick 1), defender at pos 2 holds Mathlooth-K:**
- Defender hand: `{KH, 8H, 7H, ...}` (K-tripled by H, mardoofa 8H/7H).
- Partner is the bidder team's leader (we are NOT on bidder-team — we're on opp team).
- WAIT: smother fires only when `partnerWinning` — but here OUR
  partner did NOT lead. We're the defender; the BIDDER led AH.
- Actually: smother fires when "OUR partner is winning". If our
  partner won the prior plays, we'd dump K. But this scenario has
  the BIDDER leading AH, not our partner.
- So in the bidder-leading-A case, smother doesn't fire on us
  (the defender). We have to follow suit, and the bot will
  default to lowestByRank → 7H or 8H first. ✓ Mathlooth-K is
  preserved.

**Concrete hand — Sun, our partner (defender) leads AH (trick 1), we are pos-2 K-tripled holder:**
- Hand: `{KH, 9H, 8H, AS, KS, QC, JC, 7D}` — K-tripled in H.
- Our partner led AH. partnerWinning = true.
- Smother (line 2648+) fires: pointCards = `{KH}` of led suit.
- `#pointCards == 1`, `completed == 0`, lastSeat false → gate
  `#pointCards >= 2 OR completed >= 3 OR lastSeat` is FALSE.
- Smother does NOT fire. Falls through to lowestByRank → plays
  9H (lowest of led suit). ✓ Mathlooth-K preserved.

But: change defender's H holding to `{KH, TH, 9H, 8H}` (4 H cards
including K + T — different shape, not strict Mathlooth):
- pointCards = `{KH, TH}`, `#pointCards == 2`.
- Gate fires. table.sort by trickRank desc → TH first (higher
  rank). Smother returns `pointCards[1]` = AH? No — wait:
  pointCards has KH and TH; sorted desc = [TH, KH] in plain rank
  (T=7 > K=6). Returns TH.
- TH gets dumped to partner's pile, K preserved.

Hmm, but this is K-of-held-suit + T-of-held-suit donating T not K
— that's actually correct Mathlooth play (preserve K, donate T).

**The actual gap arises in:**
- pos 4 (lastSeat=true) → smother gate `lastSeat` is true → smother
  fires unconditionally → returns highest pointCard.
- If at pos-4 of a Sun trick where partner led A and the
  K-tripled holder is forced to follow last seat with K + 8 + 7
  remaining, hand `{KH, 8H, 7H}` only (3-card mathlooth) →
  pointCards = `{KH}`, sorted = [KH]; smother returns KH. **K is
  dumped to partner's trick pile in trick 1.** Mathlooth preserved
  from trick 1 was the WHOLE POINT.

But wait: in Sun, pos-4 dumping the K to partner's pile feeds 4
points (Sun K=4 raw) to partner's trick. Per the Saudi convention,
this is fine — partner takes 11+10+4+? from this trick. The
"preservation" intent is about WINNING trick 3 with K, not
preserving the card-points.

If K is DUMPED in trick 1 to partner-winning pile: partner's team
gets the K's 4 raw points NOW. But in trick 3 (when A and T are
spent), the K WOULD have won the trick for the K-tripled holder's
team. By dumping K, we GAVE 4 points + the trick (and the +10
last-trick bonus if it were trick 8) to the other team prematurely.

Contradicts Mathlooth preservation. **Severity: MED.** This is a
real but subtle gap between general "feed-points-to-partner"
heuristic and Mathlooth-specific "preserve K for trick 3".

### 3.3 Touching-honors WRITE during AKA-led trick

Bot.lua:476-508. The WRITE is gated:
- `not wasIllegal` ✓
- `contract` non-nil ✓
- `trickPlays` non-nil and `#trickPlays >= 2` ✓
- `style.topTouchSignal` non-nil ✓
- `lead.seat == R.Partner(seat)` AND `C.Suit(lead.card) == cardSuit`
  AND `C.Rank(lead.card) == "A"` (explicit Ace-led)
  OR `S.s.akaCalled` matches.

Note: `cardSuit = C.Suit(card)` is the played card's suit. The
condition `C.Suit(lead.card) == cardSuit` requires played card SAME
suit as the led Ace. So this only fires when seat (the player) is
following suit. In Hokm if seat over-ruffs with a trump (different
suit), it doesn't fire. Good.

**Gap (already in REVIEW.md §4.2):** No explicit partner-still-winning
gate. But the same-suit gate makes this safe — Branch 1
(`C.Suit(lead.card) == cardSuit`) and Branch 2 (`S.s.akaCalled.suit
== cardSuit`) both ensure the played card is in the relevant
non-trump suit. Partner's Ace is therefore still winning. AKA
banner is also cleared at S.ApplyTrickEnd (State.lua:1327) — no
stale-AKA cross-trick poisoning. **Severity: LOW** — practical
signal is correct.

---

## Section 4 — Sun rank order propagation (A>T>K, not A>T>J)

**Verdict: COHERENT.**

### 4.1 Constants.lua

```
K.RANK_PLAIN = { ["7"]=1, ["8"]=2, ["9"]=3, ["J"]=4, ["Q"]=5, ["K"]=6, ["T"]=7, ["A"]=8 }
```
→ Sun: A(8) > T(7) > K(6) > Q(5) > J(4) > 9(3) > 8(2) > 7(1) ✓.

### 4.2 Cards.TrickRank (Cards.lua:107-114)

Hokm-trump branch returns RANK_TRUMP_HOKM; otherwise RANK_PLAIN.
Sun contracts always fall to RANK_PLAIN. ✓

### 4.3 State.HighestUnplayedRank (State.lua:1352-1381)

```
local AKA_ORDER = { "A", "T", "K", "Q", "J", "9", "8", "7" }
local TRUMP_HOKM_ORDER = { "J", "9", "A", "T", "K", "Q", "8", "7" }
```
Sun and non-trump Hokm walk AKA_ORDER (A > T > K …). ✓

### 4.4 BotMaster sampler (BotMaster.lua:159, 495)

`for _, rank in ipairs({ "A", "T", "K", "Q", "J", "9", "8", "7" }) do` —
all unseen-pool builds and broke-clears walk this order. ✓

### 4.5 Comments

Bot.lua:2799 says `RANK_PLAIN: 7<8<9<J<Q<K<T<A`. Matches RANK_PLAIN
exactly. ✓

### 4.6 Search for any A>T>J assumptions

Grepped for "A.*T.*J" and "A>T>J" — only found in test file
references and meld carré arrays (`{"A","T","K","Q","J"}`) which
are descending rank lists, not ordering claims.

### 4.7 docs/strategy

Per REVIEW.md §3 Doc fix #5: `decision-trees.md:123-138` was
reverted to K-tripled canonical (A-Src-06 confirmed Sun rank A>T>K).
docs are now coherent.

**No A>T>J residue found in code paths.**

---

## Section 5 — Escalation chain coherence (×2 / ×3 / ×4 / Gahwa)

**Verdict: PARTIALLY-INCOHERENT (HIGH on Net.lua paths).**

### 5.1 Constants

- K.MULT_BASE = 1, K.MULT_SUN = 2, K.MULT_BEL = 2, K.MULT_TRIPLE = 3,
  K.MULT_FOUR = 4. Gahwa is NOT a multiplier — match-win special-case.
- K.MELD_BELOTE = 20 raw, applied AFTER multiplier (multiplier-immune).

### 5.2 R.ScoreRound (Rules.lua:883-893)

```
mult = K.MULT_BASE
if Sun then
  mult *= K.MULT_SUN
  if doubled then mult *= K.MULT_BEL  -- Sun-Bel = ×4
  -- intentionally ignore tripled/foured/gahwa on Sun (R2 normalization)
else  -- Hokm
  if gahwa then mult *= K.MULT_FOUR  (×4 baseline; match-win special-cased below)
  elif foured then mult *= K.MULT_FOUR
  elif tripled then mult *= K.MULT_TRIPLE
  elif doubled then mult *= K.MULT_BEL
end
```
✓ Belote applied after multiplier (line 908-912):
`rawA += K.MELD_BELOTE` (multiplier-immune). ✓

### 5.3 Net.HostResolveTakweesh (Net.lua:2185-2190)

```
mult = K.MULT_BASE
if Sun then mult *= K.MULT_SUN end     -- always applies
if gahwa then mult *= K.MULT_FOUR
elif foured then mult *= K.MULT_FOUR
elif tripled then mult *= K.MULT_TRIPLE
elif doubled then mult *= K.MULT_BEL end
```

**MISSING the R2 Sun-collapse.** If a stale resync sets `Sun + tripled`,
the mult becomes ×2 × ×3 = ×6 here but ×2 in Rules.lua. Rules.lua
"intentionally ignore tripled/foured/gahwa on Sun" (R2); Takweesh
doesn't.

### 5.4 Net.HostResolveSWA-invalid (Net.lua:2930-2935)

Same code, same bug. Sun-mult-collapse not backported.

**Severity: MED.** Already in REVIEW.md §4.2 backlog as
"R2 Sun mult collapse not backported to Takweesh / SWA-invalid". On
a clean wire path the phase machine prevents Sun-tripled, but in a
hand-edited save / stale resync / adversarial peer scenario, a
Takweesh penalty would charge ×6 instead of ×2 on a Sun-tripled
contract.

### 5.5 fail/take/ok branches in Rules.lua:823-862

- "fail": cardA/B = handTotal to opp team; meldPoints = each team's
  own melds (loser keeps own — Saudi rule «مشروعي لي ومشروعك لك»). ✓
- "take" (4-10 doubled-tie inversion): cardA/B = handTotal to bidder
  team; meldPoints = each team's own melds. ✓
- "make": cardA/B = teamPoints (trick points + last-trick bonus);
  meldPoints = winner-takes-all by best-meld comparison. ✓

All three branches feed into the same `mult` calculation at line
883-893, so the multiplier propagates uniformly. ✓

### 5.6 Belote multiplier-immunity

Rules.lua:908-912 (after `rawA = (cardA + meldPoints.A) * mult`):
`if belote == "A" then rawA = rawA + K.MELD_BELOTE`. ✓
HostResolveTakweesh line 2250-2251: `if belote == "A" then rawA =
rawA + K.MELD_BELOTE`. ✓
HostResolveSWA-invalid line 2981-2982: `if beloteOwner == "A" then
rawA = rawA + K.MELD_BELOTE`. ✓

All three sites apply belote AFTER the multiplier. ✓

### 5.7 Gahwa match-win (Rules.lua:920-937)

`if contract.gahwa then` sets `gahwaWonGame = true` and
`gahwaWinner = bidderTeam` (if bidderMade) or `oppTeam` (if not).
Per-round `final` is still computed via div10 — but Net.lua's
HostStepAfterTrick reads `gahwaWonGame` and short-circuits to
match-end. ✓

**Verdict: Section 5 = PARTIALLY-INCOHERENT (MED).** Rules.lua side
is coherent. Net.lua takweesh/SWA-invalid side missing R2 Sun-collapse.

---

## Section 6 — Last-trick +10 coherence

**Verdict: COHERENT.**

### 6.1 Applied once per round

R.ScoreRound (Rules.lua:670-673):
```
if i == #tricks then
  lastTrickTeam = team
  teamPoints[team] = teamPoints[team] + K.LAST_TRICK_BONUS
end
```
The check `i == #tricks` ensures it fires only on the iteration over
the LAST trick in the array. With 8 tricks, only iteration 8 hits.
Single application. ✓

### 6.2 Multiplier-aware

`teamPoints[team] += K.LAST_TRICK_BONUS` happens BEFORE
`cardA, cardB = teamPoints.A, teamPoints.B` (line 858) and BEFORE
`rawA = (cardA + meldPoints.A) * mult` (line 895). So +10 is
multiplied. ✓

In Sun (×2 baseline): final +10 → +20 raw → +2 game points.
In Hokm-Bel (×2): +20 raw → +2 gp.
In Hokm-Triple (×3): +30 raw → +3 gp.
In Hokm-Four/Gahwa (×4): +40 raw → +4 gp.

Coherent with Saudi convention.

### 6.3 Awarded to trick winner team, not bidder team

Line 666-672: `team = R.TeamOf(t.winner)`. The bonus goes to the team
of the trick winner. There is NO ownership confusion with bidder
team (the +10 is added to teamPoints, which is partitioned by trick
winner regardless of contract).

**However**, `lastTrickTeam` is exported in the result struct and
stored — but it's not used downstream for any "bidder-team" mapping,
only as informational metadata. ✓

### 6.4 Sweep-bonus override

When sweepTeam fires (Rules.lua:817-822), `cardA = bonus or 0` —
this REPLACES teamPoints with the sweep bonus K.AL_KABOOT_HOKM=250
or K.AL_KABOOT_SUN=220. The +10 last-trick bonus is implicitly
absorbed (sweep means same team won all 8 tricks anyway, and the
sweep bonus represents the entire scoring replacement). ✓

K.HAND_TOTAL_HOKM = 162 = 152+10 (last trick), but the sweep bonus
250 is NOT 162 — it's a different number, namely 25 game points × 10
raw inverse. Per Saudi convention, sweep replaces normal scoring
entirely. The +10 doesn't double-count when sweep fires. ✓

**Verdict: Section 6 = COHERENT.**

---

## Section 7 — Carré-A in Sun = 400 vs Carré-A in Hokm = 100 propagation

**Verdict: PARTIALLY-INCOHERENT (HIGH on State.ApplyMeld).**

### 7.1 Constants.lua

```
K.MELD_CARRE_OTHER = 100   -- T, K, Q, J (any contract type) AND Carré-A in Hokm
K.MELD_CARRE_A_SUN = 400
K.CARRE_RANKS = { A=true, T=true, K=true, Q=true, J=true }
```
✓ Both constants defined and disjoint.

### 7.2 R.DetectMelds (Rules.lua:268-287)

```
for rank, count in pairs(byRank) do
  if count == 4 and K.CARRE_RANKS[rank] then
    local value
    if rank == "A" then
      value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
    else
      value = K.MELD_CARRE_OTHER
    end
    ...
  end
end
```
- Sun + 4-Aces → 400. ✓
- Hokm + 4-Aces → 100. ✓ (v0.10.0 X5 fix applied).
- Sun + 4-Kings → 100. ✓
- Hokm + 4-Kings → 100. ✓

### 7.3 State.ApplyMeld (State.lua:1167-1184)

```
if kind == "carre" then
  if K.CARRE_RANKS[top] then
    if top == "A" then
      if s.contract and s.contract.type == K.BID_SUN then
        value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
      end
      -- Hokm 4-Aces: doesn't score (per Pagat-strict)  ← BUG
    else
      value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
    end
  end
end
if not value then return end           -- Hokm 4-Aces silently DROPPED
```

**INCOHERENT.** The Hokm 4-Aces branch has no `else value = K.MELD_CARRE_OTHER`,
so `value` stays nil and the `if not value then return end` early-exits.
This is the v0.10.0 X5 bug at the **apply** path that wasn't fixed
along with the **detect** path.

### 7.4 R.CompareMelds (Rules.lua:301-353)

`meldRank` for carrés returns `1000 + (m.value or 0) + rankBonus`.
Hokm 4-Aces: value=100 (after detect), rankBonus = TrickRank(A♠ in
Hokm) × 0.01. If trump is ♠, A♠ is a trump-A (rank 6), bonus = 0.06.
If trump is non-♠, A♠ is plain (rank 8), bonus = 0.08.

So Hokm Carré-A meldRank = 1000 + 100 + 0.06 or 0.08 = 1100.06 or 1100.08.
Hokm Carré-K meldRank = 1000 + 100 + (TrickRank(K)*0.01).
- K is rank 4 in trump, rank 6 in plain → 0.04 or 0.06.

So Carré-A should beat Carré-K via the trick-rank bonus (A always
ranks higher than K in either ordering). ✓

But: this presumes Hokm Carré-A makes it INTO the comparison list.
Per §7.3, S.ApplyMeld silently drops it — so the comparison never
sees Hokm Carré-A. The bidder strict-majority gate at Rules.lua:760
also misses the +100 raw. This propagates downstream silently.

### 7.5 R.ScoreRound

When meld lists are passed to `R.SumMeldValue` (computing meldA, meldB)
and to `R.CompareMelds`, the Hokm 4-Aces meld is absent (because
S.ApplyMeld dropped it). So:
- Bidder might fail strict-majority unnecessarily (-100 raw missing).
- Belote-cancellation (≥100 meld subsumes belote) wouldn't fire on
  the Hokm 4-Aces holder → silent +20 over-scoring.

**Severity: HIGH.** Already in REVIEW.md §4.2 backlog as
"S.ApplyMeld drops Hokm Carré-A (X5 inert in apply path)".

### 7.6 Concrete worked example

Hokm contract, trump=♠, bidder team holds 4 Aces split:
- Bidder: AS, AH (2 Aces).
- Bidder partner: AD, AC (2 Aces).
- Bidder declares meld in trick 1: kind=carre, top=A.
- S.ApplyMeld: top=="A", contract.type=BID_HOKM (not SUN) → value
  stays nil → `if not value then return end` → meld NOT recorded.
- meldA stays at whatever non-Carré melds were declared.
- Defenders have nothing.

Expected: bidder team gets +100 raw (Hokm Carré-A) × multiplier,
roughly +10 game points.
Actual: bidder team gets 0 from the Carré-A → contract may fail by
narrow margin (e.g., 80 vs 80 with Carré-A would be 180 vs 80 →
make).

**Verdict: Section 7 = PARTIALLY-INCOHERENT (HIGH).**

---

## Severity-tagged summary

| # | Area | Verdict | Severity | Status |
|---|---|---|---|---|
| 1 | Faranka decision tree | COHERENT-with-MED-gap | MED (Gap #1) | New finding (deferred); F-30 trump-exhausted secondary trigger |
| 2 | Tahreeb / Tanfeer / Tamtheel taxonomy | PARTIAL | HIGH | Already in §4.2 backlog (Bargiya inner-axis flip) |
| 3 | AKA + Mathlooth + Touching-honors | INCOHERENT-MED on Sun-Mathlooth | MED | New finding (Sun pos-4 smother dumps Mathlooth-K) |
| 4 | Sun rank order (A>T>K) | COHERENT | n/a | Reverted in docs; code never had A>T>J |
| 5 | Escalation chain | PARTIAL | MED | Net.lua R2 Sun-collapse not backported (already §4.2) |
| 6 | Last-trick +10 | COHERENT | n/a | Single-application, mult-aware, ownership-correct |
| 7 | Carré-A Sun=400 vs Hokm=100 | PARTIAL | HIGH | S.ApplyMeld drops Hokm Carré-A (already §4.2) |

---

## Cross-cutting observations

**O-1 (positive).** The v0.10.3 in-tree fixes are tightly composed: each
change is local (one site, one predicate) and each site I traced fired
correctly on representative hands. The Faranka tree (3 exceptions + 2
clears) composes without contradictions.

**O-2 (positive).** The Sun-mult-collapse (R2) and Carré-A Sun/Hokm
discrimination (X5) are CORRECTLY implemented in Rules.lua's
R.ScoreRound + R.DetectMelds — the gaps are at downstream
"shadow apply" sites (State.ApplyMeld, Net.lua HostResolveTakweesh /
HostResolveSWA-invalid) that diverged from the canonical site.
Coherence work for v0.10.4+ should consider extracting a single
canonical mult-resolver and meld-value-resolver to be called from all
sites rather than re-deriving the multiplier ladder per site.

**O-3 (new finding, MED).** The Bot.lua line 484 touching-honors WRITE
gate is more airtight than REVIEW.md §4.2 implies. The same-suit
check `C.Suit(lead.card) == cardSuit` rules out the over-ruff
gap — partner-still-winning is GUARANTEED when the played card
follows the led Ace's suit (since Ace is highest in any non-trump
suit, and trump-led case is excluded by AKA's non-trump-only rule).
The "missing partner-still-winning gate" concern is theoretical;
the practical signal is correct.

**O-4 (new finding, MED).** Sun-Mathlooth pos-4 smother dumps
Mathlooth-K to partner's pile (defeats trick-3 preservation). This
is a genuine strategic loss for the K-tripled holder, but it only
fires when the K-tripled holder is on partner's winning side — i.e.
when their PARTNER led the Ace of the Mathlooth suit. The
"feed-points-to-partner" heuristic is mostly correct (donates 4
trump-points immediately) but loses the trick-3 boss potential
worth ~10 face value + +10 last-trick if it were trick 8. Net EV is
context-dependent; not a clear bug, but a flagged coherence issue.

**O-5 (re-confirmation, no action).** The Sun rank order is
unambiguously A>T>K throughout code (RANK_PLAIN, AKA_ORDER, sampler
walks, comments). No A>T>J residue. The doc fix #5 reversion to
K-tripled canonical is consistent.

**O-6 (re-confirmation, no action).** The +10 last-trick bonus is
single-application, multiplier-aware, and team-of-trick-winner-
attributed. Sweep-bonus path correctly absorbs the +10 by replacing
teamPoints. No double-counting.

---

## Recommendations for v0.10.3 release scope

In addition to REVIEW.md §9's existing scope:

1. **MED:** Add `S.HighestUnplayedRank(contract.trump) == nil` as a
   secondary `oppsVoidPath` trigger in Bot.lua's Faranka Exception
   #4 (Section 1 Gap #1). One-line addition; covers F-30 trump-pool-
   structurally-extinct case where individual opp `void[trump]`
   flags haven't been positively set yet.

2. **HIGH:** Fix State.ApplyMeld:1167-1184 to mirror the X5 fix in
   R.DetectMelds. Add `else value = K.MELD_CARRE_OTHER` to the Hokm
   4-Aces branch. (Already in REVIEW.md §4.2.)

3. **MED:** Backport R2 Sun-mult-collapse to Net.lua HostResolveTakweesh
   (line 2185-2190) and HostResolveSWA-invalid (line 2930-2935).
   Drop the `if c.gahwa/foured/tripled` chain on Sun contracts. Three
   lines of guard each. (Already in REVIEW.md §4.2.)

4. **MED (new):** Add a Mathlooth-suit-preservation gate in pickFollow
   smother branch. Detection: opp-team holds 4-card mathlooth shape
   in led suit (≥3 cards including K + supporting); skip K-donation
   in trick 1-2 if we're the K-holder. Out-of-scope for v0.10.3
   without strategy-doc support; flag as v0.10.4+ deferred.

5. **HIGH (deferred):** Bargiya inner-discriminator axis: replace
   event-count + cover-grade gate with hand-shape (suits-touched-
   count) proxy per A-Src-30 §Q3b/Q10. Already in REVIEW.md §4.2.

---

*End of G-Logic-01_coherence.md.*
