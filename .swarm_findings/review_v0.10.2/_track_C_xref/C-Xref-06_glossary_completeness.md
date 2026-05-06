# C-Xref-06 — Glossary completeness & accuracy audit (v0.10.2)

**Scope:** `docs/strategy/glossary.md` audited against `Bot.lua`,
`BotMaster.lua`, `State.lua`, `Net.lua`, `Rules.lua`, `Constants.lua`,
and `docs/strategy/*.md` (incl. `_transcripts/*.md`).
**Mode:** Read-only.
**File audited:** `C:\CLAUDE\WHEREDNGN\docs\strategy\glossary.md`
(445 lines).

The glossary's "Re-anchoring line numbers" section (lines 397-444)
itself warns: *"They drifted +165 to +461 lines across v0.5.8 →
v0.5.14; treat them as approximate hints"*. As of v0.10.2 the
drift has compounded — every cited code line is wrong by **multiple
hundreds of lines** (not the +165 to +461 the doc admits to). The
drift now exceeds the warning's stated bounds.

---

## Section A — Missing entries

These terms appear in the codebase or strategy docs (or both) and
warrant a top-level glossary row but currently have none.

### A1. الثالث / "قبلك" — Triple-on-Ace pre-emption (HIGH PRIORITY)

| Field | Value |
|---|---|
| Arabic | الثالث (al-thaalith) — "the third"; cue word: قبلك ("before you") |
| Where used (code) | `Constants.lua:123` (`K.PHASE_PREEMPT`), `Constants.lua:211` (`K.MSG_PREEMPT`), `Bot.lua:3701` (`Bot.PickPreempt`), `Net.lua:190` (`N.SendPreempt`), `Net.lua:1528`, `Net.lua:1914` (preempt action), `State.lua:57`, `State.lua:1860` ("Pre-emption (الثالث 'Triple-on-Ace')"), `UI.lua:1944-1952` ("قبلك (Pre-empt)" button), `WHEREDNGN.lua:55-57`, `Slash.lua:188` (`preemptOnAce` toggle) |
| Where used (docs) | `decision-trees.md`, A-Src-13, A-Src-27, multiple `_transcripts/` files |
| Status in glossary | Only `Bot.PickPreempt` listed in v0.5.15 snapshot table (line 434); no Arabic-term row, no description |
| Suggested glossary row (Special plays table) | <code>&#124; الثالث / قبلك &#124; **Triple-on-Ace pre-emption** — when round-2 Sun lands on the bid card "Ace", earlier seats may claim the Sun for themselves. "قبلك" ("before you") is the cue word. &#124; `K.PHASE_PREEMPT`, `K.MSG_PREEMPT`, `K.MSG_PREEMPT_PASS`, `WHEREDNGNDB.preemptOnAce` &#124; `Bot.PickPreempt` (Bot.lua:3701); `N.SendPreempt` (Net.lua:190); state at `S.s.preemptEligible` &#124;</code> |

This is one of the most-referenced Saudi-specific bidding rules in
the codebase — it has dedicated phase, message, picker, network
handler, and sources A-Src-13 / A-Src-27 — yet no Arabic-term row
exists. This is the single most-noticeable gap.

### A2. Tamtheel (التمثيل) — parent class above Tanfeer (HIGH PRIORITY)

| Field | Value |
|---|---|
| Arabic | التمثيل (at-tamtheel) — "the casting / playing" |
| Where used | `_transcripts/12_tanfeer_explained_extracted.md:36` explicitly proposes adding this term to glossary; `_transcripts/19_discover_via_tahreeb_extracted.md:27` ("اعتبر تمثيل عادي") |
| Status in glossary | NOT PRESENT |
| Suggested row (Strategy terms section) | `### Tamtheel (التمثيل) — the umbrella playing-class`. *"Speaker's umbrella term for any card you play under specific conditions — superset of Tanfeer + Tahreeb. Two definitions: (a) narrow: only the cutter discarding while opponent eats the trick; (b) broad: any non-cutting follow when you're not trick winner. Speaker prefers the broad definition. Hierarchy: Tamtheel ⊃ Tanfeer ⊃ Tahreeb."* Sources: 12, 19. Code mapping: same `pickFollow` discard branch as Tanfeer. |

