# Reaudit R3: SWA semantics — naming and mechanism

**Audit version**: v0.10.0
**Audit phase**: Phase 2 cross-reference
**Date**: 2026-05-05
**Scope**: Resolve the SWA naming/concept conflict surfaced by Source A (Tahreeb cluster, videos 01–10) vs Source I (video #35)

---

## TL;DR

The conflict is REAL but reconciles cleanly: **the same Arabic word "سوا" (swa) carries TWO different referents** in the Saudi Baloot literature.

1. In Tahreeb / burqia (`Bargiya`) context (Source A, videos 01, 02): "معك سوا" / "ما عندك سوا" describes a **supporting card alongside the Ace** (a hand-shape descriptor — "you have a backer"). This is the LITERAL Arabic meaning ("together / alongside").
2. In end-game-claim context (Source I, video #35): "سوا" / "تساوي" / "ساوى" is the **named claim mechanism** — "I declare I will win every remaining trick".

The code's `K.MSG_SWA`, `Bot.PickSWA`, `R.IsValidSWA`, `N.LocalSWA`, etc. correctly attach to **referent #2** (the end-game claim). The naming conflict is a property of the source language, not a code defect — but the code's **5-second auto-approve timer is invented** and is NOT in the source.

---

## Naming question

### Saudi-Arabic word for end-game-claim concept
- **Verbatim from #35 line 24**: "واليوم راح نتكلم على السوا في البلوت" ("Today we'll talk about al-SWA in Baloot")
- **Verbatim from #35 line 54**: "ايش معنى السوا معناته يكون عندك اكبر الاوراق في اللعب" ("What does SWA mean? It means you hold the biggest cards remaining")
- **Verbatim from #35 line 114**: "تقول سوا" ("you say 'swa'") — the verbal claim
- **Verbatim from #35 line 44**: "ابغى اساوي او عندي سوا او استوى اللعب" ("I want to swa, or I have swa, or the play has been equalized") — three forms attested

The root is **س-و-ي / س-و-ا** (swy / swa = "to be equal, to settle, to be all the same"). Forms used: noun **سوا (swa)** = "the claim"; verb **يساوي / تساوي (yusawi / tusawi)** = "to claim swa"; verb **استوى (istawa)** = "the play has been equalized" (i.e. nothing more to play for); verb **ساوى (sawa)** = "claimed swa". Speaker calls the request to do this **"تسمحوا لي اساوي"** (line 2204 — "permit me to swa").

### Saudi-Arabic word for hand-shape sense
- **Verbatim from Source A Rule 19, video 01 @ 00:11:45**: "البرقيه تكون اكه وتكون نفس الشكل اللي تبغاه ... معك سوا" ("the burqia is the Ace of the suit you want... you have swa")
- **Verbatim from Source A Rule 39, video 02 @ 00:03:55**: "ما عندك سوا فحيجيك سبيد وحتاكل حله واحده بس" ("you don't have swa so opponent will trump and you'll only win one trick")

Same word **سوا (swa)**. Same root. Used as a descriptive noun: **"معك سوا"** = "you have a backer/supporter" (i.e. you hold a card alongside the Ace that prevents opponent from immediately stealing the next trick after the Ace falls).

### Same word? Different word? Different meanings?

**Same word, two referents** — and Source A explicitly flagged this in its Open Ambiguity #1 ("the source uses سوا (literally 'together/alongside') to mean a supporting card with the A; the CLAUDE.md SWA refers to a permission-flow protocol; same Arabic word, different referent").

The two senses are linguistically related — both come from "alongside / together" — but in modern Saudi Baloot terminology video #35 has standardized **سوا** as the name of the END-GAME CLAIM, while video 01/02 (Tahreeb-cluster) still uses it as a **hand-shape adjective** describing what supporters you hold alongside an Ace.

This is a polysemy / homograph situation, NOT a code error. Native players disambiguate from context.

---

## Code naming verdict

**(A) Yes, name is correct — refers to end-game claim.**

The code's `K.MSG_SWA` / `K.MSG_SWA_REQ` / `K.MSG_SWA_RESP` / `Bot.PickSWA` / `R.IsValidSWA` / `N.LocalSWA` / `K.SWA_TIMEOUT_SEC` are all attached to the END-GAME-CLAIM concept (referent #2, video #35). The Constants.lua comment at line 192–196 confirms this:

```
K.MSG_SWA = "Q"  -- "SWA" (سوا) claim: caller asserts they will
                 -- win every remaining trick and reveals their hand.
```

That's the video #35 referent. The naming is correct.

**However**, the user's original confusion is well-founded: **anyone reading Source A in isolation would assume `Bot.PickSWA` referred to the supporting-card concept**, because that's the meaning attested in videos 01/02. Recommend a one-line glossary disambiguation comment in Constants.lua near `K.MSG_SWA` clarifying: "Note: 'سوا' in burqia/Tahreeb context (videos 01/02) refers to a supporting card with the Ace — a hand-shape descriptor. The code's SWA refers to the end-game claim mechanic of video #35. Same Arabic word, different referent."

This is a documentation polish, not a behavioral bug.

---

## Mechanism verdict

| Sub-rule | Code state | Source-correct? |
|---|---|---|
| ≤3 cards instant claim | NO LONGER instant in v0.5.17 | partially correct — see below |
| 4-card permission | YES (`needPerm` branch) | correct |
| ≥5-card MANDATORY permission | YES (same branch) | correct |
| 5-second auto-approve | YES (`K.SWA_TIMEOUT_SEC = 5`) | **INVENTED — not in source** |
| Deterministic-or-bust | YES (`R.IsValidSWA` adversarial recursion) | correct |
| Failed proof = qaid | YES (`HostResolveSWA` path) | correct |

### ≤3 cards instant claim — Y/partial + ref
- **Source #35 line 104**: "كل واحد في يده ثلاث اوراق ... من حقك انك تقول سوا" ("Each player has 3 cards left → you may say 'swa'")
- **Source #35 line 124**: "تقول سوا يعني ترمي الورق زي كذا" ("you say 'swa' meaning you throw the cards like this") — direct/instant
- **Code Net.lua line 2489–2492**: comment says "v0.5.17: route ≤3-card claims through the permission window too, so the SWA banner displays the caller's cards." Branches into the SAME 5-sec permission window for ALL counts.
- **Verdict**: The Saudi rule per #35 IS instant for ≤3 cards (no permission needed); code routes it through the same 5-sec display anyway as a UX choice. This is a **deliberate code divergence** justified in comment as "so the SWA banner displays the caller's cards" — i.e. a UX decision to ensure visibility, not a rule mismatch. Acceptable but documented as "v0.5.17 routes ALL through permission window".

### 4 cards permission — Y + ref
- **Source #35 line 2233 (sub #445–447)**: "في جلسات يسمحون عادي تساوي اربع اوراق ... في جلسات لازم تستاذن" ("Some tables allow 4-card SWA freely; others require permission")
- **Code**: `needPerm` is on by default (`WHEREDNGNDB.swaRequiresPermission ~= false`). Net.lua line 2477–2478.
- **Verdict**: Correct — code defaults to the permission-required convention (the stricter of the two table customs).

### ≥5 cards MANDATORY permission — Y + ref
- **Source #35 line 2244**: "في شيء اسمه سوا من اول يد" ("there's a thing called 'swa from first hand'") — the ≥5-card / first-hand SWA
- **Source #35 line 2404**: "هنا تستالن طبعا ما تساوي" ("here you must ask permission, of course you don't just swa")
- **Source #35 line 2414**: "لو ساويت بدون ما تستاذن يا سلام هذه مستحيل يمشونها" ("if you swa'd without asking permission — wow — they would never let it pass")
- **Code**: Same `needPerm` branch (Net.lua line 2492+) handles all card-counts ≥4 identically; ≥5 is never less restrictive than 4-card.
- **Verdict**: Correct.

### 5-second auto-approve — INVENTED (not Saudi rule)
- **Source #35**: zero mentions of any timer, "seconds", "wait", "countdown", or auto-approve.
  - Verified by Grep for `ثوان|توقيت|تايمر|ينتظر|انتظار|انتظر` — **0 matches** in the entire SRT.
- **Source #35 line 2204** describes the actual mechanic: "تقول مثلا تسمحوا لي اساوي" ("you say 'permit me to swa'") followed by **verbal** acceptance ("قالوا لك نسمح" — "they say 'we permit'") or denial ("ممكن يقول خلينا نلعب" — "they may say 'let's keep playing'") — purely a SOCIAL negotiation, no clock.
- **Code Constants.lua line 277**: `K.SWA_TIMEOUT_SEC = 5`
- **Code comment at line 270–276** is candid: "User-requested SWA timeout: when a permission-required SWA is in flight, the host auto-approves after this many seconds unless an opponent counters with Takweesh".
- **Verdict**: The 5-second auto-approve is an **addon-UX construct**, NOT a Saudi rule. Source A's audit Open Ambiguity #1 already flagged this; Source I's section B10 is explicit: "Speaker mentions a 5-second auto-approve in NO transcript. The '5-sec auto-approve' rule that the addon implements is NOT confirmed in source #35." The CLAUDE.md guidance line "with 4+ cards = permission flow with 5-second auto-approve" is therefore **wrong about the timer being a Saudi rule** — it should say "addon-UX timer to bypass deadlock; not in source".

### Deterministic-or-bust enforced in R.IsValidSWA — Y + ref
- **Source #35 line 2944**: "هذا اصلا سو مو صحيح ومن حق الفريق الثاني انه يقعيد عليك" ("this isn't a correct swa, and the other team has the right to qaid you")
- **Source #35 line 2964**: "دائما لا تساوي اذا كان عندك مثلا اكره وعندك ورقه غير الشايب" ("never swa if you have Ace + a non-King card") — i.e. if there's any holding pattern (مثلوث / muthloth = K + 2 cards in suit) by an opponent that defeats your claim, you must NOT swa
- **Source #35 line 2974**: "لانه ممكن يكون الخصم عنده مثلوث" ("because the opponent may have muthloth")
- **Code Rules.lua line 437–466**: comment block "v0.5.17: Saudi-strict-strict SWA. The caller's claim must hold REGARDLESS of which legal card any other seat (partner OR opponent) plays." Adversarial recursion treats partner adversarially too; if any legal play sequence breaks the claim, returns false.
- **Verdict**: Correct. The code is **stricter** than #35's literal text (partner is treated adversarially even though Saudi convention assumes partner cooperation in Hokm two-hand SWA per #35 line 2814 "ثق تماما انه خويك راح يجي دائما" — "trust that your partner will come"). This conservatism trade-off is documented at Rules.lua line 437–459 as a deliberate v0.5.17 decision per user intent.
- **Minor caveat**: Two-hand SWA in Hokm (Source I rule B16/B17/B18) — where partner having the second-best card or being void-and-with-trump completes the claim — is REJECTED by the current adversarial recursion because partner is treated adversarially. This **does diverge from #35** for the two-hand-SWA subtype. Whether that's intended-conservative or a true bug is a follow-up question; v0.5.17 documents it as intended.

### Failed proof = Qaid — Y + ref
- **Source #35 line 2944**: "من حق الفريق الثاني انه يقعيد عليك" ("the other team has the right to qaid you") — qaid penalty on failed proof
- **Source #35 line 2744**: "هذه فيها قعد" ("this one has qaid in it") — same penalty
- **Code Net.lua line 2131 `function N.HostResolveTakweesh`** + the SWA validation path applies the qaid penalty when `R.IsValidSWA` returns false; takweesh is the explicit counter-call. Cross-checked at Net.lua HostResolveSWA.
- **Verdict**: Correct.

---

## Detailed answers to your specific questions

### a) What is the actual Saudi-Arabic word for the end-game-claim concept that #35 covers? Is it "سوا"?

**Yes — "سوا" (swa)** is the canonical noun. Verbatim from #35 line 24: "السوا في البلوت" ("al-SWA in Baloot"). Verb forms used: **يساوي / تساوي / اساوي / ساوى / استوى / ساويت** (yusawi / tusawi / asawi / sawa / istawa / sawayt) — all from the same root س-و-ي. The video TITLE itself — `35_swa_term_detailed` — uses this transliteration.

### b) Is the same word "سوا" used for both the hand-shape concept AND the end-game-claim?

**Yes, same word, different referents.** Video 01 (Source A Rule 19, 39) uses **"سوا"** as a hand-shape adjective ("you have a backer/supporter alongside your Ace"). Video #35 uses it as the named END-GAME CLAIM. Same Arabic root, same surface form, contextually disambiguated. Source A explicitly flagged this as a CONFLICT in its Open Ambiguity #1.

### c) Is the 5-second auto-approve timer real or invented?

**INVENTED.** Verbatim search of #35 SRT for any timing-related Arabic vocabulary (`ثوان` = seconds, `توقيت` = timing, `تايمر` = timer, `ينتظر / انتظار / انتظر` = wait/waiting) yields **ZERO matches**. The speaker only describes a verbal negotiation: caller says "تسمحوا لي اساوي" (line 2204), opponents respond verbally with "نسمح" (permit) or "خلينا نلعب" (let's keep playing). No clock. Source I's section B10 also confirms this null finding.

The 5-sec timer is an addon-UX construct (per Constants.lua line 270–276 comment: "User-requested SWA timeout"). It is reasonable as UX — it prevents deadlock from absent humans — but it MUST NOT be presented as a Saudi rule. CLAUDE.md line 41 currently says "with 4+ cards = permission flow with 5-second auto-approve" which conflates the rule (permission flow) with the addon mechanism (5-sec timer).

### d) What does the speaker say about "5+ card mandatory permission"?

**Verbatim from #35 line 2244**: "في شيء اسمه سوا من اول يد" — "there's a thing called 'swa from first hand'" — the ≥5-card SWA. **Line 2253**: "اول يد من اول ثمانيه اوراق في يدك لسه تو خلاص اشتريت" — "first hand: from your first eight cards in hand, right after you bought the bid". **Line 2404**: "هنا تستالن طبعا ما تساوي" — "here you absolutely must ask permission, you don't just swa". **Line 2414**: "لو ساويت بدون ما تستاذن يا سلام هذه مستحيل يمشونها" — "if you swa'd without permission — wow — they would never let it pass; it's an opportunity for them to qaid you".

Mandatory. Confirmed.

### e) Is Saudi-strict deterministic-or-bust explicit in #35?

**YES, explicit.** Verbatim from #35 line 2944: "هذا اصلا سو مو صحيح ومن حق الفريق الثاني انه يقعيد عليك" — "this isn't a correct swa, and the other team has the right to qaid you". Line 2964: "دائما لا تساوي اذا كان عندك مثلا اكره وعندك ورقه غير الشايب لانه ممكن يكون الخصم عنده مثلوث" — "never swa if you have Ace + non-King card, because opponent may have muthloth". Line 2984: "ايش يعني مثلوث؟ يعني عنده ثلاث اوراق من نفس الشكل" — defines muthloth as 3-of-suit-with-K. Line 3104: "هذا حياكلها بالشايب اذا هذا مش سوا" — "opponent's K eats your Q, so this isn't a [valid] swa".

Speaker's framing: if any defensive holding pattern (notably muthloth = K-with-2-supporters) by ANY opponent could defeat the claim, the SWA is invalid and qaid-able. This is exactly the deterministic-or-bust rule. Source I summarises this at section B21 with the same conclusion.

### f) Does Bargiya/Burqia in tahreeb context have a SWA-related precondition that the code might be conflating with end-game SWA?

**YES — and this is the source of Source A's flagged conflict.** Per Source A Rule 16 (video 14): "الافضل لا تبرق الا اذا عندك سوا" — "best NOT to send Bargiya unless you have SWA". Per Source A Rule 19 (video 01): "البرقيه تكون اكه وتكون نفس الشكل اللي تبغاه ... معك سوا" — "burqia is Ace-of-wanted-suit ... you have swa". Per Source A Rule 39 (video 02): "ما عندك سوا فحيجيك سبيد وحتاكل حله واحده بس" — "without swa, opponent trumps and you only get one trick".

In ALL these, "swa" means **a supporting card alongside the Ace** (e.g. holding A + 10 of suit; the 10 is your "swa"). It is a **hand-shape precondition for sending a Bargiya**, NOT the end-game claim mechanic.

**Could code conflate these?** The bot's `Bot.PickSWA` is purely about end-game claim and never reads partner's burqia signals. So the code is NOT conflating them at the implementation level. **However**, anyone touching `Bot.PickBargiya` (or `Bot.PickAKA`'s burqia-emission logic, depending on naming) might confuse the two senses when reading the source. Recommend a glossary entry: "swa (alongside-card sense) = supporting card paired with Ace, used in burqia preconditions; distinct from K.MSG_SWA which names the end-game-claim".

---

## Recommended code action

**Behavioral changes**: NONE required. The code's mechanism (instant ≤3, permission ≥4, mandatory ≥5, deterministic-or-bust validator, qaid on failure) matches Source #35.

**Documentation changes** (1 small, 1 important):

1. **(SMALL — 1-line edit)** In `Constants.lua` near line 192 (`K.MSG_SWA`), add a comment:
   ```
   -- Note: 'سوا' has TWO referents in Saudi Baloot literature.
   -- Burqia/Tahreeb context (videos 01-10): a supporting card alongside an Ace (hand shape).
   -- Endgame context (video 35, this code): the "I claim the rest" declaration. Same word, different meaning.
   ```

2. **(IMPORTANT — CLAUDE.md fix)** In `CLAUDE.md` line 41, change:
   - FROM: "**SWA (سوا)** with ≤3 cards = instant claim; with 4+ cards = permission flow with 5-second auto-approve."
   - TO: "**SWA (سوا)** with ≤3 cards = instant claim per Saudi rule (v0.5.17 routes through display window for visibility); with 4+ cards = permission flow per Saudi rule. The 5-second auto-approve timer (`K.SWA_TIMEOUT_SEC`) is an **addon-UX construct** not present in the source video — it prevents deadlock from absent humans. Saudi-strict deterministic-or-bust: failed proof = qaid penalty."

3. **(OPTIONAL)** In `glossary.md`, add a SWA disambiguation entry covering both senses with their respective video sources.

**Two-hand-SWA partner-cooperative case** (currently rejected by `R.IsValidSWA` adversarial recursion): this is a known v0.5.17 trade-off (over-strict) and out of scope for this naming reaudit. Open as a separate review item — may warrant a relaxation to "partner plays adversarially-but-allows-mandated-cooperation" if Hokm two-hand SWAs are observed to fail too often.

---

## Confidence

**HIGH** on:
- Naming verdict (A — code naming is correct, just polysemous in source language).
- Mechanism verdict on instant/4-card/5+-card thresholds, deterministic-or-bust, qaid penalty.
- 5-second timer being invented (zero source matches; explicit code comment confirms user-requested).
- Verbatim Arabic quotes (re-checked against SRT line numbers).

**MEDIUM** on:
- Two-hand-SWA cooperative-partner case being a real divergence — code's adversarial-partner recursion is stricter than #35's "trust partner will come" guidance, but the v0.5.17 design comment claims this is intentional. Worth a separate audit item.

**LOW / not addressed**:
- Whether the `≤3 cards instant → routed-through-window` UX choice causes any subtle bug (e.g. takweesh window opening on a trivially-valid claim). Not investigated; orthogonal to the naming question.

---

## Sources cross-referenced

- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_A_tahreeb_cluster1.md` — Rules 19, 26, 37, 39, 58; Open Ambiguity #1; Notes-for-Phase-2 SWA bullet.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_I_melds_swa_scoring.md` — Section B (B1–B21), with B10 / B11 / B13 / B21 most directly answering the user's question; D4 (5-sec timer null finding).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_B_bargiya_discover.md` — Rules 6, 7, 8, 16, 17 (SWA prior conditional on early/late game; Bargiya-needs-swa as hand-shape precondition).
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\IMJIrhW4qOA_35_swa_term_detailed.ar-orig.srt` — direct verbatim verification at lines 24, 44, 54, 104, 114, 124, 184, 214, 504, 584, 894, 2204, 2244, 2253, 2404, 2414, 2944, 2964, 2974, 2984, 3104.
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — lines 192–206 (MSG_SWA family), 270–277 (`K.SWA_TIMEOUT_SEC`).
- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 2463–2576 (`N.LocalSWA`), 2630–2660 (`N._OnSWAReq`).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — lines 349–467 (`R.IsValidSWA`).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — lines 3679–3763 (`Bot.PickSWA`).
- `C:\CLAUDE\WHEREDNGN\CLAUDE.md` — line 41 (the SWA description that needs the timer-clarification edit).
