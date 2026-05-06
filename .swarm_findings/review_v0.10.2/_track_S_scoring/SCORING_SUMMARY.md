# SCORING_SUMMARY.md — synthesis of the 10-agent scoring sub-audit

**Trigger:** user reported "I believe something is wrong with the scoring."
**Scope:** 10 read-only agents (S-Score-01 through S-Score-10) traced
end-to-end scoring pipelines that per-function audits couldn't see.
**Verdict:** **scoring is broadly correct, but two HIGH bugs cause silent
corruption** plus several MED defensive gaps.

---

## TL;DR

The user's "scoring is wrong" intuition is **correct**. Two HIGH bugs
are responsible:

1. **🔴 X5 half-fix at `State.lua:1167-1184`** — every Hokm-Carré-A
   silently drops to 0 gp (should be 10 gp), triggers cascading Belote
   over-credit, inverts meld comparison, can flip strict-majority
   threshold near 81/162. Triple-confirmed by S-Score-03, S-Score-10,
   and prior B-State-03 / D-RT-06 / G-Logic-01. **1-line fix.**

2. **🔴 Reverse Al-Kaboot type-blind at `Rules.lua:742-745` + `847-853`** —
   defender sweep awards 250/220 raw instead of canonical +88. Over-pays
   defender by ~16 gp/round (Hokm) or ~35 gp/round (Sun). Constant
   `K.AL_KABOOT_REVERSE` doesn't exist yet.

Both are already in synthesis §4.2 backlog but neither has been applied.
**These are the v0.10.5 ship-blocker candidates.**

---

## Verified CORRECT (5 of 10 areas — no bugs)

| Area | Agent | Notes |
|---|---|---|
| Hokm happy-path scoring | S-Score-01 | Belote multiplier-immunity, fail-branch retention, div10 rounding all match video #43 verbatim |
| Sun happy-path scoring | S-Score-02 | Sun-Bel COMPOUNDS to ×4, not collapses (`Rules.lua:914-918`); Carré-A=400 math ✓ at score level |
| Belote multiplier-immunity | S-Score-04 | All 4 discriminating tests pass: ×2→22 gp, ×3→32 gp, ×4→42 gp (NOT 24/36/48 bug-paths) |
| Last-trick +10 | S-Score-05 | Single-application, multiplier-aware, attributed to trick-winner team (NOT bidder) |
| Strict-majority + rule 4-10 | S-Score-09 | `bidderTotal > oppTotal` (no off-by-one); 4-10 inversion correct for `doubled`/`four`; div10 5-up rounding correct |

---

## 🔴 HIGH bugs (production impact)

### HIGH-1: X5 half-fix — Hokm Carré-A drop at the apply path

**Site:** `State.lua:1167-1184` (in `S.ApplyMeld`)

**Bug:** v0.10.0's X5 fix patched `R.DetectMelds` (the detect path) but
not `S.ApplyMeld` (the storage path). Every meld emitter routes through
`S.ApplyMeld` (`Net.lua:1410, 2415, 3485, 4153, 407`), passing
`(kind, suit, top)` rather than the meld's `value`. ApplyMeld
re-derives the value via its own broken block — for Hokm-Carré-A,
`value` stays `nil`, line 1184 `if not value then return end` discards
the meld before insert.

**Impact (per S-Score-10):**
- Hokm Carré-A scores **0 gp** instead of 10 gp
- Cascade: absent ≥100 meld leaves Belote uncancelled (`Rules.lua:769-777`) → silent **+20 raw over-credit** to bidder team
- `R.CompareMelds` winner-takes-all flips: defender wins meld comparison if they hold any ≥100 meld
- Strict-majority threshold can flip near 81/162 (lost 10 gp from melds)

**Trigger probability:** ~1.92% of rounds (≈1 in 50). Real, not edge.

**Fix shape (1 line):**
```lua
-- State.lua:1174 — add the missing else
if contract.type == K.BID_SUN then
    value = K.MELD_CARRE_A_SUN
elseif contract.type == K.BID_HOKM then  -- ADD THIS
    value = K.MELD_CARRE_OTHER             -- ADD THIS
end                                         -- ADD THIS
```

**Also fix:** stale comments at `State.lua:1166` (says "200 raw") and
`State.lua:1177` (says "Hokm 4-Aces: doesn't score" — opposite of the
actual rule).

**Architectural improvement (optional, v0.10.5+):** extract a
`K.MeldValueFor(kind, top, contract)` helper so `R.DetectMelds` and
`S.ApplyMeld` share one value-derivation. Eliminates the duplicated
logic that caused the X5 half-fix.

**Triangulation:** S-Score-03, S-Score-10 (this audit) + B-State-03 F1 +
D-RT-06 + G-Logic-01 §7.3 + REVIEW_v0.10.2_validation.md (5 prior
audits, none had been picked up).

---

### HIGH-2: Reverse Al-Kaboot type-blind — defender sweep over-paid

**Sites:** `Rules.lua:742-745` (sweep detection) + `Rules.lua:847-853`
(bonus award)

