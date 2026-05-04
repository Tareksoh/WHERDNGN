# 20_control_game — Extracted rules

**Source:** ugE1Lsd2w-w — كيف تسيطر على اللعب (How to Control the Game) — احترف_البلوت ep.3
**URL:** https://www.youtube.com/watch?v=ugE1Lsd2w-w
**Topic:** Game control (السيطرة) — when YOU should hold the lead vs. when to GIVE the lead to your partner.

---

## 1. Central thesis

"Holding a suit/game" (مسك اللون / مسك اللعب) means controlling who wins
the trick. The speaker frames every play around two moves: **(a) hold
control yourself** when YOUR hand is the strong one, or **(b) hand
control to partner** when PARTNER's hand is the strong one. The
discriminator is which side has the high cards (إكَه, شايب, T) in the
contested suit. Concrete value: extra tricks ("اكلتين بدل اكله") and
breaking opponents' Al-Kaboot (كسر كبوت).

A second thesis the video surfaces: the choice between giving the T
(العشره) vs. the J (الولد) under partner is contract- and
hand-shape-dependent — same "give partner the lead" tactic, different
card.

---

## 2. New terms / idioms

| Arabic | Meaning | Notes |
|---|---|---|
| مسك اللون / مسك اللعب (mask al-lawn / mask al-laʕab) | "Holding the suit / holding the game" | Saudi for "controlling the suit". You hold a suit when you have its top live cards (A, T, K). The video frames every position decision around who is "holding". |
| السيطره على اللعب (as-saytarah ʕala al-laʕab) | "Control of the game" | Episode title concept. Synonymous with مسك اللعب in this speaker's usage. |
| كسر كبوت (kasr kaboot) | "Break the Al-Kaboot" | Already implied in glossary; here named explicitly as a *secondary* benefit of seizing control: even one trick captured kills opp Al-Kaboot. |
| تربي / يربي (tarbi / yirabbi) | "To raise / to lead a high card to draw out higher" | Trump-pulling verb used in Hokm context. "تربي بالعشره" = lead T to force opp's J/9. |
| دق بحكم (daqq bi-hokm) | "Knock with trump" — i.e. ruff | Already in glossary as دق; here used as "your partner needs to ruff" — coordination concept. |
| مقطوع (maqtuʕ) | "Cut off / void" | Standard term — used here to describe "send partner a suit they're void in so they can ruff". |
| مشروع (mashruʕ) / مشروع سياره / مشروع 50 / مشروع 100 | "Project / declared meld" | A revealed meld (shown to table at trick 1). Speaker uses "مشروع سياره" as slang for a Carré (= "car project"). Partner-readable signal of where your strength lies. |

(No new high-confidence terms beyond the above; everything else is reuse.)

---

## 3. Decision rules

### Section 3 — Opening leads (`pickLead` Bot.lua:953)

| WHEN | RULE | WHY | SOURCES |
|---|---|---|---|
| **Sun**, you hold the top live card(s) of suit X (إكَه + شايب, or post-A you hold T + شايب) AND you have multiple cards of X | LEAD X yourself — you are "holding" the suit; cash multiple tricks. | "تستطيع تاكل اكثر من اكله" — capturing two+ tricks in your own strong suit is the primary path to score. | 20 |
| **Sun**, your top in side suit X is just a bare T (T + 1 side card) AND you have NO independent strength elsewhere | LEAD the T (give it up to partner now); do NOT keep holding it. | Without other strength, the T won't survive — better to feed partner who can take with شايب and continue. | 20 |
| **Sun**, your top is T with **2+ side cards** (T + 2/3 others) | DO NOT lead T. Lead a low side card instead and preserve T as re-entry. | With safety cards available, T is a future winner; leading it now wastes it. | 20 |
| **Sun**, you have a declared **مشروع** (Carré / strong meld revealed at trick 1) AND the lead falls on you | Bias toward keeping control — partner reads مشروع and knows you're the strong hand; lead from your strength. | The مشروع is a public signal. Partner adjusts to "you're the boss" automatically; you should act like it. | 20 |
| **Hokm**, opponents are bidder, lead falls on you, you hold trumps + you hold the boss of a side suit (e.g. شايب of side suit) | Lead the side-suit boss to force opp's hand and prep for trump pull. | Standard Hokm: clear side aces/bosses before knocking trump. | 20 |
| **Hokm**, your team is bidder, you hold trumps INCLUDING J or A | "تربي بالحكم" — lead trump (typically the T of trump) to draw out opp's high trumps. | Bidder-side trump pull. The T forces opp's J/9 to spend, then your own J/9/A clear. | 20 |
| **Hokm**, all trumps gone, lead falls on you, you hold the boss of a side suit | Lead the side-suit boss — same play as Sun "holding" rule. | Once trump is dead the round becomes a Sun-shape; same control logic. | 20 |
| **Hokm**, lead falls on you, you are VOID in some side suit AND your team is **defender** | Lead the void suit so partner can ruff (knock with trump). | Coordination: feeding partner a ruff = transferring control to partner. | 20 |
| Lead falls on you AND partner has already established control (won prior tricks, has trumps, or has a declared مشروع) | Lead a card partner is **مقطوع** (void) in if you can identify one — partner ruffs. If unknown, lead a low side card and let partner manage. | Hand control to partner deliberately when partner is the boss. | 20 |

### Section 4 — Mid-trick play (`pickFollow` Bot.lua:1457)

