# C-Xref-04: `docs/strategy/saudi-rules.md` drift audit vs `Rules.lua`

**Scope:** Per-paragraph verification of `C:\CLAUDE\WHEREDNGN\docs\strategy\saudi-rules.md` against `C:\CLAUDE\WHEREDNGN\Rules.lua` (and `Constants.lua` where the doc names a constant).

**Authority hierarchy (per `CLAUDE.md`):** if a strategy doc and `Rules.lua` disagree, **`Rules.lua` is authoritative for legality**; the strategy doc is authoritative for *decision* heuristics. This audit treats every "the code does X" or "Rules.lua enforces X" claim as a falsifiable assertion against the live Lua, and tags drift accordingly.

**Verdict legend:**
- **ALIGNED** — doc statement matches code behavior.
- **DOC-AHEAD** — doc states a rule that code does NOT enforce (or enforces inversely). Code lags doc.
- **CODE-AHEAD** — code enforces a rule the doc misses or misdescribes. Doc lags code.
- **DRIFT** — doc and code disagree, severity-tagged (HIGH / MEDIUM / LOW). Includes both directions.

---

## Per-rule findings (in doc order)

### 1. Deck and deal — `saudi-rules.md:15-19`
- **Quote:** "Deck: 32 cards … 8 cards per player … Exactly 4, in 2 partnerships."
- **Code anchor:** `Constants.lua:11-13` (`K.SUITS` × `K.RANKS` = 32). Hand-deal at `State.lua` deal phases (HAND_TOTAL_HOKM = 152 cards trick-points consistent with 8×4×variable-points).
- **Verdict:** **ALIGNED.**

---

### 2. Bidding overview — `saudi-rules.md:21-31`
- **Quote:** "Saudi bids: HOKM, SUN, ASHKAL, PASS … no 'all trumps' or 'no trumps' auctions."
- **Code anchor:** `Constants.lua:59-66` defines exactly `K.BID_PASS`, `K.BID_HOKM`, `K.BID_SUN`, `K.BID_ASHKAL`. `R.CanOvercall` / `R.ResolveOvercall` (`Rules.lua:573-643`) implement post-Hokm Sun-overcall window.
- **Verdict:** **ALIGNED**, but doc is silent on the v0.7+ post-Hokm Sun overcall + v0.8 cross-trump take. **CODE-AHEAD (LOW)** — saudi-rules.md doesn't enumerate the overcall flow at all. Not a legality drift; it's a missing-coverage flag for the doc.

---

### 3. Card values, hand totals — `saudi-rules.md:33-43`
- **Quote:** "Hokm round total = 162 (matches French Belote). Sun round total = 130 … then ×2 multiplier applied = 260 effective."
- **Code anchors:**
  - `Constants.lua:42-47` `K.POINTS_TRUMP_HOKM` and `K.POINTS_PLAIN`.
  - `Constants.lua:53-55` `K.LAST_TRICK_BONUS = 10`, `K.HAND_TOTAL_HOKM = 162`, `K.HAND_TOTAL_SUN = 130`.
  - `Rules.lua:676` selects `handTotal` from `K.HAND_TOTAL_*` based on `contract.type`.
  - `Rules.lua:884-887` Sun-mult path: `mult = 1 × K.MULT_SUN (2) × (Bel?2)`. Sun base = ×2.
- **Verdict:** **ALIGNED.** The "260 effective" arithmetic is consistent with raw pipeline `(card+meld)*2 / 10` then game points; the "×2 multiplier baked into final score" claim is borne out by `Rules.lua:884-885`.

---

### 4. Melds table — `saudi-rules.md:47-56`

| Doc row | Code | Verdict |
|---|---|---|
| `Tierce 20 = K.MELD_SEQ3` | `Constants.lua:91` `K.MELD_SEQ3 = 20` | **ALIGNED** |
| `Quarte 50 = K.MELD_SEQ4` | `Constants.lua:92` | **ALIGNED** |
| `Quinte 100 = K.MELD_SEQ5` | `Constants.lua:93` | **ALIGNED** |
| `Carré J = 100 = K.MELD_CARRE_OTHER` | `Constants.lua:94`; `Rules.lua:276-279` Sun-A is the only special-case | **ALIGNED** |
| `Carré 9 = disallowed; K.CARRE_RANKS excludes "9"` | `Constants.lua:109` `K.CARRE_RANKS = {A,T,K,Q,J}` (9 absent) | **ALIGNED** |
| `Carré A,T,K,Q = 100 = K.MELD_CARRE_OTHER` | `Constants.lua:94` | **ALIGNED** for non-A; for Carré-A in Hokm see drift note (Item 5) |
| `Carré A in Sun = 200 = K.MELD_CARRE_A_SUN` | `Constants.lua:95` `K.MELD_CARRE_A_SUN = 400` | **DRIFT (HIGH)** — see Item 5 |
| `Belote (K+Q trump) 20 = K.MELD_BELOTE` | `Constants.lua:107` `K.MELD_BELOTE = 20` | **ALIGNED** (multiplier-immune confirmed at `Rules.lua:898-912`) |

