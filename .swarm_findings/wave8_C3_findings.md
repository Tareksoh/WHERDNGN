## Wave 8 — C3 Partner Coordination Batch B Findings (v0.4.4)

---

### B-83 — Gahwa failure outcome not tracked; no "reckless" tag

**SIGNAL/MISTAKE:** The `_partnerStyle` ledger (Bot.lua:136–151) records `gahwas` as a pure call counter incremented in `Bot.OnEscalation` (Bot.lua:162–171) only when `kind == "gahwa"`. `OnEscalation` is wired in Net.lua:873 inside `_OnGahwa`, which fires only when a Gahwa call is *accepted* — i.e., at the moment of escalation decision, before any tricks are played. There is no hook into `S.ApplyRoundEnd` (State.lua:1251) or `S.ApplyRoundResult` (State.lua:1280) that records whether the Gahwa contract was subsequently won or lost. The `lastRoundResult` and `bidderMade` data that would be needed to identify a "reckless Gahwa" exist (State.lua:1251 receives `bidderMade`; Net.lua:264 broadcasts it), but nothing in Bot.lua reads them to tag the calling seat.

**FREQUENCY:** Every Gahwa escalation. The counter always increments; failure never increments a separate counter or applies a behavioural tag.

**BOT-EXPLOITS-IT:** No. The current code does not read `gahwas` anywhere downstream to influence play decisions (styleBelTendency and styleTrumpTempo are the only derived metrics and neither references `gahwas`). The gap is a future-use risk: if a `styleGahwaTendency` heuristic is added later, it will overweight reckless callers as "bold" rather than "reckless."

**FILE:LINE:** Bot.lua:127–171 (emptyStyle / OnEscalation), State.lua:1251 (ApplyRoundEnd), Net.lua:864–875 (_OnGahwa)

**FIX:** Add a `gahwaFailed` counter to `emptyStyle`. Wire a new `Bot.OnRoundEnd(bidderMade)` callback from `S.ApplyRoundEnd` / `N._OnRound`. When `bidderMade == false` and the round's contract had `.gahwa == true`, increment `gahwaFailed` for `contract.bidder`. A derived metric `styleGahwaReckless` can then gate on `gahwaFailed / gahwas > 0.5` before trusting that seat's future Gahwa calls.

---

### B-85 — Human "natural" trump-back lead not modelled as a miscoordination signal

**SIGNAL/MISTAKE:** The `trumpEarly` counter in `_partnerStyle` (Bot.lua:130, 246–254) tracks trump LEADS before trick 5 for all seats, but it is populated regardless of context: it fires whether the leading seat is the bidder, bidder's partner, or a defender. The bot never uses this counter to distinguish a human partner's naive "lead back the bid suit" behaviour (bidder called Hokm-S, partner immediately leads a spade) from a coordinated trump-pull by the bidder themselves. There is no code that checks "did my partner lead trump on trick 1 or 2 and does that correlate with them not holding J/9 of trump (i.e., they don't know what they're doing)?"

**FREQUENCY:** Every time an advanced-or-higher bot evaluates a partner trump lead in tricks 1–4. The counter accumulates but no decision path reads it in the context of partner-is-human-or-inexperienced.

**BOT-EXPLOITS-IT:** No directly. `styleTrumpTempo` (Bot.lua:189–196) is defined but marked "currently unused by the picker code" (Bot.lua:178). Even if it were used, it conflates aggressive tempo (informed) with naive trump-back (uninformed).

**FILE:LINE:** Bot.lua:178–196 (styleTrumpTempo defined but unused), Bot.lua:246–254 (trumpEarly accumulation), pickLead Bot.lua:720–892 (no partner-lead-context check)

**FIX:** Either (a) gate `styleTrumpTempo` reads in `pickLead` so a partner with high `trumpEarly` causes the bot to avoid leading side suits that need partner to ruff (since partner burns trump early), or (b) in M3lm tier, add a `naiveTrumpBack` flag when a non-bidder partner leads trump in tricks 1–2 without the bot having observed a forced void — this distinguishes convention from ignorance. Neither fix is present.

---

### B-86 — AKA UI is sound + banner; banner IS present but lacks explicit plain-language partner instruction

**SIGNAL/MISTAKE:** `S.ApplyAKA` (State.lua:1231–1238) fires the voice cue (`K.SND_VOICE_AKA` = `"إكَهْ"`) AND sets `s.akaCalled`. `renderAKABanner` (UI.lua:2726–2747) reads `s.akaCalled` and displays a banner text of the form `"AKA ♥ — PlayerName"`. The display uses Latin "AKA" because WoW's bundled fonts can't render the Arabic glyphs (UI.lua:2723–2724 comment). The banner shows *who called* and *which suit*, but does not display an explicit directive to the human partner such as "do not over-trump Hearts." The action button label is just `"AKA ♥"` (UI.lua:1688) with no tooltip or further explanation.

**FREQUENCY:** Any game where a human player hasn't played before and doesn't know the Baloot AKA convention. Recurring every time a teammate calls AKA.

