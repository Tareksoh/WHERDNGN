# Audit 26 — Bot.PickSWA + R.IsValidSWA (HEAD = v0.7.2)

Files: `C:/CLAUDE/WHEREDNGN/Bot.lua` (3197 lines), `C:/CLAUDE/WHEREDNGN/Rules.lua` (863 lines).

## 1. v0.5.17 minimax — partner adversarial

**Verified.** `R.IsValidSWA` (`Rules.lua:349-467`) is now uniformly universal:
the loop at lines **460-466** iterates EVERY legal card for the next-to-act
seat — opponent and partner alike — and rejects the SWA if any single play
breaks the win:

```lua
for _, card in ipairs(legal) do
    local nh, ns = applyMove(card)
    if not R.IsValidSWA(callerSeat, nh, contract, ns) then
        return false
    end
end
return true
```

The earlier v0.5.16 cooperative branch (partner picks SOME play that
preserves the win) is gone — the comment at **437-459** spells out the
"partner treated adversarially" semantics. Combined with the
`winner == callerSeat` strict check at line 366 (caller alone wins —
partner over-takes don't count) this is genuinely Saudi-strict.

## 2. PickSWA gates — no probabilistic SWA

**Verified.** `Bot.PickSWA` (`Bot.lua:3125-3197`) has zero randomness.
Hard gates:
- `Bot.IsAdvanced()` (line 3126)
- `phase == PLAY` (3127)
- `#hand >= 1 and <= 4` (3130) — the ≤4 cap matches Saudi convention
- `R.IsValidSWA(...) == true` (3151) — single source of truth
- v0.5.21 Hokm trump-top gate (3165-3193)

Returns `true` only when ALL gates pass. No `math.random` in the function.

## 3. v0.5.21 Hokm safety net

**Verified, stricter than Sun.** Lines **3155-3193** add a Hokm-only
predicate AFTER `IsValidSWA` already returned true: collects caller's
top trump rank and the max trump rank held by EITHER opponent; rejects
SWA if `oppTopRank > callerTopRank`. The comment at 3155-3164 frames
this as a belt-and-suspenders gate against suspected validator
false-positives in edge cases. The Sun branch has no equivalent gate —
Sun SWA relies entirely on `IsValidSWA`.

## 4. Card-count thresholds (video #35)

**Threshold logic lives in `Net.lua:LocalSWA` (2351-2464), not Bot.PickSWA.**
v0.5.17 actually routes ALL SWA calls (including ≤3) through the
permission window so the caller's cards display to all players
(`Net.lua:2356-2362, 2377-2380`). The opponent-side flow still allows
takweesh/deny during the 5-sec window. So:
- ≤3 → permission window with auto-approve (v0.5.17 unified path)
- 4+ → same permission window
- 5+ → **NOT enforced** at PickSWA level (the `> 4` gate at `Bot.lua:3130`
  forbids bot SWA at hand-size ≥5 entirely, which is stricter than the
  rule but never violates "5+ mandatory permission")

So bots never reach the "5+ mandatory" case because they cannot even
attempt SWA at hand size 5+. Conservative but correct.

## 5. Bargiya-as-SWA-setup

**Not recognized.** `Bot.PickSWA` has no Bargiya awareness. It only
calls `R.IsValidSWA` on the live hand state. If the bot Bargiya'd
(discarded Ace per `Bot.lua:2238-2289`) and now holds the rest of that
suit, the validator will figure that out from card distribution alone —
but there's no explicit Bargiya-state shortcut, no read of `S.s.tricks`
to see "I Bargiya'd suit X earlier, so partner will lead X back."
Could in principle increase SWA timing accuracy but isn't strictly
required for correctness — the minimax handles the math.
