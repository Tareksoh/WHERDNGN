# Wave 1 — Cluster A1: Trump Strength + Escalation Correctness
## Reviewer: swarm audit agent, v0.4.4

---

## Angle A-16 — suitStrengthAsTrump: 8 and 7 scored 2 despite POINTS_TRUMP_HOKM showing 0

**VERDICT: NOT-CONFIRMED (intentional divergence; comment documents the design choice)**

**Citations:**
- `Bot.lua:312-317` — `elseif r == "8" then strength = strength + 2` / `elseif r == "7" then strength = strength + 2`
- `Bot.lua:312-314` (comment) — "13th-bot-audit fix: 8 and 7 of trump are worth 2 each per Saudi Hokm point convention."
- `Constants.lua:43-44` — `K.POINTS_TRUMP_HOKM = { ["7"]=0, ["8"]=0, ...}`

**Evidence:**
The prompt characterizes this as a potential mismatch, but the code includes a comment that explicitly acknowledges the divergence and explains it: the `+2` contribution in `suitStrengthAsTrump` is a *length proxy*, not a point-value mirror. The function is measuring how strong a suit would be as trump for *bidding purposes*, not scoring purposes. Having 8s and 7s of trump still adds modest value as length contributors — they help meet K.RANK_TRUMP_HOKM overcut chains and contribute to the count-based `math.max(0, count - 2) * 5` length bonus. Giving 0 there (as the scoring table would dictate) would under-reward hands with 6-card trump suits heading A-T-K-Q-9-8 vs A-T-K-Q-9-J. The in-code audit fix comment ("Previously fell through with 0 contribution, undercounting trump-rich hands") confirms this was a deliberate correction. No bug is present. The discrepancy between the strength function and `K.POINTS_TRUMP_HOKM` is acknowledged, intentional, and correct given the function's purpose.

**Fix recommendation:**
None required for correctness. An optional documentation improvement would be to add a one-line comment inside the function header clarifying that `strength` is a bidding-heuristic signal, not a point-value sum, so future readers do not re-raise this discrepancy as a bug.

---

## Angle A-25 — C.IsTrump correctness in Sun contracts

**VERDICT: NOT-CONFIRMED**

**Citations:**
- `Cards.lua:125-128` — `function M.IsTrump(card, contract)` / `if not contract or contract.type ~= K.BID_HOKM then return false end`
- `Bot.lua:683-688` — `highestNonTrump` calls `C.IsTrump(c, contract)` inside loop; all paths used by `pickLead` and `pickFollow`
- `Bot.lua:786-801` — `isBidderTeam and isBidder` block calls `C.IsTrump(c, contract)` for trump count
- `Rules.lua:143` — `if contract.type == K.BID_SUN then return true end` (before any trump check in `IsLegalPlay`)

**Evidence:**
`C.IsTrump` is defined at `Cards.lua:125-128` with a top-level guard: it immediately returns `false` if `contract` is nil or if `contract.type ~= K.BID_HOKM`. In a Sun contract, `contract.type == K.BID_SUN`, so this condition fires for every card without exception. All callers inside `pickLead` and `pickFollow` (lines 683, 730, 789, 817, 1034, 1057) that gate on `C.IsTrump` will uniformly receive `false` in Sun, meaning the trump-specific branches (`isBidderTeam and isBidder` lead logic at line 785, trump-discard-save at line 1057, the trump-count loop at line 789) correctly never fire in Sun. The `BotMaster.lua:376` rollout heuristic also uses `C.IsTrump` for the bidder-team lead, and it correctly falls through to the non-trump lead path in Sun. No trump-specific branch can be reached in a Sun contract context.

**Fix recommendation:**
None required.

---

## Angle A-49 — escalationStrength: J double-counted for Hokm bidder (sunStrength + full trumpStrength)

**VERDICT: BUG-CONFIRMED**

