# X4: Pro-2 mandatory leads + cut/deal procedure

Cross-references audited Saudi Baloot rules (Phase 1 sources J/K/L) against
the WHEREDNGN code at `C:\CLAUDE\WHEREDNGN`.

Sources:
- Pro-2 PDF rules L07/L08/L09 — `_phase1_sources/source_L_pdf_secrets_doubling.md`
- Cut/deal & Belote timing — `_phase1_sources/source_J_cut_deal_play.md`
- Basic rules + Kasho/Kawesh — `_phase1_sources/source_K_pdf_basic_rules.md`

---

## Pro-2 rules verdicts

### L07 — Hokm bid REQUIRES holding an Ace (defensive vs Sun-overcall / Kaboot / 4-Hundred)

**Status: PARTIAL — implemented for the 3-trump branch only, missing for 4+ trump.**

`Bot.lua:740-757` — `hokmMinShape(hand, suit)`:
```
if not hasJ then return false end          -- B-4 absolute floor
if count >= 4 then return true end         -- B-2 self-sufficient   ← NO Ace check
if count == 3 and hasSideAce then return true end  -- B-1 minimum   ← Ace check (any suit)
return false
```

- `hasSideAce` is true iff the hand has any Ace OUTSIDE the chosen trump suit. This is the L07 Ace gate, but only for the count-3 minimum. With 4+ trumps, the bot will Hokm without any Ace.
- L07's Saudi rationale (defense vs Sun overcall, Kaboot, 4-Hundred) applies regardless of trump count. The 4-trump branch is missing the Ace gate.
- Source-H notes L07 is STRATEGY (not a hard rule), so missing it is not a legality bug — but it's a bot-quality gap consistent with the partial Saudi-pro alignment.

**Code refs:**
- `Bot.lua:740-757` `hokmMinShape`
- `Bot.lua:1382-1395` round-1 Hokm bid call site
- `Bot.lua:1432-1441` round-2 best-suit search (also relies on `hokmMinShape`)

### L08 — Sun bidder seat 1 MUST lead the backed Ace+T (mardoofa) on trick 1

**Status: NOT IMPLEMENTED.**

- `pickLead` (`Bot.lua:1632-2400+`) has no special-cased "if I'm the Sun bidder
  on the opening lead AND I hold A+T mardoofa, lead the Ace" path.
- The Sun-bidder lead path falls through generic priorities (sweep pursuit,
  free-trick, singleton low, then "Sun shortest-suit lead" at line 2273-2294
  which leads the LOWEST card from the SHORTEST suit).
- The L08 mardoofa probing lead is the OPPOSITE: lead a HIGH (Ace) card
  from a backed pair to flush out partner/opp projects.
- `aceCountAndMardoofa` (`Bot.lua:811-825`) is computed in `PickBid` only;
  no reuse in `pickLead`.
- L08's "obligatory on him AND on his partner" wording suggests partner-when-on-lead
  is also bound — also not implemented.

**Missing-feature.** Bot's opening Sun lead is generic "low from shortest" rather than mardoofa probe.

### L09 — Seat 1/2 deferral when bid card supports them but doesn't form 100-meld

**Status: NOT IMPLEMENTED.**

- `Bot.PickBid` (`Bot.lua:1126-1465`) has no seat-position deferral logic for
  the Sun-direct path. The only seat-aware code is the `bidPos` computation
  at lines 1246-1258, used solely to gate Ashkal eligibility (3rd/4th seat).
- A bot with strong Sun shape on seat 1 in round 1 will return `K.BID_SUN`
  immediately at line 1374 (`if sunMinShape(hand) and sun >= thSun then return K.BID_SUN`).
- No round-1-vs-round-2 deferral, no 100-meld-completion check, no
  partner-first-chance heuristic.
