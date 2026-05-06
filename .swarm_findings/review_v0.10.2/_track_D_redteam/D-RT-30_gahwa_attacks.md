# D-RT-30 — Gahwa wire-frame red-team

**Scope:** terminal escalation rung. A successful or failed Gahwa swings the
ENTIRE match (`gahwaWonGame=true` → loser zeroed, winner forced to target).
Bug here = match-loss/match-win on a forged frame.

**Files reviewed:**

- `C:\CLAUDE\WHEREDNGN\Net.lua` — `_OnGahwa` (948–960), `_OnSkipGahwa` (1344–1352),
  `_HostStepAfterTrick` (1649–1719), `LocalGahwa` (1902–1912),
  `HostResolveTakweesh` (2127–2322), bot dispatcher (3755–3797),
  `_OnRound` (1503–1508), `authorizeSeat` (661–678).
- `C:\CLAUDE\WHEREDNGN\State.lua` — `ApplyGahwa` (1140–1147), `ApplyContract`
  (1025–1070), `ApplyFour` (1119–1133, where PHASE_GAHWA arms),
  ApplyResyncSnapshot (≈395–448), ApplyRoundEnd (1463+).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — `R.ScoreRound` Gahwa branch (920–937),
  Sun-multiplier collapse (873–893), tied-buyer inversion (780–812).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — `Bot.PickGahwa` (3661–3680).

---

## Scenario 1 — Forged Gahwa from non-bidder

**Verdict:** DEFENDED.

`_OnGahwa` enforces `seat == S.s.contract.bidder` BEFORE
`authorizeSeat`, and `authorizeSeat` then verifies the sender owns
that seat (or is host for a bot seat).

```
-- Net.lua:948-960
function N._OnGahwa(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if not S.s.contract or S.s.contract.gahwa then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    -- Gahwa is the BIDDER's terminal (match-win) escalation.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyGahwa(seat)
    ...
```

A spoofed `MSG_GAHWA;<defender_seat>` is dropped at the bidder check;
a frame `MSG_GAHWA;<bidder_seat>` from a non-bidder sender is dropped
at `authorizeSeat`. The two checks are belt + braces — either alone
would block both attack vectors.

**Note:** there is **no defensive `seat<1 or seat>4` range guard** in
`_OnGahwa` (`_HostBeginOvercallWindow` and a couple of other spots
DO range-check at lines 2642/2811/3077). Practically harmless because
`authorizeSeat` resolves `S.s.seats[seat]` and returns false for
non-existent indices, and the contract.bidder identity check rejects
any seat outside {1..4} since bidder ∈ {1..4}. Cosmetic gap only.

---

## Scenario 2 — Gahwa on Sun contract (v0.10.0 R2)

**Verdict:** PARTIAL — strong defense in depth, one residual gap.

Three layers prevent Sun-Gahwa:

1. **State machine** — `S.ApplyDouble` (State.lua:1085-1088) jumps
   Sun + Bel directly to `PHASE_PLAY`, never sets PHASE_TRIPLE/FOUR/GAHWA.

   ```
   if s.contract.type == K.BID_SUN then
       s.phase = K.PHASE_PLAY
       return
   end
   ```

2. **Bot picker** — `Bot.PickGahwa` (Bot.lua:3673-3674) hard-rejects
   Sun: `if contract.type == K.BID_SUN then return false, false end`.

3. **Scoring** — `R.ScoreRound` (Rules.lua:887) deliberately ignores
   `tripled/foured/gahwa` flags on Sun multiplier path; the tied-buyer
   inversion logic (Rules.lua:800-801) collapses Sun's `highest` to
   `double|none` regardless of those flags.

**The gap:** `_OnGahwa` does NOT check `contract.type ~= K.BID_SUN`.
A hand-crafted attacker (or stale resync from an old client) that
synthesizes phase=PHASE_GAHWA on a Sun contract and broadcasts
`MSG_GAHWA;<bidder>` would pass every check in `_OnGahwa` and call
`S.ApplyGahwa`, which then sets `s.contract.gahwa = true`. The phase
machine prevents this honestly, but if the receiver's phase desyncs
to PHASE_GAHWA on a Sun (e.g. a malicious peer crafted a snapshot frame
or a forged MSG_FOUR;1 followed by MSG_GAHWA;<bidder>), Sun + gahwa=true
would be applied locally.

