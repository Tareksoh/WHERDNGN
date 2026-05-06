# 11 — G-4 partner-bid suppression in `Bot.PickBid` R2

Files: `C:/CLAUDE/WHEREDNGN/Bot.lua` (commit `9c32c50`, v0.9.0), block at lines 1305-1330; original finding `.swarm_findings/audit_v0.7.1/72_partner_outbid_hunt.md`.

## Verdict

**PARTIAL — R2 wired, R1 not wired (as CHANGELOG says), Sun overcall preserved, suppression is by bid-type, but no regression test pin.**

## 1. R2 suppression block (verified, 1305-1330)

```lua
do
    local g4_partner = R.Partner(seat)
    local g4_partnerBid = S.s.bids and S.s.bids[g4_partner]
    local g4_partnerBidHokm = g4_partnerBid
        and g4_partnerBid:sub(1, #K.BID_HOKM) == K.BID_HOKM
    if g4_partnerBidHokm then
        if sunMinShape(hand) and sun >= thSun then
            return K.BID_SUN
        end
        return K.BID_PASS
    end
end
```

Placement: enters R2 immediately after the `Round 2` comment, BEFORE the `bestSuit` Hokm-search loop (1332-1342). Partner-Hokm short-circuits the loop entirely.

## 2. R1 — does NOT suppress (matches CHANGELOG)

R1 path (lines 1170-1303 at v0.9.0): no analogous `g4_partner...` block. The R1 Hokm-on-flipped branch (lines ~1281-1300) gates only on `not anyHokm and not anySun and bidCardSuit`, so a partner Hokm on the flipped suit is the ONLY suit the R1 branch can issue, and `anyHokm` blocks it. **R1 is fine by structural accident** — the bot in R1 can only bid `bidCardSuit`, so partner's prior `HOKM:bidCardSuit` already trips `anyHokm`. The original 72-doc scenario A is inherently a Round-2 situation (different suit). R1 has no exposure; CHANGELOG is consistent.

## 3. Sun overcall preserved (verified)

The `if sunMinShape(hand) and sun >= thSun then return K.BID_SUN end` line inside the suppression block explicitly allows Sun overcall over partner Hokm. Saudi convention OK (scenario C of original doc).

## 4. By bid-TYPE not by suit (verified)

The check is `partnerBid:sub(1, #K.BID_HOKM) == K.BID_HOKM` — matches ANY `HOKM:*`, regardless of suit. Bot's Hokm in a different trump suit is also blocked. Correct (the convention is "don't compete on Hokm at all", not "don't pick same suit").

## 5. Regression test — MISSING

Searched `tests/test_state_bot.lua` at v0.9.0 (Section C "Bot.PickBid sanity", lines 488-528): only the strong-bid and weak-pass tests exist. **No partner-Hokm scenario, no G-4 pin.** This is a documentation/CHANGELOG gap — fix shipped without a regression pin. Future refactor could silently re-introduce the violation.

## 6. Re-run scenario A

Partner (seat 3) bid `HOKM:S` in R1; bot (seat 1, partner of 3) enters R2 with strong Hokm:♥ Belote. `g4_partnerBid="HOKM:S"`, `g4_partnerBidHokm=true`. `sunMinShape` false (Belote-♥ shape, not Sun). Returns `K.BID_PASS`. **No wire violation.** Original Takweesh-(b) finding now resolved.

## Recommendation

Add a regression test in Section C: seat with strong non-trump Hokm hand, partner already bid `HOKM:<other-suit>` in R1, expect `BID_PASS`. Mirror with Sun-overcall variant (expect `BID_SUN`).
