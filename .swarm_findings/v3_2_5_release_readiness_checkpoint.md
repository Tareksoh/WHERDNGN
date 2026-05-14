# v3.2.5 release-readiness checkpoint

**Status:** investigation pass only. No runtime / packaging / test
edits. Uncommitted on `main`.

**Provenance:**

- Five test-only coverage batches landed since `v3.2.3`:
  BH/BI/BJ/BK/BL. No runtime code has changed.
- This checkpoint precedes a release decision and is paired with
  `.swarm_findings/v3_2_6_aka_takweesh_investigation.md`, which
  investigates a user-reported AKA → Takweesh incident.

---

## 1. Repo state

- **`main` HEAD** = **`origin/main` HEAD** = `051dfcc`.
- **Latest shipped tag:** `v3.2.3` (commit `b78b8d2`, see CHANGELOG
  for the release notes; this checkpoint does not retag).
- **Branches preserved:** `sprint-a-experimental`,
  `v0.5.1-experimental`. No feature branches outstanding.
- **Untracked files:** only `.swarm_findings/v3_2_0_botlua_comment_audit.md`
  (long-standing, hard-rules-preserved).

### Linear `git log --oneline` since `v3.2.3`

```
051dfcc test(Bot.lua): add T-4 Sun pos-4 Faranka regression coverage
5986361 docs: add v3.2.5 T-4 Sun pos-4 Faranka design
200a73a test(Bot.lua): add T-2 sweep-pursuit-early regression coverage
ee1d99f docs: add v3.2.5 T-2 sweep-pursuit-early design
8fea79e test(Bot.lua): add T-10 Tahreeb-return regression coverage
a203b70 docs: add v3.2.5 T-10 Tahreeb-return design
9e4e10a test(Bot.lua): add Faranka Exception #2 regression coverage
2c32c29 docs(v3.2.5 batch B): switch BI.1/BI.2 to side-suit-led fixtures
ab18415 docs: add v3.2.5 high pickplay batch B design
21d7340 test(BH): comment-only polish per Codex review
6a4cfd2 test(Bot.lua): add HIGH pickplay regression coverage
c5c8fba docs: add v3.2.5 high pickplay coverage design
... (older v3.2.x docs)
```

**All v3.2.5 commits land in two categories only:**
- `docs(*)` — design / inventory under `.swarm_findings/`.
- `test(Bot.lua)` — test-only additions under `tests/`.

No `fix(*)`, `feat(*)`, `refactor(*)`, or runtime touch.

---

## 2. Test-only v3.2.5 coverage summary

| Section | Audit ID | Branch covered | Checks | Wire-discriminator |
|---|---|---|---|---|
| **BH.1** | T-6 | Sun Tahreeb "want, no A/no T" sender at `Bot.lua:3676-3701` | 1 behavioural | `8H` (per-suit lowest) vs `7D` (all-legal lowest) |
| **BH.2** | T-1.E4 positive | Hokm Faranka Exception #4 with `oppsVoidPath` at `Bot.lua:4017-4060` | 1 behavioural | `7H` (Faranka non-trump loser) |
| **BH.3** | T-1.E4 negative | Same trick, one-opp-void → E4 doesn't fire | 1 behavioural | `AH` (natural winner) |
| **BH.4a/b/c** | source pins | `v0.11.18-final U-2`, `oppsVoidPath`, `v0.10.3 F-30b` | 3 source-pin | n/a |
| **BI.1** | T-1.E2 positive | Hokm Faranka Exception #2 + F-16 satisfied at `Bot.lua:3979-3981` + `4094-4102` | 1 behavioural | `7H` (Faranka non-trump loser) |
| **BI.2** | T-1.E2 negative | E2 trigger fires but F-16 vetoes (no K) | 1 behavioural | `AH` (natural pos-4 winner) |
| **BI.4a/b/c** | source pins | `v0.10.0 X3 anti-rule F-16`, `v0.10.3 audit (A-Src-29`, `v3.2.1 F4` | 3 source-pin | n/a |
| **BJ.1** | T-10 positive | Tahreeb-receiver T-supply count≥3 "want" at `Bot.lua:1776-1788` | 1 behavioural | `TH` (T-supply lead-back) |
| **BJ.2** | T-10 negative | Same fixture, flavor ≠ "want" (bargiya_hint) | 1 behavioural | `8H` (legacy low-lead) |
| **BJ.3 + BJ.4** | source pins | `relevant seat is a bot` (L1278), `Receiver-side reads of human signals are` (L3580) | 2 source-pin | n/a |
| **BK.1** | T-2 positive | sweep-pursuit-early + v1.0.3 U-7 Kaboot-feasibility at `Bot.lua:1081-1136` | 1 behavioural | `JS` (boss-lead via safeBosses) |
| **BK.2** | T-2 negative | One opp prior win → gate fails | 1 behavioural | `9S` (lowestByRank fallback) |
| **BK.3** | source pin | `v1.0.3 (U-7) Kaboot-feasibility hand-shape gate` (L1089) | 1 source-pin | n/a |
| **BL.1** | T-4 positive | Sun pos-4 Faranka outer gate + Advanced at `Bot.lua:3179-3181` | 1 behavioural | `KH` (return cover) |
| **BL.2** | T-4 negative | v1.4.0 anti-trigger row 167 (`holdsTopTwoUnplayed`) → smother | 1 behavioural | `AH` (smother Takbeer) |
| **BL.3a + BL.3b** | source pins | `v0.5.21 Section 5 Sun pos-4 Faranka` (L3155), `v1.4.0 (Concern 5 audit fix` (L3201) | 2 source-pin | n/a |
| **Totals** | — | **5 audit gaps closed** | **22 new checks** | — |