---

### 5. Carré-A in Sun value — `saudi-rules.md:55`
- **Doc text:** "Carré A in Sun … **200 (الأربع مئة, "Four Hundred")** — `K.MELD_CARRE_A_SUN`"
- **Code:** `Constants.lua:95` defines `K.MELD_CARRE_A_SUN = 400` (with extensive justification comment lines 95-106 documenting that the value WAS 200, was changed to 400 in v0.10.0 R5 because the prior 200 produced 40 game points instead of the canonical 80).
- **Doc text elsewhere:** `saudi-rules.md:150-162` (Q3 resolved-v0.10.0) **correctly** describes the 400 raw value.
- **Verdict:** **DRIFT (HIGH)** — internal contradiction *within saudi-rules.md*. The melds table at line 55 still says "200" while the Q3 paragraph below (line 150-162) explains the 400 fix. The table should be updated to "400" to match the code (`K.MELD_CARRE_A_SUN = 400`) and to be self-consistent. The melds-table row is the immediate look-up developers will hit; the prose footnote 100 lines later is easy to miss.
- **Severity:** HIGH because it's the canonical reference table for meld values and contradicts both the code and the doc's own resolved-Q3 narrative.

---

### 6. "9 of trump is ranked but not a meld" — `saudi-rules.md:62-63`
- **Quote:** "9 of trump is ranked but not a meld. The 9 is the second-highest trump … but four 9s never form a Carré in Saudi."
- **Code anchors:**
  - `Constants.lua:50` `K.RANK_TRUMP_HOKM = { J=8, 9=7, A=6, T=5, K=4, Q=3, 8=2, 7=1 }` — confirms 9 is rank-7 (second-highest trump).
  - `Constants.lua:109` `K.CARRE_RANKS` excludes "9" — confirms four-of-9s does not form a Carré.
- **Verdict:** **ALIGNED.**

---

### 7. Escalation chain (Bel → Bel x2 → Four → Gahwa) — `saudi-rules.md:65-82`
- **Quote:** "After bidding … there's a four-rung doubling chain: Bel (×2), Bel x2 (×3), Four (×4), Gahwa (match-win)."
- **Code anchors:**
  - `Constants.lua:68-77` `K.MULT_BASE=1, K.MULT_SUN=2, K.MULT_BEL=2, K.MULT_TRIPLE=3, K.MULT_FOUR=4`. Comment at lines 73-77 confirms Gahwa is "NOT a round-multiplier per canon. The caller's team WINS THE ENTIRE MATCH outright."
  - `Rules.lua:884-893` multiplier path: `MULT_BEL → MULT_TRIPLE → MULT_FOUR` (Hokm); Sun caps at MULT_BEL.
  - `Rules.lua:920-937` Gahwa match-win branch.
  - `Constants.lua:128-131` phase machine `PHASE_DOUBLE → PHASE_TRIPLE → PHASE_FOUR → PHASE_GAHWA` enforces voluntary-each-rung structure.
- **Doc note:** "Code identifier: `K.MSG_TRIPLE` / `Bot.PickTriple`." Confirmed `Constants.lua:173-176` defines `K.MSG_TRIPLE = "3"`, `K.MSG_FOUR = "4"`, `K.MSG_GAHWA = "5"`.
- **Verdict:** **ALIGNED** for chain mechanics.
- **Sub-issue: doc says "Bel x2" (×3) is "Triple" in code identifier.** Doc uses both Saudi name "Bel x2 / بل×2" and English code name "PickTriple". Match is consistent with `K.MULT_TRIPLE = 3` and `K.MSG_TRIPLE`. **ALIGNED.**

---

### 8. Sun multiplier ×2 baked into final score — `saudi-rules.md:39-43, 184-190`
- **Quote (line 184):** "Code applies the ×2 in the multiplier path, then `div10` at the end."
- **Code anchor:** `Rules.lua:884-887`:
  ```
  if contract.type == K.BID_SUN then
      mult = mult * K.MULT_SUN
      if contract.doubled then mult = mult * K.MULT_BEL end
  ```
  `K.MULT_SUN = 2` from `Constants.lua:69`. Multiplier applied to `(card + meldPoints)`, then div10 at line 918.
- **Verdict:** **ALIGNED.**

---

### 9. AKA — implicit AKA via bare-Ace lead — `saudi-rules.md:90-93`
- **Quote:** "Implicit AKA … leading the bare Ace of a non-trump suit … is treated as an AKA call by the partner-side convention, even without an explicit `K.MSG_AKA` broadcast."
- **Code anchor:** `Rules.lua:115-121` AKA-receiver relief:
  ```
  if akaCalled and akaCalled.seat and akaCalled.suit
     and seat and R.Partner(seat) == akaCalled.seat
     and akaCalled.suit == leadSuit
     and contract and contract.type == K.BID_HOKM then
      akaRelief = true
  end
  ```
  Code requires `akaCalled` to be set via `MSG_AKA`. There is **no** auto-set on bare-Ace lead in `R.IsLegalPlay`. The implicit-AKA convention from video #18 (re-extracted in `A-Src-07_v18_aka.md`) is **NOT** wired in `Rules.lua` legality. It MAY be wired bot-side (see `signals.md` reference) but the doc is making a *legality* claim ("treated as AKA call"), and `Rules.lua` doesn't honour it without an explicit `s.akaCalled` set.
