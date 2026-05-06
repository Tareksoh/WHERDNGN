# 55 — Bargiya Axis Mismatch: Hand-Shape vs Event-Count Impact

## Verdict: CONFIRMED — asymmetric impact (FN strong, FP narrower than feared)

`tahreebClassify` (Bot.lua:1495-1530) splits on `#signals` only.
Recorder `Bot.OnPlayObserved` (Bot.lua:515-535) appends per-suit
on every "discard while partner winning". **No hand-shape input
ever reaches the classifier** — sender محشور-state is invisible.

## Example A — TRUE invite under-weighted (FN, HIGH-IMPACT)

Sender محشور in Spades (5+ incl. A), discards A♠ on partner's
Hearts win. Wire: `signals.S = {"A"}`, `#signals == 1` →
`"bargiya_hint"` (score 1, Bot.lua:1675). Receiver scoring:
`want=2 > bargiya_hint=1` (Bot.lua:1673-1676), so any 2-event
ascending signal in another suit beats the true 5-card invite.
**Rule from video #14 transcript:14-16 (محشور ⇒ fire early as
invite) is silently demoted to noise.** Receiver fails to lead
back; partner's slam suit dies.

## Example B — DEFENSIVE shed false-bargiya (FP, NARROWER)

Per-suit indexing means scattered Aces across DIFFERENT suits
each land at index 1 → all `bargiya_hint`. So scattered-Ace shed
alone does NOT escalate. The genuine FP is narrower:

Sender voids spades by shedding A♠ on partner-win #1, then later
discards 8♠ (only spade left, forced courtesy) on partner-win #5.
`signals.S = {"A","8"}` → `#signals >= 2` → returns `"bargiya"`
(score 3). The 8 was a forced/courtesy discard, NOT cover proof.
Receiver leads ♠ back into a void. Reachable but rarer than A.

## Code-side fix

**Cheap (line-local, honors existing doc-comment promise at
Bot.lua:1499-1501):** require event #2 to be lower-rank than A
(true descending pattern = cover proof, per existing want/dontwant
logic at Bot.lua:1521-1528):

```lua
if signals[1] == "A" then
    if #signals >= 2 then
        local plain = K.RANK_PLAIN
        local r2 = plain[signals[2]] or 0
        local rA = plain["A"] or 0
        if r2 < rA then return "bargiya" end
    end
    return "bargiya_hint"
end
```

This kills Example B's FP (8 < A is true, so still escalates —
**this fix doesn't help B**). Better fix for FP: require
`signals[2]` rank ≥ T (cover-grade), not just lower:
`if r2 >= plain["T"] and r2 < rA then return "bargiya" end`.

**Stronger (recorder change, addresses A directly):** capture
sender length-in-suit at signal time. Recorder at Bot.lua:529-531
becomes `list[#list+1] = {rank=Rank, lenAtPlay=#hand∩suit}`.
Classifier promotes to `bargiya` immediately when
`signals[1].rank=="A" and signals[1].lenAtPlay >= 5` (محشور proxy
matches video #14 rule). Eliminates FN; cost ~1 hash per discard.

## Test pin (still ABSENT per finding #14)

Add to `tests/test_bot_signals.lua`:

| signals.S | cheap-fix | strong-fix |
|---|---|---|
| `{}` | nil | nil |
| `{"7"}` | hint | hint |
| `{"A"} (lenAtPlay 5)` | bargiya_hint | **bargiya** |
| `{"A","8"}` | bargiya | bargiya_hint (forced) |
| `{"A","T"}` | bargiya | bargiya |

## Files
- C:/CLAUDE/WHEREDNGN/Bot.lua:1495-1530 (classifier — fix here)
- C:/CLAUDE/WHEREDNGN/Bot.lua:515-535 (recorder — strong-fix site)
- C:/CLAUDE/WHEREDNGN/Bot.lua:1673-1676 (receiver weights)
- C:/CLAUDE/WHEREDNGN/.swarm_findings/audit_v0.9.0/14_bargiya_2flavor.md
- C:/CLAUDE/WHEREDNGN/.swarm_findings/audit_v0.9.0/32_video14_bargiya.md
