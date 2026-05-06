# B-Bot-04 — `pickLead` v0.10.2 M8 Sun-bidder mardoofa probe branch

Track-B code review of the M8 Sun-bidder/partner trick-1 mardoofa-probe lead added in v0.10.2.

Files inspected:
- `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 1703-2461 (`pickLead`)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` line 1806-1823 (M8 branch itself)
- `C:\CLAUDE\WHEREDNGN\CHANGELOG.md` lines 50-59 (M8 entry)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\03b_secrets_pro_2.txt` lines 14-16 (Pro-2 §2 / L08)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X4_pro2_deal.md` (MF-2)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\wvFAxUMggnY_41_play_sun_basics.ar-orig.txt` (video #41)
- `C:\CLAUDE\WHEREDNGN\tests\test_state_bot.lua` lines 1645-1677 (J.2 test pins)
- `C:\CLAUDE\WHEREDNGN\Net.lua` lines 2001-2024 (`HostFinishDeal` — trick-1 leader)

---

## The branch under review

`Bot.lua` lines 1806-1823:

```lua
if Bot.IsAdvanced() and contract.type == K.BID_SUN
   and trickNum == 1
   and contract.bidder
   and myTeam == R.TeamOf(contract.bidder) then
    local hasA = { S = false, H = false, D = false, C = false }
    local hasT = { S = false, H = false, D = false, C = false }
    local aceCard = { S = nil, H = nil, D = nil, C = nil }
    for _, c in ipairs(legal) do
        local r, su = C.Rank(c), C.Suit(c)
        if r == "A" then hasA[su] = true; aceCard[su] = c
        elseif r == "T" then hasT[su] = true end
    end
    for _, su in ipairs({ "S", "H", "D", "C" }) do
        if hasA[su] and hasT[su] and aceCard[su] then
            return aceCard[su]
        end
    end
end
```

Located between the trick-8/sweep-pursuit block (ends line 1788) and the Hokm "highest-unplayed in non-trump" branch (line 1829), which puts it BEFORE every other Sun fallthrough (Tahreeb, Fzloky, B-97 meld-avoid, B-77 single-opp-void, singleton-low at 2336, Sun shortest-suit at 2379, low-from-longest at 2402).

---

## Findings

### F1 — Trigger conditions: all four preconditions correctly enforced

| Precondition | Code | Status |
|---|---|---|
| Sun contract | `contract.type == K.BID_SUN` (line 1806) | OK |
| Trick 1 | `trickNum == 1` (line 1807); `trickNum = #(S.s.tricks or {}) + 1` (line 1725) | OK |
| Seat opens (lead role) | Implicit — `pickLead` is only reached when `#trick.plays == 0` (per `Bot.PickPlay` line 3398) | OK |
| Bidder OR partner-of-bidder | `myTeam == R.TeamOf(contract.bidder)` (line 1809), where `myTeam = R.TeamOf(seat)` (line 1704) | OK |
| Holds A+T of same suit | `hasA[su] and hasT[su]` per-suit scan over `legal` (lines 1818-1819) | OK |

The "seat opens" precondition is satisfied structurally: `Bot.PickPlay` (line 3398) routes to `pickLead` only when `trick.plays` is empty, i.e. the seat is the trick leader. No extra explicit check is needed.

The bidder-team test correctly intersects partner: `R.TeamOf(seat) == R.TeamOf(contract.bidder)` is true for both bidder and bidder's partner. This matches Pro-2's "obligatory on him AND on his partner" wording (Arabic: "اجبارية عليه وعلى زميله").

### F2 — Note: this branch sidesteps the `isBidderTeam` Hokm-only typo

