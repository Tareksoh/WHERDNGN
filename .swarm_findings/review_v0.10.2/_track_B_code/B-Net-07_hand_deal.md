# B-Net-07 — Deep audit: hand-whisper + deal procedure wire path

Track-B code review of the entire deal procedure from `N.HostStartRound`
through the round-1 bid window, the Kawesh redeal, the post-contract
`N.HostFinishDeal` (which routes through `S.HostDealRest`), and the
peer-side `_OnHand` / `_OnDealPhase` apply layer.

Files inspected (read-only, no code modified):

- `C:\CLAUDE\WHEREDNGN\Net.lua` lines 1-200, 480-530, 760-825, 1500-1825,
  1900-2025, 3140-3170, 3220-3530
- `C:\CLAUDE\WHEREDNGN\State.lua` lines 1-220, 250-540, 740-840, 1190-1300,
  1540-1670
- `C:\CLAUDE\WHEREDNGN\Cards.lua` (all 201 lines)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 1780-1825, 3795-3810
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X4_pro2_deal.md`
  (X4 cut/deal cross-reference)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-15_wire_malformed.md`
  (channel-scope leak findings)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-10_m8_mardoofa_probe.md`
  (M8 bidder-perspective)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-24_mardoofa_leak.md`
  (M8 opponent-perspective)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Bot-04_pickLead_m8.md`
  (M8 implementation review)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` (channel/tag definitions, referenced
  through usage sites only)

Per finding: severity / repro / quoted code with `<file>:<line>` provenance.

---

## Wire-path summary

The complete hand+deal wire path on a fresh `N.HostStartRound`
(`Net.lua:1785-1824`):

```
1. S.ApplyStart(roundNum, dealer)             -- host applies locally
2. N.SendStart(roundNum, dealer)              -- PARTY broadcast MSG_START
3. hands, bidCard = S.HostDealInitial()       -- generate + shuffle deck
4. dealHandsToHumans(hands)                   -- WHISPER per non-bot peer
5. S.ApplyHand(hands[S.s.localSeat])          -- host's own hand applied locally
6. S.ApplyBidCard(bidCard)                    -- host applies locally
7. N.SendBidCard(bidCard)                     -- PARTY broadcast MSG_BIDCARD
8. S.s.phase = K.PHASE_DEAL1                  -- host phase mutation
9. N.SendDealPhase("1")                       -- PARTY broadcast MSG_DEAL phase=1
10. S.ApplyTurn(first, "bid")                 -- host applies locally
11. N.SendTurn(first, "bid")                  -- PARTY broadcast MSG_TURN
12. N.MaybeRunBot()                           -- bot dispatch
```

The post-bid `N.HostFinishDeal` (`Net.lua:2001-2024`) tail:

```
1. hands = S.HostDealRest()                   -- bidder-aware split
2. dealHandsToHumans(hands)                   -- second WHISPER pass
3. S.ApplyHand(hands[S.s.localSeat])          -- host's now-final hand
4. S.ApplyPlayPhase()                         -- phase=PLAY
5. N.SendDealPhase("play")                    -- PARTY MSG_DEAL phase=play
6. S.ApplyTurn(leader, "play")                -- host applies locally
7. N.SendTurn(leader, "play")                 -- PARTY broadcast
8. N.MaybeRunBot()
```

Both deal events whisper hands per-seat. Deal phase + bid card + turn are
PARTY broadcasts. Channel correctness is **not validated on receive** —
see Finding #1.

---

## Findings

### F1 — `_OnHand` does not validate the channel it arrived on

**Severity: medium** (defense-in-depth gap; pre-condition for the leak in
finding F2 below).

**Location:** `Net.lua:811-819`.

```lua
function N._OnHand(sender, encodedCards, forRound)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyHand(C.DecodeHand(encodedCards), forRound)
end
```

The `HandleMessage` dispatcher (`Net.lua:485-491`) receives `channel` and
logs it but never propagates it to per-handler gates. `_OnHand` cannot tell
whether the wire frame arrived on `WHISPER` (intended) or `PARTY` (the
channel-scope leak vector flagged in `D-RT-15` lines 760-778).

**Repro (described in D-RT-15):**

A hostile/buggy host could call:

```lua
broadcast(("%s;%d;%s"):format(K.MSG_HAND, S.s.roundNumber,
    C.EncodeHand(targetHand)))
```

instead of `whisper(target, …)`. Every PARTY peer's `_OnHand` would accept
the frame because `fromHost` passes (the sender is the genuine host), and
`S.ApplyHand` would overwrite the recipient's `s.hand` with the leaked hand.
This also means a single PARTY broadcast can leak ANY seat's hand to ALL
seats, contradicting the WHISPER design intent stated at `Net.lua:7-8`:
"Private hand deals go via WHISPER to the seat owner."

**Quote (intent at top of file):**

```
-- All public broadcasts go to PARTY (party only — RAID/GUILD intentionally
-- excluded for v1). Private hand deals go via WHISPER to the seat owner.
```

**Finding:** the design intent is documented but not enforced by the
receive-side handler.

