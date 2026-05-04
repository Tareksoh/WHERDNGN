# Decision trees — WHEN / RULE / MAPS-TO

Operational if-then chains, one per row. **This is the file
Claude Code should consult when translating a strategy note into
actual bot logic.** Each rule maps to a specific picker function
+ line range so the implementation site is unambiguous.

> **Format:**
> - **WHEN:** the trigger condition (game state).
> - **RULE:** the prescribed action.
> - **WHY:** one-line rationale.
> - **MAPS-TO:** the picker function + line; if not currently
>   encoded, write `(not yet wired)`.
> - **CONFIDENCE:** Definite (≥3 sources) / Common (≥2 sources or
>   one tournament-pro emphatic) / Sometimes (single source). Drop
>   below `Sometimes` unless load-bearing.
> - **SOURCES:** video slug(s) from `_transcripts/`.

> **Status (v0.5.4):** populated from videos 01-10. Many rules are
> single-source (`Sometimes`); cross-video corroboration upgrades
> them. Keep adding sources to upgrade confidence over time.

---

## Section 1 — Bidding (`Bot.PickBid` Bot.lua:890, `Bot.PickAshkal`)
<!-- Line numbers refreshed v0.5.15. Cell-level "MAPS-TO" line refs
     elsewhere may still be stale (drifted +165 to +461 across
     v0.5.8 → v0.5.14). See glossary.md for the current snapshot
     and the grep recipe to re-anchor. -->


### Hokm bidding triggers

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Hand has J of trump + ≥1 cover trump (مردوفة) + ≥1 side Ace | **Minimum Hokm-bid threshold met** — bid Hokm | The 3-card minimum: J wins trump-J trick, cover trump for ruffing, side-Ace for off-trump trick. | `Bot.PickBid` Bot.lua:725 strength formula — needs explicit min-hand check `(refinement, partial wire via threshold)`. | Definite | 26 |
| Hand has 4+ trumps including J | **Bid Hokm confidently** — "أحلى وأحلى" tier | Trump-heavy hand maximizes Hokm advantage. | `Bot.PickBid` strength formula. | Definite | 26 |
| Hand has 5+ trumps including J | **Bid Hokm + plan Al-Kaboot** | 5-trump hand has Kaboot-feasibility. Set a flag for `pickLead` to enter pursuit-mode early. | `Bot.PickBid` + new `S.s.pursuitFlagBidder` for `pickLead` Bot.lua:953. **Not yet wired.** | Common | 26 |
| Hand has 0-2 trumps OR no J of trump | **Pass on Hokm** | Below the 3-card minimum threshold. | `Bot.PickBid`. | Definite | 26 |
| Borderline strength + uneven side-suit distribution + 1 trump cover | **Prefer Hokm over Sun** | Failed Hokm = 16 raw vs failed Sun = 26 raw. Hokm is the safer default. | `Bot.PickBid` should weight Hokm-vs-Sun choice via this asymmetry. | Definite | 25, 26 |
| Hand has K+Q trump (Belote/سراء ملكي) AND 2+ trumps total | **Mandatory Hokm** with that suit as trump | Belote +20 multiplier-immune locked in by bidding the right trump. | `Bot.PickBid` Belote-detection branch. | Definite | 26 |

### Sun bidding triggers

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Hand has at least 1 Ace, preferably **A+T mardoofa** (إكة مردوفة) | **Minimum Sun-bid threshold met** | A+T mardoofa anchors a Sun bid: T covers the A from being torn through. | `Bot.PickBid` Sun branch — needs explicit "ATmardoofa" check `(not yet wired)`. | Definite | 25 |
| Hand has 2+ Aces (one mardoofa) | **Sun-bid territory** | Sustained trick-winning power across 2+ suits. | `Bot.PickBid` Sun strength formula. | Definite | 25 |
| Hand has 3+ Aces (any distribution) | **Strong Sun-bid** — almost always Sun | The 26-vs-16 risk premium is paid by sustained trick power. | `Bot.PickBid` Sun strength formula. | Definite | 25 |
| Hand has Carré of Aces (الأربع مئة) | **Mandatory Sun** | 200 raw × 2 (Sun multiplier) = 400 effective (الأربع مئة "Four Hundred"). | `Bot.PickBid` + meld-detection. | Definite | 25, 32, 38 |
| Hand has 1 Ace, no T to cover | **Do NOT bid Sun** — vulnerable | A bare Ace gets torn through; need cover. | `Bot.PickBid` anti-trigger. | Common | 25 |
| Hand has long suit (4+) without Aces | **Do NOT bid Sun** — long suits without anchors lose | Long-no-Ace = passive in no-trump. | `Bot.PickBid` anti-trigger. | Common | 25 |
| Cumulative score ≥100 (Sun-Bel-gate context) | **Caution: defenders at <100 may Bel you** | Bel-fear band 120-vs-90: defender at 90 is dangerously close to a Bel-doubled penalty if they Bel. | `Bot.PickBid` should consult `S.s.cumulative` for Bel-fear bias `(not yet wired)`. | Common | 25 |
| **Sun-Mughataa (الصن المغطى)** — A+T mardoofa | Distinct strength bonus over raw Ace count | "Covered Sun" emphasizes safety. | `Bot.PickBid` strength formula — A+T pair = +bonus over 2 separate Aces. | Common | 25 |

