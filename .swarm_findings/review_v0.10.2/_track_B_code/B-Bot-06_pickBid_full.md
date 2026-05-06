# B-Bot-06 — Deep audit of `Bot.PickBid` (full bidding decision)

**Target:** `Bot.PickBid` (Bot.lua:1175-1514) and supporting helpers
`hokmMinShape` (782-806), `sunMinShape` (816-832), `sunStrength`
(882-927), `combinedUrgency` (1117-1122), `partnerBidBonus`
(945-964) — at v0.10.2.
**Read-only.** No code modified.
**Audit date:** 2026-05-05.

This audit complements `B-Bot-01_pickBid.md` (broader review) and
`D-RT-11_hokm_ace_tier.md` (red-team on the L07 gate). It traces
the full bid decision tree against the eleven scope items requested
and surfaces the most important EV-shaping interactions between
them.

---

## Decision-tree overview (R1 vs R2)

The function executes in this order, gated on `S.s.bidRound`:

1. **Carré-of-Aces (mandatory Sun)** — `aceCount >= 4` early-return
   (line 1189). Beats every other path. ✓
2. **Compute** `anyHokm` / `anySun` from prior bids (1191-1197).
3. **Compute strength scores**: `sun` (1215-1218), `belote` (1226),
   `urgency` (1229), per-round threshold bases `r1Base/r2Base`
   (1244-1254), jittered thresholds `thHokmR1/thHokmR2/thSun`
   (1255-1257), and Sun-Bel-fear bias (1269-1274).
4. **Round 1** (1276-1447):
   1. **Ashkal eligibility** check (1287-1410): seat `bidPos >= 3`,
      partner already bid HOKM, no prior Sun, allow-list pass on
      bid-up rank, A-5 / A-6 strength gates, Advanced bot's
      flipped-suit-J check. If `sun >= thAshkal` → `BID_ASHKAL`.
   2. **Direct Sun** (1423): `sunMinShape and sun >= thSun` → `BID_SUN`.
   3. **Hokm-on-flipped** (1431-1445): no prior Hokm/Sun + bid-up
      suit qualifies via `hokmMinShape` + `strength >= thHokmR1`
      → `BID_HOKM:bidCardSuit`.
   4. Default → `BID_PASS` (1446).
5. **Round 2** (1449-1513):
   1. **Partner-Hokm suppression** (1461-1474, G-4): partner bid
      Hokm → only Sun overcall or PASS.
   2. **Best-suit Hokm search** (1481-1490): iterate all suits
      ≠ `bidCardSuit`, gate on `hokmMinShape`.
   3. **Sun-vs-Hokm tie-break** (1498-1509, B-5): if Sun viable,
      bid Sun unless Hokm beats Sun by ≥ 5.
   4. **Hokm fallback** (1510-1512): `bestScore >= thHokmR2` →
      `BID_HOKM:bestSuit`.
   5. Default → `BID_PASS` (1513).

The structural shape is sound. The findings below catalogue
behaviour at the **decision-edge** boundaries.

---

## Findings

### F-01 (S2-medium, CONFIRMS D-RT-11.3) — L07 Aceless-Hokm hard veto blocks strong sweep hands at M3lm+

**Severity:** S2-medium (calibration drift, EV-negative on rare but
high-strength hands).

**Repro:** M3lm+ bot, 8-card hand with 5 hearts including J♥+9♥,
zero Aces anywhere. Heart bid up.

```
hand = { J♥, 9♥, T♥, K♥, 8♥, 7♣, 8♣, 9♦ }
bidCardSuit = "H"
WHEREDNGNDB.m3lmBots = true
```

**Trace:**

1. R1 line 1189: `aceCount=0`, skip Carré branch.
2. Line 1423: `sunMinShape` requires ≥2 Aces or A+T mardoofa →
   false → skip direct-Sun.
3. Line 1431-1432: `hokmMinShape(hand, "H")` is invoked; trump
   count=5, hasJ=true, hasAnyAce=false. Gate at 800-802 fires,
   returns false.
4. Line 1446: `return K.BID_PASS`.

In R2 the bot iterates other suits at line 1482-1490 — with no
Aces anywhere, `hokmMinShape` rejects every suit at the L07 gate.
`bestSuit = nil`. `sunMinShape` false (zero Aces). Line 1513:
`return K.BID_PASS`.

**Code (Bot.lua:798-805):**

```lua
if not hasJ then return false end          -- B-4 absolute floor
-- v0.10.0 L07 tier-gated requirement: any Ace in hand.
if Bot.IsM3lm and Bot.IsM3lm() and not hasAnyAce then
    return false
end
if count >= 4 then return true end         -- B-2 self-sufficient
if count == 3 and hasSideAce then return true end  -- B-1 minimum
return false
```

**Why it matters:** A 5-trump J+9 hand has ~80% expected hold even
without Aces (sweep-shape, with the K-cover for Q-loss insurance).
Pre-v0.10.0 the bot would have bid Hokm at strength ~48-55 →
`thHokmR1=42 ± jitter` is reliably crossed. v0.10.0 forces PASS,
giving the contract to a weaker opponent who lifts ~30-35 points
off it.

**EV cost:** ~0.18 game points per deal × ~30-40 deals per match
= ~5-7 game-point swing per match. Empirically detectable in
headless tournament A/B (matches D-RT-11 Issue 3 estimate).

**Source:** decision-trees.md B-1/B-2 are Saudi rules (Definite,
video 26); Pro-2 PDF L07 is strategy-tier (per Phase 1 source-H
verdict in `xref_X4_pro2_deal.md`). Implementing a strategy
convention as a hard veto at the same severity as a Saudi rule
is a documentation/implementation severity mismatch (see also
F-12 below).

---

### F-02 (S2-medium, CONFIRMS D-RT-11.4) — R1 + R2 cascade fail at M3lm+ for Aceless Hokm-strong hands

**Severity:** S2-medium (cumulative cascade of F-01).

**Repro:** Same hand as F-01. Both R1 and R2 PASS.

**Trace expanded for R2:** Assuming partner-Hokm suppression (G-4)
at line 1461 doesn't fire (no partner Hokm bid):
1. Line 1481-1490: best-suit Hokm search calls `hokmMinShape` for
   each suit ≠ `bidCardSuit`. Each suit is checked independently;
   each fails the L07 gate. `bestSuit = nil, bestScore = 0`.
2. Line 1498: `sunMinShape` requires ≥2 Aces — fails on 0 Aces.
   Sun branch skipped.
3. Line 1510: `bestSuit and bestScore >= thHokmR2` — `bestSuit` is
   nil, condition false.
4. Line 1513: `return K.BID_PASS`.

**Two-round forfeit on a hand with raw Hokm strength ≥ 48-55.**

**Code (Bot.lua:1481-1513):**

```lua
local bestSuit, bestScore = nil, 0
for _, suit in ipairs(K.SUITS) do
    if suit ~= bidCardSuit and hokmMinShape(hand, suit) then
        local s = suitStrengthAsTrump(hand, suit)
        s = s + sideSuitAceBonus(hand, suit)
        if belote == suit then s = s + K.BOT_PICKBID_BELOTE_BONUS end
        if s > bestScore then bestSuit, bestScore = suit, s end
    end
end
...
if bestSuit and bestScore >= thHokmR2 then
    return K.BID_HOKM .. ":" .. bestSuit
end
return K.BID_PASS
```

