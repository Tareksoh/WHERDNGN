# S-Score-03 — Carré-A end-to-end (Hokm and Sun)

**Audit version**: v0.10.2 (post-v0.10.0 X5 follow-through verification)
**Track**: S (scoring pipeline)
**Scope**: trace Carré of 4 Aces from `R.DetectMelds` → wire → `S.ApplyMeld`
→ `s.meldsByTeam` → `R.ScoreRound` → final game-points, in both Hokm and
Sun. Verify the v0.10.0 X5 fix landed at the apply path, and walk all 6
scenarios (plain, Sun, Bel, Sun+Bel, opposing carrés, bidder-fail).

**Files inspected**

- `C:\CLAUDE\WHEREDNGN\Rules.lua` — `R.DetectMelds` 251-321 (X5 fix
  block 285-318); `R.CompareMelds` / `meldRank` / `bestMeld` 332-384;
  `R.SumMeldValue` 534-538; `R.ScoreRound` 692-984
- `C:\CLAUDE\WHEREDNGN\State.lua` — `S.ApplyMeld` 1149-1189
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — `K.MELD_*` 91-107;
  `K.CARRE_RANKS` 109; `K.MULT_*` 68-72; `K.HAND_TOTAL_*` 54-55;
  `K.MELD_BELOTE` 107
- `C:\CLAUDE\WHEREDNGN\Net.lua` — `_OnMeld` 1390-1411; `MaybeRunBot`
  meld dispatch ~4153; AFK auto-declare ~3485; resync replay ~390-410
- `C:\CLAUDE\WHEREDNGN\tests\test_rules.lua` — Hokm Carré-A regression
  365-380; Sun Carré-A 356-363
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-State-03_applyMeld_lifecycle.md`
  (sibling audit — same finding, full cascade analysis)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-06_carre_cascade.md`
  (red-team coverage)
- `C:\CLAUDE\WHEREDNGN\CHANGELOG.md` — v0.10.0 X5/R5 entries 502-522

---

## 1. TL;DR

**Hokm Carré-A end-to-end: BROKEN — final game-points = 0, not 10.**
**Sun Carré-A end-to-end: WORKS — final game-points = 80 as canon.**

The v0.10.0 X5 fix landed at `R.DetectMelds` (Rules.lua:307-308) but
*did NOT propagate* to `S.ApplyMeld`'s parallel value-derivation block
(State.lua:1167-1184). Every meld declared in this codebase reaches
`s.meldsByTeam` only through `S.ApplyMeld` (UI declare, bot dispatch,
AFK auto-declare, resync replay, takweesh replay — see Net.lua callers
1410, 2415, 3485, 4153). For a Hokm contract with `top == "A"`, the
Sun-only branch sets `value` only when `s.contract.type == K.BID_SUN`;
the missing `else` leaves `value = nil`; line 1184 `if not value then
return end` drops the meld before `table.insert` at 1185. The X5 patch
in `R.DetectMelds` is **functionally inert** for everything except
unit tests of `R.DetectMelds` itself.

Cascade impact (per CHANGELOG v0.10.0 X5 prose AND D-RT-06):

- bidder strict-majority threshold check sees side-A short by 100 raw
  (Hokm fail/make can flip near 81 / 162);
- belote-cancellation in `R.ScoreRound` (Rules.lua:769-777, post-M5
  team-level) NEVER triggers for the Carré-A holder because the meld
  isn't in the list — silent +20 raw belote credit, ×mult;
- `R.CompareMelds` winner-takes-all (used in `R.ScoreRound`'s "made"
  branch, line 890) loses for team A because the Carré-A is not in
  `meldsByTeam.A` — if defenders have any 100-meld they win the meld
  comparison and bidder takes 0 melds.

**Score table (assuming the apply-path bug is fixed, i.e. matching the
INTENDED math):**

