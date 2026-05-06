# Section 1 (Bidding) — re-audit at HEAD v0.9.0+v0.9.1

`Bot.PickBid` is at `Bot.lua:1071` (doc cell says 890, drift +181). No `Bot.PickAshkal` — Ashkal inlined in R1 block 1183-1274.

## WIRED-CORRECT
- B-1 J+cover+side-Ace: `hokmMinShape` 685-702 (J floor 698, side-Ace 700).
- B-2 4+ trump self-sufficient: 699. B-4 no-J → pass: 698.
- B-5 Hokm-vs-Sun ≥5 margin: 1362-1373 via `K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN`.
- B-6 Belote +20: 1302-1303, 1351.
- S-1/S-5/S-6 `sunMinShape`: 712-728, gated at 1287/1333/1362.
- S-3 3+ Aces bonus: 1112. S-4 Carré → Sun earliest return: 1085. S-8 mardoofa pair: 1113-1114.
- **B-7 / S-7 Sun ≥100 Bel-fear bias** (v0.5.x deferred): wired v0.6.0, Bot.lua:1165-1170, `+8` to `thSun` when `myTotal ≥ K.SUN_BEL_CUMULATIVE_GATE=100`. Verified.
- A-1 dealer/dealer-left only: 1191-1202. A-3 bid-up A: 1212. A-4 T+own-A: 1230-1236. A-5 3+ Aces → direct Sun: 1243. A-6 65/85 pivot: 1252.
- **A-2 Ashkal bid-up rank gate** (v0.9.1): 1214-1223, explicit `bidCardRank=="K"` block. Doc's positive allow-list `{7,8,9,J,Q,singleton-T}` encoded by negative exclusion of A/K/T-covered. Minor gap: a non-singleton T (no own-A) still permits Ashkal — "singleton-T" qualifier not enforced.
- **G-4 Takweesh / partner-bid suppression** (v0.9.0): 1325-1338, partner Hokm in R2 forces PASS; Sun overcall preserved at 1333-1335. R1 not wired but structurally safe (R1 only emits `bidCardSuit`, blocked by `anyHokm`). **No regression test pin** (audit 11_g4_partner_suppress.md §5).

## NOT-WIRED (still missing)
- **B-3 5+ trump Kaboot pursuit flag**. Doc requires `S.s.pursuitFlagBidder` set in PickBid for `pickLead` trick-3 handoff. Not set anywhere. CHANGELOG v0.6.0's "partially handled by v0.5.19 sweep-pursuit-early" (Bot.lua:1544-1565) is misleading: that branch fires on `mySwept == trickNum-1` (clean record), NOT on bidder's 5-trump shape. The bidder-shape→pursuit handoff is absent.
- **G-2 R1 conservative bias**. CHANGELOG v0.6.0 claims "already wired" via R1 base=42 > R2 base=36. False intent-match: 1140-1142 shows Advanced bumps r2 to `max(36, 42-4)=38`, still lower than R1. There's no R1-specific borderline tightening; doc's "borderline R1 → pass" is only coincidentally encoded by the static base difference.
- G-3 R2 commit-strongest at min: R2 base still ≤ R1 base, opposite of doc.

## CODE-WITHOUT-DOC
- 1148-1150 trap-pass M3lm R2 -6.
- 1260-1268 Advanced Ashkal `hasJflip || sCnt>2` skip.

## NOTES
- Doc line refs `Bot.lua:725 / 890 / 953` all stale (PickBid 1071, sweep-pursuit 1544). A-1 cell `State.lua:1464-1487` likely also stale.
- v0.9.0 G-4 wire does NOT break R1 path (1287 unchanged) or Sun-overcall path (1333 still allows BID_SUN over partner Hokm).