- **Verdict:** **DRIFT (MEDIUM, DOC-AHEAD).** The doc oversells implicit AKA as a legality rule; in reality it's a partner-side heuristic that does not auto-fire `akaRelief` in `R.IsLegalPlay`. Either:
  - (a) `Rules.lua` should auto-set `akaRelief = true` when `tricks[1].plays[1].card` is a bare Ace of non-trump (and partner=receiver), or
  - (b) the doc should clarify "convention" vs "code-enforced".
- Cross-ref: `A-Src-07_v18_aka.md` confirms video #18 supports the *signaling* equivalence (HIGH confidence) — so the code lag is real, not a doc mis-extraction.

---

### 10. AKA-on-trump trick lock semantics — `saudi-rules.md` implicit / `Rules.lua:108-110` comment
- **Doc text on AKA semantics:** Doc does NOT explicitly claim "AKA on T trick-locks" — it stays at the partner-side convention level (`saudi-rules.md:90-93`).
- **Rules.lua:108-110 comment:** "The 10-substitutes-for-Ace semantic (J-067 part 1) collapses to the same rule — whichever AKA card is in play, partner's team treats the trick as locked."
- **Source verdict (per `A-Src-07_v18_aka.md` HEADLINE FINDING):** "Video #18 supports a *signaling* equivalence (T-with-AKA ≈ A-without-AKA *for partner's overtrump-release*), not a *trick-resolution* equivalence." The "10-substitutes-for-Ace" comment in Rules.lua is **misleading**.
- **Code behavior:** `R.CurrentTrickWinner` (`Rules.lua:34-59`) does NOT have any AKA-aware branch; trick winner is purely trump-played + rank. AKA-on-T does NOT lock the trick. The misleading comment overstates the code's intent.
- **Verdict:** **DRIFT (LOW)** — purely a comment-vs-code clarity issue. `saudi-rules.md` itself doesn't make this claim, but it directs readers to "see `signals.md`" (`saudi-rules.md:243-244`), and the upstream `Rules.lua:108-110` comment can mislead anyone who follows the trail. Recommend the comment be revised to: "AKA-on-T provides partner-overtrump-release equivalent to AKA-on-A; it does NOT alter trick resolution."
- Cross-ref: `B-State-05` does not flag this; it's a pre-existing finding from the v0.10.0 review (xref_X2_aka.md B5) and re-confirmed by `A-Src-07_v18_aka.md`.

---

### 11. SWA permission flow (≤3 instant vs ≥4 permission) — `saudi-rules.md:96-100`
- **Doc text:**
  - Line 96: "≤3 cards remaining: instant claim."
  - Line 97-98: "4: caller asks opponents for permission (5-sec auto-approve). 5+: caller MUST تستاذن (request permission) — mandatory."
  - Line 99-100: "Saudi-strict: SWA is **deterministic-or-bust**; sub-100%-certain SWA claims are not the convention (per video #35)."
- **Code anchor:** `Net.lua:2473-2502` `N.LocalSWA()`:
  ```
  -- v0.5.17 routes ALL calls through the 5-second permission display
  -- so the caller's cards are visible to all players in every scenario
  ...
  -- v0.5.17: route ≤3-card claims through the permission window
  -- too, so the SWA banner displays the caller's cards. Was:
  -- `if needPerm and handCount >= 4`. Now: `if needPerm` (any count).
  if needPerm then
      -- Permission flow: broadcast a request, wait for opponents.
  ```
- **Drift summary:**
  - Doc says "≤3: instant claim" — code routes ALL claims (including ≤3) through the permission window since v0.5.17.
  - Doc says "5-sec auto-approve" — confirmed by `Constants.lua:281` `K.SWA_TIMEOUT_SEC = 5`. CLAUDE.md correctly clarifies this is a UX timer, not a Saudi rule.
- **Verdict:** **DRIFT (MEDIUM, CODE-AHEAD).** The doc's "≤3: instant claim" claim describes pre-v0.5.17 behavior. Current code routes everything through the same 5-second permission window. Recommend doc say: "≤3 / 4 / 5+: all calls now route through the 5-second permission window for UI parity (v0.5.17). The 5-second timer is an addon UX construct (see CLAUDE.md), not a Saudi rule. Saudi convention per video #35 has no timer — opps verbally say نسمح or demand شرح."
- Cross-ref: `A-Src-09_v35_swa.md` confirms zero timing vocabulary in video #35 (HIGH confidence). CLAUDE.md already correctly documents this.

---

