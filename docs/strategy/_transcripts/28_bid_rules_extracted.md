# 28 — Bid rules (قوانين الشراء) — extraction

**Source:** `hH8vWf6E22M_28_bid_rules.ar-orig.txt`
**URL:** https://www.youtube.com/watch?v=hH8vWf6E22M
**Speaker:** Energy Sniper (انرجي سنايبر)
**Topic:** Rules of the bid/buy phase — who has priority, who can take from whom, conversion rules. **Rules of the game**, not heuristics.

---

## 1 — Decision rules (rules-of-the-game, not heuristics)

> Convention: "before X" = earlier in bidding order. Bidding starts with **player to dealer's right** (player 1) and goes right-to-left. Dealer is **player 4** (last to bid).

| # | Rule | Type | Source line(s) |
|---|---|---|---|
| R1 | Bidding starts with player to dealer's right (player 1); dealer bids last (player 4). | Game rule | 9-12 |
| R2 | Once a bidder declares **صن (Sun)**, they CANNOT convert it to **حكم (Hokm)** afterward. (One-way: Hokm→Sun only.) | Game rule | 12-17 |
| R3 | A Sun bid CANNOT be taken by any other player as Hokm. (Sun outranks Hokm.) | Game rule | 17-20 |
| R4 | **اصول البلوت (default rule):** A Sun bid CANNOT be taken by any other player as Sun either. The Sun bid stands. | Game rule (default) | 28-30 |
| R5 | **Common house variant:** Many sessions allow a Sun bid to be taken as Sun, but **only by a player earlier in the bidding order** than the original Sun bidder. | Game rule (variant) | 30-42 |
| R6 | If the dealer (player 4) bids Sun, nobody can take it (no one is earlier in order). | Corollary of R5 | 38-42 |
| R7 | If player 1 bids Sun, nobody can take it under R5 (no one is earlier). | Corollary of R5 | 39-42 |
| R8 | Only the **dealer (player 4)** and the **player to dealer's left (player 3)** may declare **أشكال (Ashkal)**. | Game rule | 42-44 |
| R9 | A player who has already passed CANNOT come back later to declare Ashkal — bid order is preserved; passed = out. ("راحت عليك") | Game rule | 44-53 |
| R10 | An Ashkal CAN be taken as Sun by an **earlier-bidding-position player** (same earlier-only convention as Sun). It cannot be taken as Hokm. | Game rule | 53-57 |
| R11 | A Hokm bidder MAY convert their own Hokm bid to Sun (Hokm→Sun upgrade is legal; Sun→Hokm is not — see R2). | Game rule | 57-64 |
| R12 | Other players CAN take a Hokm bid and convert it to Sun (Sun outranks Hokm). | Game rule | 59-64 |
| R13 | When taking Hokm-as-Sun, default rule: only the **earlier-bidding-position player** may do so; some sessions allow any player — **session-dependent**. | Game rule | 64-69 |
| R14 | Other players CANNOT take a Hokm bid as a different Hokm (you cannot overbid Hokm with Hokm). Only Sun (R12) or Ashkal (R10) overrides Hokm. | Game rule | 70-75 |
| R15 | Round-2 bidding follows **identical rules** to round-1 bidding. | Game rule | 76-78 |
| R16 | When buying a different Hokm trump in round 2, the bidder must announce **"حكم ثاني" (Hokm-second)**, then **wait 2-3 seconds** (or until opposing team asks), THEN name the suit. | Procedural rule | 78-90 |
| R17 | Naming the trump suit immediately while picking up the card (no 2-3 sec pause) is **incorrect/illegal procedure**. | Procedural rule | 84-88 |
| R18 | When converting an existing Hokm bid to Sun, the bidder may either explicitly say **"يقلب صن" (flip-Sun)** OR remain silent. Silence at this stage = implicit Sun. | Game rule | 90-95 |
| R19 | If a Hokm bidder forgets to name the trump suit and dealing proceeds (cards become exposed/distributed), the contract **auto-converts to Sun** — the bidder loses the right to name a trump retroactively. | Game rule | 95-99 |

**Disputes / session-dependence:** Speaker repeatedly says "قوانين البلوت على حسب الجلسه اللي تلعبها" — the rules are session-dependent. When in doubt, the table votes (line 68-69).

---

## 2 — Heuristics (none)

This video is purely about rules-of-the-game; no strategy heuristics presented. Bidding *strategy* is in companion video #27.

---

## 3 — New terms

| Arabic | Translation | Notes |
|---|---|---|
| قوانين الشراء (qawānīn ash-shirāʼ) | "rules of buying/bidding" | Title term. Maps conceptually to bidding-phase legality rules in `Rules.lua`. |
| اصول البلوت (uṣūl al-balūt) | "Baloot fundamentals / canonical rules" | The strict default ruleset (vs. session house-rules). |
| الموزع (al-muwazziʕ) | "the dealer" | Standard term. Player 4 in this video's framing. |
| حكم ثاني (hokm thānī) | "Hokm second" — verbal announcement when buying Hokm in round 2 with a different trump | Procedural; not a code identifier. |
| يقلب صن (yiqlib ṣun) | "flip-to-Sun" — verbal announcement when converting Hokm→Sun | Procedural. |
| يبغاها (yabghāhā) | colloquial "wants it" | Filler, no code mapping. |
| راحت عليك (rāḥat ʕalayk) | "you missed it / it's gone past you" | Idiom for "you forfeited your chance to bid by passing earlier". |

