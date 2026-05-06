# 58 — Tahreeb sender/receiver desync hunt (v0.9.0)

Adversarial scan of 5 mismatch scenarios after v0.9.0 wired the want-arm sender. HEAD = `Bot.lua` commit 9c32c50.

## 1. Per-suit ascending check — CORRECT

`tahreebClassify` (Bot.lua:1495–1530) is invoked per-suit by callers
(Bot.lua:1666 `signals[su]`, Bot.lua:1698 `osignals[su]`). Recording at
Bot.lua:529 also indexes `style.tahreebSent[cardSuit]` per-suit. The
ascending/descending check at lines 1521–1526 therefore evaluates
ranks WITHIN ONE SUIT only. No cross-suit contamination.

## 2. Want-arm vs T-4 race on same suit — NO RACE

Want-arm gate: `#cards >= 3` AND holds A or T (Bot.lua:2511–2514).
T-4 gate: `#cards == 2` (Bot.lua:2552). Mutually exclusive
per-suit. Want-arm placed FIRST in code order (Bot.lua:2509 vs 2550)
with early `return`, so any A/T-bearing 3+-suit short-circuits before
T-4 evaluates. Across suits, the first qualifying want-suit wins;
later T-4 dumps on the same trick are skipped — accepted in finding
13 because subsequent tricks naturally produce ascending follow-ups
when the suit drops to 2.

## 3. Bargiya 2-flavor receiver asymmetry — REAL DESYNC

Partner-pref scoring (Bot.lua:1673–1676): `bargiya_hint` weight=1.
N-3 opp-avoid (Bot.lua:1699): only `"bargiya"` or `"want"` mark
avoid; **`"bargiya_hint"` is silently dropped (no else-branch)**.
Documented as intentional in finding 14, but creates a real
sender/receiver desync: if a Saudi-tier OPP sender legitimately
emitted a Bargiya invite (Sun T-1, Bot.lua:2482–2493) and this seat's
M3lm receiver only sees the single-A event so far, we will fail to
mark their target suit as avoid — partner-of-opp may then catch us
out by leading-back. Mitigated only by event-#2 promotion to full
`bargiya`, which depends on opp getting a second discard window.

## 4. First-event prior 70/25/5 — CONFIRMED NOT-WIRED

CHANGELOG.md:175 lists "70/25/5 prior" in DEFERRED column.
Single-event non-Ace returns `"hint"` (Bot.lua:1514). Score-map at
1673–1676 has no entry for `"hint"`, so it falls through to `0`
(line 1676 `or 0`). Single-event signals from BOT partners are
ignored. Human-partner reads are independently blocked by
`Bot.IsBotSeat(p)` gate at Bot.lua:1657. So legitimate first-event
human signals are doubly missed (gate + zero-weight). Bot-partner
first-events are also missed (zero-weight only); v0.9.0 sender-side
mitigation is that the want-arm specifically aims to GENERATE event
#2 on the same suit naturally, but if the sender only gets one
discard window in the round, the signal evaporates.

## 5. Cross-tier sender/receiver — SILENT DROP

Recording at Bot.lua:515–534 is **ungated** — runs for every
`Bot.OnPlayObserved` regardless of tier. So Saudi-Master bots
(delegating to Bot.PickPlay per CLAUDE.md) DO emit want-arm signals
when partner is winning. Receiver consumption at Bot.lua:1654 is
gated `Bot.IsM3lm()`. Tier hierarchy (WHEREDNGN.lua:32–36):
Basic ⊂ Advanced ⊂ M3lm ⊂ Fzloky ⊂ SaudiMaster. So:

- Saudi-Master partner ↔ Saudi-Master receiver: works.
- Saudi-Master partner ↔ Basic receiver: **silent drop** — sender
  encodes, receiver branch never executes; receiver picks lead via
  random-legal (basic) or Advanced heuristics, ignoring style
  ledger. No fallback notification, no degradation log.

Acceptable in pure same-tier table configs but produces partial-
information leak in mixed-tier debugging tables.

## Files
- C:/CLAUDE/WHEREDNGN/Bot.lua:515–534 (recorder, ungated)
- C:/CLAUDE/WHEREDNGN/Bot.lua:1495–1530 (classifier)
- C:/CLAUDE/WHEREDNGN/Bot.lua:1654 (M3lm receiver gate)
- C:/CLAUDE/WHEREDNGN/Bot.lua:1673–1676 (partner score map, no hint entry)
- C:/CLAUDE/WHEREDNGN/Bot.lua:1699 (opp avoid, drops bargiya_hint)
- C:/CLAUDE/WHEREDNGN/Bot.lua:2509–2531 (want-arm sender)
- C:/CLAUDE/WHEREDNGN/Bot.lua:2550–2566 (T-4 dontwant sender)
