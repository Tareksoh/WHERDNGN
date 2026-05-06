# 72 — Partner-bid outbid hunt (`Bot.PickBid`)

Files: `C:/CLAUDE/WHEREDNGN/Bot.lua` (1018-1289),
`C:/CLAUDE/WHEREDNGN/State.lua` (1561-1703 `HostAdvanceBidding`).

## Verdict

**CONFIRMED — 45_takweesh_flow.md gap (b) is real.** `Bot.PickBid` has
zero suppression for partner's prior Hokm bid. The bot will outbid its
own partner whenever its own threshold passes.

## 1. Code walk — second-bid logic

`Bot.PickBid` (lines 1018-1289) reads the bid history only for two
booleans: `anyHokm` and `anySun` (lines 1035-1040). Partner-specific
state is consulted in **exactly one place** — Ashkal eligibility
(line 1137: `partnerBid = S.s.bids[partner]`, used only to gate
the Ashkal branch at line 1150).

Round 2 path (lines 1257-1289):

```lua
local bestSuit, bestScore = nil, 0
for _, suit in ipairs(K.SUITS) do
    if suit ~= bidCardSuit and hokmMinShape(hand, suit) then
        ...
        if s > bestScore then bestSuit, bestScore = suit, s end
    end
end
...
if bestSuit and bestScore >= thHokmR2 then
    return K.BID_HOKM .. ":" .. bestSuit
end
```

Only the originally-flipped suit (`bidCardSuit`) is excluded. Partner's
declared trump is **not** in the exclusion set.

## 2. Scenario A — partner Hokm:♠, bot strong Hokm:♥

Partner (seat 3) has bid `HOKM:♠` in R1; bot (seat 1) is now bidding R2
with K-Q-J-9-8 of ♥ (Belote ♥, suitStrengthAsTrump → ~50, +20 Belote =
~70, ≥ thHokmR2≈38). `bestSuit=♥`, `bestScore≈70`. **Returns
`HOKM:♥`** — outbids partner's locked contract. Host
(`HostAdvanceBidding:1655`, `:1675`) silently drops the second Hokm
because `winning` is already set, but the **wire bid was emitted** —
that is exactly the Takweesh-(b) violation per video #29 (the
"don't bid against your partner" rule isn't about who *wins* the
chair, it's about not declaring competing trump intent).

## 3. Scenario B — partner Sun, bot stronger Sun

Partner bid direct Sun. Bot has 4 Aces → line 1032 returns `BID_SUN`
unconditionally. Bot also returns `BID_SUN` whenever `sunMinShape` +
`sun >= thSun` (line 1223). Host then drops the second direct Sun
(line 1599 `priorDirectSun` guard) — bid is wire-emitted, contract is
unchanged. Same Takweesh-(b) violation.

## 4. Scenario C — partner Hokm, bot Sun-strong

Sun-overcall over partner's Hokm is **legitimate** under Saudi rules
(Sun is higher contract). Code does this correctly: line 1223 (R1)
and 1274-1278 (R2) fire `BID_SUN` regardless of partner-bid identity.
**No bug here** — this is the intended overcall path. (Also matches
the Ashkal pathway at 1149-1209, where partner's Hokm is the trigger
for Ashkal-Sun.)

## 5. Edge — partner-bid bonus is escalation-only

`partnerBidBonus` (Bot.lua:788) feeds `PickDouble`/`PickTriple`/etc.
(lines 3002, 3074) — **never** PickBid. There is no read of partner's
bid suit anywhere in PickBid's score computation.

## Fix sketch

In R2 loop (1258), skip suits where `S.s.bids[R.Partner(seat)]` is
`HOKM:<suit>` matching the candidate suit, or — stricter and matching
video #29 — return `BID_PASS` whenever any partner Hokm exists and the
bot's own bid would be Hokm (preserving the legitimate Sun-overcall
case). R1 has the same gap at 1231-1245.
