# D-RT-03 — Hokm Faranka exception interactions, post-v0.10.2 edge probe

**Reviewer:** Track-D red-team agent
**Scope:** Adversarial probing of `pickFollow`'s Hokm Faranka block at
`Bot.lua:2857-3022` for misbehaviour after the v0.10.0 X3 closures
(Exception "#3" bidder-team gate, Exception "#4" relax to bidder-team,
F-16 K-of-trump anti-rule) and the v0.10.2 carry-forward.

**Sources read end-to-end:**
- `Bot.lua` 2740-3140 (block + surrounding pickFollow context)
- `Bot.lua` 320-440 (`Bot.OnPlayObserved` void inference)
- `Bot.lua` 660-690 (`opponentsVoidInAll` / `anyOpponentVoidIn` helpers)
- `Rules.lua` 16-30 (`R.TeamOf`, `R.Partner`)
- `State.lua` 340-355 (resync replay of `s.playedCardsThisRound`)
- `State.lua` 980-1023 (overcall side-effects on `s.contract.bidder`)
- `State.lua` 1349-1381 (`S.HighestUnplayedRank` trump-aware order)
- `Net.lua` 1761-1800 (`Bot.ResetMemory` call sites at round start)
- `B-Bot-02_hokmFaranka.md` (v0.10.2 code-track audit)
- `source_C_faranka.md` (Source C rules F-23 — F-39)
- `h1eEwSezzic_04_faranka_in_hokm.ar-orig.srt` (video 04 first 5 min)

Severity flags: **BUG** = behavior contradicts Source C / Saudi convention
or causes net-negative EV. **NIT** = sub-optimal but harmless. **OK** =
predicate behaves as intended on probe. **DEFER** = real concern but
mitigation is out of scope for v0.10.2 (carry to next track).

---

## TL;DR

Six new findings against the v0.10.2 Faranka block. None are regressions
introduced by the v0.10.0/v0.10.2 changes themselves; they are **new
edge-case exposures opened up or left unaddressed by those fixes**. Two
are functional EV leaks (S-1, S-3) — recommend fix in next release.
The rest are deferred or documentation-only.

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| S-1 | F-16 K-cover veto over-fires on F-30b (opps-trump-void path) | **BUG / EV-leak** | Recommend fix |
| S-2 | F-29 J-dead detection fires on same-trick J discard (mid-trick contamination) | **NIT** | Defer |
| S-3 | F-29 J-dead bypass via in-flight trick rebuild — partial trick-1 confound | **NIT / DEFER** | Defer; coverage gap |
| S-4 | M3lm-only gate at line 2880 — Advanced tier never Farankas (EV-leak vs source intent) | **NIT / DEFER** | Spec call: keep tournament-tier framing |
| S-5 | Anti-rule rule-7 (Q-led + J+8) is structurally dead code post-v0.10.0 | **NIT** | Harmless belt-and-suspenders, document |
| S-6 | onBidderTeam computed on `contract.bidder=nil` returns false (correct but silent) | **OK** | Confirmed safe; fragile if `R.TeamOf(nil)` semantics change |

The prompt's headline questions are answered in the per-scenario
sections below. **No new bugs were introduced by v0.10.2 itself.** All
prompt items #1, #5, #7, #8 evaluate to OK; items #2, #3, #6 are
already correctly handled by code; item #4 is a defensible spec choice.
**Item #2** (the F-16 vs F-30b interaction) surfaces the lone real bug
discussed below.

---

## Scenario 1 — F-16 K-of-trump veto over-fires on Exception "#4" risk-free path

**Verdict:** **BUG (EV-leak, low–medium severity)**.

**Repro:**
- Tier: M3lm+ (gate at `Bot.lua:2880`).
- Contract: Hokm, trump = S, bidder = seat 3 (us), our team = bidder team.
- `Bot._memory[2].void["S"] = true` and `Bot._memory[4].void["S"] = true`
  — both opps observed-void in trump.
