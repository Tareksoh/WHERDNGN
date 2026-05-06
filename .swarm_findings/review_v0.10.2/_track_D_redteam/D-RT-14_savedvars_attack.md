# D-RT-14 — SavedVariables hand-edit attack surface (WHEREDNGNDB)

**Threat model:** the user has filesystem access to
`WTF/Account/<acct>/SavedVariables/WHEREDNGN.lua` between WoW sessions
and edits the file by hand to inject corrupt or malicious values. We
ask: does any single edit crash the addon at PLAYER_LOGIN, soft-lock
the next game, leak data across characters, or corrupt long-running
state without surfacing an error?

**Read sites covered:**
- `WHEREDNGN.lua:63-89` (`ensureDB` + `init`)
- `WHEREDNGN.lua:101-113` (`maybeRequestResync`, reads `lastGameID`)
- `WHEREDNGN.lua:130-296` (`PLAYER_LOGIN` → `init` → `RestoreSession`)
- `State.lua:31-126` (`reset()` — DB read with type-checks)
- `State.lua:250-375` (`SaveSession` / `RestoreSession`)
- `Slash.lua:213-269` (`/baloot history` dump)
- Audit cross-refs: `audit_v0.9.0/47_telemetry_growth.md`,
  `audit_v0.9.0/54_m4_partnerstyle_quirks.md`

Per-attack verdict: **DEFENDED / UNDEFENDED / PARTIAL**.

---

## ATK-1 — `WHEREDNGNDB = "bad"` (top-level non-table) — **DEFENDED**

`WHEREDNGN.lua:63-72` runs `ensureDB` on every PLAYER_LOGIN and
ADDON_LOADED:

```
if type(WHEREDNGNDB) ~= "table" then WHEREDNGNDB = {} end
for k, v in pairs(DEFAULTS) do
    if WHEREDNGNDB[k] == nil then WHEREDNGNDB[k] = v end
end
```

`State.lua:74` runs the same coercion at every `reset()`:

```
local DB = (type(WHEREDNGNDB) == "table") and WHEREDNGNDB or nil
```

A scalar at the root is silently replaced by an empty table populated
with defaults. **No crash, no leak.**

---

## ATK-2 — `WHEREDNGNDB.history = "junk"` (string-where-table) — **DEFENDED**

History append site `State.lua:1530-1532`:

```
if type(WHEREDNGNDB.history) ~= "table" then
    WHEREDNGNDB.history = {}
end
local h = WHEREDNGNDB.history
```

History dump site `Slash.lua:237-238`:

```
local h = WHEREDNGNDB.history
if type(h) ~= "table" then h = {} end
```

Per-row dump guard `Slash.lua:253` skips non-table rows:

```
if type(r) == "table" then
    print(("  r%-3d  %-4s  trump=%-1s ..."):format(...))
end
```

Both append and dump tolerate any garbage type at `history`. The
v0.9.2 #47 fix landed exactly this guard. **Defended.**

---

## ATK-3 — `WHEREDNGNDB.target = "100"` (string in numeric slot) — **DEFENDED**

Three reader sites all coerce:

`WHEREDNGN.lua:81` — `B.State.s.target = tonumber(WHEREDNGNDB.target) or 152`
`WHEREDNGN.lua:152-154` — `B.State.s.target = tonumber(WHEREDNGNDB.target) or B.State.s.target or 152`
`State.lua:75` — `s.target = (DB and tonumber(DB.target)) or 152`

The v0.9.0 L6 fix (audit AUDIT_REPORT_v0.7.1.md) landed all three
`tonumber()` coercions. A non-numeric string falls through to 152.
**Defended.**

---

## ATK-4 — `WHEREDNGNDB.target = -1` or `target = 0` — **PARTIAL**

`tonumber("-1")` returns `-1` and `tonumber("0")` returns `0`. The
slash-command setter at `Slash.lua:278-282` rejects values below 21:

```
local n = tonumber(tNum) or 0
if n < 21 then
    say("target must be at least 21 (Saudi sub-game minimum)")
    return
end
```

