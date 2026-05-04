# Extracted from 02_partner_after_tahreeb

**Video:** كيف تروح لخويك اذا هرب لك في البلوت
**URL:** https://youtu.be/30LkdVy4EV4

**Setup context (frame for every rule below):**
You won an early trick (e.g., with Ace), then your partner played a low card (a 7) on that trick — this is **Tahreeb (تهريب)**: partner is signaling weakness in that suit and asking you to lead a DIFFERENT suit back to them. The video covers how you, the partner, return to them — specifically when you hold a Ten (T) in the candidate suit.

Throughout: "shari3a" (شريعة / شريحة) is used as a generic suit-name placeholder (effectively "the suit you're returning to partner in"); "diamond" / "Daimon" is used interchangeably with shari3a in examples.

## 1. Decision rules

### Section 8 — Tahreeb (تهريب) — partner-supply convention

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Partner played Tahreeb (low e.g. 7) earlier; you now lead back to partner; you hold the **bare Ten (T) singleton** in suit X | **Lead the T immediately** | Standard Tahreeb "play your high card on the lead" convention; if you hold off, opponents will read partner as having T and capture it. Bare-T means partner almost always has the high cover (A or K+J). | `pickLead` Bot.lua:953 — Tahreeb-return branch (not yet wired) | Common | Speaker says "على طول روح بالعشرة" / "go straight with the T" |
| Partner played Tahreeb; you now lead back; you hold **T + one other card (T doubled, "مردوفة")** in suit X; **partner is the Sun bidder (مشتري صن)** | **Lead the side card (the shari3a / mid card), NOT the T**; expect partner to hold the missing strength because Sun bidders run on a single long suit | Sun bidder concentrates strength differently; T is safer to retain because the off-T card preserves the cover | `pickLead` Bot.lua:953 — branch on `S.s.contract.bidType == K.BID_SUN` and bidder == partner | Common | Speaker explicitly distinguishes Sun-bidder partner case as the only exception within the doubled-T rule |
| Partner played Tahreeb; you now lead back; you hold **T + one other card** in suit X; partner is **NOT** the Sun bidder (i.e. opponents bid, you bid, or it's a Hokm contract) | **Lead the T** (Tahreeb principle dominates); do NOT lead the side card | If you lead the side card, opponents read you as holding T and a defender (especially LHO) will "tafranak" (تفرنك / not over-cover) hoping to catch your T later | `pickLead` Bot.lua:953 — Tahreeb-return branch | Common | "تمشي أكثر على التهريب" — lean toward the Tahreeb convention by default |
| Partner played Tahreeb; you now lead back; you hold **T + 2 or more side cards** (T tripled+ in suit X) | **Lead the LOW side card (the 8) — NOT the T** | With 2+ side cards you have safety: even if a defender ducks, you still have an extra trick later, and partner likely has 3-card length too | `pickLead` Bot.lua:953 — Tahreeb-return branch, length-conditional | Common | Counter to the doubled-T case — extra length flips the recommendation |
| Same as above (T tripled+) — choice between **8 vs 9 vs T** | Prefer the **8** (lowest non-T); if not 8, the **9** (medium); avoid the **T** | Lead-low under partner's expected cover; preserves T for second round of the suit | `pickLead` Bot.lua:953 | Common | "الأفضل أنك تروح بالثمانية تمام، أو بالورقة المتوسطة اللي هي التسعة" |
| Partner played Tahreeb; you now lead back; you hold **a 3-card sequence/length without the T** (مثلوث) — e.g. K + small + small in shari3a | **Lead the K (شايب / Jack-equivalent high card)** is the obvious play, but the BETTER play is **lead the 8 or 7 (low)** | Leading the K gives away the trick if opponents have the A; leading low keeps the K alive as a re-entry, and partner can win and lead back | `pickLead` Bot.lua:953 — Tahreeb-return triplet branch | Sometimes | Speaker hedges — says "if you lead the K and partner had the A, fine; but the better option is low (8/7)" |
| Tahreeb-return decision in general — **never** lead the T's adjacent companion when T is doubled (شفع زوج العشرة) | **Do NOT lead the card directly next to the T** (e.g. don't lead the 9 or 8 when you hold T+9 or T+8) | Standard Baloot read: opening any non-A card from a doubled-T pair telegraphs the T to opponents, who then "tafranak" to scoop it | `pickLead` Bot.lua:953 — Tahreeb pair-discipline | Common | "خطأ أنك تروح بالورقة اللي جنب العشرة لو كانت العشرة مردوفة" — explicit "this is wrong" |
| You're the partner who Tahreeb-led, and partner returns the suit; you've already "discharged your duty" (أكلت اللي عليك) by winning the first trick with the high card | **Do NOT try to capture again with the T** on the return; release control to partner | Holding on to the T blocks partner's continuation in the suit; partner may have the K or J to win the next trick — let them | `pickFollow` Bot.lua:1457 — "released control after Tahreeb" branch | Common | "ما تبغى تمسك" — don't hog the lead |
| Tahreeb-return where you hold the bare T, but the T is now likely to be captured by opponents (e.g. last opponent likely has the A) | **Still play the T per Tahreeb convention** — accept the loss in this suit | Standard Baloot doctrine: at trick 1-2 of a return, opponents are usually expected to play their high cards too; if T loses to A here, opponents now have A out of the way for partner's K/Q to score later | `pickLead` Bot.lua:953 | Sometimes | Speaker's defense of the rule: "even if they take it, you played by the rules of Baloot — you can't be blamed" |

