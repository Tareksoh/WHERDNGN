# D-RT-19 — Red-team v0.10.2 M3 false-AKA detection

**Target:** v0.10.2 M3 host-side false-AKA validator in `S.ApplyPlay`
(`State.lua:1224-1265`).

**Verdict:** Mechanically the M3 check works for the **explicit MSG_AKA →
same-trick lead** path. **Five exploitable / functional defects** found,
two of which are mid/high severity (silently-allowed false implicit AKA;
banner-clear races on a synchronous wire flow). One Sun-contract
input-frame issue is host-blocked but client-blocking is missing.

---

## Code under review (verbatim)

```lua
-- State.lua:1238-1265
if not illegal and s.isHost and s.akaCalled
   and s.akaCalled.seat == seat
   and #s.trick.plays == 0  -- this play IS the lead
   and s.contract and s.contract.type == K.BID_HOKM then
    local cardSuit = card:sub(2, 2)
    if cardSuit == s.akaCalled.suit then
        local cardRank = card:sub(1, 1)
        local order = { "A", "T", "K", "Q", "J", "9", "8", "7" }
        s.playedCardsThisRound = s.playedCardsThisRound or {}
        local valid = false
        for _, r in ipairs(order) do
            if r == cardRank then valid = true; break end
            if not s.playedCardsThisRound[r .. cardSuit] then
                break  -- a higher rank is still out: false claim
            end
        end
        if not valid then
            illegal = true
            illegalWhy = "false AKA"
            s.akaCalled = nil
        end
    else
        -- AKA on suit X but lead is suit Y → trivially false.
        illegal = true
        illegalWhy = "false AKA"
        s.akaCalled = nil
    end
end
```

`HostResolveTakweesh` then catches `.illegal` for ALL plays
(`Net.lua:2150-2162`):

```lua
local function scanIllegal(plays)
    for _, p in ipairs(plays or {}) do
        if p.illegal and R.TeamOf(p.seat) ~= callerTeam then return p end
    end
end
local foundIllegal
for _, t in ipairs(S.s.tricks) do
    foundIllegal = scanIllegal(t.plays)
    if foundIllegal then break end
end
if not foundIllegal and S.s.trick then
    foundIllegal = scanIllegal(S.s.trick.plays)
end
```

Reason string `"false AKA"` propagates to the Takweesh banner and
chat printout (`Net.lua:2280, 2307, 2104`) — visible to the user.

---

## 1) HighestUnplayedRank correctness (non-trump suits) — PASSES

The order array `{"A","T","K","Q","J","9","8","7"}` is the plain
(non-trump) ranking. The check **explicitly gates on
`cardSuit == s.akaCalled.suit`** AND **only triggers in HOKM**
(`s.contract.type == K.BID_HOKM`). AKA is by definition non-trump only
(`Bot.PickAKA` rejects `su == trump` at line 3282; M3's gate doesn't
re-check that the AKA suit is non-trump but `_OnAKA` accepts whatever
the wire sends — see Issue 5b).

`s.playedCardsThisRound` is rebuilt on resync from `s.tricks +
s.trick.plays` (per the `TRANSIENT_FIELDS` comment at `State.lua:213-217`
and the reset at `State.lua:514-517`), and is updated by every
`ApplyPlay` (line 1276-1277). The set keys by 2-char card string —
`"AS"`, `"TH"`, etc. — matching the lookup `r .. cardSuit`.

The walk semantics: walk down the order array, stopping at either the
played card's own rank (valid=true) OR the first higher rank that has
**not** yet been played (valid=false). This correctly identifies the
"highest unplayed rank of the suit." **No off-by-one.**