But the reader sites at `WHEREDNGN.lua:81/152` and `State.lua:75`
DO NOT range-check. A hand-edit to `target = 0` lets the next round-end
trip `cumulative.A >= 0` immediately (any non-negative score wins),
short-circuiting the game on the first scoring trick. The 8th-audit
fix (referenced in `Slash.lua:275`) explicitly noted this hazard but
fixed only the slash setter, not the readers. **Partial: input validation
gated on slash command, bypassed by hand-edit.**

A negative target (e.g. `target = -50`) similarly: `cum >= -50` is true
for any score after the first round.

---

## ATK-5 — `WHEREDNGNDB.teamNames = "junk"` (non-table where table expected) — **PARTIAL**

`State.lua:80-89` (reset path) type-checks correctly:

```
if DB and type(DB.teamNames) == "table" then
    if type(DB.teamNames.A) == "string" ...
```

**But `WHEREDNGN.lua:83-86` (PLAYER_LOGIN init path) does NOT:**

```
if WHEREDNGNDB.teamNames then
    B.State.ApplyTeamNames(WHEREDNGNDB.teamNames.A,
                           WHEREDNGNDB.teamNames.B)
end
```

Truthy guard only — a hand-edited `teamNames = "evil"` or
`teamNames = 5` passes the truthy check, then `.A` indexes into a
non-table:
- string `.A` returns `nil` (no string-library member named `A`),
  so `ApplyTeamNames(nil, nil)` — silently no-ops at line 165
  (`if teamA and teamA ~= ""`). Survives.
- number `.A` raises "attempt to index a number value"
  → addon load crashes mid-init. **`B.State.SetLocalName` at line 87
  never runs**, leaving `s.localName` nil for the subsequent
  `RestoreSession` call at line 141. Per the v0.9.2 #54 fix at
  `State.lua:307`, `RestoreSession` fails closed when localName is
  nil — so the cross-character leak is still defended downstream,
  but the addon is half-initialized: the minimap icon, prefix
  registration, and resync request pipeline at lines 132-311 all
  fall through to the post-`init()` line numbers without running.

**Recommend:** copy the `State.lua:80` pattern up to
`WHEREDNGN.lua:83`:

```
if type(WHEREDNGNDB.teamNames) == "table" then
    B.State.ApplyTeamNames(...)
end
```

**Partial — defended on string, undefended on number/boolean/userdata.**

---

## ATK-6 — `WHEREDNGNDB.teamNames = { A = string.rep("X", 1000), B = "Y" }` (overflow) — **DEFENDED at apply, UNDEFENDED at read**

`State.lua:165` clamps via `:sub(1, 20)`:

```
if teamA and teamA ~= "" then s.teamNames.A = teamA:sub(1, 20) end
```

ApplyTeamNames truncates to 20 chars on the way IN. The init flow at
`WHEREDNGN.lua:83-86` calls ApplyTeamNames, so the 1000-char string
gets truncated before landing in `s.teamNames`. **Defended for the
in-memory state.**

However, the reset() path at `State.lua:81-83` reads directly:

```
if type(DB.teamNames.A) == "string" and DB.teamNames.A ~= "" then
    tnA = DB.teamNames.A   -- NO sub(1,20) here
end
```

So a `/baloot reset` re-installs the full 1000-char string into
`s.teamNames.A` (it never goes through ApplyTeamNames in the reset
path). UI labels at `UI.lua:2829` then render the long string — frame
layout breaks visually (label overflows), but no functional crash.
Score-line writes `s.teamNames.A` to addon-message wire (`Net.lua:726`)
and may exceed 255-byte chat-message-prefix limits, causing
`SendAddonMessage` to error or drop. **Partial defense: in-memory
sanitized only on the apply path; reset path bypasses the clamp.**

---

## ATK-7 — `WHEREDNGNDB.session.state.cumulative = "[]"` (string-where-table nested) — **UNDEFENDED**