### 12. Al-Kaboot (sweep all 8) — `saudi-rules.md:103-104`
- **Quote:** "bidder team sweeps all 8 tricks. Bonus: 250 raw in Hokm, 220 in Sun (pre-multiplier)."
- **Code anchors:** `Constants.lua:114-115` `K.AL_KABOOT_HOKM = 250, K.AL_KABOOT_SUN = 220`. `Rules.lua:817-822` sweep branch awards `bonus = (Hokm ? 250 : 220)`.
- **Drift sub-claim:** Doc says "**bidder team** sweeps all 8 tricks" — but `Rules.lua:712-714` detects sweep purely from `trickCount.A == 8 or trickCount.B == 8`, with NO bidder-vs-defender distinction. Defender-sweep also triggers the 250/220 bonus.
- **Verdict:** **DRIFT (MEDIUM, DOC-AHEAD)** for the bidder-restriction claim, AND the code is missing the Reverse Al-Kaboot path (see Item 13).

---

### 13. Reverse Al-Kaboot — `saudi-rules.md:105-109`
- **Quote:** "Reverse Al-Kaboot (الكبوت المقلوب) — *defenders* sweep all 8 tricks against the bidder team. Bonus: **+88 raw**. Qualifies only when bidder was the trick-1 leader. Single-source rule (video #16); confirm before wiring. New constant proposal: `K.AL_KABOOT_REVERSE = 88`."
- **Code anchor:** `Rules.lua:711-723` and `817-822` — sweep branch is type-blind on bidder/defender. There is **no** `K.AL_KABOOT_REVERSE` constant; defender-sweep is awarded the same `K.AL_KABOOT_HOKM = 250` / `K.AL_KABOOT_SUN = 220` as a bidder sweep.
- **Verdict:** **DRIFT (HIGH, DOC-AHEAD).** Doc clearly states the rule is "single-source; confirm before wiring", AND describes a `K.AL_KABOOT_REVERSE = 88` proposal that does NOT exist in `Constants.lua`. The text reads as if it's been adopted but it has not.
- Cross-ref: `B-State-05` F-01 (HIGH) flags this same UNWIRED state. The doc honestly acknowledges "confirm before wiring" — so this is more *doc-aspirational* than drift. Recommend doc explicitly tag "**STATUS: UNWIRED** — see `B-State-05` F-01".
- **Severity:** HIGH because (a) doc misleads anyone who searches the constant `K.AL_KABOOT_REVERSE`, and (b) defender-sweep currently over-pays vs the +88 interpretation by ~162 raw (Hokm) or ~132 raw (Sun).

---

### 14. Kasho vs Qaid penalty system — `saudi-rules.md:111-131`
- **Quote (Qaid row):** "Non-offending team scores **26 raw (Sun) / 16 raw (Hokm)** + their **own** melds; offending team **keeps** their own melds."
- **Code anchor:** Searched `Net.lua` for `HostResolveTakweesh` (`Net.lua:2127-2339`, per `C-Xref-02` mapping). The doc's claim of "26 raw (Sun) / 16 raw (Hokm)" is documented as *what the score side currently lacks* (line 125: "the score side currently lacks the 26/16 split"). The doc is internally consistent — it explicitly acknowledges code lag.
- **Audit note:** This audit is read-only on `Rules.lua`. Score-side qaid is in `Net.lua`, not `Rules.lua` directly. The drift, if any, is in `Net.HostResolveTakweesh` — out of scope here but flagged for `B-Net-03_takweesh_full.md` cross-check.
- **Verdict:** **DOC-AHEAD (LOW)** — doc itself notes the gap. This is honest reporting, not drift. No `Rules.lua` site to verify against.

---

### 15. Belote in Sun — `saudi-rules.md:138-143`
- **Quote:** "Belote (K+Q of trump) in Sun? ✗ **NOT in code.** `R.ScoreRound` line 504 gates Belote scoring on `contract.type == K.BID_HOKM`."
- **Code:** **The line number is wrong.** Actual gate is at `Rules.lua:694`:
  ```
  if contract.type == K.BID_HOKM and contract.trump then
      ...
  ```
  Line 504 is `R.SumMeldValue` (`Rules.lua:503-507`), an unrelated helper.
- **Verdict:** **DRIFT (LOW, DOC line-ref stale).** Substantively the doc is correct — Belote *is* gated on Hokm — but the cited line number `504` is wrong (probably stale from a pre-X5 version of `Rules.lua`). Update the doc to `Rules.lua:694`.
- Cross-ref: `R.BeloteAllowed` mentioned in this audit's task — searched `Rules.lua`, **no such function exists**. The Belote logic is inline at `Rules.lua:692-709`. The task brief itself uses a non-existent name.

---

### 16. Pos-4 partner-winning ruff-relief — `saudi-rules.md:146-148`
- **Quote:** "Pos-4 partner-winning ruff-relief? ✓ **Already in code.** `R.IsLegalPlay` lines 117-121 (over-trump-partner relief) and 145-149 (general partner-winning relief on void)."
- **Code anchors (current):**
  - `Rules.lua:137-141` (over-trump-partner relief — when leadSuit == trump, partner is currently winning, return true).
  - `Rules.lua:166-169` (general partner-winning relief on void — `curWinner = R.CurrentTrickWinner; if Partner(seat) == curWinner then return true`).
