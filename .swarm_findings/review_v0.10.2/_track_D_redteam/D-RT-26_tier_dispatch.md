# D-RT-26 — Tier Dispatch Mid-Game Flip Probe

**Date:** 2026-05-05
**Scope:** v0.10.2 — `WHEREDNGNDB.advancedBots / m3lmBots / fzlokyBots /
saudiMasterBots` toggled mid-bidding / mid-trick via `/baloot ...` or
hand-edit, plus tier-flag corruption.
**Source files:** `Bot.lua`, `BotMaster.lua`, `Slash.lua`,
`WHEREDNGN.lua`.

**Verdict summary:**
- 1 PASS-trivially (toggle helpers are OR-chained)
- 4 PASS-with-caveats
- 2 PASS but data leak observed (writes ungated, reads gated — the
  prior audit `audit_v0.7.1/65_tier_dispatch_hunt.md` flagged this as
  a *feature* for OFF→ON flips; this review reframes the ON→OFF half)
- 2 FAIL-low-severity (slash help vs implementation drift; no host
  gate on the toggles despite the help text)
- 1 FAIL-cosmetic (truthy semantics)

This re-audit extends `audit_v0.7.1/65_tier_dispatch_hunt.md` by
focusing on the **dynamic** half — what happens when the flag flips
mid-stream instead of being chosen at lobby.

---

## Background — current dispatch shape

**Helpers (`Bot.lua:48-79`):**
```lua
function Bot.IsAdvanced()
    return WHEREDNGNDB
       and (WHEREDNGNDB.advancedBots == true
            or WHEREDNGNDB.m3lmBots == true
            or WHEREDNGNDB.fzlokyBots == true
            or WHEREDNGNDB.saudiMasterBots == true)
end
function Bot.IsM3lm()    -- m3lm or fzloky or saudimaster
function Bot.IsFzloky()  -- fzloky or saudimaster
function Bot.IsSaudiMaster()  -- saudimaster only
```

The `== true` strict-equality chain enforces boolean semantics — see
scenario 6 below for the consequence.

**Toggle (`Slash.lua:143-173`):**
```lua
if msg == "advanced" or msg == "advbots" then
    WHEREDNGNDB = WHEREDNGNDB or {}
    WHEREDNGNDB.advancedBots = not WHEREDNGNDB.advancedBots
    say("advanced bots = " .. tostring(WHEREDNGNDB.advancedBots))
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
    return
end
```

No phase guard, no `isHost` guard, no game-running guard.

`BM.IsActive()` (`BotMaster.lua:132-134`) reads only the raw
`saudiMasterBots` flag — equivalent to `Bot.IsSaudiMaster()`.

---

## Scenario 1 — Mid-bidding tier change

**Setup:** Round 1, bot bids `BID_HOKM_S` while M3lm is on. User runs
`/baloot m3lm` (or hand-edits `WHEREDNGNDB.m3lmBots = nil`). Same
seat is now back to Advanced for the rest of bidding (round 2 picks,
escalation decisions, the played round).

**Code path:** `Bot.PickBid` reads `Bot.IsAdvanced()` /
`Bot.IsM3lm()` afresh at each call (`Bot.lua:732, 800, 917, 1023,
1056, 1136, 1246, 1252, 1396` etc.). No memoization.

**Behavior change:** ALL of:
- `hokmMinShape` L07 Ace-required gate (`Bot.lua:800`) — flips OFF,
  bot can re-bid Hokm without an Ace in round 2 even though it bid
  with the Ace gate in round 1
- `r2Base` adjustment (`Bot.lua:1246`) drops from 38 back to 36
- Trap-pass detection (`Bot.lua:1252`) goes silent
- `partnerBidBonus` (`Bot.lua:946`) returns 0 — partner's bid is now
  ignored
- All escalation decisions (`PickDouble/Triple/Four/Gahwa`) skip
  styleBelTendency / gahwaFailed / triples reads

**Verdict:** **PASS-with-caveats.** Each call re-reads, so the
single-decision logic is internally consistent within that call.
There is NO partial state where one half of `PickBid` thinks M3lm is
on while the other half thinks it's off — the helpers are pure
function calls with no caching.