`State.lua:289-374` `RestoreSession` does not type-check
`sess.state.cumulative`. After `for k, v in pairs(sess.state) do s[k] = v end`
at line 314, `s.cumulative` becomes the string `"[]"`. The nil-init
fallback at line 338 (`s.cumulative = s.cumulative or { A = 0, B = 0 }`)
DOES NOT trigger because the string is truthy. Subsequent `s.cumulative.A`
reads then either:
- return nil (since string library has no `A`) — `Net.lua:1679`
  `S.s.cumulative.A + addA` crashes with
  "attempt to perform arithmetic on a nil value", OR
- `UI.lua:2054` `S.s.cumulative.A >= S.s.target` → "attempt to compare
  nil with number" (Lua 5.1 semantics).

Either way the host's first round-end after restore raises an error.
**Undefended.** The v0.9.2 #54 fix landed type-checks for `sess.bot.*`
sub-fields but not for `sess.state.*` sub-fields. The same pattern is
needed for `cumulative`, `tricks`, `bids`, `seats`, `meldsByTeam`,
`meldsDeclared`, `hand`, `contract`.

**Recommend:** insert table-type guards immediately after the
`for k, v in pairs(sess.state) do s[k] = v end` blanket copy:

```
if type(s.cumulative) ~= "table" then s.cumulative = { A = 0, B = 0 } end
if type(s.tricks)     ~= "table" then s.tricks     = {} end
if type(s.bids)       ~= "table" then s.bids       = {} end
if type(s.seats)      ~= "table" then s.seats      = { [1]=nil, [2]=nil, [3]=nil, [4]=nil } end
if type(s.contract)   ~= "table" and s.contract ~= nil then s.contract = nil end
if type(s.hand)       ~= "table" then s.hand       = {} end
if type(s.meldsByTeam) ~= "table" then s.meldsByTeam = { A = {}, B = {} } end
```

---

## ATK-8 — `WHEREDNGNDB.session.state.cumulative.A = 1e308` (numeric overflow) — **DEFENDED for arithmetic, PARTIAL for game-end**

Lua doubles handle 1e308. `Net.lua:1679`'s `S.s.cumulative.A + addA`
gives 1e308 — finite, no error. `UI.lua:2054` `S.s.cumulative.A >= S.s.target`
returns true, ending the game on the first scoring round.

`1e308 + 1e308 = 1.797e308` ≈ math.huge — but still finite, comparison
holds. `math.huge + math.huge = math.huge` — also finite-ish, comparison
holds. Only `0/0` (NaN) breaks comparison: `nan >= 152` returns false,
`nan < 152` also false — but `nan + 5` gives nan, propagating silently.

A hand-edited `cumulative.A = 0/0` (or the literal `nan` if the user
writes a Lua expression) would make the game un-winnable: every
`cum >= target` returns false, `cum + add` stays NaN, score display
shows `nan` in the UI label. No crash, but the game enters a permanent
"can't end" state. **Partial — no upper-bound or finite check.**

The v0.9.0 audit findings (e.g. `audit_v0.9.0/41_v083_telemetry.md`)
noted hand-edit safety only for `target`, not for `cumulative`.

---

## ATK-9 — `WHEREDNGNDB.session.state.tricks = "[]"` (string-where-array) — **UNDEFENDED**

Same path as ATK-7 — the blanket `pairs` copy at `RestoreSession:314`
overlays `s.tricks` with a string. `State.lua:344` then iterates:

```
for _, tr in ipairs(s.tricks or {}) do
    for _, p in ipairs(tr.plays or {}) do
        s.playedCardsThisRound[p.card] = true
    end
end
```

`ipairs("[]")` errors with "bad argument #1 to 'ipairs' (table expected,
got string)". RestoreSession crashes mid-rebuild, leaving `s.cumulative`
already overwritten (from the prior loop iteration) and the function
returning nothing — but PLAYER_LOGIN's `if B.State.RestoreSession()` at
`WHEREDNGN.lua:141` evaluates the error as falsy (well, the error
propagates, killing the whole event handler). **Undefended.**

Same fix as ATK-7 — table-type-check sub-fields after the bulk copy.

---

## ATK-10 — Recursive / cyclic table — **PARTIAL**