- **Drift:** Doc cites lines `117-121` and `145-149`. Actual code has shifted: AKA-relief block was inserted at lines 103-121 in v0.10.2 M4. So:
  - Old "117-121" (over-trump-partner) → now `Rules.lua:137-141`.
  - Old "145-149" (void+partner-winning) → now `Rules.lua:166-169`.
- **Verdict:** **DRIFT (LOW, line refs stale).** The substance is still correct; only the line numbers drifted because of v0.10.2 M4 insertion at the top of `R.IsLegalPlay`. Recommend doc be regenerated against current line numbers as part of v0.10.2 cleanup.

---

### 17. Carré-A in Hokm — `saudi-rules.md:164-173`
- **Quote:** "Pre-v0.10.0 `R.DetectMelds` had no `else` branch for the Hokm-A path … Fixed in `Rules.lua:240-244` + regression test inverted at `tests/test_rules.lua:365-379`."
- **Code anchor:** Actual fix is at `Rules.lua:273-287` (current line numbers). The `value` selection for Carré-A:
  ```
  if rank == "A" then
      value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
  else
      value = K.MELD_CARRE_OTHER
  end
  ```
  This DOES set `value = K.MELD_CARRE_OTHER = 100` for Hokm-A.
- **Verdict:** **DRIFT (LOW, line refs stale).** Doc says "240-244"; actual is `Rules.lua:273-287` (or 276-280 if you want the exact value-assignment). Substance correct.
- **Critical sub-issue (CODE-AHEAD/DRIFT):** Per `B-State-05` F-04 (MEDIUM), the v0.10.0 X5 fix in `R.DetectMelds` does NOT propagate to the wire path: `S.ApplyMeld` in `State.lua:1149-1189` STILL drops Hokm 4-Aces because `value` stays nil for Hokm-A. So `R.DetectMelds` reports 100 raw, but `meldsByTeam` (the actual structure `R.ScoreRound` reads) excludes it. The doc claims X5 is "RESOLVED v0.10.0" but the resolution is partial — it works inside `R.DetectMelds` only, NOT through the `S.ApplyMeld` path that `R.ScoreRound` ultimately consumes. **This is a CODE-AHEAD-of-itself case: `Rules.lua` is correct, `State.lua` is not.** Out-of-scope for `Rules.lua` audit but flagged here per `B-State-05` F-04.

---

### 18. Score-rounding 5-up — `saudi-rules.md:175-182`
- **Quote:** "`R.ScoreRound` div10 is now `math.floor((x + 5) / 10)` — rounds 65 → 70 (UP), 64 → 60."
- **Code anchor:** `Rules.lua:914-918`:
  ```
  local function div10(x) return math.floor((x + 5) / 10) end
  ```
- **Verdict:** **ALIGNED.** Spot-check: 65 → floor(70/10)=7 → 70 gp. 64 → floor(69/10)=6 → 60 gp. Confirmed.

---

### 19. سيكل (sykl) — 9-8-7 sequence — `saudi-rules.md:192-198`
- **Quote:** "سيكل is the colloquial name for any 9-8-7 tierce; it scores **20 raw**, identical to any other tierce (`K.MELD_SEQ3`)."
- **Code anchor:** `Rules.lua:225-252` sequence detection: a 3-card consecutive run (any rank set) scores `K.MELD_SEQ3 = 20`. No sykl special-case. 9-8-7 has rank indices 3-2-1 → consecutive → seq3.
- **Verdict:** **ALIGNED.**

---

### 20. Bid takweesh (override partner's bid) — `saudi-rules.md:200-205`
- **Quote:** "This is **bid-decision logic** (`Bot.PickBid` should not bid against partner's strong contract), distinct from the existing `K.MSG_TAKWEESH` penalty-call."
- **Code anchor:** This is `Bot.lua` territory (out-of-scope for `Rules.lua` audit). No `Rules.lua` site to verify.
- **Verdict:** Not applicable. Doc note is internally consistent.

---

### 21. Bel (×2) legality gate, Sun-only — `saudi-rules.md:207-218`
- **Quote (line 209-212):** "**Sun contracts only:** the team currently at **≥100 cumulative score** is **forbidden** from calling Bel. Only the team at <100 may Bel … `R.CanBel(team)` predicate."
- **Quote (line 214-215):** "**Hokm contracts:** no such gate."
- **Code anchor:** `Rules.lua:523-561` `R.CanBel(team, contract, cumulative)`:
  ```
  if contract.type ~= K.BID_SUN then
      return true                         -- Hokm: always allowed
  end
  ...
  if mine     >  K.SUN_BEL_CUMULATIVE_GATE then return false end
  if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end
  return true
  ```
  `K.SUN_BEL_CUMULATIVE_GATE = 100` (`Constants.lua:329`).
- **Verdict:** **ALIGNED.** Hokm is open; Sun requires score-split (caller ≤ 100, opp > 100).
- **Sub-drift (LOW):** Doc says "≥100 forbidden" — code uses strict `> 100` (mine > GATE → false; mine == 100 still legal because ≤100 case falls through). Saudi rule per video #11 is "<100 may, ≥100 may not"; the code allows mine == 100 to Bel. This is a 1-point boundary discrepancy. Either:
  - Doc is wrong (rule is actually "must be at most 100" → mine ≤ 100 is fine), or
  - Code is wrong (rule is "strictly less than 100" → mine == 100 should be forbidden).
