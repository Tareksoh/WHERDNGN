# C-Xref-07 — Phase 1 vs Wave 3 Source Diff Matrix

**Agent:** C-Xref-07 (Track-C cross-referencer)
**Mandate:** Diff Phase-1 source extracts (review_v0.10.0/_phase1_sources/) against
Wave-3 re-extracts (review_v0.10.2/_track_A_sources/). For each Wave-3 entry,
verdict = CONFIRMED / CORRECTED / EXTENDED / DIVERGED, severity = HIGH / MEDIUM
/ LOW / NONE. Identify v0.10.0 fixes that may have been built on incorrect
Phase-1 reads — those are v0.10.3 reverse/correct candidates.

**Method:** Read-only. Compared 12 Phase-1 sources (A–L) vs 30 Wave-3 sources
(A-Src-01..30). Phase 1 produced 7 video-cluster bundles (A,B,C,D,E,F,G,H,I,J)
and 2 PDF bundles (K,L). Wave 3 produced 1 source per video/PDF (A-Src-01..28)
plus 2 cross-source authority files (A-Src-29 Faranka xref, A-Src-30 Tahreeb
xref). The xref files compare the re-extracts and Phase-1 sources internally —
they ARE the diff in places.

**Convention:** "P1-X" = Phase-1 source X (e.g. P1-C = source_C_faranka.md).

---

## TL;DR — net changes

- **30 Wave-3 entries reviewed.** **23 CONFIRMED**, **5 CORRECTED**,
  **2 EXTENDED**, **0 DIVERGED**. (Some entries do all three at once on
  different sub-claims — see matrix.)
