# Saudi Baloot Glossary — Arabic terms ↔ WHEREDNGN code identifiers

This file is the canonical mapping between the Arabic terms you'll
hear in YouTube videos / commentary and the identifiers used in the
WHEREDNGN codebase. **Always consult this file before adding new
terms to strategy docs** — using the existing identifiers keeps the
docs and code in sync.

> **Line numbers below are exact pointers into the source files.**
> They drift when functions move; before using them in a code
> change, re-grep to confirm. The grep recipe is in the
> "Re-anchoring line numbers" section at the bottom.

---

## Bid types

| Arabic | Pronunciation | English in code | Constants | Picker / decision site |
|---|---|---|---|---|
| حكم | hokm | trump-named contract | `K.BID_HOKM`, `K.MSG_HOKM`, `K.SND_VOICE_HOKM`, `K.PHASE_HOKM`, `K.MULT_HOKM`=1 | `Bot.PickBid` (Bot.lua:725); contract type checked throughout `pickLead` (Bot.lua:953), `pickFollow` (Bot.lua:1457) |
| صن | sun | no-trump contract | `K.BID_SUN`, `K.MSG_SUN`, `K.SND_VOICE_SUN`, `K.PHASE_SUN`, `K.MULT_SUN`=2 | `Bot.PickBid` (Bot.lua:725); Sun-specific branches in `pickLead`/`pickFollow` |
| أشكال | ashkal | 3rd/4th-position bid that hands a SUN to the partner | `K.BID_ASHKAL`, `K.SND_VOICE_ASHKAL`, `K.BOT_ASHKAL_TH`=65 | `Bot.PickBid` Ashkal branch (Bot.lua:725+) |
| باس | pass | pass | `K.BID_PASS` | `Bot.PickBid` fallback when strength < threshold |

**Bidder vs defender teams:** The team that wins the bid is the
"bidder team"; the other two seats are the "defenders". Bidder is
identified by `S.s.contract.bidder` (seat 1-4) and team by
`R.TeamOf(seat)` returning `"A"` or `"B"`.

---

## Escalation chain (the four "rungs")

**Saudi naming differs from the code identifiers.** The code was
written with English shorthand (TRIPLE/FOUR) before the Saudi
naming convention was fully captured. **Use Saudi names in strategy
docs; use code identifiers in code.** This table is the bridge.

| Saudi name | Multiplier | Constants | Window | Picker (line) |
|---|---|---|---|---|
| بل (Bel) — "double" | ×2 | `K.MSG_BEL`, `K.MULT_BEL`=2, `K.BOT_BEL_TH`=60 | defenders' window after bid | `Bot.PickDouble` (Bot.lua:1787) |
| بل×2 (Bel x2) — "double-the-double" | ×3 | `K.MSG_TRIPLE`, `K.MULT_TRIPLE`=3, `K.BOT_TRIPLE_TH`=90, `K.PHASE_TRIPLE` | bidder team's window after Bel | `Bot.PickTriple` (Bot.lua:1908) |
| فور (Four) — English loan-word | ×4 | `K.MSG_FOUR`, `K.MULT_FOUR`=4, `K.BOT_FOUR_TH`=110, `K.PHASE_FOUR` | defenders' window after Bel x2 | `Bot.PickFour` (Bot.lua:1938) |
| قهوة (Gahwa / Coffee) | match-win | `K.MSG_GAHWA`, `K.BOT_GAHWA_TH`=135, `K.PHASE_GAHWA` | bidder team's terminal | `Bot.PickGahwa` (Bot.lua:1982) |

**Shared decision helpers used by all four pickers above:**
- `escalationStrength(seat, hand, contract)` — Bot.lua:1884
- `escalateDecision(strength, th)` — Bot.lua:1899
- `scoreUrgency(myTeam, context)` — Bot.lua:588
- `matchPointUrgency(myTeam)` — Bot.lua:619

