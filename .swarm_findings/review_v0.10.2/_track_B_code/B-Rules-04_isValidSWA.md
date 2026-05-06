# B-Rules-04 — `R.IsValidSWA` deterministic SWA validator

**Version**: v0.10.2
**Track**: B (code, no modifications)
**Scope**: `R.IsValidSWA` at `C:/CLAUDE/WHEREDNGN/Rules.lua:383-501`
**Date**: 2026-05-05

---

## Reference map

| Symbol | Path |
|---|---|
| `R.IsValidSWA` | `Rules.lua:383-501` (function body) |
| `R.CurrentTrickWinner` | `Rules.lua:34-59` (used at L398) |
| `R.IsLegalPlay` | `Rules.lua:89-210` (used at L435) |
| `C.TrickRank` | `Cards.lua:107-114` |
| `C.IsTrump` | `Cards.lua:125-128` |
| `K.RANK_TRUMP_HOKM` | `Constants.lua:50` (J=8 > 9=7 > A=6 > T=5 > K=4 > Q=3 > 8=2 > 7=1) |
| `K.RANK_PLAIN` | `Constants.lua:51` (A=8 > T=7 > K=6 > Q=5 > J=4 > 9=3 > 8=2 > 7=1) |
| `Bot.PickSWA` (call site) | `Bot.lua:3866-3938` |
| `N.HostResolveSWA` (call site, top-level) | `Net.lua:2862-2916` |
| `N.LocalSWA` (entry point) | `Net.lua:2475-2586` |
| Tests, Section O | `tests/test_rules.lua:850-934` (only 4 cases) |
| Source — video #35 | `docs/strategy/_transcripts/IMJIrhW4qOA_35_swa_term_detailed.ar-orig.srt` |
| Prior audit R3 | `.swarm_findings/review_v0.10.0/_phase2_xref/reaudit_R3_swa.md` |
| Prior audit 50 | `.swarm_findings/audit_v0.7.1/50_v0.5.17_swa.md` |
| Prior audit 26 | `.swarm_findings/audit_v0.7.1/26_pickswa.md` |
| 5+ bypass audit | `.swarm_findings/audit_v0.9.0/51_swa_5plus_bypass.md` |

(`.swarm_findings/audit_v0.7.1/45_session_persistence.md` does not exist — file 45 is `45_takweesh_flow.md`. Read; no SWA-specific content beyond confirming `R.IsValidSWA` is not invoked from the Takweesh path.)

---

## Findings

### F1 — Adversarial-partner trade-off DOES over-reject canonical Saudi two-hand SWAs (REPRODUCIBLE)

**Severity**: MEDIUM — known v0.5.17 trade-off (intentional, documented), but L2 in `review_v0.10.0/REVIEW.md` re-flagged it for separate audit and the v0.10.2 codebase still ships it unchanged.

**Mechanism**. The recursion at `Rules.lua:494-499` iterates `for _, card in ipairs(legal) do … if not R.IsValidSWA(callerSeat, nh, contract, ns) then return false end end`. The loop is unconditional — `nextSeat` may be partner, but the validator demands the claim survive **every** legal partner play, not just one cooperative play. The comment block at L471-493 makes this explicit: *"partner is treated adversarially in the recursion … if partner CAN over-take in any legal play, the SWA fails."*

**Saudi convention says otherwise** for two-hand SWA. From video #35 line 2814 (verbatim, trust this transcript at `IMJIrhW4qOA_35_swa_term_detailed.ar-orig.srt:2814`): *"يدك واللعب كان على يد خويك ثق تماما انه خويك راح يجي دائما"* — "your play was on your partner's hand, trust completely that your partner will always come". This is canonical permission to assume partner cooperation in two-hand SWA execution. The decision-tree extract (`docs/strategy/_transcripts/35_swa_term_detailed_extracted.md` rows for "سوا يدين Sun valid" and "سوا يدين Hokm valid") confirms the "you+partner share top two" cases are valid SWA per Saudi rule.

**Reproducible failing case (Sun two-hand SWA)** — analytically derived from `Rules.lua:107-114` (`TrickRank` for non-trump uses `K.RANK_PLAIN`, A=8 highest):

