# v3.2.7 TAKWEESH tooltip clarification — UX-only design

**Status:** design pass only. No runtime / packaging / test edits
yet. Uncommitted on `main`.

**Provenance:**

- v3.2.6 (`c310cd2`, tag `v3.2.6`) shipped the
  `Bot.PickTakweesh` false-AKA carve-out and identified a
  follow-up UX hazard at `.swarm_findings/
  v3_2_6_aka_takweesh_investigation.md` §9.3: the existing
  TAKWEESH button tooltip does not warn the user that calling
  Takweesh on a **same-team** illegal play counts as a wrong
  call and penalizes the caller's own team.
- Current state: `main = origin/main = c310cd2`. Harness
  baseline `1295 / 0`.
- Latest shipped tag: `v3.2.6`.

**Hard constraints (this pass):**

- Design only. **No edits to `Bot.lua`**, runtime files,
  `tests/`, `.toc`, `.pkgmeta`, `.github/`, packaging, or
  CHANGELOG.
- No branch, no tag, no release.
- Preserve `sprint-a-experimental` and `v0.5.1-experimental`.
- Leave `.swarm_findings/v3_2_0_botlua_comment_audit.md`
  untouched and untracked.
- This document stays **uncommitted** until Codex review
  approves the proposed wording.

---

## 1. Existing TAKWEESH tooltip — source inventory

**`UI.lua:2476-2485`** (the only TAKWEESH tooltip call site):

```lua
addConfirmAction("|cffff5555TAKWEESH|r",
    "|cffff5555TAKWEESH? again to confirm|r",
    function() net().LocalTakweesh() end,
    "TAKWEESH — accuse the most recent illegal play "
    .. "(Saudi 'tikweesh', accusation of foul). If the "
    .. "play was actually illegal AND the violator later "
    .. "showed they had the led suit (publicly observable "
    .. "proof), the offending team takes a ~30-pt qaid "
    .. "penalty. Wrong call costs YOUR team the same "
    .. "penalty. Use only when you're sure.")
```

The tooltip is correct for **wrong-card / off-suit / revoke**
cases (the "violator later showed they had the led suit" line
is exactly the v1.5.1 realism gate semantic). It's **silent on
two related axes** that the v3.2.6 investigation identified:

1. **Same-team illegal plays don't qualify.** The host's
   `HostBeginTakweeshReview` scan at `Net.lua:3362` and
   `HostResolveTakweesh` scan at `Net.lua:3545` both filter
   `R.TeamOf(p.seat) ~= callerTeam` — so a human pressing
   TAKWEESH on their own teammate's illegal play (e.g. a bot
   teammate's noise-AKA marked as false AKA) resolves as
   "no proof found" → wrong call → caller's team penalized.
2. **False AKA is publicly observable immediately** — the
   "violator later showed" language doesn't fit; false AKA is
   knowable from the trick log + AKA banner the moment the
   lead hits the table. This is a minor mismatch and doesn't
   change tooltip behavior in practice — but a precise tooltip
   could say so.

The button is always-visible during `PHASE_PLAY` (per the
docblock at `UI.lua:2464-2468`) and always confirms via
`addConfirmAction` — so the cost of a misclick is one extra
confirmation click, not an immediate fire. The tooltip is the
user's primary information channel before they confirm.

---

## 2. Other UI sites that reference Takweesh (informational)

| Site | Purpose | Wording change needed? |
|---|---|---|
| `UI.lua:1539` | TAKWEESH banner doc comment | No |
| `UI.lua:1673-1772` | Takweesh REVIEW banner (cards-reveal display) | No — this fires only after a call is placed |
| `UI.lua:2478` | TAKWEESH button click → `net().LocalTakweesh()` | No |
| `UI.lua:2476-2485` | TAKWEESH button tooltip | **YES — clarify same-team** |

