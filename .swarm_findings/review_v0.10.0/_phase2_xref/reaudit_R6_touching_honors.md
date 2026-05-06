# Reaudit R6: Touching-honors signal granularity

## Source ground rules

The granularity question concerns the WRITE site at `Bot.lua:449-500` and READ
site at `BotMaster.lua:445-472`. The v0.9.2 #12 fix activated a previously-dead
WRITE branch (the `trick` global → nil short-circuit). With the branch now
reachable, semantic correctness — not reachability — is the question.

Authoritative source: **video #05** (`vkY55gg-39k_05_baloot_predictions_general`),
which is the canonical Section-6 video for AKA-receiver / touching-honors
signaling per `docs/strategy/signals.md`.

Source A's "Tahreeb cluster" (videos 01, 02, 03, 09, 10) does NOT cover this
content. Source A's rule references about touching-honors-down are downstream
restatements in the doc; the primary content lives in #05. The conflict between
"4 simple rules (A)" vs "6 sub-rules (D)" therefore reduces to: how detailed
does video #05 actually get, and how does the reader's interpretation diverge
from the WRITE+READ semantics in code?

---

## Quoted Arabic per rank from video #05

The relevant block runs from ~03:48 through ~05:22 (transcript lines 530–620
in the SRT, which is the Section-6 canonical passage). For each rank below I
quote the contextual Arabic (≤15 words per quote) verbatim from the SRT, then
translate.

### Lead bare-A; follower (your partner) plays T (العشره)

- **@ 03:48 – 03:53** (lines 532–554):
  > "في اصول البلوت اذا خويك لعب عشره يعني انت لعبت في البدايه وخويك لعب عشره معناته مع الشايب"
  - English: "In Baloot conventions, if your partner played the 10 — meaning
    you led and partner played the 10 — it means he holds the K (شايب)."
- **Confidence-tagging quote @ 04:36 – 04:42** (lines 743–753):
  > "خلينا نقول 95% ما عندي اصغر من عشره هذا 90% فرق بسيط بينهم"
  - English: "Let's say 95% he has nothing smaller than the 10; this is 90%;
    small difference between them." (Distinguishing right-hand opponent's
    forced-up read at 95% vs farther-seat read at 90%.)
- **Caveat @ 03:56 – 04:02** (lines 575–593):
  > "كذا راح تفهمها مش دائما لكن كاصول في البلوت"
  - English: "That's how you understand it — not always, but as a
    Baloot convention."

→ Code's "T → nextDown=K" matches: T → has K. **Match.**

### Lead bare-A; follower plays K (الشايب) — when 10 is gone

- **@ 04:48 – 04:59** (lines 783–824):
  > "اذا هذا الخصم لعب الشايب احتمال يكون عنده عشره فقط فهو لعب الشايب الاصغر من العشره"
  - English: "If this opponent played the K, possibly he has only the K [no 10]
    so he played K as the smallest he has [below the 10]." 