### Ashkal triggers (only dealer + dealer's LEFT may call)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Seat is NOT dealer or dealer's left | **Ashkal forbidden — pass or bid normally** | Saudi rule (rule of game, not heuristic). | State.lua:1464-1487 enforces via `bidPosition < 3`. NextSeat(s)=right per UI.lua:223 → dealer's-LEFT = bidPosition 3, dealer = bidPosition 4. | Definite | 27, 31 |
| Eligible seat; hand is Sun-bid-eligible (≥1 Ace, ideally mardoofa); bid-up card is small/mid (7,8,9,J,Q,singleton-T) | **Ashkal — convert partner's contract to Sun** | Bid-up small = your no-trump conversion advantage. | `Bot.PickAshkal` — add bid-up rank check `(not yet wired)`. | Common | 31 |
| Eligible seat; bid-up card is **A** of a suit | **Do NOT Ashkal** — losing the A into Sun with no protection | Bid-up Ace would be torn through immediately. | `Bot.PickAshkal` anti-trigger `(not yet wired)`. | Definite | 31 |
| Eligible seat; bid-up is **T with A in your hand same suit** | **Do NOT Ashkal** — mardoofa already exists; preserve via Hokm | Hokm preserves the A+T pair. | `Bot.PickAshkal` anti-trigger `(not yet wired)`. | Common | 31 |
| Eligible seat; you hold 3+ Aces | **Bid direct Sun, not Ashkal** | At 3+ Aces you don't need partner; claim contract yourself. | `Bot.PickAshkal` should pass strength to direct Sun branch. | Common | 31 |
| Strength ≥ 85 (well above Ashkal threshold of 65) | **Pivot to direct Sun** | 65-84 = Ashkal range; 85+ = direct Sun range. | `Bot.PickAshkal` strength tier — currently single threshold at `K.BOT_ASHKAL_TH = 65`; should add 85 pivot. | Common | 31 |

