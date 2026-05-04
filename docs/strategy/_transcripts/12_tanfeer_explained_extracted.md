# 12 — Tanfeer in Baloot explained (تهريب الخصم)

**Source:** https://www.youtube.com/watch?v=DJdjgz04fiw
**Slug:** `12_tanfeer_explained`
**Title:** شرح التنفير في البلوت ؟ - تهريب الخصم
**Topic:** Dedicated treatment of Tanfeer (تنفير) — definition, distinction from Tahreeb (تهريب), and how to read opponent vs. partner discards.

> **Note on caption rendering:** The transcript renders تنفير (*tanfeer*) as **تنفيذ** (*tanfeedh*) throughout — the standard YouTube ASR homophone error. All instances of "tanfeedh / تنفيذ" in the raw text are interpreted as Tanfeer / تنفير.

---

## 1. Decision rules

| # | WHEN | RULE | WHY | MAPS-TO | CONFIDENCE |
|---|---|---|---|---|---|
| 1 | You are مجاوب (following, not cutting) and play any non-top card under another player's lead — partner OR opponent winning | This counts as Tanfeer (تنفير) — the discard you make is "the suit you don't want THAT card of"; the suit itself may still be one you want. | Default classification: any non-cutting follow that isn't the top is Tanfeer by default; specific intent upgrades it to Tahreeb. | `pickFollow` Bot.lua:1457 — discard-classification branch `(not yet wired)`. | Common |
| 2 | You play a discard with **specific suit-shape intent** (e.g. throwing هاوس to ask for ديمه, or "عكس اللون") | Action upgrades from Tanfeer → Tahreeb (تهريب). Tahreeb = intentional Tanfeer. | "كل تهريب تنفيذ لكن ليس كل تنفيذ تهريب" — every Tahreeb is a Tanfeer, but not every Tanfeer is a Tahreeb. | `pickFollow` Bot.lua:1457 sender intent flag — drives whether style-ledger writes a directional signal `(not yet wired)`. | Definite |
| 3 | You discard a card you don't want (no high-card power in any suit; nothing to bait with) without targeting a specific suit-shape | This is Tanfeer **without intent** (تنفير بدون قصد). Carries no directional signal, even though the card was "thrown away". | Player simply has nothing meaningful to send; receivers must NOT read a directional Tahreeb signal here. | Style-ledger writer must distinguish forced-shedding from intentional Tahreeb; gate Tahreeb-write on hand-strength check `(not yet wired)`. | Common |
| 4 | You hold T+7 of suit X and X is led; opponent leads small | Play the 7 (lowest) — you are "Tanfeer'ing the 7" but the SUIT is one you still want (you hold the T). | "ما ابغى السبعه صرفتها لكن مش شرط اني ما ابغى الشكل" — you don't want THAT card, but the suit shape is fine. Card-level vs suit-level Tanfeer distinction. | `pickFollow` Bot.lua:1457 follow-with-low when holding hidden T `(not yet wired)`. Should NOT trigger any Tahreeb suit-aversion ledger write. | Definite |
| 5 | All players are مجاوب (each followed suit / nobody ruffed) — read mode | Treat any discards as Tanfeer (default). Sender either (a) holds a hidden top of that suit (like rule 4), or (b) genuinely has no power anywhere. | Tahreeb interpretation requires a cut/ruff — without one, default to Tanfeer's two priors. | `pickLead`/`pickFollow` Bot.lua:953/1457 read-side — gate Tahreeb interpretation on "did sender ruff to make this discard?" `(not yet wired)`. | Common |
| 6 | **Partner cuts (ruffs)** and discards from a side suit | **Default to Tahreeb interpretation** — partner is signaling. Read suit direction (top-down/bottom-up), apply Tahreeb conventions (عكس اللون / عكس الشكل / Bargiya). | Partner ruffing = controlled action; partner is choosing what to throw. "خويك اذا قطع... دائما تفترض مبدئيا انه خويك قاعد يهرب لك". | `pickFollow` Bot.lua:1457 partner-ruff branch — write Tahreeb signal to ledger by default `(not yet wired)`. | Definite |
| 7 | Partner cuts and discards but you later observe partner has no high-card power anywhere | Re-classify retroactively: partner was Tanfeer-ing, not Tahreeb-ing — they had nothing to redirect to. | "ممكن بعدين تكتشف ان خويك قاعد ينفر لك يعني ما عنده قوه". | Style ledger should support late-correction / downgrade of Tahreeb signals when sender's hand is fully revealed `(not yet wired)`. | Common |
| 8 | **Opponent cuts (ruffs)** and discards from a side suit; YOU are winning the round (ماكل الحله) | **Default to Tanfeer interpretation** — opponent is shedding from a position of strength: they likely hold the A or T of the discarded suit. | "الورقه اللي يقطع فيه جمال كبير انه عنده قوته عنده الاكه او العشره" — when YOU control the round, opp's discards lean toward Tanfeer (positive about that suit). | Style ledger `Bot._partnerStyle[oppSeat].suitStrength[suit]` += weight when opponent-ruffs-and-discards-while-defending `(not yet wired)`. | Common |
| 9 | Opponent cuts (ruffs) and discards; YOU are LOSING the round (opp team is making) | Tahreeb interpretation gains weight — opponent may be running their own opp-Tahreeb (positive signal to THEIR partner). Tanfeer share decreases. | "اذا انت ما انت ماكل الحله حيبدا يزيد عندنا التهريب" — score/board state shifts the prior. | Read-side weighting: bidder-team-status influences Tahreeb-vs-Tanfeer prior `(not yet wired)`. | Common |
| 10 | Opp's Tahreeb shape vs partner's Tahreeb shape — encoding | Opp-team Tahreeb uses **different conventions** than your-team Tahreeb. Don't apply your-partner Tahreeb decoding directly to opp Tahreeb. | "يختلف نظام التهريب الخصم عن التهريب خويه" — explicit. | Two distinct decoders in style ledger: `partnerTahreebSignal` vs `oppTahreebSignal`. Same encode/decode shape but maintained separately `(not yet wired)`. | Sometimes |
| 11 | You hold T+شايب of side suit X (T mardoofa with K); your turn while opp is winning the trick; you must discard | **Do NOT Tanfeer X (don't shed from X).** Shed from a different suit. Speaker example: "كان نفرت الديمق احسن واحتفظت بالشريط". | Discarding from your strong suit gives partner no info AND wastes the cover card you'd need to capture later tricks. | `pickFollow` Bot.lua:1457 anti-Tanfeer guard on suits where you hold a top + lower `(not yet wired)`. | Common |
| 12 | Partner is winning the trick; you must discard; you have ZERO power across all suits (no A, no T anywhere) | "Genuine Tanfeer" — pick any low card; no informative signal possible. Speaker explicitly says it's fine ("اعتبر تمثيل عادي"). | When you've nothing to redirect to, the discard is irreducibly informationless. | `pickFollow` no-power discard branch — should NOT write directional Tahreeb signal `(not yet wired)`. | Definite |
| 13 | Partner winning, you must discard; you hold the شايب of ديمه but no other power | Tanfeer the شايب of ديمه (give up the K); informational value low — you held it forced. | Speaker example at end: K-of-diamonds discard with no other power = low-info Tanfeer, not Tahreeb. | Same as rule 12 branch `(not yet wired)`. | Sometimes |

---

## 2. New terms

| Arabic | Phonetic | Definition (this video) | Add to glossary? |
|---|---|---|---|
| التمثيل (at-tamtheel) | "the casting / the playing" | Speaker's umbrella term for "any card you play under specific conditions" — superset of Tanfeer + Tahreeb. Two definitions offered: (a) narrow: only the cutter discarding while opponent eats the trick; (b) broad: any non-cutting follow when you're not the trick winner. Speaker prefers the broad definition. | Yes — currently undefined; add as the parent class above Tanfeer/Tahreeb. |
| التنفير بقصد (at-tanfeer bi-qasd) | "intentional Tanfeer" | Tanfeer with directional intent — equivalent to Tahreeb. | Sub-row under Tanfeer entry. |
| التنفير بدون قصد (at-tanfeer bidoon qasd) | "unintentional Tanfeer" | Tanfeer with no directional intent — pure shedding. | Sub-row under Tanfeer entry. |
| الورقه نفسها vs الشكل (al-waraqa nafsaha / ash-shakl) | "the card itself vs the suit-shape" | Speaker's distinction: Tanfeer-ing a CARD (don't want this 7) ≠ Tanfeer-ing a SUIT (don't want this whole shape). The first is fine; only the second carries strategic info. | Add as a clarification note in glossary's Tanfeer entry. |

---

## 3. Contradictions / conflicts with existing notes

| Topic | Existing note | This video says | Resolution |
|---|---|---|---|
| Tanfeer "weaker / less common than Tahreeb" (from video #03) | Section 9 of `decision-trees.md`: "Tahreeb is dominant; default to Tahreeb when uncertain" | Speaker reverses framing: **Tanfeer is the GENERIC parent class; Tahreeb is the STRENGTHENED special case** ("كل تهريب تنفيذ"). Default for any non-intentional discard = Tanfeer. | No real contradiction — different lenses. Video #03 was talking about *interpretation priors* (when reading opp/partner play, lean Tahreeb). Video #12 is talking about *taxonomy* (Tahreeb is a sub-type of Tanfeer). Both can hold: Tanfeer is the default *category*, Tahreeb is the default *interpretation*. Logged here as a clarification, not a conflict. |
| Partner-ruff convention | Section 8 (Tahreeb sender side): "ruff IS the Tahreeb event" (single line, Common) | Confirms + extends: partner-ruff defaults to Tahreeb interpretation; opponent-ruff defaults to Tanfeer interpretation, **conditional on who's winning the round**. | Upgrade Section 8 partner-ruff row to **Definite**; add new Section 9 row for opponent-ruff-and-board-state-conditioned reading. |
| Opp-Tahreeb decoding | Section 9 row: "opp small→big tahreeb-style → suit to AVOID" | This video confirms opp uses different Tahreeb conventions but doesn't fully spec them. Adds: opp-Tanfeer (cutting + discarding) ≈ "I have power in the discarded suit" — directly opposite of the small→big read. | No conflict — Section 9 row is about opp small→big *sequence*, this is about opp single-cut discard. Two different opp behaviors with different reads. Add a new row for the cutting-discard case. |

---

## 4. Non-rule observations

The video is unusual in that it spends ~80% of its runtime on definitional / taxonomic clarification before giving any operational rule. The speaker is explicitly correcting a misuse he hears in casual play ("ليش يا خوية ما نفرتلي؟" — "why didn't you Tanfeer for me?") — which is colloquially used as a synonym for Tahreeb but, per the speaker, is technically distinct.

Two key meta-observations:

1. **Tanfeer is the generic CATEGORY; Tahreeb is the SUBSET with intent.** This inverts the impression video #03 gave (where Tanfeer felt like a niche corner-case of Tahreeb). The clean taxonomy: every meaningful discard is a Tanfeer; the *intentional, suit-shaped* ones are Tahreebs.

2. **The "who won the trick" axis matters more for opp-reads than for self-action.** When deciding what to play yourself, the partner-vs-opp-winning split drives encoding. When *reading* an opp's discard, the **score/round-state** (am I making? are they making?) tilts the Tahreeb-vs-Tanfeer prior on top of the trick-winner condition.

### Polished definition block (per task instructions)

**Tanfeer (تنفير)** — the act of discarding a card you don't want when you're not the trick-winner, regardless of whether the discarded suit-shape is itself wanted. Tanfeer is the **generic category** of all such throw-away plays; **Tahreeb is the subset of Tanfeer where the player has specific suit-shape intent** (sending a directional signal). Per this transcript: "كل تهريب تنفيذ لكن ليس كل تنفيذ تهريب" — every Tahreeb IS a Tanfeer, but not every Tanfeer is a Tahreeb.

**Trigger conditions** — Tanfeer applies in any non-leading position where the player must discard a card that isn't going to win the trick. It applies to BOTH partner-winning and opponent-winning contexts. Tahreeb is the upgraded interpretation of Tanfeer when (a) sender is on the partner-team-winning side AND (b) sender holds high-card power somewhere AND (c) the discard is shaped (top-down or bottom-up sequence, or Bargiya / Ace-discard).

**Sender's encoding** — In Tanfeer (without intent), no encoding: just shed your most disposable card. In Tanfeer-with-intent (= Tahreeb), encode direction: bottom-up = "I want this suit", top-down = "I refuse this suit", Ace-discard = Bargiya. Card-level vs suit-level distinction matters: throwing a 7 from T+7 is Tanfeer-ing the 7, NOT a refusal of the suit.

**Receiver's read** — Default classification rule: who ruffed?
- **Partner ruffed → assume Tahreeb.** Read direction; apply Tahreeb decoding (عكس اللون / عكس الشكل / Bargiya).
- **Opponent ruffed AND your team is winning → assume Tanfeer.** Opp likely has the A or T of the discarded suit (positive signal *about* that suit's strength).
- **Opponent ruffed AND opp team is winning → Tahreeb-prior rises;** opp may be running their own opp-team Tahreeb. Different decoding from your-team Tahreeb.
- **No ruff (all مجاوب) → default Tanfeer** (rule 5).

**Asymmetry vs Tahreeb** — Per video #03, Tahreeb is the "stronger" convention (more common and reliable). Per this video, that framing is a lens on **interpretation**: when reading partner's discards, lean Tahreeb. The taxonomic relationship is the inverse: **Tanfeer is the parent class** — every non-leading discard is a Tanfeer, while only intentional / shaped Tanfeers are Tahreebs. The "weakness" of Tanfeer per video #03 = *Tanfeer-without-intent's signal value is near zero*; receivers can't distinguish forced-shedding from genuine "I want this suit" without other context (sender's revealed hand strength, ruff event, score state). Tahreeb resolves this ambiguity through suit-shape and directional encoding.

---

## 5. Quality notes

| Aspect | Note |
|---|---|
| Speaker style | Pedagogical / corrective — addresses a specific terminological misuse rather than giving a strategy primer. Heavy on definitions, light on hand examples. |
| Examples | Two concrete examples: (a) T+7 of a suit (rule 4), (b) shayib + diamond shed when no power (rule 13). Both used for definitional disambiguation, not as strategy templates. |
| Transcript quality | Caption errors significant: تنفير → تنفيذ throughout (homophone). Suit-name spellings vary: شريه/شريحه/شريط (Hearts), هاص/هاوس (Clubs), ديمه/الديمق (Diamonds), سبيت/سبيد (Spades). Card-name family trio (شايب=K, بنت=Q, ولد=J) used consistently. |
| Confidence reliability | Speaker confident on taxonomic claims (Definite); operational rules around opp-ruff reading are presented as defaults that "can change with score state" (Common). The opp-Tahreeb-conventions claim ("different from your-partner") is asserted but NOT specified — needs a future video to fill in the conventions themselves. |
| Information density vs. video #03 | Lower density per minute; video #03 packs ~6 operational rules into 5 minutes, this video clarifies ~3 operational rules in roughly the same length and spends the rest on definition. **But** the definitional payload is high-value — it resolves the Tahreeb-vs-Tanfeer category confusion that other videos handwave. |
| Cross-references | Implicitly cites the Tahreeb introduction video (assumed prior knowledge — speaker uses Tahreeb's encoding as a known reference point). Does NOT explicitly reference Bargiya by name (says "اعطيت برقيه" once at line 88 without elaboration). |