- Caveat in L09 ("only when bidding Sun AND bid-card does not specifically
  form your 100-meld") — both pieces of state are computable but not consulted.

**Missing-feature.** This is a defined Saudi pro convention for partner-coordination Sun bidding, currently absent.

---

## Cut/deal verdicts

### 3-3-2 + face-up + 2-3-3 deal pattern

**Status: SHORTCUTTED — net-equivalent totals, but no sub-pattern.**

`State.lua:1546-1592` implements the deal in two ATOMIC phases:

`HostDealInitial` (line 1546):
```
hands[seat] = C.DealCount(deck, 5)   -- one chunk of 5, no 3-3-2 sub-pattern
bidCard = table.remove(deck)         -- face-up bid card revealed
```

`HostDealRest` (line 1559):
```
table.insert(s.hostHands[bidder], bidCard)   -- bidder absorbs face-up
two = C.DealCount(s.hostDeckRemainder, 2)    -- bidder gets 2 more
for seat ~= bidder: three = C.DealCount(..., 3)  -- others get 3
```

- Total cards-per-player matches J-023: 8 each.
- Bidder keeps the face-up + 2 more (matches J-022).
- BUT the 3-3-2 / 2-3-3 sub-pattern is NOT simulated. It's a single 5-card
  block before the bid card and a single 3-card block (+2 for bidder) after.
- For a digital game with no physical cards, the totals are what matter and
  this is functionally correct. There's no observable Saudi-rule consequence
  to skipping the sub-pattern visualization.

**Note.** The comment at `State.lua:1564` mentions a "12 cards distributed"
total that's a typo (it's 11 = 2 + 9 in `HostDealRest`; bid card is the 12th).
Cosmetic, not a logic bug.

### Kasho 5×{7,8,9} hand-shape trigger

**Status: IMPLEMENTED (as Kawesh).**

`Cards.lua:170-177` `M.IsKaweshHand`:
```
if not hand or #hand < 5 then return false end
for _, card in ipairs(hand) do
    local r = M.Rank(card)
    if r ~= "7" and r ~= "8" and r ~= "9" then return false end
end
return true
```

`Bot.lua:3626-3632` `Bot.PickKawesh` calls it during PHASE_DEAL1 and triggers
unconditional redeal when eligible. UI surfaces a Kawesh button for humans.

This matches Source-J's Kasho hand-shape trigger ("five of {7, 8, 9}" =
unwinnable, redeal). The bot's policy is unconditional ("if eligible, call")
which matches Source-J's "redeal is strictly better than playing it" framing.

### Sessional 7-8-9 same-suit trigger

**Status: NOT IMPLEMENTED.**

- `IsKaweshHand` checks ranks only. There's no test for "7+8+9 of the same
  suit visible in your 5-card pre-buy hand → eligible for kasho/redeal."
- This sessional convention (per Source-J cluster) is not encoded anywhere.
- No grep matches for `7.*8.*9.*suit` or similar in Bot/Net/Rules/Cards.

**Missing-feature** if the team wants to support that sessional convention.

### Self-trigger override (kasho-hand + ground card J/T/A → BUY HOKM never Sun)

**Status: NOT IMPLEMENTED.**

- The override would require Bot.PickBid to consult kasho-hand state and
  the ground (bid) card rank to constrain the bidding choice.
- `Bot.PickKawesh` returns true and the host triggers a redeal, so the bot
  never reaches PickBid in that case — there's no decision branch where
  "kasho-hand but ground card is honor → don't redeal, prefer Hokm" exists.
- The redeal is forced unconditional; the override has no place to fire.

**Missing-feature.** The Saudi self-trigger nuance — that a kasho hand
with a ground-card honor flips to a forced-Hokm buy rather than redeal —
is absent.

---

## Belote timing

**Status: AUTO-DETECTED AT ROUND-END — no in-game announcement.**

