# B-Bot-01 — `Bot.PickBid` review at v0.10.2

Scope: `Bot.PickBid` (Bot.lua:1175-1514), supporting helpers `hokmMinShape` (782-806) and `sunMinShape` (816-832), inlined Ashkal allow-list (1287-1410), Round-2 partner-Hokm suppression (1461-1474).

## Findings

### F1. Hokm-needs-Ace tier-gate (X4/L07): correctly fires at the count >= 4 branch
**Wire status: CORRECT.**

`hokmMinShape` (Bot.lua:782-806) implements the v0.10.0 X4/L07 fix correctly. The `count >= 4` self-sufficient branch (B-2) is now gated for M3lm+ via the early-exit at lines 800-802:
```
if Bot.IsM3lm and Bot.IsM3lm() and not hasAnyAce then
    return false
end
```

Hits all four matrices:
- M3lm+ at count==4, no Ace anywhere → returns false (the half-implemented bug pre-v0.10.0).
- M3lm+ at count==4 with trump-A only → `hasAnyAce`=true, gate bypassed, line 803 returns true.
- Basic/Advanced at count==4 with no Ace → gate skipped (Bot.IsM3lm() false), line 803 returns true.
- All tiers at count==3 still require `hasSideAce` (B-1) — the M3lm gate is additive, not replacing.

The defensive `Bot.IsM3lm and Bot.IsM3lm()` (function-existence + value check) is the correct guard against early-load ordering.

### F2. Hokm seat-position dependency (Pro-2 L09): NOT IMPLEMENTED
The Pro-2 PDF (`03b_secrets_pro_2.txt` lines 18-23) prescribes that seat 1 / seat 2 with a flipped card supporting them should defer to give partner first chance. `Bot.PickBid` has no seat-position deferral — `bidPos` (1295-1305) is computed solely for Ashkal eligibility (`bidPos >= 3`). This was already flagged as missing in `review_v0.10.0/_phase2_xref/xref_X4_pro2_deal.md` (L09 status: NOT IMPLEMENTED). v0.10.2 did not address this.

Out-of-scope for the v0.10.0 fix set; documented gap.

### F3. Sun-direct minimum shape: correctly gated
`sunMinShape` (816-832) returns true iff `aceCount >= 2` OR (`aceCount == 1` AND mardoofa exists). Calls at lines 1423, 1469, 1498 all gate `BID_SUN` returns. Direct Sun bid at thSun=50 base ✓. 4-Aces "carré" early-return at line 1189 correctly bypasses all other paths ✓.

### F4. 3+ Aces → bid Sun direct (skip Ashkal): A-5 enforced
Line 1379: `if ok and aceCount >= 3 then ok = false end` — correctly blocks Ashkal at 3+ Aces. The hand falls through to direct Sun branch (line 1423) since `sunMinShape` is true (aceCount>=2). Note the 4-Ace path is short-circuited even earlier at 1189.

### F5. Ashkal allow-list: correctly enforced — but the T-cardinality check is DUPLICATED
**Wire status: CORRECT but contains dead-code duplication.**

