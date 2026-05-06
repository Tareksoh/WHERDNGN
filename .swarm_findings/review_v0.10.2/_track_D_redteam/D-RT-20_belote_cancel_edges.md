# D-RT-20 — Belote cancellation edge cases (M5 + X5 + M1 interaction)

**Track**: D — Red-team
**Version**: v0.10.2 review
**Scope**: Verify the M5 v0.9.0 team-level Belote-cancel fix still
holds after v0.10.0 X5 (Hokm Carré-A meld emit) and v0.10.1 M1
(Qaid offender-meld forfeit).

**Sites inspected**:
- `C:\CLAUDE\WHEREDNGN\Rules.lua` `R.ScoreRound` lines 684-746
- `C:\CLAUDE\WHEREDNGN\Net.lua` `N.HostResolveTakweesh` lines 2127-2270
- `C:\CLAUDE\WHEREDNGN\Net.lua` `N.HostResolveSWA` invalid-claim
  branch lines 2920-2987
- `C:\CLAUDE\WHEREDNGN\Rules.lua` `R.DetectMelds` line 277 (X5)
- `C:\CLAUDE\WHEREDNGN\UI.lua` lines 1511-3152 (Belote banner)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\08_m5_belote_team.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X5_meld_coverage.md`

---

## Verdict summary

| # | Question | Verdict |
|---|---|---|
| 1 | M5 team-level cancel in `R.ScoreRound` | OK |
| 2 | `declaredBy == nil` robust in `R.ScoreRound` | OK (predicate dropped) |
| 3 | M1 Qaid forfeit ↔ Belote cancel ordering | OK in current code (cancel uses pre-zero meld lists) — **but only by accident**. Documented intent vs. code-comment language is misaligned; flag for clarification. |
| 4 | X5 Hokm Carré-A now cancels Belote | INTENDED per sources, but **DEAD in production** — `S.ApplyMeld` (State.lua:1167-1184) still drops the meld at the storage layer, so `meldsByTeam` never contains a Hokm Carré-A entry. The cancel predicate has nothing to iterate. Cross-ref D-RT-06 Issue 1. |
| 5 | Multi-meld cancel idempotence (single break) | OK |
| 6 | Sun gating: no Belote in Sun | OK at all three sites |
| 7 | UI notification of cancellation | **MISSING** — silent. |
| 8 | Net.lua sites parity with Rules.lua M5 fix | **DIVERGENT — BUG.** Both Net.lua sites still use the pre-v0.9.0 player-only predicate. |

---

## 1. M5 team-level cancel — `R.ScoreRound` (OK)

`Rules.lua:738-746`:

```lua
if belote and kWho then
    local list = (meldsByTeam and meldsByTeam[belote]) or {}
    for _, m in ipairs(list) do
        if (m.value or 0) >= 100 then
            belote = nil
            break
        end
    end
end
```

`list` is keyed off `meldsByTeam[belote]` — the team that holds
Belote post-sweep-override. Iteration is intrinsically team-scoped
(no per-player gate). Any team-mate's ≥100 meld cancels. Matches
v0.9.0 audit `08_m5_belote_team.md`. ✅

## 2. `declaredBy == nil` robustness — `R.ScoreRound` (OK)

The v0.9.0 predicate dropped `m.declaredBy == kWho` entirely. A
meld with missing/nil `declaredBy` and `value >= 100` correctly
cancels Belote. Defensive `(m.value or 0)` also handles missing
value. ✅

## 3. v0.10.1 M1 Qaid forfeit ↔ Belote cancel ordering

**Concern**: when offender's melds are zeroed by Qaid, do the
zeroed melds still count toward Belote cancellation?

**Trace** (`Net.lua:2192-2251`):

```lua
2192  local meldA = R.SumMeldValue(S.s.meldsByTeam.A)
2193  local meldB = R.SumMeldValue(S.s.meldsByTeam.B)
...
2216  local offenderTeam = (winnerTeam == "A") and "B" or "A"
2217  local mpA = (offenderTeam == "A") and 0 or meldA
2218  local mpB = (offenderTeam == "B") and 0 or meldB
...
2223  local belote
2224  if c.type == K.BID_HOKM and c.trump then
       ...
