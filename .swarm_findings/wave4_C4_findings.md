# Wave 4 C4 — Partner Signaling: Fzloky firstDiscard, AKA, partnerStyle
## Agent: C4 | Codebase: WHEREDNGN v0.4.4

---

## A-71 — Score accumulation: no normalization by world count (BotMaster.lua)

**VERDICT: INFO / CONFIRMED NON-ISSUE**

**File:line:** `C:/CLAUDE/WHEREDNGN/BotMaster.lua:519–527`

**Evidence:**

The score loop at lines 519–527 accumulates raw `rolloutValue` diffs without dividing by `numWorlds`:

```lua
for w = 1, numWorlds do
    local world = sampleConsistentDeal(seat, unseen)
    if world then
        for _, card in ipairs(legal) do
            scores[card] = scores[card]
                          + rolloutValue(seat, card, world, S.s.contract)
        end
    end
end
```

The argmax at lines 529–533 compares raw sums: `if scores[c] > bestScore`. The prompt asks whether the fallback deal (uniform random, fired when all 15 constrained attempts fail) skews the sum asymmetrically across candidates.

The fallback deal path is in `sampleConsistentDeal` (lines 252–273). When the constrained sampler fails, it returns a uniform random deal. This uniform world is then evaluated for **all** candidates identically — `rolloutValue` is called for each candidate card against the same `world` table. Since the same world is used for every card scored in a given iteration `w`, the raw sum and the normalized average produce the identical argmax. There is no per-candidate bias from fallback worlds.

However, there is a subtlety: `sampleConsistentDeal` returns `nil` only if implementation is broken (in practice it always returns the fallback). The guard `if world then` means a nil world silently skips all candidate updates for that iteration, reducing the effective sample count uniformly — again symmetric across candidates.

**Conclusion:** the raw-sum vs. normalized-average concern is valid in theory but not in practice for this codebase, because each iteration updates all candidates from the same world. No divergence possible.

**Recommendation:** INFO only. No fix needed. Consider adding an assertion or counter that tracks nil worlds and logs a warning if fallback rate exceeds 50%, as persistent fallback degradation would indicate world-constraint bugs.

---

## A-73 — AKA signal gate: only from trick 2 onwards (Bot.lua line ~1104)

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1103–1104`

**Evidence:**

```lua
local trickNum = #(S.s.tricks or {}) + 1
if trickNum <= 1 then return nil end
```

The comment at line 1101–1102 says: "no opponent voids yet." The prompt asks whether this condition is always correct — specifically, whether the gate should be `tricks_with_discards > 0` rather than `trickNum > 1`.

Analysis:

- `trickNum` here is computed as `#(S.s.tricks) + 1`, meaning it equals 1 during the first trick lead (zero completed tricks), 2 during the second trick lead, etc.
- The gate `trickNum <= 1` fires only on the FIRST lead of the entire hand, suppressing AKA there. On trick 2 lead onwards, AKA can fire.
- The comment's premise ("no opponent voids yet by trick 1") is correct: no one has had an opportunity to fail to follow suit before trick 2 — void inference requires at least one off-suit discard to have occurred.
- The BUG is the inversion of the condition: trick 2 can still have ZERO discards if all three other seats followed suit on trick 1. In that case the AKA signal fires on trick 2 even though `void` inference remains empty and the signal is still unactionable for partner.
- The correct gate, as the prompt suggests, would be: check that `Bot._memory` contains at least one non-nil `firstDiscard` for any seat. However a simpler sufficient gate would be: check that at least one opposing seat has a known void (`Bot._memory[opp].void` has a true entry).
- The current gate is too permissive by one trick. In a clean trick-1 (all follow suit), the bot may announce AKA on trick 2 lead even though partner has no void information to act on. This is noise, not a correctness error (the AKA itself is accurate — the bot really does hold the boss), but the signal value is zero and the `akaSent` flag is consumed, preventing re-announcement later when the signal would have been actionable.

**Recommendation:** Change the gate from `trickNum <= 1` to a check whether any void has been inferred:

```lua
local anyVoidKnown = false
if Bot._memory then
    for s2 = 1, 4 do
        local mem = Bot._memory[s2]
        if mem then
            for _, v in pairs(mem.void) do
                if v then anyVoidKnown = true; break end
            end
        end
        if anyVoidKnown then break end
    end
end
if not anyVoidKnown then return nil end
```

This preserves the intent (signal only when partner has something to act on) without hardcoding a trick number.

---