A user writes `WHEREDNGNDB.session = { state = {} }; WHEREDNGNDB.session.state.self = WHEREDNGNDB.session.state` (cycle).

WoW's SavedVariables serializer DOES detect cycles and error on save —
but on hand-edit the file is consumed by Lua's normal loader, which
can construct cycles via local variables in the saved-variables file:

```
local t = {}; t.self = t; WHEREDNGNDB = { session = { state = t } }
```

This loads cleanly. `RestoreSession`'s `for k, v in pairs(sess.state)` at
line 314 doesn't recurse — it's a shallow copy — so the cycle is
preserved into `s` but not expanded. Most consumers don't recurse
either. The exception: `SaveSession` at `State.lua:258` does
`for k, v in pairs(s)` shallow-copy — `s.self = s` would survive into
`snap.self = s` (still the same table), then WoW's serializer at
PLAYER_LOGOUT errors trying to write the cycle. **Partial:** RestoreSession
tolerates cycles but the next SaveSession at logout fails to persist
ANY state — so progress made in the restored game is silently lost
on next /reload.

Lua's deep-copy isn't used anywhere here. No crash on read, but a
saved-variables write failure on the next logout. Difficult to detect
without instrumentation.

---

## ATK-11 — Hand-injected impossible card "ZZ" or duplicate card — **UNDEFENDED at the persistence layer**

A user injects `WHEREDNGNDB.session.state.hand = { "ZZ", "AS", "AS" }`
(invalid rank+suit, plus duplicate Ace of Spades).

`State.lua:333` `s.hand = s.hand or {}` — type-check absent (sub-field
of state). `Cards.lua:97` validates per-card via `K.RANK_INDEX[card:sub(1, 1)]`
but only at play time. The hand is not validated on restore.

Downstream: bot decision logic iterates `s.hand` in `pickFollow` at
many sites. `card:sub(1, 1)` on "ZZ" returns "Z" → `K.RANK_INDEX["Z"]`
is nil → various scoring functions return 0 (default-coerce). UI
renders a missing-glyph card art (since `K.SUIT_DISPLAY` lookup is
nil-safe per `Cards.lua:190` audit fix). `localPlay` of "ZZ" sends
malformed wire data; remote host's parse silently fails or hangs.

Duplicate "AS" in the hand: deck integrity broken, but no validation
at restore. The host's `HostValidatePlay` enforces "card must be in
that seat's hand" — passes for both copies. The trick-1 winner gets
two Ace-of-Spades plays in sequence; subsequent trick scoring may
double-count.

**Undefended.** The trust assumption documented at `State.lua:13`
("friendly play, no cheating client modification") accepts this for
WIRE input. But hand-edits are the user attacking THEIR OWN client —
the attack surface here is the user shooting themselves in the foot
mid-restore (or attacking the host they joined with a corrupted
client). **No restore-time validation of card identifiers in hands or
trick history.**

---

## ATK-12 — `WHEREDNGNDB.advancedBots = "yes"` (string-where-boolean) — **DEFENDED**

`Bot.lua:48-79` checks `== true` for every tier flag:

```
return WHEREDNGNDB
   and (WHEREDNGNDB.advancedBots == true
        or WHEREDNGNDB.m3lmBots == true
        or WHEREDNGNDB.fzlokyBots == true
        or WHEREDNGNDB.saudiMasterBots == true)
```

String "yes" is not `== true`. The tier silently turns OFF (basic
random-legal play). No crash, behaviour falls through to safe default.
**Defended.**

The same pattern holds for `Net.lua:1533, 2477, 2488, 2645, 2819` —
all use `== false` / `~= false` against the boolean-default flags.
A string "no" is `~= false` so SWA stays enabled (matches the default).

---

## ATK-13 — `WHEREDNGNDB.session.bot.partnerStyle = "corrupt"` — **DEFENDED**

`State.lua:363-373` per the v0.9.2 #54 fix:

```
if type(sess.bot.partnerStyle) == "table" then
    B.Bot._partnerStyle = sess.bot.partnerStyle
end
if type(sess.bot.memory) == "table" then
    B.Bot._memory = sess.bot.memory
end
if type(sess.bot.r1WasAllPass) == "boolean" then
    B.Bot.r1WasAllPass = sess.bot.r1WasAllPass
end
```

