# Changelog

## v0.1.30 — SWA scoring rebuilt, takweesh simplified

**SWA scoring fix (HIGH severity)**
- `HostResolveSWA` was awarding `handTotal × mult` to the winning
  side and 0 to the other regardless of how many tricks were
  played. Already-earned trick points evaporated, the kaboot
  bonus never applied, the last-trick +10 was missing.
- Now: VALID SWA synthesizes the remaining tricks (each won by
  caller seat), appends to played-trick history, and routes
  through `R.ScoreRound`. ScoreRound handles sweep / made /
  failed / meld winner / last-trick bonus / belote correctly
  by construction.
- INVALID SWA still applies the flat penalty: opp takes
  handTotal × mult + ALL melds × mult + belote.
- Sweep is now detected when caller's team has won every played
  trick AND wins all remaining via SWA → kaboot bonus
  (250 / 220 raw) applies via the same ScoreRound path.

**Takweesh scoring simplified**
- Dropped the made/failed mapping introduced in v0.1.28 — both
  branches of takweesh are punitive penalties to the same shape.
- Now: caught → caller's team takes handTotal × mult + ALL
  melds × mult + belote. Not-caught → opp-of-caller takes the
  same. Single code path, no contract-result inversion.

## v0.1.29 — belote tightened to "K+Q played", SWA/takweesh docs

**Fix (Saudi rule, rb3haa)**
- Belote (+20 raw) now requires the K AND Q of trump to BOTH be
  played before the round ends. v0.1.27/v0.1.28 had been scanning
  unplayed hands too — that's wrong: per Saudi convention, belote
  must be announced as the cards are played. If a takweesh or SWA
  ends the round before K+Q both surface, no belote bonus.
- Applies to both `HostResolveSWA` and `HostResolveTakweesh`.

**Documentation**
- `HostResolveSWA` doc-comment now flags the made/failed contract
  mapping as a HOUSE-RULE NORMALIZATION. The published Saudi
  sources don't fully specify a meld/belote formula for SWA —
  our mapping (valid+bidder→MADE etc.) is a defensible synthesis
  but isn't a verbatim attested rule.

## v0.1.28 — takweesh scoring respects melds + belote

**Fix (same shape as v0.1.27)**
- `HostResolveTakweesh` had the identical bug as the pre-v0.1.27
  SWA path: awarded only `handTotal × multiplier` and ignored
  meld points + belote. A defender team could win a takweesh
  while ALSO holding 100-point carrés and K+Q-of-trump and still
  drop those points.
- Now routes through the standard made/failed branches:
  - Caught + caller is bidder team OR not caught + caller is
    defender team → MADE: bidder team takes hand × mult, meld
    winner gets their melds × mult.
  - Caught + caller is defender team OR not caught + caller is
    bidder team → FAILED: opp-of-bidder takes hand × mult AND
    all declared melds combined × mult.