How `R.ScoreRound` handles a Sun + gahwa=true result (the
"v0.10.0 R2 defensive normalization"):

```
-- Rules.lua:884-888
if contract.type == K.BID_SUN then
    mult = mult * K.MULT_SUN
    if contract.doubled then mult = mult * K.MULT_BEL end
    -- intentionally ignore tripled/foured/gahwa on Sun
```

The multiplier is collapsed correctly — but the Gahwa MATCH-WIN branch
at Rules.lua:928 is NOT type-gated:

```
-- Rules.lua:928-937
if contract.gahwa then
    if bidderMade then
        gahwaWinner = bidderTeam
    else
        gahwaWinner = oppTeam
    end
    gahwaWonGame = true
end
```

The match-win override fires REGARDLESS of contract.type. Combined
with the un-gated `_OnGahwa`, a forged "Sun + Gahwa" arriving on a
desynced peer where phase==PHASE_GAHWA could trigger a match-win on
Sun. The state machine prevents this from arising in normal play
on a non-tampered host, but it's a single-layer defense at the wire
(only the `phase ~= K.PHASE_GAHWA` check stands between the attacker
and `S.ApplyGahwa` on a Sun contract).

**Recommendation:** add `if S.s.contract.type == K.BID_SUN then return end`
at the top of `_OnGahwa`, and `if contract.type == K.BID_SUN then
gahwaWonGame = false end` (or simply gate the Gahwa branch on
`contract.gahwa and contract.type ~= K.BID_SUN`). Mirrors the
Bot.PickGahwa pattern. Pure belt-and-braces — but this is the
TERMINAL rung; defense in depth matters more here than anywhere else.

---

## Scenario 3 — Gahwa during PHASE_PLAY (late MSG_GAHWA)

**Verdict:** DEFENDED.

```
-- Net.lua:952
if S.s.phase ~= K.PHASE_GAHWA then return end
```

A late or replayed MSG_GAHWA arriving after `S.ApplyPlayPhase()` (which
sets `s.phase = K.PHASE_PLAY`) is dropped at the phase check before
any state mutation. Same guard pattern as `_OnDouble`/`_OnTriple`/`_OnFour`.

The `S.s.contract.gahwa` idempotence guard (Net.lua:951) also prevents
double-application if the legitimate MSG_GAHWA loops back to the host
through the broadcast → recv path (the host already applied locally
in `LocalGahwa`).

---

## Scenario 4 — Gahwa without prior Bel/Triple/Four chain

**Verdict:** DEFENDED (transitively).

PHASE_GAHWA can ONLY be reached via `S.ApplyFour(seat, open=true)`:

```
-- State.lua:1126-1132
if not s.contract.fourOpen then
    s.phase = K.PHASE_PLAY
else
    s.phase = K.PHASE_GAHWA
    if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("gahwa") end
end
```

`ApplyFour` only fires from `_OnFour`, which checks
`S.s.phase == K.PHASE_FOUR`. PHASE_FOUR only comes from `ApplyTriple(open=true)`,
which comes from `_OnTriple` requiring PHASE_TRIPLE. PHASE_TRIPLE only
comes from `ApplyDouble(open=true)` in Hokm. So the chain
Bel(open) → Triple(open) → Four(open) → Gahwa is structurally enforced.

**Caveat (compounds with Scenario 2):** the chain is enforced via
phase, not via flag inspection. An attacker who can desync the receiver's
phase (e.g. by a forged MSG_FOUR with `open=1` while no Bel/Triple
exist on contract) could, on that desync'd peer, see PHASE_GAHWA and
accept MSG_GAHWA. But every step of the way the same authorizeSeat +
contract-flag-already-set guard fires (`if S.s.contract.foured` rejects
duplicate Four; `_OnTriple` checks PHASE_TRIPLE; etc.), so building
a forged chain requires forging EVERY rung in the right phase
window — not a free attack.

The honest path is sound. Adversarial construction is blocked at
each rung individually.

---

## Scenario 5 — Match-win attribution: bidder makes vs fails

**Verdict:** DEFENDED.

```
-- Rules.lua:920-937
local gahwaWonGame = false
local gahwaWinner
if contract.gahwa then
    -- Caller's team = bidder team. They "win" if bidderMade
    -- (made or doubled-tie inversion), "lose" otherwise.
    if bidderMade then
        gahwaWinner = bidderTeam
    else
        gahwaWinner = oppTeam
    end
    gahwaWonGame = true
end
```

