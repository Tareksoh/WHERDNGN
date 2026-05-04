# Endgame — Faranka, the smart move, last 3 tricks, SWA, Al-Kaboot

> **For operational rules see [`decision-trees.md`](./decision-trees.md)
> Sections 5, 7, and 10.** This file is the *prose* explanation —
> background, examples, and source provenance.

## What this file informs

- `Bot.PickPlay` → `pickLead` trick-8 branch (Bot.lua:953)
- `Bot.PickPlay` → `pickFollow` pos-4 branch (Bot.lua:1457)
- `Bot.PickSWA` (Bot.lua:2120, v0.5.1)
- AL-KABOOT pursuit logic (v0.5.1 C-4)
- **NEW**: Faranka heuristic in `pickFollow` (~15 rows in
  decision-trees.md Section 10, currently not wired)
- **NEW**: deceptive-overplay heuristic (`pickFollow.deceptiveOverplay`,
  not yet wired)

---

## 1. Faranka (فرنكة) — the strategic withhold

Faranka is the technique of **deliberately ducking your highest
card** of a suit when you legally could play it, so you can capture
a *later* trick with that top instead. The mechanic is **the same in
Sun and Hokm**; the strategic prior **inverts**.

### The mechanic

Three concrete benefits, in order (per video #6):

1. **Win two tricks instead of one** — partner takes the current
   trick; you cash your saved top later.
2. **Preserve partner's Al-Kaboot run** — your high card would
   block partner's sweep; ducking lets the sweep continue.
3. **"Fish" the opponent's 10** — your second-rank card (J/T)
   beats whatever the next-round opponent plays.

### Sun Faranka (default = YES, when factors align)

The video #6 author lists **5 factors** that increase "Faranka
percentage" (نسبة الفرنكة). Any combination — additive, no single
one mandatory:

1. You hold **J + A** of the led suit (J as recapture vehicle).
2. Partner is the player who will TAKE the trick (current winner).
3. Current play is heading toward **Al-Kaboot** — successful
   Faranka maintains partner's sweep.
4. Score tracking shows Faranka-success will **flip the round-loss
   onto opponents**.
5. The player to your **left (LHO, who leads next)** is the
   *bidder* and is leading the first trick of a fresh hand —
   proxy for "LHO holds the missing 10".

**Anti-triggers** ("don't Faranka"):
- No J in hand (just A + smaller — no recapture vehicle).
- ≥3 cards of the suit (10 drops naturally).
- You hold the **two highest unplayed** (always capture).
- Opponents are bidders threatening Al-Kaboot AGAINST you (defend,
  don't experiment).

### Hokm Faranka (default = NO, except narrow cases)

Trump is short in Hokm — withholding is high-variance. Default
rule: do NOT Faranka in Hokm. Five exceptions:

1. **Pursuing Al-Kaboot** ("النوع الثالث") — variance acceptable
   because losing ANY trick already kills Kaboot.
2. **You hold only 2 trumps total** — your trump posture is already
   weak; Faranka costs little incremental EV.
3. **The J of trump is already played/dead** and your 9 is now
   the top live trump — withhold the new top.
4. **You are bidder + opponent trump exhausted** — no one can
   punish the withhold.
5. **Partner has shown extra trump** (cut a side suit cleanly) —
   cover-burden shifts to partner.

### Hokm anti-Faranka rules (video #4)

- **If bidder is OPPONENT** — DO NOT Faranka. Opp has long trump;
  withholding gets rolled later.
- **If you hold only the 9 of trump and opp Faranka'd** — MUST
  take with the 9 (kills the AKA threat AND prevents 9 stranding).
- **Worst-case planning** — assume any held-back trump is in the
  worst-case opponent hand. If you can survive the worst case,
  Faranka is acceptable; otherwise draw trump.

### Saudi-Master variant: sacrifice the T (video #6, #8)

Pro-tier extension: instead of ducking with second-highest,
sacrifice the **10 itself**. Costs more (10 raw + tempo) but creates
ironclad "void below" deception. Speaker: "ما يسويها الا واحد
محترف في البلد" — only a real pro plays this.

Tier-fit:
- Basic / Advanced — won't find the sacrifice.
- M3lm — should find J-sacrifice in Sun.
- Fzloky — should find both J-sacrifice (Sun) and J-trump-
  sacrifice (Hokm).
- Saudi Master — only tier that should attempt T-sacrifice in Sun
  (ISMCTS rollouts may discover it; hand-coded heuristic risks
  misfiring at lower tiers).

---

## 2. The "smart move" — top-card sacrifice for deception (video #8)

A specific tactical pattern with **no settled Saudi name**. Author
explicitly invites viewers to suggest one. Internal label:
`pickFollow.deceptiveOverplay`.

### The setup (Sun)

You're 4th to play. Partner played T (or led with high). Opp-2
played a low card (8). You hold both J and 9 of led suit; you'd
take the trick either way. Standard play: 9. **Smart play: J.**

### Why it works

From the opponent's perspective:

> "He played the J. If he had any card below the J, he'd have
> played that — he wouldn't waste his top. So J was his only
> card in this suit. The 9 must be at his partner's seat."

Opp now believes partner has the 9. When they next get the lead,
they'll continue the suit — and walk into your saved 9.

### Concrete payoffs

1. **Break Al-Kaboot pursuit** — if opps are sweeping, getting
   them to feed you a winner kills the sweep (saves 220 raw in Sun).
2. **Rescue a failing bid** — bidder team behind, forced suit
   re-lead lets you cash a hidden winner.
3. **Set up SWA** — the deception buys tempo to declare سوا.

### Hokm variant — goal inverts

Same hand shape, but in Hokm the goal **flips**: you sacrifice the
J of trump to convince opp NOT to re-lead trump (preserving your
remaining 9 of trump as a future winner). Suppress the re-pull
instead of inducing the re-lead.

### Anti-triggers

- Hokm with **3+ trumps including A** — the A guarantees a winner;
  bait is wasted.
- **Partner has Tahreeb'd you** — Tahreeb takes priority over the
  bait (per video #8 explicit).

---

## 3. Last-trick targeting

The team that wins trick 8 gets +10 raw points (`K.LAST_TRICK_BONUS`).
6-7% swing on the round.

Late-game lead conventions (already wired in v0.5.0+v0.5.2):

- **Trick 8 boss-lead** — if you hold the highest unplayed in any
  suit, lead it. Non-trump bosses are safe when trump exhausted.
- **Trick 8 pos-4 picks high face-value** — when following on the
  last trick and you can win, choose the highest face-value among
  winners (T > A > K > Q > J in non-trump). Captures 10 face value
  + 10 last-trick bonus = 20 raw swing. (v0.5.2 BUG #3 fix.)

---

## 4. SWA (slam-with-ace)

`Bot.PickSWA` (Bot.lua:2120, v0.5.1) currently fires on
mathematical-certainty: bot holds highest unplayed in every
remaining suit AND ≤4 cards remaining.

### ~~Probabilistic SWA~~ — RETRACTED (video #35)

> **Earlier docs claimed Saudi pros sometimes SWA with sub-100%
> certainty. That was WRONG.** Video #35 explicitly: SWA is
> **deterministic-or-bust** in Saudi convention. The speaker rejects
> probabilistic SWA. Sub-100%-certain SWA is a procedural mistake
> that incurs Qaid (penalty) when proven unsound.
>
> Implications:
> - `Bot.PickSWA` (Bot.lua:2120) and `BotMaster.PickPlay` ISMCTS
>   should NOT generate probabilistic SWA claims.
> - Receiver-side: when opponent claims SWA, demand شرح (proof) —
>   if they cannot prove the claim, Qaid is awarded against them.

### Card-count thresholds (video #35 refinement)

- **≤3 cards remaining:** instant claim, no permission needed.
- **4 cards:** جلسة-dependent تستاذن (house-rule permission flow).
- **5+ cards:** **mandatory** تستاذن (must request permission).

Current code: instant ≤3, permission-flow ≥4. Video #35's 5+
mandate is **stricter** than current code — at 5+ cards, instant-
claim should be disallowed even if `WHEREDNGNDB.swaRequiresPermission
== false`.

### Failure modes

- **Unsound claim:** can't actually win every remaining trick → Qaid.
- **Missing شرح:** caller fails to provide proof when challenged → Qaid.
- **Skipped تستاذن:** caller didn't request permission at 5+ cards
  → Qaid.

Each gives the opp Qaid (`K.MSG_TAKWEESH_OUT` outcome).

### Bargiya as SWA setup (videos #1, #8)

When you hold the Ace of suit X and want to SWA on suit X
eventually, **discard the A early as a Bargiya signal**. Partner
reads "you have the slam in X" and leads X back when possible. The
deception buys you the right tempo to declare SWA on the back-end.

This is documented in [`signals.md`](./signals.md) Section 3 (Bargiya).

---

## 5. Al-Kaboot pursuit

Al-Kaboot = winning all 8 tricks. Bonuses: 250 raw in Hokm, 220 in
Sun (×2 multiplier = 440 effective in Sun).

### Pursuit triggers (already wired in v0.5.0+v0.5.2)

- Team wins tricks 1-7 → trick 8 is "Al-Kaboot reach".
- Pursuit mode: lead aggressive (use `highestByRank` in v0.5.0
  sweep-pursuit branch).

### Early-trigger pursuit at trick 3 (video #15)

Saudi pros switch to Kaboot pursuit much earlier than trick 8. The
trigger is **trick 3** when the following hand-shape feasibility
gate is met:

- Bidder team won tricks 1+2 cleanly with no opp cut surfacing.
- AND hand-shape is Kaboot-feasible:
  - **Sun:** 2× A+T pairs + extra A
  - **Hokm:** J+9 of trump + cover + void/singleton + partner-supply

If those conditions hold at the end of trick 2, switch to pursuit
mode at trick 3. This lets tricks 3-7 be optimized for sweep
rather than playing trick-by-trick optimally.

**Implementation note:** current `pickLead` Bot.lua:953 has only
the trick-8 sweep-pursuit branch. A trick-3 trigger needs new
state (`Bot._kabootPursuit` flag) set by `Bot.OnPlayObserved`
when the gate fires.

### Bel-vs-Kaboot multiplier interaction (video #15)

When the multiplier path scores higher than the sweep:

```
if K.MULT_BEL × hand_total > K.AL_KABOOT_HOKM:
    sabotage own sweep (تخريب الكبوت)
    let opp win one trick to land at multiplier instead
```

This is bidder-team behavior in a high-multiplier round. The bot
should evaluate the EV trade-off. **Not yet wired.**

### Reverse Al-Kaboot (الكبوت المقلوب) — video #16

Defenders sweep all 8 tricks against bidder = +88 raw. Qualifies
only when bidder was the trick-1 leader.

**This is a `Rules.lua` correctness item** — currently not scored.
Proposed constant: `K.AL_KABOOT_REVERSE = 88`. Single-source from
video #16; confirm before wiring.

### Defensive Qaid-bait (video #15)

Defender threatened by opp's near-Kaboot can deliberately mis-Qaid
to swap the 250-point Kaboot for the 26-point Qaid penalty. House-
rule territory; risky. Bot should NOT do this without dedicated
heuristic.

---

## 6. Late-trick discard discipline

Tricks 6-8 in Hokm have specific discard logic:

- **A of trump preservation** (v0.5.1 H-6) — don't waste A of trump
  on a trick partner already wins.
- **Belote preservation (K+Q of trump)** (v0.5.1 H-4) — keep K and
  Q together through tricks 1-3 to lock the +20.
- **Last-trick face-value priority** (v0.5.2) — trick 8 pos-4
  picks highest face value among winners.

### Tahreeb-priority on late tricks

If you're forced to discard late and partner has Tahreeb'd earlier,
**honor the Tahreeb** before any deceptive overplay. See
[`signals.md`](./signals.md) Section 7.

---

## 7. Match-point dynamics

When a team is at 130+ of 152 (cumulative), endgame strategy
shifts:

- **Defenders** become aggressive (Four/Bel willingness up — see
  [`escalation.md`](./escalation.md)).
- **Bidder's partner** plays conservatively to avoid Gahwa-bait.

Bot encodes via `matchPointUrgency` (Bot.lua:619) and
`scoreUrgency("defend")` (Bot.lua:588).

---

## Source video log

| Source | Title | Date processed | Sections informed |
|---|---|---|---|
| `01_tahreeb_beginners` | شرح التهريب في البلوت للمبتدئين | 2026-05-04 | Section 4 (Bargiya as SWA setup) |
| `04_faranka_in_hokm` | الفرنكة في الحكم | 2026-05-04 | Section 1 (Hokm default-NO + 5 exceptions, anti-Faranka rules) |
| `06_faranka_in_sun` | كيف تتفرنك في الصن | 2026-05-04 | Section 1 (mechanic, 5-factor framework, Sun default-YES) |
| `07_baloot_strategies` | استراتيجيات البلوت | 2026-05-04 | Section 5 (Al-Kaboot as bidder secondary goal — earlier promotion) |
| `08_smart_move` | حركه ذكيه في البلوت | 2026-05-04 | Section 2 (the smart move — Sun + Hokm variants, anti-triggers, tier-fit) |
| `14_bargiya_ace_tahreeb` | تهريب الاكة — البرقية | 2026-05-04 | Section 4 (Bargiya 2-flavor + receiver phase-split) |
| `15_kaboot_detailed` | الكبوت في البلوت | 2026-05-04 | Section 5 (early-trigger trick-3 pursuit, Bel-vs-Kaboot multiplier, defensive Qaid-bait) |
| `16_reverse_kaboot` | الكبوت المقلوب | 2026-05-04 | Section 5 (Reverse Al-Kaboot rule, +88 raw to defenders) |
| `17_k_tripled` | المثلوث K | 2026-05-04 | Section 6 (K-tripled trickle pattern) |
| `21_magnify_sun` / `22_magnify_hokm` / `23_miniaturize` | Takbeer/Tasgheer series | 2026-05-04 | Certainty-conditioned dump rules; Hokm trump non-consecutive inversion |
| `35_swa_term_detailed` | شرح مصطلح سوا | 2026-05-04 | Section 4 (SWA deterministic-or-bust, retracted probabilistic SWA, 5+ mandatory permission) |

---

## Open questions for future videos

- **Probabilistic SWA threshold** — when is sub-100%-certain SWA
  correct? Need a video discussing SWA timing decisions.
- **Mid-round Al-Kaboot pursuit triggers** — at trick 5/6/7, what
  observable conditions justify aggressive sweep play?
- **Counter-Faranka detection** — how does the bot detect that an
  opponent is *baiting* with a Faranka they don't actually intend
  to land? Currently no signal.
- **Multi-trick deceptive-overplay reuse** — once an opponent has
  seen the bait once, when (if ever) is it correct to repeat
  against the same opp same round?