Baseline grew **`1258 / 0 → 1280 / 0`** (+22 checks) across the v3.2.5 work.

---

## 3. Harness and smoke status

- **Full harness on current `main`:** `1280 passed, 0 failed`.
- **H1/H7 standalone smokes:**
  - `test_H1_pin_J9_trump.lua`: 11 passed, 0 failed.
  - `test_H7_sun_shortest_lead.lua`: 9 passed, 0 failed.
- **`git diff --check`** against `main`: clean.
- **No flaky tests observed** across the BH/BI/BJ/BK/BL merges.

---

## 4. Packaging / .pkgmeta / .toc sanity

| File | State | Notes |
|---|---|---|
| `WHEREDNGN.toc` | Unchanged since v3.2.3 | `## Version: @project-version@` (BigWigsMods packager substitutes from tag) |
| `.pkgmeta` | Unchanged | Correctly ignores `.swarm_findings/`, `tests/`, `docs/`, `tools/`, `cards/_src/`, `sounds/_make_*` |
| `CHANGELOG.md` | Unchanged | Last entry is for `v3.2.3` |
| `.github/workflows/` | Unchanged | Standard BigWigsMods packager workflow |

If we tagged `v3.2.5` today, the CurseForge release archive would
ship **identical addon bytes** to the `v3.2.3` archive — only
`.swarm_findings/` (excluded by `.pkgmeta`) and `tests/`
(excluded by `.pkgmeta`) have changed.

---

## 5. Release recommendation

### 5.1 Should v3.2.5 be a release at all?

**Recommendation: NO, do not tag `v3.2.5` as a CurseForge
release.**

Rationale:

1. **No runtime / saved-variable / protocol / scoring / UI change
   has shipped.** A v3.2.5 release would ship a bit-for-bit
   identical addon to the v3.2.3 archive. Players' clients would
   download a new addon version that does nothing different
   in-game.
2. **The CurseForge release notes would be empty of player-
   facing content.** "Internal test coverage backfill" is not a
   user-meaningful release.
3. **A tagged release implies a quality / behavior delta the
   user can audit.** v3.2.5 has zero such delta.
4. **Tag bumps are cheap to defer.** If a follow-up runtime fix
   lands (e.g. from the v3.2.6 incident investigation in §6),
   that fix can ship as v3.2.5 OR v3.2.6 at that point. Tagging
   the test-only work alone wastes a version number.

### 5.2 Specific hold on AKA → Takweesh investigation

**Even if §5.1 is overridden and a v3.2.5 release is desired,
HOLD pending the v3.2.6 investigation outcome.**

**Update (Codex correction):** the paired
`.swarm_findings/v3_2_6_aka_takweesh_investigation.md` has now
classified the incident:

- **Sub-scenario A1 (human opp clicks TAKWEESH on false AKA):**
  working as designed.
