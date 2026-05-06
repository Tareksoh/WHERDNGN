# Audit: decision-trees.md Section 3 — Opening Leads

**Codebase:** v0.7.2 (commit 93b1e9d)
**Target:** `Bot.lua` `pickLead` (actual line **1359**, doc says 1289 — **stale**)
**Section header itself says `pickLead` Bot.lua:1289; row's MAPS-TO says Bot.lua:953. Both stale.**

---

## Section 3 rule enumeration

Section 3 has exactly **one** row:

| # | WHEN | RULE | MAPS-TO note |
|---|---|---|---|
| 3.1 | Hold strength in side-suit X (e.g., a Ten as top); turn comes to you and partner has not yet captured a trick | Hold the strong card for END of round; lead a Tahreeb signal first instead | `pickLead` Bot.lua:953 strong-card-hold branch `(not yet wired)` |

---

## WIRED-CORRECT
*(none)*

## WIRED-WRONG
*(none)*

## NOT-WIRED

- **Rule 3.1 (strong-card-hold + Tahreeb-lead-instead)** — doc explicitly tags `(not yet wired)`. Confirmed: `pickLead` (Bot.lua:1359-2040) has no branch that gates side-suit Ten leads on partner-trick-history. The closest analogues — H-6 A-of-trump preservation (1762-1793, trump only), Tier-3 #11 boss-of-non-trump lead (1450-1459, the OPPOSITE — leads the boss), and lead-low-from-longest (1981-2020) — none implement "withhold a high side-suit T until end-of-round when partner has 0 tricks." No Tahreeb-signaling lead exists either; v0.5.10 wired only the **receiver** side (1461-1548).

## CODE-WITHOUT-DOC

`pickLead` contains substantial leading logic Section 3 does NOT enumerate:

1. **Trick-8 / sweep-pursuit boss lead** (1381-1444) — properly cross-referenced in Section 7 row 1.
2. **Trick-3 early Kaboot pursuit** (1383-1391) — Section 7 row 2; not in Section 3.
3. **Tier-3 #11 boss-of-non-trump lead** (1450-1459) — undocumented in any section row.
4. **Tahreeb/Section-9 RECEIVER reads** (1461-1548) — Section 8/9, not 3.
5. **Fzloky pref/avoid + opp-meld avoid (B-97)** (1556-1621) — Section 11-ish; no Section-3 row.
6. **Bidder-branch:** ace-exhaustion (B-96), trump-poor cash, conservativeOpp (B-57/B-71), J+9-trump-lock (B-98), H-6 A-of-trump preserve, trump-drought (B-82), saveHighTrump, single-opp-void boss (B-77), Sun shortest-suit lead (H-7) — none in Section 3.

## NOTES

- **Line refs stale**: Section 3 header says 1289; row says 953. Actual is **1359**. Both should be re-anchored per glossary recipe.
- Section 3 is severely under-populated for the volume of leading logic in `pickLead` (~680 lines).
- Tagging suggestion: add a CODE-WITHOUT-DOC table to Section 3 for sweep-pursuit, boss-lead, Sun shortest-suit, and the audit-tier defender heuristics — even if just as cross-references to other sections.
