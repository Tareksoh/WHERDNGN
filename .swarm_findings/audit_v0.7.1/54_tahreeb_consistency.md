# Tahreeb sender vs receiver consistency — Bot.lua v0.7.2

## 1. Sender direction (Bot.lua:2231-2462; sender block 2332-2425)

Two encoders, both gated on `Bot.IsM3lm() and voidInLed and partnerWinning and Bot.IsBotSeat(R.Partner(seat))`:

- **T-1 Bargiya** (lines 2378-2390, Sun only): if any side suit has `#cards >= 2` AND contains the Ace, return the Ace. Encodes "I have the slam, lead it back" via single-event Ace.
- **T-4 Dump-ordering** (lines 2409-2426): from a 2-card non-trump suit, return the LARGER card first (gated: `hi` rank must not be K/T/A — preserves high-value doubletons).

The T-4 comment (lines 2392-2397) is explicit:
> "larger-first reads as unambiguous refusal; smaller-first would be a false bottom-up positive signal that misleads partner"

**The sender NEVER emits a "want" (ascending/low-then-high) sequence.** There is no low-first encoder for "want suit X". Only Bargiya (Ace) and refusal (descending).

## 2. Receiver direction (Bot.lua:1394-1433 classifier; 1537-1624 reader)

`tahreebClassify` (1407-1433):
- `signals[1] == "A"` → `"bargiya"`
- ascending sequence (≥2 events, ranks rise per `K.RANK_PLAIN`) → `"want"`
- descending sequence → `"dontwant"`
- single non-Ace event → `"hint"`

Reader (1557-1608): scores `bargiya=3`, `want=2`; adds `dontwant` to avoid set; opp positives also added to avoid set; conflict-resolution drops partner pref if also in opp avoid.

## 3. Direction consistency

- **Bargiya**: sender emits Ace → receiver classifies `[1]=="A"` as bargiya. **CONSISTENT.**
- **Dontwant**: sender emits LARGER first (high-then-low). Recorder (lines 462-481) appends `C.Rank(card)` in play-order, so `signals = {hi, lo}` → `descending` → `"dontwant"`. **CONSISTENT.**
- **Want**: receiver expects ascending (low-then-high). Sender has NO encoder that produces this. The "want" classification arm is **unreachable from intentional sender output**. It can only fire incidentally when a bot's two non-Tahreeb fallthroughs (lowestByRank from different doubletons across two tricks) happen to ascend — pure coincidence, not signal.

## 4. Two-trick confirmation (video #10)

Video #10 specifies "Tahreeb needs a second Tahreeb to confirm" via small-then-big sequence. The sender's T-4 path returns `hi` from a 2-card doubleton — after that play, the suit has 1 card left, and the next discard (if any) is the `lo`, producing `{hi, lo}` = descending = dontwant. The sender CANNOT produce small-then-big from a 2-card suit because it dumps the larger first by design. There is no 3+-card suit Tahreeb encoder to produce ascending.

**Result: sender cannot produce the want-confirmation pattern (line 2397 explicitly disclaims it).**

## 5. 70/25/5 prior (video #09)

Searched Bot.lua for any prior weighting on first Tahreeb event. **Not wired.** The receiver's single-event arm returns `"hint"` (line 1417) and the reader scores `"hint"` as 0 (lines 1570-1572 — no clause for "hint", falls through to 0). No probabilistic interpretation of first-event Tahreeb exists.

## Inconsistencies summary

1. **"want" path is dead on the encoder side.** Receiver scores it (=2), but sender never produces it. Effectively only `bargiya` and `dontwant` cross the wire intentionally.
2. **Two-trick small-to-big confirmation: not implementable** with current sender (T-4 always emits high-first from doubletons).
3. **70/25/5 first-event prior: missing.** First-event hints score 0, not 0.70 weighted.

These are missing-features, not desyncs — Bargiya and dontwant directions are byte-consistent.
