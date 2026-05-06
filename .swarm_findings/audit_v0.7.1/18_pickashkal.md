# 18 — PickAshkal audit (v0.7.2 HEAD)

**Surface:** No standalone `Bot.PickAshkal`. All bot-side Ashkal logic is **inline in `Bot.PickBid`** at `Bot.lua:1054-1134`. Host-side enforcement lives in `State.lua:1528-1577` (S.HostAdvanceBidding, Ashkal branch).

## Eligibility (dealer + dealer's-LEFT)

**Bot side (Bot.lua:1062-1073):** Builds `order = { d+1, d+2, d+3, d }` and seeks own `bidPos`. Gates with `bidPos >= 3`. Position 3 = `d+3` mod 4 = the seat one BEFORE dealer in walk order = dealer's LEFT (per UI.lua:223 NextSeat=right convention). Position 4 = dealer. **CORRECT.**

**Host side (State.lua:1554-1560):** Same `order` array, same `bidPosition >= 3` gate, same silent-drop on positions 1-2. v0.5.7 comment block (lines 1549-1553) explicitly notes the v0.5.6 inversion was repaired and now matches dealer's-LEFT + dealer. **CORRECT — defense-in-depth (bot self-gates and host re-validates).**

## Bid-up rank check (A-2 deferred item)

**NOT WIRED.** The bot has no affirmative gate `bidCardRank ∈ {7,8,9,J,Q,T-singleton}`. Implementation is purely **negative anti-triggers** (A=reject, T+ourA=reject). A bid-up of K, Q, J, 9, 8, 7 all fall through with `ok = true` and proceed on strength alone. Per transcript 31 R29, K bid-up with 2-mardoofa+1A should pivot to direct Sun — but the 85-pivot (next section) handles the strong-hand case generically, and the bid-up rank itself is never inspected for the small/mid contour. **Acceptable as a partial implementation; the A-6 strength pivot subsumes most A-2 cases, but T-singleton and bid-up-K nuances are absent.**

## Anti-triggers

- **A-3 (bid-up = A → reject):** `Bot.lua:1083` `if bidCardRank == "A" then ok = false`. **WIRED.**
- **A-4 (bid-up = T + we hold A of same suit → reject):** `Bot.lua:1090-1096` scans hand for matching A. **WIRED.**
- **A-5 (3+ Aces → direct Sun):** `Bot.lua:1103` `if aceCount >= 3 then ok = false`. **WIRED.** Reject sets `ok=false`, falls through to direct Sun branch at line 1147 (gated by `sunMinShape` + `sun >= thSun`).

## 85-pivot (A-6)

`Bot.lua:1112` `if ok and sun >= K.BOT_ASHKAL_DIRECT_SUN_PIVOT then ok = false`. `Constants.lua:317` `K.BOT_ASHKAL_DIRECT_SUN_PIVOT = 85`. **WIRED CORRECTLY.** Reject path falls through to direct Sun. Single threshold (85) — no soft band, but matches transcript 31 prescription.

## Verdict

**Mostly correct.** Eligibility, A-3/A-4/A-5 anti-triggers, and the 85-pivot are all wired. Two gaps: (1) **no affirmative bid-up rank gate** — Ashkal can fire with bid-up K despite mardoofa-strong hand if `sun < 85`; (2) **Bot.PickAshkal as a separate function does not exist** — glossary/decision-trees reference `Bot.PickAshkal` Bot.lua:725 is stale (the function is `Bot.PickBid`, lines 1044-1134). Note: Ashkal-eligibility is checked BEFORE direct Sun (v0.5.8 ORDER FIX at 1044), resolving the A-08 dead-code bug from prior audits — `BOT_ASHKAL_TH=65` is now reachable. Strength jitter is `±BID_JITTER` so effective Ashkal floor is ~59-71.
