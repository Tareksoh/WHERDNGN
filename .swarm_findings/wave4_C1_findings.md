# Wave 4 C1 Findings — Escalation Chain (Continuation)
Agent: C1 | Codebase: WHEREDNGN v0.4.4 | Date: 2026-05-03

---

## A-48 — fzlokyAvoidSuit + longest-suit tie-break: "≥2 more cards" override

**VERDICT: INFO — boundary condition is permissive-by-design; no bug.**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:869`

**Evidence:**
```lua
if avoidN >= longestN + 2 then
```
The operator is `>=`, so avoid-suit=4, best-non-avoid=2 triggers the override (4 >= 2+2 → true). The boundary fires when the difference is exactly 2, not only when it is strictly greater than 2. This is intentional: the comment at lines 856-859 states "avoid-suit only wins if it **exceeds** the best non-avoid by **≥2**", and the code matches that prose exactly. Using `>` instead would require a 3-card margin, which would be a narrower and more restrictive policy than what the design documents. No correction needed, but the word "exceeds" in the comment is mildly misleading — "matches or exceeds by 2" would be more precise.

**Recommendation (info):** Tighten the comment on line 857 to say "≥2 more cards (difference of 2 also triggers override)" to avoid future confusion about boundary intent.

---

## A-52 — partnerEscalatedBonus for defender Bel: +5 for doubled, +8 for foured

**VERDICT: WARNING — semantic dead-code branch; inflated strength with no reachable rung.**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:524-526` (defender branch), called from `Bot.lua:1170,1199`

**Evidence:**
```lua
if pIsDefender then
    if contract.doubled then bonus = bonus + 5  end
    if contract.foured  then bonus = bonus + 8  end
end
```
`contract.foured = true` means a defender has already declared Four — the last rung available to the defender team. The function is called from `escalationStrength`, which feeds `Bot.PickFour` (Bot.lua:1234). At the point `PickFour` is evaluated, `contract.foured` is already set (only one Four is allowed per chain per `S.ApplyFour`). In practice the phase guard in Net.lua line 3028 (`if S.s.phase ~= K.PHASE_FOUR then return end`) means PickFour is only invoked before Four is applied, so `contract.foured` should never be true when PickFour runs — the +8 is unreachable for the defender calling PickFour.

The danger is subtler: `partnerEscalatedBonus` is also called from `PickDouble` and `escalationStrength` (used by PickTriple). A defender's partner is on the same defender team; if the partner already declared Four, that same partner cannot have Beled again (Four comes after Bel), so the cumulative bonus (+5 for doubled + +8 for foured = +13) never stacks in a single contract. However, nothing prevents the code from adding both if both flags are independently true (e.g., if state corruption or a future rung were added). There is also no guard against the case where the bot reaching `PickDouble` sees a partner who already Foured — that would mean Bel has already occurred and the phase would not be PHASE_DOUBLE, so again gated by caller-side phase checks.

The branch is structurally unreachable under current phase sequencing, but represents latent logic that could misbehave if phase sequencing changes.

**Recommendation:** Add an explicit early-return or assert inside `partnerEscalatedBonus` for the defender branch: if `contract.foured` is already true when a defender bot is evaluating escalation, log a warning and cap the bonus, or document clearly that this branch is guarded externally. Consider replacing the stacking `if doubled ... if foured` with a single `elseif` to prevent double-counting should both flags ever coexist.

---

## A-53 — Bel wantOpen decision: `strength >= jth + 20`

**VERDICT: WARNING — jitter can flip wantOpen between successive calls; likely intentional but undocumented.**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1172,1178`

**Evidence:**
```lua
local jth = jitter(th, BEL_JITTER)   -- BEL_JITTER = 10
...
local wantOpen = strength >= jth + 20
```
`jitter` calls `math.random(-10, 10)`, so `jth` ranges ±10 around `th`. The `wantOpen` threshold is `jth + 20`, which therefore ranges from `th + 10` to `th + 30`. A bot with `strength = th + 15` will set `wantOpen = true` roughly half the time (when `jth <= th - 5`... wait — re-evaluating: `wantOpen = (strength >= jth + 20)`. With strength = th+15 and jth drawn from [th-10, th+10], `jth+20` ranges [th+10, th+30]. `th+15 >= jth+20` → `jth <= th-5`, which has probability ~25/20 = 0 given jth ∈ [th-10,th+10]. More concretely: at the boundary strength ≈ th+20, the bot will fluctuate open/closed by ±10 of jitter, giving a 50% flip rate at exactly the "comfort buffer" value.

This is not a consistency bug in the sense that it breaks game state — each Bel call is a discrete event and the two calls to `jitter` are independent. However, if PickDouble is re-evaluated in a retry loop or guard check, the same bot could return conflicting wantOpen values for the same hand. Net.lua line 2913 shows PickDouble is called once inside a `pcall` and not retried, so the real-game risk is low. The anti-predictability benefit (avoid cliff behavior) appears intentional.

**Recommendation (warning):** Add a comment at Bot.lua:1178 noting that `wantOpen` inherits the same jitter basis as the yes/no threshold and that this creates ~±10-point randomness in the open/closed boundary. If strictly deterministic wantOpen is ever needed (e.g. for replays or test assertions), provide a seeded path. No functional change required for gameplay.

---

## A-54 — Gahwa terminal: `wantOpen = false` hardcoded

**VERDICT: INFO — correct terminal behavior; caller safely discards the second return.**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1253-1254` (definition), `C:/CLAUDE/WHEREDNGN/Net.lua:3082` (call site)

