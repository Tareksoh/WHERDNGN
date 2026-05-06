# B-Rules-01: R.IsLegalPlay (post-v0.10.2 AKA-aware)

## Scope verified

- `R.IsLegalPlay` body: `Rules.lua:89-210`. The new optional 6th arg
  `akaCalled = {seat, suit}` lifts must-trump-ruff for the receiver
  when partner has called AKA on the led suit (Hokm only).
- AKA-relief gate: `Rules.lua:115-121` (computed early, applied at
  `Rules.lua:175` AFTER the must-follow check, BEFORE must-trump).
- Pre-v0.10.2 the bot's `pickFollow` AKA-receiver branch
  (`Bot.lua:2546-2548`) was structurally dead — `R.IsLegalPlay`
  filtered non-trumps out of `legal` before the branch could pick
  them. Per `xref_X2_aka.md` B1 the code is now wired.

## Caller audit

Verified the v0.10.2 changelog claim that "3 Net.lua sites + Bot.lua
`legalPlaysFor`" pass `S.s.akaCalled`, simulators omit it.

**Live-play call sites that DO pass akaCalled (correct):**

- `Bot.lua:1610` — `legalPlaysFor` reads `S and S.s and S.s.akaCalled or nil`.
- `Net.lua:2040` — `LocalPlay` anti-misclick warn.
- `Net.lua:3412` — AFK auto-play in `_HostCheckTurnTimer`.
- `Net.lua:4136` — bot-side host fallback after meld error.
- `State.lua:1219` — host-side `S.ApplyPlay` illegal-mark for
  Takweesh resolution.

**Simulator/rollout call sites that DO NOT pass akaCalled (intentional):**

- `BotMaster.lua:649` — ISMCTS `heuristicPick` rollout opponent simulation.
- `BotMaster.lua:830` — `BM.PickPlay` legal-list construction at
  the actual decision point.
- `Rules.lua:435` — `R.IsValidSWA` minimax recursion.

**Live-play call sites that DO NOT pass akaCalled (DIVERGENCE):**

- `State.lua:1665` — `S.HostValidatePlay`.
- `State.lua:1966` — `S.GetLegalPlays` (UI/local helper).

See findings F1, F2 below for divergence details.

## Findings

### F1 [SEVERITY: high]: BotMaster.PickPlay (line 830) omits akaCalled — Saudi Master tier ignores AKA-relief at its primary decision point

- **Where:** `BotMaster.lua:830` — `BM.PickPlay` builds its initial
  legal-plays list with `R.IsLegalPlay(c, hand, trick, S.s.contract, seat)`,
  no 6th arg.
