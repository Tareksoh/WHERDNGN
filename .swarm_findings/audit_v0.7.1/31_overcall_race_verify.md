# 31 — v0.7.0 Sun-overcall Race-A verification

## Claim review

Finding 12 alleges `N._OnOvercallResolve` (Net.lua 1096-1105) discards
the MSG_OVERCALL_RESOLVE wire payload (`takenStr`, `by`, `otype`) and
instead re-runs `S.FinalizeOvercall` against the remote's
locally-recorded decisions. If MSG_OVERCALL_DECISION frames are
reordered or dropped relative to the RESOLVE frame, the remote's
recomputed result diverges from the host's authoritative result.
Self-correcting only when the host's own result is `taken=true`
(which triggers a follow-up MSG_CONTRACT — `_HostResolveOvercall`
1182-1189). For `taken=false`, no MSG_CONTRACT is sent.

## Payload usage

```
function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    if S.FinalizeOvercall then S.FinalizeOvercall() end          -- 1103
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end
```

`takenStr`, `by`, `otype` are received and never read. The remote
calls `S.FinalizeOvercall()` blindly, which calls
`R.ResolveOvercall(s.overcall.decisions, s.contract, ...)` (Rules.lua
548) — purely a function of the remote's local `decisions` table.
**Confirmed: payload is ignored.**

## Self-correcting paths

Host side (`_HostResolveOvercall`, 1169-1200):

- `result.taken == true` → `N.SendOvercallResolve(...)` then
  `N.SendContract(bidder, type, trump)` at 1187. The follow-up
  MSG_CONTRACT does **not** self-correct because `S.ApplyContract`
  has an idempotence guard (State.lua 988-993): if the remote's
  re-derived contract happens to match the host's broadcast (same
  bidder/type/trump), nothing changes; if they differ, the second
  MSG_CONTRACT *does* overwrite remote-side. So `taken=true` with
  divergent payload **is** self-corrected by MSG_CONTRACT.
- `result.taken == false` → only MSG_OVERCALL_RESOLVE is sent, no
  MSG_CONTRACT (1182 gate). **No self-correction available.**

## Triggering scenario

Host: seat-1 dealer, seat-2 bid Hokm-Spades. Bidder waives, all
non-bidders waive → host result `{taken=false}`. Host broadcasts:

1. MSG_OVERCALL_DECISION (seat=2, WAIVE)
2. MSG_OVERCALL_DECISION (seat=3, WAIVE)
3. MSG_OVERCALL_DECISION (seat=4, WAIVE)
4. MSG_OVERCALL_DECISION (seat=1, WAIVE)
5. MSG_OVERCALL_RESOLVE (taken=0, by=0, type="")

Now imagine seat-3's MSG_OVERCALL_DECISION (#2) is delayed/dropped
on Remote-A. Remote-A receives 1, 3, 4, 5 (and seat-3's frame
arrives after RESOLVE, or never). When Remote-A processes RESOLVE,
its `s.overcall.decisions = {[2]=W,[4]=W,[1]=W}` (seat-3 missing).
`R.ResolveOvercall` sees an undecided seat — its handling depends on
its policy. Walking Rules.lua 548+ confirms it iterates 1..4 and
ignores `nil` slots, so the result is still `taken=false`. **In
this all-WAIVE scenario divergence is benign.**

A genuinely divergent case: bidder=2 UPGRADE, seat-3 TAKE. If
Remote-A's seat-3 TAKE frame arrives after RESOLVE while seat-2's
UPGRADE has been recorded, `R.ResolveOvercall` sees only the
UPGRADE → `result.taken=true, type="UPGRADE"`. Host saw both →
priority TAKE wins → `result.taken=true, type="TAKE", by=3`. Both
remote and host end with `taken=true` but **different bidders/types**
— and because both are `taken=true`, the host's MSG_CONTRACT *does*
fire and overwrites Remote-A. **Self-corrected.**

The truly hostile race is: any case where the host's local view
yields `taken=false` but a remote's local view (with one extra
delayed-decision frame already in `decisions`) would yield
`taken=true`. This requires the remote to have *more* decisions
recorded than the host did at resolve time — only possible if the
host opens the window, decisions stream in, host hits the 5s timeout
or all-decided check, broadcasts RESOLVE, then a stray
MSG_OVERCALL_DECISION echo arrives at the remote *before* RESOLVE.
On WoW addon channel, frames ship in send-order over a single ack
queue; reorder is rare but **possible across throttled chunks**.

## Impact assessment

In the worst-realised case (host `taken=false`, remote re-derives
`taken=true`), the remote mutates `s.contract` to a Sun (UPGRADE) or
to a different bidder+Sun (TAKE) while the host stays Hokm. No
MSG_CONTRACT is sent to correct it. The remote will then play the
hand under a different contract: different trump availability,
different scoring multiplier (Sun is ×2), different Bel eligibility.
**Functional, not cosmetic.** First trick play will diverge — likely
detected as a card-legality desync the moment the now-Sun bidder
plays trump or the now-Hokm partner ruffs.

## Verdict

**CONFIRMED** as written. Race-A class match: remote re-derives
authoritative state from its own incomplete view rather than trusting
the host's wire payload. Real-world frequency low (decision frames
are small, throttling rarely splits them), but the failure mode is
contract divergence, not just banner text. Recommended fix: have
`_OnOvercallResolve` parse `takenStr/by/otype` and apply them
authoritatively (set `s.contract.type/bidder/trump` directly), then
clear `s.overcall = nil` and exit to PHASE_DOUBLE — bypassing
`R.ResolveOvercall` on the remote entirely. Bonus: `taken=false`
remains a no-op as expected.
