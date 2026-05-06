# 20 — Section 7 (Endgame / SWA / Al-Kaboot) re-audit at v0.9.0 (9c32c50)

**Verdict:** Aligned with 07_section7_endgame.md, plus rule-correctness verdict on the 63_multiplier_hunt flag.

## Rule-by-rule (HEAD 83717be on v0.9.0 files)

| # | Rule | Status | Code |
|---|---|---|---|
| 1 | Trick-3 pursuit (v0.5.19) | **WIRED** | `Bot.lua:1543-1554` — `sweepPursuitEarly = trickNum∈[3,7] AND isBidderTeam AND mySwept==trickNum-1`. Trick-8 boss-lead at 1581-1605 intact. |
| 2 | Reverse Al-Kaboot (+88) | **DEFERRED** | `Rules.lua:648-651` detects sweep via `trickCount.X==8` only; no `firstLeader==bidder` gate, no `K.AL_KABOOT_REVERSE`. Defender sweep routes to 250/220 (same as bidder). No new evidence v0.7.2→v0.9.0. Keep deferred. |
| 3 | SWA thresholds | **WIRED-LOOSE** | `Bot.PickSWA:3499` rejects hand>4 (5+ blocked). `Net.LocalSWA:2461` routes ALL claims through 5-sec permission window (post-v0.5.17). No ≤3-instant path. Stricter than #35; functionally safe. |
| 4 | SWA strict-deterministic (v0.5.17) | **WIRED** | `R.IsValidSWA` adversarial recursion preserved; `Bot.PickSWA:3520` delegates. Plus v0.5.21 Hokm top-trump safety net at 3534-3563. |
| 5 | Bargiya as SWA setup | **PARTIAL** | Sender wired at `Bot.lua:2470-2483` (T-1: Sun + void-in-led + A+cover + partner-bot). Receiver reads partner Bargiya at 1638-1709. **Own-Bargiya followup NOT WIRED.** |
| 6 | Defender qaid-bait | **NOT-WIRED (intentional)** | Doc marks "Defensive note only". |
| 7 | Multiplier-vs-Kaboot trade-off | **NOT-WIRED** | Grep `MULT_BEL`/`sabotage`/`abandon` in `Bot.lua` = zero. |

## Kaboot multiplier verdict (the 63_multiplier_hunt flag)

`Rules.lua:747-750` sets `cardA = K.AL_KABOOT_HOKM (250)` / `K.AL_KABOOT_SUN (220)` on sweep. Line 810: `rawA = (cardA + meldPoints.A) * mult`. So Hokm-Bel sweep = 250×2 = 500 raw → 50 gp. Hokm-Four = 250×4 → 100 gp. Sun-Bel = 220×2×2 → 88 gp.

`saudi-rules.md:104` says "250 raw in Hokm, 220 in Sun (pre-multiplier)". "pre-multiplier" most naturally reads as **"base value before the multiplier applies"** — Kaboot DOES get multiplied. By contrast Belote at `saudi-rules.md:56,61,206` is explicit: "scored independently of multiplier", "+20 stays at +20". CLAUDE.md flags ONLY Belote as multiplier-immune.

**Per source-of-truth doc as written, the code is correct.** No video #1-43 explicitly contradicts the multiplied-Kaboot reading. The "Bel'd-sweep over-pay" risk only exists IF Saudi convention treats Kaboot like Belote — neither doc nor cited videos make that claim.

**Recommendation:** Add a one-liner to `saudi-rules.md` ("Kaboot bonus IS multiplier-tracking, unlike Belote") to remove the ambiguity. Code unchanged.

## Doc staleness

`decision-trees.md:170` still labels rule 2 "Partial wire — only trick-8 currently active". **STALE** since v0.5.19. Update to "WIRED v0.5.19".
