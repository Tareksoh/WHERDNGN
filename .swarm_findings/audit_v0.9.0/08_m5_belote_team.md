# M5 Belote team-level cancellation — v0.9.0 audit

**Verdict: FIXED CORRECTLY.**

## Predicate change (Rules.lua:675-683)

Pre-v0.9.0:
```lua
if belote and kWho and R.TeamOf(kWho) == belote then
    for _, m in ipairs(list) do
        if m.declaredBy == kWho and (m.value or 0) >= 100 then
```

v0.9.0:
```lua
if belote and kWho then
    local list = (meldsByTeam and meldsByTeam[belote]) or {}
    for _, m in ipairs(list) do
        if (m.value or 0) >= 100 then
            belote = nil
            break
```

The `m.declaredBy == kWho` player gate is gone. The list comes from
`meldsByTeam[belote]` — the team currently holding belote (post-sweep
override). Iteration is therefore intrinsically team-scoped: any
team-mate's ≥100 meld now cancels. Correct.

## Test pin updated (tests/test_rules.lua:647-662)

The test that previously asserted `res.belote == "A"` (i.e. partner's
quarte does NOT cancel) was updated to assert `res.belote == nil`,
with comment marking it as the v0.9.0 M5 fix and noting the pre-v0.9.0
expected value of `"A"` for traceability. The buggy pin is no longer
pinning the bug. Correct.

## Edge cases

1. **Both partners hold ≥100 melds, one holds Belote.** Loop iterates
   `meldsByTeam[belote]`; first ≥100 entry hits the break. Cancellation
   fires regardless of which partner declared. Correct.

2. **Opposite-team ≥100 meld.** `list = meldsByTeam[belote]` reads only
   the belote-holding team's meld list. Opposite-team melds live under
   the other key and are never iterated. No cross-team leak. Correct.

3. **`m.declaredBy == nil` (legacy / missing field).** Pre-v0.9.0 the
   `m.declaredBy == kWho` predicate silently failed for any nil
   `declaredBy` — the bug the audit caught. v0.9.0 no longer references
   `m.declaredBy` at all in the cancellation predicate, so missing-field
   melds with `value >= 100` correctly cancel. Defends against legacy
   data shape. Correct.

## Cross-checks

- Sweep override (Rules.lua:658-660) still moves belote to sweeper
  before cancellation runs — order preserved, so cancellation operates
  on post-sweep `belote` team. Correct.
- `(m.value or 0) >= 100` defends against missing `value` field. Correct.
- `kWho` is still required (guards against belote with no K+Q holder
  identified) — sensible defensive check retained.

No regressions detected. Test count 330/330 per commit message is
consistent with the test_rules.lua delta being a single expected-value
flip (no test additions or removals).
