# 19_discover_via_tahreeb — extraction

**Source:** https://www.youtube.com/watch?v=1DNO8__Gq_s
**Title (Arabic):** اكتشف اوراق خصمك من خلال التهريب في بلوت
**Topic:** READING side — using opponent's Tahreeb (here speaker uses تنفيذ ≡ تنفير; see glossary caption-error note) to infer their hand. M3lm-tier opponent-modeling.

---

## 1. Terminology

- **تنفيذ / تنفير (tanfeer)** — speaker uses تنفيذ throughout; per glossary caption-error rule, read as **تنفير** (the inverse-Tahreeb against opponent). In this video the term is broadened to mean *any opponent discard while not winning*, including their Tahreeb to their own partner. Treat as "opponent-side discard signal".
- **القاعده الاساسيه للتنفير** — "The fundamental rule of Tanfeer (opponent-discard reading)": **any suit opp discards → assume opp HOLDS the K (شايب) or T (عشره) of that suit; any suit opp does NOT discard → assume opp DOES NOT hold its top.** This is the *worst-case* / *paranoid* prior — the "افتراض الاسود" (the black assumption).
- **افضليه / ترجيح** — "preference / weighting": when Tahreeb-read and Tanfeer-read conflict on same evidence, **always prefer the Tahreeb interpretation** (partner-side reading is more reliable per video #03 rule).
- **سادس عامل** — "sixth factor" = **bidder identity**: who bought Sun/Hokm shifts which opponent the rule applies more strongly to.

(All match existing glossary entries; no new terms.)

---

## 2. Decision rules

### 2.1 The base rule (paranoid prior)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Opponent discards (تنفير) suit X early in hand | Provisionally assume **opp holds K or T of X** (worst case for you). Conversely, any suit opp does NOT discard → assume opp lacks its top. | "Black assumption" — plan against worst case so that updates only improve your read. Mirror of Tahreeb prior but inverted-actor. | New ledger key `Bot._partnerStyle[oppSeat].tanfeerSeen[suit]` set on opp-discard while opp not winning; new key `tanfeerAbsent[suit]` for not-yet-seen `(not yet wired)`. | Common | 19 |
| Trick 1-2 (opp still holds 7-8 cards) opp discards suit X | Read **DOWNGRADED** — opp likely dumping junk, not strength. Confidence ~10-20%. | Early discards are clearance, not signal. | `tanfeerSeen[suit]` weight = `0.2` if `discardTrickIndex <= 2` `(not yet wired)`. | Common | 19 |
| Mid-to-late hand (3+ tricks played, opp has ≤5 cards) opp discards suit X | Read **UPGRADED** — opp now signaling actual strength. Confidence climbs toward 70-90%. | Late discards happen because top is committed elsewhere; junk already gone. | `tanfeerSeen[suit]` weight scales with `discardTrickIndex` `(not yet wired)`. | Definite | 19 |

### 2.2 Rank of discarded card (second factor)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Opp's discarded card itself is high in suit X (T, 9, J, Q) | Confidence opp holds higher card in X is **stronger** — they wouldn't discard a top unless safer top is held above. | Ascending rank order: A > T > 9 > 8 > 7 maps directly to confidence. | `tanfeerSeen[suit].rank` field; weight = `f(rank)` `(not yet wired)`. | Definite | 19 |
| Opp discards 7 of suit X | Lowest-rank discard — only weakly suggests strength held. Could be pure junk-clearance. | 7 carries minimal signal value. | Same key, `rank=7` lowest weight `(not yet wired)`. | Common | 19 |
| Opp discards **A** (Ace / Bargiya) of suit X | **Special case — opp has slam (SWA) in X.** Read: opp's partner WILL lead X. Signal is positive, NOT the "doesn't have top" inversion. | Ace-discard is Bargiya semantics whether by partner or opp. | `tanfeerSeen[suit].isBargiya = true` overrides standard read; trigger "do NOT lead X" + "ruff X if possible" `(not yet wired)`. | Definite | 19 |
| Opp discards **T** (عشره) **late** in hand | **Strong** read — opp's partner has the suit. Opp wouldn't burn T unless coordinated. | Late T-discard is near-certain Bargiya-equivalent for top-strength suits. | `tanfeerSeen[suit].rank=T && trickIndex >= 5` flags as quasi-Bargiya `(not yet wired)`. | Common | 19 |
| Opp discards T **early** (trick 1-2) | **Reverse** read — opp likely has NO higher in suit, dumping cleanly because top is already played/dead elsewhere. | Early T = junk, late T = signal. Asymmetric on timing. | Same key, gated on `trickIndex <= 2` `(not yet wired)`. | Common | 19 |

### 2.3 Two-discard same-suit confirmation (third factor)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Same opp discards suit X **TWICE** in consecutive tricks | Confidence climbs sharply — opp is committed away from X. Mid-to-late, treat as **near-confirmed**. | Consecutive same-suit signal mirrors the partner-side two-Tahreeb confirmation rule. | `tanfeerSeen[suit].count >= 2 && consecutive=true` upgrades weight `(not yet wired)`. | Common | 19 |
| Same opp discards suit X twice but **non-consecutive** (gap trick was a different suit) | Still upgrade, but weaker than consecutive. | Pattern less coherent; could be forced. | `tanfeerSeen[suit].count >= 2 && consecutive=false` smaller weight bump `(not yet wired)`. | Common | 19 |

### 2.4 Both opponents discard same suit (fourth factor)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Both opps each discard suit X (same trick or successive) | Confidence opp-team holds X-top concentrates on **whichever opp discarded the higher card**. | Larger card = stronger committed-away-from-X signal. | When both seats have `tanfeerSeen[suit]`, attribute top to seat with `max(rank)` `(not yet wired)`. | Common | 19 |
| Two opps discard X in successive tricks; second discard happens later in hand | Late discard outweighs early — assign top to **later-discarder**. | Late = stronger per Section 2.1. | Combine `trickIndex` + `rank` weighting `(not yet wired)`. | Common | 19 |

### 2.5 Opp switches signaled suit (fifth factor)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Opp discards X first, then later discards Y (different suit) | **CANCEL** the X-read. Top now attributed to Y. The newer signal supersedes; opp's strength has shifted to Y. | Opp burns weak suits first, holds strongest for last. The progression Y > X in time = Y > X in held strength. | `tanfeerSeen[X].active = false` when `tanfeerSeen[Y].trickIndex > tanfeerSeen[X].trickIndex && Y != X` `(not yet wired)`. | Definite | 19 |
| Opp discarded X early then 7 of X again (same suit, weak rank) | Do NOT cancel — same-suit pattern is reinforcement, not switch. | Cancel only triggers on different-suit progression. | Gate cancellation on `Y != X` `(not yet wired)`. | Common | 19 |

### 2.6 Bidder identity (sixth factor)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| **Sun** contract; bidder is **YOUR partner** (or you) | Tanfeer-rule reliability **decreases** for both opps — they don't have strong cards anyway, so their discards are mostly junk. Apply only at end of hand. | Bidder concentrated strength on bidder team; opps have leftovers. | `if S.s.contract.bidType==K.BID_SUN && R.TeamOf(bidder)==myTeam: tanfeer weight *= 0.5` `(not yet wired)`. | Common | 19 |
| **Sun** contract; bidder is **opp** | Tanfeer-rule reliability **increases for the OTHER opp** (non-bidder) and **decreases for bidder-opp**. Bidder opp holds known strength; their discards are forced-burns of weak suits. Non-bidder opp's discards reveal real preferences. | Bidder's hand is largely deduced from bid; non-bidder is the unknown. | Per-seat weight: `bidder-opp tanfeer weight *= 0.7`, `non-bidder-opp tanfeer weight *= 1.3` `(not yet wired)`. | Common | 19 |
| **Hokm**; bidder is opp | Same direction as Sun-bidder-opp case but milder. Bidder still holds long trump; their off-suit discards are informative for off-suit holdings only. | Hokm bidder strength concentrated in trump, not all suits. | Weight adjustment Hokm-conditional `(not yet wired)`. | Sometimes | 19 |

### 2.7 Tahreeb beats Tanfeer when both apply

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Same trick: partner Tahreeb'd suit X to you AND opp Tanfeer'd suit Y; you must lead next | **Honor partner's Tahreeb signal first.** Tanfeer is supplementary. | "ترجح التهريب" — Tahreeb is stronger, more reliable. Convention priority (signals.md §7 already encodes this). | `pickLead` Bot.lua:953 already-existing priority order; ensure tanfeer reads do not override partner-Tahreeb decision `(not yet wired but covered)`. | Definite | 19, 03 |
| Opp's tanfeer interpretation conflicts with your own observed safe-suit reasoning (your hand says X is safe but opp tanfeer'd → opp wants X back) | **Respect tanfeer** — do NOT lead X. Treat as suit-to-avoid. | Opp's signal is for opp's partner; leading X walks into a setup. | `pickLead` opponent-Tanfeer-read avoidance branch (already noted in decision-trees §9 row 4) — this video corroborates `(not yet wired)`. | Common | 19, 10 |