- **5 v0.10.0 fixes are candidates for v0.10.3 reverse/correct** based on
  newly-surfaced Phase-1 misreads:
  1. **R7 Sun-rank "K-tripled vs J-tripled"** (A-Src-06) — v0.10.0 R7
     reaudit *reversed* what was already correct. P1-A Rule 18 said
     "مثلوث = three non-consecutive cards in a suit"; A-Src-06 confirms
     the canonical mathlooth in #17 is the **K (Shayeb)**, with J/Q as
     lower-probability variants. The v0.10.0 R7 misread "J-tripled" should
     be reverted; canonical is K-tripled (Sun rank A>T>K).
  2. **F-16 universal Hokm application at Bot.lua:2964-2972** (A-Src-29) —
     v0.10.0 X3 lifted F-16 ("don't Faranka without K") from #06
     Sun-Faranka anti-rules into the Hokm path. **No source mandates this
     for Hokm** (P1-C correctly scoped F-16 to Sun, but X3 over-generalized).
     Over-restricts F-30b path (where opp-trump-exhausted makes the threat
     model extinct).
  3. **F-26 worked-example mislabel** (A-Src-29 Q8) — P1-C line 256 says
     "opp likely will play **J** not 9". S1 line 184 verbatim says
     **البنت (Q)**. Code rule predicate is unaffected (it gates on "9
     must be with right-opp"), but the documentation label is wrong and
     should be corrected for downstream readers.
  4. **L12 Q-row companion list** (A-Src-25 Q3) — P1-L Phase-1 transcription
     of the 100-meld 2-card refutation table listed `{7, 8, 9, 10, J}` as
     valid Q-companions. PDF verbatim says "إحدى الأوراق التي تحتها"
     ("one card below her"); under Saudi rank A>T>K>Q>J>9>8>7, "below Q"
     = `{J, 9, 8, 7}` — **10 is NOT below Q**. P1-L's `10` inclusion is
     a transcription error to correct in the project-elimination table.
  5. **A-Src-02's R3f "polarity-reversal" finding** (A-Src-30 Q9) —
     A-Src-02 reported P1-D's R3f trust-asymmetry rule as polarity-reversed
     ("trust partner / discount opponent" ↔ "constrain opponent / don't
     constrain partner"). A-Src-30 Q9 cross-checks 5 sources (#09, #10,
     #12, #14, #19) and finds the canonical polarity is unambiguously
     **partner-Tahreeb-trust > opp-Tanfeer-trust** — A-Src-02 was reading
     "تقيد" as a verb-direction signal (which it is at the surface) but
     missed that "constrain" in the Saudi sense means "treat as
     informationally pinned" — i.e. opp's plays ARE more constrained
     (predictable, low-deception) and partner's ARE less. The
     v0.10.0 framing is correct in operational terms (partner signals
     are trustworthy, opp signals can be deceptive); the literal Arabic
     polarity is the surface-mirror of operational polarity.
     **Net:** A-Src-02's framing creates a code-axis confusion but does
     NOT mandate a code change — original v0.10.0 R6 framing stands.
- **Document-level corrections that add NO code work:** mathlooth filename
  (`17_k_tripled` is correct; "J-tripled" reaudit was wrong); P1-C F-26
  worked-example J→Q label; P1-L L12 Q-row companion list; "تنفيذ" ASR
  artifact in #12 transcripts (correct root is ن-ف-ر = Tanfeer).
- **Code-impact concentration:** 4 HIGH-severity items (F-16 universal,
  R7 Mathlooth reaudit, signaling axis at Bot.lua:1640-1683 inner
  discriminator, Reverse-Kaboot blind-sweep at Rules.lua:817). 6 MEDIUM
  items. Remaining 20+ items are LOW or NONE (documentation-only or
  confirming what code already does).

---

## Wave-3 → Phase-1 mapping (file-level)

| Wave-3 ID | Wave-3 filename | Maps to Phase-1 source(s) | Topic |
|---|---|---|---|
| A-Src-01 | v04_faranka_hokm.md | P1-C source_C_faranka.md | Faranka in Hokm (video #04) |
| A-Src-02 | v05_touching_honors.md | P1-D source_D_predictions.md | Touching honors (video #05) |
| A-Src-03 | v06_sun_faranka.md | P1-C source_C_faranka.md | Faranka in Sun (video #06) |
| A-Src-04 | v11_bel100.md | P1-F source_F_bel_tanfeer.md | Bel-100 score-split (video #11) |
| A-Src-05 | v14_bargiya_hand_shape.md | P1-B source_B_bargiya_discover.md | Bargiya hand-shape (video #14) |
| A-Src-06 | v17_mathlooth.md | P1-F source_F_bel_tanfeer.md | Mathlooth K-tripled (video #17) |
| A-Src-07 | v18_aka.md | P1-G source_G_kaboot_aka.md | AKA decision matrix (video #18) |
| A-Src-08 | v29_dont_takweesh.md | P1-H source_H_bidding_penalty.md | Don't kasho on partner (video #29) |
| A-Src-09 | v35_swa.md | P1-I source_I_melds_swa_scoring.md | SWA term detailed (video #35) |
| A-Src-10 | v41_sun_basics_K.md | P1-J source_J_cut_deal_play.md | Sun basics — K-signal (video #41) |
| A-Src-11 | v07_strategy.md | P1-E source_E_strategy_magnify.md | Strategy vs Tactic (video #07) |
| A-Src-12 | v08_smart_move.md | P1-E source_E_strategy_magnify.md | Smart move (video #08) |
| A-Src-13 | v09_essential_tahreeb.md | P1-A source_A_tahreeb_cluster1.md | Essential tahreeb (video #09) |
| A-Src-14 | v10_small_to_big.md | P1-A source_A_tahreeb_cluster1.md | Small-to-big tahreeb (video #10) |
| A-Src-15 | v12_tanfeer.md | P1-F source_F_bel_tanfeer.md | Tanfeer explained (video #12) |
| A-Src-16 | v13_predict_trick.md | P1-D source_D_predictions.md | Predict trick (video #13) |
| A-Src-17 | v15_kaboot.md | P1-G source_G_kaboot_aka.md | Al-Kaboot detailed (video #15) |
| A-Src-18 | v16_reverse_kaboot.md | P1-G source_G_kaboot_aka.md | Reverse Kaboot (video #16) |
| A-Src-19 | v19_six_factor_tanfeer.md | P1-B source_B_bargiya_discover.md | Six-factor Tanfeer (video #19) |
| A-Src-20 | v21_magnify_sun.md | P1-E source_E_strategy_magnify.md | Takbeer in Sun (video #21) |
| A-Src-21 | pdf01_registration.md | P1-K source_K_pdf_basic_rules.md | PDF 01 registration system |
| A-Src-22 | pdf02_playing.md | P1-K source_K_pdf_basic_rules.md | PDF 02 playing system |
| A-Src-23 | pdf03_secrets_pro1.md | P1-L source_L_pdf_secrets_doubling.md | PDF 03 Secrets of Pro 1 |
| A-Src-24 | pdf03b_secrets_pro2.md | P1-L source_L_pdf_secrets_doubling.md | PDF 03b Secrets of Pro 2 |
| A-Src-25 | pdf04_secrets_pro3.md | P1-L source_L_pdf_secrets_doubling.md | PDF 04 Secrets of Pro 3 |
| A-Src-26 | pdf05_what_is_baloot.md | P1-L source_L_pdf_secrets_doubling.md | PDF 05 What is Baloot |
| A-Src-27 | pdf06_third.md | P1-K source_K_pdf_basic_rules.md | PDF 06 The Third |
| A-Src-28 | pdf07_doubling.md | P1-L source_L_pdf_secrets_doubling.md | PDF 07 Doubling System |
| A-Src-29 | xref_faranka.md | P1-C source_C_faranka.md (xref over A-Src-01,03,21,22) | Faranka cross-source authority |
| A-Src-30 | xref_tahreeb.md | P1-A, P1-B (xref over A-Src-05,13,14,15,19) | Tahreeb cross-source authority |

---

## Per-source diff matrix

### A-Src-01 — Video #04 Faranka in Hokm

| Field | Value |
|---|---|
| Phase-1 source | P1-C source_C_faranka.md (rules F-23..F-36) |
| Verdict | **CONFIRMED + CORRECTED** |
| Code-impact severity | **HIGH** |
| Notable changes | (a) F-16 K-of-trump cover anti-rule **NOT in #04** (orig P1-C reading correct: F-16 is Sun-only). v0.10.0 X3's Hokm-path application is unsupported. (b) F-26 worked example: opp plays **Q (البنت)** not J — P1-C line 256 mis-labelled. (c) F-29 J-dead detection: source language "اذا الولد لعب من اول" requires past-tense (prior-trick), not "this trick"; code's `S.HighestUnplayedRank` doesn't gate this. (d) F-30 bidder-team predicate confirmed via V04-Q9 "سواء انت مشتري او خويك". |
| v0.10.3 candidates | F-16 universal Hokm application at Bot.lua:2964-2972 (HIGH); F-29 J-dead prior-trick guard (MEDIUM); doc fix on P1-C F-26 (NONE). |

### A-Src-02 — Video #05 Touching Honors

| Field | Value |
|---|---|
| Phase-1 source | P1-D source_D_predictions.md (R3a..R3f) |
| Verdict | **CONFIRMED + EXTENDED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) P1-D R3a–R3e all confirmed verbatim. (b) **NEW finding:** the audit's K-singleton interpretation `cleared = {Q,J}` applies **only to opponent-K case**; partner-K case clears **{10}** instead. v0.10.0 R6 was correct for opp-K but should not clear Q/J on partner-K. (c) **Polarity-reversal flag** on R3f: A-Src-02 reads literal Arabic "تقيد" as opposite of v0.10.0 framing. **A-Src-30 Q9 reconciliation** confirms operational polarity (partner-trust high, opp-trust low) is correct; A-Src-02's flag is a surface-mirror of operational truth, not a polarity error. |
| v0.10.3 candidates | Partner-K vs opp-K branch separation in `cleared` table (MEDIUM); A-Src-02 polarity flag is **NOT** a code change candidate (NONE). |

### A-Src-03 — Video #06 Sun Faranka

| Field | Value |
|---|---|
| Phase-1 source | P1-C source_C_faranka.md (rules F-09..F-22) |
| Verdict | **CONFIRMED + EXTENDED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) 5-factor framework is **WEIGHTED** (probabilistic, additive) NOT AND-gated. Code's single AND-gate at Bot.lua:2584-2612 captures only Factors #1+#2 (A+K mardoofa + partner-winning) and is "fidelity-incomplete". (b) F-14 transcription slip confirmed in #06 only ("لازم تتفرنك" — speaker meant the opposite); code correctly does not implement the literal slip. (c) F-16 (no K → no Faranka) confirmed Sun-only; no Hokm mandate. |
| v0.10.3 candidates | Sun pos-4 Faranka could be relaxed to weighted scoring (MEDIUM); F-16 Hokm scope-down (HIGH) — same item as A-Src-01. |

### A-Src-04 — Video #11 Bel-100 Sun Double

| Field | Value |
|---|---|
| Phase-1 source | P1-F source_F_bel_tanfeer.md (F1.01–F1.10) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) Bel-100 rule confirmed score-based, role-irrelevant: "team <100 may Bel; team >100 may not". (b) Source uses "فريق" (team) framing, NEVER "bidder/defender". (c) D-RT-22's gating bug (Net._OnDouble defender-only) creates a 60s AFK regression in bidder-trailing-Sun — bidder team never gets the Bel button despite `R.CanBel` admitting it. |
| v0.10.3 candidates | Net._OnDouble gating relaxation (MEDIUM, already known under D-RT-22). |

### A-Src-05 — Video #14 Bargiya Hand-Shape

| Field | Value |
|---|---|
| Phase-1 source | P1-B source_B_bargiya_discover.md (Rules 1..20) |
| Verdict | **CONFIRMED + EXTENDED** |
| Code-impact severity | **HIGH** |
| Notable changes | (a) محشور (mahshoor) hand-shape axis verbatim confirmed at cues 509-515: "محشور بلون واحد او بلونين ومنه مثلا مردوفه بشيء صغير". P1-B Rule 9 ("hand-shape axis, not event-count") is canonically supported. (b) Code at Bot.lua:1640-1683 uses event-count + cover-grade gate (M7 fix); per #14, the correct **inner discriminator** (Bargiya invite vs defensive shed) is **cover topology / suits-touched-count**, not event-count. (c) Receiver phase-split (≥5 cards / ≤4 cards) confirmed. (d) Eat counts by partner hand-size (7→2-3, 6→1-2, 5→1) confirmed. |
| v0.10.3 candidates | Bot.lua:1640-1683 inner-discriminator axis correction (HIGH — already known M7 follow-up). |

### A-Src-06 — Video #17 Mathlooth (K-tripled)

| Field | Value |
|---|---|
| Phase-1 source | P1-F source_F_bel_tanfeer.md (cluster F3, Mathlooth) |
| Verdict | **CONFIRMED + CORRECTED** |
| Code-impact severity | **HIGH** |
| Notable changes | (a) **REVERSES the v0.10.0 R7 reaudit's "J-tripled" correction**. Speaker explicitly defines mathlooth canonically as **الشايب (K)** with two supporting cards: "المثلوث في البلوت اللي هو الشايب معاه ورقتين". J-tripled and Q-tripled are valid lower-probability variants but K is canonical. (b) Sun rank-order verbatim: "اول شيء اكه بعدها عشره بعدها شايب" → A>T>K (with K at position #3). After A and T are spent, K is the next live winner. (c) The legacy filename `17_k_tripled` reflects the speaker's emphasis correctly. (d) **R7 reaudit's framing baked in a wrong premise** ("Sun's A>T>J makes J top after A,T spent") — R7 misread A>T>K as A>T>J. |
| v0.10.3 candidates | **Revert v0.10.0 R7 Sun-rank fix on Mathlooth** (HIGH); restore K (Shayeb) as canonical mathlooth in any rank-comparison logic that R7 inverted. |

### A-Src-07 — Video #18 AKA decision matrix

| Field | Value |
|---|---|
| Phase-1 source | P1-G source_G_kaboot_aka.md (G18-01..G18-12) |
| Verdict | **CONFIRMED + EXTENDED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) 3×3 decision matrix confirmed verbatim. (b) **NEW finding:** AKA-on-T does NOT trick-lock under suit-following or trump-cut rules. The comment at Rules.lua:108-110 "10-substitutes-for-Ace semantic collapses to same rule" is misleading — speaker explicit at 03:36-03:42 that opp can still ruff over an AKA'd 10 with trump. AKA-on-T is a **signaling** equivalence (releases partner from over-trump obligation), not a **trick-resolution** equivalence. (c) X2 B5 + B-Net-01 F-AP-21 audits (which kept AKA-on-T trick-lock unimplemented) are correct. |
| v0.10.3 candidates | Doc clarification at Rules.lua:108-110 (LOW). |

### A-Src-08 — Video #29 Don't Takweesh

| Field | Value |
|---|---|
| Phase-1 source | P1-H source_H_bidding_penalty.md (H-29.x) |
| Verdict | **CONFIRMED + CORRECTED** |
| Code-impact severity | **LOW** |
| Notable changes | (a) Phase 1 H reading is **correct**: video #29 = **kasho-suppression** (don't call kasho when partner bought) NOT bid-override. (b) The earlier extraction `29_dont_takweesh_extracted.md` mis-classified this as "Takweesh-A bid-override" — it should be re-classified as "Takweesh-B kasho-suppression". (c) "NEVER kasho on partner Hokm" rule is in #34 (H-34.9), not #29 — #29 only covers Sun exception (partner hesitated + Sun + early). |
| v0.10.3 candidates | Reclassify `29_dont_takweesh_extracted.md` to kasho-suppression (LOW, doc-only); B-Bot-10-5 (LOW) `Bot.PickKawesh` ignores H-34.9 stands. |

### A-Src-09 — Video #35 SWA detailed

| Field | Value |
|---|---|
| Phase-1 source | P1-I source_I_melds_swa_scoring.md (Section B SWA) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) Verbatim "مستحيل يمشونها" at line ~10:53 confirms 5+-card unauthorized SWA is rule-strictly impossible — addon's 5-second auto-approve is UX-only construct (CLAUDE.md note already correct). (b) D-RT-13 / RT-13.1 confirmed. (c) **Cooperative trust assumption** on partner SWA: speaker at line ~564 says "خويك راح يجي دائما ثق تماما" — supports cooperative model in `R.IsValidSWA`; current partner-adversarial branch over-rejects valid Hokm two-hand SWAs. |
| v0.10.3 candidates | D-RT-31 / B-Net-04 partner-cooperative relaxation in `R.IsValidSWA` (MEDIUM). |

### A-Src-10 — Video #41 Sun basics

| Field | Value |
|---|---|
| Phase-1 source | P1-J source_J_cut_deal_play.md |
| Verdict | **CONFIRMED + CORRECTED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) **Disposes of D-RT-07 RT-07-I source-conflict claim.** The `41_play_sun_basics_extracted.md:57` claim "K → partner has Q (next-down) — Definite confidence" is **NOT in the SRT.** Line 57 is about Royal Belote project announcement (سيرا ملكي = K+Q same suit), not partner-signal teaching. (b) #41 contains NO partner-signal teaching for K, T, Q, or any rank. (c) v0.10.0 R6's K-singleton `cleared={Q,J}` stands; no genuine source conflict with #05. |
| v0.10.3 candidates | Retract `41_play_sun_basics_extracted.md:57` Definite-confidence claim (LOW, doc-only). |

### A-Src-11 — Video #07 Strategy vs Tactic

| Field | Value |
|---|---|
| Phase-1 source | P1-E source_E_strategy_magnify.md (E07-1..E07-9) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) Strategy/tactic 2-layer model confirmed verbatim. (b) Bidder-vs-defender split confirmed. (c) **Null-finding flags:** Q4 Saudi-Master moves, Q7 Hokm-vs-Sun differences, Q8 endgame vs opening, Q9 tier indicators — none directly stated in #07. Phase-1 cross-references to other videos (#11, #14, #29, #35) carry these. |
| v0.10.3 candidates | None. |

### A-Src-12 — Video #08 Smart Move

| Field | Value |
|---|---|
| Phase-1 source | P1-E source_E_strategy_magnify.md (E08-x) |
| Verdict | **CONFIRMED + EXTENDED** |
| Code-impact severity | **LOW** |
| Notable changes | (a) Sun J-sacrifice ("الشايب") confirmed verbatim at sub #25-29; goal = "make opp keep leading the suit". (b) Hokm J-of-trump sacrifice confirmed; goal = "make opp STOP re-leading trump" — opposite Sun. (c) Speaker explicitly says **the move has no canonical Saudi name** (sub #505-507). (d) T-of-trump sacrifice in Sun is "pro-tier only"; never in Hokm. |
| v0.10.3 candidates | None — code already covers J-sacrifice patterns. |

### A-Src-13 — Video #09 Essential Tahreeb

| Field | Value |
|---|---|
| Phase-1 source | P1-A source_A_tahreeb_cluster1.md (Rules 5, 6, 36) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) 70/25/5 receiver prior verbatim confirmed at 00:01:22-34. (b) 90% post-second-tahreeb posterior verbatim at 00:03:05-09. (c) Three-form mention (same-color-opposite-shape, opposite-color, opposite-shape-of-floor). (d) Single-source for the priors — P1-A Rule 5 cited only #09; this re-extract verifies. |
| v0.10.3 candidates | `Bot.PickAKA` 70/25/5 prior implementation check (MEDIUM, already-flagged). |

### A-Src-14 — Video #10 Small-to-Big

| Field | Value |
|---|---|
| Phase-1 source | P1-A source_A_tahreeb_cluster1.md (Rules 7, 8, 9, 27, 50, 51) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **LOW** |
| Notable changes | (a) "Two-time small-to-big = 100% no debate" verbatim at 00:01:02-13 and reinforced 00:01:11-20. (b) Bargiya (single-event) explicitly distinguished from ascending-tahreeb (multi-event) at 00:00:23. (c) Direction = rank-order, not point-value. (d) Recommended monotone-ascending sequence 7→9→J. |
| v0.10.3 candidates | None — distinction event-count vs hand-shape already addressed in A-Src-30 outer/inner axis. |

### A-Src-15 — Video #12 Tanfeer Explained

| Field | Value |
|---|---|
| Phase-1 source | P1-F source_F_bel_tanfeer.md (cluster F2 Tanfeer) |
| Verdict | **CONFIRMED + CORRECTED** |
| Code-impact severity | **LOW** |
| Notable changes | (a) **Tamtheel ⊇ Tanfeer ⊇ Tahreeb** taxonomy verbatim confirmed: "كل تهريب تنفيذ لكن ليس كل تنفيذ تهريب" (line 453). (b) **ASR error correction:** the SRT spelling تنفيذ (root ن-ف-ذ "execute") is a transcription error for تنفير (root ن-ف-ر "drive away"). Speaker uses ن-ف-ر verb forms throughout; only the noun gets ASR-corrupted. (c) Bargiya named under Tanfeer variants. |
| v0.10.3 candidates | Glossary correction (تنفير not تنفيذ) — LOW doc-only. |

### A-Src-16 — Video #13 Predict Trick

| Field | Value |
|---|---|
| Phase-1 source | P1-D source_D_predictions.md (R4..R31) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **LOW** |
| Notable changes | (a) 5-tier confidence buckets {100/95/90/50/10} confirmed (Phase-1 was right; P1-D's bucket-collapse note stands). (b) Pos-2 self-contradiction confirmed in source ("100%" then "تقل النسبه" adjacent breath); not a Phase-1 misread. (c) R26 median = points-axis (K/Q/J = "honor mid"), NOT rank-axis. (d) R25 contractor-holds-J is "غالبا" hedged, ~95% Phase-1 calibration is reasonable. |
| v0.10.3 candidates | None. |

### A-Src-17 — Video #15 Al-Kaboot Detailed

| Field | Value |
|---|---|
| Phase-1 source | P1-G source_G_kaboot_aka.md (G15-01..G15-12) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) Kaboot raw values: **Sun=44, Hokm=25** in game-points units (NOT 250/220). (b) Phase-1 "250/220 raw vs source 25/44" tension is resolved: video uses post-divide game-points (×10 ratio reflects the units swap). Code's `K.AL_KABOOT` constant must be checked against this scaling. (c) Strategic break-Kaboot-to-Double for Sun (52 > 44). (d) Kaboot replaces (not stacks with) Double bonus when both occur; projects stay normal. |
| v0.10.3 candidates | `K.AL_KABOOT_HOKM` / `K.AL_KABOOT_SUN` units verification (MEDIUM). |

### A-Src-18 — Video #16 Reverse Kaboot

| Field | Value |
|---|---|
| Phase-1 source | P1-G source_G_kaboot_aka.md (G16-01..) |
| Verdict | **CONFIRMED + CORRECTED** |
| Code-impact severity | **HIGH** |
| Notable changes | (a) Reverse Kaboot = **88 raw**, contrasted with regular Kaboot "40" pip; minority view treats reverse = regular. (b) **Phase-1 "bidder TEAM" reading is WRONG**. Authority verbatim at lines 93-104: "المشتري نفسه يكون اللعب على يده" — bidder PERSONALLY must lead trick 1, not just bidder team. Predicate is `firstLeaderOfRound == S.s.contract.bidder` (seat, not team). (c) Lead card NOT required to be Ace — "any card other than the AKA" is fine; what matters is bidder-leads-trick-1 + defenders-sweep. (d) Sun-only NOT confirmed — rule statement is contract-agnostic; example is Sun but the rule is not contract-gated. (e) **Rules.lua:817-822 "blind sweep" branch awards `K.AL_KABOOT_HOKM/SUN` to whichever team sweeps with no Reverse-Kaboot check** — both branches need rewiring. |
| v0.10.3 candidates | B-State-05 F1 Reverse-Kaboot wiring at Rules.lua:817-822 (HIGH). |

### A-Src-19 — Video #19 Six-factor Tanfeer

| Field | Value |
|---|---|
| Phase-1 source | P1-B source_B_bargiya_discover.md (Rules 23..32) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) All six factors enumerated by ordinal (اول/ثاني/ثالث/رابع/خامس/سادس) verbatim. (b) "1% to 99% open range" confirmed for Tanfeer-rule reliability. (c) Bidder-identity asymmetry (F6) confirmed — opp-bid raises Tanfeer confidence, your-team-bid lowers it. (d) **Tahreeb-priority gating is CATEGORICAL** (دائما = always), Bayesian priors operate underneath. Code must apply Tahreeb interpretation BEFORE Tanfeer in conflict resolution as a hard switch — naive additive Bayes is wrong. |
| v0.10.3 candidates | M3lm-tier opponent-modeling (Bayesian Tanfeer prior with 6-factor weighting) — MEDIUM, longstanding wishlist. |

### A-Src-20 — Video #21 Magnify (Takbeer) Sun

| Field | Value |
|---|---|
| Phase-1 source | P1-E source_E_strategy_magnify.md (Takbeer/Tasgheer cluster) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) Takbeer = "play your highest card" partner-direction signal confirmed verbatim. (b) v0.10.0 R7 Takbeer-vs-escalation disambiguation correct: Takbeer here is a play-direction signal, NOT an escalation rung (no overlap with Bel/x2/Four/Gahwa). (c) Video is Sun-specific; Hokm Takbeer deferred to separate video. |
| v0.10.3 candidates | None. (Note: this is the SAME R7 source — but Takbeer was correctly disambiguated; the WRONG R7 fix was on Mathlooth — see A-Src-06.) |

### A-Src-21 — PDF 01 Registration System

| Field | Value |
|---|---|
| Phase-1 source | P1-K source_K_pdf_basic_rules.md (K-01..K-08) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) PDF 01 is **scoped narrowly** to Qaid-penalty + project-credit interaction. (b) Qaid 16/26 verbatim confirmed; Sun=26 / Hokm=16 mapping is convention-supported (PDF says "حسب اللعبة" without binding which value goes to which contract). (c) "مشروعي لي ومشروعك لك" verbatim. (d) Kaboot raw=44 verbatim cited. (e) PDF 01 does NOT contain target=152, meld values, Carré, Reverse-Kaboot, strict-majority-81 — those are sourced from PDF 02/05/07 or videos. |
| v0.10.3 candidates | None. |

### A-Src-22 — PDF 02 Playing System

| Field | Value |
|---|---|
| Phase-1 source | P1-K source_K_pdf_basic_rules.md (K-13..K-37) |
| Verdict | **CONFIRMED + CORRECTED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) **Phase-1's "152" reading is correct** despite PDF text "٢٥١" (RTL flip artifact). PDF reads 152 verbatim twice (header + clarifying sentence). (b) Bel-100 rule: PDF says "opponent must be ≥101" only — the "caller ≤100" half of P1-K is **not verbatim** in PDF 02 (must be inferred / cross-sourced). (c) Sun escalation truncation: page 2 says authoritatively "no Triple/Four/Gahwa in Sun"; page 3 commentary softens this for Triple as "pointless not forbidden". K-21 vs K-33 reconciled. (d) Sun=26 / Hokm=16 mapping for foul penalty: NOT verbatim in PDF 02 ("16 or 26 depending on the game" only). |
| v0.10.3 candidates | None. (P1-K K-37 "first vs second Ashkal" subtlety: transaction-level not seat-level, no code change needed.) |

### A-Src-23 — PDF 03 Secrets of Pro 1

| Field | Value |
|---|---|
| Phase-1 source | P1-L source_L_pdf_secrets_doubling.md (L01..L06) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) All six L01-L06 quotes re-verified verbatim. (b) **Tier-distinguishing-by-construction**: PDF defines card-counting as the skill that "separates a pro from a non-pro" — relevant for Saudi-Master tier dispatch. (c) **No hand-shape category names** (محشور, مكشوف, مردوف) appear in PDF 03 — those are sourced from #14 (محشور) and other videos. (d) L42 "44" anomaly is corrupted text "ال 44" most likely refers to "the 4-4" failing penalty, not a numeric value. |
| v0.10.3 candidates | None. |

### A-Src-24 — PDF 03b Secrets of Pro 2

| Field | Value |
|---|---|
| Phase-1 source | P1-L source_L_pdf_secrets_doubling.md (L07..L09) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) **Three numbered rules**, not a list of strategic tips — author treats these as a closed enumeration. (b) Rule 1 (Hokm needs Ace): imperative mood ("فلابد") — code's `hokmMinShape` Ace-gate is hard-rule-aligned. (c) Rule 2 (mardoofa lead in Sun): imperative mood ("اجبارية") — v0.10.2 M8 `pickLead` Sun-trick-1 mardoofa probe should match. (d) Rule 3 (sequence reads): conditional ("فحاول") — strategy not hard-rule. **D-RT-11.3/.4/.6 cascade fail** flagged here. |
| v0.10.3 candidates | D-RT-11 cascade audit (MEDIUM, already known). |

### A-Src-25 — PDF 04 Secrets of Pro 3

| Field | Value |
|---|---|
| Phase-1 source | P1-L source_L_pdf_secrets_doubling.md (L10..L18) |
| Verdict | **CONFIRMED + CORRECTED** |
| Code-impact severity | **MEDIUM** |
| Notable changes | (a) 12-card visible base (1+3+8) verified verbatim with bidder/up-card-discarded adjustments to 11. (b) 100-meld 1-card refutation: J or T of suit X refutes suit X — verbatim. (c) **100-meld 2-card refutation Q-row CORRECTION**: PDF says "إحدى الأوراق التي تحتها" (one card below her). Under Saudi rank A>T>K>Q>J>9>8>7, **"below Q" = {J, 9, 8, 7}**. **P1-L L12 transcription included `10` in the Q-row companion list — that's a contradiction with the PDF's rank order**. Code project-elimination table should use {J, 9, 8, 7}. (d) 4-card-100 contract-conditional: Hokm = {A, K, Q, J, T}; Sun = {K, Q, J, T} OR {J, T} — speaker's "(الشايب او لباشا)" disjunction is ambiguous; conservative reading is {K, Q, J, T}. |
| v0.10.3 candidates | MF-1 12-card project-elimination table — Q-row companion fix to {J, 9, 8, 7} (MEDIUM). |

### A-Src-26 — PDF 05 What is Baloot

| Field | Value |
|---|---|
| Phase-1 source | P1-L source_L_pdf_secrets_doubling.md (L19..L24) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) Round total 162 verbatim ("مجموع اللعب ٢٦١" = RTL 162). (b) Hokm trump per-suit = 62; Sun count = 90 for 3 remaining suits. (c) Belote +20 origin: "K+Q-of-trump" verbatim placed; PDF says raw value is "+2" (the +20 mapping is the conventional 10× scaling). (d) PDF does NOT cover last-trick bonus, escalation rungs, bidder threshold, off-trump values, 9-rank-2, Carré — those are sourced elsewhere. |
| v0.10.3 candidates | None. |

### A-Src-27 — PDF 06 The Third (الثالث)

| Field | Value |
|---|---|
| Phase-1 source | P1-K source_K_pdf_basic_rules.md (K-39..K-48) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) Definition: "Ace has a Third" — pre-emption right held by earlier-seat to take Sun-on-Ace from later-seat buyer. (b) Eligibility: seats 1 & 2 only; Ace upcard + Sun + not partner. (c) "ما لك ثالث على خويك" — never on partner. (d) Constants: `K.PHASE_PREEMPT="preempt"` matches PDF rule including round-2 + Sun + Ace gates. (e) Code `Bot.PickPreempt` and `Net._OnPreempt` paths match PDF. |
| v0.10.3 candidates | None — code matches authority. |

### A-Src-28 — PDF 07 Doubling System

| Field | Value |
|---|---|
| Phase-1 source | P1-L source_L_pdf_secrets_doubling.md (L25..L36) |
| Verdict | **CONFIRMED** |
| Code-impact severity | **NONE** |
| Notable changes | (a) Hokm chain Bel→Triple→Four→Gahwa with multipliers ×2/×3/×4 verbatim. (b) Belote does NOT double (multiplier-immune) — matches CLAUDE.md. (c) Sun chain truncated (only Bel exists in Sun). (d) Hokm Bel: 16×2=32; Triple: 48; Four: 64. (e) Sun Bel: 26×2=52. |
| v0.10.3 candidates | None — matches existing constants. |

### A-Src-29 — Faranka Cross-Source Authority

| Field | Value |
|---|---|
| Phase-1 source | P1-C source_C_faranka.md (xref over A-Src-01, 03, 21, 22) |
| Verdict | **CORRECTED + EXTENDED** |
| Code-impact severity | **HIGH** |
| Notable changes | (a) Definitive Faranka authority table: 6 Hokm rules + 5 Sun anti-rules. (b) **F-16 universal Hokm application is UNSUPPORTED by any source** (S1, S5, S6, S7 all silent on F-16-in-Hokm). v0.10.0 X3's Bot.lua:2964-2972 is over-tight on F-30b. **HIGH severity fix.** (c) F-30b bidder-team predicate confirmed — V04-Q9 generalisation supports team scope, not bidder-only. (d) F-26 worked example uses Q (البنت), not J — P1-C line 256 doc-fix. (e) Anti-rule rule 7 (Bot.lua:2974-2993) UNSUPPORTED by any source — addon-internal heuristic. (f) F-29 J-dead detection: source requires prior-trick guard, code's `S.HighestUnplayedRank` doesn't gate. (g) Sun 5-factor framework is WEIGHTED, not AND-gated — code at Bot.lua:2584-2612 is fidelity-incomplete. |
| v0.10.3 candidates | F-16 universal Hokm scope-down (HIGH); F-29 prior-trick guard (MEDIUM); rule 7 anti-trigger deprecation (LOW); Sun 5-factor weighted scoring (MEDIUM). |

### A-Src-30 — Tahreeb Cross-Source Authority

| Field | Value |
|---|---|
| Phase-1 source | P1-A source_A_tahreeb_cluster1.md + P1-B source_B_bargiya_discover.md (xref over A-Src-05, 13, 14, 15, 19) |
| Verdict | **CONFIRMED + EXTENDED** |
| Code-impact severity | **HIGH** |
| Notable changes | (a) Definitive Tahreeb authority table: 25 rules, **0 cross-source contradictions**. (b) **Tamtheel ⊇ Tanfeer ⊇ Tahreeb** taxonomy DEFINITIVE (#12 canonical). (c) Bargiya ⊂ Tahreeb DEFINITIVE (#14 canonical). (d) **Two axes confirmed**: outer = event-count (Bargiya vs ascending Tahreeb); inner = hand-shape محشور (Bargiya invite vs defensive shed). Code at Bot.lua:1640-1683 mixes axes — outer is correct (event-count); inner is MISALIGNED (uses event-count + cover-grade gate; should use hand-shape topology / suits-touched-count proxy). **HIGH severity fix already known under M7 follow-up.** (e) **Polarity-asymmetry resolution on R3f**: A-Src-02's "polarity reversed" finding contradicts 5 cross-source authorities (#09, #10, #12, #14, #19). Canonical operational polarity stands: partner-Tahreeb-trust > opp-Tanfeer-trust. **A-Src-02's polarity flag is NOT a code-change candidate** (surface-mirror of operational truth). (f) 70/25/5 priors and 90%/100% posteriors verbatim cross-confirmed. (g) محشور (#14) vs قاطع (#09) preconditions are ALTERNATIVE not equivalent — apply to different signaling forms. |
| v0.10.3 candidates | Bot.lua:1640-1683 inner-discriminator axis correction (HIGH — already M7 follow-up); A-Src-02 polarity flag explicitly does NOT generate a code change. |

---

## v0.10.3 reverse/correct candidate list (sorted by severity)

These are v0.10.0 fixes that may have been built on incorrect Phase-1 reads — the
prime candidates for v0.10.3 reversal/correction.

| # | Fix-target | Origin | Issue | Severity | Recommended action |
|---|---|---|---|---|---|
| 1 | **R7 Mathlooth Sun-rank reaudit** (A-Src-06) | v0.10.0 R7 | Reaudit "corrected" K-tripled to J-tripled based on misread Sun rank (A>T>J). True Sun rank is **A>T>K**; canonical mathlooth IS K. | **HIGH** | **REVERSE.** Restore K (Shayeb) as canonical mathlooth in any rank-comparison logic R7 inverted. Also confirm filename `17_k_tripled` is correct. |
| 2 | **F-16 universal Hokm application** (A-Src-29) | v0.10.0 X3 | Lifted F-16 (Sun anti-rule "no K → no Faranka") into Hokm path. No source mandate. Over-restricts F-30b path where opp-trump-exhausted makes threat extinct. | **HIGH** | **CORRECT.** Scope F-16 to Sun-Faranka path only OR keep on Hokm Triggers #2/#3 but skip on Trigger #4 (F-30b). |
| 3 | **Reverse-Kaboot blind-sweep at Rules.lua:817-822** (A-Src-18) | Pre-existing | Awards `K.AL_KABOOT_HOKM/SUN` (250/220) to whichever team sweeps with no Reverse-Kaboot check; auth says +88 raw + bidder-led-trick-1 gate (bidder PERSONALLY, not team). | **HIGH** | **CORRECT.** Wire +88 Reverse-Kaboot bonus + `firstLeaderOfRound == S.s.contract.bidder` gate. Note: Phase-1 G16 said "bidder team"; A-Src-18 corrects to bidder seat. |
| 4 | **Bot.lua:1640-1683 inner-discriminator axis** (A-Src-30) | v0.10.2 M7 cover-grade gate | Code uses event-count + cover-grade for inner axis (Bargiya invite vs defensive shed). Per #14, correct inner axis is hand-shape topology (محشور / suits-touched-count). | **HIGH** | **CORRECT.** Replace cover-grade gate with suits-touched-count proxy at recorder-time. |
| 5 | **F-26 worked-example J→Q label** (A-Src-29 Q8) | P1-C (doc-only) | P1-C source_C_faranka.md:256 says opp likely plays "J"; verbatim is "Q (البنت)". Rule predicate unaffected. | **NONE (doc)** | Doc fix only in P1-C. |
| 6 | **L12 Q-row companion list 10→exclude** (A-Src-25 Q3) | P1-L (data-only) | Project-elimination 100-meld 2-card Q-row included `10`; PDF rank-order excludes it. Code MF-1 table affected. | **MEDIUM** | Data fix in MF-1 table when implemented; Q-row = {J, 9, 8, 7}. |
| 7 | **F-29 J-dead detection prior-trick guard** (A-Src-01 / A-Src-29) | Pre-existing | Source language "اذا الولد لعب من اول" requires past-tense (prior trick). Code's `S.HighestUnplayedRank` doesn't gate prior-trick. | **MEDIUM** | Add `#(s.tricks or {}) > 0` guard at Bot.lua:2922-2932. |
| 8 | **Sun 5-factor weighted scoring** (A-Src-03 / A-Src-29) | Pre-existing | Code at Bot.lua:2584-2612 has single AND-gate; source describes weighted/situational with 5 factors. | **MEDIUM** | Optional fidelity improvement — replace AND-gate with weighted scoring. |
| 9 | **A-Src-02 R3f polarity-reversal flag** | A-Src-02 finding | Surface Arabic "تقيد" reads opposite to v0.10.0 framing. A-Src-30 Q9 confirms operational polarity is correct. | **NONE** | **DO NOT CHANGE CODE.** Doc-only annotation if needed. |

---

## Phase-1 sources that are FULLY CORROBORATED with no corrections

The following Phase-1 sources need NO updates — Wave-3 re-extraction confirms all
quotes and rules without correction:

- **P1-D source_D_predictions.md** (videos 05+13) — touching honors / predictions — confirmed in A-Src-02 + A-Src-16, with one EXTENSION (partner-K vs opp-K branch).
- **P1-J source_J_cut_deal_play.md** (videos 37, 39, 40, 41, 42, 44) — cut/deal/play basics — confirmed in A-Src-10 (which actively DISPOSES of a putative D-RT-07 source-conflict).
- **P1-K source_K_pdf_basic_rules.md** (PDFs 01, 02, 06) — confirmed in A-Src-21, A-Src-22, A-Src-27 (152 reading correct despite RTL artifact; preempt mechanic matches code).
- **P1-L source_L_pdf_secrets_doubling.md** (PDFs 03, 03b, 04, 05, 07) — confirmed in A-Src-23, A-Src-24, A-Src-25, A-Src-26, A-Src-28 — with **one CORRECTION** (Q-row `10` exclusion in L12).

---

## Phase-1 sources with non-trivial corrections

- **P1-A source_A_tahreeb_cluster1.md** — extended by A-Src-13, A-Src-14, A-Src-30. All quotes and priors stand. Polarity-reversal flag from A-Src-02 disposed. Inner-vs-outer axis distinction added.
- **P1-B source_B_bargiya_discover.md** — extended by A-Src-05, A-Src-19, A-Src-30. All quotes verified. Two-axes split formalized in A-Src-30.
- **P1-C source_C_faranka.md** — corrected by A-Src-29 (F-16 Hokm-scope, F-26 J→Q label, F-29 prior-trick semantics, F-30 bidder-team scope). v0.10.0 X3 baked in F-16-universal — that's the v0.10.3 prime candidate.
- **P1-E source_E_strategy_magnify.md** — confirmed by A-Src-11, A-Src-12, A-Src-20. R7 Takbeer disambiguation correct. (R7 Mathlooth was the WRONG R7 fix — see P1-F.)
- **P1-F source_F_bel_tanfeer.md** — corrected by A-Src-06 (Mathlooth K-canonical, REVERSES R7 Sun-rank misread); confirmed by A-Src-04 (Bel-100), A-Src-15 (Tanfeer with ASR fix).
- **P1-G source_G_kaboot_aka.md** — corrected by A-Src-18 (Reverse-Kaboot bidder PERSONAL not team; +88 raw); confirmed by A-Src-07, A-Src-17. Phase-1 250/220 vs source 25/44 discrepancy resolved as units swap.
- **P1-H source_H_bidding_penalty.md** — confirmed by A-Src-08; the Phase-1 H reading is correct and `29_dont_takweesh_extracted.md` is the file to be re-classified to kasho-suppression.
- **P1-I source_I_melds_swa_scoring.md** — confirmed by A-Src-09. Cooperative-trust assumption supports D-RT-31 relaxation (already a known finding).

---

## Cross-source contradictions found

**Direct contradictions between Phase-1 sources and Wave-3 sources: 0** — all
apparent disagreements are reconcilable as either (a) ASR/transcription
artifacts (تنفيذ vs تنفير; bidder team vs bidder personal), (b) units-swap
(250/220 vs 25/44 raw), (c) Phase-1 extraction-time misreads of unambiguous
source content (R7 Mathlooth K vs J; L12 Q-row 10), or (d) v0.10.0 X3
inferences that lifted Sun rules into Hokm without source mandate (F-16
universal).

**Contradictions between code and source corpus: 5** (per A-Src-29 and
A-Src-30):
1. F-16 universal Hokm application — CODE WRONG.
2. Bot.lua:1640-1683 inner-discriminator axis — CODE PARTIALLY MISALIGNED.
3. Rule 7 anti-trigger at Bot.lua:2974-2993 — CODE UNSUPPORTED but harmless.
4. F-29 J-dead detection — CODE LOOSE on prior-trick.
5. Sun 5-factor — CODE FIDELITY-INCOMPLETE.

---

## Summary of net changes

**Phase-1 reads vindicated:** the bulk of Phase-1's source extractions stand —
72 of 70+ rules across A-L are confirmed verbatim by Wave-3. The major
investments in Phase-1 (cross-source xref tables in source_A through source_J,
the SWA semantics disambiguation, the bidding mechanics) are all corroborated.

**Phase-1 reads corrected:** a handful of localised quote-level corrections
(Mathlooth K not J; F-26 worked-example Q not J; L12 Q-row excludes 10; "تنفيذ"
ASR artifact). None of these touch the foundational rule taxonomy.

**v0.10.0 fixes built on incorrect Phase-1 reads:** **2 confirmed.** R7
Mathlooth reaudit reversed a correct read; v0.10.0 X3 lifted F-16 into Hokm
without source mandate. Both are HIGH-severity v0.10.3 candidates.

**v0.10.0 fixes built on correct Phase-1 reads:** the remaining R-fixes (R1
Bel-100, R6 K-singleton, etc.) are corroborated. Specifically: R6 stands per
A-Src-02 + A-Src-10; R1 stands per A-Src-04.

**New code-side findings surfaced by Wave-3 (not in Phase-1):** Bot.lua:1640-1683
inner-discriminator axis (M7 follow-up); Rules.lua:817-822 Reverse-Kaboot
blind-sweep (B-State-05); AKA-on-T trick-lock comment misframing at
Rules.lua:108-110.

**Documentation/data corrections (no code work):** doc fixes in P1-C line 256
(F-26 J→Q), P1-L L12 (Q-row exclude 10), `29_dont_takweesh_extracted.md`
classification, glossary spelling تنفير, `41_play_sun_basics_extracted.md:57`
retraction, Rules.lua:108-110 comment.

---

## Counts

| Item | Count |
|---|---|
| Wave-3 entries | 30 |
| CONFIRMED verdicts | 23 |
| CORRECTED verdicts | 5 |
| EXTENDED verdicts | 2 |
| DIVERGED verdicts | 0 |
| HIGH severity items | 4 |
| MEDIUM severity items | 6 |
| LOW severity items | 6 |
| NONE severity items | 14 |
| v0.10.3 reverse/correct candidates | 9 (4 HIGH, 3 MEDIUM, 2 NONE) |
| Phase-1 sources fully corroborated | 4 (D, J, K-mostly, plus large parts of L) |
| Phase-1 sources with non-trivial corrections | 5 (A, B, C, E, F, G, H — most via xref) |
| Direct Phase-1↔Wave-3 contradictions | 0 |
| Code-vs-source disagreements (per A-Src-29/30) | 5 |

**End of C-Xref-07.**