```
Contract: { type = K.BID_SUN, bidder = 1 }
Hands (2 cards each, 8 total left, 6 tricks already played):
  [1] caller : { "KH", "KS" }      -- caller (S1) has K of two suits
  [2] opp    : { "QH", "QS" }      -- opps hold the queens of those suits
  [3] partner: { "AH", "AS" }      -- partner (S3) holds both aces (live tops)
  [4] opp    : { "JH", "JS" }
trickState: { plays = {}, leader = 3 }   -- partner leads (canonical two-hand SWA arrangement)
```

Saudi-canonical result: VALID. Partner leads `AH` (top live H), all follow, partner wins. Partner leads `AS`, all follow, partner wins. Caller throws their `KH` and `KS` under partner's aces. All four remaining tricks are won by the team. Per video #35, the speaker would call this a clean two-hand SWA — caller's K is rank-2 in each suit, partner holds rank-1, "trust the partner to come" applies.

`R.IsValidSWA` result: FALSE. Walk-through:
1. Partner (`nextSeat=3`) is iterating legal plays. Partner has TWO legal plays: `AH` and `AS`. The recursion explores BOTH branches.
2. Branch B: Partner plays `AS` first. Lead suit becomes S. Caller's legal play (must follow S) is `KS`. Opp4 plays `JS`. Opp2 plays `QS`. Trick winner = partner (AS, rank 8). Per `Rules.lua:400`: `if winner ~= callerSeat then return false`. Partner ≠ caller → return false.
3. The OR-collapse at L494-499 treats this as "partner could pick a play that loses for caller" → entire SWA returns false.

**Same result happens to the simpler "you hold K, partner holds A, only 1 card each" (`#hand == 1` per seat)** when partner is the next to lead and partner's only legal play is the A. Partner wins the trick → `winner ~= callerSeat` → false. The "claim must be CALLER WINS literally every trick" rule at L365-369 + L400 is what causes the rejection, not the adversarial loop alone — but the adversarial loop also kills the case where partner has any choice.

**Same result in Hokm two-hand**:
```
Contract: { type = K.BID_HOKM, trump = "C", bidder = 1 }
Hands (1 card each, 7 tricks done):
  [1] caller : { "KC" }
  [2] opp    : { "9D" }   -- non-trump
  [3] partner: { "AC" }   -- partner holds top trump
  [4] opp    : { "8D" }
trickState: { plays = {}, leader = 3 }
```
Partner (next to play) has one legal: `AC`. Trick winner = partner (AC). caller ≠ winner → return false. Saudi says VALID (partner takes lead for the team, end of round). Code says INVALID and the caller is qaid'd.