**Evidence — Bot.lua:1253-1254:**
```lua
local yes = strength >= jitter(th, BEL_JITTER)
return yes, false
```

**Evidence — Net.lua:3080-3083:**
```lua
local yes = false
if B.Bot.PickGahwa then
    yes = B.Bot.PickGahwa(bidder)
end
```
The call site assigns only the first return value (`yes`) via a single assignment. Lua silently discards excess return values, so `false` (wantOpen) is silently dropped. This is the correct behavior: Gahwa is terminal (match-win), there is no further rung, and wantOpen is meaningless. The Net.lua comment at line 1403 also documents "Gahwa is terminal so no flag needed."

The audit fix #9 comment in Bot.lua (lines 1244-1247) shows a prior arity mismatch was already corrected to align the signature with PickTriple/PickFour. The current state is clean: definition returns two values, caller only reads one, Lua discards the second without error.

**Recommendation:** No change needed. The behavior is correct and documented. Optionally the caller could be written as `yes, _ = B.Bot.PickGahwa(bidder)` to make the intentional discard explicit for readers.

---

## A-57 — matchPointUrgency cap: ±10 cap vs. halved magnitudes (+5/+2)

**VERDICT: INFO — cap is unreachable; benign dead code but comment is misleading.**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:475-486`

**Evidence:**
```lua
if opp >= target - 15 then mod = mod + 5    -- was +8
elseif opp >= target - 40 then mod = mod + 2 end  -- was +3
if me  >= target - 15 then mod = mod - 5 end
local diff = opp - me
if diff > 50 and diff <= 80 then mod = mod + 3 end
if mod >  10 then mod =  10 end
if mod < -10 then mod = -10 end
```
Maximum reachable positive mod: both `opp >= target-15` (+5) and `diff > 50 and diff <= 80` (+3) fire simultaneously → mod = +8. Minimum reachable: `me >= target-15` (-5) with no positive branch → mod = -5. Neither +10 nor -10 is reachable in the current branch structure. The cap `if mod > 10` / `if mod < -10` is dead code.

The comment "magnitudes were also halved on the opp-near branches" is accurate (was +8/+3, now +5/+2), but the cap value of 10 was not updated to reflect the halved maximums. Leaving the cap at ±10 while actual max is ±8 is harmless (no execution path reaches it), but it creates confusion when reading the code — a reviewer might wonder whether there is a missing stacking path that could reach 10.

**Recommendation (info):** Either reduce the cap to `if mod > 8 then mod = 8 end` / `if mod < -8 then mod = -8 end` to match the actual reachable range, or add a comment explaining the cap is a safety rail for future branch additions and is currently unreachable. The existing comment mentioning "+8/+3 → +5/+2" should also note the cap was left at 10 intentionally (or inadvertently) and is not currently hit.

---

## Summary Table

| Angle | Severity | File:line | Finding |
|-------|----------|-----------|---------|
| A-48  | INFO     | Bot.lua:869 | `>=` is correct; comment "exceeds" is slightly imprecise |
| A-52  | WARNING  | Bot.lua:524-526 | defender `foured` bonus unreachable for PickFour caller; stacking risk if phase guards loosen |
| A-53  | WARNING  | Bot.lua:1172,1178 | wantOpen inherits jitter; flips ~50% at boundary; intentional but undocumented |
| A-54  | INFO     | Bot.lua:1253-1254 / Net.lua:3082 | wantOpen=false correctly returned and silently discarded; no issue |
| A-57  | INFO     | Bot.lua:484-485 | ±10 cap unreachable after magnitude halving; dead-code guard with stale comment |
