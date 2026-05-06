# E-UI-01 — Banner / Window State-Machine Correctness Audit (v0.10.2)

**Track**: E (UX) · **Date**: 2026-05-05 · **Mode**: read-only

**Scope**: SWA permission + result banner, AKA toast, escalation chain
windows (Bel/Triple/Four/Gahwa), pre-empt window, overcall window,
pause overlay, banner layering, click-through gates, localized text,
UI-side AKA-blindness on `S.GetLegalPlays`. State-machine focus —
trigger, persist, redraw, pause, clear.

**Files inspected** (read-only):
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` (entry / restore / re-arm)
- `C:\CLAUDE\WHEREDNGN\UI.lua:1234-1316, 1318-1484, 1486-1516, 1756-1958, 2010-2050, 2210-2225, 2855-2895, 2942-3163, 3181-3295, 3348-3416`
- `C:\CLAUDE\WHEREDNGN\State.lua:38-175, 519-534, 770-823, 1300-1450, 1900-1920, 191-247`
- `C:\CLAUDE\WHEREDNGN\Net.lua:155-460, 962-1053, 2026-2050, 2120-2340, 2401-2470, 2473-2638, 2640-2807, 2829-2846, 2862-3073`
- Existing reports: `_track_B_code/B-UI-01_button_rendering.md`,
  `B-UI-02_banner_score.md` (consumed; this report is non-overlapping
  state-machine focus, not a re-audit of layout findings).

---

## Executive verdict

The eight banner / window subsystems in scope are **mostly correct on
state lifecycle**. Six prior audits (v0.5.4, v0.5.17, v0.7.1 audit, B-UI-01,
B-UI-02, D-RT-13) have already hardened the scoring/result paths. The
state-machine slice this report adds focuses on **flicker, layering,
pause interaction, and localized text** — and surfaces **eight
genuinely new findings**:

| ID | Sev | Subsystem | Title |
|----|-----|-----------|-------|
| E-UI-01-1 | HIGH | SWA deny / cancel | `S.s.swaDenied` set but UI never reads it — SWA caller has no deny feedback |
| E-UI-01-2 | HIGH | Localized text | `قبلك` button label is unreadable in non-Arabic-font locales (acknowledged-elsewhere bug repeated here) |
| E-UI-01-3 | MED | SWA invalid signal | Takweesh-cancelled SWA banner closes with NO carry-over of caller's hand into the takweesh result |
| E-UI-01-4 | MED | Click-through during pause | Cards + action buttons receive clicks during pause; Net layer silently drops |
| E-UI-01-5 | MED | Pause overlay | Pause overlay covers `centerPad` only — side seat badges, action bar, hand row remain interactable |
| E-UI-01-6 | MED | Wall-clock timer drift | `redealing` 3.5s timer + `swaDenied` 3s timer ignore pause; long pause silently clears |
| E-UI-01-7 | LOW | _OnSWAOut | Non-host stale `swaRequest` survives until next round-start (phase guard saves it) |
| E-UI-01-8 | LOW | Pre-empt window | Eligibility shrink works; UI button auto-hides correctly when seat removed |

Plus four explicit confirmations of correct behaviour in scenarios
the user asked about (and which were not bugged):

- E-UI-01-C1: SWA permission denied → caller's banner clears (the
  hidden hole is the lack of a denial **message**, not the banner clear).
- E-UI-01-C2: SWA 5-sec timeout → host `swaRequest` clears via
  `HostResolveSWA`, banner hides via phase guard.
- E-UI-01-C3: AKA banner persists across `U.Refresh()` redraws —
  state-driven, idempotent `:Show()` on every refresh.
- E-UI-01-C4: Bel/Triple/Four/Gahwa action-bar buttons **replace** by
  phase, never layer; multiplier flags accumulate correctly in the
  status-line `[Bel (x2)+Triple (x3)+Four (x4)]` block.

**Severity tally**: 0 CRIT · 2 HIGH · 4 MED · 2 LOW · 4 INFO confirmations.

---

## Banner state inventory (v0.10.2 canonical)

| Banner / window | Frame | State source | Trigger | Clear path |
|---|---|---|---|---|
| Pause overlay | `pauseOverlay` (UI.lua:1269) | `S.s.paused` | `LocalPause(true)` | `LocalPause(false)` → `ApplyPause` |
| AKA toast | `akaBanner` (UI.lua:1295) | `S.s.akaCalled` | `ApplyAKA` (post-N.LocalAKA / _OnAKA) | `ApplyTrickEnd` (any trick close) |
| SWA pending | `swaBanner` (UI.lua:1390) | `S.s.swaRequest` | `LocalSWA` / `_OnSWAReq` | timer / Takweesh / deny / `HostResolveSWA` |
| SWA result | `tablePanel.banner` (UI.lua:1496) | `S.s.swaResult` | `HostResolveSWA` / `_OnSWAOut` | `ApplyStart` next round |
| Takweesh result | same banner | `S.s.takweeshResult` | `HostResolveTakweesh` | `ApplyStart` next round |
| Round result | same banner | `S.s.lastRoundResult` (host) / `lastRoundDelta` | `S.ApplyRoundEnd` | next round / `Reset` |
| Game-end | same banner | `S.s.winner`, `S.s.cumulative` | `ApplyGameEnd` | `Reset` |
| Redeal | same banner | `S.s.redealing` | `ApplyRedealAnnouncement` | wall-clock 3.5s OR next round |
| Overcall | `overcallBanner` (UI.lua:1322) | `S.s.overcall` | post-Hokm 5s window | phase exit |
| Pre-empt | action-bar buttons (UI.lua:1943) | `S.s.preemptEligible` | round-2 Sun-on-Ace | `ApplyPreempt` / all-pass |
| Bel/Triple/Four/Gahwa | action-bar `addConfirmAction` | `S.s.phase` ∈ {DOUBLE,TRIPLE,FOUR,GAHWA} | `ApplyDouble` / `ApplyTriple` / `ApplyFour` / `ApplyGahwa` | `LocalSkipDouble` / next escalation |
| swaDenied (DESIGNED toast) | NONE — no UI consumer | `S.s.swaDenied` | deny path in `_OnSWAResp` | wall-clock 3s OR `Reset` |

---

## Scenario verdicts

### Scenario 1 — SWA banner stale flicker (3 sub-cases)

**Verdict: 1a CLEAN, 1b CLEAN, 1c CLEAN-but-misleading.**

#### 1a. Permission denied → banner clears

`Net.lua:2619` (non-host responder) and `:2754` (host / `_OnSWAResp`)
both set `S.s.swaRequest = nil` immediately on deny, then call
`U.Refresh()`. `renderSWABanner` (`UI.lua:3197-3204`) reads `req` from
`S.s.swaRequest` and runs `b:Hide()` + clears card slots when `req` is
nil. **Banner closes cleanly.** ✓

But — the `S.s.swaDenied` toast struct (set at the same time, with
`{caller, denier, ts}`) has **no UI consumer**. See E-UI-01-1.

#### 1b. 5-sec timeout → banner clears

Two timer paths:
- `_OnSWAReq` → `Net.lua:2691-2729` schedules `C_Timer.After(windowSec, …)`. Inside, sets `S.s.swaRequest = nil` then calls `HostResolveSWA`. Host pause-respecting (line 2701).
- `LocalSWA` host path → `Net.lua:2546-2576`. Same guard.

After resolution, `HostResolveSWA` flips phase to `PHASE_SCORE` via
`S.ApplyRoundEnd`. `renderSWABanner`'s phase guard at `UI.lua:3198`
(`S.s.phase ~= K.PHASE_PLAY`) hides banner. **Cleanly clears.** ✓

#### 1c. Caller's hand is invalid (Takweesh-caught) → "banner closes WITH the invalid signal shown?"

Sequence:
1. SWA banner active (hand visible).
2. Opponent presses TAKWEESH → `N.LocalTakweesh` → `HostResolveTakweesh`.
3. `Net.lua:2144`: `S.s.swaRequest = nil` (explicit).
4. `Net.lua:2273`: `S.s.lastRoundResult = nil`.
5. `Net.lua:2275`: `S.s.takweeshResult = { caller, offender, card, reason, caught=true }`.
6. `S.ApplyRoundEnd(...)` → phase=PHASE_SCORE.
7. UI: SWA banner hides (phase guard). Round banner shows takweeshResult.

**The banner DOES close**, but the SWA-caller's hand is NOT carried
into the takweesh result struct. The takweeshResult shows only the
offender's card + reason. If the SWA-caller WAS the offender (caught
discarding illegally during SWA), the takweesh banner shows that one
card; the rest of the SWA-caller's hand is gone from the UI before
the player can re-inspect it. This is a **MED-severity UX gap**, not
a state-machine bug:

- **State-machine**: clean transition, no flicker.
- **UX**: when SWA + Takweesh combine, the player loses visibility
  into "what hand did the caller try to claim with?" because
  `S.s.swaRequest.encodedHand` is gone before the takweesh banner
  opens.

See E-UI-01-3 below for fix shape.

#### Repro for 1c
1. Hokm contract, seat 2 calls SWA with 4 cards remaining.
2. SWA permission window opens, swaBanner shows seat 2's 4 cards.
3. Within the 5s window, opp seat 3 presses TAKWEESH (after spotting
   an illegal play in trick 4).
4. `HostResolveTakweesh` finds the illegal card (e.g. 9♦ in `S.s.tricks[4].plays[2]`).
5. `swaRequest` cleared, `takweeshResult` set, phase → PHASE_SCORE.
6. **UI shows**: takweesh result with the offending card "9♦ — must follow suit". The SWA's other 3 cards (Q♣, J♥, 7♠) are gone from screen.
7. Player rationale: "did the SWA claim itself ALSO get penalized? what was in the hand?" — no answer in the UI.

---

### Scenario 2 — AKA banner

**Verdict: All three sub-cases CLEAN.**

#### 2a. Show partner's seat + suit

`UI.lua:3236-3257` `renderAKABanner`:
```lua
local glyph = K.SUIT_GLYPH[call.suit] or call.suit
b.text:SetText(("|c%sAKA|r %s — %s"):format(teamCol, glyph, nm))
```
Shows: caller name (via `shortName`), suit glyph (♠♥♦♣). Color-coded
by `R.TeamOf(caller) == R.TeamOf(localSeat)` (green=team / red=opp).
✓

#### 2b. Persist across screen redraws

`U.Refresh()` calls `renderAKABanner` unconditionally. The banner
state lives in `S.s.akaCalled`. As long as `akaCalled` is non-nil,
every refresh re-shows the frame. Idempotent `:Show()`. WoW UI
lifecycle quirks (frame hides on parent re-anchor / scale change)
are auto-recovered by next refresh. ✓

#### 2c. Clear when AKA-suit trick completes

`State.lua:1327` — `s.akaCalled = nil` at every `ApplyTrickEnd`. This
is **eager**: clears at the end of EVERY trick, not just the AKA-suit
trick. By design — the AKA call is for the trick following the call.
The Saudi rule states "AKA must be called BEFORE leading", so the
banner only ever covers ONE trick (the trick the caller is about to
lead). Eager clear at any trick close is correct. ✓

#### One micro-issue

The AKA banner anchor `(TOP, centerPad, TOP, 0, -4)` and the SWA
banner anchor `(TOP, centerPad, TOP, 0, -32)` overlap if both render
simultaneously. Already noted in B-UI-02. **Not reachable in canonical
play** (SWA only fires when AKA-irrelevant: defender-team SWA never
co-occurs with a partner AKA in the same trick).

---

### Scenario 3 — Escalation banner cascade (Bel→Triple→Four→Gahwa)

**Verdict: CLEAN — replace, never layer.**

There is **no dedicated banner frame** for the escalation chain.
Visual representation is two-fold:
1. **Action bar** — `addConfirmAction` buttons in `UI.lua:1756-1827`,
   gated by `S.s.phase`. Each phase replaces the previous (only one
   `S.s.phase` is active at any time, and `renderActions` rebuilds the
   bar from scratch on every refresh).
2. **Status text** — `statusFor()` at `UI.lua:2862-2867`:
   ```
   PHASE_DOUBLE → "Defenders: Bel? (×2)"
   PHASE_TRIPLE → "Bidder: Triple? (×3)"
   PHASE_FOUR   → "Defenders: Four? (×4)"
   PHASE_GAHWA  → "Bidder: Gahwa? (match-win)"
   ```
3. **Contract line** — `renderStatus()` at `UI.lua:3322-3326`
   accumulates flags into `[Bel (x2)+Triple (x3)+Four (x4)]`. This
   is the only place where the multiplier history is **layered**, and
   it does so correctly per the (already-audited) B-UI-02 finding
   (with the type-blind-Sun caveat from D-RT-09 F4).

#### Multiplier display per step
- After Bel: `[Bel (x2)]` — multiplier ×2
- After Triple (responding to Bel): `[Bel (x2)+Triple (x3)]` — multiplier ×3
- After Four (responding to Triple): `[Bel (x2)+Triple (x3)+Four (x4)]` — multiplier ×4
- After Gahwa: `[Bel (x2)+Triple (x3)+Four (x4)+Gahwa (match)]` — match-win flag, multiplier still ×4

The action-bar buttons themselves carry the multiplier label inline:
- "Bel & open" / "Bel & closed" → x2
- "Triple & open (x3)" / "Triple & closed (x3)" → x3
- "Four & open (x4)" / "Four & closed (x4)" → x4
- "Gahwa (match-win)" — terminal

✓ Correct multiplier at each step.

**Routing caveat** (already documented as B-UI-01 F-3 / D-RT-22): the
trailing-bidder Bel routing is broken when the bidder is on the
behind team. This is **routing**, not state-machine — flagged for
completeness but already covered.

---

### Scenario 4 — Pre-empt button visibility (قبلك)

**Verdict: CLEAN on shrink; HIGH localized-text bug.**

#### 4a/4b — Phase exit / shrink: CLEAN

`UI.lua:1943-1958` gates the button on (phase==PHASE_PREEMPT) AND
(`preemptEligible` non-nil) AND (`localSeat ∈ preemptEligible`). All
three are state-driven and re-evaluated each refresh:

- `ApplyPreemptPass` (`State.lua:1909-1919`) does
  `table.remove(s.preemptEligible, i)` then nils when empty.
- `ApplyPreempt` (`State.lua:1900-1907`) nils the whole list and
  jumps phase to PHASE_DEAL2BID.
- `_FinalizePreempt` (`Net.lua:1038-1053`) nils + `ApplyContract`.

Button auto-hides correctly in all three exit paths. ✓

#### 4c — HIGH: `قبلك` is unreadable in non-Arabic-font locales

`UI.lua:1952`:
```lua
addConfirmAction("|cff66ddffقبلك (Pre-empt)|r", ...)
```

`K.CARD_FONT = "Fonts\\ARIALN.TTF"` (Constants.lua:36) — ARIALN.TTF
(WoW Arial Narrow) does NOT include Arabic glyphs. The same
constraint is **explicitly acknowledged** at UI.lua:2041-2045 (the
AKA button uses Latin "AKA" because of this) and at UI.lua:2345-2353
(the Pass-bid bubble was changed from `بس` to "Pass"/"wla" because
of player-reported empty-box bug).

**The Pre-empt button is the only remaining hardcoded-Arabic
user-visible label** in v0.10.2. On enUS/deDE/frFR/etc. locales the
button reads `▢▢▢▢ (Pre-empt)` — literal empty boxes + parenthetical
English. Functional (click works), but illegible.

Severity HIGH because pre-empt is rare (round-2 Sun on Ace), the
window is the only player handle, and 60s AFK closes the window —
players unfamiliar with Arabic naming convention may miss their
chance.

#### Repro
1. Set WoW client locale to enUS / deDE / frFR.
2. Trigger PHASE_PREEMPT (round-2 Sun on Ace bid card).
3. Observe button label: empty boxes + "(Pre-empt)".

---

### Scenario 5 — Pause overlay

**Verdict: PARTIAL — covers centerPad only; click-through; banner
countdowns freeze correctly but two wall-clock timers don't.**

#### Frame coverage (UI.lua:1269-1273)
```lua
local pauseOverlay = CreateFrame("Frame", nil, centerPad, "BackdropTemplate")
pauseOverlay:SetAllPoints(centerPad)
pauseOverlay:SetFrameStrata("DIALOG")
```

Overlay covers ONLY centerPad. NOT covered: side seat badges, hand
row, action bar, score/contract text. `:EnableMouse(true)` is NOT
set, so the overlay is transparent to clicks — players can still
click cards / action buttons during pause. Net layer catches with
`if S.s.paused then return end` at every entry point and silently
drops the click. No UI feedback — looks frozen to the user.

#### Banner timer freeze under pause

| Timer | Pause-respect | Source |
|---|---|---|
| `swaBanner.OnUpdate` countdown | YES | UI.lua:1458 |
| `overcallBanner.OnUpdate` countdown | YES | UI.lua:1350 |
| `swaRequest` 5s auto-resolve (host) | YES | Net.lua:2552, 2701 |
| `swaDenied` 3s wall-clock C_Timer | **NO** | Net.lua:2627, 2761 |
| `redealing` 3.5s C_Timer | **NO** | State.lua:149-156 |
| Bel/Triple/Four/Gahwa AFK timers | YES | `StartBelTimer` re-arms on resume |
| `_HostStepPlay` 2.2s trick resolve | YES | Net.lua:1631-1634 |
| `_pulseTicker` (AFK pulse) | NO | UI.lua:3402 — cosmetic 1.4s |

Two MED bugs here: **E-UI-01-4** (silent click drop) and **E-UI-01-6**
(`redealing` / `swaDenied` timers ignore pause).

---

### Scenario 6 — Localized text (Arabic) — visibility per locale

**Verdict: HIGH — `قبلك` button (E-UI-01-2 above), otherwise CLEAN.**

Audit of every user-visible Arabic glyph in v0.10.2 UI: only ONE
hit — `UI.lua:1952` `قبلك (Pre-empt)`. All other Arabic in UI.lua
is in code comments. Player-visible labels elsewhere are Latin
transliterations ("AKA", "SWA", "Bel", "Triple", "Four", "Gahwa",
"TAKWEESH", "BALOOT", "AL-KABOOT", "WIN", "LOST", "Pass", "wla",
"Awal") explicitly because of acknowledged Arial-Narrow font
limitation. `K.SUIT_GLYPH = {♠♥♦♣}` (U+2660-U+2663 BMP) renders fine.
Voice cues (`SND_VOICE_AKA/GAHWA/FOUR/SUN/AWAL`) are audio files,
locale-independent.

---

### Scenario 7 — Click-through during banner

**Verdict: PARTIAL — banner frames don't intercept; rely on Net-layer
guards.**

#### Banner frames inspected
- `pauseOverlay` (UI.lua:1269): `EnableMouse` not set. Click-through.
- `akaBanner` (UI.lua:1295): no mouse handlers, `EnableMouse` not set.
- `overcallBanner` (UI.lua:1322): no mouse handlers.
- `swaBanner` (UI.lua:1390): no mouse handlers.
- Round-result `banner` (UI.lua:1496): no mouse handlers.

**None of the banners block clicks.** The cards, action buttons,
pause/peek/settings buttons all remain clickable through banners.

#### Where this matters

1. **Banner-card-play overlap**: a banner spans the centre area; the
   trick cards are in the same area. But trick cards are display-only
   (no `OnClick`) — only the local player's hand-row cards
   (`UI.lua:2213`) are clickable. The hand row is below centerPad, so
   no banner overlap.
2. **Critical buttons** (Pause, Settings, Reset, Peek): these are
   anchored to the main frame's TOP-RIGHT (UI.lua:1235, 1249, 1234)
   at `FULLSCREEN_DIALOG` strata. The pause button is **explicitly
   re-stacked** above the pause overlay (UI.lua:1289), so it remains
   clickable while paused. ✓

#### One concern (LOW)

When `swaBanner` (anchored TOP, centerPad, TOP, 0, -32, h=100) is
showing during PHASE_PLAY, the AKA banner (TOP, centerPad, TOP, 0,
-4, h=22) overlaps. Both have `FrameLevel = centerPad:GetFrameLevel() + 50`.
WoW renders sibling frames in creation order — the AKA banner is
created first (UI.lua:1295), the SWA banner second (UI.lua:1390), so
the SWA banner renders ABOVE the AKA banner. The AKA banner is
partially obscured by the SWA banner's top edge (~16 pixels of
overlap). Both already noted in B-UI-02.12. **State-machine clean,
visual nit.**

---

### Scenario 8 — UI-dimming AKA-blindness

**Verdict: CONFIRMED — already-documented as B-UI-01 F-1 (HIGH /
D-RT-04 / B-Net-01 F-OP-12).**

`State.lua:1961-1969` (`S.GetLegalPlays`):
```lua
function S.GetLegalPlays()
    if not s.localSeat or not S.IsMyTurn() or not s.contract then return {} end
    if s.phase ~= K.PHASE_PLAY then return {} end
    local legal = {}
    for _, c in ipairs(s.hand) do
        local ok = R.IsLegalPlay(c, s.hand, s.trick, s.contract, s.localSeat)
        -- ↑ MISSING 6th arg: akaCalled
        if ok then legal[#legal + 1] = c end
    end
    return legal
end
```

`Rules.lua:89` signature: `R.IsLegalPlay(card, hand, trick, contract, seat, akaCalled)`.

Comparable host-side calls that DO pass `akaCalled`:
- `Net.lua:2040` (`LocalPlay`) — `R.IsLegalPlay(card, S.s.hand, S.s.trick, S.s.contract, S.s.localSeat, S.s.akaCalled)`. ✓
- `Net.lua:3412` (`_HostTurnTimeout` AFK auto-pick) — passes `S.s.akaCalled`. ✓
- `Net.lua:4136` (`_OnSWAReq` recursion). ✓
- `State.lua:1219` (`S.HostValidateAndApply`) — passes `s.akaCalled`. ✓

The only path that omits the parameter is `S.GetLegalPlays`, which
feeds the UI's gold/red border highlighting (`UI.lua:2134, 2186-2198`).

**Effect**: AKA-receiver relief (Saudi rule J-066/J-067 part 2,
encoded at `Rules.lua:115-121` and `:171-175`) is invisible to the
local UI's card-dim path. Gold borders (legal) show only "must follow
suit / must trump" cards; red borders (warning) show all the discard
cards that ARE legal under AKA-relief but the UI says "Takweesh
risk".

The UI is **training the player against the AKA convention** the
addon is asking them to follow. Already-flagged as HIGH in B-UI-01.
**Confirmed and re-documented here for the state-machine track**;
no new findings beyond B-UI-01.

---

## Fix shapes (NOT applied — read-only audit)

### E-UI-01-1 — render swaDenied toast
Add early branch in `renderBanner` (UI.lua:2942):
```lua
if S.s.swaDenied then
    local sd = S.s.swaDenied
    local cName = (sd.caller and S.s.seats[sd.caller]
                   and shortName(S.s.seats[sd.caller].name)) or "?"
    local dName = (sd.denier and S.s.seats[sd.denier]
                   and shortName(S.s.seats[sd.denier].name)) or "?"
    banner:Show()
    banner:SetBackdropBorderColor(0.95, 0.30, 0.20, 1)
    banner.title:SetText(("|cffff5544SWA denied|r — %s blocked %s"):format(dName, cName))
    banner.final:SetText("Round resumes.")
    return
end
```

### E-UI-01-2 — replace `قبلك` with Latin transliteration
At UI.lua:1952, mirror the v0.5.x AKA / Pass / Bel / Triple pattern:
```lua
addConfirmAction("|cff66ddffQablak (Pre-empt)|r", ...)
```
Audio path (`SND_VOICE_*` if added) carries the Arabic feel.

### E-UI-01-3 — preserve SWA caller hand into Takweesh result
In `HostResolveTakweesh` (Net.lua:2127), before clearing
`S.s.swaRequest`, snapshot:
```lua
local prevSwa = S.s.swaRequest
S.s.swaRequest = nil
-- ...later when takweeshResult is set:
if prevSwa and prevSwa.caller then
    S.s.takweeshResult.swaCaller = prevSwa.caller
    S.s.takweeshResult.swaHand = prevSwa.encodedHand
end
```
Then UI's takweesh banner can render an extra line "SWA claim was: <cards>".

### E-UI-01-4 + E-UI-01-5 — pause click-block + full overlay
Two-part:
- Add `if S.s.paused then return end` early-out to card-tile
  (UI.lua:2213-2220) and action-button click handlers.
- Re-parent `pauseOverlay` to `tablePanel` (covering full window) or
  add a sibling overlay at higher strata.

### E-UI-01-6 — pause-aware C_Timer wrapper
Wrap `redealing` (State.lua:149) and `swaDenied` (Net.lua:2627, 2761)
clears in a re-arming helper:
```lua
local function pausedAwareAfter(sec, fn)
    C_Timer.After(sec, function()
        if S.s.paused then
            local function poll()
                if S.s.paused then C_Timer.After(0.5, poll)
                else fn() end
            end
            poll()
        else
            fn()
        end
    end)
end
```

### E-UI-01-7 — clear stale swaRequest in _OnSWAOut
At Net.lua:2840, mirror `HostResolveSWA`'s host-side cleanup:
```lua
S.s.swaRequest = nil
S.s.lastRoundResult = nil
S.s.trick = nil
```

---

## Summary table

| ID | Severity | Subsystem | Title |
|---|---|---|---|
| E-UI-01-1 | HIGH | SWA deny | `swaDenied` struct populated, NEVER read by UI |
| E-UI-01-2 | HIGH | Localized text | `قبلك` button unreadable in non-Arabic-font locales |
| E-UI-01-3 | MED | SWA / Takweesh | Takweesh-cancelled SWA loses caller's hand context |
| E-UI-01-4 | MED | Pause click-through | Cards + action buttons receive clicks during pause; silent drop |
| E-UI-01-5 | MED | Pause overlay | Overlay covers centerPad only; side panels interactable |
| E-UI-01-6 | MED | Pause / timers | Wall-clock C_Timer.After ignores pause for redealing + swaDenied |
| E-UI-01-7 | LOW | _OnSWAOut | Non-host stale `swaRequest` survives until next ApplyStart |
| E-UI-01-8 | LOW | Pre-empt | Eligibility-shrink correct (confirmation) |
| E-UI-01-C1 | INFO | SWA permission deny | Banner clears cleanly (the gap is feedback, not flicker) |
| E-UI-01-C2 | INFO | SWA timeout | Banner clears cleanly via phase guard |
| E-UI-01-C3 | INFO | AKA banner | Idempotent show across redraws; per-trick clear |
| E-UI-01-C4 | INFO | Escalation chain | Phase-replace correct; multipliers display correctly |

Cross-cut to existing reports:
- B-UI-01 F-1 (D-RT-04, AKA-blind UI dim) — confirmed via Scenario 8
- B-UI-01 F-3 (D-RT-22, trailing-bidder Bel routing) — Scenario 3
  notes for completeness
- B-UI-02-1 (HIGH) — Match-end via Takweesh/SWA shows zero detail —
  related but distinct from E-UI-01-3 (E-UI-01-3 is mid-round
  takweesh-cancels-SWA, B-UI-02-1 is match-ending takweesh/SWA).
- B-UI-02-N4 — `renderBanner` doesn't honor pause — overlap with
  E-UI-01-6 but at different layer.

---

## Files referenced (absolute paths)

- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua`
- `C:\CLAUDE\WHEREDNGN\UI.lua`
- `C:\CLAUDE\WHEREDNGN\State.lua`
- `C:\CLAUDE\WHEREDNGN\Net.lua`
- `C:\CLAUDE\WHEREDNGN\Constants.lua`
- `C:\CLAUDE\WHEREDNGN\Rules.lua`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-UI-01_button_rendering.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-UI-02_banner_score.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-13_swa_permission_race.md` (cross-cut)

---

End of E-UI-01.