**Note (deliberate divergence from `S.HighestUnplayedRank`):** the M3
check **inlines** the rank order rather than calling
`S.HighestUnplayedRank(cardSuit)`. Since `S.HighestUnplayedRank` is
trump-aware (`State.lua:1370-1374`), calling it would yield
TRUMP_HOKM_ORDER for the trump suit — but M3 only cares about non-trump
AKAs, so an inlined plain-rank walk is fine. The two stay in sync as
long as the AKA invariant (non-trump only) holds. **Recommendation:**
add a defensive comment stating M3 deliberately uses plain ranking
because the AKA suit is non-trump by construction; if a future patch
ever permits trump AKAs, this inline walk silently mis-rates.

**Severity:** none. Mechanism is correct.

---

## 2) Race: AKA called and immediately led (banner clearance async) — PASSES

The AKA-then-lead flow is host-side **synchronous** in both code paths:

**Bot path (Net.lua:4096-4113):**
```lua
if B.Bot.PickAKA then
    local akaSuit = B.Bot.PickAKA(seat, card)
    if akaSuit then
        S.ApplyAKA(seat, akaSuit)        -- sets S.s.akaCalled = {seat, suit}
        N.SendAKA(seat, akaSuit)
    end
end
local leadBefore = ...
S.ApplyPlay(seat, card)                  -- reads S.s.akaCalled (set above)
N.SendPlay(seat, card)
```

The host calls `ApplyAKA` → `ApplyPlay` synchronously in the same
function, with no scheduler tick between them. `s.akaCalled` is set by
`ApplyAKA` (`State.lua:1446`) before `ApplyPlay` reads it (line 1238).
Wire ordering (MSG_AKA → MSG_PLAY) follows.

**Human-LocalPlay path (`Net.lua:2027-2057`):** The human's AKA must
have been set via `LocalAKA` BEFORE leading (per the v0.9.0 L4 fix at
`Net.lua:2358-2363`: AKA is rejected when `#S.s.trick.plays > 0`). The
sequence is:

1. Human clicks AKA → `LocalAKA` → `ApplyAKA(localSeat, suit)` →
   `SendAKA`.
2. Human clicks card → `LocalPlay` → `ApplyPlay`.

Step 1 already mutated `s.akaCalled` host-side before step 2 fires.
**Wire-level race:** an attacker could send MSG_AKA and MSG_PLAY in
opposite order — but the wire AKA only updates the receiver's banner
(`_OnAKA → ApplyAKA`), not the host's authoritative validation. The
host already mutated its own `s.akaCalled` in step 1. **No race.**

**Severity:** none in the supported flow. (Issue 7 below covers
multi-AKA where multiple seats race.)

---

## 3) Implicit AKA via bare-A — DOES NOT TRIGGER M3 (intentional, but documentation gap)

`Bot.PickAKA` explicitly returns `nil` for rank == "A"
(`Bot.lua:3289`):

```lua
if r == "A" then return nil end
```

This is the v0.5.16 S6-10(c) "implicit AKA" optimization: leading bare
A in non-trump is itself an AKA signal, so no MSG_AKA is broadcast. The
**receiver-side** detection lives in `pickFollow` at `Bot.lua:2521-2532`
and gates on `lead.card == "A?"` from partner's first play.

**Implication for M3:** M3's gate is `s.akaCalled.seat == seat`, but
implicit AKA never sets `s.akaCalled`. **A false implicit AKA is
therefore not catchable.**

This is theoretically OK because leading bare-A is already true: the
Ace is the highest plain-rank card by definition, so the implicit
claim ("I have the boss") is trivially valid as long as the player
holds the lead-Ace. **However:**

### 3a) Hostile-client implicit-AKA exploit — REAL HOLE

A malicious client can send `MSG_PLAY: AS` from a hand the host doesn't
authoritatively know (e.g., a non-host bot via spoofing — but `_OnPlay`
already validates against `hostHands` at `State.lua:1214-1219`, so this
path is closed).