**Mitigation candidates** (per D-RT-11 §6, NOT applied):
- Sweep-strong escape: skip L07 when `count >= 5 and hasJ and has9`.
- Penalty-bias model: `strength -= K.BOT_PICKBID_NO_ACE_PENALTY`
  instead of veto.
- Saudi-Master-only enforcement: tier-gate at IsSaudiMaster() so
  M3lm/Fzloky stay on the v0.9.x calibration.

---

### F-03 (S3-low) — Duplicate T-cardinality block in Ashkal allow-list

**Severity:** S3-low (dead-code redundancy — no functional bug).

**Repro:** N/A; static code analysis. Lines 1336-1342 and
1366-1372 implement the **identical** T-cardinality check. Both
loop the hand counting T cards and set `ok = false` if `tCount > 1`.

**Code (Bot.lua:1336-1342):**

```lua
if ok and bidCardRank == "T" then
    local tCount = 0
    for _, c in ipairs(hand) do
        if C.Rank(c) == "T" then tCount = tCount + 1 end
    end
    if tCount > 1 then ok = false end
end
```

**Code (Bot.lua:1366-1372):**

```lua
if ok and bidCardRank == "T" then
    local tCount = 0
    for _, c in ipairs(hand) do
        if C.Rank(c) == "T" then tCount = tCount + 1 end
    end
    if tCount > 1 then ok = false end
end
```

The second block is unreachable when the first fires (`ok=false`
short-circuits the `if ok and ...` guard); when the first doesn't
fire (tCount<=1), the second won't either. Pure redundancy from
a missed consolidation between v0.9.2 patch (1336-1342) and v0.9.2
#60 audit fix (1366-1372).

**Recommended:** delete one block. (Already noted in
`B-Bot-01_pickBid.md` F5 — re-confirmed here.)

---

### F-04 (S3-low) — `S.s.bids` deref at line 1194 lacks defensive guard

**Severity:** S3-low (latent nil-safety inconsistency).

**Repro:** N/A; structural inconsistency. Line 1194 dereferences
`S.s.bids[s2]` without `S.s.bids and ...`, while line 1294 uses
the defensive `S.s.bids and S.s.bids[partner]`.

**Code (Bot.lua:1192-1197):**

```lua
local anyHokm, anySun = false, false
for s2 = 1, 4 do
    local b = S.s.bids[s2]      -- ← no guard
    if b == K.BID_SUN then anySun = true
    elseif b and b:sub(1, 4) == K.BID_HOKM then anyHokm = true end
end
```

**Code (Bot.lua:1293-1294, defensive):**

```lua
local partner = R.Partner(seat)
local partnerBid = S.s.bids and S.s.bids[partner]
```

In practice `s.bids = {}` is initialized at bid-phase start (no
nil reachable from PickBid call site), but the defensive
inconsistency is a hazard if PickBid is ever called from a
new entry point (e.g. testing harness, replay). Already flagged
in B-Bot-01 F15.

---

### F-05 (S3-low, NEW) — `aceCountAndMardoofa` walks the hand twice

**Severity:** S3-low (micro-perf / readability).

**Repro:** N/A; static. Line 1188 calls `aceCountAndMardoofa(hand)`
which walks the 8-card hand once. Then line 1215 immediately calls
`sunStrength(hand)` which walks the hand again. Then line 1226
calls `beloteSuit(hand)` (3rd walk). Then `combinedUrgency` is
score-only (skip), but `urgency` is consulted. Then for R1, the
Ashkal block at 1338-1340 walks the hand a 4th time for `tCount`,
again at 1350-1354 for own-A, again at 1367-1371 (duplicate per
F-03), again at 1399-1403 for `hasJflip`. R2 best-suit search
calls `suitStrengthAsTrump` per-suit (4× walks).

Total worst-case hand walks per PickBid call: ~10. Each walk is
O(hand size = 8). Not a hot path performance bug, but a
readability and maintainability concern — flag-detection helpers
that already exist (`aceCount`, `mardoofaCount` from line 1188)
could be threaded into `sunMinShape` / Ashkal-A-check / etc. to
avoid the recompute.

Not actionable as a bug; informational for a future cleanup pass.

---

### F-06 (DESIGN, NEW) — Ashkal `bidPos >= 3` correctly mirrors host's `bidPosition >= 3` predicate

**Severity:** DESIGN (no bug; cross-reference verification).