- Belote +20 raw flows independently to its K+Q-of-trump holder.
  Takweesh ends the round mid-trick, so we scan unplayed hands
  too (same fix shape as SWA's belote scan).
- Audit also confirmed: regular ScoreRound has no early-end path
  to worry about (always runs at #tricks ≥ 8 when all cards are
  played); Kawesh has no scoring path (annul + redeal); game-end
  tie-rule is consistent across all three scoring paths;
  Ashkal-shifted bidder is correctly read everywhere; bot meld
  lock is enforced in both human and bot paths.

## v0.1.27 — SWA scoring respects melds + belote

**Fix**
- SWA was awarding only `handTotal × multiplier` to the winning
  side, ignoring meld points and belote. A team with 400 worth of
  melds could lose because the opposing team called SWA — wrong
  per Saudi rules.
- `HostResolveSWA` now routes through the same made/failed
  scoring branches as a regular round:
  - **Made** (caller's claim valid AND caller is on bidder team):
    bidder team takes `handTotal × mult`. Meld winner (per
    `R.CompareMelds`) gets their melds × mult.
  - **Made** (caller's claim invalid AND caller is on defender
    team): same — defender's false claim hands the contract back
    to the bidder.
  - **Failed** (caller valid + defender, OR caller invalid +
    bidder): opposing team takes `handTotal × mult` AND ALL
    declared melds combined × mult — same rule the regular
    `ScoreRound` uses for a busted contract.
- Belote (+20 raw, Hokm only) flows to the K+Q-of-trump holder
  regardless of SWA outcome. SWA can end the round before K+Q
  are played; we scan unplayed hands so the holder still gets
  the bonus per Saudi convention.

## v0.1.26 — round-2 Sun overcall, "wla" pass label

**Saudi rule fix: round 2 has a Sun overcall window**
- Previously round 2 was "first non-pass wins" — seat 3's Hokm bid
  resolved bidding immediately, robbing seat 4 (and any later
  seats) of their chance to bid Sun.
- Now both rounds wait for all 4 bids, and Sun overcalls Hokm in
  either round. Hokm-vs-Hokm in round 2 still uses first-non-pass
  ordering. Sun-vs-Sun: first direct Sun locks (same as round 1).
- Round-2 Hokm-on-flipped-suit drop and Ashkal silently-dropped
  paths still apply.

**UX**
- Pass button in round 2 now labelled "wla" (ولا) to match the
  Saudi verbal convention. Confirms an existing bid or opens a
  redeal if all 4 say wla.

## v0.1.25 — SWA full minimax, last-trick visibility, Fzloky tier

**SWA validation upgraded to full minimax**
- Previous "sufficient condition" check rejected valid claims like
  `[A♠ A♦ T♦]` in Sun (lead A♠ → A♦ → T♦, all wins) because it
  couldn't see that T♦ becomes the boss after A♦ is played.
- Now `R.IsValidSWA` runs a recursive minimax over the remaining
  game tree: caller's team picks plays cooperatively, opponents
  pick adversarially, and the claim is valid iff caller can
  guarantee winning every remaining trick. Bounded by hand size
  so worst-case ~ thousands of nodes — fine for a one-time check.
- "Caller wins" still means trick winner == caller seat (strict
  reading; partner taking a trick doesn't satisfy the claim).

**Last-trick peek now shows all 4 plays everywhere**
- The peek button could show only 2–3 cards on non-host clients
  because `MSG_TRICK` arrived before the 4th `MSG_PLAY` and the
  trick-end snapshot captured a partial trick.
- `MSG_TRICK` now carries the full trick payload (leadSuit + all
  4 seat/card pairs). `_OnTrick` rebuilds `s.trick.plays` from
  the snapshot before applying trick-end, so `s.lastTrick` is
  always complete regardless of inter-sender ordering.

**Fzloky tier (signal-aware bots)**
- New checkbox below M3lm. Slash: `/baloot fzloky`.
- Tier cascade: `Fzloky → M3lm → Advanced`. Each lower tier is
  auto-checked-and-disabled when a higher one is on.
- Fzloky reads partner's first off-suit discard as a high/low
  suit-preference signal and biases lead choice accordingly:
  - Partner discards A/T/K → bot prefers leading that suit
    (lowest card from it; partner has the high cards).
  - Partner discards 7/8 → bot avoids leading that suit unless
    no alternative exists.
- v1 covers first-discard signaling only. Echo / petite-grand
  peter / "throw the king" are still future work.

## v0.1.24 — SWA claim, carré tie-break, M3lm UX polish

**New: SWA (سوا) claim mechanic**
- New action button "SWA" next to TAKWEESH during play. Confirm
  once before sending.
- Caller reveals their remaining hand; host validates via
  `R.IsValidSWA` (sufficient condition: every caller card is
  the current "boss" of its suit, plus a Hokm trump-count
  guarantee against forced ruffs).
- Outcome:
  - **Valid** → caller's team takes the full hand × multiplier
    (same shape as a made contract — caller proved dominance).
  - **Invalid** → opposing team takes the full hand × multiplier
    (same penalty as a failed takweesh).
- Wire: `MSG_SWA = "Q"` (caller→host with hand reveal),
  `MSG_SWA_OUT = "Z"` (host→all with verdict + scoring).
- Banner: green "SWA!" on success, red "SWA failed" on bust;
  takes priority over the normal score breakdown.

**Saudi rule fix: carré tie-break**
- Equal-value carrés (e.g. K-carré vs J-carré, both 100 raw)
  now break by the trick-rank of the top card. Trump-J carré
  beats trump-Q carré in Hokm; Aces in Sun beat anything else
  by raw value already. Bonus is small (×0.01) so it can't
  flip carré-vs-sequence comparisons.

**Saudi rule fix: bot meld lock**
- `Bot.PickMelds` now respects the trick-1 declaration window
  the same way `S.GetMeldsForLocal` does. Previously bots could
  declare melds in trick 2+ via the bot-auto-meld loop in
  Net.lua. Closes a rule-bypass.

**M3lm UX polish**
- Lobby Advanced checkbox auto-checks and disables when M3lm
  is on, signalling visually that M3lm strictly extends Advanced.
- Tooltip clarifies "stack with Advanced for full effect" was
  redundant — now reads as a single-pick tier system.

**Defensive cleanup**
- `LocalSWA` clears any stale `swaResult` banner from earlier
  in the round before broadcasting.

## v0.1.23 — M3lm tier, audit fixes, banner copy

**M3lm (pro) bot tier — host opt-in, stacks with Advanced**
- Lobby checkbox is now functional (was greyed in v0.1.20).
- New slash: `/baloot m3lm` toggles the flag.
- Adds three new layers on top of Advanced:
  - **Partner / opponent play-style modeling**: per-seat counters
    (`bels`, `trumpEarly`, `trumpLate`) accumulate across a full
    game so the bot can read each player's tendencies. Reset only
    on round 1 of a new game.
  - **Match-point urgency**: finer-grained threshold modifier
    layered on top of Advanced's `scoreUrgency` — opponent ≥
    target-15 → extra −8 (defensive desperation), opponent ≥
    target-40 → extra −3 (caution), we ≥ target-15 → extra +5
    (lock it down), behind 50–80 → extra −3 (measured risk).
  - **Coordinated escalation**: `partnerEscalatedBonus` adds to
    escalation strength when partner has already Beled / Tripled
    in the current contract. Defender chain (Bel/Triple/Gahwa)
    rewards escalating partners with +5/+8/+12; bidder chain
    (Bel-Re/Four) rewards bidder partners with +5/+8.
- Net.lua hooks `Bot.OnEscalation(seat)` from
  `_OnDouble/_OnRedouble/_OnTriple/_OnFour/_OnGahwa` so the
  partner-style ledger updates from network events too (covers
  remote players as well as bots).
- `Bot.IsAdvanced()` now returns true if EITHER advancedBots OR
  m3lmBots is set — M3lm strictly extends Advanced.

**Saudi rules audit fixes**
- Meld declaration window closes at end of trick 1 (Pagat-strict).
  Previously a player could still declare during trick 2 if they
  hadn't yet played their first card. `S.GetMeldsForLocal` now
  returns empty once `#s.tricks >= 1`.
- Game-end ties now go to the bidding team (Saudi convention)
  instead of Team A by default. Affects both
  `_HostStepAfterTrick`'s round-end branch and
  `HostResolveTakweesh`'s game-end branch.

**Copy**
- Game-end banner: "GAME OVER" → "8amt!! go play something else".

## v0.1.22 — only winning team reveals in trick 2

**Fix**
- Trick-2 card reveal is now gated to declarers on the **winning
  team only**, per Saudi rule (Pagat-cited): "the opposing team are
  not allowed to show or score for any projects." Losing team's
  cards are never exposed, even though their trick-1 announcement
  still happens.
- Both teammates on the winning team can still reveal — each gets
  their own 5-second window when their PLAY turn opens in trick 2.
- Trick-1 announcement text remains unchanged: every declarer's
  type/length/top-rank still posts (verbal declaration is public
  by everyone), suit still hidden.
- Ties (or no melds) → neither team reveals. Matches the scoring
  side, which already awards 0 to both on a tie.

## v0.1.21 — meld display rule corrected

**Fix**
- Trick 1 now shows only an announcement text — type, length and top
  rank, *no suit and no cards* ("Seq3 K (20)", "Carré J (100)"). The
  full mini-card strip is no longer flashed during trick 1.
- Trick 2: each declarer's actual cards become visible for exactly
  5 seconds when their PLAY turn starts, then hide for the rest of
  the hand. Hooked into `S.ApplyTurn` rather than `S.ApplyPlay` —
  so the timer starts with the turn, not after the play.
- Trick 3 onwards: nothing is shown. Earlier trick-1-always-visible
  behaviour was an over-broad reading of the Saudi rule; this
  release matches the table convention (announce in trick 1, brief
  reveal in trick 2, gone after).

## v0.1.20 — Advanced bot heuristics (host opt-in)

**New**
- Lobby checkboxes: **Advanced** (functional) and **M3lm**
  ("master", greyed out — reserved for a future deeper-heuristic
  layer with multi-trick lookahead and signal interpretation).
- Slash command: `/baloot advanced` toggles the host's advanced-bot
  flag.
- Default is OFF on upgrade — existing bot behaviour is unchanged
  unless the host explicitly turns Advanced on.

**Advanced-mode heuristics (Tier 1 + 2 + 3 from the bot research
agents):**

*Bidding*
- Hand evaluation: J+9 synergy bumped from +10 to +18 (Coinche
  step-jump). J-of-trump step-function damp — no-J + no 9+A pair
  + count<5 trump suit gets 0.4× score (structurally weak).
- Side-suit aces fold into Hokm strength (+8 each, capped at 3).
- Sun bid distribution penalty: −10 per suit with count<2 or no
  honors (capped at −25).
- Round-2 threshold raised to ≥ Round-1 + 6 (R2 picker has more
  optionality, so the bar should be higher, not lower).
- Ashkal additional check: only call if our own holding in the
  flipped suit is weak (no J of flipped, count ≤ 2).

*Escalation (Bel / Bel-Re / Triple / Four / Gahwa)*
- Partner's bid feeds escalation strength directly:
  HOKM-trump-match +20, HOKM-other +10, SUN +15, ASHKAL +15,
  PASS-both-rounds −10.
- Score-urgency threshold modifier: behind 80+ → −6 (more
  aggressive); near loss → −12; near win → +8 (conservative).

*Play*
- Position-aware following: 2nd-hand-low (duck unless sure
  stopper) / 3rd-hand-high (commit a card that survives 4th-seat
  overcut). 4th still cheapest-winner.
- `pickLead` boss-card scan: lead the highest unplayed card in
  any non-trump suit when we hold it (free trick).
- Bidder lead asymmetry: trump-poor bidder (<4 trump) with a
  side-suit Ace cashes the Ace before the trump pull. Bidder's
  partner falls through to defender-style logic instead of
  blindly leading high trump.
- Bot AKA self-call: when leading the boss of a non-trump suit,
  bot fires the AKA banner + voice cue first so partner doesn't
  over-trump (matches the human signal).
- Smother gate (basic + advanced): now relaxes when 4th-to-act
  with partner winning — the trick is going on partner's pile
  no matter what, free points.

**Internals**
- `Bot.IsAdvanced()` / `Bot.IsM3lm()` (the latter always returns
  false until the M3lm tier is implemented).
- All advanced helpers return 0/nil in basic mode so non-advanced
  hosts get the v0.1.19 behaviour bit-for-bit.

## v0.1.19 — Saudi rules sweep, smarter bots, meld timing

**Saudi rules**
- `Rules.IsLegalPlay` — when trump is led and your partner is currently
  winning the trick, you no longer have to overcut. Matches the
  off-lead-trump partner-winning exception that was already in place.
- `Rules.ScoreRound` — in a sweep (Al-Kaboot), the +20 belote bonus
  now follows the sweep winner instead of staying with the K+Q
  holder. "Winner takes all" applies to belote too.
- `State.HostAdvanceBidding` — round-2 Hokm cannot reuse the bid
  card's flipped suit (host-side enforcement, backing up the UI gate).
- `State.HostAdvanceBidding` — first direct Sun bid in round 1 locks
  the declarer chair; later direct Sun bids no longer overcall it.
  An Ashkal-derived Sun can still be overcalled by a later direct
  Sun (the direct bid reassigns declarer to the actual bidder per
  Saudi convention). Tracked via a `viaAshkal` flag on the winning
  record.
- `Net.HostResolveTakweesh` — takweesh penalty multiplier now respects
  the full escalation chain (Triple ×8, Four ×16, Gahwa ×32). Was
  previously stuck at base / Bel ×2 / Bel-Re ×4.

**Bots**
- Bidding thresholds raised: `TH_HOKM_R1_BASE 35→42`,
  `TH_HOKM_R2_BASE 28→36`. Bots stop committing to Hokm on weak
  hands.
- `pickLead` rewritten for non-bidder team — 5-tier priority:
  opponent-void high lead, low singleton, low from longest non-trump,
  fallback lowest non-trump, lowest trump. No more blind Ace leads.
- `pickFollow` smother gated — bots only dump A/T onto a partner-
  winning trick if (a) holding ≥2 of A/T in lead suit, OR (b) past
  trick 3. Trump-led smother skipped entirely. Stops the trick-1
  Ace burn.
- New `Bot.PickTriple` / `PickFour` / `PickGahwa` — strength-gated
  escalation (`BOT_TRIPLE_TH 95`, `BOT_FOUR_TH 115`,
  `BOT_GAHWA_TH 130`) replaces the previous flat 10% coin-flip.
- New Ashkal heuristic — when partner has bid Hokm in round 1 and
  the bot's Sun-strength clears `BOT_ASHKAL_TH (65)`, bot calls
  Ashkal to push partner into Sun (higher multiplier).

**Hand display**
- Sort order now strictly alternates colour: ♠ ♥ ♣ ♦
  (B R B R). Replaces the previous BBRR group-by-colour layout.
  Easier to scan — every adjacent pair is opposite colour.

**Meld display timing**
- Meld card strip now follows a three-window model per Saudi rule:
  - Trick 1: every declarer's strip is visible the whole time.
  - Trick 2: a seat's strip appears only while it's that seat's
    turn, and hides as soon as the next seat is up.
  - Trick 2 last player: held visible 4 seconds after their final
    play (no "next turn" to clip them).
  - Trick 3 onwards: never visible.

## v0.1.18 — meld backdrop fix, hand sort, contract banner

**Fixes**
- Meld mini-cards now render with a solid cream body + dark edge
  drawn from explicit Texture layers (BACKGROUND/0 for the edge,
  BACKGROUND/1 for the body, ARTWORK for the card face). The
  previous BackdropTemplate approach didn't reliably render at
  small sizes, leaving the cards transparent. Slot bumped to 22×30.
- Meld strip and meldText label both hide once trick 1 closes,
  matching the Saudi rule that melds are public during trick 1
  only. Previously the text label persisted for the whole round
  alongside the strip.

**UX polish**
- Hand sort now groups suits by colour (♣ ♠ ♥ ♦ → black, black,
  red, red) instead of the interleaved black-red-red-black layout
  that the old K.SUIT_INDEX produced. One colour boundary in the
  middle of the hand instead of two — easier to scan.
- Contract line at the bottom of the window upgraded to a wood-edged
  plate with a 15-px outlined font: `Contract: HOKM ♥  by  Bidder
  [Bel+x16]`. The plate auto-hides outside an active contract.
  Modifier list now also shows Triple/Four/Gahwa multipliers.

## v0.1.17 — meld display polish + AKA label fix

**Fixes**
- Meld mini-cards now have the cream card-body backdrop. Previously
  the slot was a bare texture and the card art TGAs are transparent
  outside the rank/pip glyphs, so cards looked like floating
  fragments. Each slot is now a small frame with the same body +
  edge backdrop as the table card faces, with the rank/pip texture
  laid on top.
- AKA button label and banner switched from "إكَهْ" to Latin "AKA".
  WoW's bundled fonts (Arial Narrow / Frizz / Skurri) don't include
  Arabic glyphs, so the original label rendered as empty boxes. The
  voice cue still says إكَهْ, so the audio carries the Saudi feel.
- Meld card strips now respect the Saudi-rule timing: face-up only
  during trick 1 (PHASE_DEAL3 and the first trick of PHASE_PLAY).
  After trick 1 closes the cards rejoin the hand and the strip
  hides — only the score the meld earned is remembered (shown in
  the round-end banner).
- Slot size bumped 18×24 → 26×36 so the card art is actually
  legible at table scale.

## v0.1.16 — AKA call (إكَهْ) + meld card display

**New gameplay**
- AKA (إكَهْ) partner-coordination signal in Hokm contracts. When the
  local player holds the highest unplayed card in any non-trump suit
  (Sun ranking: A → 10 → K → Q → J → 9 → 8 → 7), an "إكَهْ" button
  appears in the action row. Pressing it broadcasts a soft signal:
  voice cue plays for everyone, banner appears above the trick area
  showing the suit + caller. The teammate uses this to avoid
  over-trumping. No legal-play enforcement — purely informational,
  matching the social signal used at the table.
- Voice asset (sounds/aka.ogg) — placeholder generated via gTTS;
  re-bake with `_make_voice_eleven.py aka` on a paid ElevenLabs
  plan to swap in the Saud voice (consistent with the rest of the
  Arabic cues).

**New visual**
- Declared melds now show as face-up mini cards next to each player
  in addition to the existing text label. Per Saudi rule, melds are
  public the moment they're declared during trick 1.
- Once trick 1 closes, the meld-comparison verdict drives strip
  styling: the winning team's melds stay at full opacity, the losing
  team's melds dim to 0.45 alpha so the player can see what was
  declared but it visibly "doesn't count". Ties stay neutral (0.85).
- Strips appear under the seat-badge card-back fan for opponents and
  above the local bar for the local player.

**Internals**
- `s.playedCardsThisRound` set tracks cards played this hand; rebuilt
  from s.tricks on /reload, marked TRANSIENT for SaveSession.
- `s.akaCalled` is per-trick ephemeral, cleared by ApplyTrickEnd.
- Wire: `MSG_AKA = "e"`, payload `seat;suit`. Soft signal — host
  doesn't need to validate or arbitrate; receivers gate on PHASE_PLAY
  + HOKM contract.

## v0.1.15 — multiplayer rejoin after game-end

**Bug fix**
- After a game ended and the host clicked Reset + Host Game, joiners
  who were still showing the score banner (PHASE_SCORE / GAME_END)
  silently dropped the new lobby announcement. Symptoms: the Join
  button never appeared on the joiner's side, OR the joiner's Join
  click went out with the previous game's stale gameID and the host
  silently rejected it — leaving only some of the players visible
  in the host's seat list.
- `Net._OnHost` and `State.ApplyLobby` now accept lobby announcements
  in any "passive" phase (IDLE, LOBBY, SCORE, GAME_END). Mid-active-
  play phases still ignore stranger announcements (anti-grief).
- When a new gameID arrives, ApplyLobby soft-resets leftover round
  artifacts (contract, hand, tricks, score banner, winner) while
  preserving session identity (localName, target, team-name labels,
  peer versions).
- `pendingHost` is now cleared once the joiner is successfully
  seated, so a stale entry from a finished game can't mask a future
  host announcement.

## v0.1.14 — peek button relocated, banner re-labelled

**UI**
- The last-trick peek "?" button moved out of the felt's top-right
  corner and into the main frame's top-right gutter, just below the
  Reset button. It now sits between Bot 2's seat badge and Reset, so
  the trick area stays uncluttered.
- The pause "II" button takes the freed-up corner inside the felt
  (top-right of the centre pad).
- Round-result banner: "Contract made" → "ALLY B3DO" to match the
  Saudi-Arabish wording players use at the table.

## v0.1.13 — lobby seat-row layout fix

**UI fix**
- Lobby seat rows now auto-fit between the lobby's left edge and the
  party-members sidebar's left edge instead of overhanging it. The old
  fixed 380-px-wide centred rows clipped under the sidebar by ~22 px
  on the right; new rows use anchored TOPLEFT/TOPRIGHT pairs so the
  layout stays tidy regardless of the main frame width.

## v0.1.7 — visuals, takweesh detail, reset button, audit fixes

**New UI**
- Reset button (top-right under game code) with a Blizzard popup
  confirmation. Equivalent to `/baloot reset`.
- "(KZKZ will come)" branding next to the title.
- Minimal-bg toggle (bottom-left): hides the outer green frame so
  only the felt trick area + cards remain visible. Useful for
  streaming or low-clutter views. Persists per-account.

**Takweesh feedback**
- A successful Takweesh now displays the offending card (rank + suit
  glyph) and the rule reason in chat: "K♠ — must follow suit",
  "T♥ — must overcut", etc.
- Score banner shows the same details for the rest of the round.

**Card art**
- All 32 card-face TGAs re-baked composited against the cream
  backdrop so anti-aliased edges blend cleanly. Fixes the "glow"
  visible on Ace of Diamonds (and minor halos on other cards).

**Agent-audit fixes**
- `redealing` and `takweeshResult` added to TRANSIENT_FIELDS so
  timer-backed banners don't persist across /reload.
- `maybeRequestResync` no longer gated on PHASE_IDLE — RestoreSession
  brings us into a non-IDLE phase and we still want the host's
  authoritative state, not a possibly-stale local snapshot. Added
  a host-skip so a solo-bot host doesn't broadcast to nobody.

## v0.1.6 — escalation chain, redeal pause, polish

**New gameplay**
- Full Triple / Four / Gahwa escalation chain (×8 / ×16 / ×32) per
  Saudi rule 4-10. Bot opponents skip these by default with a small
  random escalation chance.
- Voice cues "ثري" / "فور" / "قهوة" announce each step.
- Doubled-tie inversion logic now follows the alternating "buyer"
  rule across all 5 escalation levels.

**Bidding feel**
- Bots commit on more typical biddable hands (thresholds lowered
  ~30%) — fewer all-pass rounds.
- Bel-skip no longer plays the pass voice (it was confusing right
  after a contract announcement).
- Round-2 pass says "ولا" (round-1 still says "بَسْ").
- "ثآني" announces the round-2 bidding window (mirrors "أوَل").
- AWAL / THANY voices delayed 0.5s so the visual round-start lands
  first, then the audio.
- All-pass redeal now holds for 3s with a "Next dealer: NAME"
  banner so the rotation is obvious instead of instant.
- Trick-resolve buffer 1.5s → 2.2s; bot delays 1.0s → 1.6s.

**UI polish**
- Custom team A / B names — host edits in lobby, broadcast to all
  clients, persists per-account, applied across score line + banner.
- Local player bar narrower (540 → 280px) and centered, with the
  same turn-glow texture the other three seat badges use.
- Card back replaced with a programmatic navy/gold diamond pattern.
- Ace of Clubs no longer renders a white square (chroma-keyed the
  source PNG's solid card body to transparent).
- Pause/peek buttons elevated to FULLSCREEN_DIALOG strata so they
  remain clickable when the pause overlay is up.
- Title/scale buttons no longer overlap.

## v0.1.3 — session persistence

- Game state survives `/reload` and logout. The host's snapshot
  (phase, contract, scores, seats, hands, current trick, melds) is
  saved on `PLAYER_LOGOUT` and restored on the next `PLAYER_LOGIN`.
- Per-character guard so an account's saved session can't surface on
  a different character.
- Sessions older than an hour or finished games are discarded.
- Reset clears the saved session.

## v0.1.2 — title overlap fix

- Move +/- scale buttons off the centered title (they were covering
  the "WH" of "WHEREDNGN").

## v0.1.1 — visuals, sound, scoring fixes, hardening

**Visuals**
- Vector Playing Cards art (32 cards + back) replaces the FontString placeholders.
- Four-color suit deck (♠ black, ♥ red, ♦ blue, ♣ green) — suits are unambiguous at a glance.
- Felt-green tiled trick area with winner-glow on the trick winner.
- Card slide-in animation from each player's edge.
- Bot avatar circles next to seat names.
- Window scale controls (+/−) in the title bar; size persists.

**Sound (with mute toggle in top-left)**
- Card swish + slap on every play.
- Soft bell when your turn arrives.
- Two-note chime when contract is finalized.
- Triad arpeggio when your team wins a trick.
- Four-note fanfare for AL-KABOOT / contract failure.
- Arabic voice cues (ElevenLabs Saud) for HOKM / SUN / ASHKAL / PASS / "Awal" round-start.

**Bot AI**
- Bid threshold randomized ±6 so two bots dealt similar hands don't always pick the same bid.
- Bel/Bel-Re threshold randomized ±10 — no longer a hard cliff.
- Smother-partner: in Hokm, bots dump A/10 of trick lead suit when partner is winning.
- Trump-saving: bots prefer non-trump discards when they're not closing the trick.
- Card-counting helper for outstanding-trump awareness.
- Takweesh detection: bots call Takweesh on opponent illegal plays (60% in trick 1, decays through hand).

**Networking / correctness**
- Authority + phase + idempotence guards on `_OnBid`/`_OnPlay`/`_OnMeld`/`_OnTakweesh`/`_OnKawesh`.
- Resync-on-reload (`MSG_RESYNC_REQ`/`RES`): players who `/reload` mid-game request state from the host and rehydrate.
- Host pause toggle suspends bots and AFK timers without dropping in-flight state.
- AFK pre-warn (T-10s) flashes the local bar and pings audibly so auto-pass isn't a surprise.
- Hold-to-confirm on Bel-Re and Takweesh — single-click can't trigger a round-ender by mistake.

**Saudi rule corrections**
- Strict-majority make check (Saudi rule 4-2/4-3): 65-65 (Sun) / 81-81 (Hokm) is now a tie that goes to the defenders.
- Belote shifted into the make-check total (rule 4-5).
- Doubled-tie inversion (rule 4-10): on a tied doubled hand, the bidder team takes the full count.

**Bug fixes**
- `cancelLocalWarn` was nil at call time → every Local* action crashed. Forward-declared.
- Sound dispatch: SoundKit IDs now route via `PlaySound`, not `PlaySoundFile`.
- Takweesh false-call no longer leaves the trick frozen on the table.

## v0.1.0 — initial release

- Full Saudi Baloot ruleset: Hokm, Sun, Ashkal, Belote, Al-kaboot, Takweesh, Kawesh.
- 4-player party-only over addon channel; bots fill empty seats.
- Bidding (round 1 + round 2), Bel/Bel-Re windows, meld declarations, trick play.
- AFK timer auto-skips Bel/Bel-Re windows after 60s.
- Authority + idempotence guards on Double/Redouble messages.