Each subfield is type-checked. A string in `partnerStyle` is silently
ignored — `Bot._partnerStyle` keeps its current value (or stays nil,
which `Bot.OnEscalation` rebuilds via the `if not Bot._partnerStyle`
guard). **Defended.**

---

## ATK-14 — Cross-character session leak (v0.9.2 #54 fail-closed) — **DEFENDED**

`State.lua:307-308`:

```
if not sess.owner or not s.localName then return false end
if sess.owner ~= s.localName then return false end
```

The fix-form is fail-closed: BOTH sides must be present and match.
Verified the call ordering at `WHEREDNGN.lua:75-89,141`:

```
init()                                           -- line 131 calls init()
  ensureDB()                                     -- line 76
  s.target = ...                                 -- line 81
  if WHEREDNGNDB.teamNames then ApplyTeamNames(...) end   -- line 83
  B.State.SetLocalName(GetUnitName("player", true))       -- line 87 ★
end
if B.State.RestoreSession() then                 -- line 141
```

`SetLocalName` runs at line 87 BEFORE `RestoreSession` at line 141.
`s.localName` is set when RestoreSession evaluates the guard. The
fail-closed predicate works. **Defended.**

(One residual edge: if `GetUnitName("player", true)` returns nil at
PLAYER_LOGIN — pre-PLAYER_ENTERING_WORLD timing — `s.localName` stays
nil and ALL restores are rejected, even legitimate same-character ones.
The PEW handler at line 308 re-sets the name on world load. The session
is then lost (never restored on this login). Conservative; matches the
fail-closed intent. Not a leak.)

---

## ATK-15 — `WHEREDNGNDB.session = { state = nil }` (state field absent) — **DEFENDED**

`State.lua:309` `if not sess.state then return false end`. Empty or
missing `state` rejects the restore cleanly. **Defended.**

---

## ATK-16 — Bot module state strictly-extends gap on hand-edit-revert — **PARTIAL** (overlap with audit_v0.9.0/54 #2)

Audit `54_m4_partnerstyle_quirks.md §2` flagged: `_partnerStyle` is
seat-keyed, not name-keyed. A hand-edited
`WHEREDNGNDB.session.state.seats[2].name = "OldFriend"` (when the
current seat 2 is actually "NewPlayer") leaves `_partnerStyle[2]` with
OldFriend's accumulated Bel/Triple/Four counts misapplied to NewPlayer
for the rest of the game. Restore at `State.lua:363-365` accepts the
table type, but cross-validates nothing against the actual roster.

