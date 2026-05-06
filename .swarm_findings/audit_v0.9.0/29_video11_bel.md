# Audit 29 — video #11 (Bel) extraction vs HEAD v0.9.0

**Sources:** `docs/strategy/_transcripts/11_bel_beginners_extracted.md`,
`21fN1IEm5Xk_11_bel_beginners.ar-orig.txt` (135 lines).
**Code:** `Rules.lua:489-498` (`R.CanBel`), `Net.lua:68-76`
(`N._SunBelAllowed`), `Bot.lua:3098-3107`, `K.PHASE_DOUBLE`.

## 1. Sun Bel-100 score asymmetry — verdict: ASYMMETRIC

Lines 35-50 are NOT the score-asymmetry paragraph (that segment is
the cards-revealed lockout). The actual rule is at **lines 120-127**.
Speaker text:

- L121-123: "في الصن لازم يكون فريق 100 نقطه او اعلى والفريق الثاني يكون اقل من 100 نقطه"
  — "In Sun, one team must be ≥100 AND the other below 100".
- L125-127: "الفريق اللي اقل من 100 لوحه حقيقيه يدبل لكن الفريق اللي فوق الميه ما يدبل في الصن"
  — "the <100 team really does Bel; the >100 team does NOT Bel in Sun".
- L128-130: "بعكس الحكم. الحكم مفتوح في الدبل سواء كنت اعلى من 100 او اقل" —
  Hokm has no gate.

The speaker **explicitly requires BOTH conditions**: a leading team
(≥100) AND a behind team (<100). He calls Bel a "comeback tool" for the
trailing side. Both-above-100 and both-below-100 are NOT addressed —
extracted-md L21 flags this honestly as "TBD".

This **matches `N._SunBelAllowed` (asymmetric: bidder ≥101 AND defender <101)**,
NOT `R.CanBel` (symmetric: only checks `mine < 100`). `R.CanBel` would
permit Bel when both teams are <100 (e.g. 60 vs 40); the speaker
neither permits nor forbids that case but his framing requires the
opponent to be ≥100 for the Bel-right to be triggered.

## 2. Cards-revealed lockout — PHASE_DOUBLE phase-gate

Lines 34-43: "اذا كشفت الورق خلاص وما قلت دبل ممنوع تدبل" — once cards are
revealed, Bel is forbidden. Speaker also gives the strict variant: any
of the 4 players revealing cards locks it (L40-41). The code uses
`K.PHASE_DOUBLE` (`Net.lua:858, 1308, 1839`) which closes when the
phase advances past dealing — this is a coarser proxy. It captures the
common case (phase exits before reveal) but does NOT model per-seat
reveal events; ext-md L12 flags `S.s.cardsRevealedBy[seat]` as `(not yet wired)`.
**Correct in spirit; missing strict-variant fidelity.**

## 3. Round-1 anti-grief — yes, explicit language

Lines 99-104: "ممكن تكون من اول الجيم اول مشترى بدايه الصكه لسه صفر صفر
فعشان كذا بعض الجلسات تمنع هذا الشيء" — "could be first game first bid still
0-0, so some sessions forbid this". Lines 130-132 reinforce for Hokm. Confidence:
`Sometimes` (variant). **Not wired** in HEAD (no round/cumulative-zero gate
in `R.CanBel` or `_SunBelAllowed`).

## 4. Cross-check: which matches video #11 better?

**`N._SunBelAllowed` matches the speaker's framing more faithfully**
(asymmetric, both-condition requirement). `R.CanBel` is a relaxed,
my-team-only check that the speaker neither states nor refutes. Audit-17
(`17_section2_now.md`) already flagged this divergence as STILL OPEN —
this re-verification confirms the divergence remains in HEAD v0.9.0.
