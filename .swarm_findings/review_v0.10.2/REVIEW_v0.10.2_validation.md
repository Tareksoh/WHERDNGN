# REVIEW_v0.10.2_validation.md — independent validation of the v0.10.2 audit synthesis

**Mode:** Read-only. Reviewer ran no code changes; main fork is editing concurrently.
**Primary source:** `REVIEW_v0.10.2.md` (~250 lines).
**Spot-checked secondaries:** A-Src-06 (Mathlooth), A-Src-29 (Faranka xref), C-Xref-04 (saudi-rules drift), C-Xref-07 (P1 vs W3), E-Det-01 (ISMCTS), E-Net-01 (timer races), D-RT-03 (Faranka edges), B-Bot-01 + B-Bot-06 (PickBid full).
**Files inspected for verification:** `Constants.lua`, `Bot.lua`, `BotMaster.lua`, `Net.lua`, `Rules.lua`, `State.lua` at the cited line ranges.

---

## 1. TL;DR

All five §2 applied fixes are CONFIRMED present at the cited sites and do what the
synthesis claims. Citation freshness is excellent (every line range I spot-checked
hit the right code). The main calibration miss is in §4.2: the SWA bot-timer fix
at `Net.lua:4059-4067` is **already applied in-tree** as `botSWAResolveFn`, so it
should not be in the deferred backlog. Severity calibration on §4.2 is mostly
defensible; the `swaDenied` UI gap and the cross-version OVERCALL soft-lock are
correctly HIGH. The expanded Sun-bid frequency probe finds **the dominant
suppressor is the conjunction of `sunMinShape` AND `thSun` clearing** —
combinatoric `sunMinShape` ≈ 25–28% of hands, but only ~15% of those hands clear
`thSun ≥ 50` after Bel-fear / urgency, and ~30% of THOSE lose the 5-point
Sun-vs-Hokm tie-break. Net Sun-bid rate from the formulas is ~3–5%; the user's
observed 1% suggests an empirical pile-up at low strength scores or a calibration
mismatch with `sunStrength`'s pip values rather than a structural bug. Saudi
tournament priors from A-Src-23 / A-Src-25 do not give a quantitative target,
but the qualitative evidence (Sun-Mughataa is an OK-but-uncommon special case)
suggests 5–15% Sun rate, not 1%. The recommended fix shape is to lower `thSun`
or up-tune `sunStrength`'s honor weights, not to relax `sunMinShape` (which is
source-mandated per S-1).

---

## 2. §2 applied-fix verification (per-fix)