**However:** in a HOST-side bot scenario, a buggy
`Bot.PickPlay` could lead an Ace AS A FALSE IMPLICIT AKA when the bot
holds it, yet the partner-side `pickFollow` would activate
implicit-AKA semantics (don't ruff) — which **leaks a real
coordination signal**. Partner suppresses ruff, opps capture the
trick. No false-AKA detection fires because no MSG_AKA ever flew.

This is by design (the implicit case is true by definition: leading
the Ace IS holding the boss, since no higher non-trump rank exists).
The **risk is partner action on stale-Ace** when the Ace was already
played in an earlier trick — but you can't lead a card you don't hold,
and the host's `IsLegalPlay` validates `card in hand`. So implicit AKA
**cannot be falsified** in a normal flow.

**Severity:** none. The implicit-AKA invariant is self-validating.
**Recommendation:** add a comment in M3 explicitly stating "implicit
AKAs are self-validating because Ace == top-rank by construction; this
check only handles explicit MSG_AKA."

---

## 4) AKA-on-X-then-lead-Y suit mismatch — PASSES (line 1259-1263)

```lua
else
    -- AKA on suit X but lead is suit Y → trivially false.
    illegal = true
    illegalWhy = "false AKA"
    s.akaCalled = nil
end
```

Branch fires when `cardSuit ~= s.akaCalled.suit` for a same-seat lead.
Marks illegal and clears the banner. **Correct.**

Note: the v0.9.0 L4 fix on `LocalAKA` (`Net.lua:2358-2363`) requires
AKA to be called BEFORE leading, with `#trick.plays == 0`. So the only
way to reach the suit-mismatch branch is the AKA-caller is also the
lead-seat (`s.akaCalled.seat == seat`) and they then lead a different
suit than they AKA'd. **This is the exact "I AKA spades but lead
hearts" exploit — caught.**

**Severity:** none.

---

## 5) AKA-on-X-then-trump-ruff — non-lead plays — NOT VALIDATED (intentional, but…)

The M3 gate **explicitly limits** to lead-seat plays only:

```lua
and #s.trick.plays == 0  -- this play IS the lead
```

So a seat that AKA'd-X and is now playing position 2/3/4 is unchecked.
**This is correct by Saudi convention:** AKA is announced on the lead;
the AKA-caller's NON-LEAD plays in the same trick (impossible — only 1
play per seat per trick) or in LATER tricks (banner is cleared at
trick-end per `State.lua:1325-1327`) cannot be "AKA plays." So the gate
is actually unreachable for non-lead plays involving the SAME AKA call.

**However**, consider this scenario:

1. Trick T1: seat 2 calls AKA-on-Spades, leads spades. M3 validates the
   spade lead is valid (caught/passed correctly).
2. Trick T1 ends. `ApplyTrickEnd` clears `s.akaCalled` (line 1327).
3. Trick T2: seat 2 again (suppose they won T1) calls AKA-on-Spades a
   SECOND time, leads a non-boss spade. **The bot's per-suit dedup
   `mem.akaSent[su]` prevents this for bot seats** (`Bot.lua:3298`).
   But a HUMAN at seat 2 calling LocalAKA bypasses the dedup —
   `LocalAKA` only checks `S.LocalAKAcandidate` (which re-evaluates
   against the live `s.playedCardsThisRound`), so if the actual boss
   was played, the human can't successfully AKA again. **Self-healing.**

**Severity:** none.

### 5a) Implicit AKA receiver under explicit-AKA-claimer

Cross-issue with Section 3: M3 only validates explicit MSG_AKA. A
host-side bug sending MSG_AKA on a non-existent rank (e.g., Ace already
played) IS caught by M3 — the rank lookup walks the order and finds A
played, finds T played, etc., until it stops at the first unplayed
rank. If the lead card's rank is NOT that unplayed rank,
`valid=false`, mark illegal. **Correct.**

### 5b) Sun-contract AKA wire-frame injection (RT prompt item 8)

`_OnAKA` rejects non-HOKM contracts (`Net.lua:3094`):
```lua
if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return end
```

The host applies the same check via the M3 gate (`s.contract.type ==
K.BID_HOKM` at line 1241). **A spoofed Sun-contract AKA frame would be
dropped by both client and host.**

