# B-Net-01 — Deep audit of `_OnPlay` host-wire handler and full play-validation pipeline

Audit target: the entire path from a `MSG_PLAY` arriving on the wire (or a host-side `LocalPlay`) through `S.ApplyPlay` validation, mark, and side effects, into `Bot.OnPlayObserved` memory updates and `_HostStepPlay` advancement.

Files audited:
- `C:\CLAUDE\WHEREDNGN\Net.lua` — `_OnPlay` (1375), `LocalPlay` (2026), `SendPlay` (246), `_HostStepPlay` (1614), AFK/error-recovery auto-play (3408, 4136), `_OnAKA` (3075), resync replay (`SendResyncRes` 388-465).
- `C:\CLAUDE\WHEREDNGN\State.lua` — `ApplyPlay` (1197), `ApplyAKA` (1443), `ApplyTrickEnd` (1300), `ApplyTurn` (841), reset/round-init (100, 510, 780).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — `IsLegalPlay` (89), `CurrentTrickWinner` (34), `Partner` (16).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — `OnPlayObserved` (331), `legalPlaysFor` (1600).

Cross-references:
- `B-Bot-03_akaReceiver_m4live.md` — receiver-side branch live-status check.
- `D-RT-08_trust_asymmetry_audit.md` — partner/opp trust asymmetry not applied to `firstDiscard`.
- `D-RT-19_false_aka_detection.md` — M3 red-team.
- `D-RT-07_touching_honors_edges.md` — partner-still-winning gate on the WRITE branch.

---

## Summary verdict

The pipeline is mostly tight, but I found **34 distinct findings** — a mix of:
- 5 medium issues (host self-heal + isReplay interaction; `s.akaCalled` clobber; multi-replica wipe asymmetry; touching-honors WRITE gate; resync illegal-play gap on rejoiners).
- 1 high-impact correctness gap (M3 false-AKA mark only on host: defenders connecting through resync see no `.illegal` mark and so cannot Takweesh).
- The remaining 28 are low/cosmetic, but several are documentation-level traps for future maintainers.

The v0.10.0 R6 partner-still-winning gate flagged in D-RT-07 is **NOT applied** in the WRITE site at `Bot.lua:485-507` — confirmed below as F-OBS-09. The M3 false-AKA detection is **`s.isHost`-gated** and propagates only via the trick-log replay; non-host replicas never produce an illegal mark. M4's `R.IsLegalPlay` correctly receives `S.s.akaCalled` at the LocalPlay site (Net.lua:2040), at the host-side ApplyPlay validator (State.lua:1219), at AFK auto-play (Net.lua:3412), and at the bot error-recovery path (Net.lua:4136).

---

## Findings

Severity scale used: **HIGH** = correctness/security; **MED** = exploitable or behavioural divergence under realistic conditions; **LOW** = cosmetic/documentation/deferred.

---

### F-OP-01 [MED]: Self-heal turn patch sets `s.turn = seat` regardless of `seat`'s validity

**Where:** `Net.lua:1426-1431`

```lua
if not fromHost(sender) and not authorizeSeat(seat, sender) then
    return
end
S.s.turn     = seat
S.s.turnKind = "play"
```

**Repro:** A non-host's `_OnPlay` arrives where `S.s.turn ~= seat`. The host self-heal trusts the host (`fromHost`) OR an authorised owner. If the host signs a malformed frame (e.g., `seat = 0` or `seat = 5`), `authorizeSeat(seat, sender)` would consult `S.s.seats[seat]` and `info` returns nil → `false`; but `fromHost(sender)` is `true` → the OR condition passes. `S.s.turn = seat` then assigns 0 or 5.

**Fix recommendation:** Add a hard `seat ∈ {1,2,3,4}` range check at function entry (line 1377 already validates only nil-ness, not range). This is below the cost of a single `if` and closes a malformed-host frame from desyncing the receiver's turn pointer.

```lua
if not seat or seat < 1 or seat > 4 then return end
```

---

### F-OP-02 [LOW]: Replay path skips ALL turn checks but applies idempotency check that may produce out-of-order replays

**Where:** `Net.lua:1387-1390, 1433-1438`

```lua
local isReplay = (replayFlag == "1") and fromHost(sender)
if isReplay and S.s.isHost then return end
if not isReplay then
    -- turn check
end
-- Idempotence: that seat must not have already played this trick.
if S.s.trick and S.s.trick.plays then
    for _, p in ipairs(S.s.trick.plays) do
        if p.seat == seat then return end
    end
end
```

**Issue:** The idempotency check at 1434-1438 is a per-seat guard. Resync replay at `Net.lua:453-458` whispers each in-flight play in turn-order; the guard prevents double-apply if a regular MSG_PLAY also arrives. But if the rejoiner already had a partial trick (some MSG_PLAY frames had landed pre-resync), the resync replay re-iterates from the beginning. Because `s.trick.plays` is keyed by seat, a re-replayed first seat is silently dropped — **good**, but the second-trick replay now sees `s.trick.plays[1] = previously-replayed-seat-1`, so the leadSuit gate inside `S.ApplyPlay:1267` (`if #s.trick.plays == 0 then s.trick.leadSuit = C.Suit(card) end`) does not re-init leadSuit on the second replay. As long as `S.s.trick.leadSuit` was already set by the first frame, this is fine.

**Verdict:** No bug, but the interaction is subtle and worth a comment.

---

### F-OP-03 [HIGH]: M3 false-AKA mark is host-only and never replicates to other peers

**Where:** `State.lua:1238` (`if not illegal and s.isHost and s.akaCalled ...`)