**Important naming notes:**
- The code uses `TRIPLE` as an English shortcut. Saudi convention
  for the ×3 rung varies by speaker: **"Bel x2"** (بل×2) — the
  Bel doubled again — is one common form; **"Theri" (ثري)** is
  another (loan-word from English "three" written in Arabic).
  *Earlier docs claimed Saudi players don't say ثري — that was
  wrong; video #11 confirms ثري is in active use.* Use either
  Saudi name in docs; both are valid.
- The ×2 rung's Saudi name is **"Bel" (بل)** OR **"Dabl" (دبل)** —
  both used. دبل is the loan-word from English "double".
- The ×4 rung is the English word **"Four" (فور)** adopted into
  Saudi Arabic (loan-word). No native Arabic term replaces it.
- **Gahwa (قهوة)** literally means "Coffee". The metaphor: when
  a player declares Gahwa, the loser is "treated to coffee" — a
  light-hearted way to refer to the match-ending stake.

### Bel (×2) legality gate

> **Sun-only legality rule (per video #11):** the team currently at
> **≥100 cumulative score** is **forbidden** from calling Bel in a
> Sun contract. Only the team at <100 may Bel. This is enforced
> game-rule (not heuristic). **Hokm has no such gate** — either
> team may Bel regardless of score.
>
> Implications:
> - `Bot.PickDouble` must check `S.s.cumulative[myTeam] < 100` for
>   Sun contracts. Currently `(not yet wired)`.
> - `Rules.lua` should expose `R.CanBel(team, contract)` as the
>   authoritative predicate.

**Key rule:** the chain is strictly alternating — defender (Bel) →
bidder (Bel x2) → defender (Four) → bidder (Gahwa). Each rung must
be voluntarily declared; nothing auto-escalates. Gahwa is terminal
— a successful Gahwa wins the match outright.

---

## Special plays

| Arabic / Term | English | Constants | Picker / handler (line) |
|---|---|---|---|
| إكَهْ | AKA — partner-coordination signal in Hokm | `K.MSG_AKA`, `K.SND_VOICE_AKA` | `Bot.PickAKA` (Bot.lua:1686); state at `S.s.akaCalled`; receiver convention enforced in `pickFollow` (Bot.lua:1457+) |
| سوا | SWA — slam-with-ace, claim all remaining tricks | `K.MSG_SWA`, `K.MSG_SWA_REQ`, `K.MSG_SWA_RESP`, `K.SWA_TIMEOUT_SEC`=5 | `Bot.PickSWA` (Bot.lua:2120); `Net.HostResolveSWA`, `Net.MaybeRunBot` SWA branch (Net.lua:~3535); state at `S.s.swaRequest` |
| تكويش | **Takweesh — DUAL MEANING:** (a) Call illegal-play penalty → invokes Kasho (pre-bid) or Qaid (post-bid). (b) Bid-override sense: "compete with partner's bid by buying yourself" (per video #29). | `K.MSG_TAKWEESH`, `K.MSG_TAKWEESH_OUT` cover meaning (a). Meaning (b) is bid-decision logic — `Bot.PickBid` should NOT bid against partner's strong contract unless specific exceptions hold (per video #29). | Net.lua handlers; player-initiated only for (a). |
| كبوت | Al-Kaboot — bidder team sweeps all 8 tricks | `K.AL_KABOOT_HOKM`=250, `K.AL_KABOOT_SUN`=220, `K.LAST_TRICK_BONUS`=10 | Pursuit logic in `pickLead` trick-8 branch (Bot.lua:953). **Per video #15:** pursuit should trigger as early as **trick 3** when hand-shape is Kaboot-feasible, not only at trick 8. Currently only trick-8 is wired. |
| الكبوت المقلوب | **Reverse Al-Kaboot** — defenders sweep all 8 against bidder | **Proposed `K.AL_KABOOT_REVERSE = 88`** (single-source from video #16, confirm before wiring). Qualifies only when bidder was trick-1 leader. | New `R.ScoreRound` branch needed; not currently scored. |
| كاشو | Kasho — light pre-bid penalty | Procedural error during deal → redeal, no points. NOT the same as Qaid. | Currently not modeled in code; player-only edge case. |
| القيد | Qaid — heavy post-bid penalty | Illegal play during round → 26 raw (Sun) / 16 raw (Hokm) + melds to non-offending team, ×multiplier on Bel/Bel-x2. | `K.MSG_TAKWEESH_OUT` carries the call result; score side `(not yet wired)`. |
| بلوت | "Baloot!" fanfare on a successful bid making | `K.SND_BALOOT` | Sound cue, no decision logic |

**SWA rules (Saudi-specific):**
- ≤3 cards remaining → instant claim, no permission needed
- 4+ cards remaining → caller asks opponents for permission
- 5-second auto-approve window if opponents don't respond
- Opponents can press Takweesh (illegal-play counter) or Accept/Deny
- Bots auto-accept opponent SWA requests (no meta-game read)

---

## Melds (Saudi rules — Hokm contracts only, except where noted)

| Arabic / Term | Score | Notes | Identifier |
|---|---|---|---|
| تتابع 3 / Sequence-3 | 20 | 3 consecutive cards same suit | `K.MELD_SEQ3` |
| تتابع 4 / Sequence-4 | 50 | 4 consecutive | `K.MELD_SEQ4` |
| تتابع 5 / Sequence-5 | 100 | 5+ consecutive | `K.MELD_SEQ5` |
| كاره / Carré (others) | 100 | T, K, Q, J of any suit (4-of-a-kind) | `K.MELD_CARRE_OTHER` |
| الأربع مئة / Four Hundred | 200 | Four Aces — Sun contracts only | `K.MELD_CARRE_A_SUN` |
| بيلوت / Belote | 20 | K+Q of trump in same hand, Hokm only | `K.MELD_BELOTE`, `holdsBeloteThusFar` |

**9s do not form Carré.** This is the Saudi rule (`K.CARRE_RANKS` excludes "9").

---

## Card values (memorize these — used everywhere)

### Hokm trump suit (J, 9, A, T, K, Q, 8, 7 in rank order)

| Rank | Saudi name | Trump value | Trump rank order |
|---|---|---|---|
| J | Jack | 20 | 8 (highest) |
| 9 | Nine | 14 | 7 |
| A | Ace | 11 | 6 |
| T | Ten | 10 | 5 |
| K | King | 4 | 4 |
| Q | Queen | 3 | 3 |
| 8 | Eight | 0 | 2 |
| 7 | Seven | 0 | 1 (lowest) |

Sum = 62 raw points per trump suit. Constants: `K.POINTS_TRUMP_HOKM`,
`K.RANK_TRUMP_HOKM`.

### Hokm off-trump and all suits in Sun (A=11, T=10, K=4, Q=3, J=2, 9/8/7=0)

Sum = 30 raw points per non-trump suit. Constants: `K.POINTS_PLAIN`,
`K.RANK_PLAIN`. Sun multiplier ×2 — that's why Sun games tend to
score higher per round.

---

## Game state / hand totals

| Term | Value | Identifier |
|---|---|---|
| HAND_TOTAL_HOKM | 162 | 152 cards + 10 last trick |
| HAND_TOTAL_SUN | 130 | 120 (30/suit × 4) + 10 last trick (pre ×2 multiplier) |
| LAST_TRICK_BONUS | 10 | bonus to whoever wins trick 8 |
| Match target | 152 raw | `S.s.target` |

---

## Bot tier names + thresholds

The codebase has 5 bot tiers, escalating in strength:

| Tier | Identifier | Description |
|---|---|---|
| Basic | `WHEREDNGNDB.advancedBots == false` (default) | Random-legal play |
| Advanced | `WHEREDNGNDB.advancedBots = true` | Heuristic picker (memory + boss tracking) |
| M3lm | `WHEREDNGNDB.m3lmBots = true` | Heuristic + style-ledger inference (partner reads) |
| Fzloky | `WHEREDNGNDB.fzlokyBots = true` | M3lm + extended bid reading |
| Saudi Master | `WHEREDNGNDB.saudiMasterBots = true` | ISMCTS via `BotMaster.PickPlay` |

**Note:** "M3lm" (معلم) ≈ "teacher / master craftsman". "Fzloky"
(فضولكي ≈ فضولي?) — meaning unclear; could be "the curious one"
or addon-specific. Worth confirming with native speakers.

---

## Style ledger keys (`Bot._partnerStyle[seat]`)

These are per-seat counters that M3lm+ tiers use to read opponent
playstyle. **Most are wired; some are dead infrastructure** (see
v0.5_FINAL_REPORT.md).

| Key | Wired? | Description |
|---|---|---|
| `triples` | YES | times this seat has called Bel x2 this game (legacy code name; semantically tracks ×3 calls) |
| `gahwaFailed` | YES | times this seat called Gahwa and failed |
| `sunFail` | YES | times this seat bid Sun and failed |
| `leadCount[suit]` | DEAD WRITE | suit-lead frequency (written by `OnPlayObserved`, read nowhere) |
| `aceLate` | DEAD READ | only read by sampler `pickProb`, not by play picker |

---

## Conventions and style hints (likely to expand)

- **AKA receiver:** when partner announces AKA on a non-trump suit
  and is currently winning the trick, the bot suppresses the forced
  trump-ruff (H-5 from v0.5.1). Reference: `Bot.lua` `pickFollow`.
- **Belote preservation:** in tricks 1-3, bot avoids shedding K or Q
  of trump when both are still in hand (H-4 from v0.5.1).
- **J/9 of trump pinning:** ISMCTS sampler hard-pins J/9 of trump to
  the bidder when sampling unknown hands (H-1 from v0.5.0).
- **Ashkal trigger:** Hokm-bidder's partner converts to Sun when
  they themselves have a Sun-strong hand and the Hokm bidder appears
  weak. Threshold `K.BOT_ASHKAL_TH = 65`.

---

## Strategy terms (from videos)

Defined from transcript sources 01-10 (Saudi YouTube tutorials,
2024-2025). Each entry cites the videos it draws from. **These are
the central Saudi-Baloot conventions** — not optional flavor; a
bot that doesn't implement them isn't playing Saudi Baloot.

### Tahreeb (تهريب) — partner-supply discard signal

| Aspect | Definition |
|---|---|
| **Mechanic** | A discard played while **partner is winning** the current trick. Every such discard encodes a directional preference. |
| **Direction encoding** | **Top-down** within a suit (high then lower next opportunity) = "I do NOT want this suit". **Bottom-up** within a suit (low then higher next) = "I DO want this suit, but I don't hold its Ace". |
| **Bargiya (برقية, "telegram")** | Special form: discarding the **Ace** of a suit on partner's winning trick. **Two semantic flavors** (per video #14): (a) **Come-to-me invite** — partner should lead this suit so you can SWA on the back-end; (b) **Defensive shed** (شرد بالاكة) — denying the opp a chance to capture the Ace later. Distinguish by hand shape: Bargiya-as-invite when محشور بلون واحد (cornered in one suit, 5+ cards there); Bargiya-as-shed otherwise. |
| **Bargiya receiver phase-split** | Endgame (≤4 cards in your hand): lead the Bargiya'd suit immediately. Opening (≥5 cards): burn 1-2 of your own tricks first to set up the eventual lead-back. (Per video #14.) |
| **Two-trick confirmation** | A second Tahreeb in the **same suit** (continuing the direction) raises reliability from ~70% to ~90%. Single Tahreeb is a hint; double is near-certain. |
| **Receiver prior** | One Tahreeb event → 70% partner wants opposite-color high suit; 25% same-color other-shape; 5% the suit you started in. Wait for second Tahreeb to disambiguate. |
| **Receiver discipline** | When following a Tahreeb-led trick, **never play your absolute lowest card** ("biggest mistake in Baloot" — video #9). Play second-lowest or middle, preserving your top as a re-entry. Eat with second-best when possible to enable a lead-back. |
| **Sources** | 01, 02, 03, 09, 10 |
| **Code mapping** | New `pickFollow` discard branch (Bot.lua:1457) when `partner-currently-winning-trick` is detected. Sender-side: encode direction in style ledger; Receiver-side: read style ledger in `pickLead`. **Not yet wired** — needs a `tahreebSignal` table in `Bot._partnerStyle[partnerSeat]`. |

### Tanfeer (تنفير) — discard-signal taxonomy

> ⚠️ **Caption-error warning:** YouTube auto-captions for Saudi
> Arabic frequently render تنفير (*tanfeer*, "repulsion") as
> **تنفيذ** (*tanfeedh*, "execution"). The two words sound nearly
> identical to ASR. The correct term is **تنفير** throughout. Any
> transcript that uses تنفيذ in a strategy context is the homophone
> error — interpret as تنفير.

> **Important taxonomic clarification (video #12 vs video #03):**
> Video #12 establishes that **Tanfeer is the parent class** —
> *any* throwaway discard while not-leading is a Tanfeer. **Tahreeb
> is the intent-bearing subset** — a Tanfeer that deliberately
> encodes a directional preference. So:
> - "Every Tahreeb is a Tanfeer, but not every Tanfeer is a
>   Tahreeb."
> - Video #03 framed Tanfeer as a niche corner-case for
>   *interpretation priors* (lean-Tahreeb when reading partner) —
>   that's a *reading* heuristic, not the mechanic.
> - Video #12 frames Tanfeer as the umbrella *taxonomy*.
>
> Both views reconcile: the *interpretation* default is Tahreeb;
> the *encoding mechanic* is Tanfeer with Tahreeb as one disciplined
> form.

| Aspect | Definition |
|---|---|
| **Mechanic (parent)** | Any throw-away discard played when you are not the trick leader and the trick will be decided by someone else's card. The discard *is* a signal whether you intended it or not. |
| **Tahreeb (subset)** | A Tanfeer where partner is winning and you deliberately encode directional preference (top-down = refuse, bottom-up = want, Bargiya = "lead this"). |
| **Tanfeer-when-opp-wins** | Inverse-meaning Tanfeer: when opponent has won, the discarded suit IS what you want returned (positive signal). |
| **Asymmetry rule** | When trick-winner is uncertain, **default to Tahreeb interpretation** — Tahreeb is the dominant convention (video #03 explicit). |
| **Sources** | 03, 12, 19 |
| **Code mapping** | Same `pickFollow` discard branch (Bot.lua:1457) as Tahreeb. Read-side: classify by trick-winner identity (partner / opp / uncertain). **Not yet wired**. |

### Takbeer / Tasgheer (التكبير / التصغير) — the magnify/miniaturize couple

| Aspect | Definition |
|---|---|
| **Takbeer (التكبير)** | "Magnification" — playing your HIGHEST card when the trick is going to a teammate (donate ابناء). |
| **Tasgheer (التصغير)** | "Miniaturization" — playing your LOWEST card when the trick is going to an opponent (deny ابناء). |
| **Sun rule** | Both rules apply uniformly: Takbeer when partner wins; Tasgheer when opp wins. No rank-order quirk. |
| **Hokm rule** | Same as Sun for off-trump. **Trump-suit Takbeer has a quirk** — only mandatory for *rank-consecutive* top trumps. With non-consecutive top trumps (e.g., 9 + 8 of trump, ranks 7 + 2), invert: lead the side first, preserve the 9 as re-entry. (Per video #22.) |
| **Sources** | 21, 22, 23 |
| **Code mapping** | `pickFollow` Bot.lua:1457 — needs a contract-aware Takbeer/Tasgheer branch reading the trick-winner-so-far. Hokm trump rank-consecutive check is the special case. **Not yet wired**. |

### Faranka (فرنكة) — withhold-the-top deception

| Aspect | Definition |
|---|---|
| **Mechanic** | Deliberately playing a **smaller** high card when you legally could play your TOP card of the suit, in order to keep the top in reserve for a later trick. Goal: capture two tricks instead of one, preserve partner's Al-Kaboot, or "fish" the opponent's 10. |
| **In Sun (default = YES)** | Five factors increase Faranka EV: (1) you hold J+A of the suit; (2) partner is taking this trick; (3) Al-Kaboot pursuit live; (4) Faranka-success flips round-loss to opponents; (5) LHO is bidder leading fresh hand. Anti-triggers: no J in hand, ≥3 cards of suit (10 drops naturally), you hold the top TWO unplayed (always capture). |
| **In Hokm (default = NO)** | Trump is short — withholding is high-variance. Allowed only in narrow cases: (1) Al-Kaboot pursuit; (2) only 2 trumps total in hand; (3) J of trump already dead (your 9 is now top live trump); (4) you are bidder AND opponent trump exhausted; (5) partner has shown extra trump. |
| **Saudi Master variant** | Sacrifice the **10** instead of just the second-highest — applies when you hold T+lower. Speaker calls this "only true pros" (Saudi Master tier). |
| **Sources** | 04 (Hokm), 06 (Sun, conceptual) |
| **Code mapping** | New `pickFollow` Faranka branch (Bot.lua:1457). Five-factor scoring function for Sun; restrictive default + exception list for Hokm. **Not yet wired**. |

### The "smart move" — top-card sacrifice for deception

This move has **no settled Saudi name**. The video author
explicitly invites viewers to suggest one. Until a community name
appears, internal label is `pickFollow.deceptiveOverplay`.

| Aspect | Definition |
|---|---|
| **Mechanic (Sun)** | Play your **J** of the led suit when the obvious play is the 9 (you'd win the trick either way). Opp reasons "he played his top, must be void below" → continues leading the suit → walks into your 9. |
| **Mechanic (Hokm)** | Same but goal **inverts** — you sacrifice J of trump to convince opp NOT to re-lead trump (preserving your remaining 9 as a future winner). |
| **Saudi Master variant** | In Sun, sacrifice the **T** itself (not just J). Even more ironclad deception, larger cost; speaker says only "a real pro in the country" plays this. |
| **Anti-triggers** | Hokm with 3+ trumps including A (bait wasted, A guarantees winner); partner has Tahreeb'd you (Tahreeb takes priority). |
| **Sources** | 08 |
| **Code mapping** | `pickFollow.deceptiveOverplay` — new heuristic gated on contract type, position, hand shape, and active context (Al-Kaboot risk / SWA pursuit / bidder-rescue / partner-Tahreeb). M3lm+ for Sun J-variant; Saudi Master for Sun T-variant. **Not yet wired**. |

> **Process for new terms:** when a transcript introduces a term
> not in this table, **add the row first**, with "Likely meaning"
> as your best guess from context. Only after multiple
> corroborating sources should the "Code mapping" become a real
> code change.

---

## Card-name slang (Saudi colloquial — varies by speaker)

Saudi commentators use family/age metaphors for face cards. **There
is significant inter-speaker variation** — flagged below.

| Arabic | Card | Notes |
|---|---|---|
| إكَه / الإكه (ikah) | **Ace (A)** of any suit | Distinct from إكَهْ (AKA, the partner-call signal) — same root, different phoneme. Caption auto-spelling often loses the distinction. |
| ريكا / الريكا (reeka) | **Ace** of trump (specifically) | Used in video #4; not universal. |
| كه / كاله / العشره (kah / kaala / al-ʕashara) | **Ten (T)** | Multiple spellings; same card. |
| شايب (shayib, "old man") | **King (K)** | **Authoritative.** Some auto-extraction agents misidentified this as Q based on context guesses — those were wrong. شايب = King. |
| بنت (bint, "girl") | **Queen (Q)** | Pairs with شايب=K and ولد=J as the family-trio. |
| ولد (walad, "boy") | **Jack (J)** | Pairs with شايب=K. |
| الثمانيه (ath-thamaaniyah) | **Eight (8)** | Stable. |
| التسعه (at-tisʕah) | **Nine (9)** | Stable. |

### Hand-shape terms

| Arabic | Meaning | Source |
|---|---|---|
| مردوفة (mardoofa) | "Doubled" — exactly 2 cards in a suit, especially a top + 1 cover (e.g., A+T, K+Q, J+9). Critical Saudi term. | 02, 25, 26, 31 |
| مثلوث (mathlooth) | "Tripled" — 3 cards in a suit | 02, 17 |
| إكة مردوفة (ikkah mardoofa) | A+T mardoofa: Ace + Ten of same suit | 25 |
| **الصن المغطى (Sun-Mughataa)** | "Covered Sun" — Sun bid where bidder holds A+T mardoofa as anchor | 25 |
| **الحكم المغطى (Hokm-Mughataa)** | "Covered Hokm" — Hokm bid with explicit J+مردوفة+A safety pattern | 26 |
| سراء ملكي (saraa malaki) | "Royal" hand pattern — K+Q meld + supporting trump | 26 |

> **Family-trio convention:** Saudi card-naming is family-themed —
> شايب (old man) = King, بنت (girl) = Queen, ولد (boy) = Jack. The
> mapping is stable across all speakers we've seen; earlier "inter-
> speaker variation" notes were artifacts of agent mis-extraction,
> not real disagreement among Saudi commentators.

### Suit-name slang

| Arabic | Suit | Variation |
|---|---|---|
| السبيت / السبيد / السبيل (sbeet / sbeed / sbeel) | **Spades (♠)** | Multiple spellings, same suit. |
| الهاس / الهاوس (haas / haus) | **Clubs (♣)** — best guess | Inconsistent; may be Hearts in some videos. Cross-reference example structure. |
| الشريحه / شرير (shareeha / shareer) | **Hearts (♥)** | Multiple spellings. |
| الدايمه / دايمن (dayma / dayman) | **Diamonds (♦)** | Stable. |

> **Rule for transcripts:** when a card-name or suit-name conflict
> arises in extraction, the **example structure** (rank order,
> trick context, contract type) overrides the slang. The slang is
> a hint, not authoritative.

---

## Other strategy idioms encountered

| Arabic | Meaning | Source video(s) | Notes |
|---|---|---|---|
| حلَّة / أَكلة (hilla / akla) | "trick / round-of-cards" | 01, 04, 09 | Synonyms for the existing code term `trick`. |
| الأخيري (al-akheeri) | "the last one" — i.e. the +10 last-trick bonus | 01 | Maps to existing `K.LAST_TRICK_BONUS`=10. |
| عكس اللون / عكس الشكل (ʕaks al-lawn / ʕaks ash-shakl) | "opposite color / opposite suit" | 01, 03 | Partner-return convention after a Tahreeb signal: lead the suit they were *protecting* (opposite of the one they Tahreeb'd). |
| فئة ضعيفة / متوسطة / قوية (fi'ah daʕeefah / mutawasitah / qawiyyah) | "weak / medium / strong category" | 03 | Tripartite classification of suit-holding strength; used for choosing which suit to Tahreeb. |
| دق / يدق (daqq / yidiqq) | "to knock / to cut" | 04 | "Cut" = trump a side suit. Trump-ruff in code terms. |
| ربع / يربع (rabbaʕ / yirabbaʕ) | "to lead from a specific position" | 04, 08 | Verb form for "led the [card]"; e.g., "ربع بالولد" = "led the J (of trump)". |
| كرى الحكم / يكر الحكم (yikr al-hokm) | "re-pulling trump" | 08 | Opponent leading trump again to clear it from defenders. M3lm+ aggression metric. |
| الصمت (as-samt) | "the silence" | 04 | Sun-style withholding (Faranka) viewed metaphorically. |
| فن (fann) | "art / craft" | 09 | Used to describe high-card-return technique when you can't eat partner's Tahreeb. |
| توقع الحلَّة (tawaqquʕ al-hilah) | "predicting the trick (outcome)" | 03 | Video author references a separate video; relates to `BotMaster.PickPlay` ISMCTS rollouts. |
| باستثناء (bi-istithnaaʔ) | "with the exception of" | 03 | Tahreeb's structural rule: "I don't want any suit I Tahreeb, *except* the one I'm signaling." |
| تجاهل (tajaahul) | "ignoring" | 06 | Plain-English gloss for what Faranka mechanically is. |
| نسبة الفرنكة (nisbat al-faranka) | "Faranka percentage" | 06 | Heuristic for how strongly the situation favors Faranka, summed from the 5 factors. |

---

## Open questions / terms still unconfirmed

- **B3do (بدو?)** — appears as `ALLY B3DO` UI banner; Saudi-specific
  bid-confirming term. Need to define.
- **Qaid (قيد)** — penalty applied on caught illegal play
  (Takweesh outcome). Mentioned in code comments; not a top-level
  identifier.
- **Munadara (مناداة?)** — calling/announcing. Commentary term.
- **Tafseel (تفصيل?)** — "detail"; Saudi commentators often say
  "TFSEEL" when explaining a difficult discard. Not a code term.

When you encounter a new term in a video, add it here BEFORE writing
strategy notes that use it.

---

## Re-anchoring line numbers

Bot.lua and friends are under active development. The line numbers
above are accurate as of **v0.5.15** (commit will be tagged on
ship). They drifted +165 to +461 lines across v0.5.8 → v0.5.14;
treat them as approximate hints, not exact pointers. **Always
re-grep before relying on them in a code change.**

```bash
# Pickers in Bot.lua:
grep -n '^function Bot\.\(PickBid\|PickAshkal\|PickDouble\|PickTriple\|PickFour\|PickGahwa\|PickAKA\|PickSWA\|PickMelds\|PickPlay\|OnPlayObserved\|OnEscalation\|OnRoundEnd\|ResetStyle\|ResetMemory\|IsAdvanced\|IsM3lm\|IsFzloky\|IsSaudiMaster\)' Bot.lua

# Local helpers in Bot.lua:
grep -n '^local function \(pickLead\|pickFollow\|escalateDecision\|escalationStrength\|scoreUrgency\|matchPointUrgency\|highestByFaceValue\|holdsBeloteThusFar\)' Bot.lua

# BotMaster entry points:
grep -n '^function (BM|BotMaster)\.' BotMaster.lua
```

If you update the line numbers in this file, also update any
reference in `decision-trees.md` and `CLAUDE.md`.

### Current snapshot (v0.5.15)

For a quick reference without re-grepping (verify with grep before
acting on these):

| Symbol | Line |
|---|---|
| `Bot.PickBid` | 890 |
| `Bot.PickAKA` | 2302 |
| `Bot.PickPlay` | 2344 |
| `Bot.PickMelds` | 2380 |
| `Bot.PickDouble` | 2403 |
| `Bot.PickTriple` | 2534 |
| `Bot.PickFour` | 2564 |
| `Bot.PickGahwa` | 2608 |
| `Bot.PickPreempt` | 2630 |
| `Bot.PickKawesh` | 2681 |
| `Bot.PickTakweesh` | 2708 |
| `Bot.PickSWA` | 2746 |
| `pickLead` | 1289 |
| `pickFollow` | 1882 |
| `escalationStrength` | 2510 |
| `escalateDecision` | 2525 |
| `scoreUrgency` | 753 |
| `matchPointUrgency` | 784 |
| `Bot.OnPlayObserved` | 292 |
