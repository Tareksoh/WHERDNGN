# SCHEMA PROPOSAL — `WHEREDNGNDB.history` row enrichment

This document proposes additions to the per-round telemetry row written
by `S.ApplyRoundEnd` (State.lua:1880-1908) to support the deferred
audit-item analyses listed in `tools/calibrate.py --breakdown`.

**Scope:** these are recommendations only. No code changes to
`State.lua` or `Bot.lua` are included with this work — the analyzer
treats every proposed field as **optional** with a graceful fallback.
Old (v=2) rows continue to parse cleanly under the existing analyzer.

**Schema bump:** when the first of these is implemented, bump
`v = 3` so the analyzer can detect the new shape and old-row-compat
checks remain a one-line `if r.get("v", 1) >= 3` test, mirroring the
v=1 / v=2 split already in place at `tools/calibrate.py:271-306`.

---

## Current schema (v=2, written by `S.ApplyRoundEnd`)

Reference: `State.lua:1880-1908`.

| field        | type   | source                          | notes |
|--------------|--------|---------------------------------|-------|
| `v`          | int    | literal `2`                     | schema version |
| `roundNumber`| int    | `s.roundNumber`                 |       |
| `ts`         | float  | `GetTime()`                     |       |
| `type`       | string | `s.contract.type`               | `K.BID_HOKM` / `K.BID_SUN` / `K.BID_ASHKAL` |
| `trump`      | string | `s.contract.trump`              | `"S"`/`"H"`/`"D"`/`"C"`/nil |
| `bidder`     | int    | `s.contract.bidder`             | seat 1-4 |
| `bidderIsBot`| 0/1    | derived from `s.seats[bidder].isBot` | added v=2 |
| `seat1Bot..seat4Bot` | 0/1 | per-seat `isBot` snapshot   | added v=2 |
| `doubled`    | 0/1    | `s.contract.doubled`            | Bel fired |
| `tripled`    | 0/1    | `s.contract.tripled`            | Bel x2 fired |
| `foured`     | 0/1    | `s.contract.foured`             | Four fired |
| `gahwa`      | 0/1    | `s.contract.gahwa`              | Gahwa fired |
| `forced`     | 0/1    | `s.contract.forced`             | dealer-forced bid (R2 all-pass) |
| `bidRound`   | int    | `s.bidRound`                    | 0/1/2 |
| `bidCard`    | string | `s.bidCard`                     | e.g. `"8H"`, `"AS"`, `""` if redeal |
| `addA, addB` | int    | round delta per team            |       |
| `totA, totB` | int    | game total after round          |       |
| `sweep`      | string | `"A"` / `"B"` / `""`            | final sweep team or none |
| `bidderMade` | -1/0/1 | `true→1, false→0, nil→-1`       | -1 = SWA/Takweesh cancelled round |
| `target`     | int    | `s.target`                      | game-end threshold (typ. 152) |
| `localSeat`  | int    | `s.localSeat`                   | for per-client perspective |

---

## Proposed additions (v=3 candidates)

The following fields, sorted by analyzer impact-per-line.

### 1. `bidderTier` (string, high priority)

**Purpose.** Per-tier bot fail-rate split — currently the analyzer can
only fall back to "what was the global flag at file dump time." If a
user toggles tiers mid-session, every row before the toggle is
mis-tagged.

**Source.** Snapshot the highest active flag at the **moment of the
bid being locked** (not at round end). This matters because PickBid
runs in the round-start phase under whatever tier was set at that
moment; a mid-round flag flip would otherwise leak the wrong tier
into the row.

**Where to write.**

```lua
-- At Bot.PickBid (Bot.lua) — record the tier on the contract itself
-- so it survives until OnRoundEnd.
local function activeTierName()
    if not WHEREDNGNDB then return "Basic" end
    if WHEREDNGNDB.saudiMasterBots then return "SaudiMaster" end
    if WHEREDNGNDB.fzlokyBots      then return "Fzloky"      end
    if WHEREDNGNDB.m3lmBots        then return "M3lm"        end
    if WHEREDNGNDB.advancedBots    then return "Advanced"    end
    return "Basic"
end
-- in Bot.PickBid, when the bot decides on a non-pass bid:
S.s.contract = S.s.contract or {}
S.s.contract.bidderTier = activeTierName()
```

Then in `S.ApplyRoundEnd`'s row builder:

```lua
bidderTier = (bidderIsBot == 1) and (s.contract.bidderTier or "Basic")
             or "human",
```

**Backward compat.** `tools/calibrate.py` already falls back to
`_inferredTier` (top-level flag at dump time) when this field is
missing. After the schema bump only NEW rows are tier-tagged; OLD rows
continue to use the file-level fallback.