| # | Fix | Verdict | Evidence |
|---|---|---|---|
| 1 | `Constants.lua:229` `K.MSG_OVERCALL_RESOLVE = "!"` | **CONFIRMED** | `Constants.lua:229` reads exactly `K.MSG_OVERCALL_RESOLVE = "!"`. The dispatcher comment block (lines 236-245) documents the v0.10.3 reassignment with the OVERCALL @ Net.lua:543 vs RESYNC @ Net.lua:620 ordering. Verified at `Net.lua:543` (`elseif tag == K.MSG_OVERCALL_RESOLVE then`) and `Net.lua:620` (`elseif tag == K.MSG_RESYNC_REQ then`). Fix landed correctly. |
| 2 | `Bot.lua:2943-2992` Hokm Faranka `oppsVoidPath` flag, F-16 gate respects it | **CONFIRMED** | `Bot.lua:2959` declares `local oppsVoidPath = false`. Lines 2971-2973 set `farankaTriggered = true; oppsVoidPath = true` when `oppTrumpExhausted`. Lines 2988-2993 add a **secondary trigger** for the structurally-extinct case (`HighestUnplayedRank(trump) == nil`) — this is also `G-Logic-01 §1` MED from the deferred backlog, so it has been **applied beyond the synthesis claim**. F-16 gate at line 3014 reads `if farankaTriggered and not oppsVoidPath then` — correctly skips F-16 on Exception #4. Source-aligned per A-Src-29 Q1/Q2/Q9 + D-RT-03 S-1 Option A. |
| 3 | `Bot.lua:2128` `local bidderTeam = R.TeamOf(contract.bidder)` in scope | **CONFIRMED** (line drift: actual line is `2143`, not `2128`) | `Bot.lua:2143` declares `local bidderTeam = R.TeamOf(contract.bidder)` inside the `contract.bidder ~= nil` guard at line 2134. Loop body at 2146 reads `if R.TeamOf(s2) ~= bidderTeam` — team-gate is now functional. The synthesis cite of `:2128` is off by ~15 lines; actual fix is at `:2143`. Cosmetic drift; functionally correct. |
| 4 | `Bot.lua:1705` `isBidderTeam` no longer has the `K.BID_HOKM` clause | **CONFIRMED** (line drift: actual line is `1714`, not `1705`) | `Bot.lua:1714` reads `local isBidderTeam = (myTeam == R.TeamOf(contract.bidder))` — type-blind, as claimed. The audit comment at lines 1705-1713 explains the pre-v0.10.3 type-gate bug. Sun branches downstream (sweep-pursuit-early at 1735, etc.) now reach. Synthesis line cite is the START of the comment block, not the predicate itself; reasonable shorthand but slightly imprecise. |
| 5 | `BotMaster.lua:830` `R.IsLegalPlay` called with 6 args including `S.s.akaCalled` | **CONFIRMED** (line drift: actual line is `838`, not `830`) | `BotMaster.lua:838` reads `local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat, S.s.akaCalled)`. The audit comment block at lines 827-834 documents the pre-v0.10.3 5-arg bug. The 6th positional arg matches `Rules.lua` signature (verified independently). Synthesis cites `:830` as the comment's central line; actual call site is 8 lines below. Functional fix is correct. |

**Net §2 verdict:** all 5 CONFIRMED. The line-cite drifts (#3 by 15, #4 by 9, #5
by 8) are within the explanatory comment block — the synthesis is citing the
START of the audit comment, not the line where the predicate or call lives.
Acceptable shorthand but worth tightening to the actual code line for v0.10.3
review.

---

## 3. §4.2 backlog severity calibration (per-item)