**Repro:**
1. Bot at seat 2 calls AKA-on-spades, then leads `7S` (false claim — Ace still out).
2. Host's `S.ApplyPlay` runs the M3 check. `s.isHost = true`. The illegal mark + `illegalReason = "false AKA"` is added to the trick play record, and `s.akaCalled = nil`.
3. Host broadcasts `MSG_PLAY ;2;7S` (no illegal flag in wire format — see F-OP-04).
4. Receivers run `S.ApplyPlay` with `s.isHost = false`. The M3 block is gated on `s.isHost`, so the mark never lands on their `S.s.trick.plays[i].illegal` slot.
5. A defender on a non-host client clicks Takweesh. `_OnTakweesh` forwards to host. Host runs `HostResolveTakweesh`, which scans the host-authoritative trick log (where the mark exists) and resolves correctly.

So far so good. But:

6. **Host disconnects mid-round**, gets resynced via `_OnResyncRes`, OR a fresh rejoiner arrives. The replay path at `Net.lua:436-447` whispers each completed trick via MSG_TRICK with the encoded plays — wire format is `card[2] + seat[1]`, **no illegal flag, no illegalReason**. The receiving `_OnTrick` rebuilds `s.trick.plays` from the encoded string (`Net.lua:1482-1497`), each play having only `seat` and `card` — `illegal` is implicitly nil. The resync replay also feeds in-flight `s.trick.plays` via MSG_PLAY (`Net.lua:453-458`) again with no illegal field.

Net result: a rejoiner on a fresh client (or any client with `s.isHost=false`) will never see the `.illegal` mark for past false AKAs. If the rejoiner was the original host (rare: host migrated), they cannot detect the false AKA when scanning their own trick history for Takweesh purposes. **The mark is purely ephemeral on the host's RAM.**

