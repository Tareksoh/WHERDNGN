# 54 — M4 _partnerStyle persistence quirks (v0.9.0)

Bundle path: `WHEREDNGNDB.session.bot = { partnerStyle, memory, r1WasAllPass }`,
saved by `S.SaveSession` (`State.lua:269-286`), rehydrated by
`S.RestoreSession` (`State.lua:346-358`) on PLAYER_LOGIN.

## 1. Counter overflow — NON-ISSUE
All counters (`bels/triples/fours/gahwas/gahwaFailed/sunFail/aceLate/
trumpEarly/trumpLate/leadCount[suit]/baitedSuit[suit]`) increment by 1
per action. Even a 200-round game tops out at hundreds of events per
seat. Lua doubles are safe to 2^53. Zero risk.

## 2. Stale data on cross-game restore — REAL BUG (HIGH)
`_partnerStyle` is keyed by **SEAT INDEX 1..4** (`Bot.lua:175 m[s] =
{...}`), NOT by player name. Save records `bot.partnerStyle` verbatim;
restore copies it without consulting `s.seats[s].name`. Failure mode:
mid-game `/reload` is fine (same seats), but a session that survives
GAME_END (e.g. host crashed before `SaveSession` could clear
WHEREDNGNDB.session at IDLE/LOBBY/GAME_END per `State.lua:252-255`)
has the OLD game's seat→name mapping. Within the 1-hour expiry window
(`State.lua:292`), the new game's lobby may seat different players —
seat 2's stats are now the previous Bot's history applied to a new
human. No name-keyed verification.

**Fix:** persist `{seat, name}` pairs and remap on restore using
current `s.seats[].name`; drop entries with no match. Or just call
`Bot.ResetStyle()` if any seat name differs from the saved snapshot.

## 3. Unbounded growth — LOW
`session.bot` is bounded: 4 seats × ~10 fields + 4 suit-keyed sub-
tables. `tahreebSent[suit]` (the only growing list) is reset per round
(`Bot.lua:147-153`). `topTouchSignal[suit]` is single-shot. SaveSession
auto-clears at IDLE/LOBBY/GAME_END so old sessions don't pile up. No
explicit cap, but bounded ~few KB.

## 4. Hand-edit attack — PARTIAL
Setting `triples = 999999` won't crash: `PickFour:3304-3305` reads it
with a `>= 2` bucket and `th` is floored at `BOT_FOUR_TH - 16`
(line 3313). All counter consumers gate via thresholds, not raw values
— so numeric corruption produces predictable behavior, not crashes.

**However**: setting `tahreebSent.S = "not a table"` or
`leadCount = 7` would crash `ipairs`/index call sites. No structural
type guards on rehydrate.

## 5. Type coercion — REAL BUG (HIGH)
`State.lua:349`: `if sess.bot.partnerStyle then ... end` — truthy
guard only. If a corrupt SavedVariables sets
`partnerStyle = "corrupt_string"`, the assignment succeeds. First call
to `Bot.OnEscalation` does `local m = Bot._partnerStyle[seat]` →
string indexing returns nil in Lua (no error), then
`m.bels = m.bels + 1` errors with "attempt to index a nil value (local
'm')" — but the very NEXT call to `OnEscalation` re-checks
`if not Bot._partnerStyle then ... = emptyStyle() end` (line 252),
which evaluates the STRING as truthy and skips the rebuild. Bot
decisions break for the rest of the game.

**Fix:** `if type(sess.bot.partnerStyle) == "table" then ...` at
restore, AND the same type check inside `OnEscalation/OnPlayObserved/
OnRoundEnd` guard rebuilds.

## 6. Cross-character leak — MITIGATED but order-dependent
`State.lua:298-300` rejects restore when `sess.owner ~= s.localName`.
Guard form: `if sess.owner and s.localName and sess.owner ~=
s.localName then return false end`. **If `s.localName` is nil at
restore time, the AND short-circuits and the cross-character session
is accepted.** Audit `WHEREDNGN.lua` PLAYER_LOGIN ordering: must
guarantee `S.SetLocalName(UnitName("player"))` runs BEFORE
`S.RestoreSession()`. If they're parallel event handlers, race exists.
**Fix:** invert guard: `if not s.localName or sess.owner ~= s.localName
then return false end` — fail closed.
