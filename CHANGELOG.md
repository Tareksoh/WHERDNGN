# Changelog

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
