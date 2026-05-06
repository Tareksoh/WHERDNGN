# 45 — Takweesh flow audit (v0.7.2 HEAD)

Files: `C:/CLAUDE/WHEREDNGN/Net.lua` (1977-2231, 555-560, 3848-3851), `C:/CLAUDE/WHEREDNGN/Rules.lua` (349-467, 506).

## 1. Penalty calculation (post-bid Qaid: 26 Sun / 16 Hokm + Bel multiplier)

`Net.lua:2080-2096` selects `handTotal = K.HAND_TOTAL_SUN (130)` or `K.HAND_TOTAL_HOKM (162)` and builds `mult = MULT_BASE * (Sun?MULT_SUN:1) * (Bel/Triple/Four/Gahwa rung)`. After `div10` (line 2151: `floor((raw+5)/10)`):
- Hokm bare: `162*1 / 10 ≈ 16` ✓
- Sun bare:  `130*2 / 10 = 26` ✓ (the doc-stated "26 raw Sun" is post-Sun-mult game-points, matches code per Q5 in `saudi-rules.md`).
- Bel multiplier: applied via `c.doubled` → `MULT_BEL=2`. Hokm Bel `162*2 ≈ 32`; Sun Bel `130*2*2 = 52`. ✓
- Bel-x2 (Triple): `c.tripled` → ×3. Four: ×4. Gahwa: forced ×4 (line 2093). ✓

**Issue (minor):** Gahwa is treated as "highest active rung ×4" for Qaid even when the round wasn't fully played — matches comment intent, but means a Qaid called immediately after Gahwa declaration scores ×4 rather than match-win. Comment acknowledges this as a deliberate design choice for forfeits.

## 2. Forfeit-not-transfer (v0.5.6 / video #33)

`Net.lua:2098-2110`. `mpA = meldA, mpB = meldB` — **both teams keep their OWN melds** ("مشروعي لي ومشروعك لك"). The 14th-audit fix comment explicitly notes the prior bug zeroed the loser's melds. ✓

**However:** the glossary's Q-a description ("offending team's melds **forfeited (zeroed) but NOT transferred** to caller") in `saudi-rules.md:119` **CONTRADICTS** the code (which keeps melds with owners). The code follows `saudi-rules.md:102-108` and the inline comment citing "نظام التسجيل في البلوت". **Doc inconsistency** — `saudi-rules.md` Q-a row says "forfeited (zeroed)" while the code+inline citation says "kept by owner". Resolve before next release.

## 3. Takweesh during SWA window

`HostResolveTakweesh` (line 2050) explicitly nils `S.s.swaRequest`, then sets `phase=SCORE` via `ApplyRoundEnd`. Pending SWA 5-sec timers (lines 2424-2454, 2569-2604) re-check `S.s.swaRequest and req.caller==seat` and `phase==PHASE_PLAY` — both fail → no-op. ✓ (matches 32_swa_races.md).

## 4. False Takweesh (caller wrong → invert)

`Net.lua:2081`: `winnerTeam = foundIllegal and callerTeam or oppTeam`. If no illegal found, `oppTeam` wins, gets `handTotal*mult`. ✓ Caller's team is penalized. `_OnTakweeshOut` (line 2024) prints "called incorrectly. Penalty applied." ✓

## 5. Kasho (pre-bid) vs Qaid (post-bid) phase distinction

**Issue.** `LocalTakweesh` (1977) and `HostResolveTakweesh` (2033) **only allow PHASE_PLAY** (`phase ~= K.PHASE_PLAY` returns). Pre-bid Kasho (procedural error during deal — wrong-card-shown, mis-cut) is **not modeled** — confirmed by glossary line "Kasho — Currently not modeled in code; player-only edge case." This is per design; the `MSG_TAKWEESH` channel only carries the Qaid variant. ✓ Code matches stated scope.

## 6. Takweesh meaning (b) — bid-override (`Bot.PickBid`)

**Gap.** `Bot.PickBid` (`Bot.lua:980-1263`) has no guard preventing a bot from outbidding its **own partner**. It checks prior bids only for "anySun"/"anyHokm" presence and Ashkal eligibility. `partnerBidBonus` (line 761) **adds** to escalation strength but is not consulted for bid-suppression. A bot whose partner already bid `Hokm:♠` will still bid `Hokm:♥` if its own threshold passes — direct violation of video #29 "no bid-takweesh against partner".

## Other notes

- `R.IsValidSWA` is **not** called in the Takweesh path at all (Takweesh scans `t.plays[*].illegal` flags set during prior plays, lines 2056-2068). The `IsValidSWA` references in `Net.lua:2785, 3841` are SWA-resolution paths; cross-contamination not present.
- `MSG_TAKWEESH_OUT` carries `caller;caught;offender;card;reason` (line 2209) — wire format consistent with `_OnTakweeshOut` decoder (557-560).
- `swaRequest = nil` belt-and-braces clear at 2050 is correct; comment at 2041-2049 documents the rationale.