`Rules.lua:659-684` (in `R.ScoreRound`):
```
if contract.type == K.BID_HOKM and contract.trump then
    local qWho
    for _, t in ipairs(tricks) do
        for _, p in ipairs(t.plays) do
            if C.Suit(p.card) == contract.trump then
                if C.Rank(p.card) == "K" then kWho = p.seat end
                if C.Rank(p.card) == "Q" then qWho = p.seat end
            end
        end
    end
    if kWho and qWho and kWho == qWho then
        belote = R.TeamOf(kWho)
    end
end
```

- Belote is detected POST-FACTO at round-end by scanning all completed tricks
  for K-of-trump and Q-of-trump played by the same seat.
- There is NO state machine for "play Q silent → play K → say Belote"
  (Source-J J-060/J-061) or "play K silent → play Q → say Belote" (Source-I).
- `R.DetectMelds` at `Rules.lua:194-256` does NOT detect Belote — Belote is
  not on the meld-declaration list (only seq3/seq4/seq5 and carrés). So
  `Bot.PickMelds` (`Bot.lua:3242`) cannot declare Belote on trick 1, and no
  network message announces it on the K-of-trump play.
- `audit_v0.7.1/70_ui_desync_hunt.md` notes "Belote announcement banner —
  ABSENT (BY DESIGN, NOT A BUG)" — confirming this is a deliberate
  simplification.

**Verdict.** Code does not match J-060/J-061 timing. It scores Belote
correctly but skips the announcement protocol entirely. Holders never
need to play K/Q in any specific order — the +20 fires on round scoring.

---

## Project elimination (PDF 04 L10–L18)

**Status: NOT IMPLEMENTED.**

Searched `BotMaster.lua` and `Bot.lua` for:
- "12-card visible base" inference logic (L10) — none.
- 100-meld negation by J or T sighting (L11) — none.
- 100-meld negation by Ace+(9/10/J) or K+(8/9/10/J) pairs (L12) — none.
- 4-Jacks/4-Tens carré self-resolution (L15) — none.
- 50-meld negation pair table (L16) — none.
- 20-meld/Sira negation by Q+9 or anchor-card pair (L17) — none.

**What IS implemented:**

`BotMaster.lua:230-260` — `meldPins` only handles **declared** melds (a
seat broadcast a meld via `SendMeld`). It pins the declared meld's exact
cards to the declarer's seat for ISMCTS sampling. There's no logic to
INFER an undeclared meld from the 12-card base or to ELIMINATE candidate
meld-suits based on visible cards.

`Bot.lua:1869-1897` — `pickLead` "B-97 opp-meld suit avoidance" only
fires when an opp HAS DECLARED a sequence meld in suit X (consults
`S.s.meldsByTeam` for declared melds). It avoids leading X to deny tempo.
This is the post-declaration anti-tempo rule, not the pre-declaration
elimination logic from L10-L17.

**Missing-feature.** The full PDF-04 project-elimination inference table
(12-card base, 100-meld negation pairs, 50-meld pairs, Sira anchor pairs,
J+Q-as-carré shortcut) is the most substantial missing-feature in this
audit cluster. It would feed both:
1. `Bot.PickPlay` opening leads (lead INTO deduced project suits per L13).
2. `BotMaster.lua` ISMCTS sampling (negative bias against suits where a
   project has been ruled out by visibility).

---

## Bugs found / missing features

### Confirmed missing-features

| ID | Rule | Severity | Code area |
|---|---|---|---|
| **MF-1** | L07 Hokm-Ace gate at 4+ trump | low (strategy) | `Bot.lua:740-757` `hokmMinShape` count-≥4 branch |
| **MF-2** | L08 Sun seat-1 mardoofa probe lead | medium (named pro convention) | `Bot.lua:1632-2400` `pickLead` Sun-bidder branch |
| **MF-3** | L09 seat-1/2 Sun deferral | medium (named pro convention) | `Bot.lua:1126-1465` `Bot.PickBid` Sun-direct path |
| **MF-4** | Sessional 7-8-9 same-suit kasho trigger | low (sessional) | `Cards.lua:170-177` `IsKaweshHand` |
| **MF-5** | Self-trigger override (kasho + ground-honor → Hokm-buy) | low (sessional) | `Bot.lua:3626-3632` Kawesh path |
| **MF-6** | Belote announcement timing (split K/Q play) | low (UI/protocol) | `Rules.lua:659-684`, no `Net.SendBelote` exists |
| **MF-7** | PDF-04 project-elimination inference (L10-L17) | **high** | `BotMaster.lua` sampler + `Bot.lua` pickLead |
| **MF-8** | Touching-honors trust-asymmetry (R6 carryover) | medium | `BotMaster.lua:453-472` `topTouchSignal` reader applies to all seats |

