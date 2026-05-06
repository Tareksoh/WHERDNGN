# Wave 4 C3 — ISMCTS Sampling Audit Findings
## Scope: BotMaster.lua — sampleConsistentDeal, getStrongCards, buildUnseen, rolloutValue

Reviewer: swarm agent C3, wave 4
Codebase: v0.4.4
Source file: C:/CLAUDE/WHEREDNGN/BotMaster.lua

---

## A-64 — pinCard: bid card pinned to bidder

**VERDICT: INFO (benign redundancy)**

**File:line:** `BotMaster.lua:137-146` (pin detection), `BotMaster.lua:205` (pin placement)

**Evidence:**

`S.HostDealRest` (State.lua:1323) calls `table.insert(s.hostHands[bidder], bidCard)` unconditionally when a bidder exists. By the time `PHASE_PLAY` begins — the only phase where BM.PickPlay fires — the bid card is already inside `hostHands[bidder]`. It therefore cannot appear in `buildUnseen`'s output, because `buildUnseen` walks `S.s.hostHands[seat]` for the calling bot's seat (line 68–70) and marks them seen, but — critically — it does NOT iterate `hostHands` for other seats, only played cards.

The question is whether `S.s.bidCard` as a string remains set and, if the calling bot is not the bidder, whether `S.s.bidCard` is present in `unseen`. Since `buildUnseen` only marks the calling bot's own hand as seen (lines 68–70) and played tricks as seen (lines 72–82), an unplayed bid card that belongs to the bidder's hand IS included in `unseen` — the bidder's hand cards are not subtracted. The pin at line 205 thus places it correctly into the bidder's sampled hand.

There is no duplicate assignment. In Phase 1 biased pick (lines 216–231) the pool is built from `unseen` minus `pinCard` and minus `meldPins` (line 184). The pin is pre-placed before Phase 1 runs (line 205). Phase 2 fill (lines 234–246) uses the reduced pool, so the pinCard can never be placed a second time.

**Recommendation:** No defect. Add a brief comment at line 205 noting the pin prevents duplicate placement; the logic is non-obvious.

---

## A-65 — sampleConsistentDeal fallback: uniform random ignoring voids

**VERDICT: WARNING**

**File:line:** `BotMaster.lua:251-273`

**Evidence:**

When 15 attempts fail, the fallback (lines 251–273) builds a fresh pool from `unseen` minus `pinCard` only. It does NOT exclude `meldPins` cards from general distribution. This means:

1. Declared-meld cards (e.g., a Hearts Tierce 7-8-9) can be scattered across all opponent seats instead of being locked to their declarer. This directly corrupts rollout hands: the rollout will evaluate worlds where the meld-declarer does not hold their own declared cards.

2. All void constraints are silently dropped. A seat inferred to be void in Spades can receive Spades freely.

3. The `pinCard` (bid card) is handled for the fallback, but `meldPins` is not (contrast with the 15-attempt loop at line 192 which excludes both).

**Severity reasoning:** A single corrupted world where, for example, a Tierce-of-Aces is misplaced can swing the rollout diff by the full MELD_CARRE_OTHER value (100 raw × multiplier) across every evaluation in that world. With BASE_NUM_WORLDS=30, one bad world is ~3.3% of the score but the meld-pinning defect is systematic (it fires on every fallback trigger). The fallback is most likely to trigger at late game when voids are highly constraining — ironically when meld cards are also most likely to still be in hand.

**Recommendation (report-only):** In the fallback, add `meldPins` exclusion to the pool-building loop (mirror the loop at line 184). Also carry void constraints through by attempting a single void-respecting pass before fully dropping constraints.

---

## A-67 — Partner signal suit biasing: desire[pSignalSuit] = 1

**VERDICT: WARNING**

**File:line:** `BotMaster.lua:214`, `BotMaster.lua:219`

**Evidence:**

`desire[pSignalSuit] = 1` sets a SUIT key (e.g., `desire["H"] = 1`). The weight lookup at line 219 is:

```
desire[c] or (desire[C.Suit(c)] and 20) or 0
```

`desire[c]` is a card key like `"AH"` — it returns nil for suit keys. So the `desire[c]` branch never fires for the partner signal; the path always falls through to `desire[C.Suit(c)] and 20`, returning 20 for any card of the signaled suit.

Two issues compound here:

**Issue 1 — Missing guard for non-Hokm contracts.** `pSignalSuit` is populated from `pMem.firstDiscard.suit`, which is the suit of the partner's first off-suit discard. In Sun contracts there is no trump, and off-suit discards carry different meaning. The sampler unconditionally applies the suit-preference signal in all contract types.

**Issue 2 — 70% weight for the entire signaled suit.** The signal is "partner preferred suit X," but the sampler deals ANY card of suit X to the partner's hand with 70% probability. In practice this means the partner's sampled hand is heavily skewed toward the signaled suit regardless of how many cards of that suit remain. For example, if 6 Hearts are in `unseen` and partner signaled Hearts, the sampler will try to put ~0.7 × 6 = 4.2 Hearts into the partner's 8-card hand, giving them a wildly heart-loaded distribution relative to the true population.