The "caveat" is *strategic* coherence: a bot that bid Hokm with M3lm
L07's Ace gate may, after a mid-stream toggle off, escalate
differently than its bid implied. But the engine doesn't crash and
no rule is violated; the user *asked* for tier change, so getting it
mid-stream is consistent with intent.

**Recommendation:** None — this is by-design behaviour. If the user
flips it, they get it. Document on the slash help that mid-game
flips take effect on the next decision.

---

## Scenario 2 — Mid-trick AKA-receiver branch flip

**Setup:** Hokm contract, partner just announced AKA on Spades. Bot
is about to follow with a void-in-Spades hand. Tier was Advanced.
User toggles Advanced OFF mid-trick.

**Code path:** `pickFollow` (`Bot.lua:2546-2558`):
```lua
if Bot.IsAdvanced() and contract.type == K.BID_HOKM and contract.trump
   and trick.leadSuit and partnerWinning
   and (explicitAKA or implicitAKA) then
    local discards = {}
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then
            discards[#discards + 1] = c
        end
    end
    if #discards > 0 then
        return lowestByRank(discards, contract)
    end
end
```

**Behavior change:** The AKA-receiver-relief branch goes silent.
Instead, `legal` (which already includes non-trump because
`Rules.lua:R.IsLegalPlay` was patched in v0.10.2 M4 to exempt
AKA-receivers from must-trump-ruff when `S.s.akaCalled` is set)
falls through to the natural `pickFollow` logic. Down at line 3024
the `winners` test fires; if a non-trump card "wins" it gets played,
or the bot may even RUFF with trump because the heuristic gating is
gone.