**Migration.** None required. Reading old (v=2) rows: `bidderTier` is
nil → analyzer uses the existing fallback path.

---

### 2. `tricksWonByTeam` (table {int, int}, high priority for sweep)

**Purpose.** Sweep-progression tracking. Currently the row exposes only
the **final** sweep outcome (`sweep="A"`/`"B"`/`""`); we cannot tell
whether the bidder team was on track at trick 3 (the threshold above
which Al-Kaboot pursuit becomes plausible).

**Source.** `S.s.tricks` is the canonical per-trick winner array,
already maintained by `S.ApplyTrickEnd`. Iterate at round end.

**Where to write.**

```lua
-- in S.ApplyRoundEnd, immediately before the row builder:
local tricksA, tricksB = 0, 0
local perTrick = {}  -- 1..8 array of "A"/"B"
if s.tricks then
    for ti, t in ipairs(s.tricks) do
        local winner = t.winnerSeat
        if winner then
            local team = (winner == 1 or winner == 3) and "A" or "B"
            perTrick[ti] = team
            if team == "A" then tricksA = tricksA + 1
            else tricksB = tricksB + 1 end
        end
    end
end
-- in row:
tricksA = tricksA,
tricksB = tricksB,
trickWinners = perTrick,  -- {"A","B","B","A",...} length-8
```

**Storage cost.** 8-char string `"ABBABBAB"` is more compact than
an 8-element table; recommend serializing as a single string for SV
size discipline:

```lua
trickWinners = table.concat(perTrick),  -- "ABBABBAB"
```

**Analyzer use.** Three new metrics become possible:
- "bidder team won tricks 1-2 → final-make rate" (early-lead conversion)
- "bidder team had 0/8 at trick 3 → did they recover?" (Al-Kaboot risk)
- "bidder team final sweep rate vs trick-1 sweep-rate" (trick-1 ace
  predictiveness)

**Backward compat.** Missing `trickWinners` / `tricksA` / `tricksB`
treated as "unavailable" — the analyzer's `_report_sweep_progression`
already prints a message pointing to this proposal.

---

### 3. `r0Reason` (string, medium priority)

**Purpose.** R0 sub-categorization. Currently `bidRound=0` collapses
three distinct paths:
1. Forced Hokm/Sun (R2 all-pass → dealer must bid).
2. Voluntary Ashkal (bidder declares "cannot win 4 tricks").
3. Forced Ashkal (qaid-style — R1 dealer-mandatory call).

The analyzer can disambiguate (1) vs (2/3) via `forced + type`, but
it cannot tell voluntary vs forced Ashkal. With ~33 rounds in the
sample dataset NONE of these fired, but as N grows the distinction
matters for tuning `Bot.PickAshkal` thresholds.

**Source.** Set at the bid-resolution site in `S.HostAdvanceBidding`.