- Hand: `{ JS, 9S, AH, KH, AD, QC, 8C, 7C }` (J+9 trump but no K of trump).
- Opp leads QH; we have winners (any of A/K of H beats Q). `winners > 0`.

**Trace:**
1. Line 2898-2899: `onBidderTeam = true`.
2. Line 2900-2902: `myTrumpCount == 2` is **false** (we have 2 trumps:
   JS+9S). Wait — myTrumpCount IS 2. Trigger #2 fires. (Re-roll the
   probe: change hand to `{JS, 9S, 7S, AH, KH, AD, QC, 8C}` — 3 trumps.)
3. Line 2922-2932: `S.HighestUnplayedRank("S")` — assume J still live →
   returns "J". F-29 doesn't fire.
4. Line 2943-2955: `oppTrumpExhausted = true`. F-30b fires
   (`farankaTriggered = true`).
5. Line 2964-2972: K-of-trump scan over hand `{JS,9S,7S,AH,KH,AD,QC,8C}`
   → **no K of trump (KS)**. `farankaTriggered = false`.
6. Block falls through to natural play; we play a winner.

**Why this is wrong:**
Source C F-16's premise is "the K is the cover card backing up the
withhold". The reasoning relies on the *threat model* that an opponent
holds a card capable of attacking the trump we preserved (typically
the trump A in their hand, which would punish a withhold). **When
both opponents are observed void in trump, that threat model is
extinct** — they cannot punish, period. F-16 has no useful work to do
here. By F-30b's construction, the opps have zero trump remaining; even
without K-cover, withholding the top trump is risk-free.

**Net EV cost:** the bot misses the F-30b setup it just earned the
right to take. F-30b is rare to fire (requires both opps confirmed-void),
so absolute frequency of this confound is low — but every instance is a
~1-trick give-back at the M3lm+ tier.

**Recommended fix:** scope the F-16 veto to the **trump-attack-possible**
cases. Either:
- (A) Move the F-16 K-scan to be a pre-check on **only Trigger #2 and
  Trigger #3** (the "opp can still attack trump" cases). Skip it on
  Trigger #4 / F-30b, where the predicate already proves opps can't
  attack.
- (B) Add an inline early-exit: `if oppTrumpExhausted then -- skip F-16`.
- (C) Compose: K-cover veto applies when `not oppTrumpExhausted`.

Option (A) is closest to Source C's framing (F-16 is a per-rule
anti-rule; its scope should be per-rule). Recommend (A).

**Confidence:** **HIGH** — Source C F-16 rationale + F-30b predicate are
both unambiguous.

**Notes:**
- B-Bot-02 (F3) explicitly evaluated F-16 as "correct in all cases
  inspected" but didn't probe the F-30b interaction — the audit framed
  F-16 as a universal safety; this red-team disambiguates.