- The R1 reaudit comment at `Rules.lua:541-554` cites the verbatim Arabic "اقل من 100" (less than 100) — which would suggest mine == 100 is forbidden (i.e., code should be `mine >= GATE → false`, not `mine > GATE → false`). Cross-check with `review_v0.10.0/reaudit_R1_bel100.md` recommended.
- **Verdict for sub-issue:** **DRIFT (LOW, BORDERLINE)** — 1-point boundary; the verbatim Arabic and PDF 02 ("بعد ان يتجاوز المئة اي 101") suggests the OPPOSITE — gate is "until you exceed 100, i.e. 101+", which means mine == 100 is fine to Bel. So code's `mine > 100` matches the verbatim "101+" interpretation; doc's loose ≥100/<100 phrasing is informal. Code is correct; doc is informally rounded.

---

### 22. Half-and-half tiebreak — `saudi-rules.md:228-230`
- **Quote:** "if bidder team gets exactly 81 of 162, bidder **fails** (need strictly more than half). `R.ScoreRound` encodes this."
- **Code anchor:** `Rules.lua:775-778`:
  ```
  if bidderTotal > oppTotal then
      outcome_kind = "make"
  elseif bidderTotal < oppTotal then
      outcome_kind = "fail"
  else
      ...  -- tie path
  ```
  Strict `>` for make. Tie path defaults to `outcome_kind = "fail"` for non-doubled (line 810-811): `none → fail`. So 81-81 with no escalation → fail.
- **Verdict:** **ALIGNED.** Strict-majority correctly enforced. Special case noted: with `doubled` or `foured` defender-buyer rung, 81-81 inverts to `take` (rule 4-10 inversion) — which is consistent with the doc since the doc only claims "no escalation" implicitly via "if bidder team gets exactly 81 of 162, bidder fails."
- **Sub-issue:** Doc says "**bidder fails**" unconditionally on 81-81. Code path with `doubled` (Bel) inverts: defender (the buyer) failed, bidder takes. The doc doesn't cover this nuance. **DOC-AHEAD (LOW)** — the doc oversimplifies. Recommend doc add: "(In a Bel'd or Foured contract, the rule 4-10 inversion flips this — see `R.ScoreRound` lines 779-812.)"

---

### 23. Failed bid (defenders win round) — `saudi-rules.md:231-232`
- **Quote:** "opponents capture all trick points; bidder team gets 0."
- **Code anchor:** `Rules.lua:823-840` fail branch:
  ```
  cardA = (oppTeam == "A") and handTotal or 0
  cardB = (oppTeam == "B") and handTotal or 0
  meldPoints.A = meldA
  meldPoints.B = meldB
  ```
  Defenders take `handTotal` (162/130). **Bidder keeps own melds.**
- **Verdict:** **DRIFT (MEDIUM, DOC-AHEAD).** Doc says "bidder team gets 0" — **NOT TRUE**. The bidder team retains their declared melds × multiplier (per the v0.4.3+ "مشروعي لي ولك مشروعك" rule documented at `Rules.lua:824-836`). Quote directly from `Rules.lua:830-835`: "User-reported bug RCA: with Hokm Bel'd (×2) and the bidder team failing, the bidder team showed final = 0 even when they had declared a quarte (50 raw × 2 = 100 raw = 10 gp)."
- Recommend doc say: "opponents capture all trick points (handTotal); bidder team's card-trick points → 0, but bidder keeps their own melds × multiplier."
- The Qaid table at `saudi-rules.md:119` correctly notes "offending team **keeps** their own melds" for Qaid; the rule is the same here for failed bid (and was the v0.4.3 unification fix).

---

### 24. Multiplier scope — `saudi-rules.md:233-235`
- **Quote:** "×2/×3/×4 applies to the trick-point side of the score. Belote +20 is multiplier-immune. Gahwa is binary (match-win/loss) — multiplier moot."
- **Code anchors:**
  - Multiplier on `(card + meldPoints) * mult` at `Rules.lua:895-896`.
  - Belote +20 added AFTER mult at `Rules.lua:898-912`.
  - Gahwa branch at `Rules.lua:920-937`. Per `Constants.lua:73-77`: "Gahwa is NOT a round-multiplier per canon."
- **Verdict:** **ALIGNED** for Belote-immune and Gahwa-as-match-win. Slight imprecision: doc says "×2/×3/×4 applies to the trick-point side" — actually applies to `(cardPts + meldPoints)`, i.e., trick + meld combined. Doc could be tightened, but not a drift.

---

### 25. Trick-play rules — `saudi-rules.md:237-244`
- **Doc claims:**
  - "Must follow suit if able."
  - "Must over-trump if leading suit is trump and you can over-cut. Saudi-strict; some French variants allow under-trumping."
  - "Must trump-ruff if void in led suit and your team is not currently winning the trick."
