# 17 — Bot.PickBid Hokm-branch deep audit (HEAD = v0.7.2)

Scope: `Bot.lua:942` (`Bot.PickBid`) + helpers `hokmMinShape` (594),
`suitStrengthAsTrump` (527), `sideSuitAceBonus` (566), `beloteSuit` (646),
plus thresholds `TH_HOKM_R1_BASE=42` / `TH_HOKM_R2_BASE=36` / `TH_SUN_BASE=50`
/ `BID_JITTER=±6` (lines 35–38).

## J + cover-trump + 1 side-Ace minimum (B-1 / B-2 / B-4)

PASS. `hokmMinShape` (594–611) is the canonical gate, called from both
R1 (line 1156) and R2 (line 1183). Logic:

- `not hasJ → false` (B-4 absolute floor, line 607).
- `count >= 4 and hasJ → true` (B-2 self-sufficient, line 608).
- `count == 3 and hasJ and hasSideAce → true` (B-1 minimum, line 609).
- All other shapes → false.

The 3-card-minimum-with-side-Ace is explicitly enforced. The post-v0.5.8
audit fix that added `hasSideAce` is in place; the original under-strict
gate (J + count >= 3) is gone.

## Trump-count tiers (video #26) in the strength formula

PARTIAL. `suitStrengthAsTrump` (527–561) implements per-card values
(J=20 / 9=14 / A=11 / T=10 / K=4 / Q=3 / 8=2 / 7=2) plus
`(count - 2) × 5` length bonus (line 549) and a +18/+10 J+9 pair
synergy (550–552). However, the **discrete tier bumps** demanded by
video #26 are *not* coded as named tiers:

- 0–2 trumps: filtered out by `hokmMinShape`, so effectively "pass". OK.
- 3+J min: implicit via base scoring, no explicit "min" floor reward.
- 4+ "أحلى وأحلى": no explicit bump beyond the linear +5/extra-card.
- 5+ Al-Kaboot candidate: NO tier bump, NO pursuit flag.

The continuous formula approximates the curve but the *qualitative*
tier semantics from the doc are absent. There is also a damp at
line 558 (`* 0.4`) for structurally weak no-J/short hands — this is
correct but unrelated to the tier-bump question.

## B-3 Kaboot pursuit flag (5+ trumps → set `S.s.pursuitFlagBidder`)

MISSING. `pursuit` only matches the trick-8 sweep-pursuit branch
(lines 1369–1438) inside `pickLead`. There is **no** write to
`S.s.pursuitFlagBidder` (or any equivalent) anywhere in `Bot.lua`,
and `Grep` over the repo finds the substring `pursuit` only in
`Bot.lua`. B-3 is unwired.

## Belote-mandatory branch (K+Q of trump)

PARTIAL. `beloteSuit` (646–658) detects K+Q. Both R1 (line 1162) and
R2 (line 1187) add `K.BOT_PICKBID_BELOTE_BONUS` (=20) to suit strength.
This nudges the bid but is NOT a hard mandatory override — a hand
with K+Q♠ that scores below `thHokmR2 - 20` still passes. Doc rule
B-6 ("Saudi MUST") expects unconditional Hokm-with-that-trump.

## 16-vs-26 failed-bid asymmetry as Hokm-default bias

PRESENT (lines 1198–1209). When both Hokm and Sun are viable in R2,
Sun must beat Hokm by `K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN` (=5) to
override; otherwise stays Hokm. This is the soft Hokm-vs-Sun pivot
the spec asks for. R1 still allows direct Sun via `sun >= thSun`
(line 1147) before considering Hokm-on-flipped (line 1155); the
bias only kicks in for R2 best-suit search.

## Verdict

`Bot.PickBid` Hokm branch is structurally sound on (1) and (5). It
is a graded continuous scorer rather than the doc's discrete tier
table — fine functionally, but (2) "أحلى وأحلى" + (3) Kaboot pursuit
flag + (4) Belote-mandatory are missing/under-strict. Highest-impact
gap: B-3 pursuit flag is entirely unimplemented.