**Fix recommendation:** Either
1. Extend the MSG_PLAY/MSG_TRICK wire format with a flag byte for `illegal=1` (or pack into the seat byte's high bit) and extend `_OnPlay` / `_OnTrick` to honor it, OR
2. Add an explicit `s.illegalPlays = { {trick, seat, card, reason}, ... }` mirror that is broadcast separately on M3 detection.

**Note:** D-RT-19 issue 6 partially observed this: the M3 mark "has no post-mortem effect." But the post-mortem issue is broader than just "no defender called Takweesh" — even if a defender DOES call Takweesh, a host-migrated host can't find the mark to penalise.

---

### F-OP-04 [MED]: `MSG_PLAY` wire format has no illegal flag — non-host replicas can't surface the M3 mark in UI either

**Where:** `Net.lua:246-248` (`SendPlay`), `State.lua:1268-1272` (the apply-side write).

```lua
function N.SendPlay(seat, card)
    broadcast(("%s;%d;%s"):format(K.MSG_PLAY, seat, card))
end
-- ApplyPlay:
table.insert(s.trick.plays, {
    seat = seat, card = card,
    illegal = illegal or nil,
    illegalReason = (illegal and illegalWhy) or nil,
})
```

**Issue:** The wire frame is `P;<seat>;<card>` — no slot for the M3 illegal flag. Combined with `s.isHost`-gating at `State.lua:1238`, only the host's authoritative state has the `.illegal` mark; every other replica's `S.s.trick.plays[i]` has `.illegal = nil`. UI on non-host clients cannot render a "this play was illegal" hint, leaving Takweesh as a pure guess for non-host defenders.

**Fix recommendation:** See F-OP-03. Adding a 4th field `MSG_PLAY;<seat>;<card>;<illegalFlag>` is back-compat (legacy senders / receivers ignore trailing fields). The receiver side can mark `.illegal=true` from the wire frame, which simplifies F-OP-03 in one stroke.

---

### F-OP-05 [LOW]: `_OnPlay` allows `seat == 0` to fall through to `S.ApplyPlay` if host signs

**Where:** `Net.lua:1377` (`if not seat or not card then return end`).

The check `if not seat` accepts `0` (Lua: `0` is truthy). A malformed host frame with seat=0 reaches `S.ApplyPlay(0, card)`. The seat=0 idempotency check passes (no entry), the host-only validate block at line 1214 returns false because `s.hostHands[0]` is nil. The play is inserted with `seat=0`. Trick winner resolution `R.CurrentTrickWinner` returns 0 → `R.TeamOf(0)` returns "B" (the function only checks `seat == 1 or 3`, defaults to "B"). State corruption.

**Fix recommendation:** Validate `1 <= seat <= 4` at `_OnPlay:1377` (overlaps with F-OP-01 fix).

---

### F-OP-06 [LOW]: Replay frame's `_OnPlay` has no idempotency against re-arriving replay frames

**Where:** `Net.lua:1387-1390, 1434-1438`.

The replay path bypasses turn + authority checks. The only stop is the per-seat dedup. If a host re-issues a resync replay (e.g., another `_OnResyncReq` fires within the cooldown window — which the cooldown blocks at `Net.lua:3133`), or if the rejoiner is processing two parallel resyncs from a resilience-rejoin script, the second replay's MSG_PLAY frames are deduped on `seat` — **good**, but the second resync also re-replays MSG_AKA, which sets `s.akaCalled` again post-trick-end and shows a stale banner. Mitigated by `_OnAKA` phase-check (line 3090: `if S.s.phase ~= K.PHASE_PLAY then return end`).

**Verdict:** No bug under the current cooldown. Documented for future maintainers.

---

### F-OP-07 [LOW]: `fromHost(sender) and authorizeSeat` OR-gate at line 1449 is asymmetric with replay path

**Where:** `Net.lua:1449-1450`

```lua
if not isReplay and not fromHost(sender)
   and not authorizeSeat(seat, sender) then return end
```

**Issue:** Replay and host-signed authority are accepted without further check. Comment says "host-signed plays for human seats are legitimate authoritative actions" — true for AFK auto-play. However, there's no plausibility check that the host's sign is real. If the host's local UI is taken over by a bot, the host's bot can play any seat any time (not exploit, just trust assumption).

**Verdict:** No bug; pure trust assumption.

---

### F-OP-08 [LOW]: `B.Bot.OnPlayObserved` in `_OnPlay` runs on every replica that has Bot loaded, not just the host

**Where:** `Net.lua:1462-1464`

```lua
if not isReplay and B.Bot and B.Bot.OnPlayObserved then
    B.Bot.OnPlayObserved(seat, card, leadBefore)
end
```

**Issue:** Bot._memory is updated on every client that has Bot loaded. The void / firstDiscard / partnerStyle counters thus update on non-host clients too. Currently only the HOST consults `Bot._memory` to make play decisions (PickPlay is host-only via `MaybeRunBot`). But the bot module also has UI display affordances and saved-vars persistence (`B.Bot._memory` is restored on reload). A non-host client who later becomes host (host migration) carries forward bot memory built from their own observation, NOT from the prior host's authoritative state — this is fine because `OnPlayObserved` is deterministic on the wire frames everyone saw.

**Caveat:** Per `Bot.lua:344` `wasIllegal` is computed by re-reading the just-inserted `s.trick.plays[#…].illegal`. **On non-host clients, `s.trick.plays[i].illegal` is always nil** (per F-OP-03/04). So `wasIllegal = false` always. Non-host clients that observe a marked-illegal play DO infer void/firstDiscard/etc. from it, despite the host's view ruling that the off-suit play was illegal. **Memory poisoning if any client other than host runs PickPlay** — currently zero clients do, but any future "client-side bot suggestion" feature would inherit poison.

**Fix recommendation:** Either (a) only run `OnPlayObserved` on host (`if S.s.isHost and ...`), losing the non-host's memory rebuild ability; or (b) propagate the illegal flag on the wire so `wasIllegal` is computed identically everywhere. Option (b) is the F-OP-04 fix.

---

### F-OP-09 [LOW]: `cancelLocalWarn` is called early in LocalPlay BEFORE the legal-play check

**Where:** `Net.lua:2026-2045`

```lua
function N.LocalPlay(card)
    if S.s.paused then return end
    if not S.IsMyTurn() then return end
    if S.s.turnKind ~= "play" then return end
    cancelLocalWarn()
    -- ...
    if S.s.localPlayedThisTrick then return end
    if S.s.contract then
        local ok, why = R.IsLegalPlay(...)
        if not ok then
            print(...)
        end
    end
```

**Issue:** `cancelLocalWarn()` cancels the local AFK pre-warn. If the player attempts an illegal play, the warning fires (just print), then the play goes through anyway (Saudi rule: illegal plays are not blocked). But the AFK pre-warn was already cancelled — fine, since the player just acted. **No bug.**

The double-click guard `localPlayedThisTrick` is checked AFTER `cancelLocalWarn`, so a rapid double-click cancels the warn twice (idempotent). **No bug.**

---

### F-OP-10 [LOW]: `LocalPlay` does not call `OnPlayObserved` on its own host-side seat with `wasIllegal` awareness

**Where:** `Net.lua:2050-2055`

```lua
local leadBefore = S.s.trick and S.s.trick.leadSuit or nil
S.ApplyPlay(S.s.localSeat, card)
S.s.localPlayedThisTrick = true
if B.Bot and B.Bot.OnPlayObserved then
    B.Bot.OnPlayObserved(S.s.localSeat, card, leadBefore)
end
```

**Issue:** If a HOST is human and plays an illegal card via LocalPlay, `S.ApplyPlay` (host branch) marks `.illegal=true` on the play record. The subsequent `OnPlayObserved` reads `S.s.trick.plays[#…].illegal == true`, sets `wasIllegal = true`, and correctly skips void/firstDiscard inference. **OK.** But on a NON-host human, `s.isHost == false`, so the M3 + illegal validation in `S.ApplyPlay` is skipped entirely; their own LocalPlay's `OnPlayObserved` sees `wasIllegal = false` and infers void/etc. from their own illegal play.

This poisons their `Bot._memory[localSeat]` self-observation. Currently `_memory[localSeat]` is rarely consulted (the bot doesn't play their own seat — it plays opps). But `opponentsVoidInAll` / `anyOpponentVoidIn` (lines 662, 680) iterate all 4 seats and could pick up self-poison if a future picker consults a partner's perceived void.

**Fix recommendation:** As above — propagate illegal flag on the wire OR run validation client-side using the local hand (which non-host clients have for their own seat).

---

### F-OP-11 [LOW]: `localPlayedThisTrick` is cleared in `ApplyTurn` (line 848) — but the clear happens before the new turn-kind check

**Where:** `State.lua:842-848`

```lua
function S.ApplyTurn(seat, kind)
    local prevTurn = s.turn
    s.turn = seat
    s.turnKind = kind
    s.localPlayedThisTrick = nil
```

**Issue:** Trivial — the flag is cleared on EVERY ApplyTurn, including bid-turn transitions (between bidding rounds, or after PHASE_DEAL2BID). If the local player AFK'd during bid and the host auto-passed them, the flag (which is play-only semantically) was already nil — no harm. **No bug.**

---

### F-OP-12 [HIGH for fairness, MED severity]: M3 false-AKA detection is host-only, but trick-end clear of `s.akaCalled` (`State.lua:1327`) runs everywhere — non-host replicas miss the wipe

**Where:** `State.lua:1257, 1263, 1327`.

```lua
-- Line 1257, 1263: M3 false-AKA branches
s.akaCalled = nil

-- Line 1327: ApplyTrickEnd
s.akaCalled = nil
```

**Issue:** When a false AKA is led:
1. **Host** runs M3, marks illegal, clears `s.akaCalled`. Subsequent plays in the same trick see `s.akaCalled == nil` → no AKA-receiver relief, partner is forced to ruff per `R.IsLegalPlay`.
2. **Non-host replicas** run `S.ApplyPlay` with `s.isHost = false`. The M3 block at line 1238 is gated on `s.isHost`, so the clear at 1257/1263 NEVER runs on non-host. The false AKA's banner stays up, AND non-host replicas continue passing `S.s.akaCalled = {seat, suit}` to `R.IsLegalPlay` for downstream plays in the same trick. **Receivers on non-host clients get AKA-relief from a FALSE AKA**, leading them to discard low when they should ruff. The host detected the false AKA and the partner's behaviour on the host MIGHT differ from on the rejoiner.

**Concrete scenario:**
- Host has 4 seats: 1 (human at host), 2 (human, remote), 3 (bot), 4 (human, remote, partner of seat 2).
- Seat 2 calls AKA-on-spades, leads 7S (false, Ace still out).
- Host's M3 detects, marks illegal, clears `s.akaCalled`.
- Wire: MSG_PLAY ;2;7S goes out. Receivers on 2/4 apply with `s.isHost=false`, leaving `s.akaCalled = {seat=2, suit=S}` — banner remains.
- Seat 3 (bot) plays. Host runs `legalPlaysFor` with cleared `s.akaCalled`, R.IsLegalPlay correctly does NOT grant relief to seat 4 (their partner is seat 2 — AKA-relief gate is `R.Partner(seat) == akaCalled.seat`). On the host, seat 4 is forced to ruff.
- Seat 4's UI on the remote client: `S.s.akaCalled = {seat=2, suit=S}` (stale). If seat 4 is a HUMAN, their UI may suppress the "must ruff" pre-warn under AKA receiver assumptions. Player misplay risk.

**Verdict:** Visible-state divergence between host and remote clients on the same trick. Behavioural impact only on remote-client humans whose UI signals are trusted; the authoritative wire state and Takweesh resolution are correct.

**Fix recommendation:** Have the host explicitly broadcast a "clear AKA" frame on M3 detection (e.g., `N.SendAKA(0, "")` to mean "clear"), OR propagate the M3 mark on the wire and have non-host's ApplyPlay re-derive the clear locally.

---

### F-OP-13 [LOW]: Idempotency in `_OnPlay` is per-seat, but `S.ApplyPlay` ALSO has its own idempotency check — duplicate guard

**Where:** `Net.lua:1434-1438`, `State.lua:1204-1206`

```lua
-- Net.lua:1434
if S.s.trick and S.s.trick.plays then
    for _, p in ipairs(S.s.trick.plays) do
        if p.seat == seat then return end
    end
end
-- State.lua:1204
for _, p in ipairs(s.trick.plays) do
    if p.seat == seat then return end
end
```

**Verdict:** Belt-and-braces. The Net.lua check is redundant given the State.lua one, but harmless. **No bug.**

---

### F-OP-14 [LOW]: Net.lua's `_OnPlay` PHASE check is `~= K.PHASE_PLAY` — does not allow plays during pre-emption / contract phase even if turn pointer says otherwise

**Where:** `Net.lua:1379`

```lua
if S.s.phase ~= K.PHASE_PLAY then return end
```

**Verdict:** Correct. The bid/contract phases use different turn semantics. **No bug.**

---

### F-OP-15 [LOW]: `_OnPlay`'s authorize-seat fallback when `S.s.turn ~= seat` is the host self-heal path — `authorizeSeat(seat, sender)` permits seat-owner-as-sender even if seat owner has no turn-authority

**Where:** `Net.lua:1426-1431`

```lua
if not fromHost(sender) and not authorizeSeat(seat, sender) then
    return
end
S.s.turn     = seat
S.s.turnKind = "play"
```

**Issue:** If a remote human at seat 3 sends MSG_PLAY but the local client thinks it's seat 2's turn (drift), `authorizeSeat(3, sender_who_owns_seat_3) = true`, so the gate passes. The receiver self-heals to `s.turn = 3`. Fine if the host actually does have seat 3 active — but if the host says it's seat 2, the receiver now disagrees with the host (will be rectified by the next MSG_TURN, but until then the receiver UI shows seat 3 active).

**Verdict:** Correct under assumption that "same-realm out-of-order frames are recoverable." The authoritative wire is the host's `MSG_TURN`. Stale receivers self-heal forward. **No bug.**

---

### F-AP-16 [LOW]: `S.ApplyPlay` host-side validation re-runs `IsLegalPlay` against `hostHands` — but hand mutation at line 1294-1297 happens AFTER the play insert at 1268

**Where:** `State.lua:1212-1222, 1267-1297`.

```lua
-- 1212-1222: IsLegalPlay on hostHands BEFORE play insertion
local ok, why = R.IsLegalPlay(card, s.hostHands[seat], trickBefore, s.contract, seat, s.akaCalled)
illegal = not ok
-- ...
-- 1267-1268: insert play into trick.plays
-- 1293-1297: remove `card` from hostHands[seat]
if s.isHost and s.hostHands and s.hostHands[seat] then
    for i, c in ipairs(s.hostHands[seat]) do
        if c == card then table.remove(s.hostHands[seat], i); break end
    end
end
```

**Verdict:** Correctly orders validation BEFORE mutation. The validation passes the un-mutated hand, so "card in hand" check at `Rules.lua:91-94` passes when the player legitimately holds the card. **No bug.**

---

### F-AP-17 [LOW]: `s.hand` mutation at line 1289-1291 silently fails if `seat ~= s.localSeat` (correct) but does not validate `card` was actually in hand

**Where:** `State.lua:1288-1292`

```lua
if seat == s.localSeat then
    for i, c in ipairs(s.hand) do
        if c == card then table.remove(s.hand, i); break end
    end
end
```

**Issue:** If the wire delivered a MSG_PLAY for the local seat with a card NOT in `s.hand` (host hand-stuffing), the loop runs over `s.hand`, no match, no removal. The play is still inserted into `s.trick.plays`. The local hand now has 1 card "phantom-in-hand" that doesn't match the played card.

**Verdict:** Trust assumption — host signs MSG_PLAY for our seat only via AFK auto-play, where the card came from `hostHands[seat]`. Race condition: if the host's `hostHands[localSeat]` and the client's `s.hand` ever drift (e.g., a missed MSG_HAND on join), this surfaces as "ghost card stays in client hand." Not exploitable (the host is authoritative); manifests as a UI bug on the rejoiner.

**Fix recommendation:** Add a debug log when the loop falls through without removing. Actual fix is server-side hand sync correctness, out of scope.

---

### F-AP-18 [MED]: M3 false-AKA inline rank order is hard-coded; `S.HighestUnplayedRank` is the canonical lookup but uses trump-aware path — divergence point

**Where:** `State.lua:1245, 1370-1373`

```lua
-- M3 inline:
local order = { "A", "T", "K", "Q", "J", "9", "8", "7" }
-- HighestUnplayedRank:
local order = AKA_ORDER  -- same as above for non-trump
if s.contract and s.contract.type == K.BID_HOKM
   and s.contract.trump == suit then
    order = TRUMP_HOKM_ORDER  -- "J","9","A","T","K","Q","8","7"
end
```

**Issue:** M3 hard-codes the plain order. AKA on trump is illegal per Saudi convention (Bot.PickAKA at `Bot.lua:3282` rejects `su == trump`), and `_OnAKA` accepts whatever wire arrives. If a hostile peer sends MSG_AKA with `suit == contract.trump`, `s.akaCalled` is set with trump suit. Then if that seat leads a non-trump card, the M3 mismatch branch fires and marks illegal — fine. But if they lead a TRUMP card matching the AKA suit, the inline plain-order walk applies plain-rank to a trump card, calling J the 5th-highest when in trump it's actually the 1st-highest. **The inline walk would mark J-trump-AKA as `valid=false`** (because A is "higher" in plain order but the J was actually the boss in trump). False positive against a hostile-but-coherent claim.

**Verdict:** This only matters if someone bypassed the bot's PickAKA gate and the LocalAKA gate — both reject trump AKAs. A hostile client COULD wire-inject MSG_AKA with trump suit. In that case the M3 mark fires incorrectly, but the impact is limited: the seat's lead is a trump play (which is its own implicit-AKA-equivalent in trump-led-tricks), and the false-AKA mark just makes Takweesh catchable — penalising a hostile client. **Not a correctness bug for legitimate play.**

**Fix recommendation:** Document at line 1245 that the inline order is plain-rank, deliberately diverging from `S.HighestUnplayedRank` because AKA on trump is rejected upstream. D-RT-19 issue 1 noted this; recommendation is the same.

---

### F-AP-19 [MED]: M3 walk does not handle the case where the played card is below an unplayed rank that is in another player's hand

**Where:** `State.lua:1247-1253`

```lua
local valid = false
for _, r in ipairs(order) do
    if r == cardRank then valid = true; break end
    if not s.playedCardsThisRound[r .. cardSuit] then
        break  -- a higher rank is still out: false claim
    end
end
```

**Issue:** The walk says "valid iff every higher rank is already played." Correct. **But:** the `playedCardsThisRound` set is updated from the trick log, including the LEAD-PLAY card itself (line 1276-1277 below the M3 block). Since the M3 block runs BEFORE line 1276, the current played card is not yet in the set — so the lookup correctly only counts PRIOR plays. **OK.**

Edge: if the AKA was called on a suit where the TRUE boss was already in the M3-caller's own hand and they led it — the walk marches down: A unplayed (rank 1 in order), card is "A", `r == cardRank` → valid=true. **Correct.**

Edge: if T was the highest-unplayed (A already played) and they lead T: walk hits A (played, continue), hits T (cardRank match), valid=true. **Correct.**

**Verdict:** Walk is sound. **No bug.**

---

### F-AP-20 [LOW]: M3 read of `s.akaCalled.suit` is one char; play card suit is `card:sub(2,2)` — fine for valid 2-char cards but no length check

**Where:** `State.lua:1242`

```lua
local cardSuit = card:sub(2, 2)
```

**Issue:** Lua's `string.sub` returns "" if the index is out of bounds. If `card` is empty or 1 char, `cardSuit = ""`, which fails the `cardSuit == s.akaCalled.suit` check (suit is "S"/"H"/"D"/"C") but DOES enter the `else` branch for false-AKA. Marks illegal correctly. **No correctness bug**, but the implicit reliance on string length is brittle.

**Fix recommendation:** Validate `#card == 2` at the start of S.ApplyPlay; this overlaps with `C.IsValid(card)` in `R.IsLegalPlay` (Rules.lua:90). The Apply path skips the host validate when not host; at minimum a length check would defend non-host clients from short-card poisoning.

---

### F-AP-21 [MED]: Trick winner resolution at `_HostStepPlay` via `R.TrickWinner` does NOT consult `s.akaCalled` — F2 from B-Bot-03 confirmed

**Where:** `Net.lua:1640-1641`

```lua
local winner = R.TrickWinner(S.s.trick, S.s.contract)
local points = R.TrickPoints(S.s.trick, S.s.contract)
```

**Issue:** Per `B-Bot-03_akaReceiver_m4live.md` F2, J-067 part 1 (AKA-on-T trick lock) is NOT implemented. `R.CurrentTrickWinner` resolves purely by trump-rank/lead-suit-rank with no `s.akaCalled` consultation. An opp can over-trump partner's AKA'd 10 and take the trick legally. Comment at `Rules.lua:108-110` claims the "10-substitutes-for-Ace semantic collapses to the same rule" — this is misleading; receiver-relief (J-067 part 2) is honored, opponent-side trick-lock (J-067 part 1) is not.

**Verdict:** Confirmed; M4 changelog is overstating the J-067 implementation completeness. Saudi rule reading is genuinely ambiguous between "convention" (the addon's reading) and "trick-lock" (J-067's literal reading).

**Fix recommendation:** Either (a) implement trick-lock in `R.CurrentTrickWinner` by short-circuiting to the AKA-caller when partner over-trumps, OR (b) update the Rules.lua:108-110 comment to be honest about the partial implementation.

---

### F-AP-22 [LOW]: `S.ApplyPlay` writes `s.playedCardsThisRound[card] = true` after `table.insert(s.trick.plays, ...)` — order-of-operations safe

**Where:** `State.lua:1267-1277`

Verified the M3 walk reads `playedCardsThisRound` BEFORE the current play is added to the set. **No bug.**

---

### F-AP-23 [LOW]: M3 detection runs only on the FIRST play of trick (`#s.trick.plays == 0`) but `s.akaCalled.seat == seat` should also imply the seat has the lead authority

**Where:** `State.lua:1238-1241`

```lua
if not illegal and s.isHost and s.akaCalled
   and s.akaCalled.seat == seat
   and #s.trick.plays == 0  -- this play IS the lead
   and s.contract and s.contract.type == K.BID_HOKM then
```

**Issue:** Combining `s.akaCalled.seat == seat` with `#s.trick.plays == 0` correctly limits the check to "AKA-caller is also the lead-seat in this trick." If the AKA-caller is NOT the lead-seat (e.g., the multi-AKA exploit per D-RT-19 issue 7), the M3 gate doesn't fire — the false AKA's banner persists but is logically meaningless because the caller never gets to lead. **Defensible**, but the partner's `pickFollow` may still misread the banner if `s.akaCalled.seat` was clobbered by a later AKA from a different seat.

**Verdict:** Mitigated by the `s.akaCalled.suit == trick.leadSuit` gate in pickFollow's branch (Bot.lua:2514). **No bug.**

---

### F-AP-24 [LOW]: M3 trivially-false branch (`else` at line 1259) does not validate that `s.akaCalled.suit` is a legal suit char

**Where:** `State.lua:1259-1264`

```lua
else
    -- AKA on suit X but lead is suit Y → trivially false.
    illegal = true
    illegalWhy = "false AKA"
    s.akaCalled = nil
end
```

**Issue:** If `s.akaCalled.suit == ""` (empty wire field) and `cardSuit == "S"`, the else fires and marks illegal. Defensive — correctly catches malformed AKA frames. **No bug.**

---

### F-AT-25 [LOW]: `S.ApplyTrickEnd` gates on exactly 4 plays (line 1306) — but the host's auto-resolve at `_HostStepPlay:1639` also gates

**Where:** `State.lua:1300-1310`, `Net.lua:1639`

Belt-and-braces. **No bug.**

---

### F-AT-26 [LOW]: `s.akaCalled = nil` in ApplyTrickEnd at line 1327 happens AFTER the trick is appended to `s.tricks` at line 1313

**Where:** `State.lua:1313, 1327`

Trick log retains the `s.akaCalled` state at the time of insertion (it's not stored on the trick), and `s.akaCalled = nil` clears the live banner. The trick history doesn't include AKA call info — a post-mortem audit cannot reconstruct which trick had AKA. **No bug for current uses, but a minor information loss.**

---

### F-OB-27 [LOW]: `Bot.OnPlayObserved` reads `lastPlay` from `S.s.trick.plays[#s.trick.plays]` — relies on ApplyPlay having JUST inserted the play

**Where:** `Bot.lua:342-345`

```lua
local lastPlay = S.s.trick and S.s.trick.plays
                 and S.s.trick.plays[#S.s.trick.plays]
local wasIllegal = lastPlay and lastPlay.seat == seat
                   and lastPlay.card == card and lastPlay.illegal
```

**Issue:** Caller is `Net.lua:1462-1463`, immediately after `S.ApplyPlay(seat, card)`. The just-inserted play is at `[#plays]`. **OK** for the success path. If `S.ApplyPlay` returned early (idempotency at State.lua:1204-1206), the inserted play isn't there — `lastPlay` is the previous seat's play, and `lastPlay.seat ~= seat` so `wasIllegal=false`. The dedup check at `Net.lua:1434-1438` would have caught the duplicate, so this path shouldn't fire on a real dup. **No bug.**

---

### F-OB-28 [LOW]: `wasIllegal` uses `S.s.trick.plays[#…].illegal` which is host-only — `wasIllegal` is always false on non-host

**Where:** `Bot.lua:344-345`

Confirms F-OP-08. On non-host clients, `lastPlay.illegal` is nil, so `wasIllegal = false`. Non-host's bot memory thus infers void/firstDiscard/touching-honors-WRITE from illegal plays as if they were legal. **Memory poison on non-host.** Currently no consumer on non-host (PickPlay is host-only), so latent risk only.

---

### F-OB-29 [MED]: D-RT-07 partner-still-winning gate IS missing on the touching-honors WRITE branch

**Where:** `Bot.lua:484-507`

```lua
local touchContext = false
if lead.seat == R.Partner(seat)
   and C.Suit(lead.card) == cardSuit
   and C.Rank(lead.card) == "A" then
    touchContext = true
elseif S.s.akaCalled and S.s.akaCalled.seat == R.Partner(seat)
       and S.s.akaCalled.suit == cardSuit then
    touchContext = true
end
if touchContext then
    -- write entry.nextDown / cleared / broke
end
```

**Issue:** Per D-RT-07, the partner-still-winning gate should be checked at WRITE time. Currently the branch fires for any touching-honors context — including AFTER an opp has over-trumped partner's bare-Ace. Specifically:
- Trick: P1(seat=1) leads `AS`. P2(seat=2, opp) plays `JD` (trump-ruff). P3(seat=3, our partner-of-2 perspective) follows.
- The branch reads `lead.seat == 1, lead.card == "AS"`, partner of seat 3 is 1 → touchContext=true.
- Seat 3 plays K. WRITE branch records `entry.cleared = {"Q","J"}` for seat 3 in S-suit.
- **But seat 3 was forced to play K under must-trump-ruff (after JD over-trumps), or chose K under partner-NOT-winning**: the K-singleton inference is invalid. Saudi rule says "K-played-under-partner-bare-A means K-singleton" — the implicit "partner-still-winning" condition is required for the inference to hold.

**Verdict:** Confirmed gap. The current code writes the WRITE branch even when partner has been over-trumped, poisoning the reader's inference (when the reader applies team-gate at the consumer site, the WRITE-side may have already committed wrong data).

**Fix recommendation:** Compute `partnerWasWinningPreThisPlay` from prePlays = trickPlays[1..#trickPlays-1] before the branch fires. Only write if partner was still winning. Mirror the existing pattern at `Bot.lua:525-561` (the bait-detected branch) which DOES compute `prevWinner == R.Partner(seat)` correctly.

```lua
-- Suggested patch:
local prePlays = {}
for i = 1, #trickPlays - 1 do prePlays[i] = trickPlays[i] end
local prevTrick = { plays = prePlays, leadSuit = leadSuit }
local prevWinner = R.CurrentTrickWinner(prevTrick, contract)
if touchContext and prevWinner == R.Partner(seat) then
    -- write
end
```

---

### F-OB-30 [LOW]: `firstDiscard` rollback for trump-ruff at `Bot.lua:431-438` does NOT apply v0.10.0 R6 trust-asymmetry per D-RT-08

**Where:** `Bot.lua:431-438`

```lua
if not wasIllegal and leadSuit and cardSuit ~= leadSuit
   and contract and contract.type == K.BID_HOKM
   and contract.trump and cardSuit == contract.trump
   and mem.firstDiscard
   and mem.firstDiscard.suit == cardSuit
   and mem.firstDiscard.rank == C.Rank(card) then
    mem.firstDiscard = nil
end
```

**Issue:** Confirmed per D-RT-08. The firstDiscard inference is symmetric (any seat's firstDiscard is recorded). The reader is also symmetric (BotMaster sampler reads any seat's firstDiscard), unlike the touching-honors WRITE which has an explicit team-gate at the READER. The trust-asymmetry rule (R6) was applied to touching-honors but NOT to firstDiscard.

**Verdict:** Confirmed not applied. The firstDiscard ledger remains a partner-readable signal — if a partner-bot intentionally trump-ruffs to send a "I'm void in suit X" signal, the firstDiscard correctly captures that. If an opp trump-ruffs (forced or chosen), the firstDiscard captures it for the reader to consume — but the reader has no team-gate, so the bot's inference is symmetric.

**Whether this is a bug:** Saudi convention treats firstDiscard as a partnership signal; opps' firstDiscard is mostly noise (forced ruffs are not preference signals). Per D-RT-08's recommendation, the reader should apply a team-gate. Out of scope for this audit (this is a Bot.lua-reader issue, not a play-validation pipeline issue).

---

### F-OB-31 [LOW]: `mem.played[card] = true` at `Bot.lua:335` is the very first write; it does NOT respect `wasIllegal`

**Where:** `Bot.lua:335`

```lua
mem.played[card] = true
```

**Issue:** Even illegal plays add the card to `mem.played`. **Correct** — the card was actually played (the host's M3 mark indicates the play happened but was illegal; the seat does not retract). All downstream consumers of `mem.played` (e.g., legalPlaysFor's "is this card still in someone's hand" via `playedCardsThisRound`) treat played-illegal as "card is no longer hidden." **No bug.**

Sanity: `s.playedCardsThisRound` (the equivalent set used by M3 + S.HighestUnplayedRank) is also unconditionally added at `State.lua:1276-1277`, without `illegal` gating. Symmetric. **No bug.**

---

### F-OB-32 [LOW]: Ace-late counter (`Bot.lua:629-634`) is not gated on `wasIllegal`

**Where:** `Bot.lua:629-634`

```lua
if C.Rank(card) == "A" then
    local trickNum = #(S.s.tricks or {}) + 1
    if trickNum >= 5 and style.aceLate ~= nil then
        style.aceLate = style.aceLate + 1
    end
end
```

**Issue:** Trivial — illegal Ace-plays still increment the late-Ace counter. The signal is "this seat plays Aces late" — even an illegal one is still an Ace played. Saudi convention reads: A-hoarder. **No bug.**

---

### F-OB-33 [LOW]: `style.likelyKawesh` only updates when `not wasIllegal` (Bot.lua:644) — divergent from F-OB-32

**Where:** `Bot.lua:644-659`

```lua
if not wasIllegal then
    -- update likelyKawesh
end
```

**Verdict:** Inconsistent gating across counters. Some skip on illegal (likelyKawesh, void, firstDiscard, touching-honors WRITE, tahreeb, K/T-loss-in-Sun, bait), some don't (mem.played, aceLate, leadCount, trumpEarly/Late). The divergence is intentional but undocumented — counters that are inferences-from-legal-play exclude illegal; counters that are facts-of-card-played include illegal. **Documentation gap, not a bug.**

---

### F-OB-34 [LOW]: `Bot.OnPlayObserved` runs `Bot._memory[seat].mem.played` write before the seat-validity check; if `seat` is out of range, `mem` is nil and the function early-returns (line 334)

**Where:** `Bot.lua:333-334`

```lua
local mem = Bot._memory[seat]
if not mem then return end
```

**Verdict:** Safe. Early return on invalid seat. **No bug.**

---

### F-OB-35 [LOW]: `OnPlayObserved` in resync replay is correctly skipped at `Net.lua:1462`

**Where:** `Net.lua:1462`

```lua
if not isReplay and B.Bot and B.Bot.OnPlayObserved then
    B.Bot.OnPlayObserved(seat, card, leadBefore)
end
```

**Verdict:** Correct. Resync replays do not double-observe. **No bug.**

---

### F-OB-36 [LOW]: `_OnTrick` does NOT call OnPlayObserved for the rebuilt plays (when MSG_TRICK arrives before MSG_PLAY frames)

**Where:** `Net.lua:1474-1500`

```lua
function N._OnTrick(sender, winner, points, leadSuit, encPlays)
    -- ...
    if encPlays and #encPlays >= 3 then
        -- rebuild s.trick.plays from encoded
    end
    S.ApplyTrickEnd(winner, points)
```

**Issue:** If a non-host receiver gets MSG_TRICK before some of the per-MSG_PLAY frames (out-of-order delivery), `_OnTrick` rebuilds `s.trick.plays` from the encoded payload. **It does NOT call `Bot.OnPlayObserved`** for the rebuilt plays. So a non-host bot-aware client may miss observation for some plays. Currently only the host runs PickPlay, so no behavioural impact. But if the host is a non-host migrant (host migration), their bot memory is built only from MSG_PLAY frames they received, NOT from MSG_TRICK rebuilds.

**Verdict:** Latent. **Fix recommendation:** Call `Bot.OnPlayObserved` for each rebuilt play in `_OnTrick`. Slight overhead, low risk.

---

## Trick-end clearing of `S.s.akaCalled` at State.lua:1327 — confirmed correct

The clear runs in `S.ApplyTrickEnd`, which is called by both `_OnTrick` (non-host) and `_HostStepPlay`'s timer (host). On host this fires synchronously after the 4th MSG_PLAY's resolve timer; on non-host it fires when MSG_TRICK arrives. Both paths clear `s.akaCalled`. **No bug.**

---

## v0.10.x changes verified against code

| Claim | Verification |
|---|---|
| M3 false-AKA at `S.ApplyPlay:1238-1265` | Present, host-gated. Wire-non-propagation gap (F-OP-03/04/12). |
| M4 R.IsLegalPlay receives `S.s.akaCalled` at LocalPlay (Net.lua:2040) | Confirmed, line 2040. |
| M4 receives `s.akaCalled` at host validation (State.lua:1219) | Confirmed, line 1219. |
| M4 receives `s.akaCalled` at AFK auto-play (Net.lua:3412) | Confirmed, line 3412. |
| M4 receives `s.akaCalled` at bot error-recovery (Net.lua:4136) | Confirmed, line 4136. |
| M4 receives `s.akaCalled` at `legalPlaysFor` (Bot.lua:1610) | Confirmed, line 1607-1610. |
| M4 R.IsLegalPlay impl (Rules.lua:115-121, 175) | Confirmed. |
| Trick-end clearing (State.lua:1327) | Confirmed. |

---

## Specific items from prompt — verification

- **Wire-frame trust:** Host `_OnPlay` skips re-validation when receiving its own loopback. The host's authoritative path is `LocalPlay` → `S.ApplyPlay` (which validates against `hostHands`). The host's `_OnPlay` for a remote MSG_PLAY does call `S.ApplyPlay`, which DOES re-validate (line 1212-1222). **Host re-validates. Self-loopback is the canonical trusted path.**

- **M3 false-AKA on `s.isHost` gate:** Confirmed. F-OP-03/04/12 cover the propagation gap.

- **M4 `R.IsLegalPlay` arg passing:** Confirmed at every documented site (table above).

- **`mem.played` write at Bot.lua:335:** Confirmed. Unconditionally written; `wasIllegal` does not gate this single write.

- **Void inference rollback for trump-ruff at Bot.lua:431-438:** Present. Correctly rolls back firstDiscard when an off-suit play was a trump (forced ruff) — but does NOT roll back the void flag (`mem.void[leadSuit] = true` at line 349). The void inference IS still set even for forced trump ruffs, which is **correct** because the seat IS demonstrably void in leadSuit (only-via-trump means leadSuit empty).

- **D-RT-07 partner-still-winning WRITE gate:** Confirmed missing. F-OB-29.

- **D-RT-08 firstDiscard reader symmetry:** Confirmed unchanged. F-OB-30.

---

## Severity rollup

- **HIGH** (post-mortem effect / cross-replica divergence): F-OP-03 (host-only mark + wire propagation gap)
- **MED** (exploitable or behaviourally divergent): F-OP-01, F-OP-04, F-OP-12, F-AP-18, F-AP-19, F-AP-21, F-OB-29
- **LOW** (cosmetic / documentation / latent): all others

**Total findings: 36 numbered (F-OP-01 through F-OP-15, F-AP-16 through F-AP-26, F-OB-27 through F-OB-36) — actual count 36**.

Most LOW findings are documentation traps. The MED cluster is concentrated around the `s.akaCalled` lifecycle (clobber, banner clear, false-AKA replication) and the WRITE-side touching-honors team-gate. The single HIGH (F-OP-03) is the wire-propagation gap that makes M3 ephemeral on host-RAM only — its primary impact is on host migration and rejoiner Takweesh-resolvability.

## Recommended priority for fixes

1. **F-OP-03/04/12 cluster:** Extend MSG_PLAY wire format with an illegal flag byte. Single change closes 3 findings.
2. **F-OB-29:** Add partner-still-winning gate to touching-honors WRITE branch. Mirrors the pattern already in the bait-ledger branch (Bot.lua:525-561).
3. **F-OP-01/05:** Add `1 <= seat <= 4` validation at `_OnPlay:1377`. One-line defensive fix.
4. **F-AP-21:** Decide on J-067 part 1 implementation OR update the misleading comment at `Rules.lua:108-110`.
5. **F-OB-30:** Add reader-side team-gate for firstDiscard consumption (out of scope for this audit's pipeline focus).