This is exactly the audit_v0.9.0/54 §2 finding restated as a hand-edit
attack. The mitigation proposed there ("persist `{seat, name}` pairs and
remap on restore") would close this hole. **Partial — type defended,
semantic not defended.**

---

## ATK-17 — Junk `WHEREDNGNDB.lastGameID` (resync request to nonexistent game) — **DEFENDED**

`WHEREDNGN.lua:101-112`:

```
if not WHEREDNGNDB then return end
local id = WHEREDNGNDB.lastGameID
if not id or id == "" then return end
if not IsInGroup() then return end
if B.State.s.isHost then return end
L.Info("resync", "requesting state for game %s", id)
if B.Net and B.Net.SendResyncReq then
    B.Net.SendResyncReq(id)
end
```

A hand-edited junk `lastGameID = "EVIL_PAYLOAD"` triggers a
`SendResyncReq("EVIL_PAYLOAD")`. The wire format is a fixed-width
string, so length is bounded by Net's encoder. Recipient hosts see a
gameID that doesn't match any known game, return nothing. No leak,
no crash. **Defended at the protocol layer.** A non-string lastGameID
(number) — `id == ""` is false, the call proceeds with a non-string
arg, `SendResyncReq(123)` may concat-into-string at the encoder
(silent coerce). Worth a closer look at Net's encoder, but no obvious
crash path here.

---

## ATK-18 — `WHEREDNGNDB.framePos = "junk"` — **NOT REVIEWED IN DEPTH**

Defaulted to `nil` at `WHEREDNGN.lua:18`. The UI's frame-position
restore would need a separate audit. Out of scope for this red-team —
flag for D-RT-15+ if frame-position attack is in scope.

---

## Summary table

| Attack | Verdict |
|---|---|
| ATK-1 root non-table | DEFENDED |
| ATK-2 history non-table | DEFENDED |
| ATK-3 target string | DEFENDED |
| ATK-4 target ≤ 0 / negative | PARTIAL |
| ATK-5 teamNames non-table (PLAYER_LOGIN path) | PARTIAL |
| ATK-6 teamNames overflow (1000-char) | PARTIAL |
| ATK-7 cumulative string-where-table | UNDEFENDED |
| ATK-8 cumulative 1e308 / NaN | PARTIAL |
| ATK-9 tricks string-where-array | UNDEFENDED |
| ATK-10 recursive / cyclic table | PARTIAL |
| ATK-11 impossible / duplicate card | UNDEFENDED |
| ATK-12 bot-flag string-where-boolean | DEFENDED |
| ATK-13 bot.partnerStyle string | DEFENDED |
| ATK-14 cross-character leak | DEFENDED |
| ATK-15 missing state field | DEFENDED |
| ATK-16 seat-keyed bot state stale | PARTIAL |
| ATK-17 junk lastGameID | DEFENDED |
| ATK-18 framePos | NOT REVIEWED |

---

## Concrete patch recommendations

In priority order:

**P1 — `RestoreSession` sub-field type guards** (ATK-7, ATK-9 close the
biggest crash-on-restore surface):

```lua
-- Insert after State.lua:339 ('s.seats = s.seats or ...')
if type(s.cumulative)   ~= "table" then s.cumulative   = { A = 0, B = 0 } end
if type(s.tricks)       ~= "table" then s.tricks       = {} end
if type(s.bids)         ~= "table" then s.bids         = {} end
if type(s.hand)         ~= "table" then s.hand         = {} end
if type(s.meldsByTeam)  ~= "table" then s.meldsByTeam  = { A = {}, B = {} } end
if type(s.meldsDeclared) ~= "table" then s.meldsDeclared = {} end
if s.contract ~= nil and type(s.contract) ~= "table" then s.contract = nil end
-- Numeric coercions for the critical comparison fields
s.cumulative.A = tonumber(s.cumulative.A) or 0
s.cumulative.B = tonumber(s.cumulative.B) or 0
```

**P2 — `WHEREDNGN.lua:83` teamNames type-check** (ATK-5):

```lua
if type(WHEREDNGNDB.teamNames) == "table" then
    B.State.ApplyTeamNames(WHEREDNGNDB.teamNames.A,
                           WHEREDNGNDB.teamNames.B)
end
```

**P3 — Target range-check at reader** (ATK-4):

```lua
-- WHEREDNGN.lua:81 / 152, State.lua:75 — replace `tonumber(...) or 152` with:
local t = tonumber(WHEREDNGNDB.target)
B.State.s.target = (t and t >= 21) and t or 152
```

**P4 — `State.lua:81-83` reset-path teamName clamp** (ATK-6):

Apply `:sub(1, 20)` consistently with `ApplyTeamNames`.

**P5 — Restore-time card validation** (ATK-11): on restore, walk
`s.hand` and `s.tricks[].plays[].card`, drop entries that fail
`Cards.IsValid` (assuming such a helper exists or wrap `Cards.lua:97`).
Lower priority than the table-type guards because the failure is
slow-burn (visible on next play attempt) rather than crash-on-restore.

---

## Out of scope / follow-ups

- Frame-position struct type validation (ATK-18).
- `WHEREDNGNDB.session.bot.partnerStyle.<seat>.tahreebSent.<suit>` deep
  hand-edit (string-where-table at depth 4) — audit_v0.9.0/54 §4 noted
  this; restore type-checks `partnerStyle` only at depth 1.
- Wire-level injection (D-RT-15 covers malformed wire); this report
  is purely the local-client persistence-file attack surface.