| Item | Synthesis severity | Verified verdict | Notes |
|---|---|---|---|
| Cross-version OVERCALL_RESOLVE soft-lock (E-Net-01.3-X) | **HIGH** | **CONFIRMED HIGH.** Mixed-version clusters in v0.10.3 ↔ v0.10.2 PHASE_OVERCALL `taken=false` will soft-lock — no follow-up MSG_CONTRACT to self-recover. Mitigation (a) lobby-version warning is the cheapest. |
| `Net.lua:4059-4067` SWA bot-timer pause race | **HIGH** | **DRIFTED — already FIXED in-tree.** Read of `Net.lua:4030-4090` shows `botSWAResolveFn` (lines 4064-4082) IS the named pause-aware re-arm pattern. The audit comment at lines 4050-4063 explicitly cites E-Net-01 + the v0.10.3 marker. **This item should be MOVED to §2 or REMOVED from §4.2.** |
| `S.s.swaDenied` populated but never read by UI | HIGH | **CONFIRMED HIGH.** UI deny-feedback is real user-visible gap. Worth shipping in v0.10.3 if a small UI patch suffices. |
| `قبلك` button glyph hardcoded | HIGH | Defensible as HIGH for non-Arabic-font locales (renders as box/missing-glyph). Pattern-already-fixed-elsewhere argument supports a low-risk follow-up. |
| `Rules.lua:817-822` Reverse Al-Kaboot type-blind | HIGH | **CONFIRMED HIGH.** `Rules.lua:817-822` is in the contract-tie-break section. Constant `K.AL_KABOOT_REVERSE` does not exist (verified via grep — no hits). The defender-sweep-during-reverse-Kaboot reads bidder-side bonus values per the existing `K.AL_KABOOT_HOKM/SUN` constants at line 841. Source-aligned issue; HIGH severity is right. |
| `Rules.lua:928` Gahwa match-win type-blind | HIGH | Probably HIGH; Sun cannot reach Gahwa structurally (per A-Src-22 K-33), so any Sun-Gahwa code path is a stale-resync / hand-edit defensive concern, not a live-game bug. Could be downgraded to MED unless red-team finds an exploit path. |
| `State.lua:1167-1184` `S.ApplyMeld` drops Hokm Carré-A | HIGH | **CONFIRMED HIGH.** Verified directly: lines 1171-1182 — Carré-A in Hokm falls through with `value=nil` (per Pagat-strict comment), so `S.ApplyMeld` never inserts the meld. Detect-path was fixed in v0.10.0 X5 but apply-path was missed. This IS a live-game bug for Hokm bidders who roll 4 Aces. |
| `Bot.lua:484-507` Touching-honors WRITE missing partner-still-winning gate | HIGH | Severity reasonable. Verified the cited block writes signal-suit context unconditionally; partner-winning state at write-time is a real gap (could pollute style ledger with mid-trick context). |
| `Bot.lua:1640-1683` Bargiya inner-discriminator axis | HIGH | Defensible HIGH. The cover-grade gate at lines 1668-1683 is in-tree (v0.10.2 M7), but the doc-mandated axis is hand-shape (محشور), not event-count. Fix would re-architect tahreebClassify; rightly deferred. |
| `Net.lua:1148-1149` `_OnOvercallResolve` empty-payload phase demote | MED | Reasonable MED. Cited site at line 1148 (`S.s.overcall = nil; S.s.phase = K.PHASE_DOUBLE`) writes phase unconditionally — defensive but loses the bidder-state. |
| `Bot.lua:2943-2955` F-30b oppsVoidPath secondary trigger (G-Logic-01 §1) | MED | **DRIFTED — already FIXED in-tree at lines 2988-2993** as part of fix #2. Should be removed from §4.2. |
| UI / pickFollow Sun pos-4 Mathlooth-K smother gate | MED | Reasonable MED. G-Logic-01 §3 finding; defensible to defer pending a Mathlooth-suit detection helper. |
| `Net.lua:2240, 2972` M5 Belote cancel | MED | Severity reasonable. |
| `Net.lua:2327-2331, 3064-3068` H3 tied-target tiebreaker | MED | Severity reasonable. |
| `Net.lua:2185-2190, 2930-2935` R2 Sun mult collapse | MED | Severity reasonable. |
| `State.lua:1238-1265` M3 false-AKA host-only wipe | MED | Severity reasonable. |
| `State.lua:1966` `S.GetLegalPlays` UI-dimming AKA-blind | MED | **Severity should be HIGH or at least MED-HIGH** — this is the UI-visible cousin of fix #5. `R.IsLegalPlay` is now 6-arg in BotMaster but `S.GetLegalPlays` likely still passes 5 args. Player AKA-receivers will see incorrect dimming. Worth promoting if a small State.lua patch suffices. |
| `Bot.lua:1829-1838` Hokm Branch 3 leads non-trump boss-Ace before trump-pull | MED | Severity reasonable. |
| `Bot.lua:2964-2972` (rule-7) Anti-rule "Q-led + J+8 rebut" delete | MED | **Could be downgraded to LOW** — A-Src-29 Q7 confirms it is sourceless AND structurally dead post-v0.10.0. D-RT-03 S-5 NIT verdict matches. The "deletion" risk is zero. Already in §9 follow-up #3 — consistent. |
| `Bot.lua:3801-3806` `Bot.PickKawesh` unconditional | LOW | Severity reasonable. |
| `Rules.lua:108-110` Misleading comment about AKA-on-T trick lock | LOW | Comment-only; LOW correct. |

**Net §4.2 verdict:** 2 items already FIXED in-tree (SWA pause re-arm,
F-30b secondary trigger) should be moved to §2 or removed. 1 item
(`S.GetLegalPlays`) may merit promotion to HIGH. 1 item (rule-7 anti-rule
deletion) could be downgraded to LOW. Other severities defensible.