**Citations:**
- `Bot.lua:1191-1200` — `escalationStrength` function
- `Bot.lua:1193-1195` — `strength = sunStrength(hand)` then `strength = strength + suitStrengthAsTrump(hand, contract.trump)`
- `Bot.lua:374-376` — inside `sunStrength`: `elseif r == "J" then s = s + 2` (J of trump is a plain-suit J here; gets +2)
- `Bot.lua:306` — inside `suitStrengthAsTrump`: `if r == "J" then hasJ = true; strength = strength + 20`
- `Constants.lua:252-255` — `K.BOT_TRIPLE_TH = 90`, `K.BOT_FOUR_TH = 110`, `K.BOT_GAHWA_TH = 135`

**Evidence:**
`escalationStrength` at `Bot.lua:1191` computes `strength = sunStrength(hand)` first. Inside `sunStrength` (`Bot.lua:354-399`), every card in the hand is scored, including the J of trump: at line 374-376, `elseif r == "J" then s = s + 2`. `sunStrength` has no way to know which suit is trump — it receives only `hand`, not a trump suit parameter. Then on line 1194-1195, `suitStrengthAsTrump(hand, contract.trump)` is added, which at line 306 adds +20 for the J of trump. The J of trump is thus scored once at +2 (via `sunStrength`) and again at +20 (via `suitStrengthAsTrump`), for a total contribution of +22 rather than the intended +20. The net inflation is +2 per J-of-trump held (the +2 from `sunStrength` leaks in). This is a smaller magnitude than the prompt's "+18" estimate (which conflated the full gap between trump-J value 20 and plain-suit J value 2, as if sunStrength were adding a full +20; in fact it adds only +2), but the double-count is real. For `PickTriple` and `PickFour`, where thresholds are 90 and 110 respectively, a spurious +2 on the J is unlikely to flip decisions at the margin. For `PickGahwa` at threshold 135, however, a hand with J of trump near the threshold could be boosted past it incorrectly. The same inflation affects `PickDouble` via the analogous code at `Bot.lua:1160-1162`, where `suitStrengthAsTrump` is multiplied by 0.5 rather than added directly, so the double-count there is +2 + 0.5*20 = +12 vs intended 0.5*20 = +10 — a +2 overcount that mirrors `escalationStrength`.

Note: the `9` of trump also has a divergence (+14 in `suitStrengthAsTrump` vs 0 in `sunStrength` since `sunStrength` only scores A/T/K/Q/J), but that is not a double-count — the 9-of-trump contribution through `sunStrength` is 0, and through `suitStrengthAsTrump` is +14, for a net of +14 as intended. Only the J is double-counted because J scores in both paths.

**Fix recommendation:**
In `escalationStrength` (`Bot.lua:1191`), pass a trump-suit exclusion argument to `sunStrength`, OR subtract the trump-J's plain-suit contribution after combining. The cleanest fix is to refactor `sunStrength` to accept an optional `excludeSuit` parameter — when provided, cards of that suit are skipped in the scoring loop. Then call it as `sunStrength(hand, contract.trump)` from `escalationStrength` and from the corresponding block in `PickDouble`. This removes the double-count without changing behavior for Sun contracts (where `contract.trump` is nil and the exclusion does nothing) or for the bidding path (which never calls `escalationStrength`). Alternatively, after the two-line add at `Bot.lua:1193-1195`, subtract 2 for each J-of-trump held in the hand: `if hand has J of trump then strength = strength - 2 end`. The `PickDouble` path at lines 1159-1162 has a mirrored issue and should be corrected in the same pass.

---

## Summary of Findings

| Angle | Verdict | Severity |
|-------|---------|----------|
| A-16: suitStrengthAsTrump 8/7 vs POINTS_TRUMP_HOKM | NOT-CONFIRMED (intentional divergence) | — |
| A-25: IsTrump in Sun contracts | NOT-CONFIRMED | — |
| A-49: escalationStrength J double-count | BUG-CONFIRMED | warning |

The only real defect is A-49: the J of trump is double-counted in `escalationStrength` (and in `PickDouble`'s inline equivalent), inflating escalation willingness by +2 for any Hokm hand holding the trump J. The magnitude is small but measurable on near-threshold hands; it affects `PickTriple`, `PickFour`, `PickGahwa`, and `PickDouble` uniformly. No code changes made — report only.