### 2.8 Self-modeling (mirror your own Tahreeb to read opp)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| You are uncertain how opp interpreted partner's Tahreeb | **Put yourself in the opp's seat:** what would *you* infer if you saw the same sequence? Apply that inference to opp's likely next move. | "حط نفسك مكان الخصم" — opp's behavior shape mirrors your own when conventions are shared. Self-as-model. | Meta-rule; informs `pickLead` and `pickFollow` heuristics overall. No specific code site `(philosophical, not directly wired)`. | Common | 19 |

### 2.9 Updating reads dynamically

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Anytime new card is observed (every play) | **Re-evaluate all per-seat tanfeer reads.** Reads are NOT static; each new piece of info shifts confidence. | "تتغير فرضياتك في كل مره" — your hypothesis updates every trick, every play. | `Bot.OnPlayObserved` Bot.lua:267 — extend to recompute `tanfeerSeen[suit]` weights on every play `(not yet wired)`. | Definite | 19 |
| Opp discards but partner *also* signaled wanting same suit | The two reads reinforce each other if same direction; conflict if not. **Prefer partner-Tahreeb read on conflict.** | Partner-read priority preserved. | Conflict-resolution function in style ledger lookup `(not yet wired)`. | Common | 19, 03 |

---

## 3. Code-mapping summary

