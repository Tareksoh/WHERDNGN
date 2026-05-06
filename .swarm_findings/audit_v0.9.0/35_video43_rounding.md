# 35 — Video #43 score-rounding re-verification (v0.9.0)

**Verdict:** RESOLVED in code; saudi-rules.md Q4 doc text is STALE.

## 1. Raw transcript (`-QrykaZdosE_43_score_calculation.ar-orig.txt`)

Lines 209-220 explicit speaker quote:
- L209-211: "اذا العدد كان من واحد الى اربعه راح تقربه للواحد واذا
  كان العدد من خمسه الى تسعه راح تقربه للعشره" — "1-4 round to
  the [lower] ten; 5-9 round to the [upper] ten."
- L213: "67 راح تقربها لسبعين" — 67 → 70.
- L215: **"لو مثلا 65 راح تقربها للسبعين"** — explicit: **65 → 70 (UP).**
- L217: "لو كان 64 راح تقربها للستين" — 64 → 60.
- L219: "لو كانت 55 راح يقربها 60" — 55 → 60.

Speaker says **65 → 70 unambiguously.** Extraction is correct.

## 2. `Rules.lua:833` (HEAD v0.9.0)

```lua
local function div10(x) return math.floor((x + 5) / 10) end
```
Comment at L829-832 explicitly cites video #43 + the 65/67/64
boundary cases. **Matches the spoken rule.**

## 3. `saudi-rules.md` Q4 (line 156-161) — STALE

Still reads:
> "**Q4: Score-rounding ('5 rounds down')?** ⚠ Possible mismatch.
> `R.ScoreRound` line 698: `div10(x) = math.floor((x + 4) / 10)`…"

The cited line (698) and formula `(x + 4) / 10` are **both
obsolete** — fixed in v0.5.6 (CHANGELOG L2110-2114). Doc was
never updated. Recommend rewriting Q4 as ✓ resolved + cite
Rules.lua:833 + cite v0.5.6 / v0.5.21 fixes.

## 4. Side-scoring sites

- `Net.lua:2238-2239` (`HostResolveTakweesh`, Qaid penalty):
  `math.floor((rawA + 5) / 10)` ✓ aligned.
- `Net.lua:2956-2957` (`HostResolveSWA`, SWA-failure scoring):
  `math.floor((rawA + 5) / 10)` ✓ aligned.
- v0.5.21 CHANGELOG (L1108-1121) explicitly fixed both call-sites
  to match Rules.lua's v0.5.6 formula.

**All three div10 sites are consistent.**

## 5. Action

Single doc fix needed: rewrite saudi-rules.md Q4 to reflect
resolved status. No code change.
