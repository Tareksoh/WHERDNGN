# Reaudit R2: Sun escalation chain (Triple/Four/Gahwa)

**Question.** Two PDFs and the Phase 1 K/L reports claim Sun has a truncated
escalation chain (Bel/Double only — no Triple/Four/Gahwa). Phase 1 also
flagged an internal contradiction inside PDF 02 (K-21 vs K-33). Current
code in `Rules.lua` and `Net.lua` *appears* to allow the full chain, and
`Bot.PickTriple/PickFour/PickGahwa` make decisions without Sun-specific
gates. Resolve.

**Answer (preview).** The PDFs and the video agree: in Sun, **only Bel
(×2) exists** as a multiplier rung — no Triple, no Four, no Gahwa. The
K-21 vs K-33 "contradiction" is not a contradiction in the rules; it is
a distinction between **call legality** and **escalation-chain reachability**
(see §Reconciliation). The current code already enforces the truncation
in practice through the phase-machine: `S.ApplyDouble` short-circuits
Sun + Bel directly to `PHASE_PLAY` (State.lua:1085-1087), so
`_OnTriple/_OnFour/_OnGahwa` and `Bot.PickTriple/PickFour/PickGahwa` are
never reached on a Sun contract. **No bug exists in the host pipeline.**
However, the Bot pickers and `R.ScoreRound` are missing
**defense-in-depth Sun gates** — they would happily honor a Sun-Triple
flag if one ever materialized. Recommended: add cheap explicit Sun
guards at three call sites (one liner each) plus one regression test.

---

## Quoted Arabic from each source

### Source K — PDF 02 (نظام اللعب في البلوت), p.2 — "سابعاً" (K-21)

```
ًسابعا: في حالة الدبل او الثري او الفور او
:القهوة ففي الصن اليوجد الثري والفور والقهوة وانما
يلعب
ًدبال
.فقط واليحق لالعب ان يدبل خصمة ال بعد ان يتجاوز المئة اي ١٠١.
```

Key clause (≤15 words): **«ففي الصن اليوجد الثري والفور والقهوة وانما يلعب دبلاً فقط»**

Translation: "In Sun there is **no Triple, Four, or Gahwa** — only Bel is
played." Combined with: "and a player may not Bel his opponent until the
opponent has exceeded 100 (i.e., 101)."

### Source K — PDF 02, p.3 — "بعض الملاحظات" (K-33)

```
كما هو الحال في
.الصن اليحق لالعب ان يعطي الثري النه يكتفي بالدبل
.فقط ماهو ممنوع ولكن ماله
داعي
```

Key clause (≤15 words): **«اليحق للاعب ان يعطي الثري ... ماهو ممنوع ولكن ماله داعي»**

Translation: "[Just like in...] **In Sun, a player has no right to give
Triple — Bel suffices.** It is not forbidden, but it has no purpose."

### Source L — PDF 07 (نظام الدبل في لعبة البلوت), p.1 — L34

```
نظام الدبل بالصن

( دبل فقط)

الن الدبل يكون بعد المئة وال يحتاج المشتري أن يطلب الثري ألنه يكتفي بالعدد ٢٥ لكي يفوز على
.خصمه

ويكون الدبل ٦٢ * ٢
=
 ٢٥  وجميع المشاريع تدبل.

ويكون الدبل للمتأخر فقط وهو الذي لم يتجاوز عدده ٠٠١

والصن اليوجد به أبناط.
```

Key clauses (≤15 words):
- **«نظام الدبل بالصن (دبل فقط)»** — "Doubling system in Sun: **Bel only**."
- **«ال يحتاج المشتري أن يطلب الثري ألنه يكتفي بالعدد ٢٥»** — "The buyer
  doesn't need to call Triple because reaching 52 [٢٥ RTL=52] is enough
  to beat the opponent."
- **«ويكون الدبل للمتأخر فقط وهو الذي لم يتجاوز عدده ٠٠١»** — "Bel can
  only be called by the trailing side — the one whose score has not
  exceeded 100."

### Video corroboration — `21fN1IEm5Xk_11_bel_beginners` (lines 105-119)

The host-rule statement and a soft "house variant" note both appear in the
same video:

```
105:بسيط طبعا
106:الصن ما في قهوه وفي بعض الجلسات ما
107:يلعبون
108:لانه يقول لك الصن مش نفس الحكومه الحكم
...
111:خلاص دبل يعني تظرف اثنين فقط ما في ثري
112:ولا قهوه في النهايه على حسب جلسه اللي
113:تلعب فيها لو مثلا انت جيت اشتريت هذه صن
114:او قلت اشكل كلها واحد وجاء هذا قال دبل
115:خلاص اللعب ينضرب في اثنين يعني
116:واذا كان اللعب بدون مشاريع واذا كانت
117:الجلسه تسمح بثريا او 4 خلاص في الثرية
118:راح تنضرب في ثلاثه والفور راح تنضرب
119:باربعه وصلى الله وبارك
```

