# D-RT-16 — Cross-version skew between v0.9.6 client and v0.10.2 host

**Scope:** mixed-version table where some seats run **v0.9.6** (last
tag before the v0.10.0 silent-bug review) and others run **v0.10.2**
(post-review HEAD). For each v0.10.x change, we identify whether the
divergence is observable on the wire, what the worst-case desync
looks like, and whether the right answer is *force-upgrade* (refuse
to seat older clients) or *graceful-degrade* (accept the older
client and live with the divergence).

**Read:**

- `WHEREDNGN.toc` line 5 — `## Version: @project-version@` (BigWigsMods
  packager substitutes the tag at build time; `K.GetAddonVersion`
  in `Constants.lua:146-157` returns `"dev"` when not packaged).
- `Net.lua` `SendHostAnnounce` (line 88-93), `SendJoin` (95-97),
  `SendLobby` (99-113), `_OnHost` (684-708), `_OnJoin` (710-729),
  `_OnLobby` (731-767) — handshake wire format and version tracking.
- `State.lua:94` `s.peerVersions = {}` — keyed by `S.NormalizeName(sender)`
  on write, read by `Name-Realm` in UI; v0.7.1 audit X9-4 normalized
  this. `State.lua:717,724` — survives `/reload` via the savedvars
  hydration path.
- `.swarm_findings/review_v0.10.0/` — all R1/R5/R6/X3/X4/X5 source
  triangulations and the M1/M2 deferred items.
- Commits `c013031` (v0.10.0), `b89e9d9` (v0.10.1), `fe3f8fb` (v0.10.2)
  via `git show`.

**Method:** confirmed each v0.10.x change against the v0.9.6 baseline
using `git show 9d05fa7:<file>`. For each change, asked: (a) does the
wire differ? (b) does authoritative scoring/legality differ? (c)
which seat is authoritative for the result? (d) is the divergence
silent or detectable? **No code modified.**

---

## Version handshake — what the seats actually know about each other

`Net.lua:88` (`SendHostAnnounce`): `H;<gameID>;<version>` — host
broadcasts on every lobby tick.
`Net.lua:95` (`SendJoin`): `J;<gameID>;<version>` — joiner
declares.
`Net.lua:99` (`SendLobby`): `L;<gameID>;<n1>;<n2>;<n3>;<n4>;<botMask4>;<hostVersion>` — host's lobby payload trails the host's
version.

`Net.lua:689` / `714` / `763` — receiver writes
`S.s.peerVersions[normalizedSender] = version` for each.
`UI.lua:2803-2811` — UI renders the version per seat in the lobby:
green if it matches mine, **red if it doesn't**, no enforcement.

**Critical observation:** mismatch is *displayed* but never *blocks
seating*. A v0.9.6 client and a v0.10.2 host see each other's red
tag and can still start the round.

The v0.9.6 → v0.10.2 wire format is byte-compatible: every field
either v0.9.6 reads (extra fields are tolerated by `split` +
positional access) or extra fields are absent and `fields[N]` returns
`nil` which v0.10.2 senders coalesce. So **no version-skew triggers a
parse error**; every divergence below is a *silent semantic drift*.

---

## Per-change cross-version impact

### Change 1 — R1 Bel-100 score-split rule (v0.10.0)

**v0.9.6 (`R.CanBel`):** asymmetric bidder/defender rule —
`bidderCum >= 101 AND defenderCum <= 100`.
**v0.10.2 (`R.CanBel`):** score-split, role-irrelevant —
`caller.cum <= 100 AND opposite.cum > 100`.

**Wire:** zero. `K.MSG_DOUBLE` payload is unchanged. The decision
runs locally on each client before sending the Bel.

**Cross-version impact:**

- The **UI button visibility differs across versions**. In a
  bidder-trailing scenario (e.g., bidder team at 60, defender at
  150), v0.10.2 makes the button live for *both* teams as long as
  the score-split direction is right; v0.9.6 only lets the bidder-
  trailing-defender click it.