| Scenario | Raw meld | mult | meld gp | belote bonus | notes |
|---|---|---|---|---|---|
| Hokm Carré-A, no escalation | 100 | ×1 | 10 | n/a (Carré-A would cancel a same-team Belote) | INTENDED; ACTUAL = 0 (bug) |
| Sun Carré-A | 400 | ×2 | 80 | n/a (Belote is Hokm-only) | works correctly |
| Hokm Carré-A + Bel ×2 | 100 | ×2 | 20 | belote +20 raw NOT scaled | INTENDED; ACTUAL = 0 (bug) |
| Sun Carré-A + Bel ×4 | 400 | ×4 | 160 | n/a | works (Sun-Bel composes, ×4) |
| Hokm Carré-A + Triple ×3 | 100 | ×3 | 30 | n/a | INTENDED; ACTUAL = 0 (bug) |
| Hokm Carré-A + Four ×4 | 100 | ×4 | 40 | n/a | INTENDED; ACTUAL = 0 (bug) |

(div10 uses `(x + 5) / 10`, "5 rounds up" — Rules.lua:949.)

---

## 2. Detect-path verdict — `R.DetectMelds`

**Status**: CORRECT post-v0.10.0 X5 fix.

`Rules.lua:268-287` — verbatim verified at the actual fix block
(lines 304-318 in the live file; the audit prompt's "268-287" referred
to the pre-edit block). Live code:

```lua
304:    for rank, count in pairs(byRank) do
305:        if count == 4 and K.CARRE_RANKS[rank] then
306:            local value
307:            if rank == "A" then
308:                value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
309:            else
310:                value = K.MELD_CARRE_OTHER
311:            end
312:            local cards = {}
313:            for _, s in ipairs(K.SUITS) do cards[#cards + 1] = rank .. s end
314:            out[#out + 1] = {
315:                kind = "carre", value = value, top = rank, cards = cards, len = 4,
316:            }
317:        end
318:    end
```

Verified:

- rank == "A" AND isSun (`contract.type == K.BID_SUN`, line 253) →
  `value = K.MELD_CARRE_A_SUN = 400` ✅
- rank == "A" AND NOT isSun (Hokm) →
  `value = K.MELD_CARRE_OTHER = 100` ✅ (this is the X5 fix)
- rank ∈ {T,K,Q,J} → `value = K.MELD_CARRE_OTHER = 100` ✅
- rank == "9" → not in `K.CARRE_RANKS = {A,T,K,Q,J}` (Constants.lua:109)
  → never enters the block, no carré detected ✅

`Constants.lua:91-109` re-verified:

```
91:K.MELD_SEQ3        = 20
92:K.MELD_SEQ4        = 50
93:K.MELD_SEQ5        = 100
94:K.MELD_CARRE_OTHER = 100   -- T, K, Q, J (any contract type) AND Carré-A in Hokm
95:K.MELD_CARRE_A_SUN = 400   -- v0.10.0 R5 fix
107:K.MELD_BELOTE     = 20    -- K+Q of trump in same hand, Hokm only
109:K.CARRE_RANKS = { A=true, T=true, K=true, Q=true, J=true }   -- 9 dropped
```

Test coverage at `tests/test_rules.lua:365-380` asserts
`R.DetectMelds(hand, hokm("H"))` returns a Carré-A with
`value == K.MELD_CARRE_OTHER` and `top == "A"`. Comment at line 370
confirms the assertion was inverted in v0.10.0 (was previously
"no meld emitted").

CHANGELOG entry at `CHANGELOG.md:512-522` matches the live code.

---

## 3. Apply-path verdict — `S.ApplyMeld` (THE BUG)

**Status**: BROKEN. The X5 follow-through bug is INTACT — the apply
path drops Hokm Carré-A on the floor before storage.

**Location**: `State.lua:1167-1184`. Verbatim:

```lua
1163:    local cards = C.DecodeHand(encodedCards)
1164:    -- Mirror R.DetectMelds value derivation. Constants only define
1165:    -- MELD_CARRE_OTHER (T/Q/K/J — all 100 raw) and MELD_CARRE_A_SUN
1166:    -- (Aces in Sun only — 200 raw). 9/8/7 carrés don't score.
1167:    local value
1168:    if kind == "seq3" then value = K.MELD_SEQ3
1169:    elseif kind == "seq4" then value = K.MELD_SEQ4
1170:    elseif kind == "seq5" then value = K.MELD_SEQ5
1171:    elseif kind == "carre" then
1172:        if K.CARRE_RANKS[top] then
1173:            if top == "A" then
1174:                if s.contract and s.contract.type == K.BID_SUN then
1175:                    value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
1176:                end
1177:                -- Hokm 4-Aces: doesn't score (per Pagat-strict)
1178:            else
1179:                value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
1180:            end
1181:        end
1182:        -- 9 carrés (and 8/7) drop through with value=nil → not scored
1183:    end
1184:    if not value then return end
1185:    table.insert(s.meldsByTeam[team], {
1186:        kind = kind, value = value, suit = nsuit,
1187:        top = top, cards = cards, len = #cards, declaredBy = seat,
1188:    })
```

