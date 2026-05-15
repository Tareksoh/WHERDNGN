# v3.2.9 Manual Multiplayer Playtest Checklist

**Repo:** `WHEREDNGN` (Saudi Baloot WoW addon)
**Current main:** v3.2.9 shipped (commit `280c733`, tag `v3.2.9`)
**Latest tests on main:** harness `1301 / 0`, H1=11/0, H7=9/0
**Purpose:** verify the v3.2.8 + v3.2.9 host-visual-refresh fixes
hold up in real 4-human play, AND act as the playtest gate for
deferred audit findings #4/#5 (`LocalPlay` / `LocalBid` non-host
optimistic refresh).

This is a tester-facing artifact. Print, screen-share, or fill
out as you go.

---

## Setup assumptions

Before starting:

- [ ] **4 human players**, none on the same machine. Use a
  Discord voice channel or similar so testers can call out
  observations in real time.
- [ ] **Naming convention** (used throughout this doc):
  - **H** = the host player (the one who hit "Host").
  - **L** = the player immediately clockwise from H (host's
    left / next-in-turn-order).
  - **P** = the player across from H (host's partner).
  - **R** = the player immediately counter-clockwise from H
    (host's right / just-before-host-in-turn-order).
- [ ] **Observation timing:** each tester records the relevant
  on-screen indicator (seat glow / card on table / button
  enablement) at the **exact moment** of the trigger event AND
  at **+5 seconds**. Discrepancy between the two readings is
  the bug — most v3.2.8-class bugs manifest as "host's UI
  stales until something else triggers a redraw."
- [ ] **Optional but recommended:** at least one tester
  screen-records (OBS / built-in macOS / Windows Game Bar /
  shadowplay). Replays catch sub-second flicker that's hard to
  eyeball. Especially useful for PT.C2 (the 4th-play-of-trick
  visual-lag question).
- [ ] **Slash commands handy:** `/baloot pause`, `/baloot
  resume`, `/reload` (WoW client reload). Section E uses these.

---

## Section A — Bid-phase host visual (v3.2.9 fixes)

These tests target the three `_HostStepBid` Refresh sites added
in v3.2.9. **Critical priority** because v3.2.9 is fresh.

### PT.A1 — mid-bid turn advance (host's left = next bidder)

- [ ] **Setup:** 4 humans, fresh deal. Bid order L → P → R → H.
- [ ] **Trigger:** R bids (any value, including pass).
- [ ] **Expected on host:** seat-glow moves from R to **H**
  within ~200 ms. Host sees its own bid affordances enable
  (Hokm/Sun/Pass buttons).
- [ ] **Failure mode:** glow stays on R; host's bid UI doesn't
  enable until host clicks anywhere or another network event
  arrives.
- [ ] **Attribution:** **v3.2.9 regression** (fix site #1,
  `action == "next"`).
- [ ] **Result:** ⬜ PASS ⬜ FAIL (see template below)

### PT.A2 — full bid round, all advances

- [ ] **Setup:** same as PT.A1.
- [ ] **Trigger:** L bids, then P bids, then R bids (full
  rotation).
- [ ] **Expected on host:** after each bid, seat-glow advances
  within ~200 ms. The final R→H advance is the critical one
  (per PT.A1).
- [ ] **Failure mode:** glow stales on any intermediate seat
  for host's view. Non-host views must show clean advance — if
  they also stale, it's a wire issue not a v3.2.9 regression.
- [ ] **Attribution:** **v3.2.9 regression** (fix site #1).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.A3 — round-2 bid kickoff after all-pass redeal

- [ ] **Setup:** 4 humans, all 4 pass in round 1 → round-2 bid
  kickoff. Dealer rotates; first round-2 bidder is L.
- [ ] **Trigger:** all-pass redeal completes → round-2 begins.
- [ ] **Expected on host:** seat-glow lands on **L** (first
  round-2 bidder) within ~200 ms of the deal landing.
- [ ] **Failure mode:** glow stales on dealer or remains unset
  until first round-2 bid arrives.
- [ ] **Attribution:** **v3.2.9 regression** (fix site #3,
  `action == "round2"`).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.A4 — contract finalization (non-host wins bid)

- [ ] **Setup:** 4 humans, L wins the bid (e.g. Hokm with
  bidcard).
- [ ] **Trigger:** L's bid is the final one → contract
  finalizes.
- [ ] **Expected on host:** host's UI refreshes within ~200
  ms: bid-card highlight clears, phase banner changes from
  "Bidding" to "Bel" or "Play", Bel/Triple/Four buttons appear
  if applicable.
- [ ] **Failure mode:** host's UI stays in bid mode; buttons
  don't appear; phase banner stuck on "Bidding" until next
  network event.
- [ ] **Attribution:** **v3.2.9 regression** (fix site #2,
  `action == "contract"`).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.A5 — contract finalization (host wins bid)

- [ ] **Setup:** 4 humans, H wins the bid.
- [ ] **Trigger:** H's own bid finalizes the contract.
- [ ] **Expected on host:** same as PT.A4 — host should see
  post-contract UI immediately.
- [ ] **Failure mode:** same as PT.A4.
- [ ] **Attribution:** **v3.2.9 regression** (fix site #2).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.A6 — pre-empt window (regression guard)

- [ ] **Setup:** 4 humans, bid card is an Ace, round 2, Sun
  bid — triggers pre-empt window.
- [ ] **Trigger:** host or another player triggers the
  pre-empt sub-branch.
- [ ] **Expected:** host's UI shows "Claim?" affordance
  immediately for any eligible seats (pre-existing Refresh at
  `Net.lua:2647` already covers this — v3.2.9 did not touch
  it).
- [ ] **Failure mode:** pre-empt UI doesn't appear.
- [ ] **Attribution:** **NEW issue** if it fails (pre-empt was
  untouched by v3.2.9; a failure here means we broke a working
  code path).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.A7 — bot bidder, host is human (mixed game)

- [ ] **Setup:** 3 humans + 1 bot bidder, host is human.
- [ ] **Trigger:** bot bids in any round.
- [ ] **Expected on host:** seat-glow advances correctly when
  the bot's turn-end advances state via `MaybeRunBot` →
  `S.ApplyBid` → `_HostStepBid`.
- [ ] **Failure mode:** glow stales on the bot's seat after
  bot bids.
- [ ] **Attribution:** **v3.2.9 regression** (fix site #1 — bot
  path is uncovered by `_OnBid` dispatcher Refresh, which is
  why the fix lives inside `_HostStepBid`).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

---

## Section B — Play-phase host visual (v3.2.8 regression guard)

### PT.B1 — mid-trick turn advance (host is next to play)

- [ ] **Setup:** 4 humans, mid-round, in the middle of a
  trick. Play order has R playing card just before H.
- [ ] **Trigger:** R plays their card (trick has 3 cards now,
  host next).
- [ ] **Expected on host:** seat-glow moves from R to H within
  ~200 ms. Host's playable-card highlight enables on legal
  cards in hand.
- [ ] **Failure mode:** glow stays on R; host's hand cards
  don't visually enable until host clicks anywhere or another
  event arrives. **This is the original v3.2.8 bug** — should
  NOT recur.
- [ ] **Attribution:** **v3.2.8 regression** if it fails.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.B2 — host plays 4th card of trick (trick-end timing)

- [ ] **Setup:** 4 humans, mid-round. Play order L → P → R →
  H (H plays 4th).
- [ ] **Trigger:** after H plays the 4th card, the trick
  should resolve (2.2 s pause, then winner announced).
- [ ] **Expected:** 4-card trick stays visible for 2.2 s,
  then trick-pile slides to winner's pile, glow moves to
  winner.
- [ ] **Failure mode:** trick doesn't resolve, glow stuck, or
  4-card view dismissed prematurely.
- [ ] **Attribution:** **NEW issue** if it fails (4-play path
  was already correct pre-v3.2.8).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.B3 — host won prior trick, leads next

- [ ] **Setup:** 4 humans, host won the previous trick.
- [ ] **Trigger:** trick resolves → host should now lead the
  next trick.
- [ ] **Expected:** glow moves to H, host's hand enables for
  lead-card selection.
- [ ] **Failure mode:** glow stays on the prior winning play.
- [ ] **Attribution:** **v3.2.8 regression** if it fails
  (`_HostStepAfterTrick` path — covered by C_Timer's
  `Refresh()` at `Net.lua:2736`).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.B4 — AFK timeout on a non-host human

- [ ] **Setup:** 4 humans, AFK timeout fires for a non-host
  human seat (let them sit for 60 s).
- [ ] **Trigger:** host's `_HostTurnTimeout` auto-plays a card
  for the AFK seat.
- [ ] **Expected:** all players (including host) see the
  auto-played card land within ~200 ms. Glow advances to next
  seat.
- [ ] **Failure mode:** auto-play happens but visual state
  stales on host UI specifically.
- [ ] **Attribution:** **NEW issue** if it fails (AFK path has
  its own terminal `Refresh()` at `Net.lua:5489`).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

---

## Section C — Non-host visual on own actions (deferred #4 / #5 gate)

**This section is the playtest gate for whether to ship a
v3.2.10 fix for findings #4 / #5.** If these all look clean to
the user, ship-as-is. If any feel laggy, file a v3.2.10
design pass.

### PT.C1 — non-host plays mid-trick

- [ ] **Setup:** 4 humans, you are non-host **L**. Mid-trick,
  your turn (you are play 1, 2, or 3 of the trick).
- [ ] **Trigger:** you click a card.
- [ ] **Expected (user-perception):** your card appears on the
  table immediately (or at least with the standard slide
  animation). Your hand fades the played card. Glow advances
  to next seat within ~200 ms (host's MSG_TURN echo).
- [ ] **Failure mode:** card doesn't appear on table for
  **>500 ms after click** OR your hand looks unchanged for
  >500 ms.
- [ ] **Attribution:** **Deferred #4** confirmation — if user
  reports this, re-open the v3.2.10 slice.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.C2 — non-host plays 4th card of trick (worst-case lag)

- [ ] **Setup:** 4 humans, you are non-host **R** (last to
  play in trick). You are play 4 of the trick.
- [ ] **Trigger:** you click a card.
- [ ] **Expected (user-perception):** your card appears on the
  table immediately. After ~2.2 s the trick resolves and
  slides to winner's pile.
- [ ] **Failure mode:** your card doesn't appear on the table
  for **2.2 s** after click (until MSG_TRICK arrives from
  host). The "I clicked but nothing happened" perception.
- [ ] **Attribution:** **Deferred #4** confirmation, worst
  case. **This is the most likely user-visible manifestation**
  of the deferred bug. If WoW's animator masks it, the user
  won't perceive lag — let the playtester report subjectively.
- [ ] **Result:** ⬜ PASS ⬜ FAIL
- [ ] **Subjective lag perception (1-5):** ____ where 1 =
  no lag at all, 5 = clearly broken.

### PT.C3 — non-host bids

- [ ] **Setup:** 4 humans, you are non-host **P**. Bidding
  phase, your turn.
- [ ] **Trigger:** you click your bid.
- [ ] **Expected (user-perception):** your bid choice appears
  in your bid-history display immediately. Glow advances
  within ~200 ms.
- [ ] **Failure mode:** bid choice doesn't visually register
  for >500 ms.
- [ ] **Attribution:** **Deferred #5** confirmation — re-open
  v3.2.10 if user reports.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.C4 — non-host hits Bel (escalation)

- [ ] **Setup:** 4 humans, you are non-host **P**.
- [ ] **Trigger:** click Bel button.
- [ ] **Expected:** Bel announcement banner / sound fires on
  all clients. Your Bel button disables.
- [ ] **Failure mode:** banner visible to other clients but
  your own UI doesn't update (button still enabled, no
  banner) until host echoes.
- [ ] **Attribution:** **NEW issue** if it fails (Bel has its
  own broadcast + dispatcher Refresh; should be clean).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

---

## Section D — Interruption sanity (Takweesh / AKA / SWA)

Only run if Sections A-C are clean. These are lower priority
because their visual fixes are older and have multiple explicit
Refresh sites.

### PT.D1 — Takweesh catches false AKA

- [ ] **Setup:** 4 humans, Hokm contract. Non-host bidder
  leads a non-trump K announcing AKA but doesn't hold the
  Ace (false AKA scenario).
- [ ] **Trigger:** any opposing-team player clicks TAKWEESH.
- [ ] **Expected:** TAKWEESH review banner appears on all 4
  clients within ~500 ms. Reveal-card window shows for ~8 s.
  Round resolves with caller's team winning.
- [ ] **Failure mode:** banner doesn't appear on host's UI;
  or banner appears but caller's team is penalized despite
  valid catch.
- [ ] **Attribution:** **NEW issue** if it fails (Takweesh
  paths have many explicit Refresh calls).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.D2 — same-team Takweesh tooltip (v3.2.7)

- [ ] **Setup:** 4 humans, Hokm. Caller and offender are on
  the **same team**.
- [ ] **Trigger:** hover the TAKWEESH button; read the
  tooltip. If you then click, observe the result.
- [ ] **Expected tooltip wording:** "Only OPPOSING-team
  illegal plays qualify; calling Takweesh on your own
  teammate counts as a wrong call." If caller proceeds,
  caller's team is penalized.
- [ ] **Failure mode:** tooltip wording missing (v3.2.7
  regression) OR caller's team gets credit (host-scan filter
  regression at `Net.lua:3362`).
- [ ] **Attribution:** **v3.2.7 regression** (tooltip) OR
  **v0.x infrastructure regression** (host-scan filter — BM.3
  wire-locks this).
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.D3 — AKA banner relief

- [ ] **Setup:** 4 humans, Hokm, non-trump K-led with AKA
  banner.
- [ ] **Trigger:** player announces AKA on lead.
- [ ] **Expected:** AKA banner appears for all clients within
  ~500 ms. Partner's must-trump-ruff is suppressed; partner's
  UI reflects relaxed legal set.
- [ ] **Failure mode:** banner only visible to non-host or
  only to host; partner's UI doesn't reflect relaxed
  legality.
- [ ] **Attribution:** **NEW issue** — AKA wire path has 250
  ms retry (`Net.lua:666`) and its own dispatcher Refresh.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.D4 — SWA permission flow

- [ ] **Setup:** 4 humans, late-round, hand size ≤4 cards.
  Non-host clicks SWA.
- [ ] **Trigger:** SWA permission flow.
- [ ] **Expected:** SWA banner appears on all clients; opps'
  bots (if any) auto-respond; humans see Approve/Reject
  buttons; 5 s auto-approve timer.
- [ ] **Failure mode:** banner doesn't appear on host UI; OR
  caller doesn't get round-claim despite valid SWA.
- [ ] **Attribution:** **NEW issue** if it fails. SWA paths
  have multiple explicit Refresh calls.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.D5 — SaudiMaster bot noise-AKA gets caught (v3.2.6)

- [ ] **Setup:** 4 humans, SaudiMaster bots enabled,
  mid-round.
- [ ] **Trigger:** wait for a bot to emit a noise-AKA (v1.6.0
  8% rate on non-trump K/Q leads where bot doesn't hold the
  Ace). May need many rounds to observe naturally.
- [ ] **Expected:** bot bluff is publicly markable; **opp
  bots** should call Takweesh on it within their next turn
  (v3.2.6 fix).
- [ ] **Failure mode:** bot opp never calls Takweesh on the
  bluff.
- [ ] **Attribution:** **v3.2.6 regression** if it fails.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

---

## Section E — Recovery / edge cases

Run only if time allows. These probe historically-fragile
recovery paths.

### PT.E1 — pause / resume

- [ ] **Setup:** 4 humans, mid-round. Host pauses
  (`/baloot pause`) for 30 s.
- [ ] **Trigger:** host resumes (`/baloot resume`).
- [ ] **Expected:** all clients resume seamlessly; turn-glow
  correct on all clients; current trick state intact.
- [ ] **Failure mode:** glow stales on a prior seat after
  resume; OR turn pointer wrong.
- [ ] **Attribution:** **NEW issue** — pause/resume has
  historical bug history (v0.10.6 H2); shouldn't regress.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.E2 — non-host `/reload`

- [ ] **Setup:** 4 humans, mid-round.
- [ ] **Trigger:** a non-host runs `/reload`.
- [ ] **Expected:** resync snapshot replay. Resyncing client's
  state restores to current trick + turn; UI redraws. Other 3
  clients are unaffected.
- [ ] **Failure mode:** resyncing client's UI doesn't draw,
  OR shows stale state, OR triggers some side-effect on other
  clients.
- [ ] **Attribution:** **NEW issue** — resync paths have
  explicit Refresh in replay logic.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

### PT.E3 — heartbeat self-heal

- [ ] **Setup:** 4 humans, host's heartbeat is observed
  dropping (force a network blip — toggle WoW client offline
  briefly, or use `/baloot freezelog enable` if available).
- [ ] **Trigger:** heartbeat self-heal at 15 s cadence.
- [ ] **Expected:** when the heal fires (`_OnHeartbeat` at
  `Net.lua:4046`), the affected client's turn-glow snaps to
  host's authoritative value within 200 ms.
- [ ] **Failure mode:** heal doesn't fire OR fires but UI
  doesn't redraw.
- [ ] **Attribution:** **NEW issue** — heartbeat heal has
  explicit Refresh at L4079 and L4115.
- [ ] **Result:** ⬜ PASS ⬜ FAIL

---

## Pre-flight static verification

Done by the maintainer against `main` **before** handing this
checklist to testers. This is NOT the playtest — manual
PASS/FAIL still requires a real 4-human WoW session (especially
the PT.C2/PT.C3 subjective lag-perception calls, which only a
human watching the screen can answer).

- ✅ **All four v3.2.8 / v3.2.9 host-refresh markers are
  present on `main`.** Verified by grep:
  - `v3.2.9 bid-phase analog of v3.2.8 host-turn refresh`
    (PT.A1/A2/A7 fix site, `_HostStepBid` `action == "next"`)
  - `v3.2.9 contract-finalization host-side refresh`
    (PT.A4/A5 fix site, `action == "contract"`)
  - `v3.2.9 round-2 bid-kickoff host-side refresh`
    (PT.A3 fix site, `action == "round2"`)
  - `v3.2.8 host-turn visual refresh`
    (PT.B1 fix site, `_HostStepPlay` `<4 plays`)
  The build under test genuinely contains the fixes — a PT.A*
  / PT.B1 FAIL is therefore a real regression, not a "tester
  ran an old build" artifact.
- ✅ **`N.LocalPlay` and `N.LocalBid` still intentionally have
  NO local `B.UI.Refresh()`.** Verified: both functions end
  with `S.Apply* → N.Send* → if isHost then _HostStep*()` and
  no terminal refresh. Deferred audit findings #4 (`LocalPlay`)
  and #5 (`LocalBid`) are intact, so **PT.C2 and PT.C3 remain
  meaningful human gates** — a non-host's own click has no
  local redraw trigger on `main` today; whether the WoW
  animator masks the resulting lag is exactly the subjective
  question the playtest must answer.
- ⚠️ **Manual PASS/FAIL still requires a real 4-human WoW
  playtest.** Static verification confirms the code is
  fix-complete and the deferred gate is live; it cannot
  substitute for human observation of seat-glow timing,
  card-display latency, or subjective lag perception.

## Code-path reference (for FAIL triage)

When a test fails, locate its mapped code path here. **The
line numbers below are approximate and drift as the file
evolves — marker-grep is authoritative.** For the four
host-refresh fix sites, grep the marker text rather than
trusting any line number:

```
grep -n "v3.2.9 bid-phase analog"                 Net.lua   # PT.A1 / A2 / A7
grep -n "v3.2.9 contract-finalization host-side refresh" Net.lua   # PT.A4 / A5
grep -n "v3.2.9 round-2 bid-kickoff host-side refresh"   Net.lua   # PT.A3
grep -n "v3.2.8 host-turn visual refresh"          Net.lua   # PT.B1
```

| Test group | Code path | Marker-grep / approx. location |
|---|---|---|
| **PT.A1 / A2 / A7** | `_HostStepBid` `action == "next"` branch + v3.2.9 marker + Refresh | `grep "v3.2.9 bid-phase analog" Net.lua` (≈ Net.lua:2614, approx) |
| **PT.A3** | `_HostStepBid` `action == "round2"` branch + v3.2.9 marker + Refresh | `grep "v3.2.9 round-2 bid-kickoff host-side refresh" Net.lua` (≈ Net.lua:2707, approx) |
| **PT.A4 / A5** | `_HostStepBid` `action == "contract"` main path + v3.2.9 marker + Refresh | `grep "v3.2.9 contract-finalization host-side refresh" Net.lua` (≈ Net.lua:2691, approx) |
| **PT.A6** | `_HostStepBid` `action == "contract"` pre-empt sub-branch + pre-existing Refresh | `grep "preemptEligible" Net.lua` near the pre-empt window open (pre-v3.2.9 Refresh, ≈ Net.lua:2647, approx) |
| **PT.B1** | `_HostStepPlay` `<4 plays` branch + v3.2.8 marker + Refresh | `grep "v3.2.8 host-turn visual refresh" Net.lua` (≈ Net.lua:2723, approx) |
| **PT.B2 / B3** | `_HostStepPlay` 4-play branch C_Timer → `S.ApplyTrickEnd` + `_HostStepAfterTrick` + Refresh | `grep -n "function N._HostStepPlay" Net.lua`, then the 4-play C_Timer body (≈ Net.lua:2720-2738, approx) |
| **PT.B4** | `_HostTurnTimeout` + terminal Refresh | `grep -n "function N._HostTurnTimeout" Net.lua`, terminal `B.UI.Refresh()` (≈ Net.lua:5489, approx) |
| **PT.C1 / C2** | `N.LocalPlay` — DEFERRED, no Refresh after `SendPlay` (finding #4) | `grep -n "function N.LocalPlay" Net.lua` (≈ Net.lua:3281, approx) |
| **PT.C3** | `N.LocalBid` — DEFERRED, no Refresh after `SendBid` (finding #5) | `grep -n "function N.LocalBid" Net.lua` (≈ Net.lua:2983, approx) |
| **PT.C4** | `N.LocalDouble` / Bel broadcast path | `grep -n "function N.LocalDouble" Net.lua` |
| **PT.D1** | `N._OnTakweesh` + `HostBeginTakweeshReview` scan | `grep -n "function N._OnTakweesh\|function N.HostBeginTakweeshReview" Net.lua` |
| **PT.D2** | TAKWEESH tooltip wording + host-scan same-team filter | `grep -n "OPPOSING-team illegal plays qualify" UI.lua` (v3.2.7) + `grep -n "callerTeam" Net.lua` (host-scan filter) |
| **PT.D3** | `N._OnAKA` + AKA-receiver relief | `grep -n "function N._OnAKA" Net.lua` + `grep -n "akaRelief" Rules.lua` |
| **PT.D4** | SWA permission flow | `grep -n "function N.SendSWAReq" Net.lua` + bot SWA dispatch in `MaybeRunBot` |
| **PT.D5** | `Bot.PickTakweesh` false-AKA carve-outs (v3.2.6) | `grep -n "false AKA" Bot.lua` (both completed-trick and current-trick carve-outs) |
| **PT.E1** | `LocalPause` / `HostPause` paths | `grep -n "S.s.paused" Net.lua` |
| **PT.E2** | Resync replay handlers | `grep -n "function N._OnResyncRes" Net.lua` + the L1094 `HandleMessage` dispatcher |
| **PT.E3** | Heartbeat self-heal | `grep -n "function N._OnHeartbeat" Net.lua` (heal sites contain the `HEAL` freezelog markers) |

> Approx. line numbers are a current-snapshot convenience only;
> they were estimated, not grepped, and drift across releases.
> Always resolve the actual location with the marker-grep
> commands above before editing or triaging.

---

## Fill-in failure report template

Copy/paste this block for each failing test. Paste the
completed report back to whoever triages (likely Claude in
the working session, or directly to the maintainer).

```
==============================================
FAIL REPORT — v3.2.9 manual playtest
==============================================
Test ID:           (e.g. PT.A1)

Seat roles:
  Host (H):        (player name / character)
  Left (L):        (player name)
  Partner (P):     (player name)
  Right (R):       (player name)

Game state at trigger:
  Round number:    (e.g. round 3)
  Trick number:    (e.g. trick 2 of 8 — N/A if bidding)
  Phase:           (e.g. PHASE_PLAY, PHASE_DEAL1, etc.)
  Contract:        (e.g. Hokm trump=Hearts bidder=L, or "bidding")
  Tier:            (Basic / Advanced / M3lm / Fzloky / SaudiMaster
                    — note which seats have which tier)

Exact trigger:
  (e.g. "R clicked Pass and the bid round advanced.")

What the host saw:
  Seat glow:       (e.g. "stayed on R for 4 seconds")
  Card on table:   (e.g. "R's card landed correctly")
  Buttons:         (e.g. "Hokm/Sun/Pass buttons greyed out")
  Banner:          (e.g. "still says 'R is bidding'")

What non-hosts saw:
  L's view:        (matched host? or different?)
  P's view:        (matched host? or different?)
  R's view:        (matched host? or different?)

Self-correction:
  Did the UI self-correct?  (Yes / No)
  If yes, after how long?   (e.g. ~3 seconds — likely on
                              the next MSG_TURN echo)
  What triggered correction? (e.g. "P clicked their bid")

Screenshot / video:
  Link or attached:        (optional, but very helpful for
                            PT.C2 lag-perception cases)

Initial attribution (from the table above):
  □ v3.2.9 regression
  □ v3.2.8 regression
  □ v3.2.7 regression
  □ v3.2.6 regression
  □ Deferred #4 confirmation
  □ Deferred #5 confirmation
  □ NEW issue
  □ Unclear — needs triage

Tester notes:
  (anything else — pattern observed across multiple
   rounds, repro consistency, did `/reload` help, etc.)
==============================================
```

---

## Failure-attribution quick reference

| Symptom | Likely attribution |
|---|---|
| "Host's seat-glow stays on prior bidder/player when next is host" | v3.2.8 or v3.2.9 regression |
| "When I click my card as the 4th player in trick, it takes 2 seconds to show on table" | Deferred #4 confirmation |
| "Bid buttons / Bel buttons don't appear immediately after contract" | v3.2.9 fix site #2 regression |
| "Round 2 starts but no glow on first bidder" | v3.2.9 fix site #3 regression |
| "TAKWEESH tooltip doesn't say anything about teammates" | v3.2.7 regression |
| "Bot bluffs me with noise-AKA and never gets caught by bot opps" | v3.2.6 regression |
| "Pause/resume left someone stuck" | v0.10.6 H2-class regression — escalate |
| "After `/reload` my UI is blank or stale" | resync regression — escalate |

---

## Resolution paths

| Attribution | Action |
|---|---|
| **v3.2.9 regression** | File v3.2.10 hotfix. Branch from current `main`. Investigate which of the three `_HostStepBid` Refresh sites failed using the code-path reference. |
| **v3.2.8 regression** | Quick `git log Net.lua` audit — v3.2.8 fix at L2712 is recent; ensure it's still there. |
| **v3.2.7 regression** | UI.lua text-only change. Quick fix. |
| **v3.2.6 regression** | `Bot.lua` `Bot.PickTakweesh` false-AKA carve-out — re-audit Bot.lua:5953-6004. |
| **Deferred #4 confirmation** (PT.C1 / PT.C2) | File v3.2.10 design pass for `LocalPlay` non-host optimistic refresh. Recommend the playtester include screen-recording or subjective 1-5 lag-perception score. |
| **Deferred #5 confirmation** (PT.C3) | Same as #4 but for `LocalBid`. |
| **NEW issue** | Fresh bug report. Include file:line if reproducible, full FAIL template from above. |

---

## Recommended playtest cadence

- **1 round of Sections A + B + C** ≈ 10-15 minutes of
  4-human play.
- **Section D** requires specific gameplay setups (low
  SWA-eligible hand, intentional false AKA). Plan a dedicated
  4-human session for those.
- **Section E** is recovery-testing — can be done out-of-band
  with `/baloot pause` and `/reload` commands.
- **PT.A6** (pre-empt) and **PT.D5** (noise-AKA) need a
  specific bid card / probabilistic event — may take several
  rounds to observe naturally.

If any failure attributes to **v3.2.9** or **deferred #4/#5
confirmation**, file a follow-up design pass; otherwise the
v3.2.8 + v3.2.9 pair is confirmed shipping clean.

---

## Confirmation

- This is a tester-facing doc only. No runtime / test /
  packaging / workflow files were modified to produce it.
- v3.2.9 is the latest shipped tag.
- Harness is `1301 / 0` on `main` at commit `280c733`.
- Branches preserved: `sprint-a-experimental`,
  `v0.5.1-experimental`.