Only the tooltip at L2476-2485 needs updating. The review banner
title/body text is set dynamically per-call inside
`_OnTakweeshReview` and `HostBeginTakweeshReview`, which carry
the actual outcome — they're already correct.

---

## 3. Proposed final tooltip text

Two sentences added between the existing "qaid penalty" line
and the existing "Use only when you're sure" line. The change
preserves all current information and adds the same-team rule
plus a brief acknowledgement that false-AKA is one of the
qualifying patterns:

```lua
addConfirmAction("|cffff5555TAKWEESH|r",
    "|cffff5555TAKWEESH? again to confirm|r",
    function() net().LocalTakweesh() end,
    "TAKWEESH — accuse the most recent illegal play "
    .. "(Saudi 'tikweesh', accusation of foul). If the "
    .. "play was actually illegal AND the violator later "
    .. "showed they had the led suit (publicly observable "
    .. "proof), the offending team takes a ~30-pt qaid "
    .. "penalty. False AKA on a non-trump lead is a separate "
    .. "qualifying pattern — the bogus claim is provable from "
    .. "the trick log immediately, no later reveal needed. "
    .. "Only OPPOSING-team illegal plays qualify; calling "
    .. "Takweesh on your own teammate's illegal play counts "
    .. "as a wrong call. "
    .. "Wrong call costs YOUR team the same "
    .. "penalty. Use only when you're sure.")
```

**Wording rationale:**

- "Only OPPOSING-team illegal plays qualify" uses uppercase
  OPPOSING-team to mirror the existing tooltip's uppercase
  YOUR-team (line 2484) for visual scannability.
- "your own teammate's illegal play counts as a wrong call"
  explicitly maps the failure mode onto the existing "wrong
  call costs YOUR team" pre-existing line — so the
  consequence is unambiguous.
- "False AKA on a non-trump lead is a separate qualifying
  pattern" is short, technically accurate, and ties into the
  v3.2.6 fix without using internal jargon like
  `illegalReason`. Acceptable to drop this sentence if Codex
  prefers a more minimal change; the same-team line is the
  critical addition.

**Alternative minimal wording** (same-team only, no false-AKA
mention):

```lua
    "TAKWEESH — accuse the most recent illegal play "
    .. "(Saudi 'tikweesh', accusation of foul). If the "
    .. "play was actually illegal AND the violator later "
    .. "showed they had the led suit (publicly observable "
    .. "proof), the offending team takes a ~30-pt qaid "
    .. "penalty. Only OPPOSING-team illegal plays qualify; "
    .. "calling Takweesh on your own teammate counts as a "
    .. "wrong call. Wrong call costs YOUR team the same "
    .. "penalty. Use only when you're sure."
```

Either form is acceptable.

---

## 4. Source-pin or test recommendation

### 4.1 Should a source-pin test be added?

**Yes, recommended.** The tooltip wording is the user's only
pre-confirmation safeguard against the same-team UX hazard.
A future cleanup that re-flows the tooltip prose could
accidentally drop the same-team line. A `tests/test_state_bot.lua`
source-pin on the literal phrase `"Only OPPOSING-team illegal
plays qualify"` (or the chosen anchor) would catch that.

Proposed pin location: **after BM** (the v3.2.6 AKA/Takweesh
section) in a new **BN** section, since this is the UX
follow-up to v3.2.6. One sub-assert is sufficient.

```lua
do
    local uiSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/UI.lua"):read("*a")
    -- BN.1: TAKWEESH tooltip explicitly warns same-team.
    -- v3.2.7 UX clarification per
    -- .swarm_findings/v3_2_7_takweesh_tooltip_design.md.
    assertTrue(uiSrc:find("OPPOSING%-team illegal plays qualify") ~= nil,
        "BN.1 (v3.2.7): TAKWEESH tooltip warns same-team Takweesh = wrong call")
end
```

Single source-pin assert. Harness delta: `1295 → 1296`.

### 4.2 Should a behavioral test be added?

