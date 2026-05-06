# Audit 33: video #35 (SWA term detailed) vs HEAD v0.9.0/v0.9.1

## Verdict
PARTIAL. Determinism + auto-accept routing are clean. Card-count threshold regimes (≤3 / 4 / 5+) are NOT distinguished anywhere — the code uses a binary `#hand <= 4` admit gate plus a single uniform permission flow. Player-side UI does not prevent or warn at 5+ cards.

## Evidence

### 1. 5+ "mandatory permission" — NOT distinct from 4-card flow
- `Bot.PickSWA` (Bot.lua:3525): `if not hand or #hand == 0 or #hand > 4 then return false end`
  - Bots CANNOT initiate SWA at 5+ cards at all. The video's "5+ requires تستاذن" rule is collapsed into "bots don't try".
- `N.LocalSWA` (Net.lua:2452): NO hand-count cap. Player can call SWA at 5, 6, 7, or 8 cards remaining.
  - All counts route through the same `needPerm` permission flow (line 2481). The pre-v0.5.17 code had a `handCount >= 4` gate which was removed so the banner shows the caller's hand "in every scenario". Comment at line 2480 confirms this is intentional.
- Net.lua:3974 host-bot dispatch path: also gated by `Bot.PickSWA` returning false at >4, so 5+ host-bot SWA never fires.
- No code path differentiates 5+ from 4 cards: same broadcast (`MSG_SWA_REQ`), same `K.SWA_TIMEOUT_SEC=5` window, same opponent-bot auto-accept, same resolver.

### 2. جلسة (jalsah) — does not exist
- No `jalsah`, `jalsa`, `swaThreshold`, or table-rule abstraction in Constants.lua, State.lua, or anywhere else.
- Only related toggles: `WHEREDNGNDB.allowSWA` (master on/off) and `WHEREDNGNDB.swaRequiresPermission` (force permission flow at any count).
- The "جلسة-permission for 4, mandatory for 5+" distinction from the video has no representation. Permission is uniformly required (default) or uniformly skipped — no per-count regime.

### 3. Player-side UI enforcement — NONE at 5+
- UI.lua:2011 — SWA button is shown whenever `swaEnabled and not swaPending`. NO hand-count check.
- A human at 5 or even 8 cards sees the SWA button identically to a 3-card position. Click → `N.LocalSWA` → permission flow fires unconditionally.
- No warning banner, no different button label, no count-based gate.

### 4. Failure modes (Qaid) — only 1 of 3 enforced
- Unsound claim → enforced via `R.IsValidSWA` + `HostResolveSWA` (Qaid awarded to opp on failure). CLEAN.
- Missing شرح (face-up dump when ordered-play required) → NOT modeled. The code resolves SWA atomically; there's no "play in order vs face-up dump" distinction.
- Skipped تستاذن at 5+ → NOT modeled (no 5+ category exists).

## Summary
Earlier audit's finding stands and is broader than stated: the codebase has a single binary "permission required / not" toggle. The video's three-regime model (≤3 instant / 4 جلسة-conditional / 5+ mandatory) is not implemented. Bots are conservatively capped at ≤4; humans have no count-based UI restriction at all. Two of three Qaid failure modes (شرح-missing, permission-skip) are unrepresented.