- **Issue:** `BM.PickPlay` is the *real-time* decision entry for
  Saudi Master tier bots — it is NOT a rollout simulator. The user
  intent at `Bot.lua:1605` ("Simulator callers `R.SunCanRolloff`
  deliberately omit the param so rollouts get AKA-blind semantics")
  refers only to the rollout sim, but `BM.PickPlay` itself is the
  outer driver, called once per real turn. Skipping `S.s.akaCalled`
  here means the AKA receiver running on Saudi Master tier sees
  `legal` filtered to trumps only when void+has-trump, then enters
  ISMCTS without the non-trump-discard option, and ruffs anyway —
  exactly the dead-code bug the v0.10.2 fix was supposed to close.
  `Bot.PickPlay` correctly delegates to `BM.PickPlay` when Saudi
  Master is active (per `CLAUDE.md` v0.5.0 fix), so the entry-side
  `legalPlaysFor` upgrade does NOT cover this path — `BM.PickPlay`
  builds its OWN legal list.
- **Source:** `xref_X2_aka.md` B1 (the reason the param was added);
  `CHANGELOG.md` v0.10.2 entry "every live-game legality check";
  `signals.md`/decision-trees.md Section 6 row 169 ("Released from
  must-ruff — already wired (v0.5.1 H-5)").
- **Recommendation:** Pass `S.s.akaCalled` as the 6th arg at
  `BotMaster.lua:830`. The rollout-internal `heuristicPick` at
  line 649 should remain AKA-blind (rollouts shouldn't propagate
  transient banner state into hypothetical futures), but the outer
  decision-point list at 830 must match `Bot.legalPlaysFor`
  semantics. Add a regression pin to `test_state_bot.lua` exercising
  Saudi Master tier under partner-AKA-on-led-suit + void receiver.

### F2 [SEVERITY: medium]: State.HostValidatePlay (line 1665) and S.GetLegalPlays (line 1966) omit akaCalled

- **Where:**
  - `State.lua:1665` — `S.HostValidatePlay(seat, card)` returns
    `R.IsLegalPlay(card, s.hostHands[seat], s.trick, s.contract, seat)`.
  - `State.lua:1966` — `S.GetLegalPlays()` iterates the local hand
    with the same 5-arg call.
- **Issue:** Both are live-play helpers. `HostValidatePlay` is a
  thin host-side wrapper that does not appear to be wired into the
  current play path (the actual host validation lives at
  `State.lua:1219` inside `S.ApplyPlay` and DOES pass
  `s.akaCalled`), so this is mostly latent — but if any future
  refactor calls `HostValidatePlay` directly, it would mark a legal
  AKA-relief discard as illegal and trigger a Qaid against the
  AKA-receiver. `S.GetLegalPlays` is consumed by UI (e.g., card-tile
  legality dimming) — when the human is the AKA receiver, the UI
  would mark non-trump discards as illegal and the player would be
  unable to discover the relief option without playing through the
  Takweesh-warning path.
- **Source:** `signals.md` AKA receiver convention; `xref_X2_aka.md`
  B1 ("AKA-aware legal-play override").
- **Recommendation:** Pass `s.akaCalled` (resp. `S.s.akaCalled`) in
  both call sites for parity with the rest of the live-play
  surface. UI dimming consistency in particular is user-visible.

### F3 [SEVERITY: medium]: Receiver-relief enforces must-follow but the comment claims it applies BEFORE must-follow — comment is misleading, but the silent enforcement of must-follow is the correct rule

- **Where:** `Rules.lua:113-114` comment vs `Rules.lua:115-175` flow.
- **Issue:** The comment block at `Rules.lua:113` says "This relief
  applies BEFORE must-follow / must-trump checks so a void+trump
  receiver may discard freely." But the actual code computes
  `akaRelief` early at line 115-121 and applies it at line 175
  AFTER the `hasLead` must-follow path (line 128-160). A receiver
  who DOES have a card of the led suit is still bound by must-follow.
  This is *correct Saudi behavior* (AKA only relieves must-trump-ruff
  when void; it does not let a non-void receiver throw away their
  card-of-led-suit), and matches the test fixture in test_rules.lua
  Section Q (test setup keeps the receiver void in led suit). But
  the comment misrepresents it.
- **Source:** `signals.md` AKA-receiver convention + decision-trees.md
  Section 6 row 169 ("Released from must-ruff" — only must-ruff,
  not must-follow); video #42 transcript line 71-87 confirms must-
  follow is independent.
- **Recommendation:** Edit the comment in `Rules.lua:113-114` to
  "This relief applies after must-follow but BEFORE must-trump-ruff
  enforcement, so a void+trump receiver may discard freely." No
  code change needed.

### F4 [SEVERITY: low]: Stale-banner defense is partial — relies on State.lua to clear akaCalled, no defensive seat-vs-contract.bidder-partner cross-check in Rules.lua

- **Where:** `Rules.lua:115-121` AKA-relief gate.
- **Issue:** The relief check verifies `R.Partner(seat) == akaCalled.seat`,
  i.e. that the AKA caller is the receiver's partner. It does NOT
  verify that the seat with the AKA banner is currently the lead-
  trick winner or that `akaCalled.suit ~= contract.trump`. State.lua
  has multiple paths that clear `s.akaCalled`:
    - `State.lua:1257, 1263` (M3 false-AKA wipe).
    - `State.lua:1327` (`ApplyTrickEnd` per-trick clear).
    - `State.lua:110, 524, 795, 1446` (round/reset/init paths).
  The M3 false-AKA wipe (line 1257) catches the case where the AKA
  caller leads a non-boss card. But there is no defensive guard if
  someone (hostile peer, race condition during /reload replay frame
  at `Net.lua:461-464`) re-asserts `s.akaCalled` with `suit == trump`.
  The Saudi rule is AKA is non-trump-only — this is enforced at
  `Bot.PickAKA:3110`, `N.LocalAKA:2347`, `N._OnAKA` (Hokm gate, but
  no trump-suit gate in `_OnAKA`). A spoofed AKA-on-trump banner
  would propagate into Rules.lua and grant relief on a trump-led
  trick (where the relief rule structurally doesn't make sense —
  trump-led already has its own partner-winning shortcut at
  Rules.lua:139-141).
- **Source:** `xref_X2_aka.md` per "AKA non-trump only: G18-03".
- **Recommendation:** Add `akaCalled.suit ~= contract.trump` to
  the relief gate as a belt-and-suspenders defense. The realistic
  attack surface is small (host-side false-AKA wipe handles the
  in-band case), but this is a 2-line defense against:
    - Resync replay frame replaying a stale or hostile akaCalled.
    - Future refactor that allows AKA-on-trump (would silently
      become a degenerate must-trump bypass).

### F5 [SEVERITY: low]: Test coverage gap — no positive test for AKA-active + lead is contract.trump; no test for the partner-winning + AKA-active interaction

- **Where:** `tests/test_rules.lua` Section Q (lines 1107-1156).
- **Issue:** Section Q covers:
    - Q.1, Q.2: no-akaCalled baseline (must-trump fires).
    - Q.3-Q.5: positive AKA, partner==caller, suit==leadSuit (relief).
    - Q.6: opp AKA negative.
    - Q.7: wrong-suit AKA negative.
    - Q.8: Sun-no-op.
  Missing canonical scenarios per F4 + Saudi-rules.md "Trick-play
  rules":
    - **Trump-AKA defensive case**: stale `akaCalled.suit == trump`
      (defensive — would matter if F4 is implemented).
    - **AKA + receiver has led-suit card**: must-follow still
      enforced, AKA does NOT lift must-follow. (See F3.)
    - **AKA + partner-winning shortcut**: redundant gate ordering
      verification — does the partner-winning shortcut at line 167
      mask the akaRelief check at line 175 in the natural case
      (partner led with their boss, no opp cut yet)? If yes the
      branch is reachable only after an opp over-trumps, which is
      the comment's intended scenario.
    - **AKA + stale banner from previous trick**: e.g. simulating
      a /reload replay where `akaCalled` is set but the lead seat
      doesn't match the AKA caller. (Currently the relief gate
      wouldn't fire because suit==leadSuit check filters it out
      naturally — verify with an explicit test.)
- **Source:** `xref_X2_aka.md` confidence note "no test directly
  exercises the void-in-led + has-trump + AKA-active receiver
  scenario per the test grep results"; signals.md / decision-trees.md
  Section 6.
- **Recommendation:** Add 3-4 pins to test_rules.lua Section Q
  exercising the missing scenarios. None of these are blockers, but
  the `akaCalled.suit == trump` test would exercise F4 if that
  defense is added.

### F6 [SEVERITY: info]: Param name `akaCalled` is clear — matches the state field name `S.s.akaCalled` exactly, and the AKA-receiver relief intent is documented in the function-level comment

- **Where:** `Rules.lua:89` signature; `Rules.lua:103-114` block comment.
- **Issue:** None. Param name matches `S.s.akaCalled` 1:1 across
  all caller sites (Bot.lua:1607, Net.lua:2040/3412/4136,
  State.lua:1219). Reader can grep one identifier and find every
  reference. The comment block correctly cites J-066/J-067 part 2
  and `xref_X2_aka.md` B1+B5 as the source-of-truth backings.
- **Source:** N/A — this is positive observation only.
- **Recommendation:** None.

### F7 [SEVERITY: info]: SunCanRolloff comment reference at Bot.lua:1605 is incorrect — no such function exists

- **Where:** `Bot.lua:1605` comment "Simulator callers (R.SunCanRolloff line 409) deliberately omit the param".
- **Issue:** Grepping `SunCanRolloff` across the addon shows it
  appears ONLY in this comment + the CHANGELOG.md echo. There is
  no `R.SunCanRolloff` function. The actual rollout simulator that
  omits the param is `BotMaster.lua:649` (`heuristicPick` inside
  `BM.PickPlay`). The comment is documentation drift — likely a
  prior name during planning.
- **Source:** Grep verification across `*.lua` files shows zero
  function definitions matching the name.
- **Recommendation:** Edit the comment in `Bot.lua:1604-1606`
  (and the matching `CHANGELOG.md` v0.10.2 line 22) to point at
  `BotMaster.lua:649` (`heuristicPick` rollout simulator) instead.
  Cosmetic — does not affect runtime.

## Verdict

NEEDS-ATTENTION. The core Rules.lua patch is logically correct and
matches Saudi convention (J-066/J-067 part 2). Tests cover the
canonical positive + 2 negative cases. However:

- F1 (high): `BotMaster.PickPlay` decision-point legal-list at line
  830 omits the param. For Saudi Master tier bots — the
  highest-tier picker — the AKA-receiver relief is still dead. This
  partially negates the v0.10.2 fix's primary goal.
- F2 (medium): `HostValidatePlay` (latent) and `GetLegalPlays` (UI
  dimming) divergences create an inconsistent legality view across
  the live-play surface.

F3-F5 are quality items. F6-F7 are documentation/cosmetic.

The v0.10.2 changelog claim "every live-game legality check" is
inaccurate — three live-game call sites (`BotMaster.lua:830`,
`State.lua:1665`, `State.lua:1966`) still use the AKA-blind 5-arg
form.

## Confidence

HIGH on F1, F2, F3, F6, F7 (each verified by direct file:line read).

MEDIUM on F4 (defensive trump-suit guard — argument depends on
whether the surface attack vector is realistic; State.lua's M3
false-AKA wipe blocks the in-band case).

MEDIUM on F5 (test gap — coverage is sufficient for the documented
canonical case; the missing scenarios are edge cases or would only
matter if F4 is implemented).