### Section 11 — Reads / partner-style inference

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Partner is **Sun bidder**; you are inferring partner's holding shape | Assume partner has **one long suit** (typically 4+) and concentrated high cards in it; partner unlikely to hold both colors strong; partner unlikely to hold T scattered | Sun is bid on hands that can run a single suit; mixed-strength hands bid Hokm or pass | `Bot._partnerStyle` style-inference (M3lm+ tier) | Common | Used to resolve the doubled-T return ambiguity above |
| Partner played Tahreeb (a low card after your A-win) | Read partner as: holds at minimum **A or J** in some other suit (probably the suit they expect you to return), AND likely **lacks** strength in the suit you led | The whole purpose of Tahreeb is to redirect to a suit where partner is strong — so its existence is a hard signal of partner's other-suit strength | `Bot._partnerStyle` Tahreeb-receiver inference (not yet wired) | Common | Listener-side inference; complements the leader-side rules above |

## 2. New terms encountered

| Arabic | Transliteration | Meaning in context |
|---|---|---|
| مردوفة | mardoofa | "doubled" — a card with exactly one companion in the same suit. The video uses "T mardoofa" to mean "T with one side card." |
| مثلوث | mathlooth | "tripled" — a card with two companions; or a 3-card length in a suit |
| تفرنك | tafranak | (verb form of faranka) "to play boldly" — here, refers to a defender ducking under your T hoping you'll lead it later. Used as the failure mode the convention is trying to avoid. |
| الشايب | al-shaayib | The "old man" — colloquial for the **King (K)** in non-trump (or Jack/J in some Saudi dialects, but here the "covering high card" sense matches K) |
| البنت | al-bint | "the girl" — colloquial for the **Queen (Q)** |
| العكه / إكه | al-akah / akah | The **Ace (A)** — confirmed against glossary's "AKA" entry but used here as the rank name |
| السميد | al-sameed | A specific suit reference (likely "spades / السبيت" — the example pivots between this and "Daimon"). Used as a generic suit placeholder in this video. |
| الشريعة / شريحة | shari3a / shari7a | A suit name used as a generic placeholder — the suit being returned. Variant spellings due to transcript noise. |
| الدايمن / الديمة | al-Daimon / al-Deemah | "Diamond" — the suit example used most often in the second half |
| قليل الأذرع | qaleel al-adhru3 | "few in arms" — a tactical concept the speaker introduces but doesn't fully define. Appears to mean "playing the lowest-pressure card" / "minimum-information lead." Worth confirming. |

## 3. Contradictions

| WHEN (shared) | Source A says | Source B says | Resolution |
|---|---|---|---|
| Doubled-T (T + one side) Tahreeb-return | "Lead the T (Tahreeb default)" | "If partner is Sun bidder, lead the side card" | Speaker resolves explicitly: Sun-bidder partner = exception. Both rules logged with the bidder-type predicate. |
| Tripled-T Tahreeb-return | The doubled case prefers T → naive extension says "lead T" | Speaker says "with 3+, lead the 8" | Resolved by length: ≤2 → T; ≥3 → 8. The two rules above encode the cutoff. |
| Triplet without T (K + low + low) return | Speaker first proposes "lead the K (shaayib)" | Then revises to "lead the 8 or 7" | Speaker's final recommendation is low; the K-lead is described as defensible but suboptimal. Logged at "Sometimes" because the speaker hedges. |

## 4. Non-rule observations

- The video is structured as a sequel to a "go with your highest card" base rule — this video introduces the **exceptions** for the T (and indirectly the K/J families) when partner has Tahreeb'd.
- Speaker's framing throughout: "play by the rules of Baloot first" — i.e., when in doubt, play the convention even if it costs the trick. This argues for a **convention-first heuristic** in the bot rather than an EV-maximizing single-trick search.
- The "tafranak" (defender duck) read is the central failure mode the rules guard against. This implies opponents in M3lm+ tier should themselves be modeling partner-side T-pairs and ducking against telegraphed leads.
- Speaker mentions partner having "a sequence" (sard / سرد) as evidence of strength; sequence-3 / sequence-4 melds are already encoded as `K.MELD_SEQ3` / `K.MELD_SEQ4` per glossary.

## 5. Quality notes

- Single transcript, single coach voice — confidence ceiling is **Common** per the prompt's guidance. Most rules are spoken with strong conviction ("غلط" / "wrong", "الأفضل دائماً" / "always best"), but a few are hedged with "ممكن" / "may" or "في الغالب" / "usually."
- Transcript quality is mid: auto-captions confuse "شريحة" (slice) and "شريعة" (law) as suit-name spellings; "أكه" (Ace) is rendered as both "أكه" and "إكه" and even "أوكه". I treated all as the Ace.
- Several plays are described in incomplete sentences (the speaker self-interrupts to address a child in the room around line 84); I extracted only what was clearly stated.
- The video ends mid-thought on "what if your triplet is K + low + low" — speaker proposes both K-lead and low-lead but doesn't finish the analysis. That branch is logged at "Sometimes."
- No information on Section 1 (bidding), Section 2 (escalation), Sections 3 (general opening leads beyond Tahreeb-return), 4 (mid-trick), 5 (pos-4), 6 (AKA), 7 (endgame/SWA), 9 (Tanfeer), 10 (Faranka). The video stays tightly on Tahreeb-return.