Stale comment at line 1177 — "Hokm 4-Aces: doesn't score (per
Pagat-strict)" — directly contradicts:

- `Constants.lua:94` docstring: "T, K, Q, J (any contract type) AND
  Carré-A in Hokm";
- `R.DetectMelds` X5 fix at `Rules.lua:308`;
- `CHANGELOG.md:512-522` X5 entry citing videos #32 line 245 + #38 line 61.

Stale comment at line 1166 — "MELD_CARRE_A_SUN (Aces in Sun only —
200 raw)" — also wrong post-v0.10.0 R5 (it's 400, not 200).

**For a Hokm Carré-A meld arriving at `S.ApplyMeld`:**

1. `kind == "carre"` → enters line 1171's `elseif`.
2. `K.CARRE_RANKS[top="A"]` → `true` → enters line 1172's `if`.
3. `top == "A"` → enters line 1173's `if`.
4. `s.contract.type == K.BID_HOKM` (NOT `K.BID_SUN`) → line 1174's
   `if` is FALSE → line 1175 doesn't execute.
5. No `else` for line 1174 → `value` stays `nil`.
6. Line 1183 closes the `elseif kind == "carre"` block.
7. Line 1184: `if not value then return end` → **return; meld dropped**.
8. `table.insert` at 1185 never runs.
9. `s.meldsByTeam[bidderTeam]` does NOT contain the Carré-A.

**Path verification — every wire/UI route lands here:**

- `Net.lua:1410` `_OnMeld` → `S.ApplyMeld` (peer broadcast)
- `Net.lua:2415` `LocalDeclareMeld` → `S.ApplyMeld` (local UI declare)
- `Net.lua:3485` AFK auto-declare → `S.ApplyMeld`
- `Net.lua:4153` `MaybeRunBot` bot dispatch → `S.ApplyMeld`
- `Net.lua:~390-410` resync replay → `_OnMeld` → `S.ApplyMeld`

Every emitter discards `m.value` (Bot.PickMelds returns it but
`MaybeRunBot` only forwards `kind/suit/top/encodedCards`); the wire
format `K.MSG_MELD` does not carry `value`. **Recomputing locally is
correct architecture; the missed `else` is the bug.**

This finding is identical to (and pre-dates) sibling audit
`B-State-03_applyMeld_lifecycle.md` Finding 1, and red-team
`D-RT-06_carre_cascade.md`. **No new fix delivered**; this audit
re-confirms the X5 follow-through bug is still present in the live
v0.10.2 codebase.

---

## 4. Score-path verdict — `R.ScoreRound` multiplier composition