**Bug:** Both sites award `K.AL_KABOOT_HOKM=250` / `K.AL_KABOOT_SUN=220`
to whichever team sweeps all 8 tricks — regardless of whether they're
bidder or defender. Per video #16 (canonical Saudi source for Reverse
Al-Kaboot / الكبوت المقلوب), defender sweep should be:

- **+88 raw** (not 250/220)
- **Gated** on `tricks[1].plays[1].seat == contract.bidder` (the
  bidder must have led trick 1 — which makes the reverse-sweep
  particularly humiliating)

**Constant `K.AL_KABOOT_REVERSE` does not exist.** Only mentioned in
CHANGELOG, docs, and prior swarm findings as a proposal.

**Impact (per S-Score-06):**
- Hokm: code awards 25 gp, should be ~9 gp → **over-pays defender by ~16 gp/round**
- Sun: code awards 44 gp (220×2÷10), should be ~18 gp (88×2÷10) → **over-pays defender by ~35 gp/round**

**In a 152-target game, a single Reverse-AK round is currently game-deciding when it shouldn't be.**

**Fix shape:**
1. Add `K.AL_KABOOT_REVERSE = 88` constant
2. In `Rules.lua:742-745` and `847-853`, branch on
   `R.TeamOf(sweepWinner) == R.TeamOf(contract.bidder)`:
   - Same team (forward Al-Kaboot): existing 250/220 logic
   - Different team (Reverse Al-Kaboot): `K.AL_KABOOT_REVERSE = 88`,
     gated on `tricks[1].plays[1].seat == contract.bidder` (else fall
     through to normal scoring — no Reverse-AK if bidder didn't lead)

**Status:** unchanged across v0.7.1 → v0.10.4 audit cycles. Already in
synthesis §4.2 backlog.

---

## 🟡 New MED findings (not in prior backlog)

### MED-1: Belote-cancellation rule diverges between R.ScoreRound and Net.lua qaid handlers

**Sites:**
- `R.ScoreRound:769-777` — **team-level** cancellation (any ≥100 meld on belote-team cancels the +20 belote — v0.9.0 M5 fix)
- `Net.HostResolveTakweesh:2278` — **same-player-only** check (`m.declaredBy == kWho`)
- `Net.HostResolveSWA:3001` — **same-player-only** check

**Repro:** Bidder's partner declares a quarte (100); bidder holds K+Q
of trump (Belote 20). Bidder gets Takweesh'd. `R.ScoreRound` would
cancel the Belote (team-level rule); `Net.HostResolveTakweesh` does NOT
(same-player check fails). **Bidder team is over-credited +2 gp** in
the qaid penalty.

**Source:** S-Score-07.

**Fix shape:** copy the team-level cancellation logic from
`R.ScoreRound:769-777` into both `Net.HostResolveTakweesh` and
`Net.HostResolveSWA`. Or extract to a shared helper
`R.IsBeloteCancelled(team, meldsByTeam)`.

---

### MED-2: Game-end tiebreak logic diverges across 3 host call sites

**Sites:**
- `Net.lua:1721-1750` (normal round-end) — uses **canonical post-v0.8.6 H3 tiebreak** (Gahwa-winner > bidderMade-side > defensive "A")
- `Net.lua:2362-2372` (Takweesh) — **pre-v0.8.6 raw bidder-team logic**
- `Net.lua:3091-3100` (SWA) — **pre-v0.8.6 raw bidder-team logic**

**Repro:** Both teams hit 152 gp simultaneously via a Takweesh or
SWA-invalid resolution. Pre-v0.8.6 tiebreak could award the match to
the **offender** team. Post-v0.8.6 tiebreak rules them out correctly.

**Source:** S-Score-08.

**Fix shape:** factor the H3 tiebreak into a shared
`R.GameEndWinner(cumA, cumB, target, contract, outcome_kind)` helper
and call it from all 3 sites.

---

### MED-3 (re-flagged): Gahwa-on-Sun stale-flag at Rules.lua:959

**Site:** `Rules.lua:957-967` Gahwa branch (formerly cited as line 928,
shifted post-v0.10.0).

**Bug:** Gahwa-match-win branch is NOT type-gated. The multiplier path
(lines 904-913) and inversion path (825-832) BOTH defensively collapse
Sun's stale tripled/foured/gahwa flags. The Gahwa branch was missed.

**Repro:** Sun contract with stale `contract.gahwa = true` (incomplete
state reset, resync, hostile peer) → spurious match-win for the bidder.

**Severity:** **MED** (defensive — phase machine guards prevent normal
state from setting `gahwa = true` on Sun, but state-corruption paths
exist).

**Source:** S-Score-02 + S-Score-08 both flagged this independently.

**Fix shape:** wrap the branch in `if contract.type == K.BID_HOKM and contract.gahwa then` (one line).

---

### MED-4 (re-flagged): Belote sweep-override resurrects cancelled Belote

**Site:** `Rules.lua:752-754` (sweep-override) ordered BEFORE
`Rules.lua:769-777` (cancellation walk).

**Bug:** When K+Q-holder's team has a ≥100 meld AND the OTHER team
sweeps, the sweep-override at 752-754 reassigns the Belote owner before
the cancellation walk at 769-777 has a chance to cancel it. Net result:
~2 gp swing in rare configs.

**Severity:** MED (already known from B-Rules-02 F-01).

**Source:** S-Score-04 confirmed.

**Fix shape:** swap the order — walk cancellation first, then apply
sweep-override.

---

## 🟢 LOW findings

| ID | Site | Description |
|---|---|---|
| LOW-1 | `Net.lua:2223-2228, 2959-2964` (Sun-rung normalization) | Net.lua qaid handlers don't apply v0.10.0 R2 Sun-rung defensive normalization. Production-unreachable due to phase guards but defense-in-depth gap. |
| LOW-2 | `Constants.lua` | No `K.GAME_TARGET` constant — value `152` is hardcoded as `or 152` literal in 6+ call sites. Hygiene improvement. |
| LOW-3 | `glossary.md:159` | Mislabels target units as "raw" — actually game points. Doc-only. |
| LOW-4 | `Rules.lua` (R.TeamOf nil-handling) | `R.TeamOf(nil)` returns `"B"` silently — same root cause as `B-Rules-02 F-04` and `S-Score-05 B-1`. Defensive only. |
| LOW-5 | `tests/test_rules.lua` Section J | No discriminating test for Belote multiplier-immunity at ×3/×4. Suggested pin: assert ×4 round = 42 gp (immune), not 48 gp. |
| LOW-6 | `tests/test_rules.lua` Section H | No integration test passing `value=400` through `R.ScoreRound`. R5 verification is mathematical, not test-pinned. |

---

## ✅ Resolved false alarm — REMOVE from synthesis §4.2

| §4.2 entry to REMOVE | Why |
|---|---|
| "MED \| `Net.lua:2185-2190, 2930-2935` \| R2 Sun mult collapse not backported to Takweesh / SWA-invalid \| prior summary" | **Not a bug.** Both `Net.HostResolveTakweesh:2223-2228` and `Net.HostResolveSWA invalid:2959-2964` correctly apply `K.MULT_SUN`. S-Score-07 verified. |

---

## ❓ Doctrine question for the user

Per v0.10.1 M1 user-arbitration:
- **Regular failed-bid (R.ScoreRound):** preserves both teams' melds («مشروعي لي ومشروعك لك»).
- **Qaid context (Takweesh, SWA-invalid):** FORFEITS the offender's own melds.

This asymmetry is intentional per v0.10.1 commit but isn't documented
in `saudi-rules.md`. **Was this the intended Saudi-convention reading,
or a miscommunication during M1?** If intentional, document it. If
unintentional, align Qaid context with the "keep your own melds" rule.

The agent (S-Score-07) flagged this as a doctrine question because the
prompt's framing implied the latter, while the code does the former.

---

## Citation drift to fix in saudi-rules.md (informational)

S-Score-02 caught one stale line ref:
- saudi-rules.md Q1 says Belote-Hokm gate is at `Rules.lua:694` →
  actual line is **725** (function migrated post-v0.10.0).

Also worth correcting:
- CLAUDE.md "Bidder fails on tied 81/162 — strict majority required"
  is **Hokm-only** — should also mention Sun's 65/130 threshold.

---

## Suggested v0.10.5 release scope (post-v0.10.4 ship)

**HIGH (release-defining):**
1. Apply X5 follow-through 1-line fix at `State.lua:1167-1184` + comment cleanup
2. Add `K.AL_KABOOT_REVERSE = 88` and gate `Rules.lua:742-745` + `847-853` on bidder-team check + bidder-led-trick-1

**MED (low-risk follow-ups):**
3. MED-1: factor Belote-cancellation team-level rule into shared helper, use in 3 sites
4. MED-2: factor game-end H3 tiebreak into shared helper, use in 3 sites
5. MED-3: type-gate the Rules.lua:959 Gahwa branch (1 line)
6. MED-4: reorder Belote sweep-override vs cancellation walk

**LOW (optional cleanup, can slip to v0.10.6):**
7. Add `K.GAME_TARGET = 152` constant; replace 6+ hardcoded `or 152` literals
8. Test pins: ×4 Belote-immune (LOW-5), Carré-A 400 (LOW-6), Hokm-tied-doubled (S-9 suggestion)
9. Doc fixes: saudi-rules.md line 694→725, glossary.md:159 "raw"→"game points", CLAUDE.md tied-fail Sun-mention

**Doctrine confirmation needed before release:**
- Confirm or reverse Qaid melds-forfeit asymmetry vs «مشروعي لي ومشروعك لك»

---

## Methodology notes

All 10 agents ran read-only. Output reports under
`.swarm_findings/review_v0.10.2/_track_S_scoring/S-Score-01..10.md`.
None modified code. Test suite unchanged at 377/377 pass per the
last v0.10.4 ship-readiness review.

The two HIGH bugs were each independently surfaced by 2+ agents in this
sub-audit, AND triangulated against 3+ prior audits in the v0.10.2
review corpus. High confidence.

---

*End of SCORING_SUMMARY.md*
