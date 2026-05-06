### B-83 — Human Gahwa bluff exploitation: does the bot track failed Gahwas?

Audit the _partnerStyle.gahwas counter. It tracks Gahwa calls but not Gahwa FAILURES. Identify whether a human who called Gahwa and failed (match not won) should have a "reckless" tag applied. Audit: does the style ledger capture the outcome of escalation decisions, or only the decisions themselves?

### B-85 — Exploiting human "natural" play: leading from strength in the suit partner bid

Catalog whether human Saudi Baloot defenders exploit the information in the partner's Hokm bid by leading the bid trump suit back immediately. This is "natural" play but incorrect (gives up defensive tricks). Audit: does the bot model a human partner who naturally leads trump as a signal that the human doesn't understand partner-coordination?

### B-86 — Human AKA ignorance: humans often don't know the AKA signal exists

Examine whether the AKA signal (K.MSG_AKA, K.SND_VOICE_AKA) is visible and understandable to human players in the UI. If the AKA announcement is unclear, the human partner won't stop over-trumping. Audit: does the UI display an explicit "partner holds boss of X suit" message, or only plays a sound? If sound-only, it's not exploitable for partner coordination with a human.

### B-87 — Human partner signal suppression: bots withholding signals against humans

Identify whether the bot's Fzloky firstDiscard signal would CONFUSE a human partner (human interprets a high discard as "I have these cards" rather than "lead this suit"). Audit: should IsFzloky signals be gated to "partner is also a bot" to prevent sending confusing signals to human partners who may not know the convention?

### B-88 — Human "echo" signal: playing a high card then low in the same suit (attitude signal)

Catalog whether Saudi Baloot human players use the "echo" convention (play high-then-low in a suit to signal strength). This is a standard bridge convention adopted by some Saudi Baloot advanced players. Audit: does the bot's memory track rank sequences for the same seat in the same suit across multiple tricks?
