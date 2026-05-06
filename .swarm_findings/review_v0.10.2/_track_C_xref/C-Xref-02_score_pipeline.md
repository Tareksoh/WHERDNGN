# C-Xref-02: Score pipeline cross-cut (v0.10.2)

Trace: card play → trick attribution → meld detection → R.ScoreRound
→ Net broadcast → S.ApplyRoundEnd → cumulative.

**Version under review:** v0.10.2 (CHANGELOG.md head)
**Files inspected:**
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — R.ScoreRound (661-953), R.DetectMelds (220-290), R.SumMeldValue (503-507), R.CompareMelds (343-353), R.TrickPoints (67-73), R.TeamOf (25-28), R.CurrentTrickWinner (34-59)
- `C:\CLAUDE\WHEREDNGN\State.lua` — S.ApplyRoundEnd (1463-1585), S.ApplyRoundResult (1591-1595), S.ApplyGameEnd (1597-1607), S.HostScoreRoundResult (1921-1926)
- `C:\CLAUDE\WHEREDNGN\Net.lua` — N.SendRound (271-290), N._OnRound (1503-1508), N._HostStepAfterTrick (1649-1719), N.HostResolveTakweesh (2127-2339), N.HostResolveSWA (2862-3073)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — Bot.PickMelds (3408-3418)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — full file (multipliers, hand totals, Al-Kaboot, melds)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X1_penalty_multiplier.md` (the X1 cross-ref)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\43_score_calculation_extracted.md` (video #43 distillation)

---

## 1. Pipeline overview

The pipeline has THREE entry points to the round-score state:

```
                                      ┌─ R.ScoreRound (Rules.lua:661) ──┐
   normal end-of-trick-8 ─────────────┤                                  ├─ S.ApplyRoundEnd
   N._HostStepAfterTrick (Net:1649)   │  (returns result.final.A,B,     │  (State.lua:1463)
                                      │   sweep, bidderMade, gahwa*)    │
                                      └──────────────────────────────────┘
                                                                        │
   Qaid (Takweesh)                                                      │
   N.HostResolveTakweesh (Net:2127) ──── direct addA/addB calc ─────────┤
                                                                        │
   Invalid SWA                                                          │
   N.HostResolveSWA invalid branch (Net:2920) ── direct calc ───────────┤
                                                                        │
   Valid SWA                                                            │
   N.HostResolveSWA valid branch (Net:2988) ──→ R.ScoreRound (synth) ──┘
```

All three then run:
1. `S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)` — sets cumulative, phase=SCORE, fanfare cues, telemetry write
2. Broadcast (`N.SendRound` for normal/Qaid; `N.SendSWAOut` for SWA) — receivers run `N._OnRound` / `N._OnSWAOut` which call the same `S.ApplyRoundEnd`
3. Target check `if totA >= S.s.target or totB >= S.s.target` → `S.ApplyGameEnd(winner)` + `N.SendGameEnd(winner)`

Meld detection happens twice: once at decl-time (`Bot.PickMelds` → `R.DetectMelds` → `S.ApplyMeld`, building `S.s.meldsByTeam`), and again at score-time (`R.ScoreRound` reads `meldsByTeam`).

---

## 2. Per-path trace tables

### Path 1: Make (bidder strict-majority)

| Stage | Code | Behavior |
|---|---|---|
| Trick attribution | `R.CurrentTrickWinner` (Rules.lua:34) | Trump-played seat wins or lead-suit highest; trickCount increments |
| Last-trick bonus | `R.ScoreRound` (Rules.lua:670-673) | `+K.LAST_TRICK_BONUS=10` raw to last-trick winner team |
| Meld winner-takes | `R.CompareMelds` (Rules.lua:343-353) → `R.ScoreRound` (Rules.lua:858-861) | Best-meld holder gets ALL their team's meld value; loser meld zeroed |
| Threshold check | `R.ScoreRound` (Rules.lua:763-766) | `bidderTotal = teamPoints[bidderTeam] + (effMeld + belote)` (effMeld respects compare-winner only) |
| Outcome | `R.ScoreRound` (Rules.lua:775-776) | `bidderTotal > oppTotal` → `outcome_kind = "make"` (strict greater) |
| `cardA/cardB` | Rules.lua:858 | Each team's `teamPoints` |
| Multiplier | Rules.lua:883-893 | `mult = 1 × (Sun ? 2 : 1) × (highest active rung)` — Sun gates Triple/Four/Gahwa OFF (R2 fix) |
| Belote | Rules.lua:908-912 | +20 raw AFTER mult (multiplier-immune per X1) |
| div10 | Rules.lua:918 | `(x+5)/10` (floor of 5-rounds-UP) |
| Game-points formula | — | `((teamCardPts + ownMelds) × mult + belote_if_team) ÷ 10` |
| Cumulative update | `S.ApplyRoundEnd` (State.lua:1464-1465) | `s.cumulative.A = totA` set directly (totA passed in is `cumulative.A + addA` from caller) |
| Win condition | `N._HostStepAfterTrick` (Net.lua:1683) | `if totA >= S.s.target or totB >= S.s.target` — default 152 (S.s.target initialized elsewhere) |

**Verdict:** Path 1 is correct. Numerical example: Hokm bidder 90 cards + 50 own meld vs def 72 + 0 meld → bidder = 140, def = 72; (90+50)×1 = 140 raw → 14 gp; def 72×1 = 72 raw → 7 gp. Match expected.

---

### Path 2: Fail (bidder under threshold)

| Stage | Code | Behavior |
|---|---|---|
| Outcome detection | Rules.lua:777-778 | `bidderTotal < oppTotal` → `outcome_kind = "fail"` |
| Card attribution | Rules.lua:837-838 | `cardA = (oppTeam == "A") ? handTotal : 0` — defenders take ALL of `handTotal` (162 Hokm / 130 Sun) |
| Meld treatment | Rules.lua:839-840 | **Both teams keep their OWN melds** — `meldPoints.A = meldA; meldPoints.B = meldB` |
| Multiplier scope | Rules.lua:895-896 | `(card + meldPoints) × mult` — meld is multiplied (per X1 H-36.13) |
| Belote | Rules.lua:908-912 | +20 raw post-mult; cancellation by same team's ≥100 meld AND TEAM-LEVEL (R.ScoreRound is correct here) |
| div10 | Rules.lua:918 | `(x+5)/10` |
| Cumulative | S.ApplyRoundEnd (State.lua:1464-1465) | Set directly |

**Numerical example (matches X1's worked-cell-2):** Sun-Bel, defenders take handTotal, bidder team had own seq3 (20 raw):
- Defenders: `(130 + 0) × 4 = 520` → 52 gp
- Bidder: `(0 + 20) × 4 = 80` → 8 gp
Total: defenders 52, bidder 8.

**Verdict:** Path 2 is correct under the user-confirmed reading from v0.10.0 M1: regular (non-Qaid) fail keeps each team's own melds. CHANGELOG.md:124-129 documents this scope decision deliberately.

---

### Path 3: Take (Bel/Four tied 81/162 — rule 4-10 inversion)

| Stage | Code | Behavior |
|---|---|---|
| Tie detection | Rules.lua:779-812 | `bidderTotal == oppTotal` AND escalation rung is `double` or `four` (defender-buyer rungs) |
| Sun normalization | Rules.lua:799-801 | Sun forces highest = `double` if doubled, else `none` (ignores Triple/Four/Gahwa per R2) |
| Inversion verdict | Rules.lua:807 | `if highest == "double" or highest == "four" then outcome_kind = "take"` |
| Card attribution | Rules.lua:850-851 | `cardA = (bidderTeam == "A") ? handTotal : 0` — bidder takes the full hand |
| Meld treatment | Rules.lua:852-853 | Each team keeps own melds (same as fail branch) |
| Multiplier | Rules.lua:883-893 | Same formula |
| `bidderMade` | Rules.lua:814 | `bidderMade = true` (because `take` is a bidder win) |

**Verdict:** Correct. The v0.10.0 R2 normalization correctly forces Sun's highest rung to "double" only — pre-v0.10.0 a Sun-tripled or Sun-foured fixture (impossible in practice but possible via stale resync) would have been treated as "four" tier, falsely flipping a tie to bidder-takes.

---

### Path 4: Sweep (Al-Kaboot — 8/8 tricks)

| Stage | Code | Behavior |
|---|---|---|
| Sweep detection | Rules.lua:712-714 | `if trickCount.A == 8 then sweepTeam = "A"` etc. |
| Card attribution | Rules.lua:817-822 | `bonus = K.AL_KABOOT_HOKM(=250) or K.AL_KABOOT_SUN(=220)`; full bonus to sweeper |
| Meld treatment | Rules.lua:821-822 | Sweeper takes ALL their own melds; loser's discarded |
| Multiplier | Rules.lua:895-896 | Bonus + sweeper-melds multiplied. Sun-Kaboot mult: `220 × 2 = 440 ÷ 10 = 44 gp` (matches Pagat). Hokm-Kaboot: `250 × 1 = 250 ÷ 10 = 25 gp` (matches Pagat). |
| Belote (override) | Rules.lua:721-723 | Sweep override: belote follows sweeper even if K+Q holder is on losing team. Comment explicit "Saudi winner-takes-all reading covers belote too." |
| div10 | Rules.lua:918 | `(x+5)/10` |

**Worked: Hokm Bel sweep, sweeper has 50-meld + Belote (no cancellation):**
- raw = `(250 + 50) × 2 + 20 = 620` → div10 = 62 gp.
- (Belote stands because 50-meld < 100 threshold for cancellation.)

**Verdict:** Correct. The Saudi sweep convention (winner takes belote) is intentional per the comment block at Rules.lua:716-723; CLAUDE.md note says belote is multiplier-immune which is consistent.

---

### Path 5: Reverse-Kaboot (defenders sweep + bidder led trick 1)

| Stage | Code | Behavior |
|---|---|---|
| Detection | — | **NOT IMPLEMENTED** |
| Constant | Constants.lua | `K.AL_KABOOT_REVERSE` does not exist (grep returns 0 hits) |
| Score branch | Rules.lua:712-723 | The sweep branch awards either side `K.AL_KABOOT_HOKM/SUN` (250/220 raw) — same value regardless of which team swept |

**Source state:** The v0.10.0 review (`REVIEW.md:245`) confirms +88 raw is corroborated by both videos #15 and #16 (single-source flag downgraded). Sun-only per G15-10. Most rule-sets also require lead card = Ace (MF-18).

**Verdict:** **GAP, not bug.** A defender-team sweep in Sun where the bidder led trick 1 is currently scored as a regular Sun-Kaboot (220 raw → 22 gp default, or 88 gp under Bel-Sun). Per source corroboration, it should be 88 raw (single-source value, +88 to defenders) — but this is in the broader "missing features" backlog (MF-18). Severity LOW — the difference is +66 raw (88 - 22) under no escalation, ~22 gp delta when triggered, and the trigger requires defender-sweep + bidder-led-trick-1. Not a regression; never been wired.

---

### Path 6: Gahwa match-win

| Stage | Code | Behavior |
|---|---|---|
| Per-round score | Rules.lua:926-937 | `gahwaWonGame = true` set unconditionally if `contract.gahwa`; `gahwaWinner = bidderTeam if bidderMade else oppTeam` |
| Match-win override | Net.lua:1669-1678 | `addA = max(addA, target - cumulative.A)` for winner; loser's add zeroed (v0.8.6 H2 fix). Pushes cumulative ≥ target |
| Win detection | Net.lua:1683 | Same `totA >= target` triggers `S.ApplyGameEnd` |
| Tiebreaker priority | Net.lua:1693-1709 | If totA == totB, `gahwaWinner` first, then `bidderMade`, then defensive |

**Verdict:** Correct. The Gahwa branch fully short-circuits normal scoring — even if Gahwa mathematically produced a smaller delta, the `max()` call inflates it to `target - cumulative` so the game ends. Loser's delta is zeroed to avoid the v0.8.6 H2 tiebreaker race.

**Edge case:** Gahwa called inside a Takweesh path (Net.lua:2187 treats `c.gahwa` as ×4 for the per-round penalty) — comment cites "match-win semantic only applies to a fully-played-out round, not a forfeit." Confirmed correct: Qaid path computes 26/16 base with Gahwa as ×4 mult, then standard cumulative update — does NOT short-circuit to match-win.

---

### Path 7: Qaid (Takweesh — N.HostResolveTakweesh)

| Stage | Code | Behavior |
|---|---|---|
| Phase guard | Net.lua:2129 | `if S.s.phase ~= K.PHASE_PLAY then return end` (gates out pre-bid Qaid — design choice per X1 B1) |
| Winner determination | Net.lua:2175 | foundIllegal → caller wins; else opp wins (false-Qaid penalty reverses) |
| handTotal | Net.lua:2177 | 130 Sun / 162 Hokm |
| Mult ladder | Net.lua:2185-2190 | Sun×2, then highest of Bel/Triple/Four/Gahwa (Gahwa = ×4 for forfeit per comment) |
| **OFFENDER MELDS** | Net.lua:2216-2218 | **v0.10.1 M1 fix:** offender team's `mp` = 0; winner team keeps own × mult. Belote independent. |
| Belote scan | Net.lua:2224-2245 | Hokm-only, K+Q same-seat from played cards |
| **Belote cancellation** | Net.lua:2240 | **PER-PLAYER** (`m.declaredBy == kWho`) — DIVERGES from R.ScoreRound's TEAM-LEVEL (Rules.lua:738-746) |
| div10 | Net.lua:2259-2260 | `(x+5)/10` (v0.5.21 align with R.ScoreRound) |
| Cumulative | Net.lua:2261-2264 | totA = cumulative.A + addA; `S.ApplyRoundEnd(addA, addB, totA, totB)` (NOTE: sweep + bidderMade omitted — fanfare gated on `~= nil`) |
| Win check | Net.lua:2324-2334 | Standard `totA >= target` plus tiebreaker (bidder team on tie) |

**Verdict:** Correct on offender-meld semantics (v0.10.1 M1 closure) AND on multiplier scope (per X1's verdict). However, **Belote-cancellation is INCONSISTENT** with R.ScoreRound: Net.lua's Qaid path uses per-player matching (`m.declaredBy == kWho`), but R.ScoreRound (post-v0.9.0 M5) uses team-level (any team meld ≥100 cancels). See "Findings" below.

**Worked numerical examples (X1 conformance check):**

| Scenario | Formula | Game points |
|---|---|---|
| Hokm Qaid no escalation | `(162+0)×1` ÷10 = 16 | 16 ✓ H-36.9 |
| Sun Qaid no escalation | `(130+0)×2` ÷10 = 26 | 26 ✓ H-36.8 |
| Sun Qaid+Bel | `(130+0)×4` ÷10 = 52 | 52 ✓ H-36.13 |
| Sun Qaid+Bel + own seq3 | `(130+20)×4` ÷10 = 60 | 60 ✓ H-36.13 |
| Sun Qaid+Four | `(130+0)×8` ÷10 = 104 | 104 ✓ H-36.13 |

All H-36.13 numerical examples reproduce.

---

### Path 8: Invalid SWA (N.HostResolveSWA invalid branch)

| Stage | Code | Behavior |
|---|---|---|
| Validation | Net.lua:2911-2916 | `R.IsValidSWA(callerSeat, hands, c, trickState)` |
| handTotal | Net.lua:2926 | 130 Sun / 162 Hokm |
| Mult ladder | Net.lua:2930-2935 | Same as Takweesh |
| **OFFENDER MELDS** | Net.lua:2951-2952 | **v0.10.1 M1 fix:** SWA caller (offender) team `mp = 0`; opp keeps own × mult |
| Belote scan | Net.lua:2956-2978 | Same scan as Takweesh |
| **Belote cancellation** | Net.lua:2972 | **PER-PLAYER** (`m.declaredBy == kWho`) — same divergence from R.ScoreRound |
| div10 | Net.lua:2985-2986 | `(x+5)/10` |
| Cumulative | Net.lua:3045-3046, 3058 | `S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam, contractMade)` — passes nil sweep + false bidderMade |
| Win check | Net.lua:3062-3071 | Same as Takweesh |

**Verdict:** Same semantic as Takweesh (Path 7). The v0.10.1 M1 fix is symmetrically applied. Same Belote-cancellation per-player divergence applies here too.

---

## 3. Multiplier scope verification

Per X1's verdict (which inspects all sites + 6 H-36.13 numerical examples):

| Element | Multiplier-applied | Site | OK? |
|---|---|---|---|
| Trick points (made) | YES | Rules.lua:895 | ✓ |
| Qaid base (handTotal) | YES | Net.lua:2248 / 2979 | ✓ |
| Own melds in Qaid | YES — winner side | Net.lua:2248 / 2979 | ✓ |
| Offender's own melds (Qaid) | **N/A** post-v0.10.1: zeroed | Net.lua:2217-2218 / 2951-2952 | ✓ |
| Carré-A in Sun (400 raw direct) | YES — 400 × 2 × any rung ÷ 10 | Constants.lua:95 (=400 post-v0.10.0 R5) | ✓ |
| Belote +20 | NO (post-mult) | Rules.lua:908-912 / Net.lua:2250-2251 / 2981-2982 | ✓ (X1 confirms compatible with H-36.13 + K-27 + CLAUDE.md) |
| Carré-other (T/K/Q/J) | YES | Rules.lua:895 (flows through meldPoints) | ✓ |

**Worked Carré-A in Sun example (per task prompt):**
- 4-Aces in Sun: `K.MELD_CARRE_A_SUN = 400` (Constants.lua:95)
- Sun base ×2: `mult = 2`
- Under Bel: `mult = 4`
- (cardPts + 400) × 2 ÷ 10 if no escalation; or × 4 ÷ 10 under Bel
- **Sun + Bel + own 4-Aces only:** `(0 + 400) × 4 ÷ 10 = 160` game points
- Task prompt says "Sun + Bel: 400×2×2÷10 = 160" — MATCHES.
- Per video #43 (#10) `43_score_calculation_extracted.md:29` distillation: Sun divisor is ÷5; `400 ÷ 5 = 80` — matches `400 × 2 ÷ 10 = 80` for unescalated Sun.

**Verdict:** Carré-A in Sun is correct post-v0.10.0 R5. The 200-raw-with-Sun-×2-stack was a v0.4.x misinterpretation; v0.10.0 bumped it to 400 raw direct.

---

## 4. Carré-A in Hokm cascade re-verify (v0.10.0 X5)

**Pre-v0.10.0 bug:** `R.DetectMelds` had a missing `else` branch for Ace+Hokm — `value` stayed nil and meld silently dropped.

**v0.10.0 fix (Rules.lua:268-287):**

```lua
if rank == "A" then
    value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
else
    value = K.MELD_CARRE_OTHER
end
```

Now Hokm 4-A correctly emits as a 100-raw meld.

**Cascade re-verify — Belote cancellation:** With Hokm K+Q-of-trump holder ALSO holding 4-Aces:
- Pre-v0.10.0: 100-meld DROPPED → `meldsByTeam` had no ≥100 entry → Belote NOT cancelled → +20 silent over-scoring.
- v0.10.2 R.ScoreRound (Rules.lua:738-746): scans `meldsByTeam[belote]` for any meld with `value ≥ 100` (TEAM-level per v0.9.0 M5). Now sees the emitted Hokm 4-A → cancels Belote. ✓
- v0.10.2 Net.HostResolveTakweesh / HostResolveSWA: scans for `m.declaredBy == kWho AND value ≥ 100` (PER-PLAYER). If the Hokm 4-A holder is ALSO the K+Q holder, cancellation fires. If the 4-A holder is the K+Q holder's PARTNER, cancellation does NOT fire — divergence from R.ScoreRound. (See "Findings — F1.")

**Verdict for the prompt:** Yes, R.ScoreRound's cancellation now correctly zeroes Belote in the cascade case. The cascade is closed in `R.ScoreRound`. **However**, the same fix did NOT propagate to the Net.lua Qaid paths (per-player there).

---

## 5. Cumulative & Win-condition consistency

| Path | Site that updates `cumulative` | Site that checks target | Consistent? |
|---|---|---|---|
| Normal end | `S.ApplyRoundEnd` (State.lua:1464-1465) | `N._HostStepAfterTrick` (Net.lua:1683) | ✓ |
| Takweesh | `S.ApplyRoundEnd` (called from Net.lua:2264) | `N.HostResolveTakweesh` (Net.lua:2324) | ✓ |
| Invalid SWA | `S.ApplyRoundEnd` (Net.lua:3058) | `N.HostResolveSWA` (Net.lua:3062) | ✓ |
| Valid SWA | `S.ApplyRoundEnd` (Net.lua:3058) | Same | ✓ |
| MSG_ROUND receiver (non-host) | `S.ApplyRoundEnd` (Net.lua:1507) | **NOT CHECKED on receiver** — relies on host's `MSG_GAMEEND` broadcast | ⚠ — receivers depend on `N.SendGameEnd` (Net.lua:292) for game-end |

**Default target:** `S.s.target or 152` (Net.lua:1670, 2324, 3062). `S.s.target` is initialized in `S.ApplyStart` / `S.Reset` — checked: defaults to 152 across the board.

**Tiebreaker resolution priority (Net.lua:1693-1709 — normal end):**
1. `gahwaWonGame` → `gahwaWinner`
2. `bidderMade=true` → bidderTeam ; `bidderMade=false` → oppTeam
3. Fallback: "A"

**Tiebreaker in Takweesh (Net.lua:2327-2331):**
- Uses `R.TeamOf(S.s.contract.bidder)` — bidder team wins on tie. (Net.lua:1693-1709 actually changes this for failed contracts; Takweesh path is simpler and may be inconsistent — see F2.)

**Tiebreaker in Invalid SWA (Net.lua:3064-3068):**
- Same as Takweesh — bidder team wins tie. Inconsistent with the more nuanced normal-end logic (which considers bidderMade). See F2.

---

## 6. Cross-platform / version skew

**Wire format for MSG_ROUND** (Net.lua:288-289):
```
"R;addA;addB;totA;totB;sweepStr;madeStr"
```
where:
- `sweepStr ∈ {"" | "A" | "B"}` — added in 4th-audit (post-v0.3.0)
- `madeStr ∈ {"" | "0" | "1"}` — three-state encoding (Net.lua:284-287)

**Receiver decode** (Net.lua:567-579) — three-state decode for `bidderMade`. Empty/absent → nil; "1" → true; "0" → false.

**Append-only forward-compat:** N.SendSWAOut comments (Net.lua:225-226) explicitly say "Append-only so pre-v0.3.0 clients reading the old 7-field form work unchanged."

**Cross-version analysis:**

| From (sender) | To (receiver) | Result |
|---|---|---|
| v0.10.x host → v0.10.x peer | Same wire format | OK |
| v0.10.x host → v0.9.x peer | Receiver decodes 5 fields (post-v0.3.0 wire is 7); extra fields ignored if peer is v0.3.0+ | OK if peer ≥ v0.3.0 |
| v0.9.x host → v0.10.x peer | Sender produces 7 fields; receiver decodes 7 | OK |
| v0.3.x peer (5 fields) → v0.10.x peer | Receiver reads sweepStr/madeStr as nil → no fanfare | Graceful degradation |
| Pre-v0.3.0 peer | Receiver decodes 5 fields; sweepStr/madeStr default to nil | Graceful degradation |

**Score numeric-difference risk (older host with bug, newer peer):**
- A v0.4.x host with `K.MELD_CARRE_A_SUN = 200` would broadcast `addA = 40` for a Sun-Bel + 4-Aces-meld scenario. The newer v0.10.x peer would just apply that 40 game points to its cumulative — its local copy is consistent with the host's. So peers don't fight on numeric values; they just inherit whatever the host computed. The bug appears identically on all clients. (Not a sync hazard — purely an authoritative-host-was-wrong issue.)
- v0.10.0 R5 fixed K.MELD_CARRE_A_SUN to 400 — v0.10.x hosts produce correct values, v0.10.x peers receive them.
- v0.10.1 M1 (Qaid offender melds zeroed) — old hosts produced "loser keeps melds" totals; new hosts produce "loser zeroed". Different numbers. Old peer connecting to new host displays the new host's authoritative values; no schema mismatch, just different deltas.

**Version probe:** `K.GetAddonVersion()` (Constants.lua:146-157) returns `"dev"` if not packaged. Used in handshake to detect mismatches but does NOT disambiguate score deltas.

**Verdict:** Wire format is forward-compatible. Score numeric values WILL differ between hosts on different versions for Carré-A in Sun (pre-v0.10.0 = wrong) AND Qaid offender melds (pre-v0.10.1 = generous to offender). All clients in a session inherit the host's values regardless of their own code version, so within a session it's authoritative-consistent.

---

## 7. Findings

### F1 — Belote cancellation per-player vs team-level inconsistency between R.ScoreRound and Net.lua Qaid paths

**Files / lines:**
- `Rules.lua:738-746` (R.ScoreRound) — TEAM-level: any team's ≥100 meld cancels belote
- `Net.lua:2240` (HostResolveTakweesh) — PER-PLAYER: only `m.declaredBy == kWho` AND ≥100 cancels
- `Net.lua:2972` (HostResolveSWA invalid branch) — PER-PLAYER: same per-player check

**Background:** The v0.9.0 M5 fix (Rules.lua:732-737 comment) explicitly upgraded R.ScoreRound's cancellation from per-player to team-level, citing the Saudi rule "≥100 subsumes belote" applies to the team's collective scoring side — partner's quarte cancels K+Q-holder's belote.

The same fix never propagated to Net.lua's two Qaid paths.

**Concrete divergence example (Hokm Bel + Takweesh):**
- Seat 1 holds K+Q of trump (Belote owner = team A).
- Seat 3 (partner, also team A) declared a 100-meld (e.g., Carré-T or quarte sequence).
- Caller (team B) calls Takweesh and catches an illegal play by team B's seat 2 (yes, opp's). Wait — Takweesh by team B catches team B's own player? No, the foundIllegal is filtered to require offender on opposing team to caller. Reframe:
- Caller (team A) calls Takweesh on team B → caller wins → winnerTeam = A.
- belote = "A" (seat 1's K+Q).
- Iter `meldsByTeam[A]`: seat 3's 100-meld present.
  - **R.ScoreRound (Rules.lua:738-746):** `(m.value or 0) >= 100` → match → belote = nil. ✓
  - **Net.HostResolveTakweesh (Net.lua:2240):** `m.declaredBy == kWho AND ≥100` → seat 3 ≠ seat 1 → no match → belote stays = "A". ✗
- Net's path adds +20 to rawA; R.ScoreRound's path does not.
- Concrete delta: ~2 game points per round when the cascade is hit.

**Severity:** LOW-MEDIUM. Triggers only when (a) Qaid path fires (rare), (b) Hokm contract, (c) belote present, and (d) holder's PARTNER (not holder) declared the ≥100 meld. Combined probability of all four ~1-2% of rounds, but when triggered the +2 gp directly contradicts the canonical rule and can flip a near-target win.

**Recommended fix (NOT applied — review only):** Replace Net.lua:2238-2244 and Net.lua:2970-2976 with a team-level loop matching Rules.lua:738-746:
```lua
local list = (S.s.meldsByTeam and S.s.meldsByTeam[belote]) or {}
for _, m in ipairs(list) do
    if (m.value or 0) >= 100 then belote = nil; break end
end
```

---

### F2 — Tiebreaker semantics differ between normal and Qaid paths

**Files / lines:**
- `Net.lua:1693-1709` (normal end) — multi-criteria: gahwaWinner > bidderMade-aware > defensive
- `Net.lua:2327-2331` (Takweesh) — bidder team wins tie unconditionally
- `Net.lua:3064-3068` (Invalid SWA) — bidder team wins tie unconditionally

**Concrete divergence:** Both totA and totB land at exactly target (152) after a Takweesh that the bidder team's offender just lost. The normal-end path would ask "did the bidder make?" — they didn't (they were Takweesh'd), so opp wins tie. The Takweesh path awards the tie to the bidder team — wrong team takes the match.

**Probability:** Very rare — requires both teams already at near-target AND the Takweesh delta exactly equalizes them. Probably < 0.1% of all Takweesh-resolution rounds.

**Severity:** LOW. The defensive fallback at Net.lua:1693-1709 was added in v0.8.6 H3 fix (citing "bidder failed but tie awarded match to bidder" pattern). The Takweesh / Invalid-SWA paths predate or were never updated for that fix.

**Severity assessment:** Won't matter often, but when it does, the result contradicts the very rule v0.8.6 H3 was added to encode.

---

### F3 — Reverse-Kaboot not implemented (gap, not bug)

**Files / lines:** Constants.lua, Rules.lua — no `K.AL_KABOOT_REVERSE` constant; R.ScoreRound:712-723 sweep branch has no defender-led-trick-1 conditional.

**Source state:** Per `review_v0.10.0/REVIEW.md:245`, single-source flag is downgraded — both videos #15 and #16 corroborate +88 raw value, Sun-only. Open question on lead-card requirement (some rule-sets require lead = Ace).

**Impact:** A defender-team sweep in Sun where bidder led trick 1 currently scores as a regular Sun-Kaboot (220 raw). Per source, should be 88 raw. Delta: roughly -132 raw (88 - 220) = -13 gp under no escalation, varying with mult.

**Severity:** LOW. Not a regression (never wired); explicitly flagged as MF-18 in v0.10.0 missing-features catalogue. Triggers only on defender 8-of-8 sweep WITH bidder as trick-1 leader.

**Verdict:** GAP, not bug. Path 5 from the prompt is unscored under canonical Saudi rules; current code falls through to ordinary Al-Kaboot scoring.

---

### F4 — `S.ApplyRoundEnd` arity inconsistency: Takweesh path drops sweep + bidderMade

**Files / lines:**
- `Net.lua:2264` (HostResolveTakweesh): `S.ApplyRoundEnd(addA, addB, totA, totB)` — only 4 args
- `Net.lua:3058` (HostResolveSWA): `S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam, contractMade)` — 6 args
- `Net.lua:1681` (HostStepAfterTrick): `S.ApplyRoundEnd(addA, addB, totA, totB, res.sweep, res.bidderMade)` — 6 args
- `S.ApplyRoundEnd` def (State.lua:1463-1485): treats nil sweep + nil bidderMade as "skip fanfare" — but a TAKWEESH IS a clear bidder-failed event from the loser's perspective.

**Concrete impact:** A successful Takweesh fires `S.ApplyRoundEnd` with sweep=nil and bidderMade=nil. Per State.lua:1482-1483 fanfare guard `if sweep ~= nil or bidderMade == false`, NEITHER condition is met → BALOOT fanfare does NOT fire on Takweesh resolution.

The lost-round stinger at State.lua:1493-1499 inspects deltas → since Takweesh always produces a non-zero asymmetric delta, the loser HEARS the stinger. So loser hears defeat, but neither side hears the BALOOT fanfare.

**Severity:** LOW (UX-only; no scoring impact). The comment block at State.lua:1474-1481 anticipates this case ("Pre-v0.3.0 hosts and Takweesh/SWA call sites pass nil for both — treat as no-fanfare") so the omission is INTENTIONAL — Takweesh has its own takweesh-result panel + a TAKWEESH! print line, treated as a different ceremony.

**Verdict:** Not a bug per the explicit comment. Flagged for completeness — if the cohort wants the BALOOT fanfare on Takweesh-resolves, the fix is to pass `bidderMade=false` on a successful caller-team Takweesh.

---

### F5 — Telemetry row writes regardless of path; cumulative captures totA/totB AFTER the round

**Files / lines:** State.lua:1522-1584 — telemetry row is written from `S.ApplyRoundEnd` for every path that calls it.

**Observation:** Row captures `addA, addB, totA, totB, sweep, bidderMade`. For Takweesh paths (no sweep, nil bidderMade), the row gets `bidderMade = -1` per the trinary encoding at State.lua:1574-1575. For Invalid-SWA, same. For Valid-SWA with the bidder failing, `bidderMade = 0`.

**Verdict:** Telemetry analyzer needs to be aware of the trinary encoding. Documented at State.lua:1574-1575. Not a bug; flagging in case downstream calibration scripts are unaware.

---

## 8. Verdict

**Overall pipeline integrity:** STRONG.

- All 8 paths route through one of three known entry points and converge on `S.ApplyRoundEnd` + cumulative update.
- Multiplier scope and div10 rounding are correctly aligned across all paths post-v0.5.21.
- v0.10.0 R5 (Carré-A in Sun = 400 raw direct) is correct.
- v0.10.0 X5 (Carré-A in Hokm = 100 raw, no longer dropped) is correct AND closes the Belote-cancellation cascade in `R.ScoreRound`.
- v0.10.0 R2 (Sun escalation defensive normalization) prevents stale Sun-tripled/foured/gahwa flags from miscomputing.
- v0.10.1 M1 (Qaid offender melds zeroed) is correctly applied to BOTH Qaid paths.
- Wire format is append-only forward-compatible; score numeric values flow authoritatively from host.

**Remaining issues (all LOW severity, none regressions from v0.10.0):**
- **F1** — Belote-cancellation predicate diverges between R.ScoreRound (team-level, post-v0.9.0 M5) and Net.lua Qaid paths (per-player). Concrete +2 gp delta when partner of K+Q-holder declares ≥100 meld AND Qaid path fires. Recommend porting the team-level fix to Net.lua:2238-2244 + 2970-2976.
- **F2** — Tiebreaker semantics differ between normal and Qaid paths; v0.8.6 H3's bidder-failed-on-tie logic doesn't apply on Takweesh / Invalid-SWA. Probably never triggered in practice.
- **F3** — Reverse-Kaboot not implemented (MF-18). Defender Sun-sweep with bidder-led-trick-1 currently scores 220 raw (regular Sun-Kaboot) instead of 88. Backlog item; not a regression.
- **F4** — Takweesh path passes nil sweep+bidderMade to S.ApplyRoundEnd, suppressing BALOOT fanfare. Intentional per comment, flagged for completeness.

**Cumulative & win-condition logic:** Consistent on host. Receivers rely on host's `MSG_GAMEEND` broadcast — no separate target check.

**Cross-version compatibility:** Wire format forward-compatible. Score numeric values flow authoritatively from host; cross-version sessions will inherit whichever version's bug-or-fix the host is on.

---

## 9. Confidence

| Item | Confidence |
|---|---|
| Path 1 (Make) trace | HIGH — straightforward from Rules.lua:858 + 895 + 918 |
| Path 2 (Fail) trace | HIGH — Rules.lua:823-840 explicit; matches X1 verdict + v0.10.0 closure decisions |
| Path 3 (Take inversion) trace | HIGH — Rules.lua:799-812, R2 normalization confirmed |
| Path 4 (Sweep) trace | HIGH — Rules.lua:712-723; sweep-belote override is intentional |
| Path 5 (Reverse-Kaboot) gap | HIGH — Constants.lua / Rules.lua / Net.lua grep returns 0 hits; MF-18 confirms |
| Path 6 (Gahwa) trace | HIGH — Net.lua:1669-1678 + Rules.lua:926-937 |
| Path 7 (Takweesh) trace | HIGH — Net.lua:2127-2339 walked end-to-end; matches X1 6-cell numerical table |
| Path 8 (Invalid SWA) trace | HIGH — symmetric to Path 7 |
| Carré-A in Hokm cascade closure | HIGH in R.ScoreRound; MEDIUM in Net.lua Qaid paths (F1 partner-cancellation gap) |
| Carré-A in Sun = 160 gp under Sun+Bel | HIGH — `400 × 4 ÷ 10 = 160` arithmetically correct |
| Cross-platform wire compat | HIGH — three-state encoding + append-only documented |
| Multiplier scope (mult × (card+meld); Belote +20 immune) | HIGH — X1 confirms across 6 numerical examples |
| div10 = (x+5)/10 consistent | HIGH — R.ScoreRound:918, Net.lua:2259, Net.lua:2985 all align (v0.5.21 closure) |
| F1 (Belote cancellation per-player vs team) | HIGH confidence the divergence exists |
| F2 (tiebreaker semantics differ) | HIGH confidence |
| F3 (Reverse-Kaboot gap) | HIGH confidence |
| F4 (fanfare on Takweesh) | HIGH confidence; intentional per comment |