`isBidderTeam` is set on line 1705 as `(contract.type == K.BID_HOKM and myTeam == R.TeamOf(contract.bidder))`. It evaluates to FALSE for Sun contracts. M8 deliberately re-derives the team-membership check inline (`myTeam == R.TeamOf(contract.bidder)`) instead of reusing `isBidderTeam`, which is the correct workaround. (`isBidderTeam` being Hokm-only is a separate latent issue in the file but is not in M8's scope.)

### F3 — A+T mardoofa multi-suit selection: arbitrary fixed iteration order

When the seat has TWO A+T mardoofas (e.g. ASTS plus AHTH), the for-loop at line 1818 iterates `{S, H, D, C}` and returns the FIRST match — Spades wins. Pro-2 §2 does not specify which suit to pick when multiple mardoofas exist; it just says "the mardoofa Ace … if one exists" (singular).

There's no code comment justifying the suit order. A more defensible choice would be the longest-mardoofa-suit (more length behind the A+T = stronger probe) or the shortest (faster discovery), but neither is sourced. The hardcoded `{S, H, D, C}` order is functionally fine but is **arbitrary**, and no test pin protects the ordering choice.

Minor concern: if a future probe-suit refinement is wanted (e.g. to lead from the suit where a meld is most likely), the for-loop is the natural extension point. Currently no such refinement.

### F4 — Tier gate: Advanced+ correctly enforced; Basic falls through

`Bot.IsAdvanced()` (line 48-55) returns true for Advanced, M3lm, Fzloky, and Saudi Master tiers. Basic bots return false → the M8 branch is skipped → falls through to the existing Sun shortest-suit lead at line 2379. This matches the changelog's "Tier-gated at Advanced+" claim and the test's negative case (J.2 sanity at line 1675).

### F5 — Branch order: M8 fires BEFORE all other Sun lead fallthroughs

Verified by reading every branch between line 1806 and line 2461:

| Order | Branch | Fires on Sun trick 1 leader? |
|---|---|---|
| 1 (1709-1788) | Sweep-pursuit / trick 8 | No (gated `trickNum >= 3` or `==8`) |
| **2 (1806)** | **M8 mardoofa probe** | **Yes — fires here** |
| 3 (1829) | Hokm highest-unplayed-non-trump | No (Hokm-only) |
| 4 (1855-1944) | Tahreeb partner-pref / opp-avoid | Yes, can fire later if M8 falls through |
| 5 (1946-1973) | Fzloky pref/avoid | Yes, later fallthrough |
| 6 (1975-2003) | B-97 opp-meld-suit avoid | Yes, later fallthrough |
| 7 (2005-2028) | B-82 bait avoidance | Yes, later fallthrough |
| 8 (2054-2215) | Bidder-only Hokm trump-pull | No (Hokm-only) |
| 9 (2298-2312) | Free-trick suit | Yes, later fallthrough |
| 10 (2314-2334) | B-77 single-opp-void boss | No (Hokm-only) |
| 11 (2336-2369) | Singleton-low | Yes, later fallthrough |
| 12 (2371-2400) | **Sun shortest-suit-low** | Yes, later fallthrough — exactly the branch CHANGELOG says M8 supersedes |
| 13 (2402-2441) | Low-from-longest | Yes, later fallthrough |
| 14 (2443-2460) | Lowest legal trump | Sun has no trump |

Confirms changelog claim: M8 is placed BEFORE the singleton-low fallthrough (line 2336) AND the Sun shortest-suit lead (line 2379). The branch ordering is correct.

### F6 — Conflict resolution: A+T mardoofa wins over singleton-A in another suit

If a hand has BOTH an A+T mardoofa in one suit AND a high-side singleton-A in another, the M8 branch (line 1806) returns the mardoofa Ace before the singleton branch (line 2336) is reached. This is the **correct** Saudi-pro behaviour: the mardoofa Ace has a T cover behind it; the naked singleton-A would be exposed if led. Pro-2 §2's intent is specifically about the *covered* (مغطى) Ace.

### F7 — Trick-1 leader determination: dealer's left, NOT bidder

Per `Net.HostFinishDeal` line 2020:
```lua
local leader = (S.s.dealer % 4) + 1
```

The first trick is led by the seat to the dealer's left. The bidder may or may not be that seat. So the M8 branch can fire in three scenarios:
1. Dealer's left == bidder → bidder leads → M8 picks mardoofa Ace.
2. Dealer's left == bidder's partner → partner leads → M8 picks mardoofa Ace (in partner's hand).
3. Dealer's left == an opponent → bidder/partner does NOT lead → `pickLead` is not called for them on trick 1; M8's gate `myTeam == R.TeamOf(contract.bidder)` fails for the actual leader (an opponent), so the branch correctly does not fire for opps.

All three cases handled correctly. The "obligatory on partner" wording from Pro-2 is satisfied because partner only triggers M8 when partner is the actual leader (i.e. dealer's left).

### F8 — Anti-rules / exceptions: NONE in Pro-2 §2

The Pro-2 §2 text I read at `_pdf_extracted\03b_secrets_pro_2.txt` lines 14-16 contains zero conditional exceptions to the rule. The rule is stated unconditionally: "if Sun and on lead, MUST play mardoofa Ace if one exists; obligatory on him AND his partner."

The task prompt asks about hypothetical exceptions like "leading would set up opp Kaboot." That concern is NOT in the Pro-2 source text — it's a defensive-style consideration that would belong in a separate strategy doc. M8 implements Pro-2 verbatim with no carve-outs. This is fine if the rule is genuinely unconditional, but worth flagging for awareness.

### F9 — Source-trail: SINGLE-SOURCE WEAKNESS

Per task scope, I checked:
- **Pro-2 PDF §2** (`03b_secrets_pro_2.txt`): contains the rule explicitly. ✓
- **Video #41** (`wvFAxUMggnY_41_play_sun_basics.ar-orig.txt`): basic Sun-play tutorial; covers follow-suit mechanics, last-trick wins, "biggest eats smallest." Does NOT mention the L08 mardoofa-lead mandate at all.
- **xref_X4_pro2_deal.md**: cites only Pro-2 PDF §2 for L08; flags it as "named pro convention."
- **decision-trees.md / opening-leads.md**: mardoofa is used as a *bidding* heuristic (S-8 sunStrength bonus, BOT_SUN_MARDOOFA_PAIR_CAP), but no strategy doc cross-references the L08 *lead* rule.
- **No corroborating video transcript** in `docs/strategy/_transcripts` references mandatory mardoofa-Ace opening leads in Sun.

This is a **single-source rule**. The xref_X4 confidence assessment ("High for L08 verdict") concerns whether the rule was previously implemented (it wasn't), not whether the rule itself is well-attested. Pro-2 PDF is one document; corroboration from independent source-of-truth (video commentary, second written rulebook) is absent.

### F10 — Test coverage: positive + negative-defender, NOT partner-of-bidder

`tests/test_state_bot.lua` Section J.2 (lines 1645-1677) has:
- J.2 positive: bidder=2, seat 2 holds AH+TH mardoofa, expects AH lead. ✓
- J.2 negative ("sanity"): seat 1 (defender) holds A+T mardoofa, expects fall-through to 7C (shortest-suit-low). ✓

**Missing test coverage:** the partner-of-bidder case. The branch fires for `myTeam == R.TeamOf(contract.bidder)` which is true for both bidder AND partner. There's no test pin where:
- bidder = seat 2 (partner = seat 4)
- seat 4 leads (e.g., dealer = 3 → leader = 4)
- seat 4 holds A+T mardoofa
- expect mardoofa Ace lead (not the existing fallthroughs).

The Pro-2 wording specifically calls out partner ("obligatory on him AND his partner"). The current implementation is correct for partner, but the test coverage doesn't pin it. A future refactor could regress this case silently.

**Missing test coverage:** the multi-mardoofa case (two A+T pairs). The {S,H,D,C} suit-iteration order isn't pinned by any test.

### F11 — Bidder always populated for Sun by trick 1

`State.lua:1003` and `1015` set `s.contract.bidder = result.by` during bid resolution; trick 1 only begins after `HostFinishDeal` runs, by which point `contract.bidder` is set. The `and contract.bidder` guard on line 1808 is defensive but won't typically be hit on real plays. Fine to leave.

### F12 — Comment discrepancy with changelog

The changelog (line 50) says: "Sun seat-1 mardoofa probe lead." The Bot.lua comment (line 1790-1805) more accurately says "Sun bidder-team mardoofa probe lead on trick 1." The "seat-1" framing in the changelog is misleading — the leader is dealer's-left, not literally seat 1. This is cosmetic but minor inaccuracy in the changelog header. The code comment is correct; the changelog has the misleading title.

---

## Issues & gaps

### Inside M8 scope

| ID | Severity | Issue |
|---|---|---|
| **M8-i1** | Low | Multi-mardoofa suit iteration order is hardcoded `{S,H,D,C}` with no rationale comment and no test pin. Pro-2 §2 doesn't specify a tiebreaker; defender's choice would be `longest-mardoofa-suit` (probe-strength heuristic) but this is unsourced. |
| **M8-i2** | Low | No test pin for the partner-of-bidder leader case. The branch correctly handles it, but a future refactor could silently regress it. |
| **M8-i3** | Doc | Changelog title "seat-1 mardoofa probe lead" is misleading; trick-1 leader is dealer's-left, not seat 1. Code comment is correct. |
| **M8-i4** | Source | Single-source rule (Pro-2 PDF §2 only). Video #41 does not corroborate. Worth flagging for downstream calibration before relying on it as authoritative. |

### Out of M8 scope but adjacent (informational only)

| ID | Severity | Issue |
|---|---|---|
| **adj-1** | (Pre-existing) | `pickLead` line 1705's `isBidderTeam` is gated to `K.BID_HOKM` only — so for Sun contracts it is always false. M8 correctly sidesteps this by inlining the team check. Other Sun branches that *did* rely on `isBidderTeam` would silently no-op for Sun, but I didn't find any such reliance in `pickLead` for Sun-relevant branches. Still worth a documented audit pass. |
| **adj-2** | (Pre-existing) | Line 2130's `bidderTeam` is undefined inside `pickLead` (defined elsewhere in `evaluateTrump`); evaluates to `nil`, so `R.TeamOf(s2) ~= bidderTeam` is always true. Inside the `if isBidderTeam and isBidder` block (Hokm only), so impact is "all opponents are conservativeOpp candidates." Not in M8 scope but flagged for the same Hokm-bidder branch. |

---

## Verdict

**M8 is correctly implemented for the rule it sources.**

- Trigger conditions, branch order, tier gate, and team-membership check are all correct.
- A+T mardoofa correctly wins over singleton-A in another suit.
- Partner-of-bidder is correctly bound (matches Pro-2's "him AND his partner" wording).
- The code's `myTeam == R.TeamOf(contract.bidder)` inline check correctly bypasses the latent `isBidderTeam` Hokm-only typo.
- Pro-2 §2 has no conditional exceptions to the rule, and M8 codes it unconditionally.

**Main residual concerns are not bugs:**

1. **Single-source weakness (M8-i4)**: only Pro-2 PDF §2 attests this rule; no corroborating video transcript was found in this scope. If Pro-2's interpretation is wrong or context-dependent, M8 would impose a wrong play.
2. **Test gap (M8-i2)**: partner-of-bidder leader case isn't pinned; multi-mardoofa tiebreaker isn't pinned.
3. **Multi-mardoofa tiebreaker (M8-i1)**: arbitrary `{S,H,D,C}` ordering with no rationale.

No code changes recommended; M8 ships as-is. Recommend **adding two test pins** (partner-of-bidder leader case; two-mardoofa case) and a one-line comment in the M8 branch acknowledging the hardcoded iteration order. The rule-attestation gap is a research-side item, not a code issue.

---

## Confidence

**High** for the verdict that M8 correctly implements Pro-2 §2 / L08:
- Read all of `pickLead` (lines 1703-2461) to confirm branch order and gating.
- Read the M8 branch implementation in full (1806-1823); both reachable for bidder and partner.
- Read the trick-1 leader assignment (`Net.HostFinishDeal:2020`) confirming dealer's-left is leader.
- Read Pro-2 PDF §2 verbatim to confirm rule wording covers "him AND his partner" and has no exceptions.
- Read the J.2 test pins to confirm positive bidder + negative defender are covered (and that partner / multi-mardoofa are NOT covered).

**Medium** for the single-source-weakness flag:
- I scanned `docs\strategy\_transcripts` for "mardoofa" and found 41 hits, all about *bidding* (mardoofa as a Sun-bid criterion / bonus / cover anchor), none about the *opening-lead mandate*. Video #41 specifically doesn't mention it. It's possible a corroborating video exists in a transcript I didn't enumerate, but Pro-2 §2 is the only authoritative source explicitly named in the swarm-findings xref tree (X4 cites only Pro-2). If the rule turns out to be a Pro-2 author idiosyncrasy rather than universal Saudi-pro convention, M8 imposes it on Advanced+ bots regardless.

No code was modified.