- **Code anchors:**
  - Must-follow: `Rules.lua:128-131` `if hasLead then if cardSuit ~= leadSuit then return false, "must follow suit"`.
  - Must-overcut on trump-led: `Rules.lua:137-158` (with partner-winning relief at lines 138-141).
  - Partner-winning shortcut on void: `Rules.lua:166-169`.
  - Must-trump-ruff on void+team-not-winning: `Rules.lua:177-184`.
- **Verdict:** **ALIGNED.** Doc note "AKA receiver convention overrides this in some cases — see signals.md" is consistent with the `akaRelief` branch at `Rules.lua:115-121, 175`.

---

### 26. Where this lives in code — `saudi-rules.md:248-257`
- **Quote:** "`Constants.lua` — `K.POINTS_TRUMP_HOKM`, `K.RANK_TRUMP_HOKM`, meld scores, escalation thresholds."
- **Code anchor:** `Constants.lua:42-44` `K.POINTS_TRUMP_HOKM`, `Constants.lua:50` `K.RANK_TRUMP_HOKM`, melds at 91-115, escalation `K.MULT_*` at 68-72, bot thresholds at 302-310.
- **Verdict:** **ALIGNED.**

---

## Other audit-brief items (per task)

### Belote/Triple/Four/Gahwa escalation chain (`K.MULT_*`, `R.ScoreRound`)
Already covered in Items 7 + 24. **ALIGNED.**

### Carré table (`K.CARRE_RANKS`, `R.ScoreCarre`) — note 9-of-trump exclusion
- `R.ScoreCarre` does not exist; carré scoring is inline in `R.DetectMelds` at `Rules.lua:268-287`. The audit-brief named function is non-existent. This is a brief-name drift, not a doc/code drift. Reasonable next step: doc / brief writer should reference `R.DetectMelds` or the `K.CARRE_RANKS`/`K.MELD_CARRE_*` constants.
- 9-of-trump exclusion: **ALIGNED** (Item 6).

### Bidder fails on tied 81/162 (`R.ScoreRound` strict-majority logic)
Covered in Item 22. **ALIGNED with sub-issue noted.**

### Mathlooth scoring (Sun K-tripled per A-Src-06)
- Mathlooth is a strategic concept, not a scoring rule. There is NO `Rules.lua` site for "mathlooth"; it's covered (or should be) in `Bot.lua` strategy heuristics and `docs/strategy/decision-trees.md`. `saudi-rules.md` does NOT cover mathlooth; it's correctly absent.
- Per `A-Src-06_v17_mathlooth.md`: video #17 covers Sun-Shayeb (K) tripled as the canonical case (HIGH confidence); the v0.10.0 R7 framing of "J-tripled vs K-tripled" is partially supported (J-Walad and Q-Bint mathlooth are valid lower-probability variants).
- **Verdict:** Out of scope for `saudi-rules.md` (which is about *rules*, not strategy). Not a drift.

### Reverse Kaboot per `Rules.lua:817-822` — `B-State-05` F1 flagged UNWIRED
Covered in Item 13. **DRIFT (HIGH, DOC-AHEAD).**

