# 34_takweesh_basics — extracted rules

**Source:** [شرح التكويش في البلوت للمبتدئين | 5](https://www.youtube.com/watch?v=p0svUm6THvA)
**Slug:** `34_takweesh_basics`
**Topic:** Takweesh (تكويش / كوشة) — illegal-play / void-deal penalty call.
**Code touchpoint:** `K.MSG_TAKWEESH`, `K.MSG_TAKWEESH_OUT` (Net.lua handlers).

---

## 1. New terms

| Arabic | Transliteration | Meaning |
|---|---|---|
| تكويش / كوشة | takweesh / kosha | The penalty call. Mechanically: cards are exposed, hand is voided, no points awarded, redeal. |
| أكوش / بكوش / حكوش | akoosh / bakoosh / hakoosh | Conjugations of "I will Takweesh" — heard at the table. |
| له الحق انه يكوش | lahu al-haqq an yikoosh | "Has the right to Takweesh" — i.e. holds a qualifying hand or witnesses a violation. |
| سياق | siyaaq | Sequence/run meld (`K.MELD_SEQ3/4/5`) — relevant to "may have a meld coming" reasoning. |
| مشروع | mashroo' | "Project" — a meld-in-progress (e.g. "مشروع 50" = sequence-4 in progress). |
| كبوت | kaboot | Al-Kaboot sweep — already in glossary; cited as risk justifying Takweesh. |
| جيم حامي | jeem haami | "Hot game" — match score near target; raises Takweesh threshold for partner-bid case. |
| يقيدون عليك | yiqayyidoon ʕaleek | "They penalize you" — the *qaid* (قيد) applied if Takweesh is invalid. Already noted as open-question term in glossary. |

**Count: 8 new/clarifying terms.**

---

## 2. Mechanic definition (player-side)

- **Trigger 1 (most common, the focus of this video):** Your **first 5 dealt cards** are *all* drawn from the set {7, 8, 9} — any suit mix. If even one card is T/J/Q/K/A/Ikah, no Takweesh.
- **Trigger 2 (table-variant, briefly noted):** Some tables forbid Takweesh when the 5 cards form a سياق (sequence) of all 7-8-9 in the same suit; calling there earns a *qaid* against you. Default is "allowed".
- **Trigger 3 (general, prior episode):** Caller witnesses an illegal play (failed must-follow / must-trump). Already covered in `saudi-rules.md`; this video does not re-derive it.
- **Effect:** Cards exposed, hand voided, no points, redeal. (`K.MSG_TAKWEESH` already implements.)

---

## 3. Decision rules — when to call Takweesh

Hand qualifies (5 weak cards). Decision depends on *who bought the contract*:

| WHEN | RULE | WHY | CONFIDENCE |
|---|---|---|---|
| Opponent (LHO or RHO) has bought Sun or Hokm; you have the qualifying 5-weak hand | **Takweesh — always.** Don't think, don't pass. | Opponents bid because they have strong cards; expected loss is large (potential Kaboot in Sun). Your weak hand cannot defend. | Definite |
| **Partner** has bought Sun or Hokm; you have the qualifying 5-weak hand | **Default: do NOT Takweesh.** Continue play. | Partner bid because they hold strength; the 3 cards you haven't seen yet may give support / a سياق. Takweesh upsets partner ("ممكن يزعل") and discards their potential project (50 / 100 / 400 meld). | Definite |
| Partner bought **Hokm**, score is "hot" (`جيم حامي` — near match target) AND the buyer (partner) appears to hold a strong project (Ikah + T visible, etc.) | **May Takweesh.** Narrow exception. | When match-point pressure is high and partner's hand is already winning, the upside of voiding a likely loss exceeds the project-cost. | Sometimes |
| Partner bought **Hokm**; partner showed *hesitation* across two bid passes before committing | **May Takweesh.** | Hesitation indicates marginal hand; partner unlikely to make. | Sometimes |
| Partner bought Hokm; situation is *not* one of the two exceptions above | **Do NOT Takweesh** even if your hand is the qualifying weak shape. | Speaker emphatic: "ابدا ما انصحك تكوش" — losses in Hokm are bounded; partner's bid implies enough strength to make. | Definite |
| You yourself hold the qualifying 5-weak hand and the bidding is open to you | **Default: Takweesh** rather than buy Sun. **Buy Hokm only if** the upcard / talon-card is the **J (ولد)** of your strong suit (gives 4 trumps + 50-meld). With Ikah upcard: also buyable but riskier. With T upcard: borderline; buy at start of game, Takweesh near end. | Buying Sun on this hand is hopeless; buying Hokm requires a J-anchor or strong context. | Definite |
| You hold qualifying hand, J-of-suit is the upcard, you have 7+8+9 of same suit | **Buy Hokm "blind" (مغمض)** — auto-decision. 50-meld + 4 trumps + J-top guarantees the contract. | Hand-shape forces the optimal action. | Definite |

**Single-line answer (when to call Takweesh):** call it whenever your first 5 dealt cards are all 7s/8s/9s **AND** the bidder is *opponent*, OR you are open-to-bid with no J-anchor; do NOT call when *partner* bid (except hot-game / partner-hesitated narrow cases).

---

## 4. Code mapping notes

- **Existing wires:** `K.MSG_TAKWEESH`, `K.MSG_TAKWEESH_OUT` already in Net.lua (Saudi-rules.md line 96-99).
- **Bot-side decision logic — `(not yet wired)`:** there is no `Bot.PickTakweesh` picker. Adding one would need:
  - Trigger detection: count `len([c for c in hand[:5] if rank in {"7","8","9"}]) == 5`.
  - Branch on `S.s.contract.bidder` vs `R.TeamOf(seat)` to identify opp-bidder vs partner-bidder.
  - Hot-game predicate: `S.s.scoreUrgency >= matchPointUrgency_threshold` (reuse `Bot.scoreUrgency` Bot.lua:588).
  - Hesitation-detection: requires history of bid-passes per seat — not currently logged; would need a `Bot._partnerStyle[seat].bidHesitations` ledger key.
- **Self-bid branch interacts with `Bot.PickBid`** (Bot.lua:725): the "buy Hokm blind on J-upcard with 7+8+9 of suit" rule strengthens the existing strength-threshold logic for hands that look weak by face-value but are meld-rich.

---

## 5. Decision-tree rows to add

Proposed entries for `decision-trees.md` (new section: "Section 12 — Takweesh"):

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Your first 5 dealt cards are all 7/8/9 (any suit mix); opponent has bought Sun or Hokm | Call Takweesh (`K.MSG_TAKWEESH`). | Opponents hold strength; your weak hand cannot defend; Kaboot risk in Sun. | New `Bot.PickTakweesh` `(not yet wired)`. | Definite | 34 |
| Same hand-shape; **partner** has bought Sun or Hokm | Do NOT call Takweesh; play through. | Partner has strength; remaining 3 cards may support; Takweesh discards partner's meld project. | New `Bot.PickTakweesh` partner-bid branch. | Definite | 34 |
| Same hand-shape; partner bought Hokm; `scoreUrgency` near match-point AND partner hand visibly strong (Ikah + T shown) | May Takweesh. | Hot-game upside outweighs partner-project cost. | `Bot.PickTakweesh` hot-game branch + `Bot.scoreUrgency` Bot.lua:588. | Sometimes | 34 |
| Same hand-shape; partner bought Hokm after hesitating across multiple bid rounds | May Takweesh. | Hesitation = marginal hand. | `Bot.PickTakweesh` + new ledger key `bidHesitations`. | Sometimes | 34 |
| You hold the qualifying 5-weak hand; bid is open to you; upcard is J of a suit you hold 7+8+9 in | Buy Hokm "blind" — do NOT Takweesh. | 50-meld + 4 trumps + J-top guarantees the contract. | `Bot.PickBid` (Bot.lua:725) — strengthen meld-aware path. | Definite | 34 |
| You hold qualifying 5-weak hand; bid is open; no J-anchor; T or Ikah upcard | Borderline — buy Hokm at start of round, Takweesh near match-end. | Match-point pressure flips the EV. | `Bot.PickBid` + `Bot.PickTakweesh` interaction. | Common | 34 |
| You hold qualifying 5-weak hand; bid is open; no J/T/Ikah upcard support | Default: Takweesh rather than bid. | Hand cannot make any contract. | `Bot.PickTakweesh` self-bid-window branch. | Definite | 34 |

---

**Rule count:** 7 new decision-tree rows.
**New-terms count:** 8.