- **Sub-scenario A2 (bot opp `Bot.PickTakweesh` mis-gates false
  AKA via the revoke-style realism check):** **LIKELY RUNTIME
  BEHAVIOUR GAP.** Bot opponents almost never punish noise-AKA
  bluffs because the realism gate at `Bot.lua:5962` requires
  the violator to later play the AKA'd suit — typically
  doesn't happen. Recommend a narrowly-scoped runtime fix
  (~5 lines, single function, single branch).
- **Scenario B (same-team Takweesh UX hazard):** unchanged —
  TAKWEESH tooltip should explicitly warn against same-team
  calls.

**Release decision driven by the §A2 finding:**

- **v3.2.5 alone:** test-only, no runtime delta vs v3.2.3 →
  no player-facing change → **skip the tag**.
- **v3.2.6 (recommended next release):** ship the §9.2 runtime
  fix (Bot.PickTakweesh false-AKA carve-out) + BM test slice
  + optional tooltip clarification. This is a meaningful
  player-facing change (bots now correctly punish noise-AKA)
  and warrants a release tag with CHANGELOG entry.

The v3.2.5 work is release-clean from a test-coverage
perspective (1280/0 harness, no regressions), but the v3.2.6
investigation found a likely bot-behaviour gap that should be
**resolved or explicitly deferred** before tagging the next
release. Tagging v3.2.5 now and v3.2.6 immediately after would
ship two close-spaced releases for what is effectively one
work-cycle.

---

## 6. If released later, what should the notes say?

If we eventually tag a v3.2.5 release covering only the
test-only work, the CHANGELOG entry should be **explicit** that
no player-facing behavior changed:

```markdown
## v3.2.5 — Internal validation only

**No gameplay, UI, protocol, saved-variable, or scoring changes.**

Test-coverage backfill for five HIGH-risk Saudi-canonical
pickplay branches identified in the v3.2.1 audit, all of which
were already correct in v3.2.3:

- Tahreeb "want, no A/no T" sender (Sun, video #06+#09+#10)
- Hokm Faranka Exception #4 (both opps observed-void)
- Hokm Faranka Exception #2 + F-16 K-cover veto
- Tahreeb-receiver T-supply count≥3 "want" branch
- Sweep-pursuit-early Kaboot lead (v1.0.3 U-7 feasibility)
- Sun pos-4 Faranka outer gate + v1.4.0 row 167 anti-trigger

22 new harness checks; no runtime code touched.

If you experienced any gameplay change between v3.2.3 and v3.2.5,
that is a misattribution — the addon source files (.toc / Lua
files) are byte-identical to v3.2.3.
```

This framing is honest and avoids the "shipped a release with
no functional content" perception problem.

---

## 7. Conclusion

| Item | Status |
|---|---|
| Test-only v3.2.5 work | Complete, merged, harness green at 1280/0 |
| Packaging delta vs v3.2.3 | Zero (no addon-files-of-record changed) |
| Player-facing change since v3.2.3 | None |
| User-reported incident classification | A1 working-as-designed; **A2 likely runtime gap** (`Bot.PickTakweesh` mis-gates false AKA); B UX hazard |
| Recommended action | **HOLD** v3.2.5 tag. Bundle the v3.2.6 runtime fix (Bot.PickTakweesh false-AKA carve-out) + BM tests into a single v3.2.6 release. Skip a standalone v3.2.5 tag. |

**Concrete next step:** spec a v3.2.6 implementation prompt
covering:
1. The ~5-line `Bot.PickTakweesh` carve-out per
   `.swarm_findings/v3_2_6_aka_takweesh_investigation.md` §9.2.
2. The BM test slice (5 checks per §8.1-§8.5).
3. Optional TAKWEESH tooltip wording change per §9.3 (may
   split to v3.2.6b for separate UX review).

The v3.2.5 work remains landed on `main` (commits `c5c8fba`
through `051dfcc`) and contributes to the harness baseline that
v3.2.6 will build on.

---

## 8. Confirmation

- No tracked files changed by this checkpoint pass.
- This document is created uncommitted.
- No edits to `Bot.lua`, runtime files, `tests/`, `.toc`,
  `.pkgmeta`, `.github/`, CHANGELOG.
- No branch created, no tag created, no release initiated.
- `sprint-a-experimental` and `v0.5.1-experimental` preserved.
- `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched and
  untracked.
