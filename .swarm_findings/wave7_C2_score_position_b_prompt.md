### B-51 — Human Al-Kaboot awareness: do humans play for the sweep?

Identify whether human players in Saudi Baloot actively play for Al-Kaboot (sweeping all 8 tricks, worth 250 Hokm or 220 Sun raw points). If humans rarely consider Al-Kaboot as a goal, the bot should never cede tricks unnecessarily (even 1 defensive trick costs the Al-Kaboot bonus). Audit whether the bot accounts for Al-Kaboot possibility in its rollout scoring.

### B-52 — Human reaction to bot AKA signal: do they take the appropriate trick?

Examine whether a human partner receiving a bot AKA signal (K.MSG_AKA) actually adapts their play. The AKA signal tells the partner "I hold the boss of this non-trump suit, don't over-trump it." Audit whether the AKA UI message is visible and legible to the human during their turn, and whether the bot's PickAKA decision wastes signals on human partners who never read them.

### B-53 — Human fatigue pattern: late-game plays more mechanical, less strategic

Catalog the Saudi Baloot human tendency to play more mechanically in tricks 6–8 (game tiredness). "Just play highest" is a common late-game human behavior. Audit: does the Saudi Master tier's increased world count at trick 6+ (numWorlds=100) correctly exploit late-game human predictability, or does it over-model complexity that isn't there?

### B-54 — Human bluffing Bel to test bot Triple response

Identify the human "probe Bel" tactic: Beling on a marginal hand specifically to see if the bot Triples (revealing the bot has a strong hand / the contract is confirmed). If the bot doesn't Triple, the human knows the bot-bidder is weak. Audit: does the bot vary its Triple response based on hand strength, or does a fixed threshold make it perfectly readable?

### B-55 — Human "sacrifice play" in critical tricks: deliberate self-defeat to score position

Catalog the human sacrifice play: a human defender intentionally wins a trick they didn't want (to gain LEAD) and then leads a killer suit. This "tempo steal" is common in bridge but less so in Saudi Baloot. Audit: does the bot's current pickFollow/pickLead logic account for the possibility that an opponent is LETTING it win a trick to steal a lead?