**Why this matters**. Test O.4 at `tests/test_rules.lua:923-933` regression-pins this exact behaviour — the v0.5.17 design says "partner-could-overtake → strict-invalid, by design". So the test suite would BLOCK any relaxation. But `decision-trees.md` (rows around line 24-28, derived from video #35) and the speaker's own line 2814 ("trust completely that your partner will come") are unambiguous: the Saudi rule SHOULD accept these as VALID SWA.

**Pre-existing audit lineage**:
- `review_v0.10.0/_phase2_xref/reaudit_R3_swa.md` line 109: *"Two-hand SWA in Hokm … is REJECTED by the current adversarial recursion because partner is treated adversarially. This does diverge from #35 for the two-hand-SWA subtype."* Tagged MEDIUM confidence, marked as a v0.5.17 "intentional trade-off".
- `review_v0.10.0/REVIEW.md` row L2: "R.IsValidSWA partner-adversarial may over-reject Hokm two-hand SWA — separate audit recommended". v0.10.2 review has not yet acted on this.

**Net effect on player experience**. A non-bot human who clicks SWA on a canonical two-hand Hokm/Sun arrangement (caller K + partner A + nothing-bigger-outside) gets the v0.10.1 forfeit branch (Qaid penalty) at `Net.lua:2920-2987` — the OPPOSITE of what Saudi rule says should happen. Bots are partially shielded from this because `Bot.PickSWA` gates `#hand <= 4` and bots only call SWA if `R.IsValidSWA == true` (a one-way gate — a false-negative validator never triggers a bot SWA, so bots simply never claim a two-hand SWA). Humans get bitten directly.

**Why over-rejection is one-way safe**. From a *fairness* / *no-exploit* angle this is safe: when the validator returns false, the caller forfeits but never wrongly wins. So no scoring exploit. From a *Saudi-rule fidelity* angle it diverges. The R3 author noted "partner-adversarial may relax to 'partner adversarial except mandated cooperative plays'", which would be the surgical fix — out of scope for v0.10.2 but on the long-term roadmap.

---

### F2 — Card-rank computation IS trump-aware on every comparison path

**Severity**: NONE — clean.

`R.IsValidSWA` does not directly compute card ranks. It outsources every comparison to:
1. `R.IsLegalPlay` for legality (`Rules.lua:435`, `Rules.lua:89-210`).
2. `R.CurrentTrickWinner` for trick winner (`Rules.lua:398-400`, `Rules.lua:34-59`).

Both consistently use `C.TrickRank(card, contract)` (`Cards.lua:107-114`):
- Hokm + suit==trump → `K.RANK_TRUMP_HOKM` (J=8, 9=7, A=6 — note 9-of-trump is rank-7 below J, not rank-3).
- Otherwise → `K.RANK_PLAIN` (A=8, T=7, K=6, Q=5, J=4, 9=3 — Sun-style ordering).

`R.CurrentTrickWinner` correctly handles the trump-played-overrides-led-suit case at `Rules.lua:39-51`: scans for any trump played, and if found, only trump cards are eligible for the winner test. Lead-suit-no-trump-played fallback at L51 keeps follow-suit comparisons in plain-rank.

Partner-led suit comparison: when the recursion lets partner LEAD a card (no plays yet for the trick, partner is `nextSeat`), `applyMove` at `Rules.lua:465` correctly sets `newLead = leadSuit or C.Suit(card)` — i.e. when leadSuit was nil, it becomes the suit of the leader's card. Subsequent recursion comparisons then use that lead suit. No trump-aware bug here.

Sun contract: there's no must-trump-ruff path (`Rules.lua:163: if contract.type == K.BID_SUN then return true`). So Sun legality is "follow if you can, else anything" — consistent with R.IsValidSWA's strict winner check.

**One minor observation (not a bug)**: `R.CurrentTrickWinner` at `Rules.lua:35` early-returns nil for empty trick. This is reachable from line 398 only after `#plays == 4` so always non-empty. Defensive but never triggered.

---

### F3 — Recursion termination IS bounded and infinite-loop-free

**Severity**: NONE.

Each recursive call removes exactly one card from one hand (`Rules.lua:447-461` in `applyMove`). The total card pool is monotonically non-increasing: starts at ≤32, shrinks by 1 every recursive invocation. Base cases:
1. `#plays == 4` and trick winner ≠ caller (L400) → return false. Bounded by 4 plays.
2. `#plays == 0 and #(hands[caller]) == 0` (L418) → return true. Caller-empty terminator.
3. `#legal == 0` (L438) → return false. Defensive against malformed states.

Branching factor: ≤8 legal plays per node (a player has at most 8 cards, in practice ≤4-5 after legal-play filtering).

Worst-case node count: ~5! × 4 = 480 nodes for a typical 4-card-each remaining state; ~8! ≈ 40K for an 8-card-each round-start SWA (bounded but the Saudi rule says you should never reach this point — see F8). All paths terminate.

**One subtle edge that's already handled**: the `#plays == 4` branch at L397-404 triggers BEFORE the caller-empty short-circuit at L418. Pre-fix (V14 audit), if the caller's last card was the 4th play of a losing trick, the empty-hand check would fire first and return true. The fix order matters; L397-404 sits before L418 by design. Verified.

---

### F4 — Trick-state reconstruction is robust; mid-trick SWA handled

**Severity**: NONE — robust, with one observed minor: silent acceptance of `trickState = nil` rather than rejection.

`Rules.lua:384-385`:
```
if not callerSeat or not hands or not contract then return false end
if not trickState then trickState = { plays = {}, leader = callerSeat } end
```

If `trickState == nil`, the validator synthesizes a between-tricks state with leader=caller. This is benign — top-level callers (`HostResolveSWA` `Net.lua:2902-2904`, `Bot.PickSWA` `Bot.lua:3882-3884`) ALWAYS supply trickState. The synthesis path is reached only by tests / direct invocations.

Mid-trick SWA: when `#plays > 0 and #plays < 4`, the recursion correctly resumes from `nextSeat = (plays[#plays].seat % 4) + 1` (L427) using the existing leadSuit. Tested by Section O O.2/O.3 at `tests/test_rules.lua:880-902`.

`leadSuit` propagation: `applyMove` at L465 uses `leadSuit or C.Suit(card)` — so the FIRST play of a new trick correctly establishes leadSuit; subsequent plays inherit it. Correct.

**Malformed state tolerance**:
- `plays = nil` → `#plays` would error on a nil. **Defended** at L387 (`local plays = trickState.plays or {}`).
- `leadSuit` mid-trick missing → recursion uses nil; `R.IsLegalPlay` at L100 reads `trick.leadSuit`; if nil, the must-follow-suit clauses at L124-128 don't trigger (any card OK as if no lead). This is technically wrong for a real mid-trick but **not reachable** in practice — `applyMove` always sets `leadSuit` after the first play, and top-level callers always supply a leadSuit when plays > 0.
- `leader` missing — synthesized to `callerSeat`. If `#plays > 0`, `nextSeat` is determined by the LAST play, not by leader, so `leader` doesn't matter mid-trick. Between tricks (L424), `nextSeat = leader`; if leader is bogus the wrong seat plays first. Top-level callers fill leader from `S.s.turn` (`Net.lua:2900`). Not exposed in practice.

**Top-level guard**: `HostResolveSWA` at `Net.lua:2912-2914` rejects the corrupted-state pattern (caller hand empty AND no plays) which would otherwise let `R.IsValidSWA` short-circuit-return-true. Good defensive layer.

---

### F5 — 5+ card SWA uses the same deterministic check (verified)

**Severity**: NONE for `R.IsValidSWA` itself (R3 verdict re-affirmed).

There is no card-count branching inside `R.IsValidSWA`. The recursion treats 1-card hands and 8-card hands identically — same legal-play filter, same trick winner check, same recursion. R3's claim ("only the permission flow differs") is verified.

The 5+ regime divergence is at the `N.LocalSWA` / UI layer, not at the validator (`audit_v0.9.0/51_swa_5plus_bypass.md`):
- Bots: gated `#hand <= 4` at `Bot.lua:3871`. Bots NEVER attempt 5+.
- Humans: `N.LocalSWA` (`Net.lua:2475-2586`) does NOT cap. A human can click SWA at 5/6/7/8 cards. Permission flow runs identically; `R.IsValidSWA` runs the full minimax (40K nodes worst case at 8 cards). Almost always returns false → caller pays Qaid penalty.

This is an isolated UX gap (5+ button should not be offered) but the *correctness* of `R.IsValidSWA`'s deterministic-or-bust output at 5+ is intact.

---

### F6 — Saudi-strict deterministic-or-bust: NO probabilistic / threshold paths (verified)

**Severity**: NONE.

Static read of L383-501: zero `math.random`, zero threshold comparisons, zero probability symbols. All branches return literal `true`/`false`. The single terminal `return true` at L500 fires only when EVERY legal play of EVERY non-caller seat satisfies `R.IsValidSWA(...) == true` recursively. Pure boolean.

Cross-confirmed: `Bot.PickSWA` adds NO probabilistic gate either — `Bot.lua:3892` is `if not R.IsValidSWA(...) then return false`, and the Hokm safety net at L3906-3935 is also pure boolean (oppTopRank > callerTopRank → reject).

---

### F7 — Failed proof = Qaid: integration confirmed (incl. v0.10.1 forfeit branch)

**Severity**: NONE. The integration is wired correctly; one observation about score asymmetry below.

`HostResolveSWA` (`Net.lua:2862-2916`):
1. Call `R.IsValidSWA` at L2915.
2. If `valid == false` (L2920): apply Qaid:
   - Hand-total: `K.HAND_TOTAL_SUN (130)` or `K.HAND_TOTAL_HOKM (162)` (L2926).
   - Multiplier: base × Sun × (Bel/Triple/Four/Gahwa rung) (L2930-2935).
   - **v0.10.1 forfeit branch (L2942-2952)**: caller's team's melds zeroed (`mpA = 0` if caller is on team A). Non-offender team keeps THEIR melds. Verified vs M1 source-arbitrated decision in `review_v0.10.0/REVIEW.md` row M1.
   - Belote scan (L2953-2978): if K+Q of trump landed in plays, Belote awarded. Independent of qaid. Belote is multiplier-immune (matches `CLAUDE.md` line 21 rule).
3. Caller hand empty AND no plays in flight (L2911-2913) is rejected at the top level — would otherwise short-circuit-return-true on the recursive base case. Good.

The v0.10.1 melds-forfeited-on-Qaid path is the user-arbitrated fix from the v0.10.0 review (M1). v0.10.2 inherits it correctly. No double-zero or sign error in the math.

**One minor observation (not a bug)**: the qaid path uses the FULL handTotal regardless of how many cards remain. A 4-card SWA Qaid penalty pays the same as a 1-card Qaid penalty (130×mult / 162×mult either way). The user has accepted this as Saudi convention (audit_v0.7.1/45_takweesh_flow.md note 1).

---

### F8 — Trick-1 (8-card) round-start SWA: reaches `R.IsValidSWA`, almost always rejects

**Severity**: LOW — convention-divergent but rescued by determinism check.

`Net.lua:2475-2586` (`N.LocalSWA`) has no card-count guard. UI button at `UI.lua:2011` (per `audit_v0.9.0/51_swa_5plus_bypass.md`) shows whenever `swaEnabled and not swaPending`. A human clicking "SWA" at trick 1 (8 cards each, no plays in flight) flows:
1. `N.LocalSWA` → permission window (`Net.lua:2502-2580`).
2. Auto-approve fires → `HostResolveSWA(seat, pinnedHand)`.
3. `HostResolveSWA` builds trickState `{ plays = {}, leader = S.s.turn or callerSeat }` (`Net.lua:2898-2904`).
4. `R.IsValidSWA` runs over the full 32-card tree.
5. Almost always returns false (the Saudi-strict adversarial recursion treats partner as adversarial AND demands literal-caller-wins-every-trick — virtually no 8-card hand survives).
6. Qaid penalty fires (with v0.10.1 melds-forfeited).

**Test coverage**: NONE. `tests/test_rules.lua` Section O has 4 cases (1-card, 1-card-with-trump, 1+1 partner-overtake, 2+2 partner-could-overtake). No 5+ card test, no round-start test. The 40K-node worst-case has been hand-reasoned but not exercised by automated tests.

**Reproduces F1 at scale**. The hypothetical 8-card SWA shape "4 Aces + 4 Tens" (`extracted.md` row 38: "ورق زي كذا مفجر مستحيل يمشونه فرصه لهم انهم يقيدوا عليك" — "such a hand is so explosive [opps] would never let it pass; it's an opportunity for them to qaid you") would actually be a hard-deterministic SWA (caller leads A, all win; leads T, all win — assuming caller plays the right order). The validator should pass it. But the Saudi rule says "5+ MUST take permission" so the convention enforcement happens at the social layer, not the validator. The validator's burden is just "correctness assuming the call is offered". For the 4A+4T case the validator should pass it (caller leads, all top live cards). Not a bug, just untested.

---

### F9 — Edge: caller has exactly 1 card → trivially valid SWA (with caveats)

**Severity**: NONE — handled.

Walkthrough for caller with 1 card, between tricks (`#plays == 0`, leader = callerSeat):
1. Branch L397 not taken (`#plays != 4`).
2. Branch L418 not taken (`#hands[caller] != 0`).
3. `nextSeat = leader = callerSeat` (L425).
4. Build legal: caller has 1 card, all are legal first-plays. `legal = { caller's card }`.
5. `applyMove(card)` removes it, appends to plays. Recurse with new state: `#plays == 1`, `#hands[caller] == 0`, leadSuit set.
6. Recursion. Branch L397 not taken (`#plays != 4`). Branch L418 not taken (`#plays == 1`, caller is empty — but the gate is `#plays == 0` AND `#hands == 0`). 
7. Continue: nextSeat is the second seat. Their legal plays evaluated; recursion descends through positions 2, 3, 4.
8. After 4 plays the L397 branch fires. If trick winner == caller, recurses with empty plays/empty caller. Then L418 fires, returning true.

**For O.1 test (`tests/test_rules.lua:866-877`)**: caller = AS (only spade), trump=H, opps have only D. Caller leads AS. Opp2 plays 9D (no S to follow, no H to ruff — must play any → 9D legal). Opp3 plays 8D. Opp4 plays 7D. Trick winner = caller (AS, only spade played, no trump played, lead suit S). Recursion returns true. Verified.

Edge subcases:
- Caller has 1 card, but it's a low card and partner is leader instead of caller. `nextSeat = partner`. Partner has multiple cards. The adversarial loop forces partner to TRY each card; if any partner card wins the trick AND a subsequent play forces caller's card to lose → false. F1 territory.
- Caller has 1 card, between tricks, and the trick was just resolved against caller (4th-play case at L397). `winner != caller` → return false at L400 BEFORE the empty-caller check. Correct.
- Caller has 0 cards but `#plays > 0` (i.e. caller already played their last card) — the L418 gate is `#plays == 0 AND #hand == 0`, so NOT triggered. The recursion continues to next seats; eventually L397 fires when 4 plays accumulate; the trick winner is determined; if caller won the resolved trick (which is now empty plays and empty hands at the next recursion), L418 fires returning true. Correct (per the V14 + v0.5.17 fix — see `audit_v0.7.1/50_v0.5.17_swa.md` and `Rules.lua:391-420` comment block).

---

### F10 — Edge: caller has 2 cards including the highest unplayed of led suit

**Severity**: NONE — handled (provided the lead pattern is truly winning).

Sun example, contract `{ type = K.BID_SUN }`, between tricks, leader = caller:
- Caller: { "AH", "KS" } (AH is top live H, no other AH in play; assume opp Kings of S still in play but no As live)
- Opp2: { "QH", "QS" }
- Partner3: { "JH", "JS" }
- Opp4: { "TH", "TS" }

Trick 1: caller leads AH. All follow with H. Winner = AH (caller). Trick 2: caller leads KS. All follow with S. KS rank-6 in plain. Opp2 has QS (rank 5), partner has JS (rank 4), opp4 has TS (rank 7). **Opp4's TS beats caller's KS** — so caller loses trick 2. Not a valid SWA. Correctly rejected.

Modify so caller actually has the LIVE-top of S as well:
- Caller: { "AH", "AS" }
- Opp/partners hold lower S/H ranks only.
Then caller wins both tricks as lead. Validator returns true. Correct.

The "highest unplayed of led suit" phrasing in the brief assumes Sun (or non-trump) and assumes "highest live" is genuinely the live-top. The validator handles this via the standard trick winner mechanic — no card-count special case. No edge bug.

**Caveat**: if "partner takes 2nd" is the partner-cooperative interpretation (caller leads top, partner LATER leads their own top), this falls into F1 territory. Specifically the recursion forces partner to choose adversarially when partner gets the lead. If partner has any non-top legal play that fails caller's claim, return false. The pure caller-leads-everything case is handled correctly; the alternating-lead case fails per F1.

---

### F11 — Test coverage thinness

**Severity**: LOW — 4 tests in Section O, which is light for a function that gates the most-punishing rule in the game (Qaid).

`tests/test_rules.lua:850-934` covers:
- O.1: 1-card SWA, AS unbeatable, trump=H, opps no trump → VALID.
- O.2: 1-card SWA, opp can ruff → INVALID.
- O.3: partner's only-play over-takes → INVALID (legitimate per strict rule).
- O.4: partner could over-take → INVALID (the regression pin for v0.5.17 strict-caller).

Missing:
- 4-card hand tests (the "normal" SWA bot use case).
- 5+/8-card tests (the Saudi-mandatory-permission regime, see F5+F8).
- Mid-trick SWA tests (the L425-427 nextSeat-from-last-play branch).
- Sun-only contract tests (Sun is the larger contract type; only O.* hokm tests exist).
- `trickState = nil` synthesis path test.
- `trickPlays == 4 AND winner != caller` test (the V14 fix path).
- Two-hand cooperative-canonical SWA test that should pass per Saudi rule but currently fails (F1's failing case) — would make the divergence visible to anyone running the suite.

The lack of a Sun-canonical-two-hand test means F1 is "discoverable only by careful manual reasoning"; the suite gives a false confidence signal.

---

## Verdict

| Question | Answer |
|---|---|
| Adversarial-partner trade-off over-rejects canonical Saudi two-hand SWA? | **YES — REPRODUCIBLE.** F1 walks through both Sun and Hokm canonical-two-hand cases that Saudi rule (verbatim video #35 line 2814 "ثق تماما انه خويك راح يجي دائما") accepts as VALID but `R.IsValidSWA` rejects as invalid. This is the L2 follow-up from the v0.10.0 review, explicitly out-of-scope at v0.10.2. |
| Card-rank computation trump-aware? | **YES** — all paths route through `C.TrickRank` which is trump-aware. (F2) |
| Recursion termination bounded? | **YES** — monotonic card-pool reduction; no infinite-loop hazard. (F3) |
| Trick-state reconstruction robust? | **YES** — defensive guards at every input port; mid-trick handled. (F4) |
| 5+ card SWA uses same deterministic check? | **YES** — confirms R3. The validator does not branch on count. UX-layer divergence (no UI cap) is separate (F5). |
| Saudi-strict deterministic-or-bust? | **YES** — pure boolean, no probabilistic gates. (F6) |
| Failed proof = Qaid integration? | **CORRECT** — including v0.10.1 melds-forfeited fix at `Net.lua:2942-2952`. (F7) |
| Trick-1 SWA at 8 cards reaches validator? | **YES** — no UI/Net cap on humans. Almost always rejected by the strict recursion. Untested. (F8) |
| Caller has 1 card → trivially valid? | **YES** — handled. Edge subcases enumerated; behaviour matches expectation. (F9) |
| Caller has 2 cards w/ live-top of led suit? | **YES** — handled, with the F1 caveat for the alternating-lead "partner takes 2nd" interpretation. (F10) |

**Overall**: The validator is *correct* under the strict-Saudi interpretation that v0.5.17 codifies. It is *over-strict* relative to canonical Saudi convention for two-hand SWA, by design, intentionally documented at L471-493. The "under-acceptance" failure mode is one-way safe (never wrongly approves) so no scoring exploit exists, but it does diverge from video #35 for the two-hand subtype.

The integration with `HostResolveSWA` (incl. v0.10.1 forfeit branch) is correct. The 5+ regime is correctly handled at the validator level; the UX-layer "5+ should be button-blocked" gap is a separate finding (audit_v0.9.0/51).

**Specific concrete bug-or-divergence call**: F1 is real and reproducible; it is the same item the v0.10.0 review tagged as L2; it remains unfixed in v0.10.2. It is documented as "intentional v0.5.17 trade-off" but the Saudi-rule fidelity argument (line 2814 + decision-trees rows for "سوا يدين Sun valid" + "سوا يدين Hokm valid") supports relaxing the recursion to a "partner adversarial except in mandated-cooperative-plays" model. Out of scope for the current Track-B audit (no code changes), but the over-rejection IS a real divergence.

**Test gap**: F11. Section O has 4 cases, none of which exercise (a) 4-card hands which are the bot-typical case, (b) Sun contracts, (c) a deliberate canonical-two-hand-SWA case. Adding three or four tests would harden the suite without changing semantics.

## Confidence

- **HIGH** on F1 reproducibility (analytical walkthrough against the actual code; cross-checked against constant tables `K.RANK_PLAIN` / `K.RANK_TRUMP_HOKM`; corroborated by R3 audit).
- **HIGH** on F2-F7 (direct code reads).
- **HIGH** on F8 (corroborated by audit_v0.9.0/51).
- **HIGH** on F9, F10 (analytical walkthroughs).
- **HIGH** on F11 (direct count of test cases).

No execution / harness was run; all conclusions derive from static reading of `Rules.lua`, `Cards.lua`, `Constants.lua`, `Net.lua`, `Bot.lua`, `tests/test_rules.lua`, the video #35 SRT at the cited lines, and the previous audit reports. F1 reproduction would need `tests/run.py` to actually run the failing case as a test, which is a Track-F item.