- The Source C row F-30 for the Hokm side-suit "A+K of side" hand-shape
  is **separately not wired** (X3 Bug 3) — the code's F-30b is a
  trump-only formulation. The K-of-side is not what F-16 was checking
  against in Source C either; F-16 is "K of the suit you'd be Faranka'ng".
  In a trump-only Faranka (code's F-30b), F-16's "K of trump" reading is
  the right card; in a side-suit Faranka, F-16 would target K-of-side.
  **Out of scope for this fix** but worth tracking.

---

## Scenario 2 — F-29 J-dead detection fires on same-trick J discard

**Verdict:** **NIT** — sub-optimal trigger semantics; small absolute EV.

**Repro:**
- Hokm; trump = S; bidder = seat 1 (partner of us, seat 3); we're seat 4
  in this trick. Trick so far: `{seat=2, card=AH}` (lead), `{seat=3,
  card=JS}` (partner ruffed with the J of trump as a sluff or forced
  ruff — see below). We hold `{ 9S, KS, KH, ... }`.
- Note: a "ruff with J of trump" is rare for partner unless they were
  forced (they have S as their only legal play after running out of H).
  But mid-trick can also place the J via a discard on a non-trump-led
  trick when the seat is void in lead and chooses to dump the J — also
  rare but legal.

**Trace:**
1. `s.playedCardsThisRound["JS"] = true` after partner played
   (rebuilt-on-resync at State.lua:343-353; for live play same effect via
   `S.AppendPlay` updating).
2. We're at line 2922: `S.HighestUnplayedRank(contract.trump)` —
   `S.HighestUnplayedRank("S")` walks the trump order
   `{J, 9, A, T, K, Q, 8, 7}`; "JS" is in `playedCardsThisRound` → returns
   "9".
3. We have 9S → `hold9 = true` → `farankaTriggered = true`.
4. F-16 scan: KS in hand → passes. We Faranka.

**Why this is wrong-ish:**
Source C F-29 ("Hokm Exception #5") wording is "اذا الولد لعب من اول"
("if the J was played at the start") — referring to a **prior trick's**
J fall, which establishes the 9 as durable top-trump for the rest of
the round. Same-trick J fall (especially as a discard or ruff
in-progress) doesn't establish the same durable state. The reason is
strategic: F-29's payoff is "withhold 9 now, snipe with 9 on a later
trick when opp leads trump again". When J fell mid-trick, we may not
even need to withhold — if opp is winning the trick with say AH (lead)
and we have KS or KH winners, the natural pos-4 cheapest-winner play
already takes the trick; Farankaing here means giving up an immediate
trick we'd otherwise win.

**Realistic frequency:** very low. Same-trick J fall as a non-current-
play mid-trick condition requires a partner-trump-ruff or partner-J-
discard in trick T, then F-29 evaluating in same trick T after — but the
Faranka block is reached when we're following, so it's possible.

**Net EV cost:** marginal. The same-trick J fall almost always means
either (a) partner is winning (and we're in the partner-winning branch
above the Faranka block at `Bot.lua:2740-2848`, never reaching Faranka)
or (b) opp has a high lead we couldn't beat anyway (so `winners == 0`
guards us out).