- **Authoritative gate is host-side `Net._SunBelAllowed`**
  (`Net.lua:71-83`). The host's version determines whether a Bel
  *actually applies* — the client's UI is just a hint.
- **Host v0.10.2 + Client v0.9.6:** v0.9.6 client never sees a Bel
  button in a score-split scenario its old rule rejects; v0.10.2
  host would have allowed it. Bel is silently underused. UX
  degradation, not desync — both sides still agree on the score.
- **Host v0.9.6 + Client v0.10.2:** v0.10.2 client sees the Bel
  button, clicks it, frame goes through `MSG_DOUBLE`. v0.9.6 host's
  `_SunBelAllowed` rejects it → button **vanishes locally** without
  a banner, exactly the v0.9.2 #45 UX-race bug `R.CanBel` was meant
  to close. Functional but confusing.

**Recommendation: force-upgrade.** This is a **silent UX bug** (Bel
not visible / Bel-vanishes-on-click) that the v0.9.2 #45 fix already
addressed once in single-version play. Across versions it re-opens
because the host can't honor a rule its `_SunBelAllowed` doesn't
know.

---

### Change 2 — X5 Hokm Carré-A meld emission (v0.10.0)

**v0.9.6 (`R.DetectMelds`):** `if rank == "A" and isSun then value =
K.MELD_CARRE_A_SUN end` — Hokm Carré-A falls through with `value =
nil`, the meld is silently dropped, no `MSG_MELD` is sent.
**v0.10.2:** else-branch added. Carré-A in Hokm now emits a meld
with `value = K.MELD_CARRE_OTHER` (100 raw).

**Wire:** divergent. v0.10.2 senders broadcast a real `MSG_MELD`
frame for Hokm Carré-A; v0.9.6 senders never do.

**Cross-version impact:**

- **Host v0.10.2 + Bidder v0.9.6 with Carré-A in Hokm:** the bidder
  client's `R.DetectMelds` returns no Carré-A meld → v0.9.6
  client's UI shows no declaration prompt → no `MSG_MELD` is ever
  sent → **host has no record of the carré in `S.s.meldsByTeam`**
  → bidder strict-majority threshold (R.CompareMelds), Belote-
  cancellation, and team meld total **all under-score by 100 raw
  (= ~10 gp ×mult ×Hokm)**. Cascades exactly as `xref_X5`
  describes, but caused by the *client*, not the host.
- **Host v0.9.6 + any client v0.10.2:** v0.10.2 client emits the
  `MSG_MELD` frame. v0.9.6 host's `_OnMeld` still parses it (wire
  format is unchanged — `M;<seat>;<kind>;<suit>;<top>;<cards>`).
  v0.9.6 host calls `S.ApplyMeld` which appends to `meldsByTeam`.
  But v0.9.6 `R.DetectMelds` *also runs on the host* during
  `R.ScoreRound`, and it will not produce that meld locally —
  however `meldsByTeam` is already populated from the client's
  `MSG_MELD`. **This may actually accidentally work for scoring
  *if* the v0.10.2 client always declares.** The cascade hits when
  v0.10.2 is the client and v0.9.6 is the host running its own
  `Bot.PickMeld` for a host-side bot — bots on v0.9.6 host won't
  declare. **Silent under-score on host-side bots only.**

**Recommendation: force-upgrade.** The score divergence is
asymmetric (one side records 100 meld points, other side doesn't,
divergent cumulative cascading to Bel eligibility, Gahwa thresholds,
end-of-game) — this is exactly the silent-scoring class the v0.10.0
review was created to close. Cannot live with mixed-version play.

---

### Change 3 — R5 Carré-A in Sun 200→400 raw (v0.10.0)

**v0.9.6 (`Constants.lua`):** `K.MELD_CARRE_A_SUN = 200` (Sun×2 →
final 40 gp, half the canonical 80 gp).
**v0.10.2:** `K.MELD_CARRE_A_SUN = 400` (Sun×2 → final 80 gp).

**Wire:** identical. `MSG_MELD` carries the meld definition (kind /
suit / top / cards), **not** the raw value. `R.SumMeldValue` runs
locally on each receiver.

**Cross-version impact:**