This means the **same trick** can have:
- Legal-set computed under AKA-relief (non-trump allowed)
- Picker decision computed under non-AKA semantics (might pick trump
  ruff anyway, defeating partner's coordination)

But this is no different from the user toggling tiers between any
two sequential calls. The legality layer is `R.IsLegalPlay`, which
checks `s.akaCalled` directly (not a tier helper), so the legal-set
remains relaxed. The picker's ruff would be a TIER-CHOICE outcome,
not a rule violation.

**Verdict:** **PASS-with-caveats.** No illegal play is generated.
Partner's AKA signal is wasted, which is the cost of mid-trick
toggle. Same outcome as Basic-tier game ignoring AKA.

**Recommendation:** None. The legality fix (M4) means the picker
decision doesn't corrupt legal-set — the relaxed legal-set is
purely additive (gives picker more options). Toggling tier off
just makes the picker pick worse from that set, not illegal.

---

## Scenario 3 — State leakage: `_partnerStyle` accumulation under tier change

**Setup:** Game starts at Basic. Round 1-3 played. `_partnerStyle`
counters (bels, triples, fours, gahwas, leadCount, baitedSuit,
topTouchSignal, tahreebSent, gahwaFailed, sunFail, aceLate,
trumpEarly, trumpLate) accumulate on every play because
`Bot.OnPlayObserved` (`Bot.lua:331-660`) is **ungated**. User toggles
M3lm ON in round 4.

**Code paths — WRITE (no tier gate):**
- `Bot.OnPlayObserved` (`Bot.lua:331`) — populates `_memory[].void`,
  `_memory[].played`, `_memory[].firstDiscard`, `_memory[].akaSent`,
  `_memory[].likelyKawesh` plus EVERY `_partnerStyle[]` field.
- `Bot.OnEscalation` (`Bot.lua:269`) — increments bels / triples /
  fours / gahwas.
- `Bot.OnRoundEnd` (`Bot.lua:291`) — increments gahwaFailed / sunFail.

**Code paths — READ (M3lm/Fzloky/Advanced gated):**
- `Bot.lua:1860` `if Bot.IsM3lm() and Bot._partnerStyle then` for
  Tahreeb pref-suit
- `Bot.lua:1960` `if Bot.IsFzloky() and Bot._memory then` for
  firstDiscard
- `Bot.lua:1984, 2012, 2126, 2239, 2254` — all M3lm-gated
- `Bot.lua:2068, 2102, 2152, 2323` — Advanced-gated reads of
  `_memory.played` / `_memory.void`
- `BotMaster.lua:474, 405` — Saudi-Master sampler reads
  `topTouchSignal`, `aceLate`, `leadCount`

**Behavior at the OFF→ON transition:** Reader sees a complete
ledger from round 1, **even though those rounds were played as
Basic**. The data is "honest" (it tracks what each seat actually
did), but the bot now has ledger entries from rounds where the
seats themselves were also Basic and weren't using style-aware
plays. A "habitual Beler" inferred from round 1 might just have
been Basic-bot's random Bel.

This was flagged in `audit_v0.7.1/65_tier_dispatch_hunt.md` § 3 as
**correct OFF→ON behaviour**. I confirm that conclusion: the
ledger contains genuine observations and the M3lm reader's
inference (e.g., "this opp Bel'd twice → habitual") is honest. The
edge case is small.

**Behavior at the ON→OFF transition:** Reader stops consuming the
ledger; writer continues filling it. This is asymmetric:
1. ON→OFF is a no-op for picker output (just stops consulting).
2. OFF→ON yields data from prior basic rounds.
3. ON→OFF→ON LATER — same as OFF→ON.

**Verdict:** **PASS** (data leak observed, no functional bug).
WRITE-ungated by design (cheap counters), READ-gated by tier
helper. The asymmetry was deliberate per the original architect's
comments (`Bot.lua:396-398` "Cheap counters; we only USE them in
M3lm-gated branches").

**Recommendation:** Document the OFF→ON edge case. If a future
release wants tier coherence, the cleanest fix is `Bot.ResetStyle()`
on EVERY tier-toggle slash command. Alternative: gate the writers
too (`if Bot.IsM3lm() then style.bels = style.bels + 1`), but that
loses cross-tier observability — a Basic game then can't be
"upgraded" to M3lm reads on existing data.

---

## Scenario 4 — Saudi-Master upgrade mid-game; ISMCTS depends on style data

**Setup:** Game runs Advanced for rounds 1-3. User toggles
saudiMasterBots ON in round 4. The next play call hits
`Bot.PickPlay` (`Bot.lua:3372-3402`):
```lua
function Bot.PickPlay(seat)
    if not Bot._inRollout then
        local BM = WHEREDNGN and WHEREDNGN.BotMaster
        if BM and BM.IsActive and BM.IsActive() and BM.PickPlay then
            local masterCard = BM.PickPlay(seat)
            if masterCard then return masterCard end
        end
    end
    -- … fallthrough to heuristics
end
```

**ISMCTS reads:**
- `BotMaster.lua:474` `style.topTouchSignal` for partner-only
  pinning of the next-rung card
- `BotMaster.lua:405` `style.aceLate` for the A-hoarder pickProb
  damping
- `BotMaster.lua:419` `B.Bot.OpponentUrgency(bidder)` (M3lm-gated
  internally — returns 0 when M3lm is OFF, but always 0 won't
  crash; the mid-game upgrade DOES cross M3lm activation since
  saudimaster ⊂ Fzloky ⊂ M3lm)
- `BotMaster.lua:436` `style.leadCount` for opponent suit-bias

After upgrade, `Bot.IsSaudiMaster()` returns true → all four lower
helpers also return true (they OR-chain saudimaster). The sampler
sees:
- A complete `_partnerStyle` ledger from rounds 1-3 (writes are
  ungated, scenario 3).
- An incomplete `topTouchSignal` ledger because the **writer** at
  `Bot.lua:476-507` IS gated:
  ```lua
  if not wasIllegal and contract and trickPlays
     and #trickPlays >= 2 and style.topTouchSignal then
  ```
  Wait — it's gated on `style.topTouchSignal`, not on a tier helper.
  Re-checking — the writer fires for any tier as long as
  `_partnerStyle` exists.

**Re-verification at the writer site (`Bot.lua:474-508`):**
The branch fires unconditionally on any tier — `style.topTouchSignal`
is always-present (it's initialized in `emptyStyle`). So the writer
populates the field on every play even at Basic. ✓

**Verdict:** **PASS — data is consistent** between rounds 1-3 ledger
state and round 4 ISMCTS reads. The OF→ON tier change does NOT
introduce a stale-data bug because writers were always running.

**Caveat:** ISMCTS will now use rounds-1-3 data of seats that PLAYED
basic-tier; the inferences may be noisier than they would be in a
game that started at Saudi Master. This is the same caveat as
scenario 3.

**Recommendation:** None. By-design.

---

## Scenario 5 — Tier-gated WRITE vs gate-less READ (the inverse of #3)

**Setup:** Tier is OFF mid-game. Are there any reads that fire when
the tier is OFF? Searched all `Bot._partnerStyle` and
`Bot._memory` reads.

**Findings:**
- `Bot._memory.played` reads in `pickLead`'s Ace-exhaustion branch
  (`Bot.lua:2068`) are gated on `Bot.IsAdvanced()`. ✓
- `Bot._memory.void` reads in `opponentsVoidInAll` /
  `anyOpponentVoidIn` (`Bot.lua:662`, `Bot.lua:680`) — **GATE-LESS**.
  These are called from inside `pickLead`'s "free trick" check
  (`Bot.lua:2299`) — also gate-less.
- `Bot._memory.void` reads in `suitCardsOutstanding`
  (`Bot.lua:2466`) — **GATE-LESS**.
- `BotMaster.lua:299, 342` `_memory[].void` reads — gated by
  `BM.IsActive()` indirectly (whole sampler is Saudi-Master only).

**The `void` field is set in `Bot.OnPlayObserved` (`Bot.lua:349`):**
```lua
if not wasIllegal and leadSuit and cardSuit ~= leadSuit then
    mem.void[leadSuit] = true
```

This is a structural inference (a seat that didn't follow lead suit
is void in it), not a tier-gated heuristic. Reading it at any tier
is correct behaviour. ✓

**Verdict:** **PASS.** All identified gate-less reads are reading
*structural* fields (`void`, `played`) that are tier-independent
inferences (rule-of-the-game derived). The tier-conditional
fields (`firstDiscard`, `tahreebSent`, etc.) are read with proper
gating. No tier-leak found beyond what the prior audit covered.

**Recommendation:** None.

---

## Scenario 6 — Tier flag corruption: `m3lmBots = 1`

**Setup:** SavedVariables hand-edit, or future code that uses
`WHEREDNGNDB.m3lmBots = 1` (truthy number).

**Code paths:**
```lua
function Bot.IsM3lm()
    return WHEREDNGNDB
       and (WHEREDNGNDB.m3lmBots == true
            or WHEREDNGNDB.fzlokyBots == true
            or WHEREDNGNDB.saudiMasterBots == true)
end
```

The `== true` is a STRICT-EQUALITY check. `1 == true` is FALSE in
Lua — the predicate returns FALSE for `m3lmBots = 1`.

Same for `BM.IsActive()` — `WHEREDNGNDB.saudiMasterBots == true`
is strict.

**Slash toggle behaviour:**
```lua
WHEREDNGNDB.m3lmBots = not WHEREDNGNDB.m3lmBots
```

If a user hand-edits `m3lmBots = 1`, then `not 1` is `false` (only
`nil` and `false` are falsy in Lua). So:
- Initial state: `m3lmBots = 1` → `IsM3lm()` returns false (because
  `1 ~= true`)
- After `/baloot m3lm`: `m3lmBots = false` → `IsM3lm()` still false
- After another toggle: `m3lmBots = true` → `IsM3lm()` true

So a user who hand-edits to `1` gets the tier OFF until they toggle
twice. There's no visible inconsistency — the helpers agree (all
return false), and the toggle works correctly after one extra flip.

**Edge case found:** If a hand-edit has `m3lmBots = "true"` (string
literal):
- `IsM3lm()` returns false ("true" ~= true)
- `not "true"` is `false` (string is truthy in Lua)
- After `/baloot m3lm`: `m3lmBots = false`
- After another `/baloot m3lm`: `m3lmBots = true`

Same recovery pattern. No crash.

**Verdict:** **PASS — robust.** Strict equality + the `not` toggle
both behave deterministically. Hand-edits to non-boolean values are
silently ignored as OFF, with two toggles to recover.

**Recommendation:** Cosmetic — `Slash.lua` could normalize:
```lua
WHEREDNGNDB.m3lmBots = (WHEREDNGNDB.m3lmBots ~= true)
```
to recover from corrupt hand-edits in a single toggle. Low priority.

---

## Scenario 7 — Per-bot tier vs uniform tier

**Setup:** Game has 4 bots. User wants seat 1 = Saudi Master, seat
2 = Basic, etc.

**Code:** No per-seat tier field. Per `audit_v0.7.1/65 §6`, the
`State.lua:423` schema stores only `s.seats[seat].isBot`. All tier
helpers read globals.

**Verdict:** **PASS — heterogeneous tiers are impossible by
design.** Every bot in the game reads the same global flag at
every decision. Mid-game flip changes ALL bots simultaneously.

**Recommendation:** None — this is the existing design constraint.
If a future feature needs per-seat tier, schema change required.

---

## Scenario 8 — Slash help vs implementation drift (host-gate)

**Setup:** `Slash.lua:17-20` help text says "(host only)" for
advanced/m3lm/fzloky/saudimaster toggles, but the dispatch handlers
`Slash.lua:143-173` have NO `isHost` check. Compare with
`Slash.lua:83 (bots)` and `Slash.lua:108 (start)` which DO check
`B.State.s.isHost`.

**Behavior:** A non-host player can toggle their LOCAL
`WHEREDNGNDB.advancedBots` flag, but since bots only run on the
host (per `Bot.lua:1` "Driven from Net.lua's MaybeRunBot when it's
a bot's turn" — host-only), the flag is dead-code on the
non-host's machine. The local UI checkbox cascade (`UI.lua:850`)
also lets non-host users toggle their own flag.

**Verdict:** **FAIL-low-severity.** The help text is misleading
but the behavior is harmless: only the host's flag determines bot
behaviour, so a non-host's flip has no effect. A non-host's
SavedVariables edit also has no effect.

**Recommendation:** Either remove the "(host only)" suffix from
help text (it's not enforced and the non-host's flag is
inconsequential anyway), OR add `if not B.State.s.isHost then say
("not host"); return end` in front of the four toggle handlers for
consistency with `bots` and `start`. Pick whichever matches
intent. Low priority.

---

## Scenario 9 — Mid-bidding host-migration (out-of-scope but related)

If a host transfer happens mid-game (it doesn't currently — host
is fixed for the game's lifetime per `State.lua` schema), the new
host's WHEREDNGNDB tier flags would take over. Not testable in
v0.10.2.

**Verdict:** N/A.

---

## Summary table

| # | Scenario | Verdict | Severity |
|---|---|---|---|
| 1 | Mid-bidding tier flip | PASS-caveat | none (intended) |
| 2 | Mid-trick AKA-receiver flip | PASS-caveat | none |
| 3 | `_partnerStyle` accumulation under tier change | PASS (data leak observed but intentional) | very low |
| 4 | Saudi-Master upgrade mid-game | PASS | none |
| 5 | Gate-less READ scan | PASS | none (structural fields are tier-independent) |
| 6 | Tier flag corruption (`= 1`, `= "true"`) | PASS-robust | cosmetic |
| 7 | Per-bot tier | PASS-by-design | constraint, not bug |
| 8 | Slash help vs implementation drift | FAIL-LOW | help text misleading |

---

## Recommendations (bundled)

**P0 (none.)** No release-blocker found.

**P1:** None. Functional behaviour is solid.

**P2 (cosmetic):**
1. `Slash.lua:143-173` — either enforce host gate or update help
   text. (Scenario 8.)
2. `Slash.lua:153, 161, 169` — use `(WHEREDNGNDB.flag ~= true)` so
   single-toggle recovers from hand-edited non-boolean values.
   (Scenario 6.)
3. Add a `Bot.ResetStyle()` call in each tier-toggle handler if
   the user complaint about "M3lm reading round-1-Basic data" ever
   surfaces. Has a downside (loses cross-tier observability), so
   only do it if user feedback demands it. (Scenario 3.)
4. `Slash.lua` could log to `B.Log` when toggled mid-game so the
   `/baloot log` dump shows tier transitions for post-mortem
   debugging. (Defensive.)

**Note:** Both prior audits and this re-audit conclude the
write-ungated / read-gated split is the **correct** architecture
for cheap counters. Don't reverse this without strong reason.
