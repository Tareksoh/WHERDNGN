### A-71 — scores accumulation: no normalization by world count

Inspect the score accumulation in BM.PickPlay (lines ~519-526). Scores are summed raw across all worlds without dividing by numWorlds. The final selection uses `scores[c] > bestScore` (argmax). Verify: since all candidates are evaluated on the same N worlds (same N for each), raw sum and average give the same argmax — but verify that this assumption holds when the fallback deal fires mid-loop (one world is uniform random, skewing the sum for ALL candidates equally).

### A-73 — AKA signal gate: only from trick 2 onwards (line ~1104)

Audit Bot.PickAKA's trick number gate (line ~1104: `trickNum <= 1 then return nil`). The comment says "no opponent voids yet." Verify: is it always true that by trick 2 at least one void inference is possible? If no one has discarded yet by trick 2, the AKA signal is still not actionable for the partner. Consider whether the gate should be tricks-with-discards > 0 rather than trickNum > 1.

### A-74 — AKA dedup: per-suit akaSent flag reset in Bot.ResetMemory

Inspect the akaSent flag (lines ~112-113, ~106 in emptyMemory). Confirmed it resets per round. Audit: if the bot leads the boss card of suit H in trick 2 (AKA H sent), then wins it, and the boss of H falls to an opponent — the next trick the bot leads H again but the SECOND-HIGHEST unplayed H is now the new boss. Does the bot incorrectly skip AKA on this re-lead due to the per-suit dedup flag?

### A-76 — Fzloky: high (A/T/K) = lead this suit, low (7/8) = avoid this suit

Audit the Fzloky signal interpretation (lines ~752-758). Q and J fall into neither category — they are ignored. In Saudi Baloot, a Q discard from a short suit could signal strength or weakness depending on context. Audit whether Q/J first-discards in a non-trump suit should be treated as low/high/neutral.

### A-77 — Fzloky lead preference: lowest card of signaled suit (line ~771)

Inspect the lead-to-partner-signal behavior (lines ~763-772). The bot leads its LOWEST card of the signaled suit. Audit: in Hokm, leading the lowest non-trump of the partner's strong suit allows the partner to win with their A/T/K and then lead again — correct. But verify: if the bot's lowest card of the signaled suit is also the only boss remaining in that suit (e.g., bot holds 7 but K was already played), leading 7 into an exhausted suit is wasteful.