**Recommended fix:** **DEFER**. Possible patch: gate F-29 on
`#(s.tricks or {}) > 0` — i.e., require at least one prior completed
trick to have happened. But the cost of the patch (dead-code branch
that's exercised by maybe 1 trick per 100 hands) is not worth a v0.10.2
slip.

**Confidence:** **MEDIUM** — Source C wording leaves ambiguity, and the
strategic-frequency argument is what dominates the verdict. Either
behaviour is defensible; the current code is slightly EV-loose but not
strictly wrong.

---

## Scenario 3 — F-29 against partial in-flight trick on resync

**Verdict:** **NIT / DEFER**; documentation gap.

**Repro:**
- Host crashes mid-trick (partner had just played JS, sealing J-dead).
  Host /reloads. State.lua:341-353 rebuild walks `s.tricks` (completed)
  AND `s.trick.plays` (in-flight). `playedCardsThisRound["JS"] = true`.
- Bot._memory IS NOT rebuilt from the snapshot — only `Bot._memory[seat]
  .void` and `.played` accumulate via `Bot.OnPlayObserved`, and the
  resync replay path does NOT call OnPlayObserved (the host's
  `MaybeRunBot` is the entry point; replays from snapshot bypass it).
- Result: `Bot._memory` is **fresh-empty** post-resync; no void flags
  set. F-30b cannot fire.

**Critical observation:** F-29 (`HighestUnplayedRank`-driven) **survives
resync correctly** because it reads `s.playedCardsThisRound` which IS
rebuilt. F-30b (`Bot._memory[s2].void[trump]`-driven) **does NOT survive
resync** — the void inferences are lost permanently for the rest of the
round.

**Net effect:** post-resync, F-30b is essentially dead until a fresh
off-suit play happens after the rejoin (which will re-set the relevant
`mem.void[trump]`). Some F-30b setups — where the only off-suit-trump
plays already occurred — are permanently un-detectable.

**Why this is a NIT not a BUG:**
F-30b is the rarest trigger anyway; the v0.10.0 X3 fix relaxed it from
bidder-self to bidder-team but the predicate is still very narrow.
Post-resync EV loss from this is small.

**Recommended fix:** **DEFER**. The proper fix is to replay
`Bot.OnPlayObserved` for every play in `s.tricks` during resync, but that
is a cross-cutting change touching multiple subsystems. Track for next
release as architectural follow-up.

**Confidence:** **HIGH** for the resync gap (verified at Bot.lua:331 and
State.lua:341-353); **MEDIUM** for the EV severity claim (F-30b firing
frequency is empirically untested).

---

## Scenario 4 — M3lm-only gate (line 2880) starves Advanced tier

**Verdict:** **NIT / DEFER** — defensible spec choice.

**Repro:**
- Player runs Advanced tier (`WHEREDNGNDB.advancedBots = true`,
  m3lmBots = false, etc.). Source-C-derived Faranka rules (5 source-C
  exceptions, 3 wired, all M3lm+) never fire.
- Lower tier bot plays natural winners every time.

**Why this is a NIT:**
- Source C frames Hokm Faranka as "Saudi tournament strategy" and
  Source C's rule F-23 says "default = NO" for Hokm. Lower tiers staying
  on the default-NO posture is *consistent* with source intent.
- Advanced tier is positioned as "heuristic but not tournament-grade";
  per CLAUDE.md tier table, M3lm is the "+ style ledger" tier. Adding
  Faranka to Advanced would conflict with the tier-progression design.

**Why it could be a BUG:**
- The 3 wired exceptions are pro-Faranka triggers that gain the bidder
  team EV. Refusing to take them at Advanced tier means a clear EV gap
  between Advanced and M3lm beyond just "extra style ledger". Source C
  F-23's "default NO" also says exceptions exist — if the addon enforces
  the exceptions, all tiers should benefit.

**Net assessment:** **DEFER** — this is a spec call by the author. Either
posture is defensible; the v0.10.2 review-only scope can't resolve it.

**Confidence:** **HIGH** that the gate is M3lm-only (`Bot.IsM3lm()` per
B-Bot-02 F8); **LOW** that the EV gap matters in practice (no
tournament telemetry available).

---

## Scenario 5 — Anti-rule rule-7 (Q-led + J+8) is structurally dead code post-v0.10.0

**Verdict:** **NIT** — harmless redundancy; document only.

**Repro:**
- Hokm; trump = S; **opp is bidder** (e.g., bidder = seat 2, we are
  seat 4 = same team as seat 2... wait). Reconstruct: opp leads Q of
  trump means lead.seat is opp = bidder. Then `lead.seat == contract.
  bidder` and `R.TeamOf(lead.seat) ~= R.TeamOf(seat)`.
- We're at line 2974 anti-rule. But to reach this line, `farankaTriggered`
  must be true at line 2974. **Each trigger requires `onBidderTeam`**.
  `onBidderTeam = (R.TeamOf(contract.bidder) == R.TeamOf(seat))`. If
  `R.TeamOf(lead.seat) ~= R.TeamOf(seat)` AND `lead.seat ==
  contract.bidder`, then `R.TeamOf(contract.bidder) ~= R.TeamOf(seat)`,
  so `onBidderTeam = false`, so no trigger fired, so we're not at line
  2974. **Contradiction.**

**Result:** the rule-7 anti-trigger un-veto path at `Bot.lua:2974-2993`
**cannot be reached** after v0.10.0 X3 added the bidder-team gate to
all 3 triggers (and v0.9.2 #49 added it to Trigger #2). It is dead
code.

**Why this is a NIT not a BUG:**
- Belt-and-suspenders. If a future change relaxes `onBidderTeam`
  semantics on any trigger, the J+8 anti-rule re-activates as a real
  veto. Defensive code is fine.
- Zero correctness impact at v0.10.2.

**Recommended fix:** none (keep as defensive). Suggest a one-line code
comment marking it as "intentionally unreachable post-v0.10.0; kept for
future-proofing". No functional change.

**Confidence:** **HIGH** — gate analysis is straightforward; B-Bot-02 F6
also reaches the same conclusion.

---

## Scenario 6 — onBidderTeam with `contract.bidder=nil` mid-resync / forced-Takweesh

**Verdict:** **OK** — predicate is correct; latent fragility flagged.

**Probe:**
What happens to the Faranka block if `contract.bidder` is nil at the
moment the block evaluates?

**Trace:**
- `onBidderTeam = (contract.bidder and R.TeamOf(contract.bidder) ==
  R.TeamOf(seat))`. Lua short-circuit: `contract.bidder` is nil →
  expression evaluates to nil → `onBidderTeam = nil`.
- All 3 triggers gate on `onBidderTeam` (truthiness). Nil is falsy →
  triggers skip → `farankaTriggered` stays false.
- F-16 scan only runs if `farankaTriggered` → skipped.
- J+8 anti-rule (`if lead.seat == contract.bidder`) — nil-bidder makes
  this `lead.seat == nil`, which is false (lead.seat is always a valid
  seat 1-4 in `trick.plays[1]`). Veto skipped, but irrelevant since
  `farankaTriggered` is already false from the gate above.

**Result:** nil-bidder safely produces "no Faranka" — the conservative
default. Correct.

**Latent fragility:**
- `R.TeamOf(nil)` returns "B" silently (cited as Rules.lua F-04 in
  B-Rules-10). If a future caller did
  `R.TeamOf(contract.bidder) == R.TeamOf(seat)` without the
  short-circuit guard, nil-bidder would mis-attribute the bidder to team
  B and could spuriously enable a trigger. **The current code's
  short-circuit prevents this**, but the code style is non-uniform —
  e.g., other call sites in `Bot.lua:1153-1156`, `1808-1809` defend
  with `if not contract.bidder then return ...` instead. The Faranka
  block's use of inline short-circuit is fine but subtler.

**Recommended fix:** none. **Confidence: HIGH.** The defensive layering
in `R.TeamOf` (B-Rules-10's recommended tightening to return nil for
invalid seats) would harden every call site. Track at the Rules-track
level, not Faranka.

---

## Scenario 7 — Played-cards corruption resilience for Exception "#3"

**Probe (prompt item #7):**
Could a corrupted `s.playedCardsThisRound` falsely trigger F-29?

**Setup:** what corruptions can `s.playedCardsThisRound` exhibit?

1. **JS missing despite J actually played:** `HighestUnplayedRank("S")`
   returns "J" (or whatever's higher in the order); F-29 sees "J" not
   "9"; trigger doesn't fire. Conservative — false negative, no
   misbehaviour.
2. **JS spuriously present despite J actually live:** rebuild bug or
   manual mutation. `HighestUnplayedRank("S")` returns "9" (assuming
   that's the next live rank); F-29 fires; we Faranka. **Could
   surrender a winnable trick** if J is in fact live with opp.
3. **Duplicate ranks (e.g., JS twice):** Lua key-set semantics dedupe;
   no effect.

**Defensive analysis:** the rebuild at State.lua:343-353 walks
`s.tricks` (completed plays from authoritative state) and
`s.trick.plays` (in-flight). It does not introduce phantom keys; it can
only fail to add real ones (e.g., if `s.tricks` is itself stale on a
client). Corruption (2) requires a malicious or buggy snapshot — not a
realistic attacker model for a co-op WoW addon.

**Verdict:** **OK**. Corruption (1) is conservative; corruption (2)
requires non-adversarial snapshot bug; no robust mitigation needed
beyond what State.lua already does (rebuild from authoritative tricks).

**Confidence:** **HIGH**.

---

## Scenario 8 — Bidder-team gate bypass for forced/Takweesh contracts (`contract.bidder=nil`)

**Probe (prompt item #8):**
Per `State.lua:1003`, after `S.FinalizeOvercall` resolves a TAKE,
`s.contract.bidder = result.by` — always a valid seat. Per
`State.lua:1015`, `TAKE_HOKM` does the same. Per `S.ApplyContract` at
`State.lua:1025+`, the bidder is always set via the function param.

**Question:** is there any code path where `contract.bidder` becomes
nil after being set?

**Trace:**
- Grep for `contract.bidder = nil` in `WHEREDNGN/` returns 0 matches in
  source files. Only narrative mentions in audit / changelog.
- `S.ResetForNextRound` (or equivalent) resets the entire `contract`
  table, not just `bidder`. New round begins → new contract → bidder
  set fresh.
- Forced contract / Takweesh recovery: I found no code path where
  Takweesh would leave `bidder=nil`. Takweesh is its own resolution
  flow that sets a result struct including `by` (the seat that
  Takweesh'd or the dealer-preempt seat).

**Verdict:** **OK** — the prompt's concern about "forced/Takweesh-recovery
contracts (contract.bidder=nil)" appears to be a false alarm. There is
no code path that produces nil-bidder mid-round in normal flow. **If**
such a path existed, Scenario 6 confirms the Faranka block would still
default to no-Faranka safely.

**Confidence:** **HIGH** for "no nil-bidder path in current source";
**MEDIUM** for "no future regression possible" (nothing structurally
prevents a future caller from setting nil — recommend a State-level
invariant).

---

## Cross-scenario synthesis: is the v0.10.2 block correct net-net?

| Prompt item | Verdict | Scenario |
|---|---|---|
| 1. Trigger-ordering bugs (`if not farankaTriggered` short-circuit) | OK — OR-semantics correct | (B-Bot-02 F7 audit re-verified) |
| 2. F-16 vs F-30b interaction (no K but opps void) | **BUG — over-veto** | **S-1** |
| 3. Anti-rule rule-7 vs F-16 K-required | NIT — rule-7 dead code | S-5 |
| 4. M3lm-only gate (line 2880) | NIT / spec call | S-4 |
| 5. `onBidderTeam` with `contract.bidder=nil` | OK | S-6 |
| 6. Source-C F-14 transcription slip — code reads corrected intent | OK (B-Bot-02 F4) | (Sun-block, not Hokm) |
| 7. Exception "#3" J-dead corruption robustness | OK | S-7 |
| 8. Bidder-team gate bypass for forced/Takweesh | OK — no path exists | S-8 |

**Bottom-line recommendation for next release:** apply S-1's fix
(scope F-16 to non-F-30b path); track S-3 (resync void replay), S-4
(tier policy), and S-5 (dead-code annotation) as documentation /
deferred items.

---

## Ranking of findings by suggested ship-priority

1. **S-1 (BUG)** — F-16 over-vetoes F-30b. Single-line fix. **Ship in
   v0.10.3** (next release).
2. **S-3 (DEFER)** — resync replay of `Bot._memory`. Cross-cutting,
   schedule for the resync-track epic.
3. **S-2 (NIT)** — F-29 same-trick J. Defer; cost > benefit.
4. **S-4 (DEFER)** — tier gate. Author spec call.
5. **S-5 (NIT)** — annotate J+8 as defensive-only. One-line comment.
6. **S-6, S-7, S-8 (OK)** — no action; document robustness for next
   audit.

---

## Confidence summary

- S-1: **HIGH** confidence in the bug. Source C F-16 reasoning + F-30b
  predicate are both unambiguous.
- S-2: **MEDIUM** — Source C wording is ambiguous; live-play frequency
  argument dominates.
- S-3: **HIGH** for the resync gap (verified call paths), **MEDIUM** for
  EV severity (untested).
- S-4: **HIGH** for "gate is M3lm-only", **LOW** for whether the EV gap
  matters at lower tiers.
- S-5: **HIGH** — gate analysis chain is straightforward.
- S-6, S-7, S-8: **HIGH** — all probed against current source paths
  end-to-end.