**Status**: CORRECT (assuming the meld value reaches `meldsByTeam`,
which it doesn't for Hokm Carré-A — see §3).

`Rules.lua:914-924`:

```lua
914:    local mult = K.MULT_BASE                                      -- ×1
915:    if contract.type == K.BID_SUN then
916:        mult = mult * K.MULT_SUN                                  -- Sun ×2
917:        if contract.doubled then mult = mult * K.MULT_BEL end     -- Sun-Bel ×4
918:        -- intentionally ignore tripled/foured/gahwa on Sun (R2)
919:    else
920:        if     contract.gahwa   then mult = mult * K.MULT_FOUR  -- Hokm-Gahwa ×4
921:        elseif contract.foured  then mult = mult * K.MULT_FOUR  -- Hokm-Four ×4
922:        elseif contract.tripled then mult = mult * K.MULT_TRIPLE -- Hokm-Triple ×3
923:        elseif contract.doubled then mult = mult * K.MULT_BEL    -- Hokm-Bel ×2
924:        end
925:    end
```

Then at `Rules.lua:926-927`:

```lua
926:    local rawA = (cardA + meldPoints.A) * mult
927:    local rawB = (cardB + meldPoints.B) * mult
```

**Multiplier composition table verified:**

| Contract | Mult |
|---|---|
| Hokm plain | ×1 |
| Hokm + Bel | ×2 |
| Hokm + Triple | ×3 |
| Hokm + Four / Gahwa | ×4 |
| Sun plain | ×2 |
| Sun + Bel | ×4 |
| Sun + Triple/Four/Gahwa | collapses to ×4 (R2 defensive normalization, Sun-Bel max) |

**Belote +20 is multiplier-immune** — confirmed at lines 939-943:

```lua
939:    if belote == "A" then
940:        rawA = rawA + K.MELD_BELOTE   -- after mult applied
941:    elseif belote == "B" then
942:        rawB = rawB + K.MELD_BELOTE
943:    end
```

Comment at 930-932 cites Pagat verbatim "Baloot always 2 points
unaffected".

**Final divisor**: `(x + 5) / 10` floored — Rules.lua:949 ("5 rounds
up", per video #43).

**Per-scenario gp arithmetic (assuming meld lands in `meldsByTeam`):**

- **Hokm Carré-A plain**: cardA = team's tricks + last; meldPoints.A
  includes 100 from carré-A (winner-takes-all in "made" branch, sole
  meld so wins comparison). mult = ×1. Carré-A contribution to rawA
  = 100 × 1 = 100. div10 → 10 gp. ✅ (matches prompt)
- **Sun Carré-A plain**: meldPoints.A includes 400; mult = ×2. carré
  contribution = 400 × 2 = 800; div10 → 80 gp. ✅ (matches prompt)
- **Hokm Carré-A + Bel ×2**: carré = 100 × 2 = 200; div10 → 20 gp.
  ✅ (matches prompt; the formula is `100 × 2 / 10`, NOT `100 × 1 +
  20`. The prompt's "verify this is what happens, not 100×1+20"
  question — answer: it IS the multiplier formula `meldRaw × mult / 10`,
  not an additive Bel bonus.)
- **Sun Carré-A + Bel ×4**: 400 × 4 = 1600; div10 → 160 gp.
  (Note: Sun-Bel composes via line 916-917; ×2 × ×2 = ×4.)
- **Hokm Carré-A + Triple ×3**: 100 × 3 = 300; div10 → 30 gp.

For ALL Hokm cases above, current code yields 0 gp (not the figure)
because of the §3 apply-path bug.

---

## 5. Compare-path verdict — `R.CompareMelds` winner-takes-all

**Status**: CORRECT (Pagat-strict winner-takes-all working; loser
melds zeroed in the "made" branch — but `R.CompareMelds` is bypassed
in fail / take / sweep branches per §6).

`Rules.lua:332-384`. `meldRank` returns `1000 + value + rankBonus`
for carrés (line 352) and `lenScore + topIdx + trumpBonus` for
sequences (line 361). `bestMeld` picks the max-by-meldRank from each
team's list. `R.CompareMelds` returns "A" / "B" / "tie".

Used in `R.ScoreRound`:

- **Threshold check** (Rules.lua:791-797): `meldVerdict =
  R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)`; only the
  meld-winner team's `meldA` / `meldB` is added to that side's
  `bidderTotal` / `oppTotal` for the bidder strict-majority
  comparison. Loser team's melds are 0 for the threshold, even if
  the loser team also has melds. ✅ (confirmed lines 792-793).
- **"Made" branch meld awarding** (Rules.lua:888-892): same
  `R.CompareMelds`, loser team gets 0 meldPoints. ✅

**Two opposing carrés (scenario 5):**

Bidder team has Carré-A; defender has Carré-T. Both are 100 raw.
meldRank values (Hokm contract, trump=H, neither carré is in trump
because all four cards are needed — but for tie-break the top-card
trick rank within trump-suit context applies):

- Carré-A: `1000 + 100 + (TrickRank("AS", contract) * 0.01)`
  — A is rank 8 in Hokm, so bonus ~0.08, total ~1100.08
- Carré-T: `1000 + 100 + (TrickRank("TS", contract) * 0.01)`
  — T is rank 6 (or whatever K.RANK_INDEX says), bonus ~0.06,
  total ~1100.06

Carré-A wins on rankBonus tie-break. `R.CompareMelds` returns "A"
→ bidder team gets meldA = 100; defender team gets meldPoints.B = 0
(their Carré-T is voided). **Loser-team melds zeroed: VERIFIED.**

This matches the prompt's "Pagat-strict says highest-value carré
wins, all losing-team's melds void" requirement.

**HOWEVER**, in the live v0.10.2 codebase, because the Carré-A is
silently dropped at `S.ApplyMeld` (§3), the bidder team's
`meldsByTeam.A = {}` empty. `R.CompareMelds` then sees A empty,
B with Carré-T → returns "B" → defender team gets their 100 raw
× mult (10 gp Hokm plain), bidder gets 0. **Inverted outcome.**

If bidder team has additional melds (e.g. a seq3 of trump), the
Carré-A drop is partially masked because they still have SOME
meld for comparison; but they lose the carré value (100 raw, 10 gp
Hokm plain) AND lose tie-break vs an opposing carré.

---

## 6. Fail-path retention verdict — "مشروعي لي ومشروعك لك"

**Status**: CORRECT in formula (each team retains its own melds
on fail/take), BROKEN in practice for Hokm Carré-A bidder (§3 — the
meld is missing from `meldsByTeam` so retention has nothing to retain).

`Rules.lua:854-871` (fail branch):

```lua
854:    elseif outcome_kind == "fail" then
...
868:        cardA = (oppTeam == "A") and handTotal or 0
869:        cardB = (oppTeam == "B") and handTotal or 0
870:        meldPoints.A = meldA   ← bidder retains
871:        meldPoints.B = meldB   ← defender retains
```

`Rules.lua:872-884` (take / doubled-tie inversion):

```lua
872:    elseif outcome_kind == "take" then
...
881:        cardA = (bidderTeam == "A") and handTotal or 0
882:        cardB = (bidderTeam == "B") and handTotal or 0
883:        meldPoints.A = meldA
884:        meldPoints.B = meldB
```

Both fail and take preserve EACH team's full `meldA` / `meldB`
(no winner-takes-all here — that's only the "made" branch).
This implements v0.4.3 "مشروعي لي ومشروعك لك". The leading
comment at lines 856-867 cites the rule and the user-reported
Hokm-Bel quarte-loss bug as the regression that motivated the
fix.

**Scenario 6 walkthrough (intended):**

- Hokm contract, bidder team A holds Carré-A.
- Bidder fails 64/162. `outcome_kind = "fail"` (line 841 default).
- `cardA = 0`, `cardB = handTotal = 162`.
- `meldPoints.A = meldA` (= 100 if Carré-A correctly stored).
- `meldPoints.B = meldB` (= 0 if defender no melds).
- `mult = 1` (Hokm plain).
- `rawA = (0 + 100) * 1 = 100`; div10 → **10 gp** to bidder.
- `rawB = (162 + 0) * 1 = 162`; div10 → **16 gp** (164/10 → wait,
  162+5=167 → floor(16.7)=16) to defender. ✅ matches prompt.

Net: defender +16 gp + own melds; bidder +10 gp meld + 0 cards.

**ACTUAL with the §3 bug**: bidder Carré-A is missing from
`meldsByTeam.A`. `meldA = 0`. `meldPoints.A = 0`. `rawA = 0`. Bidder
gets 0 gp, not 10. **The retention rule fires correctly on whatever
IS in `meldsByTeam.A` — but there's nothing there.**

---

## 7. Bugs found

### Bug S-Score-03-1 — `S.ApplyMeld` Hokm Carré-A drop (X5 follow-through)

**Severity**: HIGH (silent meld loss; inverts Hokm-Carré-A scoring;
silent +20 belote over-credit; flips meld winner-takes-all; flips
bidder strict-majority threshold near margins)

**Status**: confirmed live in v0.10.2; identical to sibling
B-State-03 Finding 1 + D-RT-06 Finding 1.

**Location**: `State.lua:1167-1184`.

**Cascade** (verbatim from CHANGELOG v0.10.0 X5 prose; all four
cascade legs are reachable via the apply-path):

1. bidder strict-majority threshold check sees side-A short by 100
   raw (~10 gp). At thresholds (e.g. 81/162 in Hokm), this can flip
   contract-made/contract-failed outcome.
2. `R.CompareMelds` winner-takes-all (Rules.lua:890): if the bidder
   team's only meld was the Carré-A, the now-empty `meldsByTeam.A`
   flips the comparison — defenders' lesser melds win, bidder gets 0
   meldPoints AND a defender carré (if any) is awarded full value.
3. Belote-cancel (Rules.lua:769-777, post-v0.9.0 M5 team-level): the
   100-raw Carré-A would normally cancel a same-team Belote (K+Q of
   trump in same hand). With Carré-A missing from the list, Belote
   stays uncancelled → silent +20 raw, scaled by `mult` (×1 = +2 gp;
   ×2 = +4 gp; ×4 = +8 gp; etc. — note: actually the +20 is added
   AFTER mult per lines 939-943, so it's always +2 gp).
4. State desync on resync (manifest as B-State-03 Finding 10):
   if the host's `meldsByTeam.A` somehow contained Carré-A (it
   doesn't post-bug, because the host runs `S.ApplyMeld` too — but
   if a fix landed only at `R.DetectMelds` and the host stored it
   via a different path), the resync replay would transmit the
   wire frame to the rejoiner, who runs `S.ApplyMeld`, drops it,
   ends up with a different `meldsByTeam` than the host. Currently
   moot because both sides are equally broken.

**The minimum fix** (mirrors `R.DetectMelds`):

```lua
            if top == "A" then
                value = (s.contract and s.contract.type == K.BID_SUN)
                        and K.MELD_CARRE_A_SUN
                        or K.MELD_CARRE_OTHER
            else
                value = K.MELD_CARRE_OTHER
            end
```

and remove the stale comment at 1177 + update comment at 1166 (200
raw → 400 raw post-R5).

### Bug S-Score-03-2 — Stale doc comment at State.lua:1166

**Severity**: LOW (doc-drift; misleads reviewers)

**Location**: `State.lua:1166` — "(Aces in Sun only — 200 raw)".

`K.MELD_CARRE_A_SUN` is 400 raw post-v0.10.0 R5 (Constants.lua:95).
The comment was written in the v0.4.x era when the value was 200.
Aligned doc-fix should accompany the S-Score-03-1 fix.

### Bug S-Score-03-3 — Stale doc comment at State.lua:1177

**Severity**: HIGH (root-cause doc; if this comment had been correct
at v0.10.0 X5 review time, the apply-path duplicate would have been
spotted in the same audit)

**Location**: `State.lua:1177` — "Hokm 4-Aces: doesn't score (per
Pagat-strict)".

Contradicts:
- `Constants.lua:94` ("T, K, Q, J ... AND Carré-A in Hokm");
- `Rules.lua:285-298` X5 fix block prose;
- `CHANGELOG.md:512-522` X5 entry.

To remove together with S-Score-03-1.

### Bug S-Score-03-4 — Architectural: value-derivation duplicated across `R.DetectMelds` and `S.ApplyMeld`

**Severity**: HIGH (drift risk; X5 itself is a manifestation; will
recur for any future K.MELD_* tweak unless extracted)

**Locations**: Rules.lua:273-279, 304-318 (DetectMelds);
State.lua:1167-1183 (ApplyMeld).

The two blocks must compute identical `value` for identical
`(kind, top, contract.type)` tuples. Right move: extract a
single helper, e.g. `K.MeldValueFor(kind, top, contract)` (or
`R.MeldValue`), called from both sites. Constants are already
single-source (K.MELD_*); the derivation logic also should be.

---

## Notes for the swarm

- **No code modified**; this is a read-only audit per the prompt.
- All findings independently re-confirmed against the live
  v0.10.2 codebase. Sibling audits B-State-03, D-RT-06, and the
  prior B-Rules-03 detect-path audit all converge on the same
  apply-path drop. **This is the same bug, surfaced four times.**
  v0.10.0 X5 patched DetectMelds; the apply-path duplicate has been
  flagged by multiple agents but not yet fixed in v0.10.2.
- `R.ScoreRound`'s formula (multiplier composition, fail-branch
  retention, belote-cancellation, winner-takes-all in made branch,
  belote multiplier-immunity) is structurally correct. Every
  failure mode in this audit traces to the §3 ApplyMeld drop, NOT
  to ScoreRound.
- Test coverage gap: `tests/test_rules.lua` covers `R.DetectMelds`'
  Carré-A in Hokm (line 365-380) but no test exercises the path
  `S.ApplyMeld → meldsByTeam` for Hokm Carré-A. B-State-03
  Recommendations §1 lists the 4 missing tests; F-Test-01 likely
  covers this gap.

**End of audit S-Score-03.**