**HOWEVER:** the host's `_OnAKA` runs even on the host's own loopback
of MSG_AKA. The spoofed frame reaches the host's `_OnAKA`, gets
contract-rejected, and never sets `s.akaCalled`. So the M3 gate never
fires either (because `s.akaCalled` is nil). **Net effect: a
Sun-contract MSG_AKA is silently dropped, no false-AKA mark, no
Takweesh-able illegal.** This is correct: AKA has no meaning in Sun,
so the only protection needed is "ignore the frame" — done.

But the **banner display** is also blocked. ✓

**Severity:** none.

---

## 6) Banner cleared by other paths (RT item 6) — IDENTIFIED RACE (medium)

`s.akaCalled` is cleared in **six** places:

| Site | When | OK in M3 context? |
|---|---|---|
| `S.reset()` (line 110) | new game | yes |
| `TRANSIENT_FIELDS` (line 216) | persists nil across /reload | yes |
| `ApplyStart` round-init (line 524) | new round | yes |
| `ApplyStart` round-init (line 795) | new round | yes |
| `ApplyTrickEnd` (line 1327) | end of trick | yes |
| `ApplyPlay` false-AKA branches (lines 1257, 1263) | M3 catch | yes |

**No off-cycle clear paths.** Critically, `_OnAKA` does NOT clear
`s.akaCalled` even if a SECOND AKA arrives in the same trick (only
overwrites via `ApplyAKA`). See Issue 7.

**Edge case (low severity):** the `ApplyTrickEnd` clear at line 1327
runs **after** `s.tricks` is appended (line 1313), so the M3 illegality
mark survives into `s.tricks` and is still scannable by
`HostResolveTakweesh`. **OK — Takweesh catches the false AKA even after
trick-end.** Verified by `scanIllegal` walking `S.s.tricks` first
(`Net.lua:2156-2159`).

**However:** if no opponent calls Takweesh in the trick where the false
AKA was led AND the round ends normally (e.g., bidder makes contract),
the false AKA's `.illegal` mark is still in trick history — but **no
post-round reconciliation** scans for it. The Saudi-rule Takweesh window
is per-round, and the timer/UX exits PHASE_PLAY at round-end. **A false
AKA played but un-Takweesh'd by round-end is a free pass.** This is
intentional (Takweesh requires a defender to actually call) but means
the M3 mark has no post-mortem effect.

**Severity:** low. By Saudi convention this is correct (defenders must
notice and call), but worth noting that the M3 illegality has zero
deterrent unless a defender notices and presses Takweesh.

**Recommendation:** consider an *optional* round-end auto-Takweesh
sweep that fires if `phase` exits PLAY without a manual call AND any
unflagged opp `.illegal` mark exists. Probably out-of-scope for M3.

---

## 7) Concurrent multi-AKA (RT item 7) — REAL HAZARD (medium)

The host's `S.s.akaCalled` is a single struct (`{seat, suit}`), not a
per-trick array. The M3 gate keys on `s.akaCalled.seat == seat` and
`#s.trick.plays == 0` to ensure the AKA-caller is leading.

**Scenario:** seat 2 calls AKA-on-S as lead in trick T. Before seat 2
plays the lead card, seat 4 (their partner — wrong-team AKA, but
nothing host-side prevents it) somehow sends MSG_AKA-on-D. `_OnAKA` at
`Net.lua:3084`-3087 has authority check `authorizeSeat(seat, sender)`:

```lua
if not isReplay and not authorizeSeat(seat, sender) then return end
```

So a peer cannot impersonate another seat. **But seat 4 CAN call AKA on
their own behalf** (a buggy non-host bot that broadcasts MSG_AKA from
its own seat number). Seat 4 isn't leading, so their AKA is logically
nonsense, but `_OnAKA` doesn't validate that the caller is the
upcoming lead-seat:

