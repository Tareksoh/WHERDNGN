# Video #05 (التوقعات) re-verification vs HEAD v0.9.0

## Verdict: PARTIAL — claim 1 OK, claim 2 BUG (write site dead), claim 3 OK (#05), claim 4 OK

---

## 1. Sun K-dump void inference (Tasgheer-derived) — WIRED, CORRECT

**Transcript:** lines 78-83. Speaker: "اذا هذا الخصم لعب الشايب احتمال يكون عنده
عشره فقط فهو لعبه الشايب الاصغر من العشره لكن هل ممكن يكون عنده البنت ولا الولد
لا مستحيل لو عنده كان لعبها بدال الشايب لانها اصغر من الشايب." → "if opp played K
they may hold T only; impossible they hold Q/J — would have played those instead
because they are smaller-than-K."

**Code:** `Bot.lua:340-376` (v0.7.2 fix). Wires K and T (correctly hedges Q out at
the speaker's 90% confidence boundary). Sets `mem.void[leadSuit] = true` when
opp follows lead with K/T and loses. Source comment cites video 05 Section 11 rule 1.
Match.

## 2. Touching-honors WRITE site at Bot.lua:442 — DEAD CODE (BUG CONFIRMED)

**Transcript:** lines 54-59. Speaker explicitly: "في اصول البلوت اذا خويك لعب
عشره ... معناته مع الشايب واذا الشايب اتلعب ... معناته مع البنت" → "as a
foundation of Baloot: if your partner plays T → he is with K; if [partner] plays
K → with Q." Confirmed verbatim T→K, K→Q, Q→J chain.

**Code BUG at `Bot.lua:442-472`:**
```lua
if not wasIllegal and contract and trick and trick.plays
   and #trick.plays >= 2 and style.topTouchSignal then
```
Variable `trick` is **never declared** in `Bot.OnPlayObserved` (function spans
lines 313-end-of-fn). Only `trickPlays` is locally bound (line 396). `trick` has
no global binding either (`grep -n "^trick\|^local trick$\|^trick ="` returns
zero hits in Bot.lua). Lua 5.1 evaluates `trick` to `nil` → predicate always
false → entire `topTouchSignal` ledger is **never written**. Read site at
`BotMaster.lua:453-454` consequently iterates an empty table forever. Section 6
rules 1-4 (Definite, video 05) marketed as wired in v0.9.0 are NON-functional.

Fix: change `trick` → `S.s.trick` (or bind `local trick = S.s.trick` near line
395 alongside `trickPlays`).

## 3. Inverse-dump asymmetry: video #05 attribution — CONFIRMED

Transcript Sun section: line 75 "95% ما عندي اصغر من عشره" (dump-HIGHEST).
Hokm section: lines 222-227 "اذا انت لعبت ولد الحكم في البدايه وهذا لعب ثمانيه
الحكم صعب يكون عنده سبعه الحكم" → opp plays LOWEST trump under your J. Both
asymmetric halves are explicitly in video #05 (transcript lines 204-244 for the
Hokm side). Extracted-MD rules at lines 39 and 43 correctly attribute. Video #09
is Tahreeb-only — does NOT contain this rule. v0.7.2 wiring stands; #09 is
unrelated.

## 4. Trump-count fundamental + 5-trump pigeonhole — IN TRANSCRIPT

Transcript lines 234-241: speaker walks through "4 احكام راحت وهنا اثنين وهنا
واحد كم باقي باقي حكم بالعقل ... راح يكون عند خوية" — 4 trumps shown, 1 left,
forced to one seat by elimination. Lines 270-275: 5-trump example "اربع احكام
باقي ... ثلاثه احكام ثلاثه هنا" — three remaining trumps all pinned to one
opponent by pigeonhole. Extracted MD rules at lines 41-42 match. Sampler J/9-pin
already partially implements (BotMaster H-1); generalized pin not yet wired.