A more correct approach would be to use a per-card weight based on `strong` style (numerical priority), rather than a flat 20 for the entire suit.

**Recommendation (report-only):** Guard the pSignalSuit assignment behind a Hokm contract check. Reduce the flat suit-weight (20) to a softer per-card nudge (e.g., 5) to avoid over-concentration, or switch to the same numerical priority table style used for bidder strong cards.

---

## A-68 — rolloutValue: initialHands includes already-played cards

**VERDICT: INFO (intentional, but worth documenting)**

**File:line:** `BotMaster.lua:293-308`

**Evidence:**

`initialHands[s]` is constructed by combining the sampled remaining cards (`world[s]`) with all previously played cards from completed tricks AND the current in-progress trick (lines 293–308). This is intentional — `R.DetectMelds` (Rules.lua:194) requires the complete starting hand to detect sequences and carrés. A seat that played three cards of a 4-card sequence early in the hand would not register the meld if only their current remaining cards were used.

The correctness of this approach hinges on one rule: melds are declared in trick 1 only (Rules.lua:999, State.lua:999-1000). By PHASE_PLAY trick 1 has already closed, so the meld-declaration window is past. Running `R.DetectMelds` mid-rollout against a full reconstructed hand does not imply "melds are being declared now" — it is a retroactive reconstruction of what was declared at trick 1. The rollout's `meldsByTeam` (line 465–473) feeds `R.ScoreRound`, which uses it for scoring, not re-declaration.

One subtle correctness risk: `initialHands[s]` for the sampled world is a reconstruction, not ground truth. For non-self seats the sampled remaining cards in `world[s]` may differ from their actual hands, and thus the reconstructed `initialHands[s]` differs from the true starting hands. `DetectMelds` may produce phantom melds (sequences that happened to exist in the sample but not in reality) or miss real melds (sequences not present in this sample). This is an unavoidable consequence of determinization and is expected to average out across worlds.

**Recommendation:** No defect. Add an inline comment at lines 293–308 explaining why played cards are added back (meld reconstruction requires full starting hand), to prevent a future reviewer from treating this as a bug.

---

## A-69 — rolloutValue: heuristicPick lead branch defaults to "highest non-trump, else lowest"

**VERDICT: WARNING**

**File:line:** `BotMaster.lua:425-436`

**Evidence:**

The lead heuristic (lines 425–436) is:

1. If bidder-team in Hokm: lead the highest-ranked card from the full legal set (`highestRank(legal)`), then check if it is trump. If it is trump, return it; otherwise fall through.
2. Otherwise: lead the lowest non-trump. If none, lead the lowest overall.

**Bug at line 428:** The bidder-team branch calls `highestRank(legal)` over all legal cards, not just trumps. If the highest-ranked card overall is a high non-trump Ace (e.g., AS), `C.IsTrump` returns false and the branch falls through to "lead lowest non-trump." The bidder-team lead collapses to the same logic as the defender lead. The intended behaviour was clearly to lead the highest trump when holding trump. The correct implementation would call `highestRank` over `{ c in legal : C.IsTrump(c, contract) }` and fall through if that set is empty.

**Gaps identified:**

- AKA suit signals: the rollout heuristic never checks `Bot._memory[s].akaSent` to avoid leading into a partner's announced boss suit. Rollouts will over-estimate the value of leading a suit where the partner holds the boss.
- Void detection: the heuristic never checks inferred voids. It may lead a suit where an opponent is void, effectively donating a ruff opportunity. The real `Bot.pickLead` cross-references void memory.
- Singleton leads: leading a singleton to create a ruff is a standard advanced strategy. The rollout heuristic has no singleton detection.
- Fzloky suit preferences: the `fzlokyPrefSuit` / `fzlokyAvoidSuit` logic in Bot.lua pickLead (Bot.lua:747–754) is absent from the rollout heuristic.

**Quantified gap estimate:** The bidder-team trump-lead bug (point 1 above) is the most impactful. In Hokm the bidder team's optimal early strategy is nearly always to draw trump; failing to do so in rollouts means the sampler systematically over-values cards that succeed when trump is drawn early vs. cards that succeed when trump is not drawn. This biases the score comparison and can invert the card ranking for early-round decisions, particularly for the first two tricks of a Hokm hand.

**Recommendation (report-only):** Fix the bidder-team lead branch to select from trump-only candidates. Defer AKA/void/singleton/Fzloky gaps as a known simplification.

---

## Summary Table

| ID  | Angle                                | Severity | File:Line              |
|-----|--------------------------------------|----------|------------------------|
| A-64 | pinCard: bid card pinned to bidder  | INFO     | BotMaster.lua:137-146  |
| A-65 | Fallback deal ignores meldPins/voids| WARNING  | BotMaster.lua:251-273  |
| A-67 | Partner signal suit weight = flat 20| WARNING  | BotMaster.lua:214,219  |
| A-68 | initialHands includes played cards  | INFO     | BotMaster.lua:293-308  |
| A-69 | Lead heuristic: trump-lead bug      | WARNING  | BotMaster.lua:427-429  |