Key clauses:
- **«الصن ما في قهوه»** — "Sun has no Gahwa."
- **«خلاص دبل يعني تظرف اثنين فقط ما في ثري ولا قهوه»** — "Just Bel, multiplied
  by 2 only — no Triple and no Gahwa."
- **«على حسب جلسه اللي تلعب فيها ... اذا كانت الجلسه تسمح بثريا او 4»** —
  "Depends on the session you're playing in ... if the session allows
  Triple or Four..."

The video corroborates **the canonical Saudi rule (Bel only in Sun)**
explicitly while acknowledging that **some house sessions allow** Triple/Four
in Sun as a non-canonical variant. This directly explains the "ماهو ممنوع"
hedge in K-33 — see §Reconciliation.

The other video, `Xxsf2QvaiU0_21_magnify_sun.ar-orig.txt`, discusses
Sun-magnification (takbeer / تكبير in Sun) but does not address the
Triple/Four/Gahwa question — it talks about scoring magnification, not the
escalation chain. No conflict either way.

---

## Reconciliation analysis

### Resolving K-21 vs K-33

K-21 (PDF 02 p.2) is in the rules section (سابعاً) and states a positive
*existence* claim:
> "في الصن لا يوجد الثري والفور والقهوة"
> "In Sun, **Triple, Four, and Gahwa do not exist.**"

K-33 (PDF 02 p.3) is in the *clarifying-notes* section ("بعض الملاحظات"
addressing common player misconceptions) and says:
> "في الصن لا يحق للاعب أن يعطي الثري لأنه يكتفي بالدبل فقط. ما هو ممنوع
>  ولكن ما له داعي"
> "In Sun, a player has no right to give Triple — Bel suffices. **It's
>  not forbidden, but pointless.**"

These are not contradictory once you read them in context.

