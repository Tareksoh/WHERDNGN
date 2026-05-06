# Section 4 (Mid-trick play) audit — HEAD v0.9.0

Source: `docs/strategy/decision-trees.md` lines 100-129 at tag `v0.9.0` (commit 9c32c50).

## 1. Rule 1A revert (Sun OPP-winning Tasgheer = absolute lowest) — INTACT
Line 104. Reads: "play **SMALLEST** of legal in-suit cards (typically absolute lowest)" with annotation "**wired v0.7.2** (was v0.5.11 over-correction 'dump HIGHEST', reverted per #05 re-read)". The v0.7.2 revert from v0.5.11's HIGHEST-dump back to LOWEST is preserved verbatim. Source #05 cited.

## 2. Rule 1B (Sun PARTNER-winning second-lowest) — wouldWin check STILL MISSING
Line 105. Reads: "Play **SECOND-LOWEST** — explicitly NOT absolute lowest" with annotation "**wired v0.7.2**" and "Layered AFTER the smother branch (Section 4 rule 7); only fires when no point-card donation is possible". No precondition guard requiring `not bot.WouldWin(myCard, ...)` is documented in the WHEN cell — bot may second-lowest even when its own card would beat partner's winner. Gap unchanged from prior audit.

## 3. v0.5.18 Takbeer point-card extension (A,T,K,Q,J donate) — clean
Lines 116-117 (Takbeer/Tasgheer certainty-conditioned subsection). Rule 1: "Trick-winner is **CERTAIN partner** … play your HIGHEST card. Donate ابناء" (ابناء = A/T/K/Q/J point cards). Rule 2 mirror for Tasgheer: "Deny ابناء". Wording is clean and consistent. NOTE: both marked `(not yet wired)` — rule documented but not implemented in `pickFollow`.

## 4. K-tripled subsection (مثلوث الشايب) — STILL NOT-WIRED
Lines 123-128. Both rules carry `(not yet wired)`:
- Defensive trickle: K + 2 lower in side suit, smallest first across tricks 1-2 — `pickFollow` Bot.lua:1457 K-tripled trickle branch `(not yet wired)`.
- Offensive bait: lead إكَه but withhold T — `pickLead` Bot.lua:953 K-tripled exploit branch `(not yet wired)`.

## 5. Deceptive overplay (video #08 J/T sacrifice) — STILL NOT-WIRED
Lines 108-110. Three rows: Sun J/T sacrifice, Hokm J-trump (الولد) sacrifice (inverted goal), and anti-trigger (≥3 trumps including A). All three carry `pickFollow.deceptiveOverplay (not yet wired)`. Saudi Master T-variant gate documented but unimplemented.

## 6. Takbeer/Tasgheer certainty-conditioned subsection — clean
Lines 112-121. Heading explicitly "certainty-conditioned"; rule 3 (line 118) gates: "**UNCERTAIN** → fall through to Tahreeb/Tanfeer/Faranka". Priority chain documented: certain-winner-Takbeer/Tasgheer > Tahreeb > Faranka. All five rows marked `(not yet wired)`.

## 7. Hokm trump rank-consecutive vs non-consecutive — wired correctly
Lines 119-120. Consecutive → Takbeer-mandatory HIGHEST (line 119); non-consecutive → INVERT, preserve top, lead/play side first (line 120). Rationale "opp can ambush between your two ranks" preserved. Both `(not yet wired)`. Logic direction is correct.

## Summary
v0.9.0 doc carries 1 INTACT revert (1A), 1 PERSISTENT GAP (1B wouldWin), 5 NOT-WIRED feature rows (1B-aside is wired; deceptive overplay 3, K-tripled 2, Takbeer-certain 5, anti-Faranka pos-4 referenced from §5). Section 4 shape is sound; implementation lag is the standing issue.
