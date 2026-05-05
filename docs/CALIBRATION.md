# Calibration workflow

The bot has ~20 tunable thresholds in `Constants.lua` (`BOT_BEL_TH`,
`BOT_GAHWA_TH`, `BOT_OVERCALL_*_TH`, `TH_HOKM_R1_BASE`, etc.). They
were calibrated from Saudi-tournament videos + symmetric-deal
unit-tests, but never against **real-game telemetry**. v0.8.3 added
the data pipeline; v0.9.3 has the analyzer ready.

## How to dump telemetry

1. Play games in WoW with WHEREDNGN active. **Telemetry is on by
   default** — `WHEREDNGNDB.historyEnabled` defaults to true.
2. Each round-end writes one row to `WHEREDNGNDB.history` (capped at
   200 rows; FIFO drop-oldest). Rows include contract type, trump,
   bidder seat, score deltas, multiplier flags, sweep, bidderMade.
3. After your session, in chat:
   ```
   /baloot history 50
   ```
   This dumps the last 50 rows to chat for a quick look.
4. The full table lives in
   `World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\SavedVariables\WHEREDNGN.lua`
   under the key `WHEREDNGNDB.history`.

## Run the analyzer

```bash
# from repo root
python tools/calibrate.py "C:/Path/To/WHEREDNGN.lua"
```

Output includes:
- Contract-type mix (Hokm vs Sun fraction)
- Bid-round breakdown (R1/R2/forced)
- Bidder make/fail rate
- Bel/Triple/Four/Gahwa fire rates vs current thresholds
- Per-seat bidder performance
- Sweep frequency
- **Calibration signals** flagging any threshold that's dramatically off

## What we'll learn

| Metric | Healthy range | What it tells us |
|---|---|---|
| Bidder fail rate | 30–40% | <20% = thresholds too conservative; >50% = bots over-bidding |
| Bel rate | 20–35% | <10% = BOT_BEL_TH too high; >50% = too aggressive |
| Triple rate | 5–15% | Cascade indicator — only fires after Bel |
| Gahwa rate | <2% | Terminal commit; should be very rare |
| Sweep rate | 5–12% | Higher-tier bots should sweep more |
| Per-bidder delta | positive net | Confirms the bot's bidding decisions are EV-positive |

## Send the output

Either:
- Run `python tools/calibrate.py <path>` and paste the **printed
  report** back — that's the most digestible.
- OR send the raw `WHEREDNGN.lua` file (or just the
  `WHEREDNGNDB.history` block) and I'll run it.

Once we have ~100 rounds of real data, refitting `BOT_BEL_TH`,
`TH_HOKM_R1_BASE`, and `BOT_OVERCALL_*_TH` against actual outcome
distributions should be straightforward — most of the calibration
work is just figuring out which thresholds are mis-calibrated.

## Privacy notes

- Telemetry is **per-account** (per `WHEREDNGN.toc` SavedVariables
  declaration), local to your machine.
- No data is sent over the network; only round-resolution wire
  payloads (`MSG_ROUND`) carry score state, and that's already
  visible to all 4 seats.
- Rows contain no hand contents, no card identifiers, no player
  names — just contract metadata + score deltas + flags.
- Disable any time with `/baloot history off`. Rows persist (use
  `/baloot history clear` to wipe).