2238    local list = (S.s.meldsByTeam and S.s.meldsByTeam[belote]) or {}
2239    for _, m in ipairs(list) do
2240      if m.declaredBy == kWho and (m.value or 0) >= 100 then
2241        belote = nil
2242        break
```

`mpA/mpB` are zeroed for scoring purposes, but the Belote scan
reads `S.s.meldsByTeam[belote]` — the **unmodified state list,
which still contains the offender's declared melds.** So if the
offender was the K+Q holder AND held a ≥100 meld, the Belote
cancel still fires even though the underlying meld no longer
scores points.

**Question**: is this the intended semantic?

**Interpretation 1 (current behavior)**: "the meld existed at the
table" — its presence subsumes the +20 even though the offender
cannot score it. Belote is cancelled.

**Interpretation 2**: "the meld was forfeited, treat it as if not
declared" — offender keeps the +20 because there's no scoring
≥100 meld on their side anymore.

**Source check**: PDF 02 K-04 ("the buyer's meld is forfeited —
kept by neither side, just lost") and Source H-36.12
("zeroed/forfeited") describe the **scoring** treatment. They do
not address the Belote-cancel hypothetical, because Saudi rule
"≥100 subsumes Belote" (per "ماهو البلوت في لعبة البلوت") is a
Belote-side rule and the Qaid context is rare. No source crosses
the two.

**Recommendation**: defensible either way. **Current behavior
(Interp 1) is the more conservative reading** — the offender
already loses their ≥100 meld scoring; also losing the +20 Belote
is consistent with "Qaid is severe." But this is **not
explicitly intended by code comments** — neither line 2196-2215
("Saudi Qaid rule (offender melds forfeited)") nor the Belote
block at 2220-2245 acknowledges the interaction. **Flag**:
document intent in a comment so future readers don't "fix" it
the wrong way. Same flag applies to `HostResolveSWA` invalid
branch.

## 4. v0.10.0 X5 Carré-A in Hokm now cancels Belote (INTENDED but DEAD IN PRODUCTION)

`Rules.lua:277`:

```lua
value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
```

Pre-v0.10.0: Hokm Carré-A had `value = nil`, meld was silently
dropped, never appeared in `meldsByTeam`, Belote-cancel never saw
it. **Holder of K+Q-trump and Carré-A scored both: +100 nq for
Carré-A (after fix) AND +20 Belote.**

Post-v0.10.0 IN `R.ScoreRound`: Carré-A in Hokm = 100 raw,
nominally lands in `meldsByTeam`, `>= 100` predicate hits, Belote
cancelled. **Intended: Carré-A scores 100 raw → 10 nq, Belote
+20 vanishes.**

**Source verdict** (per
`xref_X5_meld_coverage.md` line 23 and Source I §A11 / Source L
L22-L24): Saudi rule is "≥100 meld subsumes Belote." Carré-A in
Hokm is a 100-meld per video #32 L243-245 + #38 L59-61. **Yes,
this is the intended behavior** — the X5 fix correctly aligns
the meld-emit and the cancel rule cascades through.

### CRITICAL: cascade is DEAD because `S.ApplyMeld` drops Hokm Carré-A

Cross-reference: D-RT-06 Issue 1 (already-filed HIGH bug). The
X5 fix only patched `R.DetectMelds` (Rules.lua:240-242). The
**parallel value-derivation in `S.ApplyMeld`** at `State.lua:1167-1184`
was NOT updated:

```lua
1167  local value
1168  if kind == "seq3" then value = K.MELD_SEQ3
1169  elseif kind == "seq4" then value = K.MELD_SEQ4
1170  elseif kind == "seq5" then value = K.MELD_SEQ5
1171  elseif kind == "carre" then
1172      if K.CARRE_RANKS[top] then
1173          if top == "A" then
1174              if s.contract and s.contract.type == K.BID_SUN then
1175                  value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
1176              end
1177              -- Hokm 4-Aces: doesn't score (per Pagat-strict)  ← STALE
1178          else
1179              value = K.MELD_CARRE_OTHER
1180          end
1181      end
1182  end
1183  if not value then return end                   -- ← drops the meld silently
1184  table.insert(s.meldsByTeam[team], { ... })
```

The "doesn't score (per Pagat-strict)" comment is a v0.10.0-pre
artifact. Post-X5 the rule changed; the comment didn't. Every
wire-arrived meld declaration funnels through `S.ApplyMeld`
(per `Net._OnMeld` L1372, `N.LocalDeclareMeld` L2377, AFK auto
L3436, `MaybeRunBot` L4079, replay L407). So Hokm Carré-A NEVER
reaches `meldsByTeam` in any production code path — bot, human,
host, peer, or replay.

**Effect on the X5 → M5 Belote-cancel cascade**: the Belote
cancellation predicate at Rules.lua:738-746 has nothing to
iterate. `meldsByTeam[belote]` does not contain a Hokm Carré-A
entry. The +20 Belote is NOT cancelled in any real round.

The X5/M5 cascade is **intended** but **functionally inert**
until D-RT-06 Issue 1 is fixed (`S.ApplyMeld` patched to mirror
the post-X5 `R.DetectMelds`).

**Test scenario** (predicted, against current code):
- Bidder seat with K+Q of trump and four Aces in Hokm.
- Pre-v0.10.0: bidder gets +20 Belote, no Carré-A meld emitted.
- Post-v0.10.0 / v0.10.1 / v0.10.2 IN PRODUCTION: bidder still
  gets +20 Belote (no `meldsByTeam` entry → no cancel) AND no
  Carré-A score (S.ApplyMeld drops it). The visible behavior is
  **identical to pre-v0.10.0** despite the X5 changelog claim.
- Post-v0.10.0 IN UNIT TEST (calling R.ScoreRound directly with
  a hand-built `meldsByTeam` containing the Carré-A): cancel
  fires, Belote = nil. This is what `test_rules.lua:658-668`
  asserts — and it passes — but it bypasses the wire path that
  is actually broken.

✅ Intended at the rule layer. ❌ Wire path broken (D-RT-06).
⚠️ **Test pin recommended**: add an end-to-end test that calls
`S.ApplyMeld(seat, "carre", "", "A", encodedAces)` in a Hokm
contract, then `R.ScoreRound`, and asserts `belote == nil`. The
existing test at `test_rules.lua:658-668` does NOT cover this —
it injects the meld directly into the `meldsByTeam` argument,
bypassing `S.ApplyMeld`.

## 5. Multi-meld cancel idempotence (OK)

`break` statement at L743 ensures the loop exits on first ≥100
hit. `belote = nil` is a single boolean assignment; further
iterations would no-op anyway. No double-cancel possible. Holder
with quinte AND Carré-A: cancel fires once (sets nil, breaks). ✅

## 6. Sun gating (OK at all three sites)

| Site | Gate |
|---|---|
| `Rules.lua:694` | `if contract.type == K.BID_HOKM and contract.trump then` |
| `Net.lua:2224` (Takweesh) | `if c.type == K.BID_HOKM and c.trump then` |
| `Net.lua:2956` (SWA invalid) | `if c.type == K.BID_HOKM and c.trump then` |

All three early-out for Sun. No Belote in Sun anywhere. ✅

## 7. UI notification of cancellation (MISSING)

`UI.lua:3150-3152`:

```lua
-- Belote line (if applicable)
if r.belote then
    banner.belote:SetText(("Belote (K+Q ♥): %s +20 raw"):format(teamLabel(r.belote)))