- **`R.ScoreRound` runs on every seat for display + on host for
  authoritative score.** The host's score is the one that gets
  echoed in `MSG_ROUND` and overrides locally-computed totals (`Net.lua`
  `_OnRound` calls `S.ApplyRoundResult` which sets
  `S.s.cumulative` from the wire value).
- **Host v0.10.2 + Client v0.9.6:** host scores Carré-A in Sun at
  400 raw → 80 gp final → broadcasts via `MSG_ROUND` →
  v0.9.6 client receives the wire totals and adopts them. No
  divergence on the canonical score. v0.9.6 client's local
  `R.ScoreRound` *would* have produced 40 gp, but only the host's
  number propagates. **Cum drift only if a client also runs
  R.ScoreRound for their own decision-making** (e.g.,
  Bot.PickGahwa Sun-cum check) — yes, `Bot.PickGahwa` does read
  `S.s.cumulative` which is host-authoritative, so the host's
  number wins. **Safe.**
- **Host v0.9.6 + Client v0.10.2:** host scores 200 raw → 40 gp →
  v0.10.2 client adopts the under-scored cum. **Active under-score
  on the table.** Same canonical-bug class as single-version
  v0.9.6 play.

**Recommendation: force-upgrade.** The under-score itself is the
v0.9.6 bug; it doesn't get *worse* in mixed play but it doesn't
get *fixed* either when the host is on v0.9.6. The fix only takes
effect when the **host** is on v0.10.2.

---

### Change 4 — R6 Touching-honors K-signal inversion (v0.10.0)

**v0.9.6 (`Bot.lua` touching-honors handler):** K-played pinned Q
to that seat (inverted — actively mispredicting).
**v0.10.2:** K-played → cleared{Q,J} negative-bias (now correct).

**Wire:** zero. Pure local-bot heuristic. No broadcast frame
involved.

**Cross-version impact:**

- ISMCTS sampling on v0.9.6 picks slightly worse moves on
  touching-honors situations than v0.10.2 — but **only on its own
  bot turns**. Their plays still go out through `MSG_PLAY`, and the
  card itself is what matters for the trick. Skew is in *play
  quality*, not in legality / scoring / wire.
- A v0.9.6 host with bots reads opp-side touching-honors
  inverted; a v0.10.2 host doesn't. This is invisible on the wire
  (no opt-in declaration) and invisible to other clients except
  via long-run win-rate.

**Recommendation: graceful-degrade.** This is purely a bot-decision
quality difference. Mixed-version tables with v0.9.6 bots play
slightly weaker bot opponents on the affected seats. No score
divergence, no legality dispute, no wire issue.

---

### Change 5 — M3 false-AKA detection (v0.10.2)

**v0.9.6:** no host-side AKA validation. A bot or buggy client
declaring AKA on a non-boss card silently goes through.
**v0.10.2 (`State.lua:1219+`, `S.ApplyPlay`):** host validates
AKA truth-claim. If the lead isn't the highest-unplayed of the
AKA'd suit, lead is marked `.illegal=true` with reason
`"false AKA"`; existing Takweesh resolution path catches it as
a Qaid against the false-caller's team.

**Wire:** zero NEW frames. `MSG_AKA` and `MSG_PLAY` are
unchanged; `MSG_TAKWEESH` already exists.

**Cross-version impact:**

- **Host v0.10.2 + Client v0.9.6:** v0.9.6 client's bot
  could (in theory) emit a false `MSG_AKA` followed by a non-boss
  lead. v0.10.2 host's `S.ApplyPlay` flags it `.illegal`. If any
  seat calls Takweesh, the Qaid resolves against the v0.9.6
  caller's team. **Cross-version trust works in v0.10.2's favor.**
- **Host v0.9.6 + Client v0.10.2:** v0.10.2 client's
  `S.ApplyPlay` runs on the local copy, but **only the host's
  apply is authoritative** (the client's `S.ApplyPlay` runs after
  receiving `MSG_PLAY` and has the same path). v0.9.6 host
  doesn't validate, so a v0.9.6 host-side bot that emits a false
  AKA gets away with it — Takweesh window opens but no one calls
  it because v0.10.2 client's bot would have to be the one
  calling, and bot-driven Takweesh runs on the host. **False-AKA
  goes undetected on a v0.9.6 host.**