`bidderMade` is computed from outcome_kind ∈ {make, take} earlier in
ScoreRound (Rules.lua:814: `bidderMade = (outcome_kind == "make" or
outcome_kind == "take")`). This includes the rule 4-10 doubled-tie
inversion path — but for a Gahwa contract the `highest = "gahwa"`
branch (Rules.lua:802) sets `outcome_kind = "fail"` on tie, so a
Gahwa-contract tie correctly gives the match to defenders (the bidder
is the "buyer" at the gahwa rung, ties go against the buyer).

Verified at Rules.lua:789:
> `--   gahwa             → bidder is buyer    → fail`

Loser-zeroing at Net.lua:1671-1677 (the v0.8.6 H2 fix) properly handles
both branches:

```
if res.gahwaWinner == "A" then
    addA = math.max(addA, target - (S.s.cumulative.A or 0))
    addB = 0
else
    addB = math.max(addB, target - (S.s.cumulative.B or 0))
    addA = 0
end
```

`math.max(addA, target - cumulative.A)` ensures A reaches AT LEAST
target — `addA` might already be ≥ target-cumulative if the natural
round score is huge (×4 + sweep + Belote on a long-game tail), but
the max keeps the bigger value. Good — does not REGRESS the natural
score, only floors it at "match-decided".

---

## Scenario 6 — Gahwa + Takweesh interaction

**Verdict:** PARTIAL — Takweesh path skips the Gahwa match-win override.

`HostResolveTakweesh` (Net.lua:2127+) computes its own per-round
penalty WITHOUT consulting the Gahwa match-win branch. Multiplier
is treated as ×4 (Net.lua:2186-2190):

```
if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
if     c.gahwa   then mult = mult * K.MULT_FOUR
elseif c.foured  then mult = mult * K.MULT_FOUR
elseif c.tripled then mult = mult * K.MULT_TRIPLE
elseif c.doubled then mult = mult * K.MULT_BEL end
```

The comment at 2178-2184 explicitly acknowledges this is intentional:

> `-- v0.2.0+ multiplier ladder: Bel(×2)/Triple(×3)/Four(×4). Gahwa is`
> `-- NOT a multiplier — it's a match-win. But for early-termination`
> `-- penalties (takweesh, invalid SWA), the per-round score is still`
> `-- computed to charge the bare 26 (Sun) / 16 (Hokm) penalty even`
> `-- when Gahwa was called — so we treat Gahwa as ×4 for THIS path`
> `-- (highest active rung). The match-win semantic only applies to`
> `-- a fully-played-out round, not a forfeit.`

This is INTENDED behavior per the design comment, but it has a sharp
edge: if Takweesh fires AFTER Gahwa was called (which is allowed —
`PHASE_PLAY` follows `ApplyGahwa` → `HostFinishDeal` → `ApplyPlayPhase`,
and Takweesh is PHASE_PLAY only), the Gahwa rung becomes a stat-bump
(×4 multiplier on the 16gp Hokm penalty / 26gp Sun penalty) but is
silently STRIPPED of its match-win semantic.

**Whether this is a bug:** depends on Saudi rule reading. The design
choice is documented, defensible, and consistent. But it creates an
asymmetric outcome:
- Gahwa called + played out + bidder fails legally → match to opp.
- Gahwa called + opp Takweesh's an illegal play by bidder team → ×4
  qaid penalty (~64gp), NOT match-win.

If a player called Gahwa on a hand they could only "win" via an
illegal play, Takweesh effectively dodges the match-loss they signed
up for. This is the documented behavior; whether players consider
it correct is a rules question (not visited by this red-team).

**Wire-frame attack vector:** none. Takweesh requires an actually-illegal
play in the trick history (`scanIllegal` checks `p.illegal`), so no
forged frame can manufacture the Takweesh-skirts-Gahwa outcome. The
illegal flag is set during `S.ApplyPlay` server-side based on
`R.IsLegalPlay` evaluation; not wire-attackable.

---

## Scenario 7 — Gahwa during overcall window

**Verdict:** DEFENDED.