```lua
function N._OnAKA(sender, seat, suit, replayFlag)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    if not suit or suit == "" then return end
    -- ...
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return end
    S.ApplyAKA(seat, suit)
end
```

**`ApplyAKA` overwrites `s.akaCalled` regardless** (line 1446). So
seat 4's spurious AKA-on-D **clobbers** seat 2's earlier AKA-on-S.
When seat 2 then plays their lead card, the M3 gate checks
`s.akaCalled.seat == seat` — `s.akaCalled.seat == 4`, but `seat == 2` —
gate FALSE. **Seat 2's lead bypasses the false-AKA check entirely** if
seat 2's card was actually false.

Worse, once seat 2 leads, a partner running `pickFollow` reads
`s.akaCalled = {seat=4, suit=D}`. Since `s.akaCalled.seat == 4` and
`R.Partner(seat) == 4` is only true for seat 2, the partner-relief
branch may activate on the wrong suit (D vs. lead S), so the explicit
gate `s.akaCalled.suit == trick.leadSuit` (Bot.lua:2514) suppresses
the relief. **Implicit AKA still fires correctly** if seat 2 led an
Ace. So the gameplay impact is: the fraudulent AKA does NOT grant
relief to anyone, but it DOES bypass the M3 detection.

**Exploit summary:** a malicious peer broadcasts a junk MSG_AKA to
clobber a real-AKA-caller's banner, neutralizing M3.

**Severity:** medium. Requires a hostile client.

**Recommendations:**
1. `_OnAKA` should validate `seat == S.s.turn` AND `S.s.turnKind ==
   "play"` AND `#S.s.trick.plays == 0` (i.e., seat is about to lead).
   This mirrors the LocalAKA check at `Net.lua:2358-2363` and would
   close the clobber window.
2. Alternatively, refuse to overwrite `s.akaCalled` if it's already set
   in the same trick (FIFO: first call wins).
3. Mark `s.akaCalled` with a trick number / play index timestamp so M3
   can detect "this AKA is from a different lead-context."

---

## 8) Sun contract AKA wire-frame injection (RT item 8) — DOUBLE-GATED

Already covered in 5b. Both `_OnAKA` and the M3 gate check
`contract.type == K.BID_HOKM`. Sun-contract AKA frames are dropped at
the receiver. **No false-AKA mark generated, but no display either.**

**Severity:** none.

---

## 9) Wire-format gap: `SendAKA` does not include the AKA card

`N.SendAKA(seat, suit)` (`Net.lua:208-210`) sends only `(seat, suit)`.
The receiving host's `s.akaCalled.suit` is what M3 compares against,
but the M3 truth-check derives the "boss rank" from
`s.playedCardsThisRound` and compares to the LEAD CARD'S rank. This is
fine — AKA's claim is "I hold the boss of suit X," not "I hold rank R
of suit X." The lead card reveals the rank, M3 cross-checks.

**No issue.** Worth noting that an attacker can't lie about the rank
they're leading (the lead card is the play itself, host-validated by
`IsLegalPlay`).

**Severity:** none.

---

## 10) Edge case: AKA-then-(somebody-else-leads-out-of-turn)

Per `_OnPlay`'s strict turn check (`Net.lua:1421` and surrounding
self-heal), an out-of-turn play is rejected unless the host vouches
for it. So someone other than the AKA-caller cannot lead after the
caller AKA's. **This case can't occur under host authority.**

**Severity:** none.

---

## 11) Race: replay path during resync may double-trigger

`_OnAKA` accepts a replay flag (`fields[4] == "1"`) and bypasses
authorizeSeat (`Net.lua:3081-3082`). The replay sender is the host
(`fromHost(sender)`). The replay re-applies `ApplyAKA(seat, suit)` on
the rejoiner, setting their local `s.akaCalled` for banner display.

**M3 is host-only**, so the rejoiner doesn't run M3. The host has
already done the M3 check on the original lead. **No duplicate
illegality mark.** The replayed banner is purely cosmetic.