### Gahwa match-win type-blind issue (`Rules.lua:928`, `B-State-05` F2)
- `Rules.lua:920-937`: Gahwa match-win branch fires `gahwaWonGame = true` whenever `contract.gahwa == true`, even on a (stale) Sun contract. The multiplier-side correctly collapses Sun-Triple/Four/Gahwa to Sun-Bel-max at `Rules.lua:884-887`, but the match-win branch does not mirror that gate.
- `saudi-rules.md` does not directly comment on this defensive collapse; it just says "Gahwa is binary (match-win/loss) — multiplier moot." That's true at the multiplier path but blind to the defensive-normalization asymmetry on Sun-with-stale-gahwa.
- **Verdict:** Not a doc-vs-code drift in the conventional sense; this is a code internal-consistency bug already flagged by `B-State-05` F-02. The doc isn't lying; the doc just doesn't (and shouldn't) describe the defensive-normalization edge.

---

## Summary table

| # | Topic | Verdict | Severity |
|---|---|---|---|
| 1 | Deck and deal | ALIGNED | — |
| 2 | Bidding overview | ALIGNED (overcall window not mentioned) | LOW |
| 3 | Card values, hand totals | ALIGNED | — |
| 4 | Melds table (most rows) | ALIGNED | — |
| 5 | **Carré-A in Sun = 200 in melds table** | **DRIFT** (DOC stale, internal contradiction with line 152-162) | **HIGH** |
| 6 | 9-of-trump rank vs Carré | ALIGNED | — |
| 7 | Escalation chain | ALIGNED | — |
| 8 | Sun ×2 multiplier | ALIGNED | — |
| 9 | Implicit AKA via bare-Ace lead | DRIFT (DOC-AHEAD: not enforced in `Rules.lua`) | MEDIUM |
| 10 | AKA-on-trump trick lock comment | DRIFT (`Rules.lua:108-110` comment misleading) | LOW |
| 11 | **SWA ≤3 instant claim** | **DRIFT** (CODE-AHEAD: v0.5.17 routes ALL through window) | **MEDIUM** |
| 12 | Al-Kaboot bidder-only claim | DRIFT (DOC-AHEAD: code is type-blind) | MEDIUM |
| 13 | **Reverse Al-Kaboot UNWIRED** | **DRIFT** (DOC-AHEAD: `K.AL_KABOOT_REVERSE` doesn't exist) | **HIGH** |
| 14 | Kasho/Qaid 26/16 split | DOC-AHEAD (doc honestly notes the gap) | LOW |
| 15 | Belote in Sun gate line ref | DRIFT (line `504` stale, actual is `694`) | LOW |
| 16 | Pos-4 ruff-relief line refs | DRIFT (line refs `117-121, 145-149` stale; actual `137-141, 166-169`) | LOW |
| 17 | Carré-A in Hokm | DRIFT (line refs `240-244` stale; actual `273-287`); plus `S.ApplyMeld` wire-path drop | LOW (line refs); MEDIUM (wire path, see B-State-05 F-04) |
| 18 | Score-rounding 5-up | ALIGNED | — |
| 19 | سيكل (9-8-7 tierce) | ALIGNED | — |
| 20 | Bid takweesh | N/A (Bot.lua scope) | — |
| 21 | Bel ×2 legality gate (Sun-only) | ALIGNED (1-point boundary phrasing imprecise) | LOW |
| 22 | **Half-and-half 81/162 fails** | DRIFT (DOC-AHEAD: ignores rule 4-10 inversion on Bel/Four) | LOW |
| 23 | **Failed bid → "bidder team gets 0"** | **DRIFT** (DOC-AHEAD: bidder keeps own melds × mult) | **MEDIUM** |
| 24 | Multiplier scope | ALIGNED | — |
| 25 | Trick-play rules | ALIGNED | — |
| 26 | Code-living-locations | ALIGNED | — |

**Top-priority doc fixes (recommended ordering):**
1. **HIGH** — Item 5: melds table line 55, change "200" → "400" for Carré-A in Sun. Self-contradicts the Q3 paragraph at lines 150-162.
2. **HIGH** — Item 13: explicitly tag Reverse Al-Kaboot as "**STATUS: UNWIRED, K.AL_KABOOT_REVERSE does not exist** — see `B-State-05` F-01."
3. **MEDIUM** — Item 11: rewrite SWA section to match v0.5.17 behavior (all calls go through 5s permission window). Cross-ref CLAUDE.md's already-correct framing.
4. **MEDIUM** — Item 23: rewrite "Failed bid → bidder gets 0" to "bidder card-trick points → 0, bidder keeps own melds × multiplier." Cross-ref `Rules.lua:823-836`.
5. **MEDIUM** — Item 9: Implicit AKA — clarify "convention" vs "code-enforced". `R.IsLegalPlay` does not auto-fire `akaRelief` on bare-Ace lead.
6. **MEDIUM** — Item 12: Al-Kaboot is bidder-OR-defender team; pair this with Item 13 (Reverse Al-Kaboot fix proposal).
7. **LOW (sweep)** — Items 15, 16, 17: regenerate stale line refs against current `Rules.lua`. Pre-v0.10.2-M4 line refs all shifted ~25-30 lines down due to AKA-relief insert at line 103.
8. **LOW** — Item 22: doc the 4-10 inversion edge case for tied 81/162.
9. **LOW** — Item 10: revise `Rules.lua:108-110` comment to drop "10-substitutes-for-Ace semantic" framing per `A-Src-07_v18_aka.md` HEADLINE FINDING.

---

## Cross-track references
- `B-State-05_scoreRound_full.md` — corroborates Items 13 (F-01), gahwa-typeblind (F-02), and Hokm-Carré-A wire-path drop (F-04).
- `A-Src-07_v18_aka.md` — corroborates Item 10 (AKA-on-T trick-lock not in source).
- `A-Src-09_v35_swa.md` — corroborates Item 11 (no timer in video #35; "نسمح" is verbal-only).
- `A-Src-06_v17_mathlooth.md` — out of scope for `saudi-rules.md` but contextual on mathlooth strategic ranking.
- `C-Xref-02_score_pipeline.md` — corroborates Items 22 (strict-majority `>`), 23 (fail branch keeps loser melds), 24 (multiplier scope).
- `CLAUDE.md` — already correctly framed on Items 11 (SWA UX timer) and 22 (strict-majority); doc lags CLAUDE.md on Items 11 and 23.

---

## Out-of-scope-but-noted
- `R.BeloteAllowed` named in audit brief — does NOT exist in `Rules.lua`. Belote logic is inline at `Rules.lua:692-709`.
- `R.ScoreCarre` named in audit brief — does NOT exist. Carré scoring is inline in `R.DetectMelds` at `Rules.lua:268-287`.
- `S.ApplyMeld` Hokm-A wire-path drop — `State.lua` scope; cross-ref `B-State-05` F-04.
- `Net.HostResolveTakweesh` 26/16 split — `Net.lua` scope; flagged in `saudi-rules.md` line 125 as "score side currently lacks the 26/16 split."

**End of audit. No code modified; read-only.**