### Existing keys touched
- `Bot._partnerStyle[seat]` — extend per-opponent (not just partner) for tanfeer tracking.
- `Bot.OnPlayObserved` (Bot.lua:267) — write-site for tanfeer events.
- `pickLead` (Bot.lua:953) — read-site for "avoid suit X" / "lead suit Y" decisions.

### New keys proposed
- `Bot._partnerStyle[oppSeat].tanfeerSeen[suit] = { count, lastTrickIndex, maxRank, isBargiya, active }` — per-opp per-suit discard log (mirrors `tahreebSignal`).
- `Bot._partnerStyle[oppSeat].tanfeerAbsent[suit]` — derived flag: opp has NOT yet discarded suit X across N tricks → opp probably lacks its top.
- `Bot._partnerStyle[oppSeat].tanfeerSwitchedTo[suit]` — set when opp progressed from suit X to suit Y; cancels prior X-read.
- Confidence scoring helper: `tanfeerWeight(seat, suit) → [0,1]` summing the six factors (timing, rank, count, both-opps, switch, bidder-identity).

### Code mapping is `(not yet wired)` for all rows above.

---

## 4. Non-rule observations

### Opponent-Tahreeb reading algorithm

When opp (not partner) discards on a trick they're not winning, treat each discard as an information event with these inputs:
1. **Timing** — `discardTrickIndex` ∈ [1, 8]; weight rises with index (1-2 ≈ 0.2, 3-5 ≈ 0.6, 6-8 ≈ 0.9).
2. **Rank** — A (Bargiya, special-case), then T, 9, J, Q, K, 8, 7 (descending weight).
3. **Repetition** — same suit twice consecutive ⇒ near-confirm; non-consecutive twice ⇒ moderate confirm.
4. **Cross-opp redundancy** — both opps discarding same suit ⇒ split assignment by `max(rank, lateness)`.
5. **Direction switching** — opp moved from suit X to suit Y in later trick ⇒ cancel X-read, prefer Y.
6. **Bidder identity** — Sun-bidder-opp's reads are weaker; non-bidder-opp's reads are stronger; partner-bidder context softens both opps.