```

**The banner shows Belote ONLY when `r.belote ~= nil`.** When
cancelled (set to nil per the M5 path), the line is silent —
`banner.belote:SetText("")` clears it (L2959, L2993).

**User-visible signal**: zero. A K+Q-trump holder who also has a
quinte/quarte never sees a "Belote cancelled by 100-meld"
acknowledgement. The +20 quietly disappears from their
breakdown. From the player's perspective, this looks identical to
"the host forgot to credit my Belote."

**Recommendation**: add a one-line note when `r.beloteCancelled
== true` (would require `R.ScoreRound` to return that flag
alongside `r.belote = nil`). Cheap UX win, big trust improvement.
The cancel rule is real Saudi rule but obscure; players will
challenge it if the UI is silent.

**Severity**: LOW (cosmetic / UX), but a high-value fix relative
to its cost.

## 8. Net.lua parity with `R.ScoreRound` M5 v0.9.0 fix (DIVERGENT — BUG)

**This is the primary finding of this red-team pass.**

`R.ScoreRound` (Rules.lua:740-744) — v0.9.0 M5 corrected:

```lua
for _, m in ipairs(list) do
    if (m.value or 0) >= 100 then
        belote = nil
```

`HostResolveTakweesh` (Net.lua:2239-2244) — **still uses the
pre-v0.9.0 player-gated predicate**:

```lua
for _, m in ipairs(list) do
    if m.declaredBy == kWho and (m.value or 0) >= 100 then
        belote = nil