- **Trust asymmetry:** the host is the AKA judge per the v0.10.2
  design. Clients can't independently flag `.illegal` because
  `s.isHost` gates the entire branch.

**Recommendation: force-upgrade.** This is a *new defensive
invariant*. A mixed-version table where the host is v0.9.6
provides false-AKA protection of v0.9.6 (i.e., none) — a
malicious or buggy v0.9.6 client could grief a v0.10.2 client by
declaring AKA on a non-boss and stealing the trick lead's value.

---

### Change 6 — M4 AKA-receiver legality relief (v0.10.2)

**v0.9.6 (`R.IsLegalPlay`):** signature
`(card, hand, trick, contract, seat)` — 5 params. Always forces
must-trump-ruff for void+has-trump receivers.
**v0.10.2:** signature
`(card, hand, trick, contract, seat, akaCalled)` — 6 params, opt-in
relief: when partner has AKA'd on the led suit, the receiver
exempt from must-trump.

**Wire:** zero — `R.IsLegalPlay` is a pure predicate, not
broadcast. But the *consequence* is wire-visible: a v0.10.2 client
plays a discard that v0.9.6 considers illegal.

**Cross-version impact (most subtle and dangerous):**

- **Host v0.10.2 + Client v0.9.6, AKA active:** v0.10.2 host
  signals AKA via `MSG_AKA`. v0.9.6 receiver (partner of caller)
  is void + has trump. v0.9.6 `R.IsLegalPlay` (no `akaCalled`
  param) forces must-trump → bot picks a trump → MSG_PLAY trump.
  This is *legal under both versions* (must-trump is permitted,
  it's just no longer mandatory). **No problem.**
- **Host v0.9.6 + Client v0.10.2, AKA active:** v0.10.2
  receiver's `Bot.legalPlaysFor` (M4-aware) lets the bot discard
  a low non-trump. The bot picks the discard, sends `MSG_PLAY`.
  v0.9.6 host's `S.ApplyPlay` runs `R.IsLegalPlay(card, hand,
  trick, contract, seat)` — **5-param call, no `akaCalled`** —
  which **rejects** the discard as illegal must-trump-ruff.
  **The host marks the play `.illegal=true`. Any seat then has a
  Takweesh window on a play that v0.10.2 considered legal.**
  v0.9.6 bots will see the `.illegal` flag and a v0.9.6
  bot-driven Takweesh might fire → **false Qaid against the
  v0.10.2 client's team.**
- **Disagreement on legality is the worst class of cross-version
  bug.** A v0.10.2 client who *correctly* invokes the M4 relief
  gets *penalized* by a v0.9.6 host.

**Recommendation: force-upgrade — this one is hard-blocking.** The
divergence is *not* benign; it produces wrong Qaid penalties
against the v0.10.2 client's team on a v0.9.6 host. The fact that
v0.10.2 made `akaCalled` *optional* (defaulting to AKA-blind for
simulators) does not save mixed-version play, because the host
calls it without the param.

---

### Change 7 — M8 mardoofa probe lead (v0.10.2)

**v0.9.6 (`Bot.lua` pickLead):** Sun bidder/partner with A+T
mardoofa leads the lowest card from the shortest suit (anti-probe).
**v0.10.2:** branch added BEFORE singleton-low fallthrough — leads
the Ace.

**Wire:** zero. Pure bot picker — output is a single `MSG_PLAY`
which is just a card.

**Cross-version impact:**

- v0.9.6 bots in a Sun-bidder-team seat lead the wrong opening
  card. The Ace is *legal*, just not picked. Host accepts the
  lead, trick proceeds normally.
- A v0.10.2 host doesn't run remote v0.9.6 clients' bot pickers
  (bots are host-only — see CLAUDE.md "bots live only on the
  host"). So if the host is v0.10.2, *all* bots use the M8 logic;
  if the host is v0.9.6, *all* bots use the old logic.

**Recommendation: graceful-degrade.** Bot quality difference only;
no wire / legality / scoring impact. Host version determines bot
play quality across the table.

---

### Change 8 — M1 Qaid offender melds forfeit (v0.10.1)

**v0.9.6 (`Net.lua` HostResolveTakweesh + HostResolveSWA invalid
branch):** both teams keep their own declared melds.
**v0.10.2:** offender team zeros their own melds; winner team
keeps × mult.

**Wire:** zero. The decision lives entirely in the host's
`HostResolveTakweesh` / `HostResolveSWA` Qaid branches. The wire
frame is `MSG_ROUND` (or `MSG_TAKWEESH_OUT` / `MSG_SWA_OUT`)
carrying the **final cumulative** — no breakdown.

**Cross-version impact:**

- **Host v0.10.2:** computes M1-corrected score. Wire
  `MSG_ROUND`/`MSG_SWA_OUT` carries new cum. v0.9.6 client adopts
  it via `_OnRound`. **No divergence** — host is authoritative.
- **Host v0.9.6:** keeps both teams' melds in Qaid, ~10-20 gp
  silent over-credit to offender vs M1 spec. v0.10.2 client
  adopts the wrong cum. The v0.10.2 client *would* have computed
  the correct M1 number locally if it ran `R.ScoreRound`, but
  the Qaid branch is in `Net.lua HostResolveTakweesh`, not
  `R.ScoreRound`, and only the host runs it.

**Recommendation: graceful-degrade is acceptable, force-upgrade is
preferred.** Score difference is bounded (~10-20 gp/round) and
manifests only on Qaid-triggering rounds. Host version
deterministically picks the rule. Players can live with v0.9.6-host
under-penalty if upgrade isn't possible; the wire never disagrees.

---

### Change 9 — CRIT-1 wire-tag collision: `K.MSG_RESYNC_REQ` = `K.MSG_OVERCALL_RESOLVE` = `"?"`

**Both v0.9.6 and v0.10.2:** `Constants.lua` defines:

```
K.MSG_RESYNC_REQ      = "?"   (line 181 in v0.10.2 / 177 in v0.9.6)
K.MSG_OVERCALL_RESOLVE = "?"   (line 229 in v0.10.2 / 225 in v0.9.6)
```

The dispatcher in `HandleMessage` (`Net.lua:486-628`) checks
`MSG_OVERCALL_RESOLVE` at line 543 BEFORE checking `MSG_RESYNC_REQ`
at line 620. **Every `"?"` frame routes to `_OnOvercallResolve`**.
`_OnResyncReq` is unreachable. (Confirmed in v0.9.6 — same line
ordering, same collision.)

This is the BLOCKER finding from D-RT-15 (cross-referenced).

**Cross-version impact:**

- The bug is **identical in v0.9.6 and v0.10.2**. There is no
  version where resync works correctly on the host receive path.
- The Sun-overcall feature was added in v0.7.0 (commit `a3abe18`),
  which also introduced `K.MSG_OVERCALL_RESOLVE = "?"` colliding
  with the pre-existing `K.MSG_RESYNC_REQ = "?"`. So **resync has
  been broken since v0.7.0 across all subsequent versions**,
  including v0.9.6 and v0.10.2.
- The v0.9.1 L5 fix (`expectingResyncRes` 30s window) is a
  defensive measure on the response side — it doesn't help if the
  request never reaches the host.

**Cross-version implication:** force-upgrade does NOT solve this.
The fix requires changing `K.MSG_OVERCALL_RESOLVE` to a different
character (e.g., `"!"` or any free code). That's a wire-protocol
break itself. So:

- **Same-version play:** resync is broken on every version since
  v0.7.0.
- **Mixed-version play:** resync stays broken; mixed-version is no
  worse off than same-version on this axis.
- A *future* fix for CRIT-1 will introduce a new wire-skew. The
  pre-fix client will keep sending `"?"` and the post-fix host
  will look for `"!"` (say); resync will be broken for old
  clients until they upgrade. **Plan for a versioned cutover.**

**Recommendation:** **(separate from this redteam)** open a HIGH
ticket to change `K.MSG_OVERCALL_RESOLVE` to a non-colliding tag.
When that ships, **the new version must refuse to seat
pre-fix clients** (not just warn — actively block in the host's
`_OnJoin`) because:
1. Resync was *always* broken; the user-visible regression is
   only "the new version exposes the bug instead of hiding it
   behind unreachable code."
2. The collision affects host-receive only; broadcast direction is
   the same character, but the dispatch is one-way per role.
3. We don't want a half-fixed table where the upgraded host can
   resync new clients but old clients keep silently mis-routing.

---

## Summary table

| Change | Wire-format change | Authority | Cross-version safe? | Recommendation |
|---|---|---|---|---|
| R1 Bel-100 | None | Host `_SunBelAllowed` | UX-only divergence; no score skew | **Force-upgrade** (UX confidence) |
| X5 Hokm Carré-A meld | New `MSG_MELD` from v0.10.2 only | Host scoring | **No** — silent ~10-20 gp under-score on v0.9.6 host or non-emitting client | **Force-upgrade** |
| R5 Sun Carré-A 400 | None (raw value local) | Host scoring | Bug only when host=v0.9.6; no mixed-version skew worse than single-version | **Force-upgrade** (fixes when host upgrades) |
| R6 Touching-honors | None | Local bot only | Yes — bot quality only | **Graceful-degrade** |
| M3 false-AKA | None (uses existing Takweesh) | Host `S.ApplyPlay` | v0.9.6 host cannot enforce; v0.10.2 host enforces against any client | **Force-upgrade** |
| M4 AKA legality | New `akaCalled` param to `R.IsLegalPlay` | Host `S.ApplyPlay` | **NO — actively dangerous.** v0.9.6 host marks v0.10.2 client's legal-under-M4 play as illegal → wrong Qaid | **Force-upgrade — HARD-BLOCKING** |
| M8 mardoofa probe | None | Local bot only (host-only execution) | Yes — bot quality only | **Graceful-degrade** |
| M1 Qaid offender melds | None | Host `HostResolveTakweesh` | Score varies by host version; bounded (~10-20 gp) | **Graceful-degrade ok, force-upgrade preferred** |
| CRIT-1 `"?"` collision | Pre-existing in BOTH versions | n/a — broken everywhere | Identical breakage; no mixed-version delta | **Separate HIGH fix; versioned cutover when shipped** |

---

## Final recommendation: gate seating on host

The single hard-blocking divergence is **Change 6 (M4 AKA-receiver
legality)**. A v0.9.6 host running v0.10.2 clients will mark legal
M4 discards as illegal and create false Qaid penalties. This is a
silent, score-affecting divergence with no detection path on the
v0.9.6 side.

**Concrete recommendation:** add a host-side seating gate in
`HostHandleJoin` (or `_OnJoin`) that compares `S.s.peerVersions`
against a minimum-required version string. The peerVersions write
already exists (`Net.lua:691,714,764`). The block path is roughly:

> If the joiner's version is below the host's `MIN_PEER_VERSION`,
> reject with a polite system message rather than seat them. The
> UI's red-vs-green badge stays for backwards-compatibility cases
> within an acceptable range; below the floor, no seating.

The threshold for v0.10.2 should be **>= v0.10.2** because every
v0.10.x change after v0.10.0 either tightens an invariant (M3, M4)
or corrects a host-authoritative score (R5, M1). v0.10.0 → v0.10.2
divergence is also nontrivial (M1's ~10-20 gp swing per Qaid
round), so v0.10.0 / v0.10.1 hosts running v0.10.2 clients still
produce score drift.

**Out of scope here but flagged:** CRIT-1 fix (changing
`K.MSG_OVERCALL_RESOLVE` to a free character) is a separate
wire-protocol break that *must* coordinate with this same
seating-gate threshold. When that ships, the new
`MIN_PEER_VERSION` enforcement is the mechanism that makes the
collision-fix safe — old clients can't seat, so they can't send
the colliding tag.
