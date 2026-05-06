# Audit 57 — Sun-overcall × Belote interaction (HEAD v0.9.0)

Scope: cross-trump TAKE_HOKM and SELF_OVERCALL_SUN reshape `s.contract.{type,trump,bidder}`. Verify Belote scan, sampler pins, bot preservation discipline, and SELF-UPGRADE eligibility loss.

## 1. R.ScoreRound Belote scan — CORRECT

`Rules.lua:631-646` gates on `contract.type == K.BID_HOKM and contract.trump`, scanning K/Q played within `t.plays` filtered by `C.Suit(p.card) == contract.trump`. The `contract` argument is the **final** contract (Net.lua passes `S.s.contract` at end-of-round), so cross-trump rewrites at `State.lua:998-1002` correctly land before scoring. Original-bidder K+Q-of-♠ does NOT register as Belote when contract.trump rewrites to ♥. New-bidder K+Q-of-♥ DOES register because the scan is suit-keyed, not player-keyed. **Verified.**

Subtle property: tricks BEFORE the overcall window do not exist — `S.FinalizeOvercall` runs in PHASE_OVERCALL → PHASE_DOUBLE → PHASE_PLAY (`State.lua:942,1006,1071+`). `s.tricks` is empty at trump rewrite. No retroactive K/Q-of-old-trump can pollute the scan.

## 2. SELF_OVERCALL_SUN (UPGRADE) — CORRECT

`State.lua:980-983` sets `type=BID_SUN, trump=nil`. `R.ScoreRound:631` short-circuits on `contract.type ~= BID_HOKM`, so Belote never fires. `K.MULT_SUN` applies via `Rules.lua:804`. Original-bidder loses the +20 entitlement; this is the documented Saudi semantic ("Sun has no Belote — Hokm-only meld"). **Verified.**

## 3. v0.5.0 H-1 J/9-trump pin in BotMaster sampler — CORRECT post-rewrite

`BotMaster.lua:198-200,271-274` reads `S.s.contract` and `contract.trump` LIVE per `sampleConsistentDeal` call. After `S.FinalizeOvercall` rewrites `s.contract.trump`, the next `BM.PickPlay → sampleConsistentDeal` invocation pins J/9 of the **NEW** trump and pigeonholes unseen new-trump cards to remaining-trump-eligible seats (`BotMaster.lua:286-318`). No cached-trump leak.

One gap: pinning is justified by "the bidder's bid carries a trump signal." Post-TAKE_HOKM the new bidder's hand is the relevant signal source, but the H-1 pin still pins J/9 to **`bidder`** (`BotMaster.lua:271,283`). Because `s.contract.bidder` is rewritten by `State.lua:1000`, this naturally retargets to the new (taker) bidder. **Correct by data flow — confirm in next refactor that `bidder` is read live, not snapshotted.**

## 4. v0.5.1 H-4 Belote-preservation discipline — CORRECT post-rewrite

`Bot.lua:1426-1440 holdsBeloteThusFar(hand, contract)` reads `contract.trump` from the live argument. Caller at `Bot.lua:2864` passes the live `contract` (downstream of `S.s.contract` lookup). When trump rewrites mid-window, the next `Bot.PickPlay` re-evaluates against the new trump:
- Original bidder's K+Q-of-♠ no longer triggers preservation in ♥-Hokm — they may freely discard K♠/Q♠.
- New bidder (taker) holding K+Q-of-♥ now triggers `holdsBeloteThusFar` — preservation kicks in for `#tricks < 4`.

**Verified pivot.** No stale-trump preservation seen.

## Verdict

All four checks pass at HEAD. Architecture is robust because: (a) tricks are empty at overcall window close, (b) all hot paths read `S.s.contract` per-call, (c) the Belote scan keys on suit not seat. No race or stale-cache findings.