The user's question explicitly lists "Tamtheel" as one of the
"three-level taxonomy from A-Src-13" terms to verify. It is not in
glossary.md. The 12_tanfeer_explained transcript explicitly says
"Yes — currently undefined; add as the parent class above
Tanfeer/Tahreeb."

### A3. Bargiya (برقية) — own row, not just Tahreeb sub-row

| Field | Value |
|---|---|
| Arabic | برقية / برقيّة (bargiya / burqia) — "telegram" |
| Where used (code) | `Bot.lua:243` ("single Ace at index 1 = Bargiya (برقية, 'telegram'..."), `Bot.lua:570` ("single Ace at index 1 → Bargiya"), `Bot.lua:594` ("v0.10.2 M7 — Bargiya canonical FN: محشور بلون"), `Bot.lua:1638` (`tahreebClassify`, returns "bargiya"/"bargiya_hint"), `Bot.lua:1665` (returns "bargiya"); CHANGELOG.md M7 |
| Where used (docs) | `signals.md`, `decision-trees.md`, A-Src-05, `_transcripts/14_bargiya_ace_tahreeb_extracted.md` (entire video dedicated to Bargiya) |
| Status in glossary | Mentioned only inside the Tahreeb row (line 225) and inside Tanfeer row (line 261). No top-level Strategy-terms row. |
| Suggested row | `### Bargiya (برقية / burqia) — Ace-discard form of Tahreeb`. Six sender-side rules + six receiver-side rules per video #14. Two flavors: (a) come-to-me invite (محشور بلون واحد); (b) defensive shed (شرد بالاكة). Code identifier: `bargiya` / `bargiya_hint` from `Bot.tahreebClassify` (Bot.lua:1638). |

The user's question lists "Bargiya/Burqia (برقية) — A-Src-05" as a
specific term to verify. The code already has a canonical
identifier (`tahreebClassify` returns the literal string `"bargiya"`)
but the glossary buries it inside the Tahreeb row. Promoting to its
own subsection mirrors the existing pattern for Tahreeb / Tanfeer /
Faranka / Takbeer-Tasgheer.

### A4. محشور (mahshoor) — "cornered in one suit"

| Field | Value |
|---|---|
| Arabic | محشور بلون واحد (mahshoor bi-loon waahid) — "cornered in a single color" |
| Where used (code) | `Bot.lua:594` ("Bargiya canonical FN: محشور بلون واحد"), `Bot.lua:1654` ("محشور بلون واحد proxy"), `Bot.lua:1665` ("(محشور proxy)"); test: `tests/test_state_bot.lua:1763, 1801, 1809, 1818` (J.4 (M7) Bargiya canonical FN closure) |
| Where used (docs) | `signals.md:179`, `glossary.md:225` (passing mention only, inside Tahreeb row), `_transcripts/14_bargiya_ace_tahreeb_extracted.md`, audit `reaudit_R4_bargiya_tahreeb.md` |
| Status in glossary | Single inline mention in Tahreeb row; no row of its own |
| Suggested row (Hand-shape terms table, lines 332-338) | <code>&#124; محشور (mahshoor) &#124; "cornered" — holding 5+ cards in a single suit, leaving few options elsewhere. Critical proxy in `tahreebClassify` for distinguishing **Bargiya-as-invite** (sender محشور) from **Bargiya-as-shed**. &#124; 14, code (Bot.lua:1654-1665) &#124;</code> |

The user's question explicitly asks for "محشور — A-Src-30 / video
14" — not in glossary. Code uses it as a load-bearing axis for
M7 Bargiya classification.

### A5. Six-factor framework (Tanfeer reading) — A-Src-19

| Field | Value |
|---|---|
| Term | "Six-factor opp-Tanfeer reading framework" / سادس عامل |
| Where used (docs) | `signals.md:126` ("Six-factor opponent-Tanfeer reading"), `bot-personalities.md:179`, `_transcripts/19_discover_via_tahreeb_extracted.md:14, 102, 149, 155` |
| Where used (code) | Not yet wired — flagged in `_transcripts/19_*_extracted.md` |
| Status in glossary | NOT PRESENT |
| Suggested row | Add a sub-section under Tanfeer with the six factors: (1) timing (trick-index), (2) rank of discarded card, (3) two-discard same-suit confirmation, (4) both-opps discard same suit, (5) switch-suit, (6) bidder identity. Confidence weights summed in proposed `tanfeerWeight(seat, suit) → [0,1]`. Source: video #19. |