```

`HostResolveSWA` invalid branch (Net.lua:2971-2976) — **same
pre-v0.9.0 player-gated predicate**:

```lua
for _, m in ipairs(list) do
    if m.declaredBy == kWho and (m.value or 0) >= 100 then
        beloteOwner = nil
```

### Impact

The M5 v0.9.0 fix corrected the cancellation predicate to
**team-scoped** ("any team-mate's ≥100 meld cancels"). This
correction was applied at `R.ScoreRound` only. The two Net.lua
sites — which compute Belote independently from `R.ScoreRound`
during early-termination paths — were NOT updated.

**Concrete scenario where the bug surfaces:**

- Hokm contract, ×2 (Bel'd) for clarity.
- Seat 1 holds K-of-trump and Q-of-trump (would-be Belote +20).
- Seat 3 (seat-1's partner) declared a quinte (100 raw). Seat 1
  has no ≥100 meld personally.
- An invalid play is caught → Takweesh fires.

Path 1 — **what happens in `R.ScoreRound`** (e.g. regular fail
branch in normal round-end): partner's quinte cancels Belote.
Final Belote contribution = 0. ✅ Per Saudi rule.

Path 2 — **what happens in `HostResolveTakweesh`** (Net.lua:2239):
the predicate `m.declaredBy == kWho` skips partner's quinte
(declaredBy ≠ K-holder). Cancellation does NOT fire. Belote =
+20 raw applied. ❌ Pre-v0.9.0 buggy behavior.

Same exact bug in `HostResolveSWA` invalid branch.

### Two related sub-bugs in the Net.lua sites

**(a) `declaredBy == nil` regression**: legacy meld objects with
nil `declaredBy` ALSO fail the predicate. This is exactly the
legacy-data-shape robustness the v0.9.0 fix was meant to provide,
and Net.lua never received it.

**(b) `kWho = kWho or p.seat` first-seen vs. last-seen**: the
Net.lua scans (lines 2229, 2961) use `kWho = kWho or p.seat`
(first-seen retention), while `R.ScoreRound` uses `kWho = p.seat`
(last-seen, line 699). For K+Q-of-trump this is benign — there's
exactly one of each card in the deck, so one play = one seat.
But it's a divergence and worth noting for code-review parity
even if no behavioral effect today.

### Recommendation

**HIGH PRIORITY**: align the two Net.lua sites with the v0.9.0
M5 fix. Replace lines 2239-2244 and 2971-2976 with the
team-scoped predicate from Rules.lua:740-744. Drop the
`m.declaredBy == kWho` clause. Optionally factor a helper
`R.BeloteAfterCancel(meldsByTeam, kWho)` and call it from all
three sites — single source of truth for the M5 rule.

**Test pin recommended**: add a test under `tests/test_net.lua`
(or harness equivalent) that drives the Takweesh and invalid-SWA
paths with a partner-quinte + K+Q-trump-holder setup and
asserts no Belote +20 is added. Today's test suite (per
audit_v0.9.0/08_m5_belote_team.md) only covers the
`R.ScoreRound` site.

---

## Summary table

| Finding | Severity | Site | Action |
|---|---|---|---|
| Net.lua Takweesh & SWA-invalid still use pre-v0.9.0 player-gated cancel | **HIGH** | `Net.lua:2240`, `Net.lua:2972` | Apply M5 fix; add test pin. |
| Hokm Carré-A → Belote cancel cascade dead in production (`S.ApplyMeld` drops the meld at storage) | **HIGH** (cross-ref D-RT-06 Issue 1) | `State.lua:1167-1184` | Mirror post-X5 `R.DetectMelds` value-derivation in `S.ApplyMeld`; without this fix, the X5 → M5 cascade described in the X5 changelog cannot fire in any real round. |
| Belote-cancel UI silence | LOW | `UI.lua:3150-3152` | Add `r.beloteCancelled` flag + cancel banner line. |
| M1 forfeit ↔ Belote cancel intent undocumented | INFO | `Net.lua:2216-2245`, `Net.lua:2940-2977` | Add comment clarifying that Qaid-zeroed melds DO still trigger Belote cancel. |
| `kWho = kWho or p.seat` first-seen vs. `R.ScoreRound`'s last-seen | INFO | `Net.lua:2229`, `Net.lua:2961` | Cosmetic parity fix. |
| Hokm Carré-A cancels Belote (X5/M5 cascade) at the rule layer | OK (intended) at Rules.lua, but inert in production until D-RT-06 Issue 1 is fixed | `Rules.lua:738-746` | Add explicit end-to-end test (`S.ApplyMeld` → `R.ScoreRound`) for the K+Q + Carré-A combo. |

## Recommendation (overall)

The principal regression is **Net.lua parity drift**: the two
Qaid-context Belote scans never received the v0.9.0 M5 fix and
silently retain the player-gated predicate. Two test-coverage
gaps follow from this — Net.lua's Takweesh and invalid-SWA paths
have no Belote-cancel test, so the regression is invisible to
the harness. Recommend a single shared helper and test pins at
both Net.lua sites.

Secondary improvements: (1) UI cancellation banner, (2) intent
comment for the Qaid-vs-Belote-cancel ordering question.

The v0.10.0 X5 cascade (Hokm Carré-A → ≥100 → Belote cancel) is
intended and correctly wired **in `Rules.lua`** (R.DetectMelds
+ R.ScoreRound). It is currently **dead in production** because
the parallel `S.ApplyMeld` value-derivation in `State.lua` still
drops Hokm Carré-A (D-RT-06 Issue 1). After both fixes — Net.lua
parity AND `S.ApplyMeld` — the cascade will be correctly wired
in all four sites (`R.ScoreRound`, `HostResolveTakweesh`,
`HostResolveSWA-invalid`, AND the storage layer that feeds them).

## EV / scoring impact (quantified)

For a Hokm round where the K+Q-of-trump holder ALSO holds a ≥100
meld declared by their PARTNER (this is the M5-fix's motivating
case — same-player → covered already by the legacy predicate):

| Path | Pre-v0.9.0 | Post-v0.9.0 (`R.ScoreRound` only) | Today (Net.lua sites) |
|---|---|---|---|
| Normal round-end | Belote scored +20 (BUG) | Belote = nil ✅ | Belote = nil ✅ (uses `R.ScoreRound`) |
| Takweesh resolution | Belote scored +20 (BUG) | n/a (uses Net.lua) | Belote scored +20 ❌ |
| Invalid-SWA resolution | Belote scored +20 (BUG) | n/a (uses Net.lua) | Belote scored +20 ❌ |

**Per-round EV swing**: +20 raw incorrectly added to the K+Q
holder's team in the Takweesh / invalid-SWA paths. With escalation:
20 × ×2 (Bel) = 40 raw = 4 nq; 20 × ×3 (Triple) = 60 raw = 6 nq;
20 × ×4 (Four) = 80 raw = 8 nq. **Belote is multiplier-immune
per CLAUDE.md and `Rules.lua` design** — the +20 is added AFTER
multiplier (Net.lua:2250-2251 confirms `rawA = rawA +
K.MELD_BELOTE` after `rawA = (cardA + mpA) * mult`). So the EV
swing is a flat **+2 nq per affected round** in those two paths,
regardless of multiplier.

**Frequency estimate**: K+Q-of-trump is held in same hand in
roughly 1 in 16 deals (≈6.25% — both come from trump suit, ~3
cards per player on average). Of those, the partner holding a
≥100 meld (quinte / Carré-T/K/Q/J / Carré-A-Sun) is rarer —
maybe 5-10% of the 6%. So ≈0.3-0.6% of all dealt rounds. Of
those, the round must end via Takweesh or invalid-SWA (rare;
maybe 1-2% of rounds). Net: **≈0.003-0.012% of rounds carry
this bug** — a vanishingly small per-game effect, but a clear
correctness issue and an obvious symptom-of-divergence that the
test harness misses.

The X5 → M5 cascade (Hokm Carré-A → cancel) increases the
frequency of cancellations in `R.ScoreRound` once D-RT-06 Issue
1 is fixed (Hokm-K+Q-holder also-holding-4A is rarer than
partner-quinte but lifts the affected fraction another tick).