### Notes

- **MF-7 is the highest-leverage missing feature in this cluster.** The
  12-card-base inference + project-negation tables are an entirely missing
  Saudi-pro inference layer. Implementing it would:
  1. Feed `Bot.PickPlay` opening leads (lead INTO deduced meld suits per
     L13; avoid leading negated suits).
  2. Feed BotMaster sampling (down-weight high cards in negated suits when
     placing them in opponent hands; up-weight high cards in deduced
     meld suits to declarers).
  3. Tier-gate naturally: L10's "11 cards if I'm the bidder" caveat means
     the inference is most powerful on trick-1 lead decisions.

- **MF-8 (R6 carry-over).** Both `Bot.lua:470-500` (writer) and
  `BotMaster.lua:453-472` (reader) treat touching-honors signals from any
  seat — partner OR opponent — as authoritative. Saudi convention treats
  these as PARTNER-only signals (an opponent's K-on-A-led may be deceptive,
  not a signal of holding Q). The R6 finding flagged the writer; the
  BotMaster READER has the same gap and can pin opponent-side phantom
  cards. Recommend gating both sites on `R.TeamOf(s) == R.TeamOf(seat)`.

- **MF-1 (L07 partial)** is interestingly half-implemented. The `count == 3`
  branch enforces `hasSideAce`, which gives away that the original author
  knew about the Ace-defense rationale. The `count >= 4` branch was
  presumably given a free pass on the assumption that 4+ trump is
  self-sufficient. Saudi pro conviction (per Source-L) is that the Ace
  matters even at count 4+ for the defensive scenarios listed.

- **Cut/deal sub-pattern (3-3-2 / 2-3-3).** Functionally correct totals,
  no Saudi-rule consequence to skipping the sub-pattern. Not a missing-
  feature in the bug-correctness sense; only relevant if the team wants
  to add visual deal-animation faithfulness.

- **Belote timing (MF-6) is benign** in scoring terms — bonus is awarded
  correctly. The missing protocol means players can never "miss"
  announcing it (which is itself a Source-H soft-Qaid trigger in some
  sessions), so the addon is more permissive than strict Saudi tables.
  This is consistent with the addon's general policy of avoiding qaid
  surfaces in casual/digital play.

---

## Confidence

- **High** for L07/L08/L09 verdicts (read all of `Bot.PickBid` and
  `pickLead`, no mardoofa-lead or seat-defer logic exists).
- **High** for cut/deal verdicts (read `S.HostDealInitial` and
  `S.HostDealRest` start-to-end).
- **High** for Kasho 5×{7,8,9} (read `IsKaweshHand` and `Bot.PickKawesh`).
- **High** for sessional 7-8-9-same-suit and self-trigger-override
  absence (no grep matches anywhere in the codebase).
- **High** for Belote-timing (read `R.ScoreRound` belote block and
  `R.DetectMelds`; corroborated by audit_v0.7.1/70 explicit "BY DESIGN"
  finding).
- **High** for project-elimination absence (no grep matches for
  "negation"/"elim"/"infer.*meld" outside the declared-meld pinning).
- **High** for MF-8 BotMaster R6 carryover (read `BotMaster.lua:443-472`
  topTouchSignal reader; no team check).

No code was modified.
