### B-62 — Human bid pattern by hand count: humans bet more aggressively with 5-card suits

Examine whether human Saudi Baloot players systematically over-bid on 5-card suits (length-over-quality bias). If yes, the bot's getStrongCards heuristic in BotMaster should apply a skepticism penalty when sampling hand distributions for human bidders who bid Hokm.

### B-63 — Human escalation hesitation as information

Examine the timing gap between the escalation window opening (K.PHASE_DOUBLE) and the human's response. If the addon tracks response latency, a 20-second wait before declining Bel signals a weak-ish hand that nearly met threshold. Audit whether latency data is accessible to the bot's inference engine.

### B-64 — Human last-trick concession: humans often concede the last trick rather than fight

Identify human tendency to concede the last trick when they're losing the round by a large margin (throw-in instead of fighting for 10 last-trick bonus). Audit: does the bot's rollout scoring include the K.LAST_TRICK_BONUS = 10 in its R.ScoreRound call, and does it play optimally for the last trick even when the round is already decided?

### B-66 — Human over-dependent on bot partner: expecting bot to "cover" mistakes

Identify the human play style of taking risks early (aggressive leads, loose Bel decisions) because they trust the bot partner to bail them out. Audit whether the bot's pickLead/pickFollow heuristics are "defensive" enough to absorb a reckless human partner's mistakes or whether they also play aggressively.

### B-67 — Tracking per-seat A/T retention: human who holds A until late game

Catalog the human pattern of holding A/T in hand until the last 2–3 tricks (A-hoarding). If the bot knows a specific human retains As late (trumpEarly=low, typically), it should lead non-trump aggressively early to force the human to spend trump on low-value tricks, depleting their trump before the A can be used.