**New-terms count: 7** (5 procedural/conceptual, 2 idiomatic).

No new card-name slang or strategy-convention terms in this video.

---

## 4 — Contradictions / discrepancies vs `saudi-rules.md` and `Rules.lua`

> **Important:** I have NOT read `Rules.lua` source in this extraction; flags below are based on `saudi-rules.md` only and on inference from text.

| # | Discrepancy | Severity | Detail |
|---|---|---|---|
| D1 | **`saudi-rules.md` "Bidding" section does NOT document the earlier-only override convention** (R5, R10, R13). | **HIGH** — this is a real legality rule that affects `Bot.PickBid`. The current `saudi-rules.md` says "First non-pass wins the contract; subsequent players can `PASS`, accept silently, or call `ASHKAL`". This is incomplete: subsequent players who are **earlier in bidding order** can also take Sun-over-Hokm or Sun-over-Sun (per house rule). | The earlier-only override is the most common house variant; saudi-rules.md should document both the strict default and the variant. |
| D2 | **`saudi-rules.md` does NOT document the Hokm→Sun upgrade rule** (R11) or the Hokm→Sun takeover by other players (R12). | **MEDIUM** | The fact that any player can take a Hokm bid and convert it to Sun is a fundamental legality rule. `Rules.lua` may not enforce this; needs verification. |
| D3 | **`saudi-rules.md` does NOT document the procedural "Hokm second" 2-3 second pause rule** (R16, R17). | **LOW** | This is a procedural/social rule rather than a hard code rule, but if the addon implements bid timing UI, it matters. |
| D4 | **`saudi-rules.md` does NOT document the auto-convert-to-Sun rule on forgotten trump-naming** (R19). | **MEDIUM** | This IS a real legality rule that should affect contract resolution in `Rules.lua` / `Net.lua`. If the bidder fails to name a Hokm suit before deal completes, contract should default to Sun. Worth checking whether Rules.lua handles this. |
| D5 | **Speaker's stated point values: Sun=26, Hokm=16** (line 23-24). | Note: this is almost certainly the **multiplier or category difference**, not raw card-point totals. The speaker is making a strength-comparison shorthand, not contradicting glossary card values (Sun=130 raw, Hokm=162 raw). | **NONE** — interpret as informal strength comparison, not a rules contradiction. Probably referring to bid-strength categories used in `Bot.PickBid`. |
| D6 | **`saudi-rules.md` Ashkal description** says Ashkal is "3rd/4th-position bid that hands a SUN to partner". R8 confirms only seats 3+4 (dealer's left + dealer) can Ashkal — consistent. R9 (cannot Ashkal after passing) is **not** documented in `saudi-rules.md` — should be added. | **LOW-MEDIUM** | Minor doc gap. |

**Recommended action items for `saudi-rules.md`:**
- Add a new subsection under "Bidding" titled **"Bid takeover and conversion rules"** documenting R3, R4, R5, R10-R14.
- Add R9 ("once passed, cannot come back to Ashkal") to the Ashkal description.
- Add R19 (auto-Sun on forgotten trump) to either bidding or contract-resolution section.
- Note the strict-default vs. house-variant distinction explicitly (R4 vs R5).

**Action items for `Rules.lua` review (NOT verified in this extraction):**
- Verify `R.IsLegalBid` (or equivalent) enforces:
  - Sun cannot be overbid as Hokm (R3)
  - Hokm CAN be overbid as Sun (R12)
  - Hokm cannot be overbid as Hokm (R14)
  - Earlier-only override toggle (configurable for house-variant) (R5, R10, R13)
- Verify contract resolution auto-converts to Sun if Hokm trump never named (R19).

---

## 5 — Non-rule observations

- The speaker explicitly frames the strict default ("اصول البلوت") differently from the common house variant: under strict rules, **a Sun bid is final** (nobody can override), but in practice most sessions ("كثير من الجلسات") allow earlier-position players to override Sun-with-Sun. This is the cleanest articulation of the dual-ruleset I've seen across videos 01-10.
- Speaker references the same "session-dependent, when in doubt vote" disclaimer that appeared in earlier videos.
- The 2-3 second pause for "Hokm second" is socially-enforced timing — not strictly a code rule, but it does map to a UI affordance: between "tap Hokm" and "select trump suit", the addon could (and per this rule, perhaps should) enforce a delay or at least surface the announce-then-select sequence rather than collapse them.
- The "silent flip to Sun" rule (R18) is interesting: it implies that if a Hokm bidder takes the card without naming a suit, the default contract is Sun. This is consistent with R19 (forgot-to-name → Sun). The codebase should treat **"Hokm bid without trump-name commitment" as a Sun bid by default**.

---

## Sources

- Single source: video 28 (`hH8vWf6E22M`).
- Companion to: video 27 (bid heuristics — separate extraction).
- Confidence: rules R1-R3, R8, R11-R12, R14-R19 are stated unambiguously and align with prior video understanding → **Definite** even from single source. Rules R4, R5, R10, R13 are stated as session-dependent → tag **Common-default** (with house-variant noted) until corroborated by another rules video.