**Recommendation (no code change in scope):** add `channel == "WHISPER"`
gate in `_OnHand` (and symmetrically in `_OnResyncRes` per D-RT-15 line 770).
Tracked separately by D-RT-15.

---

### F2 — `_OnHand` lets a forged empty whisper wipe a peer's hand mid-round

**Severity: medium-high** (combined with F1, allows a hostile host to
delete a peer's hand silently; otherwise mitigated by `fromHost`).

**Location:** `Net.lua:505-512` + `State.lua:825-835`.

The `MSG_HAND` decoder accepts both legacy single-field and
v0.9.x dual-field forms:

```lua
elseif tag == K.MSG_HAND then
    if fields[3] then
        N._OnHand(sender, fields[3], tonumber(fields[2]))
    else
        N._OnHand(sender, fields[2], nil)
    end
```

`C.DecodeHand("")` returns `{}` (`Cards.lua:75-83`). `S.ApplyHand({}, forRound)`
on a stale-round whisper rejects via the round guard:

```lua
function S.ApplyHand(cards, forRound)
    if forRound and s.roundNumber and forRound < s.roundNumber then
        return
    end
    s.hand = cards or {}
    s.handRound = forRound or s.roundNumber
end
```

But a `forRound == s.roundNumber` (current-round) frame with empty payload
sets `s.hand = {}` and writes `s.handRound = roundNumber` — the receiver
silently loses their hand. **No legitimate code path produces an empty
hand mid-round.** The Kawesh redeal in `_HostRedeal` (`Net.lua:1768-1772`)
re-sends the full hand from `S.HostDealInitial`'s 5-card-each output, never
an empty hand.

**Repro:**

Forged frame `MSG_HAND;<currentRound>;` (trailing semicolon, empty cards
field) accepted by `_OnHand` and reaches `S.ApplyHand({}, currentRound)` →
`s.hand = {}`. UI renders an empty hand; `Bot.PickPlay` returns `nil` legal
plays for the local seat.

**Finding:** the apply layer trusts the wire payload absolutely. There's
no sanity gate "incoming hand size matches phase" (DEAL1 → 5 cards;
post-DealRest → 8 cards). A buggy host's empty whisper is indistinguishable
from a legitimate empty-hand state at the receive side.

**Recommendation (no code change in scope):** in `_OnHand`, reject empty
encoded payloads when phase is DEAL1/PLAY and roundNumber > 0; or assert
8/5 card count by phase. Currently NONE of these guards exist.

---

### F3 — Hand validation on receipt: NO validation for impossible cards, duplicates, or count mismatch

**Severity: medium** (correctness + cheat-resistance gap).

**Location:** `Net.lua:818` → `State.lua:825-835`. Card decoding in
`Cards.lua:75-83`.

`C.DecodeHand` simply chunks the wire string into 2-character pairs:

```lua
function M.DecodeHand(s)
    local out = {}
    if not s or #s == 0 then return out end
    for i = 1, #s, 2 do
        local c = s:sub(i, i + 1)
        if #c == 2 then out[#out + 1] = c end
    end
    return out
end
```

There is **no `M.IsValid(c)` call**. An impossible-card pair like `"XX"` or
`"7Z"` is appended verbatim. `S.ApplyHand` does not call `M.IsValid` either.
A forged hand could include duplicate cards (e.g. `"ASAS"`), too-many cards
(>8), or impossible glyphs.

`Cards.lua:95-98` provides the validator that nobody calls on the receive
path:

```lua
function M.IsValid(card)
    if type(card) ~= "string" or #card ~= 2 then return false end
    return K.RANK_INDEX[card:sub(1, 1)] ~= nil and K.SUIT_INDEX[card:sub(2, 2)] ~= nil
end
```

`R.IsLegalPlay` (`Rules.lua:90`) does call `IsValid` — but only at play time,
not at hand-receipt time. A duplicate card in the receiver's `s.hand` would
silently render twice in the UI; an impossible glyph would crash
`C.Pretty` formatting (mitigated by `M.IsValid` check in
`Cards.lua:138`).

**Repro:**

Forged whisper `MSG_HAND;1;ASASASASASASASAS` (eight aces of spades).
`C.DecodeHand` returns `{"AS","AS",...}` (8x). `S.ApplyHand` stores it
verbatim. `s.hand` now has 8 duplicate cards.

**Finding:** receive-side hand validation is absent. The host is trusted
absolutely on hand contents. This is consistent with the addon's overall
"friendly play" trust model (`State.lua:13`: "Trust assumption: friendly
play, no cheating client modification") — but a buggy host or wire
corruption would still produce visible breakage.

**Recommendation (no code change in scope):** add a hand-validate helper
in `Cards.lua` that checks `#hand <= 8`, no duplicates, all valid; call it
from `_OnHand` before `S.ApplyHand`. Reject silently with a `log("Warn", …)`.

---

### F4 — Bid card whisper-replay path on resync re-leaks the bid card to the rejoiner via WHISPER, NOT PARTY (correct, but inconsistent with primary broadcast)

**Severity: low** (informational; documents a wire-path inconsistency
that doesn't actually leak).

**Location:** `Net.lua:142-149` (`SendBidCard` — PARTY) vs `Net.lua:393-398`
(resync re-replay — WHISPER).

The primary path broadcasts the bid card on `MSG_BIDCARD` PARTY:

```lua
function N.SendBidCard(card)
    broadcast(("%s;%s"):format(K.MSG_BIDCARD, card or ""))
end
```

This is **correct by Saudi rule** — the bid card is a face-up public card.
Per X4 line 87 ("face-up bid card revealed") and Saudi rule J-022, the bid
card is publicly visible from the moment of reveal.

The resync path (`Net.lua:393-398`, inside `N.SendResyncRes`) re-whispers
the bid card to the rejoiner:

```lua
if S.s.bidCard then
    whisper(target, ("%s;%s"):format(K.MSG_BIDCARD, S.s.bidCard))
end
```

Both paths land at `_OnBidCard` (`Net.lua:821-826`):

```lua
function N._OnBidCard(sender, card)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyBidCard(card)
end
```

The receiver does not (and per the Saudi-rule public-bid-card semantics,
need not) discriminate by channel. So switching one path to whisper has
zero observable effect — but it's a wire-protocol inconsistency that
could confuse a future packet-trace audit.

**Finding:** non-issue on Saudi-rule grounds. Worth a code comment.

---

### F5 — 3-3-2 + face-up + 2-3-3 sub-pattern: net-equivalent to 5+3 atomic deal (X4 finding intact)

**Severity: low** (functional correctness preserved; visual-fidelity gap).

**Location:** `State.lua:1611-1656` (`HostDealInitial` + `HostDealRest`).

Per X4 (xref_X4_pro2_deal.md lines 76-103), the implementation shortcuts
the 3-3-2 / 2-3-3 sub-pattern to two atomic phases:

`HostDealInitial` (`State.lua:1611-1622`):

```lua
function S.HostDealInitial()
    if not s.isHost then return end
    local deck = C.NewDeck()
    C.Shuffle(deck, math.floor(GetTime() * 1000) % 1e9)
    local hands = { {}, {}, {}, {} }
    for seat = 1, 4 do hands[seat] = C.DealCount(deck, 5) end
    local bidCard = table.remove(deck)
    s.hostHands = hands
    s.hostDeckRemainder = deck
    s.bidCard = bidCard
    return hands, bidCard
end
```

`HostDealRest` (`State.lua:1624-1657`):

```lua
function S.HostDealRest()
    if not s.isHost or not s.hostHands or not s.hostDeckRemainder then return end
    local bidder = s.contract and s.contract.bidder
    local bidCard = s.bidCard
    if bidder and bidCard then
        table.insert(s.hostHands[bidder], bidCard)
        local two = C.DealCount(s.hostDeckRemainder, 2)
        for _, c in ipairs(two) do table.insert(s.hostHands[bidder], c) end
        for seat = 1, 4 do
            if seat ~= bidder then
                local three = C.DealCount(s.hostDeckRemainder, 3)
                for _, c in ipairs(three) do
                    table.insert(s.hostHands[seat], c)
                end
            end
        end
    end
    …
```

**Net cards-per-seat:** bidder = 5 + 1 (bid card) + 2 = 8; non-bidder =
5 + 3 = 8. Total = 32 cards (full deck). Matches Saudi rule J-022/J-023.

**3-3-2 sub-pattern not modeled.** The face-up reveal happens AFTER all
8 initial cards are dealt (single 5-card chunk); Saudi rule has the bid
card revealed AFTER 8 cards (3+3+2 = 8) on each player, then a 2-3-3 final
distribution. The addon does it as 5+1bid+(2or3) which is a different
ordering of identical totals.

**Verdict (X4 confirmed v0.10.2):** still SHORTCUTTED. Net 8 cards correct.
No Saudi-rule consequence; cosmetic only. Comment at `State.lua:1632`
("12 cards distributed") is a typo (it's 11 in the remainder + 1 bid card =
12 total).

---

### F6 — Bid card reveal timing: BEFORE first hand is whispered, not AFTER

**Severity: low** (X4 finding adjacent — not a bug, but worth flagging).

**Location:** `Net.lua:1768-1772` (`HostStartRound`) and `Net.lua:1812-1815`
(`_HostRedeal` body).

```lua
local hands, bidCard = S.HostDealInitial()
dealHandsToHumans(hands)              -- whisper hands first
S.ApplyHand(hands[S.s.localSeat])
S.ApplyBidCard(bidCard)
N.SendBidCard(bidCard)                -- broadcast bid card AFTER hands
```

The order is `dealHandsToHumans → SendBidCard`. Each peer sees their own
5-card hand BEFORE the bid card is revealed publicly. This matches Saudi
rule semantics (5 cards each, then face-up reveal). The wire-order is
correct — but per F5, the addon doesn't model the 3+3+2 sub-pattern, so
the reveal happens after the full 5-card chunk arrives at each peer
rather than after a partial 3-3-2 visualization.

**Finding:** OK in the addon's atomic model. No bug.

---

### F7 — Kasho 5×{7,8,9} hand-shape trigger (Kawesh) is wired correctly via host-state validation

**Severity: low** (validates X4's "WIRED" verdict; minor race window noted).

**Location:** `Net.lua:3222-3256` (`LocalKawesh` + `_OnKawesh`),
`Net.lua:3510-3528` (`HostHandleKawesh`), `Bot.lua:3801-3807` (`PickKawesh`),
`Cards.lua:170-177` (`IsKaweshHand`).

`Cards.lua:170-177`:

```lua
function M.IsKaweshHand(hand)
    if not hand or #hand < 5 then return false end
    for _, card in ipairs(hand) do
        local r = M.Rank(card)
        if r ~= "7" and r ~= "8" and r ~= "9" then return false end
    end
    return true
end
```

The `< 5` guard (audit M-1 fix) prevents partial-deal false positives.

`Net.lua:3510-3528` (`HostHandleKawesh`) re-validates against `s.hostHands`:

```lua
function N.HostHandleKawesh(seat)
    if not S.s.isHost then return end
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_DEAL1 then return end
    if S.s.hostHands and S.s.hostHands[seat] then
        if not C.IsKaweshHand(S.s.hostHands[seat]) then
            log("Warn", "kawesh rejected: seat %d hand isn't all 7/8/9", seat)
            return
        end
    end
    N._HostRedeal("kawesh")
end
```

The host validates the call against its own authoritative `hostHands` —
a forged Kawesh from a peer who doesn't actually hold a 5×{7,8,9} hand
gets rejected silently. **Cheat-resistance is correct.**

The bot-side path (`Bot.lua:3801-3807`):

```lua
function Bot.PickKawesh(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return false end
    if S.s.phase ~= K.PHASE_DEAL1 then return false end
    if C.IsKaweshHand and C.IsKaweshHand(hand) then return true end
    return false
end
```

Bots only call when their own hand is genuinely Kawesh — host-side trusted
since bots run host-locally.

**Race window noted:** between `S.HostDealInitial` setting `s.hostHands`
(`State.lua:1618`) and the dealer rotation in `_HostRedeal` running
(`Net.lua:1730`), a Kawesh call mid-DEAL1 fires. There's no apparent race
because all of this runs on a single thread (Lua coroutine on host); but
Note that `HostHandleKawesh` does NOT guard on `S.s.contract == nil`. If a
peer crafts a malformed Kawesh frame after a contract has been declared
(say, mid-DEAL2BID) it would pass the `S.s.phase ~= K.PHASE_DEAL1` gate
(rejection) — confirmed safe.

**Verdict:** WIRED correctly. Matches X4 verdict "IMPLEMENTED (as Kawesh)".

---

### F8 — Sessional 7-8-9-same-suit Kasho: NOT IMPLEMENTED (X4 carryover)

**Severity: low** (sessional convention; X4 already flagged as MF-4).

**Location:** `Cards.lua:170-177`.

`IsKaweshHand` checks ranks only, not the "7+8+9 of the same suit visible
in the 5-card pre-buy hand" sessional convention. Grep confirms no
`7.*8.*9.*suit` or similar pattern anywhere in `Bot.lua` / `Net.lua` /
`Rules.lua` / `Cards.lua`.

**Verdict:** STILL ABSENT in v0.10.2. Same status as v0.10.0 X4 finding.
Track-X4 MF-4 unchanged.

---

### F9 — Self-trigger override (kasho-hand + ground-honor → BUY HOKM, not redeal): NOT IMPLEMENTED (X4 carryover)

**Severity: low** (sessional convention; X4 already flagged as MF-5).

**Location:** `Bot.lua:3801-3807` (Kawesh path) + `Bot.PickBid` (no
ground-card-rank consultation in the Kawesh branch).

`Bot.PickKawesh` returns true unconditionally on a 5×{7,8,9} hand. There
is no code path "if my hand is Kasho but the ground (bid) card is J/T/A,
prefer Hokm-buy over redeal." The redeal is forced; the override has no
place to fire.

**Verdict:** STILL ABSENT in v0.10.2. Same status as X4 MF-5.

---

### F10 — v0.10.2 M8 mardoofa probe gates correctly post-deal

**Severity: none** (correctness verified).

**Location:** `Bot.lua:1806-1823` (M8 branch).

```lua
if Bot.IsAdvanced() and contract.type == K.BID_SUN
   and trickNum == 1
   and contract.bidder
   and myTeam == R.TeamOf(contract.bidder) then
    local hasA = { S = false, H = false, D = false, C = false }
    local hasT = { S = false, H = false, D = false, C = false }
    local aceCard = { S = nil, H = nil, D = nil, C = nil }
    for _, c in ipairs(legal) do
        local r, su = C.Rank(c), C.Suit(c)
        if r == "A" then hasA[su] = true; aceCard[su] = c
        elseif r == "T" then hasT[su] = true end
    end
    for _, su in ipairs({ "S", "H", "D", "C" }) do
        if hasA[su] and hasT[su] and aceCard[su] then
            return aceCard[su]
        end
    end
end
```

**Post-deal gates verified:**

1. `contract.type == K.BID_SUN` — only fires after a Sun contract is
   declared (after `S.ApplyContract`). `pickLead` is called from
   `Bot.PickPlay` which is called from `MaybeRunBot` only when `phase ==
   K.PHASE_PLAY`. So M8 fires AFTER `HostDealRest` has run (the post-deal
   deal-rest produced the bidder's 8 cards, including the bid card and
   any A+T mardoofa).
2. `trickNum == 1` — `trickNum = #(S.s.tricks or {}) + 1`
   (`Bot.lua:1725`). After `S.ApplyPlayPhase` (`State.lua:1192-1195`),
   `s.tricks = {}` so `trickNum = 1` until the first trick completes.
3. `contract.bidder` — set in `S.ApplyContract` before phase transitions
   to PLAY. M8's gate `contract.bidder` (truthy check) protects against a
   nil bidder which can happen during PHASE_PREEMPT (the original buyer's
   contract is stashed in `s.pendingPreemptContract`, not `s.contract`).
4. `myTeam == R.TeamOf(contract.bidder)` — fires for bidder OR partner.
   Opposing-team leaders fall through, correct per Pro-2 §2.

`legal` is the post-DealRest hand (8 cards), so any A+T mardoofa from the
2-3-card final deal is included. The bid card (when bidder gets it) is
appended to bidder's hand at `State.lua:1634`. If the bid card is the
A or T of mardoofa-suit, the mardoofa pair is "completed" by the deal
itself — M8 will fire on it correctly.

**Verdict:** correctly gated post-deal. M8 fires on the FINAL 8-card
hand, not the 5-card pre-buy hand. Confirmed via reading
`HostFinishDeal` → `HostDealRest` → `ApplyPlayPhase` → `MaybeRunBot` →
`Bot.PickPlay` → `pickLead` chain. No race with the deal itself.

---

### F11 — Replay path for resync (post-deal state reconstruction): no `hostHands` snapshot, host-only hand state survives, peer hands re-whispered via re-replay

**Severity: low** (correct; documents the design split).

**Location:** `Net.lua:3157-3170` (`SendResyncRes`) + `State.lua:191-198`
(`hostDeckRemainder` persistence note).

After a peer's `MSG_RESYNC_REQ`, the host:

1. Sends a fresh `MSG_RESYNC_RES` snapshot via `N.SendResyncRes` (which
   does NOT include hand contents — see snapshot fields list at
   `State.lua:391-415`).
2. Re-whispers the requesting peer's hand via:

```lua
if seat and S.s.hostHands and S.s.hostHands[seat] then
    N.SendHand(sender, S.s.hostHands[seat])
end
```

The hand is **always sent from authoritative `s.hostHands`**, never
reconstructed from played cards or snapshot replay. A peer's mid-trick
rejoin gets:

- Resync snapshot (phase, contract, scores, seat names, bids).
- Full current hand (8 minus already-played cards) re-whispered.
- Replayed `MSG_MELD` / `MSG_TRICK` broadcasts (per `State.lua:511-512`)
  to rebuild the trick history.

The host's own `hostHands` is mutated by `S.ApplyPlay`
(`State.lua:1293-1297` removes played cards). So the re-whispered hand
correctly reflects the post-play state.

**`hostDeckRemainder` persistence:** the comment at `State.lua:191-198`
explicitly notes that `hostDeckRemainder` is NOT marked transient
because it pairs with `hostHands` across PHASE_DEAL1..PHASE_DEAL3. A
host /reload between `HostDealInitial` and `HostDealRest` would need
both fields to survive.

**Verdict:** post-deal resync is structurally sound. No bug.

---

### F12 — /reload mid-deal restoration: `hostDeckRemainder` survives via SaveSession; phase + hostHands restored correctly; bid card persisted

**Severity: low** (correct; documents the path).

**Location:** `State.lua:191-248` (TRANSIENT_FIELDS table),
`State.lua:250-287` (`SaveSession`), `State.lua:289-375` (`RestoreSession`).

The TRANSIENT_FIELDS list (`State.lua:191-248`) explicitly **excludes**:

- `hostHands` (host's authoritative deal — must persist)
- `hostDeckRemainder` (deck rest used by HostDealRest; comment explains
  why)
- `bidCard` (face-up reveal — public state)
- `swaRequest` (pre-vote state)
- `preemptEligible` / `pendingPreemptContract` (pre-emption window state)

A host /reload during PHASE_DEAL1 (after `HostDealInitial` ran) restores:

- `s.phase = K.PHASE_DEAL1`
- `s.hostHands = { {5 cards}, {5 cards}, {5 cards}, {5 cards} }`
- `s.hostDeckRemainder = { 11 remaining cards }`
- `s.bidCard = "<rank><suit>"`

After `RestoreSession` returns true (`State.lua:289-375`), normal flow
resumes. The bidder bid window is still open; `HostFinishDeal` (called
when contract is finalized) reads the surviving `hostDeckRemainder` and
correctly issues 2 + 3+3+3 cards.

**One subtle point:** the host's persisted `s.hand` (their own 5 cards)
must equal `s.hostHands[s.localSeat]` after restore. The save/restore
roundtrip preserves both fields independently. They diverge only if
`s.hostHands[s.localSeat]` was mutated post-save (e.g., by a play); for
DEAL1 there are no plays yet. No bug.

**Race:** if the host /reloads BETWEEN `S.HostDealInitial` and the
PARTY broadcast of `MSG_DEAL phase=1` / `MSG_BIDCARD`, peers never see
the deal. Their `s.phase` stays at the previous round's terminal state
(PLAY/SCORE) and their `s.hand` stays empty. **No code path detects
this** — the host's own restored state has the deal, but the peers don't.
Recovery requires the peers to send `MSG_RESYNC_REQ` (which they only
do on /reload themselves — NOT triggered by host's /reload). Soft-lock.

**Finding:** mid-deal host /reload between `HostDealInitial` and
`SendDealPhase("1")` produces a state-divergence soft-lock. The
restoration is internally consistent but the peers are out-of-sync.
Would require a "host re-broadcast on restore" hook that doesn't exist.
Adjacent to D-RT-15 BLOCKER on `MSG_RESYNC_REQ` tag collision — even if
peers DID try to resync from their /reload, the resync request would
route to `_OnOvercallResolve`, not `_OnResyncReq`.

**Recommendation (no code change in scope):** on host's `RestoreSession`
returning true with phase in {DEAL1, DEAL2BID, PLAY}, call
`N.SendStart`+`N.SendBidCard`+`N.SendDealPhase`+per-seat re-whisper
hands. Currently absent.

---

### F13 — Host's own hand is set via direct `S.ApplyHand`, not via the WHISPER loopback (correct)

**Severity: none** (verified).

**Location:** `Net.lua:130-140` (`dealHandsToHumans`) +
`Net.lua:1768-1770`.

```lua
local function dealHandsToHumans(hands)
    for seat = 1, 4 do
        local info = S.s.seats[seat]
        if info and not info.isBot and seat ~= S.s.localSeat then
            N.SendHand(info.name, hands[seat])
        end
    end
end
```

The host is **excluded** from the whisper loop (`seat ~= S.s.localSeat`).
The host's hand is set explicitly via `S.ApplyHand(hands[S.s.localSeat])`
on line 1770 / 1813 / 2015. This avoids:

- Round-trip latency (host's hand visible immediately).
- Whisper-to-self quirks (some WoW realms reject self-whispers).
- Loopback ordering (`MSG_HAND` whispers don't loopback to sender via
  `CHAT_MSG_ADDON` — only PARTY broadcasts do).

The bot seats also get their hands assigned via `s.hostHands[botSeat]`
exclusively — no whisper path. Bots read their hand from `S.s.hostHands`
directly (e.g., `Bot.lua:3802`).

**Verdict:** correct architecture. `dealHandsToHumans` is the only
WHISPER call site for hands.

---

### F14 — Hand whisper scope is correctly per-recipient; no cross-seat leak in normal operation

**Severity: none** (verified — the channel-leak risk is purely on the
hostile-host path covered by F1/F2).

**Location:** `Net.lua:130-140`.

```lua
for seat = 1, 4 do
    local info = S.s.seats[seat]
    if info and not info.isBot and seat ~= S.s.localSeat then
        N.SendHand(info.name, hands[seat])
    end
end
```

Each non-bot non-host seat's hand is whispered ONLY to that seat's name.
WoW addon-message WHISPER channel routing is single-recipient — the
recipient's name is the only target. The wire frame is not visible to
party members.

`info.name` is set from the lobby roster. A spoofed name would route to
the spoofer instead of the legitimate seat-holder, but that's a
seat-claim attack against the lobby (`SendLobby`), not the deal itself.

**Verdict:** WHISPER scope is enforced by the WoW API on the SEND side.
The receive-side `_OnHand` doesn't validate channel (F1), but sending is
correct. **D-RT-15 channel-scope-leak is a RECEIVE-side defense gap, not
a SEND-side leak.** The X4 finding "only hand recipient sees their cards
(no PARTY-scope leak per D-RT-15)" is consistent with this.

---

### F15 — Forced contracts (Takweesh, Forced 4th, Bel) bypass PHASE_PREEMPT and `HostDealRest` is reached via `HostFinishDeal`

**Severity: none** (verified path).

**Location:** `Net.lua:1576-1601` (`_HostStepBid` `action == "contract"`
branch).

After contract finalization (`S.ApplyContract`), `_HostStepBid` either:

1. Opens a Sun-overcall window via `_HostBeginOvercallWindow`
   (Net.lua:1585) — defers `HostFinishDeal`.
2. Skips DOUBLE for Sun-with-no-Bel-eligibility
   (`_SunBelAllowed`):

```lua
if payload.type == K.BID_SUN then
    if not N._SunBelAllowed(payload.bidder) then
        S.s.belPending = nil
        N.HostFinishDeal()
        return
    end
end
```

3. Otherwise enters PHASE_DOUBLE; bel/triple/four/gahwa decisions
   eventually call `HostFinishDeal` (`Net.lua:891, 908, 927, 944, 959,
   986, 1049, 1320, 1330, 1341, 1351, 1597`, and many bot-dispatch
   sites at 3608, 3615, etc).

ALL of these paths land at the same `HostFinishDeal` (`Net.lua:2001-2024`)
which calls `S.HostDealRest`. The bidder is set on `s.contract.bidder`
before any of these fire. So `HostDealRest`'s `bidder = s.contract and
s.contract.bidder` (`State.lua:1626`) always has a valid bidder.

**One edge case: Takweesh contract.** A Takweesh ruling
(`HostResolveTakweesh`, Net.lua:2127+) terminates the round
immediately — does NOT call `HostFinishDeal`. So the post-deal
3-3-3+2 split never runs. Correct behavior: Takweesh ends the round
early, no PLAY phase needed. Verified by reading `HostResolveTakweesh`
flow.

**Verdict:** all contract-finalization paths correctly funnel through
`HostFinishDeal` → `HostDealRest`. Bidder-aware split is always reached.

---

### F16 — Kawesh redeal advances dealer correctly; `_HostRedeal` reset state correctly before re-deal

**Severity: none** (verified).

**Location:** `Net.lua:1721-1781` (`_HostRedeal`) + `Net.lua:3525-3527`
(`HostHandleKawesh` deferral comment).

```lua
function N._HostRedeal(reason)
    local nextDealer = (S.s.dealer % 4) + 1
    S.ApplyRedealAnnouncement(nextDealer)
    broadcast(("%s;redeal;%d"):format(K.MSG_DEAL, nextDealer))
    …
    C_Timer.After(3.0, function()
        if thisGen ~= B._redealGen then return end
        if not S.s.isHost then return end
        if S.s.phase ~= K.PHASE_DEAL2BID and S.s.phase ~= K.PHASE_DEAL1
           and not S.s.redealing then
            return
        end
        if S.s.paused then return end
        S.s.dealer = nextDealer
        if B.Bot and B.Bot.ResetMemory then B.Bot.ResetMemory() end
        S.ApplyStart(S.s.roundNumber, nextDealer)
        N.SendStart(S.s.roundNumber, nextDealer)
        local hands, bidCard = S.HostDealInitial()
        dealHandsToHumans(hands)
        S.ApplyHand(hands[S.s.localSeat])
        S.ApplyBidCard(bidCard)
        N.SendBidCard(bidCard)
        S.s.phase = K.PHASE_DEAL1
        N.SendDealPhase("1")
        local first = (nextDealer % 4) + 1
        S.ApplyTurn(first, "bid")
        N.SendTurn(first, "bid")
        N.MaybeRunBot()
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
    end)
end
```

The `B._redealGen` token (`Net.lua:1750-1753`) protects against a
`/baloot reset` mid-redeal countdown. The `S.s.paused` guard prevents
deal during pause. `S.ApplyStart` (`State.lua:752-823`) resets per-round
state including `s.hostHands = nil`, `s.tricks = {}`, etc — so the
fresh `HostDealInitial` produces a clean deal.

**One important detail:** `HostHandleKawesh` (`Net.lua:3525-3527`) does
NOT pre-rotate the dealer; the comment notes a former bug:

```lua
-- _HostRedeal advances the dealer itself; do NOT pre-rotate here
-- or we'd skip a seat (was a bug — rotated twice).
```

Verified the rotation happens exactly once in `_HostRedeal` line 1730.

**Verdict:** Kawesh redeal procedure is correct. Round number stays the
same (no team scored), dealer advances by 1, fresh `HostDealInitial`
runs after the 3-second banner.

---

### F17 — `_OnDealPhase` round-2 announcement clears `s.bids` on receivers (cosmetic timing nit)

**Severity: low** (informational; the cleanup matches host-side
`HostBeginRound2`).

**Location:** `Net.lua:783-809`.

```lua
function N._OnDealPhase(sender, phase, extra)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if phase == "1" then S.s.phase = K.PHASE_DEAL1
    elseif phase == "2" then
        S.s.phase = K.PHASE_DEAL2BID
        S.s.bids = {}                -- clear round-1 bids on receivers too
        S.s.bidRound = 2
        if B.Sound and B.Sound.Cue then
            C_Timer.After(0.5, function()
                B.Sound.Cue(K.SND_VOICE_THANY)
            end)
        end
    elseif phase == "3" then S.s.phase = K.PHASE_DEAL3
    elseif phase == "play" then S.ApplyPlayPhase()
    elseif phase == "redeal" then
        local nextDealer = tonumber(extra)
        S.ApplyRedealAnnouncement(nextDealer)
    end
end
```

Receivers handle round-2 transition by clearing `s.bids` (parallel to
host's `HostBeginRound2`). Phase=play triggers `S.ApplyPlayPhase` which
sets up `s.trick = { leadSuit = nil, plays = {} }`. Phase=redeal sets
`s.redealing` for the announcement banner (auto-clears in 3.5s per
`State.lua:147-156`).

**Verdict:** receive-side phase handling is correct. No bug.

---

## Summary table

| Severity | ID | Finding | File:line |
|---|---|---|---|
| medium-high | F2 | `_OnHand` accepts empty whisper, wipes peer hand silently | `Net.lua:818` + `State.lua:825-835` |
| medium | F1 | `_OnHand` doesn't validate channel (PARTY-scope leak vector for hostile host) | `Net.lua:811-819` |
| medium | F3 | No hand validation: impossible cards / duplicates / count mismatch all accepted | `Net.lua:818` + `Cards.lua:75-83` |
| low | F8 | Sessional 7-8-9-same-suit Kasho not implemented (X4 MF-4 carryover) | `Cards.lua:170-177` |
| low | F9 | Self-trigger override (kasho + ground-honor → Hokm) not implemented (X4 MF-5 carryover) | `Bot.lua:3801-3807` |
| low | F4 | Bid card resync re-replay uses WHISPER vs primary PARTY (inconsistent but harmless) | `Net.lua:393-398` vs `Net.lua:142-149` |
| low | F5 | 3-3-2 / 2-3-3 sub-pattern shortcutted to atomic 5+3 (X4 confirmed in v0.10.2) | `State.lua:1611-1656` |
| low | F12 | Mid-deal host /reload between `HostDealInitial` and `SendDealPhase("1")` produces peer state-divergence soft-lock | `State.lua:191-248` + `Net.lua:1768-1778` |
| low | F17 | Round-2 deal-phase announcement also clears `s.bids` on receivers (cosmetic) | `Net.lua:783-809` |
| none | F6 | Bid card revealed AFTER hands whispered (correct atomic order) | `Net.lua:1768-1772` |
| none | F7 | Kawesh trigger correctly wired with host-side validation | `Net.lua:3510-3528`, `Cards.lua:170-177` |
| none | F10 | v0.10.2 M8 mardoofa probe gates correctly post-deal (fires on full 8-card hand) | `Bot.lua:1806-1823` |
| none | F11 | Resync replay path: hostHands authoritative + per-trick replay reconstructs state | `Net.lua:3157-3170` |
| none | F13 | Host's own hand assigned directly, not via whisper loopback (correct) | `Net.lua:130-140` |
| none | F14 | Hand whisper scope per-recipient (WoW WHISPER API enforces; F1 is receive-side gap, not send-side) | `Net.lua:130-140` |
| none | F15 | All contract-finalization paths funnel through `HostFinishDeal` → `HostDealRest` | `Net.lua:1576-1601, 2001-2024` |
| none | F16 | `_HostRedeal` advances dealer once, does correct state reset | `Net.lua:1721-1781` |

---

## Cross-references to existing reviews

- **X4 (`xref_X4_pro2_deal.md`)**: F5 confirms shortcut still in v0.10.2.
  F8/F9 confirm MF-4/MF-5 still ABSENT. F7 confirms Kawesh STILL WIRED.
- **D-RT-15 (`D-RT-15_wire_malformed.md`)**: F1/F2 reproduce the
  channel-scope leak gap (lines 760-778) for the specific hand-whisper
  path. F3 amplifies (no hand-content validation).
- **D-RT-10 (`D-RT-10_m8_mardoofa_probe.md`)**: F10 confirms M8 fires
  on the post-deal hand correctly; bidder-perspective gating intact.
- **D-RT-24 (`D-RT-24_mardoofa_leak.md`)**: F10 confirms the M8
  branch position post-deal; opp-perspective info-leak concerns are
  out of scope here but the wire-path correctness is verified.
- **B-Bot-04 (`B-Bot-04_pickLead_m8.md`)**: F10 corroborates B-Bot-04
  F1-F5 (M8 implementation review).

---

## Confidence

- **High** for F1/F2/F3 (read all of `_OnHand` + `S.ApplyHand` +
  `C.DecodeHand`; no validation present anywhere on the receive path).
- **High** for F4 (read both bid-card send sites + `_OnBidCard`).
- **High** for F5 (read `HostDealInitial` + `HostDealRest` start-to-end;
  matches X4's earlier full-read).
- **High** for F6/F13/F14/F15/F16/F17 (read full `HostStartRound`,
  `HostFinishDeal`, `_HostRedeal`, `_OnDealPhase`, `dealHandsToHumans`
  bodies).
- **High** for F7/F10 (read `HostHandleKawesh`, `Bot.PickKawesh`,
  `Cards.IsKaweshHand`, M8 branch; trigger flow verified line-by-line).
- **High** for F8/F9 (cross-checked with X4's grep for sessional and
  override patterns; confirmed no new code added in v0.10.0..v0.10.2).
- **High** for F11 (read `SendResyncRes` re-whisper block; trick history
  reconstructed from broadcast replay per State.lua:511-512 comment).
- **High** for F12 (TRANSIENT_FIELDS table is explicitly enumerated in
  `State.lua:191-248`; `hostDeckRemainder` is explicitly NOT in the
  list with a comment explaining why; mid-deal /reload soft-lock is
  inferred from absence of any `RestoreSession`-triggered re-broadcast
  hook).

No code modified.