The allow-list (lines 1311-1391) implements:
- **A blocked** (1316): `if bidCardRank == "A" then ok = false`
- **K blocked** (v0.9.1, 1327): `if ok and bidCardRank == "K" then ok = false`
- **T-with-own-A blocked** (A-4, 1349-1355): own-A in bid-up suit
- **T cardinality > 1 blocked** (v0.9.2, 1336-1342): tCount > 1
- **T cardinality > 1 blocked AGAIN** (v0.9.2 #60, 1366-1372): tCount > 1 — IDENTICAL block

The same predicate is computed twice with the same loop. Both write `ok = false` when tCount > 1; second invocation is a no-op since `ok and bidCardRank == "T"` will be false (ok was already cleared) when it'd have mattered. Pure redundancy — likely a merge artifact between the v0.9.2 patch (line 1336-1342) and the v0.9.2 #60 audit fix (line 1366-1372) which both implemented the same check independently.

7/8/9/J/Q/singleton-T-without-A: cleanly accepted (none of the four sieves fire). ✓
Doubleton-J / doubleton-Q: allowed (no rank-based cardinality gate other than for T). ✓ (matches doc — only T has a cardinality requirement).

Confidence on the duplication: HIGH (literally same loop, same predicate, copy of one is ineffective).

### F6. Bid-up A blocks Ashkal even when meld-completion exception (R16) applies
Per video #31 R16, an Ashkal-on-A is allowed in narrow exception when bid-up A could complete a 4-Aces / 100-meld via the 3-card stack draw. The hard `bidCardRank == "A"` block (line 1316) does not check for this exception. Per doc, R16 is "Sometimes" confidence, single-source — likely an acceptable simplification for the bot. Documented gap, not a regression.

### F7. Trap-pass detection: correctly gated for Round 2 only
Line 1252: `if round == 2 and Bot.IsM3lm() and Bot.r1WasAllPass then r2Base = r2Base - 6 end`

`Bot.r1WasAllPass` is reset to false at every round start (State.lua:788) and set to true only in `HostBeginRound2` (State.lua:1844-1846) when R1 actually ended with all 4 PASSes. So inside Round 1 PickBid, the flag is `false` and the gate cannot fire on R1. ✓ Safe.

### F8. Bel-fear bias for Sun (B-7 / S-7 v0.6.0): still active
Lines 1269-1274: when `S.s.cumulative[myTeam] >= K.SUN_BEL_CUMULATIVE_GATE` (=100), `thSun += 8`. Active and gated correctly. The +8 nudge raises the Sun-bid threshold proportional to Bel-fear risk. ✓

### F9. Round 2 Hokm-non-flipped: hand-shape gating correct, Advanced bump small
Line 1483: `bestSuit` search iterates all 4 suits, skipping `bidCardSuit` (R2 cannot reuse the flipped suit per video 28 R15) and gating on `hokmMinShape(hand, suit)`. The Advanced r2Base bump from 36 → 38 (line 1246: `r2Base = math.max(r2Base, r1Base - 4)`) is small but honors the "R2 should be ≥ R1" intent. Documented in code comments as a 13th-audit calibration to fix M3lm bidder-team underperformance.

### F10. Round 2 tie-handling / Sun-vs-Hokm asymmetry: correct
Lines 1498-1512 implement B-5 (16-vs-26 failed-bid asymmetry):
- Both viable + Sun >= bestScore + 5 → Sun
- Sun-only viable → Sun
- Hokm-only viable or both viable but Sun margin <5 → falls through to Hokm at line 1510

✓ Matches decision-trees.md B-5.

### F11. Partner-Hokm-bid suppression (G-4 v0.9.0): correctly gates only on partner Hokm
**Wire status: CORRECT for partner Hokm; INCOMPLETE for opponent Sun.**

Lines 1461-1474 (R2 only):
```
if g4_partnerBidHokm then
    if sunMinShape(hand) and sun >= thSun then return K.BID_SUN end
    return K.BID_PASS
end
```

By bid-type (`partnerBid:sub(1, #K.BID_HOKM) == K.BID_HOKM`), so any HOKM:* trump matches. Sun overcall preserved. R1 unaffected (no analogous block, but R1 only emits `bidCardSuit` — partner's R1 Hokm:bidCardSuit would already win R1 and prevent R2 entry). Verified against `audit_v0.9.0/11_g4_partner_suppress.md` — same conclusion.

### F12. Opponent-Sun-prior bid wire violation (NEW finding, distinct from G-4)
In R2, if an opponent (or partner) has bid Sun before our turn, `anySun=true` is set at line 1195. However:
- `anySun` is consulted only at line 1308 (Ashkal block, R1) and line 1431 (R1 Hokm-on-flipped).
- The R2 path (lines 1461-1513) does NOT consult `anySun`.

Concrete violation: In R2, if partner is at PASS and an opponent bid Sun, the bot can fall through to line 1510 and emit `HOKM:bestSuit`. Per Saudi rule R3 (video #28: "A Sun bid CANNOT be taken by any other player as Hokm"), this is illegal. The host silently drops it (since `winning` already locks Sun), but the wire frame is a rule violation — the same shape of issue G-4 closed for partner-Hokm.

**Severity: minor.** Host-side defensive; visible in logs. Not a play-correctness regression. But it's a structural cousin of G-4 not addressed.

### F13. Bid-takweesh on partner's marginal Sun (video #29): NOT WIRED
Decision-trees.md (line 74) classifies "Bid takweesh" as Common confidence, partial wire. v0.9.0 G-4 closes the partner-Hokm case. The partner-Sun case ("don't takweesh partner who just bought Sun marginally") is NOT suppressed by code:

In R2, if partner bid Sun, line 1469 still allows our Sun overcall (the host drops the duplicate per R4, but the bot is wire-emitting). More importantly: line 1510 could still emit HOKM after partner's Sun, which is illegal per R3 (Sun outranks Hokm).

This is a documented gap, not a v0.10.2 regression. The decision-trees.md row is explicitly tagged `(refinement)`.

### F14. `sunStrength` and `suitStrengthAsTrump` point allocations
**Sun (line 882-927)**: pip values match `K.POINTS_PLAIN` exactly: A=11, T=10, K=4, Q=3, J=2, 9/8/7=0. ✓ Correct per Saudi pip values.

**Hokm trump (line 706-740)**: J=20, 9=14, A=11, T=10, K=4, Q=3 ✓ matches `K.POINTS_TRUMP_HOKM`. **DEVIATION**: 8 and 7 of trump are scored as 2 each (lines 723-724). The canonical Saudi pip values are 0 for both. Comment cites "13th-bot-audit fix" — intentional strength-eval tweak, not pip values. The function is `suitStrengthAsTrump` (a heuristic strength score, not a literal pip count), so this is calibration, not a correctness bug. Length bonus +5 per card beyond 2 (line 728), J+9 synergy +18 (line 730), J-less + count<5 + no 9+A pair → ×0.4 damp (lines 732-738). All advanced-tier-gated where appropriate.

### F15. `aceCount`, `bidCardSuit`, `bidCardRank` derivation: nil-safe except one path
- Line 1179-1180: `bidCardSuit/bidCardRank` correctly use `S.s.bidCard and ...` guards.
- Line 1188: `aceCountAndMardoofa(hand)` — only iterates the hand, no S.s deref needed.
- **Line 1194: `S.s.bids[s2]` is dereferenced WITHOUT a `S.s.bids and ...` guard**, while line 1294 uses the defensive form. If `S.s.bids` is nil, this throws. In practice `s.bids = {}` is initialized when the bid phase starts, so never nil at PickBid call time, but the defensive inconsistency is worth flagging.

### F16. Tier dispatch: `IsAdvanced / IsM3lm / IsFzloky / IsSaudiMaster`
PickBid behavior per tier:
- **Basic**: r1Base=42, r2Base=36, no urgency, no partner-bid bonus, no trap-pass, no Hokm-Ace gate.
- **Advanced** (`IsAdvanced` true): r2Base bumped to max(36, 42-4)=38; sideSuitAceBonus active; sunStrength penalty active; suitStrengthAsTrump damping active; Ashkal Advanced check `hasJflip || sCnt>2` (line 1396-1404).
- **M3lm** (`IsM3lm` true, `IsAdvanced` true): adds Hokm-Ace requirement at all trump counts; trap-pass r2 -=6; matchPointUrgency contribution; opponentUrgency reads.
- **Fzloky / SaudiMaster**: `Bot.IsM3lm()` returns true for both (extends), so they inherit M3lm bidding behavior. Bidding does NOT differ between M3lm and Fzloky/SaudiMaster — those higher tiers diverge in play, not bidding. ✓ Per CLAUDE.md tier dispatch table.

No PickBid path tests `Bot.IsFzloky()` or `Bot.IsSaudiMaster()` directly. Confirmed: bidding is identical M3lm and above.

### F17. `Bot.PickAshkal` does not exist as a separate function
Per audit `audit_v0.9.0/16_section1_now.md` line 1: "No `Bot.PickAshkal` — Ashkal inlined in R1 block." Confirmed at v0.10.2; the Ashkal logic remains inside `Bot.PickBid` round-1 branch (1287-1410). decision-trees.md refers to a `Bot.PickAshkal` that doesn't exist; line refs in the doc cells are stale.

## Verdict

**MOSTLY CORRECT with two redundancies and one structural cousin not closed.**

Hokm-Ace M3lm+ gate (X4/L07), Ashkal allow-list (A/K/T-with-A/T-cardinality), 3+ Aces → Sun direct, partner-Hokm R2 suppression (G-4), trap-pass detection, Bel-fear-Sun bias, Sun-vs-Hokm 5-margin asymmetry, sun/Hokm minimum shape gating: all wired correctly per the cited specs.

Issues found:
1. **F5 (cosmetic, dead code)**: T-cardinality check duplicated at lines 1336-1342 and 1366-1372. Not a bug but pure redundancy from a missed consolidation between v0.9.2 patch and v0.9.2 #60 fix.
2. **F12 (minor wire violation, NEW)**: R2 with prior opponent Sun → bot can emit HOKM:bestSuit (illegal per R3). Cousin of G-4, not closed.
3. **F13 (documented gap)**: bid-takweesh on partner's marginal Sun is not suppressed; decision-trees.md flags this as `(refinement)`.
4. **F15 (defensive inconsistency, latent nil-safety)**: line 1194 lacks `S.s.bids and` guard while line 1294 has it.
5. **F2 / F6 (out-of-scope, documented gaps)**: Pro-2 L09 seat-position deferral (not implemented), R16 Ashkal-on-A meld-completion exception (not implemented).
6. **F14 (intentional deviation)**: 8/7 of trump credited 2 each in `suitStrengthAsTrump` heuristic (canonical pip is 0). Not a bug — strength-eval tweak documented in code.

No regression versus v0.10.0 / v0.9.0 closures was found. The half-implemented L07 bug at the `count >= 4` branch is closed correctly (F1).

## Confidence

**HIGH** for F1, F3, F4, F5, F7, F8, F9, F10, F11, F14, F15, F16, F17 (direct code reads, comparable to existing audits, all paths traced).

**MEDIUM** for F12, F13 (logical inferences from code paths plus host-side rules; would need a unit test or live-game scenario to fully validate the host's silent-drop assumption).

**LOW** for F2, F6 (Pro-2 L09 / Ashkal R16 — single-source rules, doc-flagged as out-of-scope refinements).

## Cross-references

- `Bot.lua:1175-1514` — full `PickBid` body
- `Bot.lua:706-740` — `suitStrengthAsTrump`
- `Bot.lua:782-806` — `hokmMinShape` (X4/L07 fix at lines 800-802)
- `Bot.lua:816-832` — `sunMinShape`
- `Bot.lua:882-927` — `sunStrength`
- `Bot.lua:1336-1342` and `Bot.lua:1366-1372` — duplicated T-cardinality check (F5)
- `Bot.lua:1461-1474` — G-4 partner-Hokm suppression
- `Constants.lua:42-47` — pip-value tables
- `State.lua:1834-1846` — `r1WasAllPass` write site
- `State.lua:788` — `r1WasAllPass` reset
- `audit_v0.9.0/11_g4_partner_suppress.md` — prior G-4 wiring audit
- `audit_v0.9.0/60_a2_singleton_t.md` — v0.9.2 #60 cardinality fix that created the duplication
- `audit_v0.9.0/16_section1_now.md` — Section 1 tier-snapshot
- `review_v0.10.0/_phase2_xref/xref_X4_pro2_deal.md` — L07/L08/L09 Pro-2 cross-ref
- `_pdf_extracted/03b_secrets_pro_2.txt` — Pro-2 PDF L07/L09 source
- `docs/strategy/_transcripts/27_how_to_bid_basics_extracted.md` — video #27 (mechanical bidding)
- `docs/strategy/_transcripts/28_bid_rules_extracted.md` — video #28 R3/R5/R10/R12/R14 (Sun-Hokm legality)
- `docs/strategy/_transcripts/31_ashkal_detailed_extracted.md` — video #31 R1-R30 (Ashkal allow-list)
- `docs/strategy/decision-trees.md` Section 1 — operational rule references

## Suggested follow-ups (informational, not requested)

1. Consolidate the duplicated T-cardinality check at lines 1336-1342 and 1366-1372 (delete one block).
2. Add `S.s.bids and` guard at line 1194 for defensive consistency with line 1294.
3. Consider an `anySun` consultation in R2 to suppress wire-violation HOKM-over-Sun (cousin of G-4, video #28 R3).
4. Add a regression test pin for G-4 partner-Hokm suppression (still missing per audit_v0.9.0/11). Mirror with Sun-overcall variant.