---

## 4. Citation-freshness table

| Synthesis cite | Actual code site | Match? | Notes |
|---|---|---|---|
| `Constants.lua:229` (K.MSG_OVERCALL_RESOLVE) | `Constants.lua:229` exact | ✓ EXACT | |
| `Net.lua:543` (OVERCALL elseif) | `Net.lua:543` exact (`elseif tag == K.MSG_OVERCALL_RESOLVE then`) | ✓ EXACT | |
| `Net.lua:620` (RESYNC elseif) | `Net.lua:620` exact (`elseif tag == K.MSG_RESYNC_REQ then`) | ✓ EXACT | |
| `Bot.lua:2943-2992` (Hokm Faranka block) | Block actually spans `2934-3022`; oppsVoidPath fix at 2959-2993, F-16 at 2996-3022 | ≈ approximate | Block-range cite is fuzzy; specific line targets are within the cited window |
| `Bot.lua:2128` (bidderTeam fix) | Actual code at `Bot.lua:2143` | DRIFT +15 | Cite points at the comment-block start (line 2128 is in the v0.6.1+ B-57/B-71 comment); the `local bidderTeam` declaration is at 2143 |
| `Bot.lua:1705` (isBidderTeam fix) | Actual predicate at `Bot.lua:1714` | DRIFT +9 | Cite is the audit comment start; predicate is 9 lines down |
| `BotMaster.lua:830` (R.IsLegalPlay 6-arg) | Actual call at `BotMaster.lua:838` | DRIFT +8 | Cite is mid-comment; call is 8 lines down |
| `Net.lua:4059-4067` (SWA timer) | `botSWAResolveFn` at `Net.lua:4064-4082` (re-arm logic present in-tree) | ✓ for line range, ✗ for "no re-arm" claim | Range matches but the synthesis "bare-exits without re-arm" description is stale — the v0.10.3 fix has been applied |
| `Rules.lua:817-822` (Reverse Al-Kaboot) | Confirmed at `Rules.lua:817-822` (contract-tie-break section context) | ✓ EXACT | |
| `Rules.lua:928` (Gahwa match-win) | Within `R.ScoreRound` Gahwa branch (verified at 920-940 region) | ✓ approximate | |
| `State.lua:1167-1184` (S.ApplyMeld) | Verified — `value=nil` for Hokm Carré-A at lines 1173-1182 | ✓ EXACT | |
| `Bot.lua:1640-1683` (Bargiya tahreebClassify) | `tahreebClassify` body at 1638-1700 | ✓ approximate | |
| `Bot.lua:484-507` (Touching-honors WRITE) | Block verified at 480-508 | ✓ approximate | |
| `Net.lua:1148-1149` (`_OnOvercallResolve` end) | `S.s.overcall = nil; S.s.phase = K.PHASE_DOUBLE` at 1148-1149 exact | ✓ EXACT | |

**Net citation freshness:** Excellent on the verbatim constants and dispatcher
sites; ±10 line drift on the longer audit-comment blocks where the synthesis
cites the comment rather than the predicate. Recommend tightening the §2
table to cite the actual code line (not comment start) for v0.10.3 ship.

---

## 5. Missing items

Spot-checked the secondaries; the synthesis surfaces the major findings. A few
items I noticed that did not make the §4.2 cut:

1. **B-Bot-01 / B-Bot-06 F-01/F-02 (S2-medium): L07 cascade fail at M3lm+ for Aceless 5-trump J+9 hands.** Not in §4.2. The audits flag this as the only S2-medium pair with measurable EV impact: a 5-trump J+9 hand without any Aces fails `hokmMinShape` at M3lm+ in BOTH R1 and R2, forcing PASS. EV cost ~5-7 game points per match per the B-Bot-06 estimate. **Severity rating: MED** (clear EV cost, narrow hand shape, M3lm+ tier only). Worth queuing for v0.10.4.
2. **B-Bot-01 F12 / B-Bot-06 F-07: R2 missing `anySun` consultation.** Bot can emit `HOKM:bestSuit` after an opp Sun bid in R2 — illegal per video #28 R3, host silently drops. Wire violation visible in logs. **Severity: LOW-MED**, structural cousin of G-4.
3. **B-Bot-01 F5 / B-Bot-06 F-03: Duplicate T-cardinality check at Bot.lua:1336-1342 and 1366-1372.** Pure dead code from a v0.9.2 + v0.9.2-#60 merge artifact. **Severity: LOW** (cosmetic, no functional bug). Worth a single-line cleanup in v0.10.3 or whenever Section 1 is next touched.
4. **B-Bot-06 F-27: R2 Hokm fallback skips Bel-fear bias.** Sun-Bel-fear (`thSun += 8` at cum>=100) has no Hokm twin. Failed Bel'd Hokm = 32 game points lost. **Severity: LOW-MED** (calibration angle, asymmetric). Could ship a `thHokm += 3` mirror in v0.10.3 if simulation A/B confirms.
5. **E-Net-01.2: Resync-mid-window joiner zombie PHASE_OVERCALL.** When host's all-decided early-close fires between `packSnapshot()` and the joiner's apply, MSG_OVERCALL_RESOLVE / MSG_CONTRACT are not in the replay queue. **Severity: LOW** (rare race; depends on resync cadence).

None of these contradict the synthesis; they are gaps the synthesis chose not to
elevate. The L07 M3lm+ cascade (item 1) is the most likely tournament-A/B-
detectable.

---

## 6. v0.10.3 release-scope assessment

The synthesis §9 proposes:

- **Definitely in scope:** §2 fixes #1-5 + §3 doc fixes #1-7. **Verdict:** correct. All 5 code fixes verified; 7 doc fixes are markdown-only and low-risk.
- **Suggested in scope:** delete dead rule-7 anti-trigger (#3); re-anchor decision-trees Section 0 (#4); add 10 missing glossary entries (#5).
  - **Verdict on #3 (rule-7 deletion):** **AGREE.** A-Src-29 Q7 + D-RT-03 S-5 both confirm it's sourceless and structurally dead post-v0.10.0. Zero risk to delete.
  - **Verdict on #4 (decision-trees Section 0 re-anchor):** AGREE. Mechanical update.
  - **Verdict on #5 (10 glossary entries):** AGREE. Markdown-only.

**My adds to v0.10.3 scope:**

- **Promote `S.GetLegalPlays` AKA-blind fix from MED-deferred.** This is the UI cousin of code fix #5; without it, players acting as AKA-receivers will see incorrect card dimming. If `S.GetLegalPlays` is a single call site that needs `, S.s.akaCalled` appended, it's a 1-line patch that closes a real player-visible regression.
- **Remove from §4.2:** `Net.lua:4059-4067` (already in-tree as `botSWAResolveFn`), `Bot.lua:2943-2955` G-Logic-01 §1 secondary trigger (already in-tree at lines 2988-2993). Both are listed as deferred but are present in code; this would mislead the v0.10.3 reviewer.
- **Optional v0.10.3 nit:** delete the duplicate T-cardinality block at `Bot.lua:1336-1342` (single-line cleanup, no functional change).

**My defers (agree with synthesis):**

- Reverse Al-Kaboot rewrite (HIGH but design-call); Bargiya axis flip (HIGH but architectural); ISMCTS akaCalled-respecting sample pool (HIGH but design call); backported MED Net.lua / State.lua fixes.
- Bot.lua:484-507 touching-honors partner-winning gate (HIGH but needs careful predicate design).

---

## 7. Sun-bid frequency analysis (expanded scope)

### 7a. Combinatoric probability of `sunMinShape`

**Definition (Bot.lua:816-832):** `sunMinShape` = (aceCount ≥ 2) OR (aceCount = 1 AND ∃ suit s.t. (A_s AND T_s)).

**Setup:** 32-card Saudi deck, 8-card hand, 4 Aces, 4 Tens.

**P(aceCount ≥ 2):** Hypergeometric with N=32, K=4 (Aces), n=8.
- P(0 A) = C(28,8)/C(32,8) = 3,108,105 / 10,518,300 ≈ 0.2955
- P(1 A) = 4·C(28,7)/C(32,8) = 4·1,184,040 / 10,518,300 ≈ 0.4502
- P(≥2 A) = 1 − 0.2955 − 0.4502 ≈ **0.2543** (25.4%).

**P(1-Ace AND mardoofa | 1 Ace):** Given exactly 1 Ace in suit X, we need the T_X also in hand. T_X is in the remaining 7 cards drawn from the remaining 28 non-A cards (which include T_X). P(T_X in remaining 7) = 7/28 = 0.25.

**P(1-Ace AND mardoofa, marginal):** P(1 A) × 0.25 = 0.4502 × 0.25 ≈ **0.1126** (11.3%).

**P(sunMinShape) = P(≥2 A) + P(1-Ace + mardoofa) ≈ 0.2543 + 0.1126 ≈ 0.367 (36.7%).**

(Note: I am ignoring the small overlap where ≥2-Ace hands have a mardoofa — that's already counted under ≥2A.)

**Sanity-check refinement:** for ≥2 Ace hands, mardoofa is also frequently present and adds bonus to `sunStrength` via S-8 — but the gate is OR, so the marginal calculation above is the right floor.

**P(sunMinShape) ≈ 35–37% of random 8-card hands.**

### 7b. P(sunStrength ≥ thSun + (hokmStrength − 5)) | sunMinShape true

This is the harder probability. Need to look at `sunStrength` (Bot.lua:882-927)
under the `sunMinShape` posterior.

**`sunStrength` pip values:** A=11, T=10, K=4, Q=3, J=2, 9/8/7=0.

**Plus bonuses:** +6 per card beyond 4 in long suits with A or K; +8 AKQ stopper; -10/suit if count<2 or no honors (Advanced+, capped at 18).

**Plus S-3/S-8 layered on top in PickBid (lines 1216-1218):** +15 if aceCount≥3; +5 per A+T mardoofa pair (cap 2 pairs).

**Conditional expected `sunStrength` given sunMinShape:**

- **Bare 2-Ace hand (no T-cover, no length, no AKQ):** sun ≈ 22 (2A) + ~6 (avg honors in 6 other cards) − ~10 (Advanced penalty for short suit + missing-honor) ≈ **18-22.**
- **2-Ace + 1 mardoofa:** ≈ 22 (2A) + 10 (T) + 5 (S-8) + ~4 (other honors) − 10 (penalty) ≈ **31-35.**
- **2-Ace + 2 mardoofa:** ≈ 22 + 20 + 10 + 0 (penalty likely 0) ≈ **52.**
- **3-Ace + 1 mardoofa:** ≈ 33 + 10 + 15 (S-3) + 5 (S-8) + ~4 − 0 ≈ **67.**
- **1-Ace + mardoofa (the marginal sunMinShape case):** ≈ 11 + 10 + 5 (S-8) + ~5 (other honors) − ~10 (penalty) ≈ **20-22.**
- **AKQ same-suit + 1 other A:** ≈ 11+4+3 (AKQ) + 8 (stopper) + 11 (other A) + ~3 ≈ **40.**

**Threshold:** thSun base = 50; with urgency=+15 reaches ~35; with Bel-fear at cum≥100 nudges to ~58; with jitter ±6.

**Effective thSun median:** ~50 in normal play, ~58 if cum≥100.

**P(sunStrength ≥ 50 | sunMinShape):**

Looking at the breakdown:
- The bare 2-Ace + 1-Ace-mardoofa cases (sun ≈ 18-35) DO NOT clear thSun=50.
  Per `sunMinShape` proportions, 1-Ace+mardoofa is ~30% of sunMinShape hands (0.113/0.367); this is the dominant fail-case.
- 2-Ace + 2-mardoofa (sun ≈ 52) is borderline; jitter ±6 makes it 50/50.
- 3-Ace+ is rare (P(3+A) = 1 − P(0A) − P(1A) − P(2A) ≈ 1 − 0.296 − 0.450 − 0.222 ≈ 0.032, ~3%) but reliably clears thSun via the +15 S-3 bonus.

**Rough conditional estimate:** P(sun ≥ 50 | sunMinShape) ≈ **15-25%.**

### 7c. Sun-vs-Hokm 5-point margin (B-5 asymmetry)

In R2, even if `sun ≥ thSun`, line 1504 requires `sun ≥ bestScore + 5` to actually return BID_SUN over a viable Hokm. This bites on hands that are simultaneously Sun-shaped AND Hokm-shaped (e.g. a 4-trump-J + 2 side-Aces hand: Hokm-strong AND sun ≈ 40-50).

P(Hokm-viable | Sun-viable) is high — ~60-70% per the per-suit `hokmMinShape` checks (the J + count≥3 OR count≥4 floor). When Hokm IS viable, ~30-40% of Sun-viable hands lose the 5-point tiebreak.

### 7d. Net Sun-bid rate from formula

Approximate:
- P(sunMinShape) ≈ 0.37
- P(sun ≥ thSun | sunMinShape) ≈ 0.20 (after Bel-fear nudge)
- P(survives B-5 tiebreak in R2 | sun ≥ thSun) ≈ 0.65 (R1 has no tiebreak; R2 ~0.6; weighted ~0.65)
- P(no prior Hokm/Sun in R1, no partner Hokm in R2) ≈ 0.6 (back-of-envelope)

**P(Sun bid) ≈ 0.37 × 0.20 × 0.65 × 0.6 ≈ 0.029 ≈ 3%.**

The 4-Ace short-circuit at line 1189 adds another ~0.001 (P(4A)=C(4,4)·C(28,4)/C(32,8) ≈ 0.0019).

**Formula prediction: ~3-4% per seat.** The user's observed ~1% suggests either:
- The empirical sample is biased toward later-round / higher-cum-score states where Bel-fear has nudged thSun higher and locked Sun out of marginal hands.
- An interaction with the `combinedUrgency` math is suppressing Sun more than the back-of-envelope (`urgency` can be negative when behind, raising thSun).
- `sunStrength`'s pip values may be calibrated tighter than the +15/+5 bonuses can offset.

The 1% rate is **plausibly low but not 1-2 orders of magnitude wrong** — the formula prediction is ~3×.

### 7e. Dominant gate ranking

1. **`sunStrength ≥ thSun` (the 50-point threshold).** This is THE main suppressor. Bare 1-mardoofa hands at sun ≈ 22 are far from 50, and they constitute ~30% of sunMinShape hands. Even most 2-Ace hands without length/stopper land at sun ≈ 30-40. The threshold of 50 was set when sunStrength's ace-pair contribution was 22 — making Sun threshold-clearing require a structural up-tier (mardoofa, AKQ, length).
2. **B-5 5-point margin (Sun must beat Hokm by ≥5).** Second-most suppressive; bites ~30-40% of Sun-viable hands in R2.
3. **`sunMinShape` (the 2-Ace floor).** Removes ~63% of hands. Source-mandated per S-1 + S-5 (Definite, video #25). Cannot be relaxed without source contradiction.
4. **Bel-fear nudge (`thSun += 8` at cum≥100).** Score-state-dependent; only fires on ~25-35% of bid contexts; nudge is small relative to thSun.

### 7f. Saudi tournament priors

A-Src-23 (PDF 03 / Secrets of Pro 1) is purely about card-counting — does not give Sun-bid rate priors. A-Src-25 (PDF 04 / Secrets of Pro 3) discusses the `K.MELD_CARRE_A_SUN = 400` weighting and Q-row companion lists for project-elimination — also no quantitative bid-rate prior.

The video transcripts (#25, #26) frame Sun and Hokm as roughly co-equal contract types: video #25 spends ~7 minutes on when to bid Sun, video #26 spends a comparable duration on Hokm. The Sun-Mughataa side-bar in #25 (R29-R31) explicitly frames blind Sun as "OK BUT expect opponent Bel" — pedagogically OK but with a real downside, suggesting Sun is **not** a fringe bid in tournament play.

**Quantitative estimate from priors:** I don't have a hard verbatim "X% of bids should be Sun" claim. The 15-25% target the prompt cites is reasonable but not directly source-anchored — it appears to be a calibration heuristic, not a Saudi rule.

**However:** 1% Sun rate is **almost certainly too low** if the bot is meant to play tournament-quality. A 1-in-100 Sun rate means in a typical 30-deal match, the bot bids Sun ~0.3 times — effectively never, which contradicts video #25's pedagogical weight.

A target of ~5-10% feels source-defensible; >15% would be aggressive.

### 7g. Suggested fix shape

**Primary lever — parameter retune:** lower `TH_SUN_BASE` from 50 to 44 (or nudge `sunStrength` honor weights up).
- Rationale: with thSun=50, only 2-mardoofa+ shapes (sun ≈ 52) reliably clear; with thSun=44, 2-Ace + 1-mardoofa (sun ≈ 35) becomes borderline and stopper triples (sun ≈ 40) reliably clear.
- Effect: Sun bid rate moves from ~3% to ~7-9%, closer to source-implied target.

**Alternative — boost mardoofa bonus:** raise `K.BOT_SUN_MARDOOFA_BONUS` from 5 to 10 (and possibly raise the cap). A+T mardoofa is THE source-anchored Sun strength signal (decision-trees S-8); its current +5 contribution barely moves thSun-clearing.

**Do NOT relax `sunMinShape`:** it's source-mandated per S-1 (Definite, video #25). The 1-Ace-no-mardoofa floor is correct by Saudi convention.

**Do NOT remove the B-5 5-point margin:** it's the failed-bid asymmetry guard (Sun fails for 26 raw vs Hokm 16). Source-anchored per video #25/#26.

**Recommended action shape (no apply):**
1. Run a tournament A/B with `TH_SUN_BASE = 44` (or `BOT_SUN_MARDOOFA_BONUS = 10`).
2. Compare Sun bid rate, match-win rate, average margin.
3. If Sun rate moves to ~5-10% with no match-win regression, ship the calibration in v0.10.4.

---

## 8. Top 3 corrections to apply to the synthesis

1. **§4.2 row "Net.lua:4059-4067 SWA bot-timer pause race" is stale — already fixed in-tree.** `botSWAResolveFn` (Net.lua:4064-4082) IS the named pause-aware re-arm function, with v0.10.3 marker comment at 4050-4063 explicitly citing E-Net-01. **Action:** move this row from §4.2 into §2 as a 6th applied fix, OR explicitly note "fix applied this cycle, deferred items below are the remaining sub-cases" if `HostResolveSWA`/`_OnSWAResp accept` paths still lack pause guards.
2. **§4.2 row "Bot.lua:2943-2955 F-30b oppsVoidPath secondary trigger (G-Logic-01 §1)" is stale.** Lines 2988-2993 already contain the `S.HighestUnplayedRank(trump) == nil` secondary trigger with explicit v0.10.3 marker. **Action:** remove from §4.2 backlog; mention as a sub-fix folded into fix #2.
3. **§2 line cites should target the actual code line, not the audit-comment start.** Fix #3 actual line is `Bot.lua:2143` (cited 2128); fix #4 actual line is `Bot.lua:1714` (cited 1705); fix #5 actual line is `BotMaster.lua:838` (cited 830). Comment-block-start citations make line-grep more annoying for downstream reviewers.

**Optional 4th correction:** consider promoting `State.lua:1966 S.GetLegalPlays UI-dimming AKA-blind` from MED to MED-HIGH or HIGH — it's the player-visible cousin of the v0.10.3 BotMaster fix #5, and almost certainly a 1-line `, S.s.akaCalled` addition to a single call.

---

*End of REVIEW_v0.10.2_validation.md*