The bot-side seat eligibility check at lines 1295-1306 is
identical in semantics to the host-side check at
`State.lua:1751-1755`. Both use the dealer-relative ordering
`{(d%4)+1, ((d+1)%4)+1, ((d+2)%4)+1, d}` and require
`bidPos >= 3` (positions 3 = dealer's left, 4 = dealer himself).

```lua
-- Bot.lua:1295-1306
local bidPos = 0
if S.s.dealer then
    local d = S.s.dealer
    local order = {
        (d % 4) + 1, ((d + 1) % 4) + 1,
        ((d + 2) % 4) + 1, d,
    }
    for i, st in ipairs(order) do
        if st == seat then bidPos = i; break end
    end
end
if bidPos >= 3
   and partnerBid and partnerBid:sub(1, #K.BID_HOKM) == K.BID_HOKM
   and not anySun then
```

```lua
-- State.lua:1751-1755 (host-side enforcement)
local bidPosition = 0
for i, ord in ipairs(order) do
    if ord == seat then bidPosition = i; break end
end
if bidPosition < 3 then
    -- Silently drop — 1st and 2nd bidders can't legally call Ashkal.
```

**Status: CORRECT.** The bot's defensive check matches the host's
authoritative check. No mismatch. ✓

---

### F-07 (CONFIRMS B-Bot-01 F12, S3-low) — R2 missing `anySun` consultation

**Severity:** S3-low (cousin of G-4; wire violation only — host
silently drops illegal HOKM-over-Sun since Sun already locks
`winning`).

**Repro:** R2 path. Setup: opponent bid Sun in R1 (so `winning` is
locked Sun). The bot reaches R2 with partner at PASS and a strong
Hokm hand. Trace:

1. Line 1461-1473: `g4_partnerBidHokm` is false (partner passed).
2. Line 1481-1490: best-suit Hokm search runs. `bestSuit =
   <some suit>`, `bestScore` may exceed `thHokmR2`.
3. Line 1498: `sunMinShape` may or may not be true; either way
   the path doesn't gate on `anySun`.
4. Line 1510: returns `BID_HOKM:bestSuit` if `bestScore >= thHokmR2`.

Per Saudi rule R3 (video #28: "A Sun bid CANNOT be taken by any
other player as Hokm"), this is illegal. The host drops it
silently (the prior Sun has already won `winning`), but the wire
frame is a rule violation visible in logs.

**Code path with bug:**

```lua
-- Line 1481-1490: no `anySun` guard
local bestSuit, bestScore = nil, 0
for _, suit in ipairs(K.SUITS) do
    if suit ~= bidCardSuit and hokmMinShape(hand, suit) then
        ...
```

The R1 Hokm-on-flipped path at line 1431 (`if not anyHokm and
not anySun and bidCardSuit then`) does correctly gate on
`anySun`. The R2 best-suit search and the Hokm fallback at line
1510 do not.

**Source:** decision-trees.md A2/A3 (video #28 R3); already
flagged in B-Bot-01 F12. Re-confirmed: not addressed in v0.10.2.

---

### F-08 (DESIGN, NEW) — Bel-fear bias is asymmetric: own-team only

**Severity:** DESIGN (intended; documented in code).

**Code (Bot.lua:1269-1274):**

```lua
if S.s.cumulative then
    local myTotal = S.s.cumulative[R.TeamOf(seat)] or 0
    if myTotal >= K.SUN_BEL_CUMULATIVE_GATE then
        thSun = thSun + 8
    end
end
```

The bias raises `thSun` (more conservative) when **own** team's
cumulative ≥ 100 — because the **other** team can still Bel us in
Sun (per E-1: only the team <100 may Bel). This is one-directional.

**Verification:** Cross-checked with `R.CanBel`:

```lua
-- Rules.lua:558-559
if mine     >  K.SUN_BEL_CUMULATIVE_GATE then return false end
if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end
```

The CanBel predicate disallows Bel by a team at >100 (line 558)
but permits the OTHER team to Bel us if they are still <100
(line 559's "OTHER team <=100" is reversed-sense: returns false
unless other > 100; so we may bel only if our cumulative <=100
AND other > 100). Wait — re-read: `if otherCum <= 100 then
return false`, meaning Bel allowed only when other side > 100.
That confirms only the team <100 may Bel — and our risk vector
is opp at <100 belling us, so the gate fires correctly when WE
are at >=100.

**Status: CORRECT.** Bias is well-grounded in the CanBel rule.

**Subtle gap:** the threshold is `>=` 100 in the bidding code
(line 1271) but `>` 100 in CanBel (Rules.lua:558). At exactly
100 cumulative, the bot raises `thSun` but the opp can still Bel
(since 100 > 100 is false → CanBel does NOT block). Boundary is
consistent (both forbid Bel at >100 but the bidding code's
`>=100` paranoia at exactly 100 is harmless — adds caution where
the rule technically allows opp Bel when our team is at exactly
100). Documented gap: minor caution-mismatch at the exact 100
boundary.

---

### F-09 (S3-low, NEW) — `bidCardRank == "K"` Ashkal block is restrictive vs. v0.9.1 doc

**Severity:** S3-low (potential calibration; matches doc but worth
noting).

**Repro:** Bid-up card is K of any suit. Bot is M3lm+, in Ashkal
seat (3rd/4th position), partner has bid Hokm. Bot has a hand
strong enough for Ashkal (sun >= 65). The K-block at line 1327
fires unconditionally:

```lua
-- v0.9.1 patch A-2: K is NOT on the allow list — blocks
-- Ashkal at this rank.
if ok and bidCardRank == "K" then ok = false end
```

**Discussion:** The v0.9.1 K-block is per video #31 R1 — bid-up
K is not on the allow-list. **However**, video #31 R7-R10
(re-read in `_transcripts/31_ashkal_detailed_extracted.md`) say
the K-block is for "K-completes-جرية" reasons — when the K
contributes to a meld. If the K does NOT complete a meld
(no Q+K already in hand), the K-block becomes overconservative.

The current code blocks ALL K bid-ups regardless of meld
context. Per the doc, this is correct on the strict allow-list
reading (only 7/8/9/J/Q/singleton-T-without-A is allowed). But
the audit angle is whether a stricter allow-list inadvertently
suppresses Ashkal calls that real Saudi pros would make on
K-no-meld hands.

**Status:** matches doc allow-list. Not a bug. Calibration angle
for future tournament A/B if Ashkal frequency under-fires.

---

### F-10 (CONFIRMS B-Bot-01 F4) — A-5: 3+ Aces correctly skip Ashkal

**Severity:** OK.

**Code (Bot.lua:1379):**

```lua
if ok and aceCount >= 3 then ok = false end
```

After Ashkal is rejected on `aceCount >= 3`, the path falls
through to the direct-Sun branch at line 1423. Since `aceCount
>= 2` satisfies `sunMinShape`, and `sun` after the +15 3-Ace
bonus (`K.BOT_SUN_3ACE_BONUS`) reliably crosses `thSun`, this
falls through cleanly. ✓

The earlier `aceCount >= 4` short-circuit at line 1189 (Carré-A
mandatory Sun) handles the 4-Ace edge separately.

---

### F-11 (CONFIRMS B-Bot-01 F11, OK) — G-4 partner-Hokm suppression scope

**Severity:** OK.

**Code (Bot.lua:1461-1474):**

```lua
do
    local g4_partner = R.Partner(seat)
    local g4_partnerBid = S.s.bids and S.s.bids[g4_partner]
    local g4_partnerBidHokm = g4_partnerBid
        and g4_partnerBid:sub(1, #K.BID_HOKM) == K.BID_HOKM
    if g4_partnerBidHokm then
        if sunMinShape(hand) and sun >= thSun then
            return K.BID_SUN
        end
        return K.BID_PASS
    end
end
```

Partner Hokm in R1 → R2 bot can only Sun-overcall or PASS.
Sun-overcall preserved (different contract type, not a competing
Hokm violation). ✓ Per audit_v0.9.0/11_g4_partner_suppress.md.

**Note:** `partnerBidBonus` and `partnerEscalatedBonus` (lines
945-964 / 1131-1169) are NOT used inside `Bot.PickBid`. They
appear only in the escalation pickers (`escalationStrength` at
line 3554-3567 and `Bot.PickDouble` at 3489-3490). The
"partner-style reads (M3lm-gated)" audit item is satisfied by
G-4 partner-Hokm suppression and the Ashkal partner-Hokm gate,
not by direct partner-bid bonus integration.

---

### F-12 (CONFIRMS D-RT-11.6, DESIGN) — L07 implemented as hard veto vs. soft Saudi convention

**Severity:** DESIGN (per D-RT-11.6).

The Pro-2 PDF L07 rationale ("`اذا اراد ان يحكم اللاعب فلابد من
وجود اكه لديه`" / "if a player wants to call Hokm he must have
an Ace") is a **soft convention** — STRATEGY tier per Phase 1
source-H verdict in `xref_X4_pro2_deal.md`. Real Saudi tables
treat it as a soft default, not a hard veto.

The current implementation (`Bot.lua:798-805`) returns `false`
unconditionally — same severity as the B-4 absolute floor
("no J → no Hokm"), which IS a hard Saudi rule.

Implementing strategy and rules at the same severity is a
documentation/implementation mismatch. The recommended pattern
(D-RT-11 §7) is a strength-penalty bias:

```lua
if Bot.IsM3lm() and not hasAnyAce then
    strength = strength - K.BOT_PICKBID_NO_ACE_PENALTY  -- e.g. 12
end
```

This lets the strongest 5-trump-no-Ace hands still bid Hokm
(strength survives the penalty), while weaker 4-trump-no-Ace
hands fall below threshold and pass — closer to how Saudi pros
actually use the convention.

Not a bug; design observation per the L07 → strategy classification.

---

### F-13 (S3-low, NEW) — Trap-pass detection scope: M3lm-only and R2-only is intentional but underdocumented

**Severity:** S3-low (calibration angle).

**Code (Bot.lua:1252-1254):**

```lua
if round == 2 and Bot.IsM3lm() and Bot.r1WasAllPass then
    r2Base = r2Base - 6
end
```

Two gates: round==2 (R1 cannot fire; verified safe per
B-Bot-01 F7) and `Bot.IsM3lm()` (M3lm+ only). The trap-pass
detector lowers `r2Base` from 36 → 30 (or 38 → 32 with
Advanced bump). With `BID_JITTER=±6`, the effective R2 Hokm
threshold range becomes 24-36 (vs 30-42 normal R2 Advanced).

**Concern:** Basic and Advanced bots do not see this signal. A
Basic bot in R2 after R1-all-pass uses `thHokmR2 ~= 36 ± 6`,
identical to a non-trap-pass R2. Pre-v0.10.0 commentary
(audit_v0.7.1/01_section1_bidding.md G-2) calls trap-pass
detection "an adaptive bid-table model, undocumented" — and the
M3lm-only gating means Basic/Advanced bots are exploitable by
trap-passing humans.

**Status:** intentional per "M3lm-gated since the data only
becomes meaningful when partner-style differentiation is on"
(comment at lines 1250-1251). But the calibration angle is
worth a tournament A/B: does Basic-tier bot under-perform in
trap-pass-followup R2?

Not a bug; documented gap.

---

### F-14 (CONFIRMS B-Bot-01 F1, OK) — L07 gate correctly fires at count>=4 and count==3

**Severity:** OK.

The gate at line 800-802 is structurally correct:

- M3lm+ at count==4, no Ace anywhere → returns false (the half-
  implemented bug pre-v0.10.0).
- M3lm+ at count==4 with trump-A only → `hasAnyAce`=true (set on
  the trump-suit branch at line 792), gate bypassed → line 803
  returns true.
- Basic/Advanced at count==4 with no Ace → gate skipped (not
  M3lm+), line 803 returns true. Preserves pre-v0.10.0 calibration
  for lower tiers.
- All tiers at count==3 still require `hasSideAce` (B-1) — the
  M3lm+ gate is additive (`hasAnyAce` is a strict superset of
  `hasSideAce`; the count==3 path was already enforcing side-Ace
  pre-v0.10.0).

The tier dispatch via `Bot.IsM3lm()` correctly cascades to
Fzloky and Saudi-Master per `Bot.IsM3lm` definition at lines
60-65. ✓

---

### F-15 (CONFIRMS B-Bot-01 F8, OK) — Sun-Bel-fear bias gates on own-team cumulative

**Severity:** OK.

**Code (Bot.lua:1269-1274) — see F-08 above.**

`thSun += 8` when `myTotal >= K.SUN_BEL_CUMULATIVE_GATE (=100)`.
Mirrors the R.CanBel boundary at Rules.lua:558. Bias direction
correct: at 100+ cumulative, opp can Bel us → safer to avoid
Sun bids. ✓

---

### F-16 (S3-low, NEW) — Bel-fear bias is OPPONENT-blind

**Severity:** S3-low (calibration).

The bias at line 1269-1274 reads `myTotal` only. It does NOT
check whether the OPPONENT is at <100 (the only way they can
Bel us). If both teams are at >=100 (rare but possible
late-match), neither side can Bel — the +8 thSun bias becomes
overconservative.

Verifying via R.CanBel:

```lua
-- Rules.lua:558-559
if mine     >  K.SUN_BEL_CUMULATIVE_GATE then return false end  -- can't Bel ourselves
if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end  -- other can't Bel us if other >100
```

Re-reading the second line: `otherCum <= 100 → false`, meaning
Bel allowed only when otherCum > 100. Wait, that's the
otherTeam's view from R.CanBel(myTeam, ...). Let me re-trace.

R.CanBel(team, contract, cum) is "can `team` Bel?". So
`mine = cum[team]`, `otherCum = cum[otherTeam]`. The function
returns true only when `mine <= 100 AND otherCum > 100`. From
opp's perspective belling us: opp_can_bel iff opp_cum <= 100
AND our_cum > 100. So when both teams are at >=100 cumulative,
neither side can Bel — opp cannot Bel us. The +8 bias should
NOT fire.

The bidding code's gate `myTotal >= 100` (line 1271) fires
whenever we're at >=100, regardless of opp's position. So when
both teams >= 100, the bias fires but is unwarranted (opp can't
Bel us either).

**Late-match edge case:** target=152 means matches typically end
before both teams reach 100 simultaneously. But this can occur
in long matches with frequent draws/escalation churn.

**Recommended (NOT applied):** consult opp cumulative too:

```lua
local oppTotal = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
if myTotal >= K.SUN_BEL_CUMULATIVE_GATE
   and oppTotal <= K.SUN_BEL_CUMULATIVE_GATE then
    thSun = thSun + 8
end
```

Minor. Late-match edge.

---

### F-17 (S2-medium, NEW) — `combinedUrgency` cap interaction with Sun-Bel-fear bias

**Severity:** S2-medium (calibration; potential extreme-bid
cliff).

**Setup:** Worst-case stack: M3lm bot, our team at 100 cumulative,
opp at target-15 (137). Bot has a marginal Sun hand
(`sun = 50`, exactly at thSun base).

**Compute:**

- `scoreUrgency`: opp >= target-25 → returns +12 (line 999).
- `matchPointUrgency` (M3lm): opp >= target-15 → +5; me >=
  target-15? me=100 < 137=target-15 → no -5; diff = opp-me =
  37, no diff branch fires. Total +5.
- `combinedUrgency`: 12+5 = 17 → cap at +15 (line 1119-1120).
- `thSun = jitter(50 - 15, 6) = 29 to 41`.
- Sun-Bel-fear: `myTotal=100 >= 100` → `thSun += 8` → 37 to 49.
- Effective thSun: 37-49.

So `sun=50` reliably crosses, and the bot bids Sun.

**The interaction:** the +8 Sun-Bel-fear bias is applied AFTER
the combinedUrgency cap, not subject to it. Combined effect on
thSun in worst case: -15 (urgency) + 8 (Bel-fear) = -7 net. So
thSun ranges from 50-7 ± 6 = 37-49. Conservative side: 49,
which a sun=50 hand still crosses.

But consider opposite extreme: own team at 130, opp at 0:
- `scoreUrgency` (me >= target-25=127): -8 (line 998).
- `matchPointUrgency` (me >= target-15=137? no, 130<137):
  fires nothing on the me-side. opp=0, diff = -130; not in any
  branch. opp >= target-15? 0 < 137, no. Total 0.
- `combinedUrgency`: -8+0 = -8.
- `thSun = jitter(50 - (-8), 6) = jitter(58, 6) = 52-64`.
- Bel-fear: myTotal=130 >= 100 → thSun += 8 → 60-72.
- A sun=50 hand far below threshold. Bot passes Sun.

**Status:** the calibration is intentional and the cap+bias
interaction is sane. Documenting the magnitude in case future
calibration changes break the implicit assumption.

**One subtle finding:** the `r2Base = r2Base - 6` trap-pass
adjustment at line 1253 IS subject to `BID_JITTER = ±6`. With
trap-pass + Advanced bump, R2 thHokm range is `38 - 6 ± 6`
= 26-38. With urgency=+15 (max desperate), R2 thHokm = `38 - 6
- 15 ± 6` = 11-23. **A bot facing trap-pass + extreme score
desperation can bid Hokm at strength as low as 11.** That's
sub-marginal (a hand with no J-of-trump can't even bid; with J
+ 2 trumps + side-A, strength is around 27 from suitStrengthAsTrump).
So while the threshold theoretically reaches 11, real hands at
that strength fail `hokmMinShape`. No actual bid hazard. ✓

---

### F-18 (S2-medium, NEW) — `Bot.IsM3lm()` early-load asymmetry between hokmMinShape and PickBid

**Severity:** S2-medium (init order edge case).

**Code (Bot.lua:800):**

```lua
if Bot.IsM3lm and Bot.IsM3lm() and not hasAnyAce then
    return false
end
```

`hokmMinShape` defensively checks `Bot.IsM3lm` exists before
calling it. This is the correct guard against early-load order
issues where `Bot.IsM3lm` might be nil if Bot.lua hasn't fully
loaded.

**Code (Bot.lua:1252):**

```lua
if round == 2 and Bot.IsM3lm() and Bot.r1WasAllPass then
```

`Bot.PickBid` at line 1252 calls `Bot.IsM3lm()` directly without
the existence guard. By the time PickBid is callable, Bot.lua
has fully loaded so `Bot.IsM3lm` exists — but the inconsistency
with `hokmMinShape` at line 800 is structurally awkward (and
would fail differently if the load order ever changed).

Same pattern at line 1407, 1023, 1056. All assume `Bot.IsM3lm`
exists.

**Status:** functionally safe given current load order. The
defensive guard at line 800 may be over-cautious, OR the
non-defensive calls elsewhere may be under-cautious — they don't
agree. Recommended: standardize on one or the other.

---

### F-19 (S3-low, NEW) — `aceCount >= 4` early-return at line 1189 bypasses Sun-Bel-fear bias

**Severity:** S3-low (intended; documenting the interaction).

**Code (Bot.lua:1188-1189):**

```lua
local aceCount, mardoofaCount = aceCountAndMardoofa(hand)
if aceCount >= 4 then return K.BID_SUN end
```

The Carré-of-Aces (400) early-return at line 1189 fires BEFORE
the Sun-Bel-fear bias is computed (lines 1269-1274). So even at
own-team cumulative >= 100, a Carré-A hand bids Sun
unconditionally.

**Justification:** doc-confirmed mandatory bid (decision-trees.md
S-4 Definite, video 25/32/38). 4 Aces = 200 raw × 2 Sun
multiplier = 400 effective. Bel-fear is moot — even a failed
Sun-Bel'd 400 contract is offset by the rarity (~0.1% of deals)
and the magnitude of the swing when made (+260 raw vs ~-260
raw). EV-positive on average.

**Status:** intentional. Documenting the interaction.

---

### F-20 (S3-low, NEW) — Ashkal-eligible bot with high `sun` may double-commit on partner's marginal Hokm

**Severity:** S3-low (calibration angle).

**Setup:** Bot in seat 3 (dealer's left). Partner (in seat 1, the
first bidder) bid Hokm with marginal strength (e.g.
`thHokmR1=38` after urgency, partner's strength was ~40). Bot
has Sun-strong hand (`sun = 70`, well above `thAshkal=65`).
Bid-up rank not blocking (e.g. 8 of any suit).

**Decision:** at line 1408, bot calls Ashkal. Ashkal converts
contract to Sun with PARTNER as declarer. But **partner's hand
is Hokm-shape, not Sun-shape**. With partner already having
committed Hokm at strength ~40, partner's Sun strength may be
much lower (maybe `sun = 35-40` since side-Aces and length, the
core of Hokm strength, don't transfer to Sun strength).

**Net effect:** Ashkal hands a likely-failing Sun contract to
partner, even though bot's sun=70 in own hand was strong.

**Mitigation present:** A-6 (line 1388-1390) blocks Ashkal at
`sun >= 85` (direct-Sun pivot — bot bids Sun itself). The
65-84 range is the Ashkal sweet spot.

**Concern:** within 65-84, partner's marginal Hokm bid is the
"`Ashkal handed weak contract to partner`" failure mode. The
current code does not gate on partner's Hokm strength — it
treats partner's Hokm as a Sun-strength signal worth +15
(per `partnerBidBonus`, but that's not used in PickBid).

**Suggested refinement (NOT applied):** in M3lm+ tier, only
Ashkal when partner's Hokm is on the FLIPPED suit (R1). If
partner Hokm-bid the flipped suit, that's a strong-trump signal.
If partner bid a different suit (R2), the Hokm is more marginal
— partner couldn't even bid the flipped suit, suggesting weaker
hand.

**Status:** documented gap; calibration-tier issue. The R1
Ashkal block at line 1287-1410 IS structurally R1-only (line
1276 starts the `if round == 1 then` block), so partner's bid
is necessarily an R1 Hokm-on-flipped — partner did bid the
flipped suit. So this concern is moot for the current code.
✓ Confirmed by tracing.

---

### F-21 (S3-low, OK) — Sun-strength scoring matches doc

**Severity:** OK.

`sunStrength` (Bot.lua:882-927):
- Pip values: A=11, T=10, K=4, Q=3, J=2, 9/8/7=0. Matches
  `K.POINTS_PLAIN`. ✓
- Length walk bonus: +6/card beyond 4 in suits with a top card.
  Heuristic, not in doc. Documented in code as 13th-bot-audit
  fix.
- AKQ stopper triple: +8. Heuristic; not in doc.
- Distribution penalty (Advanced+): -10/suit if count<2 or no
  honors. Cap 18.

The S-3 (3+ Aces +15) and S-8 (mardoofa pair +5, cap 2 pairs)
bonuses are layered ON TOP of `sunStrength` at lines 1216-1218.
Combined effect:
- 3-Ace hand without AKQ: ~33 (3×11) + 15 (S-3) = ~48 — clears
  thSun=50 with median jitter. ✓ per CHANGELOG.md:2293-2295
  Wave-2 audit calibration.
- 1-Ace + mardoofa: 11 (A) + 10 (T) + 5 (S-8) = 26 — way below
  thSun. Doesn't cross even with -urgency. ✓ correctly leaves
  Sun bidding to the 2+Ace shapes.

---

### F-22 (S3-low, NEW) — `suitStrengthAsTrump` weights diverge from raw pip values intentionally

**Severity:** S3-low (informational; documented in code).

`suitStrengthAsTrump` (Bot.lua:706-740):
- J=20, 9=14, A=11, T=10, K=4, Q=3 — matches
  `K.POINTS_TRUMP_HOKM`.
- 8=2, 7=2 — DEVIATION from K.POINTS_TRUMP_HOKM (which has 0/0).
  Per CHANGELOG comment at lines 720-724: "13th-bot-audit fix:
  8 and 7 of trump are worth 2 each per Saudi Hokm point
  convention."

But the K constants table has 0/0 for 8/7 of trump (per pip
values in Constants.lua). The "Saudi Hokm point convention" cited
in the comment refers to a calibration tweak, not a literal pip
value. The function name `suitStrengthAsTrump` suggests pip
counting, but the implementation is strength-eval.

**Status:** intentional. Per B-Bot-01 F14 — calibration tweak,
not a correctness bug. The strength score is a heuristic,
threshold-aware rating — not a literal pip count.

---

### F-23 (S3-low, NEW) — `R.Partner` and `R.TeamOf` derefs are unguarded throughout

**Severity:** S3-low (latent nil-safety; not realistic in
practice).

Examples:
- Line 1138-1139: `local p = R.Partner(seat) ... contract.bidder`
  guards on `p` and `contract.bidder` separately.
- Line 1153-1156: `R.TeamOf(p)` and `R.TeamOf(contract.bidder)`
  guarded.
- Line 1229: `R.TeamOf(seat)` unguarded.
- Line 1270: `R.TeamOf(seat)` unguarded.
- Line 1293: `R.Partner(seat)` unguarded.
- Line 1462: `R.Partner(seat)` unguarded.

In practice `R.Partner` and `R.TeamOf` are pure deterministic
functions of seat (1-4), no S.s deref, no failure modes. The
unguarded calls are safe.

**Status:** OK; no action needed.

---

### F-24 (DESIGN, NEW) — Trap-pass detection sign convention

**Severity:** DESIGN (intent vs. mechanism).

The comment at line 1247-1251 reads:

> "Audit Tier 4 (B-80 / H-10): trap-pass detection. When R1 was
> all-pass (every seat declined the flipped suit), the table is
> weak overall — R2 thresholds should drop slightly so we don't
> under-bid back into a redeal."

But the rationale "table is weak overall" is the _opposite_ of
the wave8 C2 finding rationale at `wave8_C2_findings.md:64`:

> "This prevents the bot from being exploited by R1 trap-passers
> who open R2 with a strong hand the bot should have matched."

The two readings are mathematically compatible: an all-pass R1
COULD be a generally weak field (everyone passed because
everyone has weak hands), OR it COULD be a trap-pass (one or
more humans is hiding a strong hand to bid in R2). In either
case, lowering R2 threshold is the correct response — the bot's
own R2 hand is more competitive against either weak field or
trap-passer.

**Status:** mechanism-correct, narrative slightly muddled. The
code does the right thing for both interpretations. ✓

---

### F-25 (S3-low, NEW) — Ashkal `Bot.IsAdvanced()` check at line 1396 ALSO blocks M3lm

**Severity:** S3-low (intended cascade; documenting).

**Code (Bot.lua:1396-1404):**

```lua
if ok and Bot.IsAdvanced() and bidCardSuit then
    local sStr, sCnt = suitStrengthAsTrump(hand, bidCardSuit)
    local hasJflip = false
    for _, c in ipairs(hand) do
        if C.Rank(c) == "J" and C.Suit(c) == bidCardSuit then
            hasJflip = true; break
        end
    end
    if hasJflip or sCnt > 2 then ok = false end
end
```

Since `Bot.IsM3lm()` and `Bot.IsFzloky()` cascade through to
true → also `Bot.IsAdvanced()` returns true. So the
"Advanced check" applies at all M3lm+ tiers. ✓ Per the
"strictly extends" hierarchy.

A Basic bot (no flag) skips this check — Basic Ashkal is more
permissive (no flipped-suit-J or count check).

---

### F-26 (S3-low, NEW) — `bestSuit` tie-break at line 1488 picks first equal-score suit

**Severity:** S3-low (deterministic but potentially calibration-
sensitive).

**Code (Bot.lua:1488):**

```lua
if s > bestScore then bestSuit, bestScore = suit, s end
```

Strict `>` means ties go to the first suit in `K.SUITS` order
(per line 1482's iteration order). If two suits have identical
strength, the bot consistently picks the suit listed first in
`K.SUITS`. This is deterministic but cards across suits don't
have intrinsically different EV — the Saudi convention has no
"prefer Spades over Hearts" rule. Determinism here is a side
effect, not a designed bias.

**Status:** OK; no observable bug. Calibration angle if a
specific suit ordering were ever found to bias matches.

---

### F-27 (S2-medium, NEW) — Round-2 Hokm fallback skips Sun-Bel-fear bias for Hokm-only path

**Severity:** S2-medium (asymmetric calibration).

The Sun-Bel-fear bias at lines 1269-1274 raises `thSun` by +8
when own team >=100. **There is no analogous Hokm bias.** A
Hokm bid by our team at 100+ cumulative also carries Bel risk
(opp at <100 may Bel us in Hokm) — but the code does not nudge
`thHokmR1`/`thHokmR2` upward.

**Why is this asymmetric?** Sun's 2× multiplier means a Bel'd
failed Sun is 4× the raw, vs Hokm's 2× for Bel'd failed Hokm.
So the Sun bias is calibrated stronger. But Hokm-Bel is still
real exposure — at thHokm ~38, a failed Bel'd Hokm = 16 raw × 2
= 32 game points lost. Not negligible.

**Status:** intentional asymmetry per B-7 / S-7 doc rationale.
But worth explicit consideration in a future calibration round
— a small +3 bias on `thHokm` at cum>=100 may improve EV.

Not actionable now; calibration angle.

---

### F-28 (DESIGN, OK) — `BID_JITTER = ±6` applied to all three thresholds independently

**Code (Bot.lua:1255-1257):**

```lua
local thHokmR1 = jitter(r1Base    - urgency, BID_JITTER)
local thHokmR2 = jitter(r2Base    - urgency, BID_JITTER)
local thSun    = jitter(TH_SUN_BASE - urgency, BID_JITTER)
```

Three independent jitter calls with jitter amplitude ±6. So
two bots dealt similar hands at the same score state still pick
different bids in some fraction of cases.

**Concern from .swarm_plan.md A-04:** does the ±6 amplitude
create or hide a "predictable cliff"? With urgency at maximum
+15, R2 thHokm range is `36 - 15 ± 6` = 15-27 (Basic) or `38 -
15 ± 6` = 17-29 (Advanced). The 12-point spread spans
"weak-marginal" to "marginal-strong" boundary, ensuring
non-deterministic bids in marginal cases.

**Status:** intentional design. ✓ Per the function comment at
lines 24-34 of Bot.lua: "Originally these were tuned for
'professional' bot bidding ... Now sensible middle: bot needs
J+kicker, or 9+Ace, or A+T+K with length."

---

### F-29 (S3-low, NEW) — `K.BOT_ASHKAL_TH or 65` fallback at line 1407 is dead

**Severity:** S3-low (cosmetic; resilience pattern).

**Code (Bot.lua:1407):**

```lua
local thAshkal = jitter(K.BOT_ASHKAL_TH or 65, BID_JITTER)
```

`K.BOT_ASHKAL_TH = 65` is unconditionally set in
`Constants.lua:309`. The `or 65` fallback would only fire if
`K.BOT_ASHKAL_TH` were nil, which can only happen if Constants
hasn't loaded — but PickBid is called from MaybeRunBot which
runs after addon-load. So the fallback is dead.

**Status:** harmless defensive idiom. No action needed.

---

### F-30 (S2-medium, NEW) — A-2 v0.9.2 #60 patch enforces "singleton-T" twice but doesn't enforce "no own-A"

**Severity:** S2-medium (allow-list completeness).

The A-2 doc allow-list (per
`_transcripts/31_ashkal_detailed_extracted.md`) reads:
"singleton-T-without-A". The "without-A" part is enforced at
A-4 (line 1349-1355): bid-up T + own A in same suit → block.

**But:** the singleton-T check is enforced TWICE (lines 1336-
1342 and 1366-1372 — see F-03), and the "without-A" check is
enforced once. The redundancy at F-03 is dead code. The
"without-A" check is only checking the BID-UP suit's A, not
any A.

**Re-reading A-4 (line 1349-1355):**

```lua
if ok and bidCardRank == "T" and bidCardSuit then
    for _, c in ipairs(hand) do
        if C.Rank(c) == "A" and C.Suit(c) == bidCardSuit then
            ok = false; break
        end
    end
end
```

This blocks Ashkal when bot holds A of the SAME suit as the bid-
up T. The doc rationale: "A+T mardoofa pair preserved by Hokm;
Ashkal converts to Sun and breaks the cover."

What about T-no-own-A but holding multiple Aces in OTHER suits?
The A-5 check (`aceCount >= 3`) at line 1379 catches the 3+ Aces
case. The 2-Ace case (e.g. bid-up T-of-Hearts, bot has A♣ +
A♦ but no A♥): A-4 doesn't fire (no A♥), A-5 doesn't fire (only
2 Aces), singleton-T check passes (only 1 T total), all other
checks pass. Bot calls Ashkal.

Per doc, is this correct? The doc says singleton-T-without-A,
where "A" means same-suit-A (else A-5 wouldn't be a separate
rule). 2-Ace + singleton-T-no-same-suit-A is allowed Ashkal per
doc. ✓ Correct.

**Status:** OK; verified against doc.

---

## Threshold computation summary

For reference, the thresholds at v0.10.2 with all M3lm+ tier
flags on:

| threshold | base | adjustment | jitter | effective range |
|---|---|---|---|---|
| `thHokmR1` | 42 | -urgency (-15..+15) | ±6 | 21..63 |
| `thHokmR2` | 36 | Advanced bump → 38 | ±6 | (38 - urgency) ± 6 = 17..59 |
| `thHokmR2` (trap-pass) | 38 - 6 = 32 | -urgency | ±6 | 11..53 |
| `thSun` | 50 | -urgency, +8 if cum>=100 | ±6 | 27..71 |
| `thAshkal` | 65 | none (no urgency) | ±6 | 59..71 |

Trap-pass at extreme urgency reaches as low as `thHokmR2 = 11`,
but `hokmMinShape` (J + count>=3 + side-A or count>=4) puts a
hard structural floor at strength ~27-30 (e.g. J + 3 small
trumps + 1 side-A = 20+5+5+5+8=43). So a threshold of 11 is
unreachable in practice. ✓ See F-17 for full trace.

---

## Severity table

| ID | Severity | Issue | Confidence |
|---|---|---|---|
| F-01 | **S2-medium** | L07 hard veto blocks strong sweep hands at M3lm+ | HIGH |
| F-02 | **S2-medium** | R1+R2 cascade fail at M3lm+ for Aceless Hokm-strong | HIGH |
| F-03 | S3-low | Duplicate T-cardinality check (dead code) | HIGH |
| F-04 | S3-low | `S.s.bids` deref at 1194 unguarded | HIGH |
| F-05 | S3-low | `aceCountAndMardoofa` walks hand twice | INFO |
| F-06 | DESIGN | Ashkal `bidPos>=3` mirrors host correctly | OK |
| F-07 | S3-low | R2 missing `anySun` consultation (cousin of G-4) | MED |
| F-08 | DESIGN | Bel-fear bias asymmetric (own-team only) | OK |
| F-09 | S3-low | K bid-up Ashkal block possibly overconservative | LOW |
| F-10 | OK | A-5 3+Aces skips Ashkal correctly | HIGH |
| F-11 | OK | G-4 partner-Hokm suppression scope correct | HIGH |
| F-12 | DESIGN | L07 implemented as hard veto vs. soft convention | DESIGN |
| F-13 | S3-low | Trap-pass M3lm+only cleanup needed for Basic/Advanced | INFO |
| F-14 | OK | L07 gate fires correctly at count>=4 and ==3 | HIGH |
| F-15 | OK | Sun-Bel-fear gate boundary matches CanBel | HIGH |
| F-16 | S3-low | Bel-fear bias opponent-blind at exactly 100 boundary | LOW |
| F-17 | **S2-medium** | combinedUrgency cap + Bel-fear stack interaction | MED |
| F-18 | **S2-medium** | `Bot.IsM3lm()` defensive guard inconsistency | MED |
| F-19 | S3-low | Carré-A early-return bypasses Bel-fear bias | OK |
| F-20 | S3-low | Ashkal-eligible high-sun double-commit (R1-only, moot) | OK |
| F-21 | OK | Sun-strength scoring matches doc | HIGH |
| F-22 | S3-low | suitStrengthAsTrump 8/7=2 deviation from pip values | OK |
| F-23 | S3-low | `R.Partner`/`R.TeamOf` unguarded derefs | OK |
| F-24 | DESIGN | Trap-pass narrative-vs-mechanism consistency | OK |
| F-25 | S3-low | Ashkal Advanced check cascades through M3lm+ | OK |
| F-26 | S3-low | bestSuit tie-break first-suit bias | OK |
| F-27 | **S2-medium** | R2 Hokm fallback skips Bel-fear bias asymmetry | MED |
| F-28 | DESIGN | BID_JITTER=±6 amplitude calibration | OK |
| F-29 | S3-low | `K.BOT_ASHKAL_TH or 65` fallback dead | OK |
| F-30 | OK | A-2 v0.9.2 #60 singleton-T-without-A correct | HIGH |

---

## Summary by audit-scope item

1. **R1 vs R2 bid logic**: structurally sound. R1 walks Ashkal
   eligibility → direct Sun → Hokm-on-flipped → PASS. R2 walks
   partner-Hokm suppression → best-suit Hokm search → Sun-vs-
   Hokm tie-break → Hokm fallback → PASS. ✓ See F-11, F-07.

2. **Pass / Hokm / Sun / Ashkal decision tree**: All gates wired
   per cited specs. Carré-A short-circuit at top, then Ashkal
   (R1-only), then direct Sun, then Hokm. Fallback paths to
   PASS work correctly. ✓

3. **Threshold computation**: BOT_HOKM_TH_R1=42 base, R2=36
   base, Advanced bump R2 to 38 (=R1-4), trap-pass R2 -=6,
   urgency -15..+15, jitter ±6, Sun-Bel-fear +8 on Sun only.
   Effective ranges in summary table above. ✓ Per F-15, F-17.

4. **v0.10.0 X4/L07 hasAnyAce gate at hokmMinShape**: correctly
   wired but **2 confirmed S2-medium bugs (D-RT-11.3, D-RT-11.4)
   cascade fail at M3lm+** when Aceless 5-trump hand cannot bid
   Hokm in either round. See F-01, F-02. Mitigation candidates
   in D-RT-11 §6 (sweep-strong escape, penalty-bias, Saudi-
   Master-only).

5. **v0.5.8 patches A-3, A-4, A-5, A-6**: all four enforced.
   See F-10 (A-5), and A-3/A-4/A-6 traces above. ✓

6. **v0.9.1 A-2 K-block**: enforced at line 1327. See F-09 for
   calibration angle (no functional bug).

7. **v0.9.2 #60 doubleton-T-no-A gate**: enforced — but DUPLICATED
   at lines 1336-1342 AND 1366-1372. See F-03. Cosmetic dead-code
   redundancy.

8. **Ashkal seat eligibility (3rd/4th in turn order)**: bot's
   `bidPos >= 3` check at line 1306 mirrors host's `bidPosition
   >= 3` at State.lua:1755. ✓ See F-06.

9. **Sun-Bel-fear bias when own team >=100**: enforced at lines
   1269-1274. ✓ See F-08, F-15. Asymmetric — F-27 notes Hokm
   has no analogous bias.

10. **Partner-style reads (M3lm-gated)**: implemented via
    G-4 partner-Hokm suppression (R2 only) and Ashkal partner-Hokm
    gate (R1 only). `partnerBidBonus` and `partnerEscalatedBonus`
    are NOT used in PickBid — they're escalation-picker helpers.
    ✓ See F-11.

11. **Trap-pass detection**: correctly gated at round==2 +
    Bot.IsM3lm() + Bot.r1WasAllPass at line 1252-1254. R1 cannot
    fire (flag is reset to false in `_OnDealPhase` at
    State.lua:788 and only set true in HostBeginRound2 at
    State.lua:1844-1846). ✓ See F-13, F-24.

---

## Confidence

**HIGH** for F-01, F-02, F-03, F-04, F-10, F-11, F-14, F-15, F-21,
F-30 (direct code reads, comparable to existing audits).

**MEDIUM** for F-07, F-17, F-18, F-27 (logical inferences from
code paths plus host-side rules; would benefit from live-game
scenarios or unit tests).

**LOW** for F-09, F-16, F-20 (single-source rules / late-match
edges where empirical observation would be needed).

**OK / INFO / DESIGN** flags are documentation, not severity.

---

## Cross-references

- `Bot.lua:1175-1514` — full `PickBid` body
- `Bot.lua:706-740` — `suitStrengthAsTrump`
- `Bot.lua:782-806` — `hokmMinShape` (X4/L07 fix at lines 800-802)
- `Bot.lua:816-832` — `sunMinShape`
- `Bot.lua:882-927` — `sunStrength`
- `Bot.lua:945-964` — `partnerBidBonus` (NOT used in PickBid)
- `Bot.lua:986-1035` — `scoreUrgency`, `opponentUrgency`
- `Bot.lua:1055-1099` — `matchPointUrgency`
- `Bot.lua:1117-1122` — `combinedUrgency`
- `Bot.lua:1131-1169` — `partnerEscalatedBonus` (NOT used in PickBid)
- `Bot.lua:1244-1257` — threshold computation
- `Bot.lua:1252-1254` — trap-pass detection (B-80/H-10)
- `Bot.lua:1269-1274` — Sun-Bel-fear bias (B-7/S-7)
- `Bot.lua:1287-1410` — Ashkal eligibility & allow-list (R1)
- `Bot.lua:1316` — A-3 (bid-up A blocks Ashkal)
- `Bot.lua:1327` — v0.9.1 A-2 K-block
- `Bot.lua:1336-1342, 1366-1372` — v0.9.2 #60 singleton-T (DUPLICATED)
- `Bot.lua:1349-1355` — A-4 (T + own-A in same suit blocks)
- `Bot.lua:1379` — A-5 (3+ Aces skip Ashkal)
- `Bot.lua:1388-1390` — A-6 (sun >= 85 → direct Sun pivot)
- `Bot.lua:1396-1404` — Advanced check (Jflip / count>2)
- `Bot.lua:1407-1408` — final Ashkal threshold check
- `Bot.lua:1423` — direct Sun (R1)
- `Bot.lua:1431-1445` — Hokm-on-flipped (R1)
- `Bot.lua:1461-1474` — G-4 partner-Hokm suppression (R2)
- `Bot.lua:1481-1490` — best-suit Hokm search (R2)
- `Bot.lua:1498-1509` — Sun-vs-Hokm tie-break (B-5)
- `Bot.lua:1510-1513` — Hokm fallback / PASS
- `Constants.lua:309` — `BOT_ASHKAL_TH = 65`
- `Constants.lua:315-322` — Sun bonuses, Belote, B-5 margin, A-6 pivot
- `Constants.lua:329` — `SUN_BEL_CUMULATIVE_GATE = 100`
- `Rules.lua:558-559` — `R.CanBel` boundary check
- `State.lua:788` — `r1WasAllPass` reset
- `State.lua:1681-1823` — `HostAdvanceBidding` (Ashkal seat enforcement)
- `State.lua:1825-1857` — `HostBeginRound2` (`r1WasAllPass` snapshot)
- `B-Bot-01_pickBid.md` — broader review (companion)
- `D-RT-11_hokm_ace_tier.md` — red-team on L07 gate
- `audit_v0.9.0/11_g4_partner_suppress.md` — G-4 wiring audit
- `audit_v0.9.0/16_section1_now.md` — Section 1 tier-snapshot
- `audit_v0.9.0/60_a2_singleton_t.md` — v0.9.2 #60 cardinality fix
- `review_v0.10.0/_phase2_xref/xref_X4_pro2_deal.md` — L07/L08/L09 source-H
- `wave8_C2_findings.md:64` — trap-pass rationale
- `docs/strategy/decision-trees.md` Section 1 — operational rules
- `docs/strategy/_transcripts/25_when_bid_sun_extracted.md` — Sun rules
- `docs/strategy/_transcripts/26_when_bid_hokm_extracted.md` — Hokm rules
- `docs/strategy/_transcripts/28_bid_rules_extracted.md` — R3 Sun-overcalls-Hokm
- `docs/strategy/_transcripts/31_ashkal_detailed_extracted.md` — Ashkal R1-R30

---

## Suggested follow-ups (NOT applied per prompt)

1. **F-01/F-02 mitigation:** soften L07 hard veto. Three options
   (D-RT-11 §6): sweep-strong escape clause for `count >= 5 and
   hasJ and has9`; penalty-based bias instead of veto; or
   Saudi-Master-only enforcement. **Recommended priority: HIGH**
   — this is the only S2-medium pair with clear EV impact.

2. **F-03 cleanup:** consolidate the duplicated T-cardinality
   check at lines 1336-1342 and 1366-1372 (delete one).
   **Recommended priority: LOW** — cosmetic, no functional bug.

3. **F-04 cleanup:** add `S.s.bids and` guard at line 1194.
   **Recommended priority: LOW** — defensive consistency.

4. **F-07 fix:** add `anySun` consultation in R2 to suppress
   wire-violation HOKM-over-Sun (cousin of G-4, video #28 R3).
   **Recommended priority: MEDIUM** — wire violation visible
   in logs even though host silently drops.

5. **F-17 calibration test:** run headless A/B at extreme
   score states (cum >= 130 / opp at target-15) to verify
   thSun + Bel-fear stack does not cause unintended cliff
   suppression.

6. **F-18 standardization:** decide on guarded vs unguarded
   `Bot.IsM3lm` calls. Update all sites consistently.

7. **F-27 calibration:** consider symmetric Hokm-Bel-fear bias
   (`thHokm += 3` at cum >= 100) for completeness with Sun.

8. **Regression test pin:** B-Bot-01 §F11 already noted no
   regression test exists for G-4 partner-Hokm suppression.
   Mirror with Sun-overcall variant (F-07).

9. **Tournament A/B (HIGH PRIORITY):** D-RT-11 §6 recommends
   100-200 deal seeds comparing v0.10.0 M3lm+ vs v0.9.x M3lm+
   on Hokm-bid frequency, Sun-bid frequency, match-win rate,
   and average margin. The L07 cascade (F-01/F-02) is the
   most likely calibration regression since v0.10.0; A/B
   testing is the primary diagnostic.
