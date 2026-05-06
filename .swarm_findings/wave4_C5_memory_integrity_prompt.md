### A-78 — AKA signal: K.MSG_AKA sent in Net.lua — does bot AKA affect pickLead?

Audit whether Bot.PickAKA is connected to the lead card choice. PickAKA is called AFTER pickLead determines the lead card (it's called with the already-chosen leadCard). Verify: does the AKA signal back-propagate to affect the lead decision, or is it purely a communication signal to the partner? If the bot leads a non-boss card but PickAKA returns non-nil, there may be a logic inconsistency.

### A-82 — ResetMemory timing: called by Net.lua — verify call site

Audit where Bot.ResetMemory() is called relative to the start of each round. It must be called BEFORE any OnPlayObserved calls for the new round. Verify: if the host processes deal3 (second deal) before calling ResetMemory, the new-round plays could corrupt the old-round memory. Check Net.lua's round-start flow.

### A-83 — ResetStyle timing: called by Reset() / new game

Inspect Bot.ResetStyle (line ~149-151). It resets the per-seat style counters. This happens on game reset (not round reset). Verify: is this the correct granularity? The comment says "accumulated ACROSS the entire GAME." Confirm that round-resets do NOT call ResetStyle — the style ledger should persist across rounds to be useful.

### A-86 — mem.played tracking: includes own cards and all observed plays

Audit whether `mem.played[card] = true` is set for all four seats' played cards in OnPlayObserved. Since OnPlayObserved is called with `seat` and `card`, each call adds to that specific seat's played set. Verify: suitCardsOutstanding iterates all 4 seats' `mem.played` tables to get the total played count — confirm this loop correctly accounts for the calling seat's own plays.

### A-90 — S.s.meldsByTeam structure compatibility with meldPins (BotMaster)

Inspect the meldPins build (BotMaster lines ~162-177). It accesses `S.s.meldsByTeam[team]` with team in {"A","B"}, and iterates melds expecting `m.declaredBy` and `m.cards`. Audit State.lua to verify the actual structure of meldsByTeam — does it store melds as {cards=..., declaredBy=...} or a different schema? A schema mismatch would silently skip all pins.
