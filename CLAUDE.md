# CLAUDE.md — repo guidance for Claude Code

This is a **Saudi Baloot** WoW addon. Saudi Baloot is a regional
variant of French Belote — many rules differ. **Do not assume
French Belote conventions.**

When working on bot decision logic, **consult `docs/strategy/`
first** — it contains topic-organized notes distilled from real
Saudi tournament videos and commentary.

---

## Where to look

| If you're touching… | Read first |
|---|---|
| **Any picker function** (translating strategy into code) | `docs/strategy/decision-trees.md` *(operational WHEN/RULE/MAPS-TO chains; consult before topic docs)* |
| `Bot.PickBid`, `Bot.PickAshkal` | `docs/strategy/bidding.md` |
| `Bot.PickDouble`, `Bot.PickTriple`, `Bot.PickFour`, `Bot.PickGahwa` | `docs/strategy/escalation.md` |
| `Bot.PickPlay` → `pickLead` (early tricks) | `docs/strategy/opening-leads.md` |
| `Bot.PickAKA`, `pickFollow` AKA-receiver | `docs/strategy/signals.md` |
| `Bot.PickSWA`, trick-8 logic, Al-Kaboot pursuit | `docs/strategy/endgame.md` |
| `BotMaster.PickPlay` (ISMCTS), tier dispatch | `docs/strategy/bot-personalities.md` |
| Any rule-correctness question (`Rules.lua`, `R.ScoreRound`, etc.) | `docs/strategy/saudi-rules.md` |
| Adding a new Arabic term anywhere | `docs/strategy/glossary.md` (always) |

**Recommended read order when implementing a new strategy rule:**
1. `decision-trees.md` — find the operational rule.
2. `glossary.md` — confirm the code identifier + line number for
   the picker function.
3. The topic doc (e.g. `signals.md`) — read the prose rationale +
   source-video log to understand the rule's basis.
4. The picker function in `Bot.lua` / `BotMaster.lua` — apply.

The glossary is the **canonical mapping** between Arabic terms
(حكم, صن, بلوت, قهوة, etc.) and the code identifiers
(`K.BID_HOKM`, `K.BID_SUN`, `K.MULT_BEL`, `K.PHASE_GAHWA`, …).
**Always use existing identifiers** rather than inventing new ones.

---

## Important non-obvious rules (Saudi-specific)

These trip up anyone who knows French Belote:

- **9 of trump is rank 7 (second-highest), but four 9s do NOT form
  a Carré.** `K.CARRE_RANKS` excludes "9".
- **Sun contracts have a ×2 multiplier** baked into final scoring.
  Hand total in Sun is 130 (120 + 10 last-trick) ×2 = 260 effective.
- **Belote (K+Q of trump, +20) is multiplier-immune.** A ×4 round
  doesn't ×4 the Belote bonus.
- **The escalation chain (Bel → Bel x2 → Four → Gahwa) is
  Saudi-specific.** Each rung must be voluntarily declared.
  *Saudi names (Arabic):* بل / بل×2 / فور / قهوة. Code identifiers
  use English shorthand (`PickTriple`, `PickFour`, `PickGahwa`) —
  use Saudi names in docs and player-visible text, code names only
  inside Lua.
- **Bidder fails on tied 81/162** — strict majority required.
- **Last trick = +10 raw** — bonus to whoever wins trick 8.
- **AKA (إكَهْ) is the only explicit partner signal.** No
  echoing, no "petit" announcements.
- **SWA (سوا)** with ≤3 cards = instant claim; with 4+ cards =
  permission flow with 5-second auto-approve.

If a strategy doc and `Rules.lua` disagree, **`Rules.lua` is
authoritative for legality**; the strategy doc is authoritative
for *decision* heuristics. File a discrepancy if you find one.

---

## Code-organization quirks

- **Lua 5.1** target (WoW). No `goto`, no integer division `//`,
  use `math.floor` and `or`-default patterns.
- **Tested under Lua 5.5 via Python `lupa`** — see `tests/run.py`.
  Most tests run headless without WoW APIs (stubbed in each
  harness file).
- **No external WoW dependencies** — pure ace-of-base addon.
- **Constants** live in `Constants.lua` (`K.*`), exposed via
  `WHEREDNGN.K`.
- **State** lives in `State.lua` (`S.s.*`); `S.s.swaRequest`,
  `S.s.akaCalled`, `S.s.contract`, etc.
- **Networking** via `C_ChatInfo.SendAddonMessage` in `Net.lua`;
  `MaybeRunBot` is the host's bot-dispatch entry point.

---

## Bot tier dispatch

| Tier | Flag | Picker entry |
|---|---|---|
| Basic | _(default)_ | `Bot.PickPlay` (random legal) |
| Advanced | `WHEREDNGNDB.advancedBots` | `Bot.PickPlay` (heuristics) |
| M3lm | `WHEREDNGNDB.m3lmBots` | `Bot.PickPlay` (+ style ledger) |
| Fzloky | `WHEREDNGNDB.fzlokyBots` | `Bot.PickPlay` (+ extended reads) |
| Saudi Master | `WHEREDNGNDB.saudiMasterBots` | `Bot.PickPlay` → delegates to `BotMaster.PickPlay` (ISMCTS) |

**v0.5.0 fix:** `Bot.PickPlay` delegates internally to
`BotMaster.PickPlay` when Saudi Master tier is active. **Do NOT
add a second explicit `BotMaster.PickPlay` call** at any caller
site — that causes double-rollout. The single canonical entry is
`Bot.PickPlay`.

---

## When to ship

The user explicitly approves each release. Don't tag/push without
approval. Standard flow:

1. Write the change.
2. Run `python tests/run.py` — must be 177/177 pass.
3. Update `CHANGELOG.md` with a new version entry at the top.
4. Commit with descriptive message + `Co-Authored-By` line.
5. **Wait for explicit "ship" / "tag" / "push" instruction.**
6. `git tag -a vX.Y.Z -m "..."`, push commits, push tag.

The tag triggers BigWigsMods packager → CurseForge auto-publish.
Project ID: 1526129.