Output: a per-(seat, suit) confidence value for "opp holds the top of this suit" plus a flag for Bargiya/SWA-setup.

### Hand-distribution updates

Seeing opp's tanfeer changes the sampler's hand-allocation in two ways:

**Forward**: any suit opp discarded → bias sampler to deal opp the K or T of that suit (and possibly higher unseen cards). When mid-to-late, bias is strong enough to pin (similar to existing H-1 J/9-pin for trump under bidder).

**Reverse**: any suit opp has NOT discarded across all tricks → bias sampler **away** from giving opp the top of that suit. Useful for inferring partner's location of unseen high cards by elimination.

For Bargiya (Ace-discard) specifically: pin **all remaining cards of that suit** below A to opp's partner — opp wouldn't burn A unless committed.

### Counter-action

Given confident tanfeer reads:
- **Do NOT lead the suit opp has tanfeer'd** (their partner is set up there).
- **Lead the suit opp has NOT tanfeer'd**, especially if it's also opposite-color/opposite-shape from a partner-Tahreeb hint — reads compound.
- **Ruff opp's partner's leads** when that partner predictably leads the tanfeer'd suit.
- **In Sun late-hand**: if opp Bargiya'd, expect SWA call from opp's partner; if you have ruffing power (Sun = no trump, so cover via A or T of suit), preserve it.
- **In Hokm**: a tanfeer'd off-suit by opp = cover that suit with trump on next opp lead, since the holder is now exposed.
- **Self-mirror**: if you Tahreeb'd partner, expect opp to read it the same way — anticipate opp to start playing defensive against your own signaled return suit.

---

## 5. Open questions / contradictions

- **Threshold for "early vs late"** — speaker uses "اول دور / ثاني دور" (first/second round) vs "اخر الجيم" but doesn't fix a numeric boundary. Operationally suggest: `early = trickIndex ≤ 2`, `mid = 3-5`, `late = 6-8`.
- **Cross-confirmation with partner-Tahreeb-direction** — speaker doesn't address: if partner Tahreeb'd suit X (negative) and opp tanfeer'd suit X (positive for opp), do these tighten or weaken each other? Implementation guess: they tighten — both confirm "X is loaded somewhere, not on your team".
- **Hokm tanfeer of trump** — speaker doesn't separate trump-tanfeer from off-suit-tanfeer. Likely a future-video gap; for now apply same rules with caution since Hokm trump dynamics differ (Section 4 of decision-trees already handles trump-follow conventions).
- **Numeric weights** — speaker explicitly says "نسبه نجاحها من 1% الى 99% نسبه مفتوحه" (open-range). The six-factor weight scaling proposed above is a code interpretation, not a directly stated formula.

---

## Source

Single source: this transcript. Primarily *corroborates and inverts* video #03 (which introduced Tahreeb-vs-Tanfeer asymmetry) and is the **first dedicated treatment of the OPPONENT-side reading** in the corpus. Most rules above are NEW to the docs (no prior video covered the six-factor opp-tanfeer-reading framework). Should be cross-promoted to `signals.md` Section 6 (counter-signals) and `decision-trees.md` Section 11 (reads/inference) on integration.