User explicitly lists "Six-factor framework (Tanfeer) — A-Src-19"
as a term to verify. Not in glossary.

### A6. Phase boundaries (Opening / Mid / Endgame) — A-Src-30 / video #14

| Field | Value |
|---|---|
| Arabic | بدايه اللعب / نهايه اللعب (bidaayat al-laʕib / nihaayat al-laʕib) |
| Where used (docs) | `_transcripts/14_bargiya_ace_tahreeb_extracted.md:63` defines: opening = 5+ cards in hand; endgame = ≤4 cards in hand; `glossary.md:226` references the boundaries in passing within Bargiya row |
| Where used (code) | Implicit in `Bot.lua` via `#hand` checks; no shared constant |
| Status in glossary | NOT PRESENT as named terms |
| Suggested rows | Add to Game state / hand totals or Other strategy idioms section: <code>&#124; بدايه اللعب (bidaayat al-laʕib) &#124; "opening/mid" — 5+ cards in hand &#124; 14 &#124; Used in Bargiya phase-split rules &#124;</code> and <code>&#124; نهايه اللعب (nihaayat al-laʕib) &#124; "endgame" — ≤4 cards in hand &#124; 14 &#124; Bargiya in endgame ⇒ lead immediately &#124;</code> |

User asks for "Mid-game / late-game phase markers from A-Src-30
(#14)" — not present as named entries.

### A7. كسر كبوت (kasar kaboot) — "broke the Kaboot"

| Field | Value |
|---|---|
| Arabic | كسر كبوت |
| Where used | `_transcripts/14_bargiya_ace_tahreeb_extracted.md:64` ("Already implied in `endgame.md`; this video uses the verb form explicitly.") |
| Status in glossary | NOT PRESENT |
| Suggested entry (Other strategy idioms) | <code>&#124; كسر كبوت (kasar kaboot) &#124; "broke the kaboot" — first-success against an Al-Kaboot sweep &#124; 14 &#124; Already implied in `endgame.md` Al-Kaboot pursuit logic &#124;</code> |

### A8. شرد بالاكة (sharrad bil-ikkah) — "shed-with-the-Ace"

| Field | Value |
|---|---|
| Arabic | شرد بالاكة |
| Where used | `glossary.md:225` (inline mention only inside Bargiya), Source A; also `_transcripts/14_bargiya_ace_tahreeb_extracted.md` Rule 4 |
| Status in glossary | Single inline mention |
| Suggested action | When Bargiya gets its own row (see A3), this can be a sub-bullet defining the defensive-shed flavor. |

### A9. The Three-level Tahreeb / Tanfeer / Tamtheel taxonomy (A-Src-13)

User asks for "Tahreeb (تهريب) / Tanfeer (تنفير) / Tamtheel — three-level taxonomy from A-Src-13".
- Tahreeb: PRESENT (line 219, dedicated subsection) ✓
- Tanfeer: PRESENT (line 234, dedicated subsection) ✓
- Tamtheel: ABSENT (see A2) ✗

The taxonomic relationship Tamtheel ⊃ Tanfeer ⊃ Tahreeb is hinted
at in the Tanfeer description ("Tanfeer is the parent class…
Tahreeb is the intent-bearing subset") but the parent **above
Tanfeer** is missing.

### A10. Ashkal vs الثالث distinction (A-Src-27)

User asks "Ashkal — A-Src-27 (vs الثالث)". Ashkal IS in glossary
(line 22, Bid types) ✓. The الثالث preempt (see A1) is missing,
so the *contrast* between the two cannot be drawn — the docs lack
the second pole.

---

## Section B — Inaccurate / nonexistent code identifiers

These glossary entries cite identifiers that don't exist in the
current codebase, or describe code state inaccurately.

### B1. `K.MULT_HOKM` does not exist — line 20

**Glossary line 20** (Bid types row "حكم") cites:
`K.BID_HOKM, K.MSG_HOKM, K.SND_VOICE_HOKM, K.PHASE_HOKM, K.MULT_HOKM=1`

Verified against `Constants.lua`:
- `K.BID_HOKM` = "HOKM" (line 60) ✓
- `K.MSG_HOKM` — **DOES NOT EXIST**. The wire-message constants do
  not include a per-bid-type tag (the contract-type is encoded
  inside the BID/CONTRACT message payload, not a separate MSG).
- `K.SND_VOICE_HOKM` (line 265) ✓
- `K.PHASE_HOKM` — **DOES NOT EXIST**. Phases are by stage of play
  (DEAL1, DEAL2BID, PREEMPT, OVERCALL, DOUBLE, TRIPLE, FOUR, GAHWA,
  DEAL3, PLAY, SCORE, GAME_END) — not by contract type.
- `K.MULT_HOKM=1` — **DOES NOT EXIST**. The base multiplier is
  `K.MULT_BASE=1` (Constants.lua:68); there is no Hokm-specific
  `MULT_*` constant.

Recommended fix: drop `K.MSG_HOKM`, `K.PHASE_HOKM`, `K.MULT_HOKM`
from the row; replace with `K.MULT_BASE=1` if a base-multiplier
note is desired.

### B2. `K.MSG_SUN`, `K.PHASE_SUN` do not exist — line 21

**Glossary line 21** (Bid types row "صن") cites:
`K.BID_SUN, K.MSG_SUN, K.SND_VOICE_SUN, K.PHASE_SUN, K.MULT_SUN=2`

Verified:
- `K.BID_SUN` = "SUN" (Constants.lua:61) ✓
- `K.MSG_SUN` — **DOES NOT EXIST**. Same as B1.
- `K.SND_VOICE_SUN` (Constants.lua:266) ✓
- `K.PHASE_SUN` — **DOES NOT EXIST**. Same as B1.
- `K.MULT_SUN=2` (Constants.lua:69) ✓

Recommended fix: drop `K.MSG_SUN`, `K.PHASE_SUN`.

### B3. `K.MSG_BEL` does not exist — line 41

**Glossary line 41** (Escalation chain row "بل") cites:
`K.MSG_BEL, K.MULT_BEL=2, K.BOT_BEL_TH=60`

Verified:
- `K.MSG_BEL` — **DOES NOT EXIST**. The wire constant is
  `K.MSG_DOUBLE = "X"` (Constants.lua:172).
- `K.MULT_BEL=2` (Constants.lua:70) ✓
- `K.BOT_BEL_TH=60` (Constants.lua:313) ✓

Note the asymmetry: `K.MSG_TRIPLE`, `K.MSG_FOUR`, `K.MSG_GAHWA`
all exist with those exact names, but the ×2 rung is named
`K.MSG_DOUBLE` in code (English-shorthand, not "BEL"). The
glossary should use the actual identifier or note the discrepancy
(this is exactly the kind of code-vs-Saudi-naming mapping the
glossary is supposed to clarify).

Recommended fix: replace `K.MSG_BEL` with `K.MSG_DOUBLE` and add
the parenthetical "(code uses English shortcut DOUBLE for the Bel
×2 rung)".

### B4. v0.5.15 snapshot table — every line number is stale

**Glossary lines 419-444** ("Current snapshot (v0.5.15)") provide
a "quick reference without re-grepping". As of v0.10.2 (Bot.lua
now 3953 lines vs ~2700 in v0.5.15), every entry is wrong.

Verified actual line numbers via grep against `Bot.lua`:

| Symbol | Glossary line (cited) | Actual line | Drift |
|---|---|---|---|
| `Bot.PickBid` | 890 | **1175** | +285 |
| `Bot.PickAKA` | 2302 | **3276** | +974 |
| `Bot.PickPlay` | 2344 | **3387** | +1043 |
| `Bot.PickMelds` | 2380 | **3423** | +1043 |
| `Bot.PickDouble` | 2403 | **3446** | +1043 |
| `Bot.PickTriple` | 2534 | **3593** | +1059 |
| `Bot.PickFour` | 2564 | **3629** | +1065 |
| `Bot.PickGahwa` | 2608 | **3676** | +1068 |
| `Bot.PickPreempt` | 2630 | **3701** | +1071 |
| `Bot.PickKawesh` | 2681 | **3816** | +1135 |
| `Bot.PickTakweesh` | 2708 | **3843** | +1135 |
| `Bot.PickSWA` | 2746 | **3881** | +1135 |
| `pickLead` | 1289 | **1703** | +414 |
| `pickFollow` | 1882 | **2484** | +602 |
| `escalationStrength` | 2510 | **3569** | +1059 |
| `escalateDecision` | 2525 | **3584** | +1059 |
| `scoreUrgency` | 753 | **986** | +233 |
| `matchPointUrgency` | 784 | **1055** | +271 |
| `Bot.OnPlayObserved` | 292 | **331** | +39 |

Drift now **exceeds the +461-line bound** the glossary itself warns
about (see line 401). Specifically the Pick* picker block has
drifted ~1000+ lines uniformly, indicating major insertions in the
helper / observation block earlier in the file.

Also note: the grep recipe at line 407 includes `PickAshkal` —
**no `Bot.PickAshkal` function exists** in `Bot.lua` (and never
has, per the table above where Ashkal logic lives inside
`Bot.PickBid`). The grep recipe should drop `PickAshkal`.

Per-row fixes are deferred to a glossary edit; this audit is
read-only. Recommend a single regeneration pass that runs the
grep recipe against current Bot.lua and overwrites the snapshot
table.

### B5. Inline body line numbers — all stale

**Glossary lines 20-50, 93-99, 231, 265, 276, 287** include
inline `Bot.lua:NNN` references. Spot-check confirms each is now
inside an unrelated function. Examples:

| Glossary cite | What the line actually contains today |
|---|---|
| `Bot.PickBid (Bot.lua:725)` (lines 20-22) | Inside the strength helper for Hokm bid evaluation (a helper above PickBid, not PickBid itself). Actual PickBid is at 1175. |
| `pickLead (Bot.lua:953)` (line 20) | Inside `partnerBidStrength` helper. Actual pickLead is at 1703. |
| `pickFollow (Bot.lua:1457)` (lines 20, 93, 231, 265, 276, 287) | Inside a Hokm-overcall comment in PickBid. Actual pickFollow is at 2484. |
| `Bot.PickAKA (Bot.lua:1686)` (line 93) | Inside `tahreebClassify` (returns "bargiya"/"want"/etc.). Actual PickAKA is at 3276. |
| `Bot.PickSWA (Bot.lua:2120)` (line 94) | Inside pickFollow trump-tempo comment. Actual PickSWA is at 3881. |
| `Bot.PickDouble (Bot.lua:1787)` (line 41) | Inside pickLead sweep-pursuit branch. Actual PickDouble is at 3446. |
| `Bot.PickTriple (Bot.lua:1908)` (line 42) | Inside pickLead bargiya_hint comment. Actual PickTriple is at 3593. |
| `escalationStrength` "Bot.lua:1884" (line 47) | Inside pickLead tahreeb-receiver score table. Actual escalationStrength is at 3569. |
| `escalateDecision` "Bot.lua:1899" (line 48) | Same pickLead branch. Actual escalateDecision is at 3584. |
| `scoreUrgency(myTeam, context) — Bot.lua:588` (line 49) | Inside MULT_BASE / mode-pickPicker. Actual scoreUrgency is at 986. |
| `matchPointUrgency(myTeam) — Bot.lua:619` (line 50) | Same area. Actual matchPointUrgency is at 1055. |
| `Net.lua:~3535` for "MaybeRunBot SWA branch" (line 94) | `MaybeRunBot` is at Net.lua:3552 — within the "approximate hint" tolerance, the only line cite that is roughly accurate. |

### B6. Fzloky meaning is canonical, not "unclear"

**Glossary lines 175-178** — "Fzloky (فضولكي ≈ فضولي?) — meaning
unclear; could be 'the curious one' or addon-specific. Worth
confirming with native speakers."

**Code is canonical**: `WHEREDNGN.lua:33` and `Bot.lua:67` both
state: *"Fzloky (فظلوكي — 'veteran / they leave you no scraps')"*.
The Arabic spelling in the code is **فظلوكي** (with ظ), whereas
the glossary speculates **فضولكي** (with ض / with ول). These are
different roots. Code's gloss has been stable across revisions.

Recommended fix: align glossary with code's authoritative gloss.
"Fzloky (فظلوكي) — 'veteran / they leave you no scraps'. Saudi
slang for an opponent who plays so tightly there's nothing left
for you to grab."

### B7. Takweesh / Qaid / Kasho conflation note

**Glossary lines 95, 98, 99** describe Takweesh/Kasho/Qaid as
related-but-distinct. **Already partially correct** — lines 95
and 98 already note "(Kasho is NOT the same as Qaid)".

However per `_transcripts/30_qaid_vs_kasho_extracted.md:13-33`
(the dedicated definitional video for these two penalties), the
**Takweesh row itself** is *also* slightly wrong by conflation:

> "The existing **`تكويش (Takweesh)`** entry in Special-plays
> table — described as 'call illegal-play penalty (qaid)' — is
> also **wrong by conflation**. Takweesh is the **verbal form
> of Kasho**, the *light* pre-bid penalty, NOT the call that
> results in Qaid."

The current glossary row (line 95) does include both senses but
attributes them as both "calls" — when actually Takweesh is the
*verbal noun of Kasho*, and Qaid has its own verbal-noun family
(تجييد, تسجيل). Source video #30 is the authoritative
disambiguator.

Recommended fix: rewrite the Takweesh row to clarify
"Takweesh (verbal form of Kasho)" and split Qaid into its own
row (Qaid is currently only in the Open-questions list at lines
385-387, which itself contradicts the Special-plays row).

### B8. SWA 5-second timeout note clashes with CLAUDE.md

**Glossary lines 102-107** describe the SWA permission flow and
state "5-second auto-approve window if opponents don't respond".

CLAUDE.md (lines 70-79) clarifies (per video #35 verbatim):

> "The 5-second auto-approve timer is an **addon UX construct,
> NOT a Saudi rule**. Per video #35... Saudi convention uses verbal
> negotiation with no timeout — opps either say 'نسمح' (allow)
> or demand شرح (proof). The addon's auto-approve prevents
> network deadlock when humans don't respond."

The glossary doesn't acknowledge this. A reader following the
glossary alone would conclude 5s-auto-approve is the Saudi rule.

Recommended fix: add a parenthetical "(addon UX construct, not
Saudi convention — see CLAUDE.md and video #35)" to the 5-second
bullet.

### B9. "Bot.PickBid Ashkal branch (Bot.lua:725+)" — line 22

The "+" makes this an open range, but as confirmed in B5,
Bot.lua:725 is in the strength-helper for Hokm bidding, not in
the Ashkal branch of PickBid. The Ashkal branch is somewhere
inside Bot.PickBid (1175-3275 range). Recommended fix: re-anchor
to `Bot.PickBid` (Bot.lua:1175) and let the reader navigate.

### B10. Stale "MSG_TAKWEESH_OUT covers meaning (a)" claim — line 95

The glossary says `K.MSG_TAKWEESH_OUT` covers Takweesh meaning (a)
— illegal-play penalty call. **Actually correct in code**:
`K.MSG_TAKWEESH = "k"` and `K.MSG_TAKWEESH_OUT = "z"` (Constants.lua
187-188); these are the wire-message pair for caller→host call
and host→broadcast outcome. ✓ This entry is accurate.

### B11. Reverse Al-Kaboot constant status — line 97

Glossary says "**Proposed `K.AL_KABOOT_REVERSE = 88`** (single-source
from video #16, confirm before wiring). Qualifies only when bidder
was trick-1 leader. New `R.ScoreRound` branch needed; not currently
scored."

Verified: `K.AL_KABOOT_REVERSE` does NOT exist in Constants.lua.
The "Proposed" framing is correct. ✓ But cross-referenced in
`audit_v0.7.1/07_section7_endgame.md:21,28` and re-affirmed in
`review_v0.10.2/_track_A_sources/A-Src-18_v16_reverse_kaboot.md:239,243,275`
which now records "**Confirmed.** Authority says 88 raw" —
single-source per the strict rule, but the audit-corroboration is
recent. Glossary's caveat is appropriate.

---

## Section C — Stale code refs / pointers that have moved

This is mostly summarized in B4 and B5. The unique findings beyond
the line-number drift:

### C1. `Bot.PickAshkal` is referenced in re-anchoring grep recipe but doesn't exist

**Glossary line 407** grep recipe:
```bash
grep -n '^function Bot\.\(PickBid\|PickAshkal\|...\)' Bot.lua
```

`Bot.PickAshkal` has never existed; Ashkal logic is a branch
inside `Bot.PickBid`. The recipe should drop `PickAshkal` to
avoid silent zero-match.

(Note: CLAUDE.md ALSO references `Bot.PickAshkal` in its
"Where to look" table — that's a separate doc-staleness issue
outside this audit's scope but worth flagging.)

### C2. `K.MULT_BASE` is the actual base-multiplier constant; not surfaced anywhere in glossary

`K.MULT_BASE = 1` (Constants.lua:68) is used in
`Net.lua:2185, 2930` and `Rules.lua:883` to denote the round-multiplier
when no escalation has occurred. The glossary's confusing
"`K.MULT_HOKM`=1" placeholder (B1) suggests the author *meant*
this constant but used a non-existent name. Recommended addition:
mention `K.MULT_BASE` in the Bid types intro paragraph.

### C3. `S.s.preemptEligible` — undocumented state field

The الثالث preempt convention (A1) writes/reads
`S.s.preemptEligible` (Net.lua:417), but no glossary row mentions
this state field. Compare to the explicit `S.s.akaCalled`,
`S.s.swaRequest`, `S.s.contract` mentions throughout glossary.

### C4. `tahreebClassify` is a load-bearing helper, not in line-number snapshot

**Glossary v0.5.15 snapshot (lines 423-444)** lists `escalationStrength`,
`escalateDecision`, `scoreUrgency`, `matchPointUrgency`,
`Bot.OnPlayObserved` but NOT `tahreebClassify` (Bot.lua:1638) —
which is the entry point for all Bargiya/Tahreeb classification
referenced throughout the Bargiya / Tanfeer / Tahreeb sections.

Recommended fix: when regenerating the snapshot table (B4), include
`tahreebClassify`.

### C5. `N.HostResolveSWA` line is unspecified

Glossary line 94 says "Net.HostResolveSWA, Net.MaybeRunBot SWA
branch (Net.lua:~3535)". The `~3535` cite refers to MaybeRunBot
(actually Net.lua:3552). The `HostResolveSWA` location is **not
given** — actual: Net.lua:2862. Recommend explicit cite.

---

## Summary

**Counts**
- Section A — missing entries: 10 (2 high-priority: A1 الثالث/preempt; A2 Tamtheel)
- Section B — accuracy issues: 11 (3 critical: B1/B2/B3 nonexistent constants; B4/B5 systemic line-number drift)
- Section C — stale pointers: 5

**Highest-impact fixes**
1. **Add الثالث/قبلك pre-emption row (A1)** — full code support exists but term has no glossary row.
2. **Add Tamtheel row (A2)** — completes the three-level taxonomy explicitly requested by user, and `_transcripts/12_*.md` already proposes the row text.
3. **Drop the nonexistent `K.MSG_HOKM`, `K.PHASE_HOKM`, `K.MULT_HOKM`, `K.MSG_SUN`, `K.PHASE_SUN`, `K.MSG_BEL`** from rows 20, 21, 41 (B1/B2/B3) — replace `K.MSG_BEL` with `K.MSG_DOUBLE`.
4. **Regenerate the v0.5.15 snapshot table (B4)** — every entry now off by 200-1100+ lines; the in-doc warning's stated bound is exceeded.
5. **Promote Bargiya (A3) and محشور (A4) to their own rows** — both are first-class identifiers in the v0.10.2 M7 work but only mentioned inline.

**Files referenced**
- `C:\CLAUDE\WHEREDNGN\docs\strategy\glossary.md` (the audit subject)
- `C:\CLAUDE\WHEREDNGN\Bot.lua`
- `C:\CLAUDE\WHEREDNGN\Constants.lua`
- `C:\CLAUDE\WHEREDNGN\Net.lua`
- `C:\CLAUDE\WHEREDNGN\State.lua`
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` (canonical Fzloky gloss)
- `C:\CLAUDE\WHEREDNGN\Slash.lua` (preemptOnAce toggle)
- `C:\CLAUDE\WHEREDNGN\UI.lua` (قبلك button label)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\12_tanfeer_explained_extracted.md` (Tamtheel proposal)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\14_bargiya_ace_tahreeb_extracted.md` (Bargiya / phase boundaries / محشور)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\19_discover_via_tahreeb_extracted.md` (six-factor framework)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\30_qaid_vs_kasho_extracted.md` (Takweesh/Qaid/Kasho disambiguation)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R4_bargiya_tahreeb.md` (محشور as classification axis)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_A_sources\A-Src-18_v16_reverse_kaboot.md` (Reverse Al-Kaboot 88 confirmation)