## A-74 — AKA dedup: per-suit akaSent flag reset and re-boss scenario (Bot.lua lines ~112–113, ~1096–1106)

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:112–113` (flag declaration), `Bot.lua:1096–1107` (dedup and emit)

**Evidence:**

The per-suit `akaSent` flag is initialized in `emptyMemory()` (line 112):
```lua
akaSent = { S = false, H = false, D = false, C = false },
```
and reset on `Bot.ResetMemory()` (line 118–120), which is called on each new round. The dedup check is at lines 1098:
```lua
if mem and mem.akaSent and mem.akaSent[su] then return nil end
```
and the flag is set at line 1106:
```lua
if mem and mem.akaSent then mem.akaSent[su] = true end
```

The prompt describes the re-boss scenario:

1. Bot leads the boss card of suit H in trick 2 → AKA H is fired → `akaSent[H] = true`.
2. An opponent takes the trick by some other means (e.g., the lead was H but opponents held a trump in Hokm and ruffs). Or more precisely: bot's H boss is captured as part of the trick, and subsequently the NEXT highest unplayed H becomes the new H boss.
3. On a subsequent trick, the bot leads H again. The new lead card is the new H boss (say, T-of-H if A-of-H just fell). `S.HighestUnplayedRank("H")` would now return "T" and the bot holds "TH". The AKA gate at line 1092 would pass. But `akaSent[H]` is `true`, so the signal is suppressed.

This IS a real suppression bug: the bot legitimately holds a NEW boss of H (because A-of-H has been played), but the per-suit dedup flag blocks the signal from going out again. The partner was told "bot holds boss of H" when the boss was the Ace; now the boss is the Ten and the partner is not re-informed.

The severity depends on how often this scenario occurs. In a full hand (8 tricks), suit bosses fall frequently in mid-hand. The `akaSent` flag was designed to prevent spam-repeat on the same lead suit, but it over-suppresses: it should block re-announcement on the same underlying boss card, not on the entire suit for the round.

**Recommendation (warning):** Replace the per-suit flat boolean with a per-suit "rank that was already announced" record:

```lua
akaSent = { S = nil, H = nil, D = nil, C = nil },  -- nil or the rank string
```

At check: `if mem.akaSent[su] == r then return nil end` (same rank already announced — true repeat).
At set: `mem.akaSent[su] = r` (record which rank was announced).

This lets a new boss of the same suit signal again after the previous boss falls, while still preventing genuinely redundant re-announcements on the same card.

---

## A-76 — Fzloky: Q/J first-discards are ignored (Bot.lua lines ~752–758)

**VERDICT: INFO**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:752–758`

**Evidence:**

```lua
local r = sig.rank
if r == "A" or r == "T" or r == "K" then
    fzlokyPrefSuit = sig.suit
elseif r == "7" or r == "8" then
    fzlokyAvoidSuit = sig.suit
end
```

Q and J fall into neither branch and produce no signal interpretation. The prompt asks whether Q/J should be treated as low/high/neutral in Saudi Baloot context.

Analysis:

- In Saudi Hokm (Baloot), the Fzloky convention is a well-established suit-preference signal. The traditional high/low partition is A/T/K = "lead this" and 7/8 = "avoid this". Q and J occupy the middle ground.
- In standard Baloot play, Q is 3 points and J is 2 points in non-trump suits. Discarding them is neither a dramatic strength signal nor a clear weakness signal — they represent moderate cards that a player may shed when holding three-card suits or needing to discard from a partially stopped suit.
- The omission of Q/J is a deliberate design choice documented in the comment at line 740–758: "High (A/T/K) = lead this suit, Low (7/8) = avoid this suit." Treating Q/J as neutral (no signal) is a conservative and correct default.
- The prompt notes that "in Saudi Baloot, a Q discard from a short suit could signal strength or weakness depending on context." This is true but context-dependent: the same Q discard from a doubleton signals shortness, from a 4-card suit it may signal relative weakness of that suit vs. another. Without tracking hand length (which the bot does not have access to for opponents), no reliable inference is possible from Q/J alone.

**Conclusion:** The current behavior (ignore Q/J discards) is correct given available information. Adding Q/J interpretation would require either guessing direction (risky) or tracking additional context the bot doesn't maintain. This is an appropriate design limitation, not a bug.

**Recommendation:** INFO only. If a future enhancement tracks opponent hand-length estimates (derivable from the deal size minus tricks played), Q could be mapped to a weak-preference signal. Until then, the neutral interpretation is sound.

