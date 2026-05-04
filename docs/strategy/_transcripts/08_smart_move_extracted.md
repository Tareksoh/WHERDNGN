# Extracted from 08_smart_move
**Video:** حركه ذكيه في البلوت (A smart move in Baloot)
**URL:** https://www.youtube.com/watch?v=NW2GTyrqGXM

## 1. Decision rules

### Section 4 — Mid-trick play / sacrifice-the-top deception (`pickFollow` Bot.lua:1457)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Sun contract; partner played T (العشره), opponent-2 played 8 (الثمانيه), you must follow with hand containing J (الشايب) and 9 (التسعه) and you'd take this trick anyway | Play **J** (top card), NOT the natural 9 — sacrifice top to deceive opponent into believing you hold no card lower than J | Opponent reasons: "if he had any card below J he'd have played it; J was his top" — concludes partner holds the rest of the suit, will continue leading the suit and let you sweep | `pickFollow` pos-3/4 Sun branch — needs new heuristic `playOversizedToBaitContinuation` *(not yet wired)* | Common | Headline "smart move". Tier-fit: M3lm+. Goal: get opponent to lead suit again so you cash 9 and break Al-Kaboot / save a hand / set up SWA |
| Sun; same scenario but you have nothing else of value, no Al-Kaboot pressure, no SWA pursuit, partner gave no Tahreeb signal | Do **NOT** sacrifice; play normal 9 and take trick | Sacrifice has cost (you give up the T-equivalent gap); only worth it when payoff (forcing suit re-lead) materially helps | `pickFollow` Sun branch — gate the bait on (Al-Kaboot risk OR SWA setup OR bidder-rescue OR partner-Tahreeb) *(not yet wired)* | Common | Bot must check context before triggering bait |
| Sun; same setup but you hold **T (العشره)** itself instead of just J/9 (i.e., you have T+lower beneath, partner played a smaller card not the T) — top-of-the-suit Saudi-master variant | Sacrifice the **T** (العشره) — even bigger deception, only a true pro plays this | T-for-T trade is a much larger sacrifice (10 raw + tempo); opponent reads it as ironclad proof you're void of smaller cards in suit, almost guaranteed to never lead suit again | `pickFollow` Sun branch — Saudi-Master-tier ISMCTS rollout should evaluate this; lower tiers should not | `BotMaster.PickPlay` ISMCTS *(not yet wired as a hand-coded heuristic; emerges from rollout if value is high enough)* | Sometimes | Tier-fit: Saudi-Master ONLY. Speaker says "غالبا ما يسويها الا واحد محترف في البلد" (only a real pro in the country plays this) |
| Hokm contract; same shape (partner played mid-suit, opp played low, your turn) — applying the bait | Use **J (الولد)** as your sacrifice/deception card, NOT T or 9; treat T/9 of trump as "AKA-equivalent" — never sacrifice them | In Hokm, J is the highest trump (rank 8, value 20); 9 (rank 7, value 14) and T (rank 5, value 10) are guaranteed winners against any covering card; sacrificing them is wasted because you'd auto-win the trick anyway when opponent leads trump | `pickFollow` Hokm branch — Belote-preservation rule already protects K/Q (H-4); add analogous "T/9 trump-sacrifice ban" *(not yet wired)* | Common | Speaker: "ما يمديك تضحي بالتسعه في الحكم … التسعه والولد اعتبرهم اكه" |
| Hokm; bidder bought trump and "ربع بالولد" (led trump-J), partner covered with Q (البنت), opp played T to you, you hold J of suit (الشايب) and 9 | Play **J (الشايب)** — bait is to convince opponent you have no lower trump so they will NOT re-lead trump (kill the re-trump) | In Hokm the bait's purpose flips: in Sun you want opp to RE-LEAD that suit; in Hokm you want opp to NOT re-lead trump because re-lead clears your trump; suppressing re-lead preserves your remaining 9 as a future winner | `pickFollow` Hokm — same heuristic as Sun but inverted gate: trigger when "stop the trump re-pull" is the goal *(not yet wired)* | Common | Section split confirmed at transcript line ~168: "نشرح لكم في الحكم" |
| Hokm; you hold 3+ trumps including **A (الاكه)** | Do **NOT** play the bait — just play normally | A guarantees one winner regardless of what opp does; bait is unnecessary; saving the J for a meaningful pull is more valuable than burning it for deception you don't need | `pickFollow` Hokm — gate bait off when `trumpCount(hand) >= 3` AND `holds(A_trump)` *(not yet wired)* | Common | Speaker explicit: "لو افترضنا عندك اكه عندك ثمانيه عندك بنت دام ورقه ثلاثه في الحكم ومنها اكه راح تاكل غصبا عنها … ما لها داعي تسوي الحركه هذه" |
| Sun; you are 2nd-to-play (only partner has played; opps haven't shown anything) — applying the bait pre-emptively | Sacrifice STILL valid but harder; better to do it when you're 4th (last) | More information when last; 2nd-position sacrifice flies blind on what opponents hold; success rate drops | `pickFollow` — position check before triggering bait *(not yet wired)* | Sometimes | Speaker line ~73: "الافضل تكون انت اخر لاعب" |
| Sun; partner cut (قطع) the led suit on a previous trick — your turn now in same suit (or analogous) | Probability of bait succeeding **increases** — partner-void info changes opp's read | When partner is known void, opp's mental model of "who has what" leaves more room for the deception to land | `pickFollow` — modulate bait threshold by `partnerKnownVoidIn(suit)` *(not yet wired)* | Sometimes | Speaker line ~75: "خويك لو قطع تزيد هنا احتماليه انك تسوي هذه الحركه" |
| Sun; your hand contains the suit-card BETWEEN two of your strong cards (e.g. you hold T and J of suit, opp leads 9, you have J in middle of T-and-something-higher) | Bait still applies — play the higher of the two strong cards; the gap-card (the middle one) becomes your guaranteed winner next round | Play biggest card in this trick; the next-highest you retain is the winner you cash on the suit re-lead | `pickFollow` Sun — pattern match "strong-gap-strong" hand shape *(not yet wired)* | Sometimes | Speaker line ~79: "الورقه بين قوتين عندك" |
| Any contract; you sacrificed top in this trick; later in the round you observe opp lead a different suit (NOT re-lead the deceived suit) | Update read: bait failed for this opponent — they likely **don't have** mid-suit, OR they read through the bait | Adjust subsequent reads accordingly; don't repeat the bait against the same opp this round | M3lm+ style ledger — add `baitDetectedBy[seat]` counter *(not yet wired)* | Sometimes | Implicit from speaker's "hard to know if it worked" framing |
| 2nd-position variant: partner led, opp-2 played small (e.g. 8); your turn; you have T and would normally be 4th-best | Play **T** to make opp think you have no smaller; opp will assume J is at partner's seat and won't re-lead suit | Same deception logic in 2nd position with one fewer card visible; weaker but still has read value | `pickFollow` pos-2 Sun branch *(not yet wired)* | Sometimes | Speaker line ~108-118 |

### Section 8 — Tahreeb interaction (`pickFollow` / `pickLead`)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Sun; you'd consider the bait, BUT partner has telegraphed Tahreeb (تهريب) — fed you a signal card | **Tahreeb takes priority** over bait; follow partner's setup | Partner's signal is information you must honor; the bait is exploratory and opportunistic | `pickFollow` priority order — Tahreeb-respond > bait *(not yet wired)* | Common | Speaker line ~159-163: "ركز على تهريب خويك … خلي الاولويه للتهريب" |

---

## 2. New terms encountered

| Arabic | Transliteration | Meaning in this video | Code mapping (tentative) |
|---|---|---|---|
| (no fixed name) | "the smart move" / حركه ذكيه | Sacrificing a high card (T in Sun, J in Hokm) to deceive opp's read of remaining suit/trump distribution; goal differs by contract | New heuristic in `pickFollow` — call it `pickFollow.deceptiveOverplay` |
| ربع | rba3 / "ruba3" | "Quartering" — leading or following with a specific card; in transcript context "ربع بالولد" = leading the J of trump from the bidder | Verb only; affects opp-model interpretation in `pickFollow` |
| سبيل / سبيت | sabeel / sabeet | "The suit (in question)" — the suit currently led; transcript uses both spellings | UI/log term only |
| السميد | as-smayd | Apparent variant of "as-spayd"/سبيت referring to the led suit; possibly the suit-of-the-trick term | Same as سبيت |
| العمله | al-3umla | Literally "the currency"; here used colloquially for "the play" / "the round" | No code mapping |
| كرى الحكم / يكر الحكم | yikr al-hokm | "Re-pulls trump" — opponent leading trump again to clear it from defenders | `pickLead` Hokm aggression metric; M3lm+ tier read |

**Note:** The video's headline move has no formal Saudi name — speaker explicitly says "ما لها مسمى معين" (it has no specific name) and at the end asks viewers to suggest one. We could provisionally name it **"التضحيه بالعشره" / "Sacrifice-the-T"** in Sun and **"التضحيه بالولد" / "Sacrifice-the-J"** in Hokm.

---

## 3. Contradictions

| WHEN (shared) | This video says | Earlier sources say | Resolution |
|---|---|---|---|
| Hokm pos-3/4, you hold T or 9 of trump | Never sacrifice T or 9 of trump as bait — they are AKA-equivalent | (No prior contradicting source in transcripts processed; aligns with H-1 J/9-pinning convention from Bot.lua) | No conflict; reinforces existing pin |
| Sun pos-3/4, partner played T | Sacrificing top can be the right play even though it loses 10 raw points this trick | Standard Belote intuition: "play smallest legal that still wins" — would say play 9 | This video defines the Saudi-Master deviation; default heuristic stays "smallest", bait branch is opt-in for higher tiers |

---

## 4. Non-rule observations

**The smart move** — Sun contract, mid-game. Trick state: partner leads (or plays earlier), playing T (العشره). Opp-2 plays low (8 / الثمانيه). You are 4th to play (or 3rd) and you hold both J (الشايب) and 9 (التسعه) of the led suit. You're going to win the trick either way.

The **obvious** play is the 9 — it's the smallest card that still beats the 8, you win the trick, and you save the J for later. Every textbook says this.

The **smart** play is the **J**. You sacrifice your top card to win a trick you'd have won anyway. The point isn't this trick — it's the *next* trick.

**Why it works:** From the opponent's seat, they reason: *"He played his J. If he had any card below the J, he'd have played that instead — he wouldn't waste his top. So J was his only card in this suit, or his only card above the 8. Either way, the 9 must be at his partner's seat."* They now believe partner has the rest of the suit, including the 9. So when they later get the lead, they'll **continue leading the suit** — expecting partner to win — and walk straight into your 9.

Why is this so valuable? Three concrete payoffs the speaker enumerates:
1. **Break Al-Kaboot pursuit** — if opps are sweeping all 8, getting them to feed you a winner kills the sweep (saves 220 raw in Sun).
2. **Rescue a failing bid** — if your team is bidder and behind, a forced suit re-lead lets you cash a winner you couldn't otherwise have surfaced.
3. **Set up SWA** — the deception buys you the right tempo to declare سوا on the back-end.

The Saudi-Master variant: instead of J, sacrifice the **T itself** when you have T-and-lower (partner played a smaller card). The deception is even more ironclad ("he played his ten — he must be void below"), but the cost is also bigger. Speaker says only true pros do this, and only when they're confident the read will land.

The flip in Hokm: same shape, but in Hokm you sacrifice the **J (الولد)**, never the T or 9 (those are "AKA-equivalent" — guaranteed winners regardless). And the *goal* inverts: in Sun you want opp to **re-lead** the suit; in Hokm you want opp to **NOT re-lead trump**, because re-lead clears your trump strength. Suppress the re-pull, preserve your remaining 9 of trump as a future winner.

When NOT to do it (Hokm): if you already hold 3+ trumps including the A. The A guarantees a winner whether opp re-leads or not, so the bait is wasted — burning your J for no information gain.

**Tier-fit:**
- **Basic / Advanced** — would NOT find this. They'd play the 9 as obvious smallest-winner. No information modeling.
- **M3lm** — could plausibly find the Sun J-sacrifice IF a partner-style-ledger entry is added that tracks "opponent doesn't re-lead suits where J was sacrificed → bait worked". The pattern is teachable. The Hokm J-sacrifice variant is also reachable.
- **Fzloky** — should reliably find both variants once the M3lm ledger entry exists; Fzloky has the extended bid-reading needed to gate the bait correctly (e.g., recognize Al-Kaboot risk).
- **Saudi-Master** — only tier that should attempt the **T-sacrifice** variant in Sun. ISMCTS rollouts will discover it when payoff is high enough; hand-coded heuristic is overkill (and risks misfiring) for non-master tiers.

**Speaker's note on naming:** The move has no canonical Saudi name. Speaker explicitly invites viewers to suggest one. Until a community name appears, suggest internal label `pickFollow.deceptiveOverplay` or `bait_via_top_sacrifice`.

**Position dependency:** Speaker says the bait works best when you're **4th to play** (last). 2nd-position is possible but riskier — fewer cards visible, opp's read has more uncertainty for the deception to land cleanly. The bot should weight bait-trigger threshold by trick position.

**Partner-void boost:** When partner has cut (قطع) the led suit on a prior trick, the bait becomes more reliable — opp's "who has what" model has one less hand to put cards in, so the deception lands harder.

---

## 5. Quality notes

- Transcript is auto-generated Arabic with several mis-transliterations (سبيل / سبيت / السميد all refer to the led suit; "العمله" appears used for "the play"). Did not affect rule extraction.
- Speaker is methodical — explicitly walks through Sun first, then "خلصنا من الصن" transition (~line 168), then Hokm. Clean two-section structure.
- Speaker quotes opponent's reasoning in first person (line 28-32, 217-220) which is unusually concrete for a Saudi commentary video — gave high confidence on the read-modeling logic.
- One spot of ambiguity (~line 130-140): speaker briefly self-inserts as the deceived opponent and discusses how to RESPOND to the bait. Extracted as the "play your power, watch for opp not re-leading suit" rule but boundaries between "I'm baiting" vs "I'm being baited" got fuzzy. Marked as Sometimes confidence.
- No video timestamps in raw transcript file — line numbers refer to transcript file lines only.
- Transcript ends at line 256 with speaker explicitly asking viewers what the move should be called — confirms the move has no settled Saudi name.