The overcall window is post-MSG_CONTRACT but pre-PHASE_DOUBLE
(Net.lua:1585-1587). During PHASE_OVERCALL, MSG_GAHWA is dropped at
the `phase ~= K.PHASE_GAHWA` check (Net.lua:952). The overcall window
itself only mutates `s.contract` via MSG_CONTRACT broadcast at the
end (`_HostResolveOvercall`); during the 5s window `s.phase` is
firmly `PHASE_OVERCALL`.

A forged MSG_GAHWA arriving DURING the overcall window is rejected
at the phase guard. After overcall resolves, `phase` becomes
`PHASE_DOUBLE` (via the contract being newly `S.ApplyContract`'d).
PHASE_GAHWA can only be reached via the legit Bel→Triple→Four chain
on the resolved contract.

Note: an overcall TAKE → new Sun contract → would be subject to the
Sun-Gahwa concern flagged in Scenario 2 (no `_OnGahwa` Sun gate),
but only if subsequent state advanced to PHASE_GAHWA on the Sun —
which State.lua's machine prevents.

---

## Scenario 8 — Cross-network Gahwa race (concurrent MSG_GAHWA + MSG_FOUR)

**Verdict:** DEFENDED.

Concurrent receipt of MSG_FOUR(open=1) and MSG_GAHWA scenarios:

**Case A:** MSG_FOUR arrives, then MSG_GAHWA. Phase advances to
PHASE_GAHWA in `ApplyFour`; MSG_GAHWA fires `S.ApplyGahwa` correctly.

**Case B:** MSG_GAHWA arrives before MSG_FOUR (out-of-order delivery).
Phase is still PHASE_FOUR when MSG_GAHWA arrives → dropped at
`S.s.phase ~= K.PHASE_GAHWA`. Then MSG_FOUR arrives, phase becomes
PHASE_GAHWA, but the Gahwa frame is gone. The bidder would re-emit
MSG_GAHWA via Local/MaybeRunBot's bot dispatcher. Effective stall
until either re-broadcast or AFK skip — but no inconsistent state.

**Case C:** Two MSG_GAHWA in flight. Second one is rejected by
`if S.s.contract.gahwa then return end` (Net.lua:951).

**Case D:** Forged MSG_FOUR(open=1) by a non-defender to set up a
fake PHASE_GAHWA window. `_OnFour` gates: `seat == eligibleSeat`
where eligibleSeat = bidder+1 mod 4 (Net.lua:937), and
`authorizeSeat` then requires the sender owns that seat or is host.

**Honest race conditions:** clean. **Adversarial races:** blocked
at the per-rung authorization gates.

---

## Scenario 9 — Round-end MSG_ROUND match-win flag propagation

**Verdict:** DEFENDED — but with a subtle reliance on the
match-win flag flowing only through host's locally-computed result.

`_OnRound` (Net.lua:1503-1508) is bare-minimum:

```
function N._OnRound(sender, addA, addB, totA, totB, sweep, bidderMade)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
end
```

The match-win override (loser-zeroing + winner forced to target)
runs on the HOST in `_HostStepAfterTrick` BEFORE `SendRound` is
called. Non-host clients receive the already-overridden addA/addB
values — they don't re-derive the override.

This is correct AND tamper-resistant: a malicious peer cannot
inject a fake MSG_ROUND because `not fromHost(sender)` rejects it.
But it does mean `gahwaWonGame` and `gahwaWinner` are NOT exposed
on the wire — the receiver sees the score deltas without knowing
Gahwa decided the match. The receiver's UI / banners reading
`s.contract.gahwa` (still `true` until next-round init) infer
"Gahwa caused this" from the contract flag plus the addX==target-cumulative
shape. Workable, but the receiver can't distinguish "natural ×4
crush hit target" from "Gahwa override hit target" at the wire layer.

**Cumulative tie-at-target tiebreaker (Net.lua:1693-1707):** uses
`res.gahwaWinner` first, which only the host has. Non-hosts don't
run the tiebreaker — they get `MSG_GAMEEND` from the host (Net.lua:1711)
which is also `fromHost`-gated (`_OnGameEnd` at 1510-1515). So the
canonical match-decision flows host → all peers exactly once and
cannot be forged.

---

## Scenario 10 — Failed-Gahwa raw scoring (no match-win short-circuit)

**Verdict:** DEFENDED.

The audit_v0.9.0/02_h2_gahwa_loser.md confirms the v0.8.6 fix:
loser's delta is zeroed in `_HostStepAfterTrick` (Net.lua:1673, 1676)
AFTER `R.ScoreRound` returns. `R.ScoreRound` itself (Rules.lua) still
computes raw deltas via the "fail" branch (Rules.lua:823-840), which
preserves both teams' meld points (per "مشروعي لي ومشروعك لك"). The
loser's `addX = 0` line then strips the loser's delta before
cumulative-add.

The H2 fix landed at exactly the right layer: `R.ScoreRound` stays
honest about points (so SWA / non-Gahwa paths still get raw scoring),
and the Gahwa-specific override happens once, in the host's
post-score step, where it can also force-target the winner's
cumulative.

The pin in test_state_bot.lua:1554-1569 is regex-on-source rather than
behavioral, but at HEAD there's only one match each for `addA = 0` /
`addB = 0` inside `_HostStepAfterTrick`, so a revert IS detected.

**One residual concern (also flagged in audit doc, line 32):** a
future refactor that adds an unrelated `addA = 0` line elsewhere
inside `_HostStepAfterTrick` would mask a regression of the Gahwa
zeroing. Cosmetic — pin should ideally anchor to the gahwa branch
(e.g. assert on the substring `gahwaWinner == "A"` followed within
N lines by `addB%s*=%s*0`). Not a wire-frame attack vector; build
hygiene only.

---

## Cross-cutting observations

1. **`_OnGahwa` lacks Sun-type gate** (Scenario 2). Single-layer
   defense via state machine. Bot.PickGahwa, R.ScoreRound multiplier
   path, and tied-buyer inversion all explicitly Sun-gate; only this
   wire handler doesn't. Cheap fix, defense-in-depth value.

2. **Gahwa MATCH-WIN branch in R.ScoreRound is type-blind.** Same
   point — the override fires regardless of contract.type. Should
   probably be `if contract.gahwa and contract.type ~= K.BID_SUN`.

3. **Takweesh-after-Gahwa documented behavior.** ×4 qaid penalty
   replaces match-win semantic. Whether this matches Saudi rule
   is a strategy-doc question outside red-team scope; design comment
   at Net.lua:2178 says it's deliberate.

4. **Match-win flag NOT on the wire.** Receivers infer from contract
   flag + score shape. Acceptable because MSG_GAMEEND is the
   canonical decision message and is host-gated.

5. **Loser-zero pin is source-regex.** Behavioral test would be
   stronger — pin survives accidentally if someone introduces a new
   `addA = 0` elsewhere in the function. Build-hygiene tweak.

---

## Summary table

| # | Scenario | Verdict |
|---|---|---|
| 1 | Forged Gahwa from non-bidder | Defended |
| 2 | Gahwa on Sun contract | Partial (no `_OnGahwa` type gate; MATCH-WIN branch in Rules.lua type-blind) |
| 3 | Gahwa during PHASE_PLAY (late MSG_GAHWA) | Defended |
| 4 | Gahwa without prior Bel/Triple/Four | Defended (transitively via per-rung phase + auth) |
| 5 | Match-win attribution: bidder makes vs fails | Defended |
| 6 | Gahwa + Takweesh interaction | Partial (intentional design — Takweesh strips match-win semantic; documented) |
| 7 | Gahwa during overcall window | Defended |
| 8 | Cross-network Gahwa race (concurrent MSG_GAHWA + MSG_FOUR) | Defended |
| 9 | Round-end MSG_ROUND match-win flag propagation | Defended |
| 10 | Failed-Gahwa raw scoring (per `R.ScoreRound`) | Defended (v0.8.6 H2 fix verified) |

---

## Recommended hardening (non-blocking)

1. **`_OnGahwa` Sun gate** — add `if S.s.contract.type == K.BID_SUN then return end`
   before `S.ApplyGahwa`. Mirrors `Bot.PickGahwa` line 3674.
2. **`R.ScoreRound` MATCH-WIN type gate** — change line 928 to
   `if contract.gahwa and contract.type ~= K.BID_SUN then`. Pairs
   with #1; either alone is sufficient at wire layer; both together
   make the invariant unmissable.
3. **Test pin precision** — H2 regex pin should anchor to the
   `gahwaWinner ==` branches rather than the function body, so future
   `addA = 0` additions can't mask a regression of the loser-zero.
   (Audit-doc-acknowledged.)

None of these block — current state is sound under honest play and
defensible under wire attack via the layered guards.