---

## A-77 — Fzloky lead preference: leading lowest of signaled suit into an exhausted suit (Bot.lua lines ~763–772)

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:760–773`

**Evidence:**

```lua
if fzlokyPrefSuit then
    local fromPref = {}
    for _, c in ipairs(legal) do
        if C.Suit(c) == fzlokyPrefSuit
           and not C.IsTrump(c, contract) then
            fromPref[#fromPref + 1] = c
        end
    end
    if #fromPref > 0 then
        return lowestByRank(fromPref, contract)
    end
end
```

The bot leads its LOWEST card of the preferred suit. The prompt identifies a specific scenario: bot holds a 7 of the signaled suit, but the K (and all cards above 7) of that suit have already been played. The 7 is now the only card left in that suit; it is therefore the de-facto boss. Leading it into an "exhausted" suit is wasteful — it accomplishes nothing because no opponent can beat it (they are all void or low), but it also doesn't deliver the card to the partner who the signal implied held the high cards.

Investigating `S.HighestUnplayedRank`: it is checked just BEFORE the Fzloky block at lines 731–738:

```lua
if Bot.IsAdvanced() and contract.type == K.BID_HOKM and S.HighestUnplayedRank then
    for _, c in ipairs(legal) do
        local r = C.Rank(c)
        local su = C.Suit(c)
        if su ~= contract.trump and S.HighestUnplayedRank(su) == r then
            return c
        end
    end
end
```

This block fires first (before Fzloky), so if the 7 of the signaled suit is the boss unplayed card, it would already be returned here as a "free trick" lead. This partially mitigates the scenario described in the prompt.

However, the mitigation is incomplete:

1. The boss-boss check at 731–738 only fires in Hokm contracts (`contract.type == K.BID_HOKM`). In a Sun contract, the HighestUnplayedRank short-circuit does not trigger, and the Fzloky block runs unrestricted.
2. Even in Hokm, there is a scenario where the exhausted-suit lead is wasteful without being a "boss": if the bot holds the 7 of the signaled suit and the highest remaining unplayed card in that suit is the Q (held by an opponent), then the bot's 7 is NOT the boss and the HighestUnplayedRank check does not fire. The Fzloky block leads 7 into a suit where partner's promised A/T/K have all been played, following an outdated signal.

The root issue is that the Fzloky pref-suit lead does not check whether the partner's signaled strength cards (A/T/K) are still unplayed. If all of A/T/K of the signaled suit have been played, the signal is stale and following it is wasteful.

**Recommendation (warning):** Before the `lowestByRank(fromPref, contract)` return, verify that at least one of A/T/K of `fzlokyPrefSuit` remains unplayed. The `S.HighestUnplayedRank` function is already available:

```lua
if fzlokyPrefSuit then
    local fromPref = {}
    for _, c in ipairs(legal) do
        if C.Suit(c) == fzlokyPrefSuit
           and not C.IsTrump(c, contract) then
            fromPref[#fromPref + 1] = c
        end
    end
    if #fromPref > 0 then
        -- Guard: signal is stale if partner's promised high cards are gone.
        local topRem = S.HighestUnplayedRank and S.HighestUnplayedRank(fzlokyPrefSuit)
        local signalStillValid = topRem == "A" or topRem == "T" or topRem == "K"
        if signalStillValid then
            return lowestByRank(fromPref, contract)
        end
        -- Fall through to normal lead logic.
    end
end
```

This prevents leading into an exhausted or near-exhausted suit based on a stale Fzloky signal.

---

## Summary Table

| Angle | Verdict   | File:line               | Issue |
|-------|-----------|-------------------------|-------|
| A-71  | INFO      | BotMaster.lua:519–527   | Raw sum vs. normalized average — proven non-issue due to symmetric world usage; nil-world guard is silent |
| A-73  | WARNING   | Bot.lua:1103–1104       | AKA gate fires on trick 2 even when no voids have been inferred yet — akaSent flag consumed wastefully |
| A-74  | WARNING   | Bot.lua:112–113, 1098, 1106 | akaSent per-suit boolean suppresses re-announcement after boss changes within same round |
| A-76  | INFO      | Bot.lua:752–758         | Q/J neutral interpretation is correct given available information; no actionable fix without hand-length tracking |
| A-77  | WARNING   | Bot.lua:760–773         | Fzloky pref-suit lead does not check whether partner's signaled A/T/K are still unplayed; leads into stale/exhausted suits |