**BOT-EXPLOITS-IT:** Not directly. The gap hurts human coordination, not bot strategy. A confused human partner who over-trumps anyway is exploitable by opponents (the over-trump wastes the human's trump, weakening the team), but the bot does not currently model "partner ignored my AKA" as a signal to change play strategy.

**FILE:LINE:** UI.lua:2726–2747 (renderAKABanner — no instruction text), UI.lua:1679–1690 (action button label, no tooltip), State.lua:1231–1238 (ApplyAKA — sound + state only)

**FIX:** Extend the banner text from `"AKA ♥ — Name"` to `"AKA ♥ — Name (boss suit — don't over-trump)"` or a shorter equivalen. Optionally add a GameTooltip on the AKA action button explaining the convention to new players. This is a pure UI addition with no logic change required.

---

### B-87 — Fzloky firstDiscard signal is sent to ALL partners regardless of whether they are bots or humans

**SIGNAL/MISTAKE:** `pickLead` in Bot.lua (lines 747–773) reads `Bot._memory[partner].firstDiscard` and derives `fzlokyPrefSuit` / `fzlokyAvoidSuit` unconditionally whenever `Bot.IsFzloky()` returns true. There is no gate on whether the *partner seat* is a bot (`s.seats[partner].isBot`) or a human. If the human partner is in the game and the bot discards a high card (A/T/K) in its first off-suit play, the bot internally records this as a "lead this suit" signal — but the bot has NO mechanism to communicate that convention to the human partner, and in standard Saudi Baloot the high discard is NOT a universally understood suit-preference signal (it is an advanced Fzloky convention). The human partner will typically interpret a high discard as "I have these cards here" or simply play their own hand without reading a signal.

Conversely, the bot reads the human partner's first discard as a Fzloky signal (Bot.lua:748–758, `sig = Bot._memory[p] and Bot._memory[p].firstDiscard`). A human who throws a high card because they are discarding from strength — not signalling — will cause the bot to lead into that suit unnecessarily.

**FREQUENCY:** Every hand at Fzloky or SaudiMaster tier where at least one seat is human. This includes any mixed human-bot game at those tiers.

**BOT-EXPLOITS-IT:** Yes, in the sense that an opponent bot can read the *human's* unintentional "signal" and calibrate accordingly — but more critically the bot partner mis-plays because it trusts a signal the human never intended to send. An opponent who knows this tier is active could discard high from a weak suit to draw the bot partner into a losing lead.

**FILE:LINE:** Bot.lua:747–773 (fzlokyPrefSuit/fzlokyAvoidSuit read, no isBot gate), Bot.lua:101–112 (firstDiscard field in emptyMemory), Bot.lua:217–226 (firstDiscard assignment in OnPlayObserved)

**FIX:** In `pickLead`, gate the Fzloky signal read on `S.s.seats[p] and S.s.seats[p].isBot`. Only interpret `firstDiscard` as a suit-preference signal when the partner is another bot. When the partner is human, skip the Fzloky preference pass entirely. Similarly, the reverse (bot sends Fzloky signal to human) is moot since the signal is implicit in the card played, but a UI tooltip or in-game explanation could help advanced human partners opt in.

---

### B-88 — No per-seat rank-sequence tracking; echo (high-then-low attitude signal) is invisible to the bot

**SIGNAL/MISTAKE:** `Bot._memory[seat]` (Bot.lua:97–116) stores: `void` map, `played` map (card-keyed set, Bot.lua:204), `firstDiscard`, and `akaSent`. The `played` set uses the full card string as key (e.g., `"AS"`) and records presence but not order. There is no structure that tracks the *sequence of ranks played by a seat in the same suit across multiple tricks*, which is the prerequisite for detecting the echo convention (play 8♥ trick 3, then 7♥ trick 5 = attitude signal for hearts).

**FREQUENCY:** Every hand. The absence is a structural gap, not a conditional branch.

**BOT-EXPLOITS-IT:** No — the bot cannot detect an echo it doesn't track, so human echo signals are ignored. This is a missed-opportunity gap rather than an active exploit. An opponent who knows the bot can't read echoes could play echo-style as a form of deceptive reverse signal (play high-low in a suit they DON'T want led), but the current bot will not misread it either — it simply ignores rank sequence entirely.

**FILE:LINE:** Bot.lua:97–116 (emptyMemory — no rankOrder or suitPlays-by-trick structure), Bot.lua:200–269 (OnPlayObserved — only firstDiscard and void are derived from rank)

**FIX:** Add a `suitPlays` field to the per-seat memory: `suitPlays = { S = {}, H = {}, D = {}, C = {} }` where each list appends `{rank, trickNum}` on every observed play. In M3lm or SaudiMaster tier, a helper can scan a partner seat's `suitPlays[suit]` for a high-then-low descending pair across consecutive tricks in the same suit to flag an echo. This would let the bot recognise human advanced partners who use the convention and not over-trump or lead into their signalled suit unnecessarily.

---

*Findings authored: 2026-05-03. No code was modified.*