**Values.** `"forcedHokm"` / `"forcedSun"` / `"voluntaryAshkal"` /
`"forcedAshkal"` / `""` (R0 didn't fire).

**Where to write.**

```lua
-- in S.HostAdvanceBidding, when finalizing a round-2-all-pass dealer-
-- forced contract:
if everyonePassed then
    s.contract = { ...,
                   forced = true,
                   r0Reason = (declType == K.BID_ASHKAL) and "forcedAshkal"
                              or (declType == K.BID_HOKM and "forcedHokm")
                              or "forcedSun" }
elseif declType == K.BID_ASHKAL then
    s.contract.r0Reason = "voluntaryAshkal"
end
```

**Backward compat.** Missing → analyzer's `_report_r0_breakdown` falls
back to the (forced, type) heuristic already in place.

---

### 4. `sideAKQ` (string or 0, medium priority for Sun forensic)

**Purpose.** Audit Item #5 — Sun-stopper analysis. When a Sun bidder
fails, did they hold AKQ-stopper in any side suit? Currently the row
has no card-composition data; we cannot retrospectively answer
"was the bid technically defensible by side-suit stopper?"

**Source.** Bidder's hand at `Bot.PickBid` time. Stash the side-suit
AKQ-presence string on `s.contract` before the hand is dealt out.

**Format.** A 4-char string `"3210"` where each digit is the count
of {A,K,Q} held in suits {S,H,D,C}, **excluding** the trump suit
(which is meaningless in Sun anyway since there is no trump). Total
range 0-3 per suit, so a single digit suffices.

```lua
-- at Bot.PickBid, after a Sun bid is locked:
if contract.type == K.BID_SUN then
    local hand = s.hostHands[bidder]
    local stopperPerSuit = {}
    for _, suit in ipairs({"S","H","D","C"}) do
        local n = 0
        for _, card in ipairs(hand) do
            if C.Suit(card) == suit then
                local r = C.Rank(card)
                if r == "A" or r == "K" or r == "Q" then n = n + 1 end
            end
        end
        table.insert(stopperPerSuit, tostring(n))
    end
    contract.sideAKQ = table.concat(stopperPerSuit)  -- e.g. "3110"
end
```

**Analyzer use.** New section: of failed-Sun rounds, what % had
`sideAKQ.maxDigit >= 2`? If high, the bid was theoretically defensible
and the failure is a play-execution bug, not a bid-threshold bug.

**Backward compat.** Missing → side-AKQ section is skipped entirely.

---

### 5. `bidPoints` (int, low priority)

**Purpose.** The internal "bid score" computed by `Bot.PickBid`'s
`scoreHand` function (the value compared against `BOT_HOKM_TH`,
`BOT_SUN_TH`, etc.). Logging it lets us empirically measure
threshold accuracy: "of bids with score 65-70, what was the actual
fail rate?" — direct calibration.

**Source.** The `scoreHand` return value at `Bot.PickBid`. Currently
discarded after the threshold compare.

**Where.** Bot.PickBid line where the winning bid is committed.

**Storage.** Single int. Negligible.

**Backward compat.** Missing → "score-bucket" calibration section
is skipped.

---

### 6. `bidderHandStrength` (string, low priority)

**Purpose.** Capture the broader hand fingerprint at bid time so
post-hoc clustering becomes possible (e.g., "bids of shape
4-3-3-3 fail at X%"). Lower priority than `bidPoints` because
fingerprint analysis is exploratory; threshold calibration is the
direct concern.

**Format.** 4-digit suit-distribution sorted desc: e.g. `"5421"`.

**Backward compat.** Missing → distribution clustering section is
skipped.

---

### 7. `partnerSwingerHints` (small table, low priority)

**Purpose.** For M3lm partner-style ledger validation: was the partner
a known "swinger" (high Bel-tendency) at bid time? Currently the
ledger lives in-memory at `Bot._partnerStyle` and dies on /reload.

**Format.**
```lua
partnerSwingerHints = {
    bels = Bot._partnerStyle[partnerSeat].bels,
    fails = Bot._partnerStyle[partnerSeat].sunFail,
}
```

**Backward compat.** Missing → no impact.

---

## Migration / version-bump strategy

| step | action |
|------|--------|
| 1    | Pick a subset of these to implement (recommend #1, #2, #3). |
| 2    | Bump `v = 3` in `S.ApplyRoundEnd`. |
| 3    | Old rows (v=1, v=2) keep their existing field set; nothing is rewritten. |
| 4    | `tools/calibrate.py` already gates feature checks on `r.get("v", 1) >= N`. |
| 5    | Write a one-line CHANGELOG entry: `Telemetry schema v=3 — adds bidderTier, trickWinners, r0Reason for richer offline calibration. Old rows compatible.` |
| 6    | Test with `python tests/run.py` to ensure no test fixtures broke. |
| 7    | Run `python tools/calibrate.py --breakdown=all` on a fresh dump to verify the new fields appear in the report. |

## Ordering recommendation

If implementing incrementally:

1. **`bidderTier`** — highest payoff. Unblocks per-tier bot calibration
   immediately. ~10 lines.
2. **`trickWinners`** — second highest. Unlocks sweep-progression and
   mid-round Al-Kaboot pursuit analysis. ~15 lines.
3. **`r0Reason`** — only matters when N(R0) > 0; current dataset has
   zero R0 rounds. Defer until rare-event sample grows.
4. **`sideAKQ`** — implement only if the Sun-fail forensic becomes a
   priority signal. Currently 6 failures across 33 rounds; not yet
   urgent.
5. **`bidPoints`** / **`bidderHandStrength`** / **`partnerSwingerHints`**
   — exploratory; defer.

---

## Verification

After implementing any subset:

```bash
# Dump fresh data
# (play 5+ rounds in-game, then exit)

# Run analyzer
python tools/calibrate.py --breakdown=all path/to/WHEREDNGN.lua

# Confirm new fields appear in JSON dump
python tools/calibrate.py --json out.json path/to/WHEREDNGN.lua
python -c "import json; d=json.load(open('out.json')); \
           print(set(d[-1].keys()))"
# Expect: bidderTier, trickWinners, r0Reason in latest row.
```

The analyzer is **fully backward-compatible** at every step — old
files remain readable, mixed-schema datasets (e.g., the user combines
v=2 and v=3 dumps) Just Work because every new metric is gated on
field presence.