**No.** The behavior the tooltip warns about (same-team scan
rejecting → false-call penalty) is **already wire-locked by
BM.3** at `tests/test_state_bot.lua:11321+`. BM.3 proves that
`HostBeginTakweeshReview` finds no illegal play when caller is
on the violator's team. The v3.2.7 tooltip change is text-only;
no runtime / scoring / scan-filter behavior changes, so BM.3
remains the right regression guard for the underlying
mechanism.

---

## 5. Recommended slice shape

**Smallest viable slice: tooltip text change + BN.1 source-pin.**

- **UI.lua:2479-2485** — replace the existing tooltip string
  with the new wording from §3 (whichever Codex picks:
  expanded form or minimal form).
- **tests/test_state_bot.lua** — add BN section after BM with
  a single source-pin sub-assert.

**Estimated branch / commit shape:**

- 1 commit on a feature branch `takweesh-tooltip-v3.2.7`:
  `ui(UI.lua): clarify TAKWEESH tooltip same-team rule`.
- Single behavioral commit; no docs needed beyond this design
  doc + the inevitable v3.2.7 CHANGELOG entry when shipped.

**Expected harness delta:** `1295 → 1296` (+1 source-pin).

**Release impact:** the only change is a tooltip string. **No
gameplay / protocol / saved-variable / scoring / .toc /
packaging change.** Justifies a v3.2.7 patch tag with a 1-line
CHANGELOG entry ("clarify same-team Takweesh tooltip
wording").

---

## 6. Stop conditions

1. **Tooltip wording exceeds visual reasonability.** Long
   tooltips wrap awkwardly. If the chosen wording renders
   wider than the existing tooltip's width budget (~400px in
   the default Blizzard tooltip frame), trim to the minimal
   form in §3.
2. **Source-pin substring fails to match.** Verify against
   current `UI.lua` HEAD before committing; do NOT silently
   weaken the pin.
3. **BM.3 regresses.** Same-team filter is a runtime
   invariant; tooltip change must not touch `Net.lua` /
   `Bot.lua`. If BM.3 breaks, the slice has scope-crept.
4. **Behavioral test failure.** Should not happen — only
   `UI.lua` is touched. If any behavioral test changes status,
   stop and audit scope.

---

## 7. Recommendation

**Proceed with the smallest slice in §5.** Single UI.lua text
change + single source-pin assert. Defer to Codex for:

1. Choice between the expanded form (mentions false AKA) vs
   the minimal form (same-team only).
2. Whether to tag this as v3.2.7 immediately, batch with a
   future runtime fix, or hold indefinitely.

The minimal form is the safer wording choice — it doesn't
introduce SaudiMaster-specific terminology into the UI and
focuses on the actionable rule the player needs to know.

---

## 8. Open questions for Codex review

1. **Tooltip wording length.** Expanded form (mentions false
   AKA) is more accurate but ~1.5x longer. Minimal form is
   tighter but doesn't tie the v3.2.6 fix into the visible UX.
   **Recommend minimal form.**
2. **Source-pin scope.** Single assert vs paired (same-team
   phrase + qualifying-pattern phrase). **Recommend single
   assert** — over-pinning increases doc-rewording fragility.
3. **Release timing.** Tag v3.2.7 immediately, or hold for
   bundled future fixes (e.g. if a tooltip change is the only
   thing in a release, the version bump may feel light).
   **Recommend immediate v3.2.7 patch** — UX is a meaningful
   player-facing change that warrants its own release.

---

## 9. Confirmation

- No tracked files changed by this design pass.
- This document is created uncommitted; Codex review precedes
  any commit.
- No edits to `Bot.lua`, runtime files, `tests/`, `.toc`,
  `.pkgmeta`, `.github/`, CHANGELOG, or packaging.
- No branch created, no tag created, no release initiated.
- `sprint-a-experimental` and `v0.5.1-experimental` preserved.
- `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