**One edge:** if the host re-broadcasts the AKA replay AFTER the M3
caught a false AKA and cleared `s.akaCalled = nil`, the replay won't
fire (host's `s.akaCalled` is nil at the time of resync replay, so the
condition at `Net.lua:461-463` short-circuits).

**Severity:** none.

---

## 12) `Bot.PickAKA` per-suit dedup vs. M3 detection

`Bot.PickAKA` sets `mem.akaSent[su] = true` (`Bot.lua:3368`) AFTER
deciding to send AKA. **If M3 catches the AKA as false**, `akaSent`
stays true — the bot will not re-AKA the same suit later in the round
(per the dedup at line 3298). But since a false AKA results in
**round-end via Takweesh** (HostResolveTakweesh terminates the round),
there's no "later in the round" to worry about.

**Severity:** none.

**However:** if Takweesh is NOT called (Issue 6), the bot's `akaSent`
flag locks out re-AKA on the suit even though the previous "AKA" was
nonsense. Not a correctness issue (the actual boss may have changed
and a NEW AKA on the same suit may now be legitimate), but a missed
opportunity. Probably not worth fixing.

---

## Summary of findings

| # | Issue | Severity | Action |
|---|---|---|---|
| 1 | HighestUnplayedRank in M3 (inlined plain ranking) | none | Add comment about non-trump invariant |
| 2 | AKA→lead race | none | OK |
| 3 | Implicit-AKA bypass of M3 | none (self-validating) | Add comment |
| 4 | Suit-mismatch | none (caught) | OK |
| 5 | Trump-ruff non-lead path | none (unreachable) | OK |
| 5b | Sun-contract AKA injection | none (double-gated) | OK |
| 6 | Banner cleared by other paths | low | Optional round-end auto-Takweesh |
| **7** | **Concurrent multi-AKA clobbers M3 gate** | **medium** | **Add lead-context guards in `_OnAKA`** |
| 8 | Sun AKA wire-frame | none | OK |
| 9 | SendAKA wire format | none | OK |
| 10 | Out-of-turn lead | none | OK |
| 11 | Resync replay double-trigger | none | OK |
| 12 | Bot dedup persistence | none | OK |

---

## Recommendations (prioritized)

### High (close exploitable hole)

**Add lead-context guards to `N._OnAKA`** (`Net.lua:3075-3096`). After
the existing checks:

```lua
-- Lead-context: AKA only meaningful when seat is about to LEAD.
-- This mirrors LocalAKA's gate (Net.lua:2358-2363) and closes the
-- clobber window where a non-lead seat's spurious MSG_AKA would
-- overwrite a legitimate caller's banner before M3 fires.
if S.s.turn ~= seat or S.s.turnKind ~= "play" then return end
if S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0 then return end
```

Refuses any AKA frame not from the seat currently about to lead.

### Medium

**Tag `s.akaCalled` with a trick index** so M3 can detect a clobber:

```lua
-- ApplyAKA
s.akaCalled = { seat = seat, suit = suit, trickIdx = #(s.tricks or {}) }
```

M3 then validates `s.akaCalled.trickIdx == #s.tricks` to confirm the
AKA banner belongs to THIS trick. Defends against the edge where AKA
state survives across an unintended trick boundary.

### Low / cosmetic

**Add documenting comments** to M3 about:
- The plain-ranking inline walk being deliberate (non-trump invariant).
- Implicit AKA being out-of-scope for the explicit-MSG_AKA M3 check
  (because implicit AKA is self-validating: leading a card you hold
  proves you hold it, and Ace is by definition the top plain rank).

### Pass

The core M3 mechanism — explicit MSG_AKA → lead-card-vs-boss
comparison via `playedCardsThisRound` — works correctly for all
single-call scenarios. The Takweesh-side resolution catches the
`.illegal=true; illegalReason="false AKA"` mark and surfaces it on
the chat banner with the correct verbiage.