| WHEN | RULE | WHY | SOURCES |
|---|---|---|---|
| **Sun**, partner led a small/mid card (e.g. 9), you are pos-3, you hold the شايب (K) of led suit, you ALSO hold a low card (7/8) of led suit | Play the LOW card (7/8) — let opp win this trick; **you keep the شايب in reserve** to hold the suit on the next round. | "تخليه يمسك" = let opp think they're holding the suit; you ambush next round. Hand control now, take it back later. | 20 |
| **Sun**, you are pos-3 with bare T mardoofa (T + 1 side card), partner played the led suit, opp played low | Play the T — sacrifice it to partner's continuation rather than save it. | Bare T won't survive a return — give it up while it can still win the trick. | 20 |
| **Sun**, you are pos-3 with T + 2+ side cards in led suit, partner already winning trick or is the strong hand | Play LOW (the side card), NOT the T. | Preserve T as re-entry; partner is fine without your top contribution here. | 20 |
| **Sun**, opp pos-2 played a low card (8), you are pos-3 holding T + شايب of led suit, you have NO other strength in hand | Play the T — capture, you must take initiative because no other card pulls weight. | Without independent strength, the T must do work now; saving it for later is unrealistic when you can't generate another lead. | 20 |
| **Sun**, you are pos-3 holding a strong suit elsewhere (e.g. J+T+9 in another suit), you hold T mardoofa here AND opp played low | Play the SIDE card (NOT the T); you can come back to this suit via your other strength. | When you have multiple strong-suit projects, don't burn T on a single trick — Faranka logic. | 20 |
| **Hokm**, your team bidder, partner led trump (T of trump), opp pos-3 forced over (must beat T) | Pos-4 must take with shorter J/9/A as needed; do not save it — trump-pull continues. | Trump-pull discipline: opp playing forces are extracted and consumed. | 20 |
| **Hokm**, opps are bidder, opp leads trump, you (pos-2) hold trump-J + trump-low | Take with the J — do NOT Faranka. (Re-statement of existing rule from #04.) | Consistent with section 10 default-NO Faranka in Hokm vs. opp bidder. | 20 |

### Section 7 — Endgame / Al-Kaboot defense

| WHEN | RULE | WHY | SOURCES |
|---|---|---|---|
| Defender team, opps mid-round on Al-Kaboot pace; you hold the boss of any unplayed side suit | LEAD that boss as soon as you get the lead — even ONE trick captured "كسر كبوت". | A single break trick eliminates the +250/+220 Al-Kaboot bonus. Bigger value than any positional finesse. | 20 |
| Defender, opp is bidder, you have control of one side suit (boss) | Holding control = first-class defensive goal #1: break Kaboot. Goal #2: force bid failure. | Speaker explicit: "تخرب كبوت ... انت كذا كسرت كبوته". | 20 |

### Section 11 — Reads / partner-style inference

| WHEN | RULE | WHY | SOURCES |
|---|---|---|---|
| Partner declared a **مشروع** (Carré/sequence) at trick 1 | Read: partner has concentrated strength in that meld's suit; treat partner as the "boss" candidate going forward. | Public meld → public read. Bot should bias "give partner control" when partner has شار meld. | 20 |
| Partner is **Sun bidder** AND lead/trick choice involves giving up a T | Lean toward keeping the T (preserve for partner's long-suit setup); inverse of normal "feed partner" instinct. | Sun bidder concentrates strength differently — already documented in glossary's video #02 contradiction. Reinforced here. | 20 |
| Partner bid **Hokm** AND has revealed (via plays) that they DO NOT hold high trump (T of trump dropped by partner) | Treat partner's bid as ASHKAL-shaped (Sun-leaning) hand; partner expects YOU to handle trump pull. | Speaker's Hokm trump-pull example: bidder's partner drives the pull when bidder has shape but not depth. | 20 |

---

## 4. Contradictions / open questions

- **Bare T (T + 1 side):** speaker contradicts the existing decision-tree row (Section 8, "Lead the T" default for doubled T) by introducing a hand-strength gate — "if you have NO other strength, lead T; if you have strength elsewhere, hold T." Existing rule should be qualified with this hand-strength predicate. **Resolution:** add hand-strength factor to the doubled-T branch — `leadT iff (independentStrength == 0)`.
- **مسك اللعب** is a meta-concept that overlays multiple existing decisions (lead choice, follow choice, Tahreeb direction, Faranka). It is not a new picker branch but a *narrative* the speaker uses to teach. Code should not add a new "control" function — instead, existing pickers should reference the concept in comments.

---

## 5. Code mapping summary

| Rule | Picker site | Status |
|---|---|---|
| "Hold suit X if you own its top live cards (Sun)" | `pickLead` Bot.lua:953 strong-suit-lead branch | Partial — strength threshold encodes part of (a). Explicit "I am the boss of suit X" predicate not yet wired. |
| "Lead the side-suit boss when defender, to break Kaboot" | `pickLead` Bot.lua:953 anti-Kaboot branch | Not yet wired. Style-ledger flag for "opps on Kaboot pace" needed. |
| "Bare T → lead it only if no other strength" | `pickLead` Bot.lua:953 doubled-T branch | Update existing branch (from video #02) with hand-strength gate. |
| "Pos-3 hold-the-شايب deception" | `pickFollow` Bot.lua:1457 | Not yet wired. Distinct from `pickFollow.deceptiveOverplay` — this is "withhold the K under opp pos-2 low" rather than "burn the J under partner-winning". |
| "Read partner's مشروع → bias toward partner-control" | `pickFollow` / `pickLead` reads | Not yet wired. Needs `Bot._partnerStyle[partner].declaredMeldSuit` after meld declaration in trick 1. |

---

## 6. Sources used

Single source: video #20 (this transcript). All rules added at `Sometimes` confidence; cross-reference required for upgrade.