K-21 establishes the **rules of the system** ("the system has no Triple
rung in Sun"). K-33 addresses **a specific player question** ("what
happens if a player verbally announces 'triple' on a Sun contract?") —
the answer is "the announcement isn't a rule violation per se, but it
has no game-mechanical effect, so Bel already gives you the maximum
Sun multiplier; calling Triple changes nothing."

The reading "Sun-Triple is forbidden by rule" (K-21) and "Sun-Triple
is not a rule violation" (K-33) coexist when interpreted as:
- **Mechanically**: there is no Triple rung in Sun. Calling "ثري" on a
  Sun round does not multiply scores by ×3. Bel-on-Sun is the terminal
  rung.
- **Etiquette**: a player who *announces* Triple on a Sun round isn't
  cheating or breaking a rule — they're just confused. The announcement
  is null; the round is treated as Sun + Bel = ×2.

L34 (PDF 07) confirms K-21's reading: the entire Sun doubling section is
titled **«نظام الدبل بالصن (دبل فقط)»** — "Sun doubling system: **Bel
only**" — listed as a single rung, not a chain. The author then
*explains why* in mathematical terms (52 raw is already enough to
beat the opponent — see L34 reasoning) which mirrors K-33's "ما له داعي"
("it has no purpose").

### Cross-validation against video 11

Video 11 explicitly corroborates the canonical reading: **«الصن ما في
قهوه ... ما في ثري ولا قهوه»**. The video also adds nuance ("بعض الجلسات
ما يلعبون... على حسب جلسه اللي تلعب فيها") — house variants in some
sessions allow Triple/Four — but this is presented as a **departure from
the standard rule**, not the rule itself.

This explains why K-33 says "not forbidden, but pointless" — author is
acknowledging that **a player may attempt to call Triple in Sun** and the
host shouldn't necessarily error out, while the **canonical engine
behavior** is that Triple has no effect in Sun.

### Reconciliation conclusion

The PDFs and video agree on the canonical rule:

| Rung | Sun? | Source |
|---|---|---|
| Bel (×2) | Yes — but *only* the trailing side, *only* when the bidder team has crossed 100 | K-22, L26, L34, L36, video 11 |
| Triple (×3) | **No** — no rung exists | K-21, L34, video 11 ("ما في ثري") |
| Four (×4) | **No** | K-21, L34, video 11 |
| Gahwa (match-win) | **No** | K-21, L34, video 11 ("الصن ما في قهوه") |

K-33's hedge ("not forbidden, just pointless") only refers to player
**etiquette/announcement**, not to the existence of the rung in the
scoring engine.

---

## Verdict

**Sun escalation chain has exactly ONE rung: Bel.**

- **Sun Triple**: **forbidden as a rule** (no engine rung; K-21, L34,
  video 11 agree). The K-33 "not forbidden" qualifier is etiquette-level
  only, not engine-level. From the perspective of `Rules.lua`,
  `Net.lua`, `Bot.lua`, and `R.ScoreRound`: a Sun contract MUST NOT
  carry `tripled = true`.

- **Sun Four**: **forbidden as a rule**. Same evidence (K-21, L34,
  video 11). Sun contract MUST NOT carry `foured = true`.

- **Sun Gahwa**: **forbidden as a rule**. Same evidence + video 11
  explicitly says **«الصن ما في قهوه»**. Sun contract MUST NOT carry
  `gahwa = true`.

Confidence: **HIGH**. Three sources (PDF 02 ruleset, PDF 07 doubling
system, video 11 beginners' explanation) agree on the canonical rule.
The only "contradiction" is a misreading of K-33's etiquette note as a
rule statement.

---

## Current code status (audit)

### Where the truncation IS already enforced

1. **`State.lua:1075-1097` — `S.ApplyDouble`** explicitly short-circuits
   Sun + Bel:
   ```lua
   if s.contract.type == K.BID_SUN then
       s.phase = K.PHASE_PLAY
       return
   end
   ```
   With a comment citing the Saudi rule:
   > "في الصن لايوجد الثري والفور والقهوة" — Sun has only Bel; no
   > Triple/Four/Gahwa.

   This is the canonical truncation gate. Once Sun + Bel is applied,
   `phase = PHASE_PLAY` and the chain ends.

2. **`Net.lua:864-917` — `N._OnDouble`** sets `wasSun = (contract.type ==
   K.BID_SUN)` and finishes the deal directly when `wasSun or not open`,
   never advancing to `PHASE_TRIPLE`.

3. **`Bot.lua:3372` — `Bot.PickDouble`**:
   ```lua
   if contract.type == K.BID_SUN then return true, false end  -- wantOpen=false
   ```
   Forces `wantOpen=false` for Sun, so the bidder's Triple window never
   opens for Sun-Bel.

4. **`Net.lua:919-967` — `_OnTriple/_OnFour/_OnGahwa` handlers** all
   guard with `if S.s.phase ~= K.PHASE_TRIPLE/FOUR/GAHWA then return end`.
   Since Sun never enters those phases, these handlers no-op for Sun.

### Where the truncation is NOT enforced (defense-in-depth gaps)

1. **`Bot.lua:3412-3505` — `Bot.PickTriple/PickFour/PickGahwa`** do **not**
   check `contract.type`. They rely entirely on the upstream phase-machine
   guarantee. If any future code path or impostor wire message ever
   invokes these pickers with a Sun contract, they will compute strength
   and may return `yes, wantOpen=true`.

2. **`Rules.lua:636-906` — `R.ScoreRound`** at lines 841-846 honors
   any combination of `contract.tripled / foured / gahwa` flags
   regardless of `contract.type`:
   ```lua
   if contract.type == K.BID_SUN then mult = mult * K.MULT_SUN end
   if     contract.gahwa   then mult = mult * K.MULT_FOUR
   elseif contract.foured  then mult = mult * K.MULT_FOUR
   elseif contract.tripled then mult = mult * K.MULT_TRIPLE
   elseif contract.doubled then mult = mult * K.MULT_BEL end
   ```
   This is what the existing tests at `test_rules.lua:562-577` exercise:
   they construct `sun(1, { doubled=true, tripled=true })` and the
   scorer multiplies by ×6 (Sun×Triple). The scorer permits the
   combination because no Sun-only multiplier filter exists at the
   scoring layer.

3. **`Constants.lua`** has no `K.SUN_MAX_RUNG` or equivalent constant
   that would let a single source-of-truth gate be wired everywhere.

The host pipeline as a whole is correct. The defense-in-depth gaps mean
that **a future refactor or a malicious/buggy client could in principle
sidestep the truncation** by injecting a `tripled=true` flag onto a Sun
contract via state manipulation (no plausible network path exists today,
since `_OnTriple` enforces phase, but reflective tools, savegame replay,
or future "rejoin from snapshot" code might).

---

## Recommended code action

**The user said "do not modify code."** What follows is the recommended
patch plan only — not applied here.

### Recommended gates (defense-in-depth)

**Patch 1 — `Bot.lua:3412` (`Bot.PickTriple`):** add at top of body, after
the contract-fetch:
```lua
if contract.type == K.BID_SUN then return false, false end
```

**Patch 2 — `Bot.lua:3443` (`Bot.PickFour`):** same one-liner.

**Patch 3 — `Bot.lua:3488` (`Bot.PickGahwa`):** same one-liner.

These match the comment at `Bot.lua:3372` (`PickDouble`'s "Sun: open is
moot (no Triple rung)") and preserve the v0.2.0 design.

**Patch 4 — `Rules.lua:836-846` (`R.ScoreRound` multiplier section):** add
a defensive normalization before the mult chain:
```lua
-- Sun has no Triple/Four/Gahwa rung (per "نظام الدبل بالصن: دبل فقط"
-- in PDF 07; K-21 / L34). Defensive normalization: strip any erroneous
-- escalation flags from a Sun contract so the scorer cannot be tricked
-- into ×6/×8/×match-win on Sun via a malformed contract table.
local effTripled = contract.tripled and contract.type ~= K.BID_SUN
local effFoured  = contract.foured  and contract.type ~= K.BID_SUN
local effGahwa   = contract.gahwa   and contract.type ~= K.BID_SUN
-- ... use effTripled/effFoured/effGahwa in the mult chain below
```
This stops the existing tests at `test_rules.lua:562-577` and `:696` from
passing — they explicitly assert Sun×Triple=×6 and Sun×Four=×8. **Those
tests encode the invariant violation we want to eliminate**, so they
need to be updated, not just left alone (see Patch 6).

**Patch 5 — `Net.lua:864-917` (`N._OnDouble`):** the existing branch
handles `wasSun` correctly. No change needed at the wire layer; the
phase-machine in `S.ApplyDouble` is the canonical gate.

### Tests to add / modify

**Test A (NEW — `test_rules.lua`)**: Sun + Bel terminal-rung assertion.
After `S.ApplyDouble(seat, true)` on a Sun contract, verify:
- `s.phase == K.PHASE_PLAY` (not `PHASE_TRIPLE`)
- `s.contract.tripled == nil` (no implicit Triple flag set)

**Test B (NEW — `test_rules.lua`)**: Bot picker rejection in Sun.
- `Bot.PickTriple(seat)` returns `(false, false)` when contract.type ==
  K.BID_SUN.
- Same for `PickFour` and `PickGahwa`.

**Test C (NEW — `test_rules.lua`)**: `R.ScoreRound` Sun-flag normalization.
Construct a malformed Sun contract with `tripled=true` (or `foured`,
`gahwa`) and verify the multiplier is `K.MULT_SUN * K.MULT_BEL` (×4),
NOT `K.MULT_SUN * K.MULT_TRIPLE` (×6) etc. This requires Patch 4 to
land first.

**Test D (MODIFY — `test_rules.lua:562-577, :696`)**: the existing tests
that assert Sun×Triple=×6 and Sun×Four=×8 encode the violation. They
should be replaced with Test C above. The existing tie-tripled/tie-foured
behavior under Sun is moot if Sun can never reach those rungs — replace
with the Hokm-equivalent assertions if not already present.

### Confidence

- **Verdict confidence (Sun has only Bel)**: HIGH. Three sources agree.
- **Code-correctness confidence (host pipeline today)**: HIGH. The
  truncation IS enforced at the phase-machine layer; no live bug.
- **Recommended-patches confidence**: HIGH. Defense-in-depth only — no
  behavior change in the canonical pipeline; closes test-construction
  back doors and protects against future refactor regressions.

### Where to gate Sun-only Bel — summary

The user prompt asks specifically about "where to gate Sun-only Bel".
The canonical gate is **already in place** at `State.lua:1085-1087`
(S.ApplyDouble short-circuits Sun → PHASE_PLAY). That gate is sufficient
for the live game. Three additional defense-in-depth gates are
recommended at `Bot.PickTriple/Four/Gahwa` (Bot.lua:3412/3443/3488) and
one at `R.ScoreRound`'s multiplier chain (Rules.lua:841-846), with
matching test changes.

---

## Source map

| Claim | Source | Confidence |
|---|---|---|
| Sun has Bel only (no Triple/Four/Gahwa) | PDF 02 K-21, PDF 07 L34, video 11 (105-119) | HIGH |
| Bel only after opp crosses 100 | PDF 02 K-22, PDF 07 L26+L36, video 11 (120-127) | HIGH |
| K-33 ("not forbidden, just pointless") = etiquette, not rules | Inferred from K-33 context vs K-21/L34 wording + video 11 ("على حسب جلسه") | HIGH |
| Some house sessions allow Triple/Four in Sun (non-canonical) | Video 11 lines 116-119 only | MEDIUM (acknowledged variant) |
| Code already truncates via phase-machine | State.lua:1075-1097 + Net.lua:864-917 + Bot.lua:3372 (read directly) | HIGH |
| Bot pickers + ScoreRound have no explicit Sun gate | Bot.lua:3412-3505 + Rules.lua:836-846 (read directly) | HIGH |