### General bidding goal-discipline

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Deciding whether to bid Hokm/Sun/Ashkal | Commit only if hand has path to (a) making OR (b) sweeping (Al-Kaboot). Else pass. | A bid implicitly commits to one of two outcomes; pathless bids are undisciplined. | `Bot.PickBid` strength threshold partially encodes (a); Al-Kaboot-path check `(not yet wired)`. | Common | 07, 25, 26 |
| **Round 1, first lap, borderline hand** | **Pass** to see what others do | Round 2 has more info; round-1 over-bidding is the most common amateur mistake. | `Bot.PickBid` round-1-conservative bias `(not yet wired)`. | Common | 25 |
| Round 2 (terminal), hand at minimum threshold | **Bid the strongest available** (don't repeat round 1) | Round 2 redeal if all pass; commit. | `Bot.PickBid` round-2 bias toward bidding. | Common | 25, 27 |
| **Bid takweesh** (override partner's contract) — your hand has Hokm/Sun-bid-strength but partner already bid | Generally do NOT bid against partner's contract. Exception: partner was hesitant + bid Sun + early in bidding. | Partner's "project" (مشروع) makes your strong cards into partner-supply, not override material. | `Bot.PickBid` should NOT outbid partner's contract under normal conditions `(refinement)`. | Common | 29 |

---

## Section 2 — Escalation (`Bot.PickDouble` 2403, `PickTriple` 2534, `PickFour` 2564, `PickGahwa` 2608)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| **Sun contract**, your team's cumulative score is ≥100 | **Bel is FORBIDDEN** — legality gate, not heuristic. | Hard Saudi rule: only the team <100 may Bel in Sun. Hokm has no such gate. | `Bot.PickDouble` Bot.lua:1787 — needs `S.s.cumulative[myTeam] < 100` precondition for Sun contracts. **Rule-correctness item: also `R.CanBel(team, contract)` in `Rules.lua`.** | Definite | 11 |
| Hokm contract, any score | Bel allowed regardless of score | "الحكم مفتوح في الدبل" | Existing `Bot.PickDouble`, no change | Definite | 11 |
| Round 1 of any session | **Round-1 Bel restricted** (exact rule TBD from follow-up video) | Anti-grief convention | Need follow-up video to confirm exact mechanism. | Sometimes | 11 |
| Cards have been revealed in any prior trick | Bel window is **closed** (مقفول) — cannot Bel mid-round | Once info is exposed, no further escalation. | `Bot.PickDouble` should be gated to call window only (currently is, via phase). | Common | 11 |
| Hokm contract, your team is the **bidder** team, you've won tricks 1-2 cleanly without opponent cut, hand has Kaboot-feasible shape (J+9 trump + cover + void/singleton + partner-supply) | Switch to **Al-Kaboot pursuit mode** at trick 3 (not trick 8) | Sweep needs the full 8 — only viable if no opp cut surfaces in tricks 1-2. Earlier-trigger pursuit lets you optimize tricks 3-7 for sweep. | `pickLead`/`pickFollow` Kaboot-pursuit flag — currently only trick-8 logic; needs trick-3 trigger in Bot.lua:953. **Partial wire.** | Common | 15 |
| Sun contract, you're the bidder, on track to make + Bel-multiplier > Kaboot bonus | **Sabotage own sweep** (تخريب الكبوت) — let opp win one trick to land at multiplier instead of Kaboot constant | When `K.MULT_BEL × hand_total > K.AL_KABOOT_SUN`, the multiplier path scores higher than the sweep. | New `pickFollow` branch — score-aware sweep abandonment. **Not yet wired.** | Sometimes | 15 |
| Defender team threatened by opponent's near-Kaboot, you have an opportunity to call **Qaid-bait** (تقيد عليه) | Deliberately mis-Qaid to swap the 250-Kaboot for 26-Qaid penalty | Trade the bigger loss for a smaller one. House-rule-territory; risky. | Player-tier maneuver; bot likely should NOT do this without dedicated heuristic. **Defensive note only.** | Sometimes | 15 |

---

## Section 3 — Opening leads (`pickLead` Bot.lua:1289)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| You hold strength in side-suit X (e.g., a Ten as your top); turn comes to you and partner has not yet captured a trick | Hold the strong card for END of round; lead a Tahreeb signal first instead. | Strong-card timing: keep your top as the final winner, not the opening shot. Leading the T early lets opponents equalize / cut. | `pickLead` Bot.lua:953 strong-card-hold branch `(not yet wired)`. | Common | 09 |

---

## Section 4 — Mid-trick play (`pickFollow` Bot.lua:1882, positions 2-3)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| **Sun**, **OPP** is winning the trick, you must follow with cards that can't beat | **Tasgheer** — play **SMALLEST** of legal in-suit cards (typically absolute lowest). | Saudi tasgheer / play-smallest convention: under a winning higher card, dump your smallest non-saving card. Per video #05 transcript: opp's K-play implies no Q/J/9/8/7 below it (those would have been played first because they are smaller than K in plain rank). Mirror: we play smallest non-saving = absolute lowest (no "winning save" candidates exist when we've already failed the can-we-win check). | `pickFollow` Bot.lua opp-winning follow branch — **wired v0.7.2** (was v0.5.11 over-correction "dump HIGHEST", reverted per #05 re-read). | Common | 05 |
| **Sun**, **PARTNER** is winning the trick (e.g. partner led, or partner is current winner), you must follow with cards that can't beat | Play **SECOND-LOWEST** — explicitly NOT absolute lowest. | "Biggest mistake in Baloot" per video #09: absolute lowest signals "I'm out of this suit, partner can't lead it back to me". Second-lowest preserves the re-entry — partner can still lead this suit back, knowing you may have a higher card to take. Layered AFTER the smother branch (Section 4 rule 7); only fires when no point-card donation is possible. | `pickFollow` Bot.lua partner-winning fallback — **wired v0.7.2**. | Definite | 09 |
| **Hokm**, you are losing-side **trump** follow (must trump, can't over-trump partner/opponent winner) | Dump the **LOWEST** trump you have — inverse of the Sun rule. | "If they had a smaller trump they'd play it." Saving high trumps preserves cover for later tricks. | `pickFollow` Bot.lua:1457 Hokm trump-follow branch. State already partially captured by `Bot._memory[seat].void[trump]` writes (Bot.lua:282-292). Read-side `(not yet wired)`. | Definite | 05 |
| **Sun**, partner is winning the trick; you are void in led suit and must discard | Encode a Tahreeb signal in your discard (see Section 8). Every such discard MUST carry positive or negative directional preference. | "Each card you play must have a reason" — Tahreeb is the framework. | `pickFollow` Bot.lua partner-winning discard branch (wired in v0.5.10 T-1 Bargiya / T-4 dump-ordering). | Definite | 01, 03, 09, 10 |
| **Sun**, you'd take the trick anyway with a smaller card and you hold both J and 9 (or T and 9) of the led suit; partner has played the T or higher | **Sacrifice the J** (top) instead of the natural 9 — bait opp into believing you're void below J, so they re-lead the suit. | Deception: opp re-leads → walks into your saved 9. Captures two tricks instead of one. **Saudi-Master variant:** sacrifice the **T** instead of J (highest tier only — explicit "only a real pro plays this"). | `pickFollow.deceptiveOverplay` Bot.lua:1457 Sun branch `(not yet wired)`. M3lm+ for J variant; Saudi Master only for T variant. | Sometimes | 08 |
| **Hokm**, same shape as above; partner played mid-trump, opp played low, you have J of trump and 9 of trump and would win anyway | **Sacrifice the J of trump** (الولد) — but goal **inverts**: now you want opp NOT to re-lead trump (preserving your remaining 9 as future winner). | Inverted use of the same deception. T and 9 of trump are "AKA-equivalent" — never sacrifice them. | `pickFollow.deceptiveOverplay` Bot.lua:1457 Hokm branch `(not yet wired)`. Anti-trigger: `holds(A_trump) && trumpCount >= 3`. | Sometimes | 08 |
| Hokm, you hold ≥3 trumps including A | Do NOT use deceptive overplay — A guarantees a winner regardless. | Bait is wasted; saving J for a meaningful pull is more valuable than burning it for unneeded deception. | `pickFollow.deceptiveOverplay` gate-off condition `(not yet wired)`. | Common | 08 |

### Takbeer / Tasgheer (magnify / miniaturize) — certainty-conditioned

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Trick-winner is **CERTAIN partner** (any contract, off-trump suit) | **Takbeer** — play your HIGHEST card. Donate ابناء. | Maximize trick-point capture when partner takes it. | `pickFollow` partner-certain-winning branch `(not yet wired)`. | Definite | 21, 22, 23 |
| Trick-winner is **CERTAIN opponent** (any contract) | **Tasgheer** — play your LOWEST card. Deny ابناء. | Minimize point gift to opponent. | `pickFollow` opp-certain-winning branch `(not yet wired)`. | Definite | 21, 22, 23 |
| Trick-winner is **UNCERTAIN** | Fall through to Tahreeb / Tanfeer / Faranka signaling logic | Certainty-conditioned rules only apply when winner is determined. | `pickFollow` priority chain: certain-winner-Takbeer/Tasgheer > Tahreeb > Faranka. | Definite | 21, 22, 23 |
| **Hokm trump suit**, you hold rank-CONSECUTIVE top trumps | Takbeer-mandatory — play HIGHEST | Consecutive ranks = no opp can slip a higher trump between yours. | `pickFollow` Hokm-trump branch — `K.RANK_TRUMP_HOKM` adjacency check `(not yet wired)`. | Definite | 22 |
| **Hokm trump suit**, you hold NON-consecutive top trumps (gap in rank order) | **INVERT** — preserve top, lead/play side first | Opp can ambush between your two ranks. Your top is a "lone top" with no immediate cover. | `pickFollow` Hokm-trump non-consecutive branch `(not yet wired)`. | Definite | 22 |
| Hokm; must over-cut and hold consecutive trumps | Over-cut with the SMALLER (preserve top for ambush) | Save top for true ambush opportunity. | `pickFollow` over-cut branch `(not yet wired)`. | Definite | 22 |

### K-tripled (مثلوث الشايب) — 3-card K-holding

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Sun, you hold K + 2 lower in side suit (مثلوث الشايب); side suit is led | Play SMALLEST first across tricks 1-2; K lands trick 3 | The 3rd-trick K-capture is the entire point of the holding; opp's high cards typically go in tricks 1-2. | `pickFollow` Bot.lua:1457 K-tripled trickle branch `(not yet wired)`. | Common | 17 |
| Sun, you suspect opp holds مثلوث الشايب in suit X | Lead إكَه but withhold the T for trick 1 | Bait: opp Tanfeers a card from their مثلوث (preserving K for late capture). Forces info reveal. | `pickLead` Bot.lua:953 K-tripled exploit branch `(not yet wired)`. | Sometimes | 17 |

---

## Section 5 — Pos-4 (last-to-play) plays (`pickFollow` pos-4 branch Bot.lua:1882)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| **Sun**, you are pos-4; partner already winning trick with high card; you hold A + next-highest (e.g. A+T or A+K) of led suit | **Faranka — duck with the smaller of your two high cards** (play T / K), let partner take this trick. You pick up the next trick with the A. | Captures two tricks instead of one; "fishes" opp's missing 10 on the next round. | `pickFollow` Bot.lua:1457 pos-4 Faranka branch `(not yet wired)`. | Definite | 06 |
| Sun, pos-4; partner is sweeping toward Al-Kaboot (≥6 tricks won); your A would block partner's run | Faranka — duck under partner's high card. Preserve the sweep. | Al-Kaboot bonus 220 raw × 2 (Sun) = 440 effective; dominates single-trick value. | `pickFollow` pos-4 Al-Kaboot pursuit branch `(not yet wired)`. | Definite | 06 |
| Sun pos-4; you hold the **two highest unplayed** cards of the led suit | NEVER Faranka — play normally to capture both tricks. | Ducking gives opp's smaller-high a free win because partner has nothing better. | `pickFollow` Bot.lua:1457 anti-Faranka guard `(not yet wired)`. | Definite | 06 |
| Sun pos-4; you hold ≥3 cards of the suit | Do NOT Faranka — 10 likely drops naturally; play A normally. | Concentrated suit means doubleton-or-shorter 10s drop early in others' hands. | `pickFollow` anti-Faranka guard `(not yet wired)`. | Definite | 06 |
| Sun pos-4; you have only A (no J of suit, no second-highest) | Generally do NOT Faranka — without J as recapture vehicle, ducking gives up control. | "Faranka percentage" drops without the J. | `pickFollow` Faranka gate `(not yet wired)`. | Common | 06 |
| Sun pos-4; you hold T (no A); the A is known to be at LHO (next leader) | Do NOT Faranka — take this trick with the T. | T won't survive — LHO will lead and pull or capture it. | `pickFollow` Bot.lua:1457 `(not yet wired)`. | Common | 06 |
| Sun pos-4 considering Faranka; the high card you'd "release to" sits with RHO (just played a low card e.g. 8) | **Strongest Faranka spot** — duck. RHO probably holds the missing 10; partner will recapture. | Three cards on table = max info; risk bounded. Factor 5 of the "5 factors". | `pickFollow` pos-4 Faranka score boost `(not yet wired)`. | Definite | 06 |
| Sun pos-4; LHO led the suit and is on the bidding team in trick 1 of fresh hand | Faranka anyway despite LHO-lead — bidder probably holds the 10. | Bidder-team-leader-of-fresh-hand presumed strong. | `pickFollow` Bot.lua:1457 with bidder-team check `(not yet wired)`. | Sometimes | 06 |
| Sun pos-4; LHO led; **opponents are bidders** (your team defender) | Do NOT Faranka — take the trick to deny opps Al-Kaboot. | Defending against Al-Kaboot dominates +10 fishing. | `pickFollow` defender branch `(not yet wired)`. | Common | 06 |

---

## Section 6 — AKA / signaling (`Bot.PickAKA` Bot.lua:2302, AKA-receiver in `pickFollow`)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Sun trick 1, partner leads Ace (or AKA-led); next-to-act partner plays T (Ten) | Infer: **partner has the K (Shayeb)** of that suit. (Touching-honors-down convention.) | Saudi rule: "if partner played T, K must be with partner." Partner wouldn't waste T unless K is safely held. | `pickFollow` partner-supply read; new ledger key proposal: `Bot._partnerStyle[partner].toptouchSignal` increment `(not yet wired)`. | Definite | 05 |
| Same setup, partner plays K under your Ace | Infer: partner has the Q (Bint) — next-down touching honors. | Same convention, one rung down. | Same as above. | Definite | 05 |
| Same setup, partner plays Q under your Ace | Infer: partner has the J (Walad) — next-down. | Same convention, two rungs down. | Same. | Definite | 05 |
| Partner plays a clear LOW card (e.g. 7 or 8) under your winning lead | Infer: partner is **broke in suit's high cards**. NEVER assume the unseen high is partner's. | Inverse of touching-honors signal. | Sampler suit-X high-card allocation; should NOT pin to partner if partner played low. `(not yet wired)`. | Common | 05 |
| AKA partner-call window — you hold the highest unplayed card in some non-trump suit | Consider AKA call. Receiver convention applies in `pickFollow` — H-5 (v0.5.1). | Standard Saudi AKA convention. | `Bot.PickAKA` Bot.lua:1686; receiver in `pickFollow` Bot.lua:1457. | Definite | 05 + existing v0.5.1 H-5 |
| Hokm, you are leading trick-1 with the **bare Ace** of a non-trump suit (no AKA explicitly broadcast) | Receiver applies AKA-receiver convention anyway — **implicit AKA** | Saudi convention: leading bare Ace in non-trump = implicit AKA call. Receiver suppresses ruff. | Extend `pickFollow` H-5 receiver branch to fire on partner's bare-Ace lead AND `S.s.akaCalled == nil`. **Refinement of v0.5.1 H-5.** | Definite | 18 |
| Hokm, you are pos-4 (last to play); partner is currently winning the trick; you are void in led suit | **Released from must-ruff** — may discard non-trump instead | Saudi rule: must-trump obligation lifts when partner is the current trick-winner. Saves trump for future tricks. | **ALREADY WIRED:** `R.IsLegalPlay` Rules.lua:118-121 (trump-led branch) and Rules.lua:147-149 (off-lead-trump branch) both have the partner-winning exception. The actionable gap is a `pickFollow` heuristic that *prefers* a non-trump discard when released — currently the bot defaults to lowestByRank which may pick a trump anyway. | Common | 42 |
| Hokm, partner verbally announced AKA on highest unplayed of led suit | **Released from must-ruff** — already wired (v0.5.1 H-5) | Same as above; AKA is the explicit form. | `pickFollow` H-5 (v0.5.1). | Definite | 42 + existing |
| **AKA must be VERBAL** — silent high-card play does NOT confer AKA-receiver relief | If you play the highest unplayed without announcing, partner is NOT obligated to defer | Saudi convention is verbal-announcement-required. | `Bot.PickAKA` Bot.lua:1686 already gates on explicit broadcast (`S.s.akaCalled` state). No change needed. | Definite | 42 |
| AKA-call decision (sender side) preconditions | All of: (a) contract == Hokm; (b) card.suit != trump; (c) card.rank != "A"; (d) you hold the HIGHEST UNPLAYED of that suit; (e) you're leading + trick has 0 plays so far; (f) NOT (partner certainly void in trump); (g) round_stage allows (early-stage with low scoreUrgency, OR top-of-suit confidence is certain). | Tightens existing AKA-call gate. | `Bot.PickAKA` Bot.lua:1686 — augment with predicates (f) and (g). | Definite | 18 |

---

## Section 7 — Endgame / SWA / Al-Kaboot (`Bot.PickSWA` Bot.lua:2746, `pickLead` trick-8 branch Bot.lua:1289)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Bidder team, on track to make + Al-Kaboot reachable (won ≥6 tricks) | **Promote secondary goal: pursue Al-Kaboot.** Kaboot points dominate single-trick gains. | `K.AL_KABOOT_HOKM`=250, `K.AL_KABOOT_SUN`=220 (×2 = 440 in Sun). | `pickLead` trick-8 branch Bot.lua:953 — sweep-pursuit logic exists; promote Kaboot earlier in round `(partial wire)`. | Common | 06, 07 |
| **Trick 3 trigger:** bidder team won tricks 1+2 cleanly (no opp cut) AND hand-shape is Kaboot-feasible: Sun = 2× A+T pairs + extra A; Hokm = J+9 trump + cover + void/singleton + partner-supply | **Switch to Kaboot-pursuit mode at trick 3, not trick 8** | If no opp cut by trick 2, trump distribution is favorable; sweep is genuinely reachable. Earlier trigger lets tricks 3-7 be optimized for sweep. | `pickLead`/`pickFollow` Kaboot-pursuit flag — currently only trick-8 logic; needs trick-3 trigger in Bot.lua:953. **Partial wire — only trick-8 currently active.** | Common | 15 |
| Bidder, Sun contract, you're winning + score-tracking shows `K.MULT_BEL × hand_total > K.AL_KABOOT_SUN` | **Sabotage own sweep** (تخريب الكبوت) — let opp win one trick to land at multiplier instead | Multiplier path scores higher than the sweep when Bel was called. House-rule territory; sometimes-applicable. | New `pickFollow` score-aware sweep abandonment branch `(not yet wired)`. | Sometimes | 15 |
| Defender threatened by opp's near-Kaboot (opp has won tricks 1-N) | **Qaid-bait** (تقيد عليه) — deliberately mis-Qaid to swap 250-Kaboot for 26-Qaid penalty | Trade bigger loss for smaller. Risky; player-tier maneuver. | `Bot.PickPlay` defender branch — bot likely should NOT do this without dedicated heuristic. **Defensive note only.** | Sometimes | 15 |
| Defender, opponents threatening Al-Kaboot | **Primary defender goal #1: prevent Kaboot.** A single trick won is "first success" (كسرت كبوت). | Removes +250/+220 risk from a sweep. | `pickFollow` Bot.lua:1457 — implicit; could become explicit "anti-Kaboot mode" flag. | Common | 07 |
| Defender, mid-round, bidder making | **Primary defender goal #2: force bidder to FAIL.** Capture high-value tricks even at cost of low-card discipline. | A failed bid hands all trick points to defenders (`R.ScoreRound`); strictly better than just preventing Kaboot. | `pickFollow` defender branches; `scoreUrgency` Bot.lua:588 already tracks point-race urgency. | Common | 07 |
| Sun, partner is winning a trick; you hold A of suit X and want partner to lead X next | Play **A on this trick (Bargiya / برقية)** — Ace-discard signals "lead X, I have the slam (SWA)". | Ace-discard is the maximally strong "come here" signal. | New `pickFollow` Bot.lua:1457 Bargiya branch; integrates with `Bot.PickSWA` follow-up `(not yet wired)`. | Common | 01 |
| Sun trick 8 / very late round; you've Bargiya'd in suit X earlier; turn comes to you | Lead X if held; the deception buys SWA tempo. | Per video #8: "set up SWA" is one of the three Faranka payoffs; same logic for Bargiya. | `pickLead` Bot.lua:953 Bargiya-followup branch `(not yet wired)`. | Sometimes | 01, 08 |
| **Reverse Al-Kaboot** — defenders sweep all 8 against bidder; bidder was trick-1 leader | Score +88 raw to defending team (proposed `K.AL_KABOOT_REVERSE = 88`) | Saudi rule: full defender sweep is a recognized scoring outcome with its own bonus. | New `R.ScoreRound` branch — gating predicate `defenderSweep && firstLeader == bidder`. **Rule-correctness item; single-source from video #16; confirm before wiring.** | Sometimes | 16 |
| **SWA card-count thresholds** | ≤3 cards = instant; 4 = جلسة-dependent تستاذن; 5+ = mandatory تستاذن | Video #35 refines thresholds; current code: instant <= 3 / permission >= 4 (`K.SWA_TIMEOUT_SEC=5`). 5+ rule **stricter** than current code. | `Net.MaybeRunBot` SWA dispatch + `Bot.PickSWA` Bot.lua:2120 — review against #35 stricter rule. | Common | 35 |
| **SWA = deterministic-or-bust (Saudi-strict)** | Speaker explicitly rejects sub-100% SWA claims | Earlier suggestion of "probabilistic SWA" for Saudi Master tier was WRONG; Saudi convention is deterministic only. | Update `Bot.PickSWA` and `BotMaster.PickPlay` ISMCTS — do NOT generate sub-100%-certain SWA claims. **Earlier endgame.md "probabilistic SWA" note RETRACTED.** | Definite | 35 |
| Opp denies your SWA claim via Takweesh, demanding شرح (proof) | If you cannot prove (the claim was unsound), you incur a Qaid against you | Saudi penalty for false SWA. | `Net.HostResolveSWA` outcome path — `K.MSG_SWA_OUT` carries result. | Common | 35 |

---

## Section 8 — Tahreeb (تهريب) — partner-supply convention

The most heavily-sourced section: 5 of 10 videos. **This is the central Saudi-Baloot partnership convention**; bot needs first-class support.

### Sender side (you discard while partner is winning)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Sun, partner winning trick; you must discard; you hold A of suit X and want partner to lead X | **Bargiya** — discard the A of X. Strongest "want this suit" signal. | Ace-discard = "I have the slam in X, lead it." | `pickFollow` Bot.lua:1457 Bargiya branch `(not yet wired)`. | Definite | 01, 03 |
| Sun, partner winning; you want suit X (without holding A of X) | **Bottom-up sequence in X**: discard low first (7/8), higher (9/J) on next discard. | Two-trick ascending sequence = "I want this suit, no Ace to Bargiya." | `pickFollow` Bot.lua:1457 ascending-discard pattern `(not yet wired)`. | Definite | 01, 09, 10 |
| Sun, partner winning; you do NOT want suit X | **Top-down sequence in X**: discard high first (J/9), lower next. | Two-trick descending = "I refuse this suit." | `pickFollow` Bot.lua:1457 descending-discard pattern `(not yet wired)`. | Definite | 01, 10 |
| Sun, partner winning; you must dump from a 2-card suit you don't want (e.g. J + 9 of unwanted suit) | Always dump the **LARGER first** (J before 9), never smaller first. | Larger first = unambiguous refusal; smaller first = false bottom-up positive signal. | `pickFollow` Bot.lua:1457 dump-ordering rule `(not yet wired)`. | Definite | 01 |
| Sun, partner winning; you hold STRONG suit (K+T after A gone, or two top cards) | **Do NOT Tahreeb the strong suit.** Tahreeb a different suit; partner reads "opposite color/shape" and returns the strong one you withheld. | Saving strong suits for later; partner-return convention is "lead the suit you didn't Tahreeb". | `pickFollow` discard-suit-selection branch `(not yet wired)`. | Common | 03 |
| You become the cutter (will ruff opponent's lead) AND partner has 100% taken some prior reference trick | Your **ruff IS the Tahreeb event** — the suit you discard while ruffing carries the message. | Tahreeb works through any "throw away" while teammate is winning, not just on partner's leads. | `pickFollow` ruff branch — Tahreeb-aware discard-selection `(not yet wired)`. | Common | 03 |

### Receiver side (partner Tahreebs to you)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Partner Tahreeb'd (single event, low card discarded on your win) | Treat as **negative signal about led suit + positive pointer to another suit**. Read 70/25/5 prior across other three suits. Wait for second Tahreeb to disambiguate. | First Tahreeb is a hint, not certainty. Speaker explicit: "تهريب يحتاج تهريب ثاني عشان يأكد". | Style ledger read in `pickLead` Bot.lua:953 `(not yet wired)`. | Definite | 09 |
| Partner Tahreeb'd a SECOND card in same suit, in clear ascending or descending direction | **~90% confirmed:** lead the inferred target suit on next opportunity. | Two-trick sequence is the disambiguation signal. | `pickLead` Bot.lua:953 two-Tahreeb sequence detector `(not yet wired)`. | Definite | 09, 10 |
| Partner Tahreeb-led (low) and you hold **bare T (singleton)** in the candidate return suit | **Lead the T immediately.** | Standard Tahreeb-return; if you hold off, opps read partner as having T and capture it. | `pickLead` Bot.lua:953 Tahreeb-return-bare-T branch `(not yet wired)`. | Common | 02 |
| Partner Tahreeb'd; you hold **T + 1 other (T mardoofa/doubled)** AND **partner is Sun bidder** | **Lead the SIDE card (NOT the T).** Sun bidders concentrate strength differently; T safer to retain. | Sun-bidder special case; partner expected to hold the missing strength. | `pickLead` Bot.lua:953 — branch on `S.s.contract.bidType == K.BID_SUN && bidder == partner` `(not yet wired)`. | Common | 02 |
| Partner Tahreeb'd; you hold T + 1 other (T doubled); partner is **NOT** Sun bidder | **Lead the T** — Tahreeb principle dominates. | If you lead the side, opps read you as holding T and "tafranak" (duck) to catch your T later. | `pickLead` Bot.lua:953 Tahreeb-return-doubled-T default `(not yet wired)`. | Common | 02 |
| Partner Tahreeb'd; you hold T + 2+ side cards (T tripled+) | **Lead LOW (8 or 9), NOT the T.** | With 2+ side cards you have safety; preserve T as re-entry. | `pickLead` Bot.lua:953 Tahreeb-return-tripled-T branch `(not yet wired)`. | Common | 02 |
| Receiver: you have NO winning card in the Tahreeb-suggested suit on second event | Send your **highest available** card back to partner — the high return is your only contribution. Do NOT play absolute lowest. | Even forced, cooperate maximally. Lowest = "biggest mistake in Baloot". | `pickFollow` Bot.lua:1457 high-card-return discipline `(not yet wired)`. | Definite | 09 |
| Receiver: partner Tahreeb-led small→big in suit X; you hold T of X | Lead the T of X back to partner. | Partner's small→big tahreeb implies partner does NOT have the T — supply it. | `pickLead` Bot.lua:953 partner-return T-supply branch `(not yet wired)`. | Definite | 10 |
| Receiver: you've already won partner's Tahreeb-return trick; partner re-supplies the suit | **Do NOT capture again with T** (release control). | Holding the T blocks partner's continuation; partner may have K or J to win the next trick. | `pickFollow` Bot.lua:1457 release-control branch `(not yet wired)`. | Common | 02 |
| Sender's strong suit is X but only 3 cards in hand | Don't Tahreeb FROM X. Tahreeb from a different (weak) suit using opposite-color/shape mapping. | Burning your strong suit defeats the purpose. | `pickFollow` discard-suit-selection `(not yet wired)`. | Common | 09 |

### Three-discard variant

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| You'll Tahreeb across 3 discards (e.g., have 7+9+J in target suit, 3 partner-winning tricks ahead) | Discard 2 smallest in **strict ascending order** (7→9), keep biggest (J) for last. Avoid mixing direction. | 3-card sequence small-to-big-to-bigger remains coherent; any descending step looks like reversal. | `pickFollow` extended discard-pattern `(not yet wired)`. | Common | 10 |

---

## Section 9 — Tanfeer (تنفير) — opponent-disrupt convention

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| OPPONENT (not partner) has 100% taken the trick; you must discard / ruff | Discard the suit you DO want partner to return (inverse of Tahreeb). | Against opp there's no point hiding strength via "negative discard"; positive-signal directly. | `pickFollow` Bot.lua:1457 opponent-winning discard branch `(not yet wired)`. | Common | 03 |
| Trick-winner uncertain (not near-certain who wins) | **Default to Tahreeb semantics, NOT Tanfeer.** Tahreeb is the dominant convention. | Speaker explicit: "تهريب اقوى من تنفير وقاعده تهريب تمشي معاك اكثر." | `pickFollow` discard branch fallback `(not yet wired)`. | Common | 03 |
| Opponent does small→big tahreeb-style discard on you | Recognize: opp wants that suit returned by their partner. **Do NOT lead that suit; treat as suit-to-AVOID.** | Same convention applies to opp; useful when opp's partner has cards there. | `pickLead` Bot.lua:953 opponent-read branch `(not yet wired)`. | Common | 10 |

---

## Section 10 — Faranka (فرنكة) — withhold-the-top deception

### Sun Faranka (default = YES when factors align)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Sun, you hold J+A of led suit, partner is taking trick, you are pos-3/4 | **Faranka — duck with the J or smaller**, let partner take, capture next trick with A. | Captures two tricks; fishes opp's 10. | See Section 5 for full pos-4 rules. | Definite | 06 |
| Sun pos-4; partner is on Al-Kaboot run (won ≥6); your A would block | Faranka — duck. Preserve sweep. | 220 raw × 2 = 440 effective bonus dominates. | `pickFollow` pos-4 Al-Kaboot pursuit `(not yet wired)`. | Definite | 06 |
| Sun, Faranka would flip round-loss to opponents (score-tracking shows game-flipping outcome) | Faranka — extra fished +10 lands on already-losing team. | "Score-the-loss-on-them" logic. Factor 4 of the 5. | `pickFollow` Bot.lua:1457 score-aware Faranka `(not yet wired)`. | Sometimes | 06 |

### Hokm Faranka (default = NO except narrow exceptions)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| **Hokm**, no exception condition active | **Default: do NOT Faranka.** Play natural high trump. | Trump is short; withholding high-variance and dangerous. | `pickFollow` Bot.lua:1457 Hokm-trump default `(not yet wired)`. | Definite | 04 |
| Hokm exception #1: pursuing Al-Kaboot ("النوع الثالث") | Faranka allowed — variance acceptable because losing ANY trick already kills Kaboot. | "تقريبا نفس الصمت" — approximates Sun-style silence. | `pickLead` Bot.lua:953 trick-8 branch + earlier Kaboot-check `(not yet wired)`. | Common | 04 |
| Hokm exception #2: you hold only 2 trumps total | Faranka allowed — trump posture already weak. | Costs little incremental EV. | `pickFollow` two-trump Faranka branch `(not yet wired)`. | Common | 04 |
| Hokm exception #3: J of trump already played/dead, your 9 is now top live trump | Faranka allowed — withhold the new top to ambush opp's other high. | Your 9 is now the boss. | `pickFollow` top-trump-shifted branch `(not yet wired)`. | Common | 04 |
| Hokm exception #4: you are bidder + opponent trump exhausted | Faranka allowed — no one can punish the withhold. | Risk-free at this point. | `pickLead` bidder-clean-trump branch `(not yet wired)`. | Common | 04 |
| Hokm exception #5: partner has shown extra trump (cut a side suit cleanly) | Faranka risk decreases — partner takes cover-burden. | Cover-burden shifts to partner. | `pickFollow` partner-strong-trump branch + style ledger `(not yet wired)`. | Sometimes | 04 |
| Hokm; bidder is opp; opp led trump-Q; you hold trump-J + trump-8 | **Do NOT Faranka — play J normally, take trick.** | Opp has long trump; withholding gets rolled later. Direct counter-rule. | `pickFollow` defender-vs-bidder anti-Faranka `(not yet wired)`. | Definite | 04 |
| Hokm; you are pos-4 holding trump-9 only; opp Faranka'd by playing T after partner's J was over-trumped | **MUST take with the 9 — do NOT counter-Faranka.** | "هذا يشيل الايكا ولا يشيل التسعه" — kills both AKA threat AND prevents 9 stranding. | `pickFollow` pos-4 cover-with-9 branch `(not yet wired)`. | Common | 04 |
| Hokm Faranka in any position; trump still live in opp hands | Always assume worst case (opp will cut). Default to covering unless worst case is acceptable. | Risk-management meta-principle. | All Hokm `pickLead`/`pickFollow` decision sites. | Definite | 04 |

---

## Section 11 — Reads / partner-style inference (M3lm+ tier)

Rules that read `Bot._partnerStyle[seat]` ledger entries. Many require new ledger keys (proposed in last column).

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Sun, opp plays K or higher in 2nd-position when next-to-act, under your higher card | Infer: opp has **NO card lower than the played rank** in that suit (~95% confidence at K, ~90% at Q). | Saudi **Tasgheer / play-smallest** convention: under a winning higher card, dump your smallest non-saving card. Per video #05 transcript: opp's K-play implies they don't hold Q/J/9/8/7 in that suit because those are smaller than K (in plain rank A>T>K>Q>J>9>8>7) and would have been played first per the convention. T (the only card larger than K) may still be saved. | `OnPlayObserved` Bot.lua — opp K-or-higher 2nd-position losing-follow infers per-seat suit void (post-play; assumes the K play exhausts their non-T holding in that suit). **wired v0.7.2**. | Common | 05 |
| Hokm, opp follows trump with higher than minimum (e.g. T into J-led when 8/9 still live) | Infer: opp is **short on trump** (just spent a non-forced high). | "If they had more trumps they'd dump the lowest." | New ledger key proposal: `Bot._partnerStyle[seat].trumpHighDump` increment `(not yet wired)`. | Common | 05 |
| Hokm trump count: 5 visible, 3 remain, you and partner hold 0 of remaining | Pigeonhole: **all 3 remaining trumps in the same opponent's hand** — pin them in sampler. | Mathematical force. Extension of H-1 J/9-pin. | `BotMaster.PickPlay` sampler — extend pin logic beyond J/9 `(not yet wired)`. | Definite | 05 |
| Partner is Sun bidder | Assume partner has **one long suit** (4+) with concentrated high cards. | Sun bid pattern; mixed-strength hands bid Hokm or pass. | Sampler bias `(not yet wired)`. | Common | 02 |
| Partner Tahreeb'd you a low card | Read: partner holds **A or J** in some other suit + lacks strength in led suit. | Tahreeb's whole purpose is redirect to partner's strong suit. | Style ledger `Bot._partnerStyle[partner].tahreebSuspect[suit]` proposal `(not yet wired)`. | Common | 02, 09 |
| Partner played a card and you are NOT yet winning the trick | Touching-honors inference does **NOT** apply (partner forced to follow legally). | Inference assumes partner had a choice. | Gate touching-honors reads on `S.s.trick.winnerSeatSoFar == myTeamSeat` `(not yet wired)`. | Definite | 05 |
| Partner has historically violated touching-honors / Tahreeb conventions (multiple game-history events) | Downgrade rule confidence — partner may be a beginner. | "Predictions presume good convention adherence." | New ledger key: `Bot._partnerStyle[partner].conventionAdherence` (rolling counter) `(not yet wired)`. | Sometimes | 05 |
| Opp just performed `pickFollow.deceptiveOverplay` (sacrificed top) | Update ledger — they've shown the bait once; bait against same opp this round less likely to land. | "Bait detected" tracking. | New ledger key `baitDetectedBy[seat]` `(not yet wired)`. | Sometimes | 08 |

---

## Contradictions log

| WHEN (shared) | Source A says | Source B says | Resolution |
|---|---|---|---|
| Doubled-T Tahreeb-return (T + 1 side card) | Lead the T (Tahreeb default) | If partner is Sun bidder, lead the side card | Speaker (02) explicitly resolves: Sun-bidder partner = exception. Both rules logged with bidder-type predicate. |
| Triplet without T (K + low + low) Tahreeb-return | Naive "lead the K (highest)" | Speaker recommends "lead the 8 or 7" (low) | Speaker (02) hedges; final recommendation is low. Logged at "Sometimes" with K-lead noted as defensible alternative. |
| Sun off-suit losing-side dump direction (v0.5.11 misreading) | Video #05 says dump HIGHEST | Video #09 says dump LOWEST is "biggest mistake" | **RESOLVED v0.7.2**: the two videos describe DIFFERENT scenarios that v0.5.11 collapsed into one rule. Video #05 (Tasgheer/play-smallest, opp-winning context) → SMALLEST in-suit. Video #09 ("biggest mistake", partner-winning context with re-entry preservation) → SECOND-LOWEST (avoid absolute lowest). The v0.5.11 fix went from one wrong extreme (always LOWEST regardless) to another (always HIGHEST), citing both videos; the correct interpretation splits Section 4 rule 1 into 1A (Sun+opp-winning) and 1B (Sun+partner-winning). See Section 4 rules 1A/1B. |
| Hokm trump losing-side dump direction | Dump LOWEST trump | _(no conflicting source)_ | No contradiction — this is the inverse of Sun rule 1A and has its own row in Section 4. Tagged for completeness. |
| Faranka in Hokm | Default NO (#04) | Recommended in narrow exceptions (#04 list) | Same source. Clear default + 5-exception structure. |

---

## Format invariants — please preserve

1. **WHEN** must be testable from game state alone (cards in hand,
   trick history, contract type, score, position, partner's last
   play). If WHEN includes "feel" or "intuition", reduce to
   observable predicates or drop the rule.
2. **MAPS-TO** must reference a real function or write
   `(not yet wired)`. Don't invent function names. Re-grep
   line numbers periodically — see `glossary.md` re-anchoring
   recipe.
3. **CONFIDENCE** must be one of `Definite` / `Common` /
   `Sometimes`. Below `Sometimes` = drop.
4. **SOURCES** uses the slug from `_transcripts/` filenames
   (e.g., `01_tahreeb_beginners`, `04_faranka_in_hokm`).
5. When adding a new transcript, **upgrade existing rows'
   CONFIDENCE if the new source corroborates** — don't create
   duplicate rows.
