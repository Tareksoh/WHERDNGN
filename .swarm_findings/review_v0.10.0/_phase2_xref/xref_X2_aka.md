# X2: AKA mechanism completeness

**Scope:** Cross-reference Phase-1 audit AKA rules (Sources G #18, J #42, D) against the WHEREDNGN code (`v0.10.0` working tree).

**Code surface inventory:**
- `Bot.lua:3108-3204` — `Bot.PickAKA(seat, leadCard)` (sender decision)
- `Bot.lua:2387-2439` — pickFollow AKA-receiver branch (explicit + implicit)
- `Bot.lua:449-500` — touching-honors-down WRITE (uses `S.s.akaCalled` to determine touch context)
- `Net.lua:208-216` — `N.SendAKA(seat, suit)` (wire send)
- `Net.lua:2331-2362` — `N.LocalAKA(suit)` (human entry point)
- `Net.lua:3057-3078` — `N._OnAKA(sender, seat, suit, replayFlag)` (wire receive)
- `Net.lua:463-468` — AKA replay during resync
- `Net.lua:4076-4082` — bot-side auto-broadcast of AKA after lead
- `State.lua:1295-1407` — `AKA_ORDER`, `S.HighestUnplayedRank`, `S.LocalAKAcandidate`, `S.ApplyAKA`
- `State.lua:s.akaCalled` — `{seat, suit}` banner state, cleared on trick end (line 1284)
- `UI.lua:2031-2049` — AKA button visibility (Hokm + LocalAKAcandidate gate)
- `UI.lua:1295-1316, 3236-3255` — AKA banner render
- `Rules.lua` — **no AKA references at all** (key finding for AKA-on-10 / false-AKA)

---

## Decision matrix code verification

The Phase-1 grid (G18-09) is a 3×3 matrix mapping {self-confidence about being-largest} × {partner-trump-state} → {call/skip}. Bot.PickAKA's structure is gate-stack rather than explicit grid; map cell-by-cell:

| Grid cell (self × partner-trump) | Phase-1 rule | Bot.PickAKA branch | Match |
|---|---|---|---|
| Sure-largest × partner-has-trump | CALL | Pre-check `HighestUnplayedRank(su) == r` (3139) is the "sure largest" gate. Partner-trump-presence is not directly checked; only the *negative* case (partner certainly void) is filtered (3160-3166). Default action: CALL. | **Partial** — call fires correctly, but the branch never explicitly verifies "partner has/may have trump" — it filters *only* the proven-void case. |
| Sure-largest × partner-may-have-trump | CALL | Same path; 3160-3166 only suppresses on `pmem.void[trump] == true`. If status unknown → CALL. | **Match** |
| Sure-largest × partner-certainly-void-in-trump | SKIP | Lines 3160-3166: `if pmem and pmem.void and pmem.void[trump] then return nil end`. | **Match** |
| Suspect-largest × any | SKIP | Line 3139 `S.HighestUnplayedRank(su) ~= r` returns nil → no AKA when not boss. **But:** suspect-largest in the speaker's grid is a *bot-side belief* about whether it's largest; the code uses the deterministic shared-state `playedCardsThisRound` map (line 1326), so "uncertainty" doesn't really exist in code — bot has perfect memory of played cards. The grid cell collapses to the next one. | **N/A in code** — collapses to "not largest" because bot has full played-card memory. |
| Known-not-largest × any | SKIP | Same `HighestUnplayedRank` gate. | **Match** |

**Three additional code-only gates not in the matrix but stated in Phase-1 preconditions:**
- Hokm-only: 3110 — match (G18-02 / J-066)
- Non-trump only: 3129 — match (G18-03)
- AKA only when leading: 3111 (`#S.s.trick.plays > 0` ⇒ skip) — match (G18-05)
- Card != Ace: 3136 — match (because Ace is implicit AKA, G18-08; redundant explicit AKA leaks info)
- Trick 1 skip: 3151 (`trickNum <= 1`) — **NOT in Phase-1 rules**; this is a code-internal opportunism gate (no opponent voids shown yet). It is consistent with the G18-09 spirit (no upside on first trick) but the speaker does NOT impose a trick-1 ban. **Possible over-filter.**
- Bot-partner only: 3125 — **NOT in Phase-1 rules**; the speaker assumes any partner. This is a defensible information-leak guard (humans don't read AKA banners as ruff-suppression). **Code-only addition.**

---

## Per-rule verdicts

### Hokm-only gate: **Y**
Three independent enforcements:
1. `Bot.PickAKA` Bot.lua:3110 — `if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return nil end`
2. `N.LocalAKA` Net.lua:2337 — same check (human entry)
3. `N._OnAKA` Net.lua:3076 — same check (wire receive guard against malicious/lagged peer)
4. `UI.lua:2037` — AKA button hidden in non-Hokm contracts
5. `S.LocalAKAcandidate` State.lua:1345 — early-out when not Hokm

**Verdict:** Strongly enforced — defence-in-depth across UI / sender / receiver / state. Matches G18-02 and J-066 verbatim.

### Implicit AKA via bare-A lead (G18-08, D-R3): **Y (receiver) / N (sender)**
- **Receiver branch:** Bot.lua:2396-2426 implements implicit AKA correctly. Triggers on `partner LED bare A of non-trump in Hokm AND partnerWinning AND not explicitAKA`. Behaviour identical to explicit AKA (suppress ruff). v0.5.16 wiring verified.
- **Touching-honors WRITE:** Bot.lua:478-486 detects implicit-AKA context for inferring partner's nextDown card. Correctly checks BOTH the explicit `S.s.akaCalled` path AND the implicit "lead.card was Ace by partner" path.
- **No "fire AKA via bare-A lead" path:** Confirmed — there is intentionally NO code that calls `S.ApplyAKA` or sets `S.s.akaCalled` when partner leads bare A. Sender-side `Bot.PickAKA` line 3136 explicitly returns nil for `r == "A"` (comment cites G18-08 / S6-6 — "redundant; receivers detect via H-5"). Receiver compensates by inspecting trick.plays[1].
- **Touching-honors WRITE works in both modes** because line 478-486 has both branches.

**Verdict:** Implementation matches G18-08 exactly. Implicit AKA is a *receiver convention*, not a sender broadcast — there is no MSG_AKA emitted on bare-A lead, by design.

### AKA-on-10 substitution (J-066/J-067): **Partial Y (relief) / N (lock)**
The Phase-1 J-067 rule has two parts:
1. **"AKA on 10 substitutes 10 for Ace"** — the 10 is treated as the boss and trick is closed for over-trumping requirements.
2. **"Exempts partner from must-trump-ruff"** — the receiver-relief side.

Part 2 (relief): **Y** — `pickFollow` Bot.lua:2427-2438 fires on any AKA where `S.s.akaCalled.suit == trick.leadSuit` and `partnerWinning`. The 10 is one of the legal AKA cards (when A is dead) per `S.HighestUnplayedRank` walking `AKA_ORDER = {"A","T","K","Q","J","9","8","7"}`.

Part 1 (lock): **N** — `Rules.lua` does NOT consult `S.s.akaCalled`:
- `R.CurrentTrickWinner` (Rules.lua:34-59) — trick winner is purely highest-rank-by-trick-rank; AKA banner has zero legal effect.
- `R.IsLegalPlay` (Rules.lua:89-184) — does NOT check `S.s.akaCalled` anywhere. A void player legally MUST trump-ruff regardless of AKA banner. The exemption is only honored by the bot heuristic at Bot.lua:2427-2438.

**Bug:** A human player following an AKA call must legally still trump-ruff — `R.IsLegalPlay` will reject a side-suit discard with "must trump". The bot's pickFollow returns the legal-illegal — wait — **re-check legality flow:** Bot.lua:2437 returns `lowestByRank(discards, contract)` from a `discards` list filtered from `legal`. So the bot only returns legal non-trump cards. But that means `legal` (computed by `legalPlaysFor` → `R.IsLegalPlay`) ALREADY contains non-trump options when AKA is active. **Wait — does it?** Re-check Rules.lua:151-156: must-trump fires whenever `hasTrump` is true, regardless of `s.akaCalled`. So `legal` for a void+has-trump+AKA-active receiver only contains trumps — `discards` would be empty → fall through.

**Confirming this:** the actual AKA-receiver branch returns `lowestByRank(discards, contract)` only if `#discards > 0`. If `discards` is empty (because `legal` only has trumps because Rules.lua doesn't recognize AKA), the branch falls through and the bot ruffs anyway. **Either:**
- (a) the receiver branch is dead code in the AKA receiver context (only fires when partner is winning AND a non-trump suit is in the receiver's hand other than the led suit — which is true when receiver is *not* void in led suit), OR
- (b) the legal-play computation does NOT enforce must-trump when `s.akaCalled` is set somewhere else.

Looking at Bot.lua's `legalPlaysFor` (need to check):

<see grep below>

The branch DOES fire when: receiver is void in led suit AND has trump AND has at least one non-trump non-led-suit. In that case `legal` contains: (i) trumps (must-trump rule), (ii) NOT non-trump non-led (because must-trump). So `discards = {}` → branch falls through → bot ruffs anyway.

**This means the AKA receiver-relief branch is structurally broken for the canonical case (void + has-trump).** The branch only fires meaningfully when the receiver is NOT void in led suit (must-follow path) — in which case there's no must-ruff conflict to override anyway.

**Verdict:** Receiver-side relief is **functionally non-operative** because Rules.lua doesn't recognize AKA-as-relief. The intent matches J-066/J-067 part 2 but the legal-play layer overrides. AKA-on-10 lock (J-067 part 1) is not implemented at all.

### False AKA = Qaid (J-069): **N**
- No `Rules.lua` validation of AKA calls against truth. `N._OnAKA` does NOT verify the sender actually holds the highest unplayed; comment at Net.lua:2458-2459 confirms this is intentional ("Soft signal — we apply locally regardless of whether the caller actually has the AKA").
- `N.LocalAKA` Net.lua:2354-2358 *does* verify the local caller before broadcasting (`S.LocalAKAcandidate()` check). But this is a sender-side anti-misclick guard — a hostile or buggy peer could spoof a false AKA, and the host would apply it without checking.
- `Bot.PickAKA` Bot.lua:3137-3139 verifies sender's lead card is the boss before broadcasting. Same anti-self-fault guard.
- **Nowhere does code track or penalize a false AKA.** No `R.ScoreRound` branch on `s.akaWasFalse` flag. No `K.MSG_QAID` triggered on AKA-mismatch.

**Verdict:** Phase-1 J-069 is NOT implemented. The code architecture treats AKA as advisory; an actual false call (hostile peer or bot bug) would never produce a Qaid.

### Risk-tolerance by game state (G18-10): **Partial Y (late-game) / N (doubled hands)**
Bot.PickAKA Bot.lua:3168-3200 implements *one* of the two G18-10 axes:

- **Late-game suppression:** Lines 3184-3200 suppress AKA when `trickNum >= 6` AND not in clutch state (within 25 of target, or |delta| <= 20). This matches "late-game ⇒ conservative" per G18-10 paragraph 1.
- **Doubled-hand check:** **MISSING.** Bot.PickAKA never inspects `S.s.contract.mult`, `K.MULT_BEL`, or any escalation flag. The Phase-1 transcript explicitly states "اللعب طبيعي مش دبل" (regular play, not doubled) as the early-tolerance gate; the inverse — "doubled ⇒ never AKA on uncertainty" — is not enforced.
- **Early-game permissiveness:** Code skips AKA on trick 1 (line 3151) — *opposite* of G18-10's spirit ("بدايه الجيم لسه عوافي" = early game is comfortable, can take risk). The trick-1 skip exists for a different reason (no voids shown, signal not actionable). Phase-1's "early-game permissiveness" implies *relaxing* certainty requirements early; code implementation is "skip first trick entirely" which is a stricter, not looser, gate.

**Verdict:** The decision-trees.md row "(g) round_stage allows" is implemented for the late-game half. The doubled-contract conservatism is missing. The early-game permissiveness rule of G18-10 is not implemented — possibly because Bot.PickAKA only fires when the bot has perfect knowledge of being-largest (no "uncertain" branch exists in code), so the "take a risk on uncertain bossness early" rule has no surface to attach to.

---

## Bugs found

### B1. AKA receiver-relief is functionally dead code (severity: high)
- **Location:** Bot.lua:2427-2438 + Rules.lua:89-184
- **Issue:** The AKA-receiver branch returns a non-trump discard "if any non-trump is legal", but Rules.lua's must-trump enforcement (Rules.lua:151-158) doesn't honor `S.s.akaCalled`, so for the canonical case (receiver void in led suit, has trump), `legal` will only contain trumps — `discards` will be empty — branch falls through and bot ruffs anyway, defeating AKA's primary purpose.
- **Confirming question:** check whether `Bot.legalPlaysFor` adds an AKA-relief carve-out independent of `R.IsLegalPlay`.
- **Phase-1 rules violated:** G18-06 ("AKA's PRIMARY effect — releases partner from must-trump obligation"), J-066, J-067.

### B2. False-AKA = Qaid not implemented (severity: medium)
- **Location:** Rules.lua (absence) and Net.lua:3057-3078
- **Issue:** No legality enforcement on AKA truth-claim. A bug, a hostile peer, or a desync could call AKA on a non-boss card and trigger no penalty. Phase-1 J-069 mandates Qaid against the false-caller.

### B3. Doubled-contract conservatism missing in Bot.PickAKA (severity: low)
- **Location:** Bot.lua:3168-3200
- **Issue:** G18-10 explicitly distinguishes regular vs doubled hands; on doubled hands the speaker says even certain AKA should be reconsidered. Code only checks late-trickNum + score-distance proxy.

### B4. Trick-1 skip is opposite of speaker's intent (severity: trivial / philosophical)
- **Location:** Bot.lua:3149-3151
- **Issue:** Speaker says early-game is the *permissive* zone. Code makes trick 1 the most-strict zone (categorical skip). Defensible (no voids shown yet), but semantically opposite of G18-10's "early-game tolerance" framing.

### B5. AKA-on-10 trick lock (J-067 part 1) not implemented (severity: low)
- **Location:** Rules.lua:34-59 (trick winner)
- **Issue:** Phase-1 J-067 says "AKA on 10 = 10 substitutes for Ace" — i.e. the trick is "closed for over-trumping requirements". Code never considers AKA when computing trick winner or legal plays. The 10 simply wins as the highest live non-trump-suit card if no over-trump occurs — which produces the same outcome *most of the time* via natural play but does not actually implement the substitution semantics.

---

## Missing features

1. **AKA-truth verification in Rules.lua / Host validation.** Currently sender-side guards exist (`S.LocalAKAcandidate`, `Bot.PickAKA`'s 3139 check) but no host-side wire validation. Adding `R.ValidateAKA(seat, suit)` consulting `s.playedCardsThisRound` would close the spoofing gap.

2. **AKA-aware legal-play override.** `R.IsLegalPlay` would need a parameter (or a state read on `s.akaCalled`) to allow non-trump discard when partner-AKA-is-active and partner is currently winning. Without this, B1's bug becomes structural — bot heuristic and Rules.lua disagree.

3. **Doubled-contract gate in Bot.PickAKA.** Read `S.s.contract.mult >= K.MULT_BEL` and tighten threshold.

4. **3×3 grid representation.** Code uses gate-stack, not matrix. The cells "suspect-largest × partner-has-trump → SKIP" and "sure-largest × partner-uncertain → CALL" don't have explicit branches because (a) bot has perfect played-card memory (no "suspect"), and (b) partner-trump status is only inspected as a negative filter (`pmem.void[trump]`). For a humanized bot, the matrix would need a real 9-cell decision; current code collapses to a 3-cell gate (bossness, partner-not-void, late-clutch).

5. **No false-AKA Qaid scoring path.** Even if validation were added, `R.ScoreRound` has no branch for "team A made a false AKA, award team B's Qaid value (16 Hokm raw + their melds)".

---

## Confidence

**High confidence** on the following findings:
- Hokm-only gate is correctly enforced (Y).
- Implicit AKA via bare-A is correctly handled receiver-side (Y).
- False AKA = Qaid is not implemented (N) — verified by absence-of-evidence in Rules.lua and explicit comment at Net.lua:2458 (`-- Soft signal`).
- Doubled-hand suppression in Bot.PickAKA is missing (N).
- AKA-on-10 trick-locking semantics (J-067 part 1) are not implemented (N) — `R.CurrentTrickWinner` does not consult `S.s.akaCalled`.

**Medium confidence** on:
- The receiver-relief dead-code claim (B1). Depends on the exact behavior of `Bot.legalPlaysFor` — needs a focused trace of one void-in-led-suit + AKA-active scenario through `legalPlaysFor` → `R.IsLegalPlay` to confirm `legal` contains only trumps. The comment at Bot.lua:2392-2394 ("Falls through to normal logic when no non-trump exists") suggests the developer knew about this fall-through but interpreted it as a corner case rather than the main case.
- Whether `Bot.legalPlaysFor` has an internal AKA carve-out independent of `R.IsLegalPlay`. (Did not verify in this pass.)

**Low confidence / unverified** on:
- Whether the Bot.PickAKA "trick-1 skip" is intentionally opposite of G18-10 or simply the developer reading G18-10 differently from the audit's interpretation.
- Whether B1 has been observed in metrics — no test directly exercises the void-in-led + has-trump + AKA-active receiver scenario per the test grep results (only `s.akaCalled = nil` resets, no positive AKA tests).

---

## Cross-reference summary table

| Phase-1 rule | Code path | Status |
|---|---|---|
| G18-02 / J-066: AKA Hokm-only | Bot.PickAKA:3110, N.LocalAKA:2337, N._OnAKA:3076, UI:2037, S.LocalAKAcandidate:1345 | **Y** (defence-in-depth) |
| G18-03: AKA non-trump only | Bot.PickAKA:3129 | **Y** |
| G18-04: AKA on largest-remaining | Bot.PickAKA:3139 via S.HighestUnplayedRank | **Y** |
| G18-05: AKA only when leading | Bot.PickAKA:3111 | **Y** |
| G18-06: AKA releases partner from must-trump | pickFollow:2427 (heuristic) + **Rules.lua absent** | **Partial / probably broken (B1)** |
| G18-07: extra trick from saved trump | Implicit in B1 fix; no explicit code | **Implicit only** |
| G18-08 / D-R3: implicit AKA via bare-A lead (receiver) | pickFollow:2396-2426, touching-honors:478-486 | **Y** |
| G18-09: 3×3 decision matrix | Bot.PickAKA gates 3110-3203 | **Partial — collapsed to gate-stack** |
| G18-10 (late-game): conservative late | Bot.PickAKA:3184-3200 | **Y** |
| G18-10 (doubled): conservative | — | **N (B3)** |
| G18-10 (early-game): permissive | Bot.PickAKA:3151 (opposite — strict skip) | **N / opposite (B4)** |
| G18-11: AKA-on-Ace = wrong-call risk | Bot.PickAKA:3136 (skip Ace = redundant) | **Y (sender-side)** |
| G18-12 / G18-13: AKA on 10/K/Q valid if higher dead | S.HighestUnplayedRank walks order | **Y** |
| J-067 part 1: AKA-on-10 substitutes for Ace + locks trick | — | **N (B5)** |
| J-067 part 2: exempts partner from must-trump-ruff | pickFollow:2427 | **Partial (see B1)** |
| J-068: forgetting AKA = ruff still required | Default Rules.lua behavior (must-trump unless explicit AKA banner) | **Y** (by absence) |
| J-069: false AKA = Qaid | — | **N (B2)** |
