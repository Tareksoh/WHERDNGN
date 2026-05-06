# 14 — Bargiya 2-Flavor Split (v0.9.0)

## Verdict: SHIPPED-CORRECT (test pin missing)

Original v0.7.1 finding (Bot.lua:1410-1415): both invite and defensive-shed
collapsed under single `bargiya` label, wasting Aces in shed scenarios.
v0.9.0 splits into 2 confidence tiers per the CHANGELOG spec.

## Wire verification

### Classifier (Bot.lua:1495-1518, commit 9c32c50)

```lua
local function tahreebClassify(signals)
    if not signals or #signals == 0 then return nil end
    if signals[1] == "A" then
        if #signals >= 2 then
            return "bargiya"        -- confirmed invite (cover proven)
        end
        return "bargiya_hint"       -- ambiguous (possible defensive shed)
    end
    if #signals == 1 then return "hint" end
    ...
```

Matches CHANGELOG: `bargiya` requires `signals[1]=="A"` AND `#signals >= 2`;
`bargiya_hint` is the single-Ace fallback. Pre-v0.9.0 conditional collapsed
both into `"bargiya"`.

### Receiver scoring weights (Bot.lua:1666-1676)

```lua
local cls = tahreebClassify(signals[su])
local score = (cls == "bargiya"      and 3)
           or (cls == "want"         and 2)
           or (cls == "bargiya_hint" and 1)
           or 0
```

Matches CHANGELOG: 3 / 2 / 1. The hint scoring 1 (below `want`=2)
correctly lets multi-event signals dominate ambiguous single-A.

### N-3 opp-avoid (Bot.lua:1698-1701)

Opponent-side classifier reuses `tahreebClassify` but only marks `bargiya`
or `want` for avoid — `bargiya_hint` is intentionally NOT treated as
opp-avoid. Correct: low-confidence opp signal does not dominate our own
lead pref.

## Edge answers

**4. What escalates `_hint` → `bargiya`?**
Just `#signals >= 2`. The classifier inspects ONLY array length — it does
not require the second event be same-suit (signals are already per-suit
indexed: `signals[su]`), nor higher/lower rank. Any second discard event
in the same Tahreeb suit confirms cover and promotes to invite.

**5. Receiver passes on `bargiya_hint` — does sender re-fire?**
No automatic re-fire mechanism. The sender ledger
(`tahreebSent[suit][]`) is append-only via `Bot.OnPlayObserved`. If the
sender has further opportunities, natural follow-up discards will append
event #2 organically (because the sender's hand-shape conditions still
hold). The signal does not re-emit "louder" specifically because the
receiver passed; sender is unaware of receiver's classification.

**6. Test pin status: ABSENT.**
Grep for `bargiya_hint` across `tests/` returns 0 matches.
`test_state_bot.lua:829` references "T-1 Bargiya: skipped" only as a
comment in a `pickFollow` scenario, not a classifier-output assertion.
No `tahreebClassify` direct unit test, no scoring-weight regression pin.
Untested wire — risk that future refactors silently collapse the flavors
back without test failure. Recommend adding a 4-row table test:
empty/single-non-A/single-A/multi-A → expected nil/hint/bargiya_hint/bargiya.

## Files
- C:/CLAUDE/WHEREDNGN/Bot.lua:1495-1518 (classifier)
- C:/CLAUDE/WHEREDNGN/Bot.lua:1666-1676 (partner-pref weights)
- C:/CLAUDE/WHEREDNGN/Bot.lua:1698-1701 (opp-avoid filter)
- C:/CLAUDE/WHEREDNGN/CHANGELOG.md:142-146 (spec)
