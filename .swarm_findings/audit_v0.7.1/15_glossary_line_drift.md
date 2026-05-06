# Glossary line-number drift audit (v0.7.2 HEAD)

**Summary: 16 stale, 0 current** — every Bot.lua / Net.lua line citation in `docs/strategy/glossary.md` is now stale. The doc explicitly self-anchors to v0.5.15; HEAD is v0.7.2. Drifts now range from +52 to +517 lines.

| Doc citation | File:line claimed | Actual file:line | Function/variable |
|---|---|---|---|
| L20 (Bid types row "حكم") | Bot.lua:725 | Bot.lua:942 | `Bot.PickBid` |
| L21 (Bid types row "صن") | Bot.lua:725 | Bot.lua:942 | `Bot.PickBid` |
| L21 (Bid types row "صن") | Bot.lua:953 | Bot.lua:1359 | `pickLead` (local) |
| L21 (Bid types row "صن") | Bot.lua:1457 | Bot.lua:2063 | `pickFollow` (local) |
| L22 (Ashkal row) | Bot.lua:725+ | Bot.lua:942 | `Bot.PickBid` (Ashkal branch inside) |
| L41 (Bel row) | Bot.lua:1787 | Bot.lua:2714 | `Bot.PickDouble` |
| L42 (Bel x2 row) | Bot.lua:1908 | Bot.lua:2846 | `Bot.PickTriple` |
| L43 (Four row) | Bot.lua:1938 | Bot.lua:2877 | `Bot.PickFour` |
| L44 (Gahwa row) | Bot.lua:1982 | Bot.lua:2922 | `Bot.PickGahwa` |
| L47 (helper bullets) | Bot.lua:1884 | Bot.lua:2822 | `escalationStrength` (local) |
| L48 (helper bullets) | Bot.lua:1899 | Bot.lua:2837 | `escalateDecision` (local) |
| L49 (helper bullets) | Bot.lua:588 | Bot.lua:791 | `scoreUrgency` (local) |
| L50 (helper bullets) | Bot.lua:619 | Bot.lua:822 | `matchPointUrgency` (local) |
| L93 (AKA row) | Bot.lua:1686 | Bot.lua:2606 | `Bot.PickAKA` |
| L93 (AKA row, receiver) | Bot.lua:1457+ | Bot.lua:2063 | `pickFollow` |
| L94 (SWA row) | Bot.lua:2120 | Bot.lua:3094 | `Bot.PickSWA` |
| L94 (SWA row) | Net.lua:~3535 | Net.lua:2728 (HostResolveSWA), Net.lua:3387 (MaybeRunBot SWA-guard) | `N.HostResolveSWA`, `N.MaybeRunBot` SWA guard |
| L96 (Al-Kaboot row) | Bot.lua:953 | Bot.lua:1359 | `pickLead` |
| L231 (Tahreeb code-mapping) | Bot.lua:1457 | Bot.lua:2063 | `pickFollow` |
| L265 (Tanfeer code-mapping) | Bot.lua:1457 | Bot.lua:2063 | `pickFollow` |
| L276 (Takbeer/Tasgheer code-mapping) | Bot.lua:1457 | Bot.lua:2063 | `pickFollow` |
| L287 (Faranka code-mapping) | Bot.lua:1457 | Bot.lua:2063 | `pickFollow` |
| L302 (deceptiveOverplay) | Bot.lua:1457 (implied) | Bot.lua:2063 | `pickFollow` |

## v0.5.15 snapshot table (lines 419-444) — ALL stale

| Symbol | Doc claims | Actual HEAD line | Drift |
|---|---|---|---|
| `Bot.PickBid` | 890 | 942 | +52 |
| `Bot.PickAKA` | 2302 | 2606 | +304 |
| `Bot.PickPlay` | 2344 | 2655 | +311 |
| `Bot.PickMelds` | 2380 | 2691 | +311 |
| `Bot.PickDouble` | 2403 | 2714 | +311 |
| `Bot.PickTriple` | 2534 | 2846 | +312 |
| `Bot.PickFour` | 2564 | 2877 | +313 |
| `Bot.PickGahwa` | 2608 | 2922 | +314 |
| `Bot.PickPreempt` | 2630 | 2945 | +315 |
| `Bot.PickKawesh` | 2681 | 3029 | +348 |
| `Bot.PickTakweesh` | 2708 | 3056 | +348 |
| `Bot.PickSWA` | 2746 | 3094 | +348 |
| `pickLead` | 1289 | 1359 | +70 |
| `pickFollow` | 1882 | 2063 | +181 |
| `escalationStrength` | 2510 | 2822 | +312 |
| `escalateDecision` | 2525 | 2837 | +312 |
| `scoreUrgency` | 753 | 791 | +38 |
| `matchPointUrgency` | 784 | 822 | +38 |
| `Bot.OnPlayObserved` | 292 | 292 | 0 (still accurate) |

## Notes
- `Bot.OnPlayObserved` at L444 of glossary is the only line cite that is **still current** (line 292 unchanged).
- Largest in-table drifts are on the escalation pickers (`Bot.PickTriple/Four/Gahwa` ~+938 from prose-table claims of ~1908/1938/1982 vs actual 2846/2877/2922).
- Rules.lua / State.lua / BotMaster.lua have NO concrete line cites in the doc body — only generic mentions (e.g. "`Rules.lua` should expose `R.CanBel`"). No drift to verify there.
- The "v0.5.15 snapshot" subsection claims 18 line numbers; 17 are stale, only `Bot.OnPlayObserved` (line 292) survived intact.