- **@ 04:52 – 04:58** (lines 794–814):
  > "هل ممكن يكون عنده البنت ولا الولد لا مستحيل لو عنده كان لعبها بدال الشايب"
  - English: "Can he have the Q or J? No — impossible. If he had them he would
    have played them instead of the K [because they're smaller than K]."
- **Conclusion @ 05:01 – 05:13** (lines 833–884):
  > "هتفهم انه هذا اللاعب اللي لعب الشايب الشايب عنده تك لانه العشره طلعت عند خويك"
  - English: "You understand the player who played the K has the K alone
    [تك = singleton], because the 10 came up at your partner."

**Critical observation:** The K-signal in #05 is NOT "has Q (next-down)". It
is the OPPOSITE inference — the player has **only the K** (singleton), and
the 10 is **at one of the OTHER two players** (specifically, since A and K are
both spent, the 10 is at "your partner" in the worked example, OR at the other
opponent if partner already played small).

The reasoning is elimination-based: "had he had Q or J he would have played
those (smaller) cards instead of the K." So K-as-second-card is the
**high-end** of his holding, not the bottom-of-a-touching-pair.

→ Code's "K → nextDown=Q" **does NOT match**. The source says K-followed
implies "no Q, no J in this player's hand" — exactly the opposite of pinning Q.

### Lead bare-A; follower plays Q (البنت)

- **@ 05:13 – 05:18** (lines 884–894):
  > "ولو هذا لعب بنت السبيت هويك مع الولد"
  - English: "And if this one played the Q of spades, your partner has the J."

**Note:** The source phrasing here ("your partner has the J") — NOT "this player
has the J". Read together with R3a (T→partner-has-K), the pattern is:

- T played by opponent → partner has K (the missing rung)
- Q played by opponent → partner has J (the missing rung)

The signal is symmetric in shape (touching-down) but the inference is about
**where the missing rung lives** — generally at PARTNER, the unseen-card seat.

When the player playing the Q is YOUR PARTNER (the AKA-receiver context the
code targets), by the same elimination logic as R3b, the inference flips: Q is
the highest-rank card he holds, J is somewhere else.

→ Code's "Q → nextDown=J" **partially matches** but conflates the
"opponent-played" reading (J is at partner) with the "partner-played"
elimination (J is NOT at partner) — see Verdict.

### Lead bare-A; follower plays J (الولد)

- **@ 05:13 – 05:22** (lines 884–924):
  > "هذا لعب اصغر شيء عندي اللي هو الشايب وهذا لعب اصغر شيء عنده اللي هو البنت"
  - English: "He played his smallest [card], which is the K; and the other
    played his smallest, which is the Q." (worked example narration)
- **Forward-looking @ 05:18 – 05:22** (lines 904–924):
  > "معناته المره الجايه راح يقطعون انت راح تاكل هذا تمام"
  - English: "Meaning next time they will cut [trump]; you will eat this trick."

**The source does not give an explicit "J → has nothing" rule.** What it says
is the meta-pattern: each player plays the smallest of their honor block, and
when J appears it indicates the player has played the bottom of their honor
holding (so future tricks they will RUFF, not follow). Source D's R3d ("J →
nothing") is a reasonable inference but the source video is more cautious — it
frames J as "they will cut next trick" rather than "they hold nothing."

→ Code does not handle J at all. The transcripts treat J as part of the same
elimination-chain, not as a discrete "broke" signal.

### Lead bare-A; follower plays 9 (التسعه)

- **The transcript does not isolate 9 from 7/8** in the touching-honors
  passage. The 9 appears in the rank-list narration (line 524: "العشرات شايب
  البنت السبعه التسعه ثمانيه") as part of the descending rank order, NOT as
  a distinct signal class.
- The "0-abna3" framing (9/8/7 all worth zero in Sun) appears in source D
  (video #13) at ~01:03 and in #05 ~04:08–04:50 (small-cards-played-under),
  but #05 itself does not name 9 as either equivalent-to or distinct-from 7/8
  in the touching-honors context. The source is silent on a 9-vs-7/8 split.

→ Source under-specifies. Code currently only matches 7 or 8 → broke; 9 falls
through and writes nothing. See Verdict.

### Lead bare-A; follower plays 8 (الثمانيه)

- The 8 appears in the rank list and in the "smallest-card" inference passage
  (lines 1424–1444, ~07:22–07:30): "اللاعب اللي يلعب اصغر ورقه تفترض عنده
  اوراق اكثر" — "the player who plays the smaller card, you assume he holds
  more cards [in the suit]."
- This is a generic length-inference rule (R16 in source D), not specific to
  the AKA-receiver touching-honors signal.

→ Code's "8 → broke" matches the spirit (no high cards in suit), even though
the source's reasoning is "long suit, no honors" rather than "honor-broke".

### Lead bare-A; follower plays 7 (السبعه)

- Same as 8 — the 7 is conflated with "smallest card" length-inference.
- The "small cards in Sun = 0 abna3 = 'discourage further A-runs'" rationale
  comes from #13, not #05.

→ Code's "7 → broke" matches.

### Asymmetry rule (R3f from source D)

- **@ 03:17 – 03:22** (lines 412–434):
  > "طبعا انت ما تقيد على خويك لكن هذا خصم ممكن يقيد عليه"
  - English: "Of course you don't [deceive] your partner, but this one is an
    opponent — he can [deceive]."

This is the trust-asymmetry rule in source D. It IS in #05's transcript and
applies generally to all signaling, not just touching-honors. Code does not
distinguish partner vs opponent at the WRITE site (the only check is "lead.seat
== R.Partner(seat)" — i.e. the LEADER must be SEAT's partner; SEAT itself
can be partner OR opponent).

---

## Comparison: code vs source per rank

| Rank | Source #05 signal | Code signal (`Bot.lua:489-497`) | Match? |
|---|---|---|---|
| T | "Player has the K" (touching-down inference) | `nextDown = "K"` (pin K to player) | **Match** |
| K | "Player has ONLY the K (singleton); 10 and Q+J are NOT at this player" — elimination chain | `nextDown = "Q"` (pin Q to player) | **MISMATCH** — code pins Q to a player who source says explicitly does NOT have Q |
| Q | "Partner [unseen seat] has the J" — touching-down at the OTHER seat (or, when player IS partner, elimination implies J is elsewhere) | `nextDown = "J"` (pin J to player) | **AMBIGUOUS** — works for opponent reading, inverts for partner-played |
| J | Not framed as a discrete signal in #05; implication is "they will cut next trick" (future-trick warning) | not handled (falls through) | **Source under-specifies; code silent** |
| 9 | Not isolated in #05 touching-honors passage; 0-abna3 framing in #13 only | not handled (falls through) | **Source silent in #05; code silent** |
| 8 | Length-inference ("smallest = longest holding") — generic, not honors-specific | `broke = true` (clear A/T/K/Q/J desire for suit) | **Approximate match** (different rationale, similar effect) |
| 7 | Same as 8 | `broke = true` | **Approximate match** |

**Trust-asymmetry (R3f):** Source #05 explicit at 03:17–03:22. Code: WRITE
site at `Bot.lua:471-487` writes for ANY seat whose LEADER was their partner —
including opponent seats reading their own partner's signals. READ site at
`BotMaster.lua:454` iterates `for suit, entry in pairs(style.topTouchSignal)`
across all seats. **Trust-asymmetry not enforced.**

---

## Verdict

### Current 4-rule model: incomplete AND semantically wrong on the K case

The post-v0.9.2 #12 fix activated a WRITE branch whose semantics do not match
the source video. Now that the branch is reachable, it is **actively
mispredicting** for the K-signal case.

### Specific bugs

1. **K-signal interpretation: code pins Q to player, source says player has
   ONLY K (no Q, no J).**
   - `Bot.lua:491-492` writes `entry.nextDown = "Q"` when player plays K.
   - `BotMaster.lua:455-462` then bumps `desire["Q" .. suit] = 60` for that
     seat, biasing the sampler to put Q at this seat.
   - Source #05 lines 794–814 explicitly state: "Can he have Q or J? No,
     impossible — he would have played those instead." The Q is at one of
     the OTHER two seats.
   - **Effect:** Code pins Q to a seat that demonstrably does not have Q.
     Inverse of the correct inference.

2. **J-signal: code does not handle it.**
   - No `elseif theirRank == "J"` branch in `Bot.lua:489-497`.
   - Source #05 frames J-played as a "future-trick warning" (player will cut
     next time) rather than a card-location pin. Source D extrapolates this
     to "J → has nothing" which is reasonable but slightly stronger than the
     transcript supports.
   - **Effect:** Missing handler. Could be added as a `broke`-style flag
     given the future-cut implication, but with caveat that the source
     under-specifies.

3. **9-signal: code does not handle it; source #05 does not specify.**
   - Code only fires `broke = true` for 7 or 8. 9-played falls through silently.
   - Source #05 lists 9 in the rank order but does not name it as a discrete
     signal in the touching-honors passage. Source D's R3e groups 9/8/7 as
     "0-abna3 = discourage" — but that's #13, not #05.
   - The addon HAS a separate `likelyKawesh` mechanism (`BotMaster.lua:402`)
     that fires on rank 7/8/9 in tricks 1-3, which DOES cover 9.
   - **Effect:** Inconsistency — 7/8 trigger the touching-honors broke clear,
     9 does not, even though all three are 0-abna3 in Sun and source D treats
     them identically.

4. **Trust-asymmetry not enforced (source R3f, #05 @ 03:17–03:22).**
   - WRITE writes for both partner-side and opponent-side seats.
   - READ reads from both.
   - Source explicit: "of course you don't deceive your partner, but the
     opponent can deceive." Saudi convention says trust partner signals at
     face value, discount opponent signals.
   - **Effect:** Opponent's deceptive K-play (deliberately playing K while
     holding Q to mislead) gets full sampler weight. The mis-pin (#1 above)
     is then weaponized BY opponents AGAINST the bot.

### Severity ranking

- **#1 (K-signal inversion)** — high. Code is now actively pinning Q to the
  wrong seat. With the v0.9.2 #12 fix making this branch reachable, this is
  the new active bug.
- **#4 (trust-asymmetry)** — medium-high. Compounds with #1 because opp
  signals are now read at face value.
- **#3 (9-signal inconsistency)** — low. The `likelyKawesh` mechanism
  partially covers it; the code is internally inconsistent but not catastrophic.
- **#2 (J-signal missing)** — low. Source itself is ambiguous about this; not
  adding it does not contradict #05.

---

## Recommended code action

### Priority 1: Fix the K-signal inversion

Change `Bot.lua:491-492` from:

```lua
elseif theirRank == "K" then
    entry.nextDown = "Q"            -- rule 2
```

to (based on #05's elimination chain, lines 794–824):

```lua
elseif theirRank == "K" then
    -- Source #05 @ 04:48-05:13: K-played-second implies player has K
    -- ALONE; Q and J are at one of the OTHER two seats. The pre-fix
    -- nextDown="Q" was incorrect — it pinned Q to the seat that the
    -- source says does NOT have Q. Mark the K as singleton-confirmed
    -- and clear Q/J desires for THIS seat.
    entry.kAlone = true             -- rule 2 (corrected)
```

And add a corresponding READ-side handler in `BotMaster.lua:454-471` that
clears `desire["Q" .. suit]` and `desire["J" .. suit]` for the seat with
`kAlone`, AND optionally bumps Q/J desire on the OTHER two seats.

### Priority 2: Add trust-asymmetry guard at WRITE site

Wrap the touching-honors WRITE branch at `Bot.lua:471` with a partner-of-bot
check. The signal is reliable when the SEAT (the follower) is on the BOT's
team; when the SEAT is an opponent, write with a "deception-possible" flag and
have the READ site weight it down (e.g. desire bump 30 instead of 60).

Note: this requires plumbing — `Bot.OnPlayObserved` doesn't know which seat
the bot itself is. Could be done by deferring the trust-discount to the READ
site, where the iterating sampler knows `seat` (the sampling seat) and can
compute `R.TeamOf(s) == R.TeamOf(seat)` per-iteration.

### Priority 3: Decide on J-handler

Either:
- Add `elseif theirRank == "J" then entry.broke = true` (matches source D's
  extrapolation but stronger than #05's actual phrasing), OR
- Leave unhandled (matches #05's literal silence), OR
- Add `entry.willCut = true` and have the READ site bias the sampler to put
  trump cards at this seat in Hokm contracts (matches the "they will cut next
  trick" phrasing).

**Recommendation: leave unhandled** until a second source confirms the J-as-
discrete-signal interpretation; current source #05 evidence is too thin.

### Priority 4: Decide on 9-handler

Source #05 does not say. Source D's R3e groups 9 with 7/8 as "0-abna3 =
discourage." Two reasonable options:

- Extend the existing branch: `elseif theirRank == "7" or theirRank == "8"
  or theirRank == "9" then entry.broke = true` — matches source D and matches
  the existing `likelyKawesh` mechanism's rank set.
- Leave 7/8-only — matches #05's literal omission.

**Recommendation: extend to include 9.** Internal consistency with
`likelyKawesh` (which already groups 7/8/9) and source D's R3e converge on this.

### Anti-recommendation

Do NOT keep the current K-as-Q-pin behaviour. The v0.9.2 #12 fix made it
reachable; reachable + wrong is worse than dead + wrong.

---

## Confidence

- **K-signal inversion bug (#1):** Definite. Source #05 quotes are direct,
  unambiguous, and in the canonical Section-6 video. The mismatch is plain
  text vs plain code.
- **Trust-asymmetry (#4):** Definite as a source rule (R3f, #05 explicit).
  Definite as a code gap (`Bot.OnPlayObserved` and `BotMaster` sampler both
  iterate uniformly over all seats).
- **J under-specification:** Definite that #05 does not give a discrete rule.
  Source D's R3d is an extrapolation, not a quote.
- **9 under-specification in #05:** Definite. The convergence between #13's
  R3e and the existing `likelyKawesh` mechanism makes "extend to 9" the most
  internally-consistent choice but it is a secondary-source convergence, not
  a #05 quote.

Overall confidence in the verdict: **high** for the K-inversion fix
recommendation; **medium** for the trust-asymmetry recommendation (the source
is clear but the code refactor is non-trivial); **low-medium** for the 9-and-J
handler decisions (source under-specification at #05).

---

## File references

- WRITE site: `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 449–500.
- READ site: `C:\CLAUDE\WHEREDNGN\BotMaster.lua` lines 445–472.
- Initialization (per-suit subtable): `C:\CLAUDE\WHEREDNGN\Bot.lua` line 237.
- Per-round reset: `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 167–168.
- Source video #05 SRT: `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\vkY55gg-39k_05_baloot_predictions_general.ar-orig.srt` lines 530–924 (Section-6 canonical passage), supplemented by lines 1424–1444 (smallest-card length-inference).
- Source A Phase-1 report: `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_A_tahreeb_cluster1.md` — does NOT cover Section 6; only references it via downstream rules.
- Source D Phase-1 report: `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_D_predictions.md` lines 55–116 (R3a–R3f).
- Prior audit of WRITE-branch dead-code: `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\12_touching_honors.md` (the bug the v0.9.2 #12 fix addressed).
