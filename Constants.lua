-- Game constants: card definitions, point tables, scoring multipliers,
-- message-type tags, and tunable timings.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.K = B.K or {}
local K = B.K

-- -- Cards --------------------------------------------------------------

K.SUITS = { "S", "H", "D", "C" }   -- spades, hearts, diamonds, clubs
K.RANKS = { "7", "8", "9", "T", "J", "Q", "K", "A" }
K.RANK_INDEX = { ["7"]=1, ["8"]=2, ["9"]=3, ["T"]=4, ["J"]=5, ["Q"]=6, ["K"]=7, ["A"]=8 }
K.SUIT_INDEX = { S=1, H=2, D=3, C=4 }

K.SUIT_GLYPH  = { S = "\226\153\160", H = "\226\153\165", D = "\226\153\166", C = "\226\153\163" } -- ♠ ♥ ♦ ♣
K.SUIT_NAME   = { S = "Spades", H = "Hearts", D = "Diamonds", C = "Clubs" }

-- Suit colors for chat/log on the dark WoW chat background.
K.SUIT_COLOR  = { S = "ffffffff", H = "ffff5555", D = "ffff8800", C = "ff66ff66" }

-- Suit colors for the cream card face. Uses the four-color-deck poker
-- convention (♠ black, ♥ red, ♦ blue, ♣ green) so same-shape pairs
-- (♠/♣, ♥/♦) are unambiguous at a glance — the traditional 2-color
-- red/black scheme makes them indistinguishable at small sizes.
K.SUIT_COLOR_ONCARD = {
    S = "ff111111",  -- near-black
    H = "ffcc1f1f",  -- deep red
    D = "ff1f5fcc",  -- deep blue
    C = "ff1c8a3c",  -- forest green
}

-- WoW's default font (Friz Quadrata) lacks the U+2660-U+2666 card suit
-- glyphs and renders them as missing-glyph boxes. Arial Narrow ships with
-- WoW and includes them. Use this for any FontString that renders cards.
K.CARD_FONT = "Fonts\\ARIALN.TTF"

-- v2.0.0 (audit v1.6.1 SA-01 HIGH): optional Arabic font for in-game
-- rendering of Saudi terms (حكم / صن / بل / فور / قهوة / بلوت / etc).
-- WoW's bundled fonts (Arial Narrow / Frizz / Skurri / Morpheus) lack
-- the Arabic Unicode block, so direct «بل» renders as boxes. Bundling
-- a free Arabic font (e.g. Noto Naskh Arabic or Amiri) at the path
-- below unlocks real Arabic glyphs.
--
-- USAGE:
-- 1. Download Noto Naskh Arabic Regular (Google Fonts, OFL-licensed,
--    free for redistribution): https://fonts.google.com/noto/specimen/Noto+Naskh+Arabic
-- 2. Save the .ttf file as:
--    Interface\AddOns\WHEREDNGN\fonts\NotoNaskhArabic-Regular.ttf
-- 3. /reload — UI auto-detects the font's presence and starts using it
--    for the SaudiName helper at UI.lua. If the file is absent, the
--    helper transparently falls back to the existing romanized labels
--    (Bel / Bel x2 / Four / Gahwa).
--
-- The default value below is a path; the actual font-loading is in
-- UI.lua via the SaudiName helper, which uses pcall(SetFont, ...) to
-- detect availability without raising errors when the file is missing.
K.ARABIC_FONT = "Interface\\AddOns\\WHEREDNGN\\fonts\\NotoNaskhArabic-Regular.ttf"

-- Cached romanized↔Arabic Saudi term map. Used by UI.SaudiName(key)
-- which returns the Arabic form when ARABIC_FONT is loadable, the
-- romanized form otherwise. Keys mirror code identifiers; values are
-- {romanized, arabic} pairs.
K.SAUDI_NAMES = {
    HOKM      = { "Hokm",     "حكم"   },
    SUN       = { "Sun",      "صن"    },
    PASS      = { "Pass",     "بَسْ"  },
    WLA       = { "wla",      "ولا"   },
    BEL       = { "Bel",      "بل"    },
    BEL_X2    = { "Bel x2",   "بل×2"  },
    BEL_X3    = { "Bel x3",   "بل×3"  },
    FOUR      = { "Four",     "فور"   },
    GAHWA     = { "Gahwa",    "قهوة"  },
    BALOOT    = { "BALOOT!",  "بلوت!" },
    AKA       = { "AKA",      "إكَهْ" },
    SWA       = { "SWA",      "سوا"   },
    ASHKAL    = { "Ashkal",   "إشكل"  },
    KAWESH    = { "Kawesh",   "كاوش"  },
    QABLAK    = { "Qablak",   "قبلك"  },
    TAH       = { "TAH!",     "طاح!"  },
}

-- -- Card points -------------------------------------------------------
-- HOKM trump: J=20, 9=14, A=11, 10=10, K=4, Q=3, 8/7=0  (sum 62)
-- HOKM off-trump and SUN all suits: A=11, 10=10, K=4, Q=3, J=2, 9/8/7=0 (sum 30/suit)

K.POINTS_TRUMP_HOKM = {
    ["7"]=0, ["8"]=0, ["9"]=14, ["T"]=10, ["J"]=20, ["Q"]=3, ["K"]=4, ["A"]=11,
}
K.POINTS_PLAIN = {
    ["7"]=0, ["8"]=0, ["9"]=0, ["T"]=10, ["J"]=2, ["Q"]=3, ["K"]=4, ["A"]=11,
}

-- Trick-resolution rank: higher index wins.
K.RANK_TRUMP_HOKM = { ["7"]=1, ["8"]=2, ["Q"]=3, ["K"]=4, ["T"]=5, ["A"]=6, ["9"]=7, ["J"]=8 }
K.RANK_PLAIN      = { ["7"]=1, ["8"]=2, ["9"]=3, ["J"]=4, ["Q"]=5, ["K"]=6, ["T"]=7, ["A"]=8 }

K.LAST_TRICK_BONUS = 10
K.HAND_TOTAL_HOKM  = 162  -- 152 cards + 10 last trick
K.HAND_TOTAL_SUN   = 130  -- 120 (30/suit * 4) cards + 10 last trick (pre-multiplier)

-- -- Bidding ----------------------------------------------------------

K.BID_PASS    = "PASS"
K.BID_HOKM    = "HOKM"     -- trump suit follows
K.BID_SUN     = "SUN"      -- no trump
K.BID_ASHKAL  = "ASHKAL"   -- 3rd/4th-position bid that hands a SUN
                           -- contract to the caller's PARTNER (the
                           -- partner takes the exposed bid card and
                           -- becomes declarer). Available only in
                           -- round 1 if all prior bidders passed.

K.MULT_BASE   = 1
K.MULT_SUN    = 2  -- sun contracts score x2
K.MULT_BEL    = 2  -- doubled (×2)
K.MULT_TRIPLE = 3  -- ثري — bidder's response after Bel (×3)
K.MULT_FOUR   = 4  -- فور — defender's response after Triple (×4)
-- Gahwa (قهوة, "Coffee") is NOT a round-multiplier per canon. The
-- caller's team WINS THE ENTIRE MATCH outright (cumulative→target).
-- Handled as a special branch in scoring rather than a multiplier.
-- See "نظام الدبل في لعبة البلوت": four escalation rungs total —
-- Bel(×2), Triple(×3), Four(×4), Gahwa(match-win).

-- -- Melds (declarations in trick 1) -----------------------------------

-- Raw values (divided by 10 at round end, then x mult). For reference,
-- "game points": Hokm = raw/10, Sun = raw/10 * 2 (Sun×2 multiplier
-- applies to ALL melds per v0.11.10 user-arbitrated rule; Belote
-- alone is multiplier-immune, scored independently post-mult).
-- Pagat-strict Saudi values:
--   3-seq:        2 gp / 4 gp     = 20 raw   (Hokm/Sun)
--   4-seq:        5 / 10           = 50
--   5+seq or
--   4-of-K/Q/J/T: 10 / 20          = 100  ("One Hundred")
--   4 of A:       10 / 40          = Hokm 100 raw / Sun 200 raw post-
--                                    v0.11.10 revert. Arabic name
--                                    الأربع مئة / "Four Hundred"
--                                    refers to Sun's post-multiplier
--                                    value (200 × Sun×2 = 400 effective
--                                    raw → ÷10 = 40 game points).
--   4 of 9, 8, 7: don't score
--   Belote (K+Q of trump): 2 gp = 20 raw, scored independently
K.MELD_SEQ3        = 20
K.MELD_SEQ4        = 50
K.MELD_SEQ5        = 100
K.MELD_CARRE_OTHER = 100   -- T, K, Q, J (any contract type) AND Carré-A in Hokm
K.MELD_CARRE_A_SUN = 200   -- "Four Hundred" (الأربع مئة) — four Aces in Sun.
                           -- v0.11.10 user-arbitrated authoritative rule:
                           -- ALL melds (sequence, carré-other, carré-A) get
                           -- the Sun ×2 contract multiplier (and any active
                           -- escalation: Bel ×2, Triple ×3, Four ×4, Gahwa
                           -- ×4). ONLY Belote (K+Q of trump) is multiplier-
                           -- immune. Stored as 200 raw so the Sun ×2 mult
                           -- in R.ScoreRound brings the post-mult to 400,
                           -- ÷10 = 40 nq game points — the canonical Saudi
                           -- value (videos #32 + #38 + #43).
                           --
                           -- Math reference per user-stated rule:
                           --   sere   20 raw → Hokm 2 nq, Sun 4 nq
                           --   quarte 50 raw → Hokm 5 nq, Sun 10 nq
                           --   quinte 100 raw → Hokm 10 nq, Sun 20 nq
                           --   Carré-A 200 raw → Sun 40 nq (Hokm: emits as
                           --     Carré-other 100 raw → 10 nq via X5 path)
                           --
                           -- History of this constant:
                           --   v0.4.x: 200 (correct)
                           --   v0.10.0 R5: 200 → 400 (WRONG — produced 80
                           --     nq in Sun, 2x canonical)
                           --   v0.11.6: kept 400 + made melds Sun-immune
                           --     (WRONG differently — produced 40 nq
                           --     for Carré-A but broke sere/quarte/quinte
                           --     to 2/5/10 nq instead of canonical 4/10/20)
                           --   v0.11.10: full revert to 200 + Sun×2 on
                           --     all melds. User-stated authoritative rule.
K.MELD_BELOTE      = 20    -- K+Q of trump in same hand, Hokm only

K.CARRE_RANKS = { A=true, T=true, K=true, Q=true, J=true }   -- 9 dropped

-- Al-kaboot (sweep all 8 tricks): replaces normal scoring entirely.
-- Pagat: 25 game points (Hokm) or 44 game points (Sun).
-- Raw form (will be * mult / 10 at the end): 250 (Hokm), 220 (Sun, since 220 * 2 / 10 = 44).
K.AL_KABOOT_HOKM = 250
K.AL_KABOOT_SUN  = 220

-- Reverse Al-Kaboot (الكبوت المقلوب) — defenders sweep all 8 tricks
-- against the bidder team. Per user-supplied canonical Saudi rule:
--
--   "اللاعب الذي على يمين الموزع بشراء صن و(كبتت) عليه ولديه إكه
--    سواء أخذها من الميدان أو كانت في يده. تسجل للفريق المقابل كبوت
--    مقلوب بـ(88) بنط بالمشاريع"
--
-- = "[When] the player to the dealer's right buys Sun and is kabooted,
--    AND has an Ace whether he took it from the field [trick/bidcard]
--    or it was in his hand. The opposite team scores reverse-kaboot
--    at (88) banta with the melds [+ defender's declared melds]."
--
-- All FOUR conditions must hold for reverse-kaboot to fire:
--   1. Defender team sweeps all 8 tricks
--   2. Bid is Sun (not Hokm)
--   3. Bidder is on dealer's right (seat == NextSeat(dealer))
--   4. Bidder played (or holds) an Ace at any point during the round
--
-- Reward: 88 banta FLAT (= 880 raw, post-multiplier — bypasses cardMult
-- so the same 88-banta result holds in Sun-bare and Sun-Bel'd) +
-- defender's declared melds × meldMult.
--
-- v1.0.12 (D HIGH-3 closure): the user supplied the canonical PDF/Saudi
-- text, replacing the v0.10.5 video-#16-single-source hypothesis
-- (88 raw + bidder-led-trick-1). Both the gate AND the value changed:
--   • Gate: bidder-led-trick-1 → dealer-right + Sun + Ace held
--   • Value: 88 raw (× cardMult) → 880 raw (cardMult-immune flat)
--
-- The constant value is the post-multiplier raw amount: 880 raw
-- yields floor((880 + 5) / 10) = 88 banta exactly.
K.AL_KABOOT_REVERSE = 880

-- -- Game phases ------------------------------------------------------

K.PHASE_IDLE     = "idle"        -- no game, lobby visible
K.PHASE_LOBBY    = "lobby"       -- host has invited, waiting on players to claim seats
K.PHASE_DEAL1    = "deal1"       -- 5 cards out, bid card up, round-1 bidding
K.PHASE_DEAL2BID = "deal2bid"    -- all passed round 1, round-2 bidding
K.PHASE_PREEMPT  = "preempt"     -- round-2 Sun on Ace bid card: earlier seats may pre-empt (الثالث)
K.PHASE_OVERCALL = "overcall"    -- post-Hokm-bid 5s window: bidder may upgrade to Sun
                                 -- (non-Ace bid card only) AND non-bidder seats may take
                                 -- the bid as their Sun. Bid-order priority among takers.
                                 -- See R.CanOvercall / R.ResolveOvercall.
K.PHASE_DOUBLE   = "double"      -- contract decided, defenders' window for Bel
K.PHASE_TRIPLE   = "triple"      -- Bel happened, bidder's window for Triple (×3)
K.PHASE_FOUR     = "four"        -- Triple happened, defenders' window for Four (×4)
K.PHASE_GAHWA    = "gahwa"       -- Four happened, bidder's window for Gahwa (match-win)
K.PHASE_DEAL3    = "deal3"       -- final 3 cards out, optional meld declarations
K.PHASE_PLAY     = "play"        -- trick play
K.PHASE_SCORE    = "score"       -- showing score, host advances to next round
K.PHASE_GAME_END = "gameend"

-- -- Networking -------------------------------------------------------

K.PREFIX = "BLT"   -- C_ChatInfo prefix; max 16 chars

-- Addon version, read from the .toc Version line. After CurseForge
-- packaging the @project-version@ token gets substituted; in dev it
-- stays literal so we surface that as "dev" to peers. Used in
-- handshake messages so every player can see if anyone in the party
-- is on a mismatched version.
function K.GetAddonVersion()
    local meta
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        meta = C_AddOns.GetAddOnMetadata("WHEREDNGN", "Version")
    elseif GetAddOnMetadata then
        meta = GetAddOnMetadata("WHEREDNGN", "Version")
    end
    if not meta or meta == "" or meta == "@project-version@" then
        return "dev"
    end
    return meta
end

-- Message tags - keep short to fit 255-byte limit.
-- See Net.lua for the wire grammar.
K.MSG_HOST     = "H"   -- host announces lobby; payload: gameID
K.MSG_JOIN     = "J"   -- player asks to join; payload: gameID
K.MSG_LOBBY    = "L"   -- host broadcasts seat list
-- v0.11.5 XR-14: kick-a-seat constant removed (was tag "K"). Never
-- wired — zero references across the codebase. The "kick a seat" UX
-- was never implemented. Tag "K" is now free for future reuse.
K.MSG_START    = "S"   -- host starts deal
K.MSG_DEAL     = "D"   -- host signals deal phase (cards arrive privately)
K.MSG_HAND     = "h"   -- private whisper: your 5 / 8 cards
K.MSG_BIDCARD  = "b"   -- public face-up bid card
K.MSG_TURN     = "T"   -- whose turn now (bidding or play)
K.MSG_BID      = "B"   -- a bid was made
K.MSG_CONTRACT = "C"   -- contract finalized
K.MSG_DOUBLE   = "X"   -- Bel (×2) — defenders
K.MSG_TRIPLE   = "3"   -- Triple (×3) — bidder's counter to Bel
K.MSG_FOUR     = "4"   -- Four (×4) — defenders' counter to Triple
K.MSG_GAHWA    = "5"   -- Gahwa (match-win) — bidder's terminal
K.MSG_MELD     = "M"   -- meld declaration in trick 1
K.MSG_PLAY     = "P"   -- card played
K.MSG_TRICK    = "W"   -- trick winner + points
K.MSG_ROUND    = "R"   -- round ended; per-team points
K.MSG_GAMEEND  = "G"   -- game ended
K.MSG_RESYNC_REQ = "?" -- request state from host
K.MSG_RESYNC_RES = "="  -- host's resync payload
K.MSG_SKIP_DBL   = "n"  -- defender voted skip on double window
K.MSG_SKIP_TRP   = "u"  -- bidder voted skip on triple window
K.MSG_SKIP_FOR   = "v"  -- defender voted skip on four window
K.MSG_SKIP_GHW   = "w"  -- bidder voted skip on gahwa window
K.MSG_TAKWEESH     = "k"  -- player calls Takweesh (catches an illegal play)
K.MSG_TAKWEESH_OUT = "z"  -- host's outcome: caught or false-call
K.MSG_KAWESH       = "a"  -- player calls Kawesh/Saneen (5-card 7/8/9 annul)
K.MSG_PAUSE        = "p"  -- host pauses/unpauses; payload "1" or "0"
K.MSG_HEARTBEAT    = "~"  -- v1.8.0: host-alive heartbeat broadcast every
                          -- HOST_HEARTBEAT_SEC. Payload: empty. Remotes
                          -- watchdog and surface a "host gone" warning
                          -- after HOST_HEARTBEAT_TIMEOUT_SEC of silence
                          -- (audit v1.6.1 MP-21 CRITICAL).
K.MSG_TEAMS        = "t"  -- host broadcasts custom team names; payload teamA;teamB
K.MSG_AKA          = "e"  -- partner-coordination signal in Hokm: caller
                          -- holds the highest unplayed card in a non-trump
                          -- suit. Tells teammate not to over-trump.
                          -- Payload: seat;suit (e.g. "e;3;H").
K.MSG_SWA          = "Q"  -- "SWA" (سوا) claim: caller asserts they will
                          -- win every remaining trick and reveals their
                          -- hand. Payload: seat;encodedHand. Host
                          -- validates and broadcasts the outcome via
                          -- MSG_SWA_OUT.
K.MSG_SWA_OUT      = "Z"  -- host's outcome of an SWA claim. Payload:
                          -- caller;valid;addA;addB;totA;totB.
K.MSG_SWA_REQ      = "I"  -- caller asks opponents for permission to
                          -- claim SWA with 4+ cards remaining (Saudi
                          -- "Allow me to Sawa"). Payload: seat;
                          -- encodedHand. Opponents respond via
                          -- MSG_SWA_RESP. Host arbitrates the result.
K.MSG_SWA_RESP     = "O"  -- opponent's accept/deny vote on a pending
                          -- SWA permission request. Payload:
                          -- responderSeat;accept(0/1);callerSeat.
K.MSG_PREEMPT      = "@"  -- "Triple-on-Ace" pre-emption (الثالث): an
                          -- earlier seat (in bidding order) claims a
                          -- Sun bid when the bid card is an Ace and a
                          -- later seat already bought it. Payload:
                          -- seat. Seat must be earlier in bid order
                          -- and not the partner of the would-be
                          -- declarer. Settles the bid by reassigning
                          -- declarer to the pre-empter.
K.MSG_PREEMPT_PASS = "%"  -- waive the pre-emption right. Payload: seat.
K.MSG_BELOTE       = "$"  -- v1.0.11: Baloot/Belote announcement (PDF
                          -- §Belote): «يجب على اللاعب الذي لديه
                          -- البلوت ذكره أثناء لعب الورقة الثانية» —
                          -- "the holder must announce on the second
                          -- card of K+Q-of-trump play". Payload:
                          -- seat. R.ScoreRound counts the +20 Belote
                          -- bonus only if announced (or covered by a
                          -- declared sequence-meld containing K+Q).
                          -- Bots auto-announce via Net.HostMaybeBelote.
K.MSG_OVERCALL_OPEN     = ">"  -- v0.7 host opens a 5s post-Hokm Sun-overcall
                              -- window. No payload — clients already have
                              -- the contract / bidder / bidCard / dealer
                              -- in S.s.* from earlier MSG_CONTRACT etc.
K.MSG_OVERCALL_DECISION = "<"  -- a seat has decided in the overcall window.
                              -- Payload: seat;decision (decision is
                              -- "UPGRADE", "TAKE", or "WAIVE"). Host
                              -- validates; broadcasts the same payload
                              -- to all clients for UI parity.
K.MSG_OVERCALL_RESOLVE  = "!"  -- host announces the overcall window
                              -- closed and what happened. Payload:
                              -- taken(0|1);by(seat or 0);type
                              -- ("UPGRADE"|"TAKE"|""). When taken=1, a
                              -- subsequent MSG_CONTRACT carries the
                              -- rewritten Sun contract.
                              --
                              -- v0.10.3 wire-tag fix (CRIT-1, audit
                              -- summary): pre-v0.10.3 this constant
                              -- collided with K.MSG_RESYNC_REQ ("?"),
                              -- causing every "?" tag to be dispatched
                              -- to _OnOvercallResolve before reaching
                              -- _OnResyncReq (the OVERCALL elseif at
                              -- Net.lua:543 precedes RESYNC at line 620).
                              -- RESYNC was therefore dead in production.
                              -- Reassigning OVERCALL_RESOLVE to "!"
                              -- frees "?" for its older RESYNC_REQ owner.

-- -- Sound effects ----------------------------------------------------
-- Bundled OGG cues (synthesized to match the kammelna.com baloot feel:
-- short crisp card slaps + gentle bell chimes for milestones). All
-- routed via PlaySoundFile in Sound.lua. Files live in sounds/.
local SND_BASE = "Interface\\AddOns\\WHEREDNGN\\sounds\\"
K.SND_TURN_PING = SND_BASE .. "turn_ping.ogg"     -- soft bell, your turn
K.SND_CARD_PLAY = SND_BASE .. "card_play.ogg"     -- card-slap noise burst
K.SND_CARD_SWISH = SND_BASE .. "card_swish.ogg"   -- slide-across-table whoosh
K.SND_CONTRACT  = SND_BASE .. "contract.ogg"      -- two-note ascending chime
K.SND_TRICK_WON = SND_BASE .. "trick_won.ogg"     -- triad arpeggio, our team won
K.SND_BALOOT    = SND_BASE .. "baloot.mp3"        -- v1.0.2: user-supplied
                                                  -- Saudi vocal "بلوت" cue.
                                                  -- Fires for the K+Q-of-trump
                                                  -- Belote bonus reveal.
K.SND_LOST_ROUND = SND_BASE .. "lost_round.ogg"   -- player-supplied stinger,
                                                  -- fires when local team
                                                  -- loses a round

-- v1.0.2 user-supplied meld announcement cues. S.ApplyMeld dispatches
-- to the matching cue based on the meld's value/kind/contract. Saudi
-- convention names each meld by its raw point value; the .mp3 vocals
-- carry that name (e.g. SERA = ثلاث / "three" colloquial seq3, 50 =
-- خمسين, 100 = مية, 400 = أربع مية / four-aces-in-Sun). Older
-- placeholder K.SND_MELD_DECLARE removed — the dispatcher in
-- S.ApplyMeld now picks the correct per-meld sound directly.
K.SND_MELD_SERA = SND_BASE .. "SERA.mp3"          -- seq3 (3 consec, same suit) — 20 raw
K.SND_MELD_50   = SND_BASE .. "khamseen.mp3"      -- seq4 (4 consec, same suit) — 50 raw
K.SND_MELD_100  = SND_BASE .. "100.mp3"           -- seq5, carré-T/K/Q/J, OR
                                                  -- carré-A in Hokm — all 100 raw
K.SND_MELD_400  = SND_BASE .. "400.mp3"           -- carré-A in Sun (200 raw,
                                                  -- 40 nq player-named "أربع مية")

-- Arabic voice cues (Saudi-accented edge-tts) for the bid actions, in
-- the spirit of the kammelna.com baloot announcer. Fired from the
-- bid-handler hooks so every player on every client hears them.
K.SND_VOICE_HOKM   = SND_BASE .. "hokm.ogg"       -- "حكم"
K.SND_VOICE_SUN    = SND_BASE .. "sun.ogg"        -- "صن"
K.SND_VOICE_ASHKAL = SND_BASE .. "ashkal.ogg"     -- "أشكال"
K.SND_VOICE_PASS   = SND_BASE .. "pass.ogg"       -- "بَسْ" — round-1 pass
K.SND_VOICE_WLA    = SND_BASE .. "wla.ogg"        -- "ولا" — round-2 pass
K.SND_VOICE_AWAL   = SND_BASE .. "awal.ogg"       -- "أوَل" (round-1 bidding start)
K.SND_VOICE_THANY  = SND_BASE .. "thany.ogg"      -- "ثآني" (round-2 bidding start)
-- v1.0.2 user-supplied: BEL.mp3 is the new Saudi-vocal cue for the
-- FIRST escalation rung (×2 multiplier — defender team's "double"). UI
-- relabels the Bel buttons to "Double x2" alongside this. NEW cue —
-- pre-v1.0.2 the rung had no voice line.
K.SND_VOICE_DOUBLE = SND_BASE .. "BEL.mp3"        -- "بل" / "Double x2" — defenders escalate ×2
K.SND_VOICE_TRIPLE = SND_BASE .. "three.mp3"      -- v1.0.2 user-supplied vocal
                                                  -- (replaces triple.ogg).
                                                  -- "ثلاث" / "Triple x3" — bidder's counter to Bel.
K.SND_VOICE_FOUR   = SND_BASE .. "four.mp3"       -- v1.0.2 user-supplied
                                                  -- (replaces four.ogg).
                                                  -- "فور" — defenders' counter to Triple.
K.SND_VOICE_GAHWA  = SND_BASE .. "gahwa.mp3"      -- v1.0.2 user-supplied
                                                  -- (replaces gahwa.ogg).
                                                  -- "قهوة" — bidder's terminal call.
K.SND_VOICE_AKA    = SND_BASE .. "aka.ogg"        -- "إكَهْ" (AKA signal)

-- v0.10.7 user-requested specialized cues. All file names below must
-- exist as .ogg files under sounds/ — drop user-supplied audio under
-- those names to enable the cues. Until the files exist, PlaySoundFile
-- silently no-ops (WoW's documented behaviour for missing paths) so
-- the wiring is safe to ship even before files land.
K.SND_SWEEP_TRACK   = SND_BASE .. "sweep_track.ogg"   -- after trick 3 closes when same team won 1+2+3 (sweep pursuit confirmed). Fires once per round on all clients.
K.SND_KABOOT        = SND_BASE .. "kaboot.ogg"        -- round-end when local team achieved Al-Kaboot (won all 8 tricks). Winning-team-only.
K.SND_TRUMP_CUT     = SND_BASE .. "trump_cut.ogg"     -- first trump played in a non-trump-led trick (Hokm-only). Fires on all clients per cut.
K.SND_LAST_TRICK_WIN = SND_BASE .. "last_trick_win.ogg" -- local seat plays the winning card of trick 8 (round-final climax). Once per round at most, local-only.
K.SND_HOKM_LOST     = SND_BASE .. "hokm_lost.ogg"     -- Hokm contract failed (bidderMade=false). Fires on the bidder team (losers) only; supersedes generic SND_LOST_ROUND.
K.SND_KABOOT_AGAINST = SND_BASE .. "kaboot_against.ogg" -- round-end when Al-Kaboot was scored against local team. Losing-team-only; supersedes SND_LOST_ROUND.

-- -- Tunables ---------------------------------------------------------

K.LOBBY_BROADCAST_SEC = 3.0   -- host re-announces lobby every N sec until full
K.TURN_TIMEOUT_SEC    = 60    -- host auto-acts on this seat after N seconds
K.HEARTBEAT_SEC       = 5.0
K.LAST_TRICK_PEEK_SEC = 3.0   -- duration of the once-per-hand last-trick peek
K.TRICK_GLOW_SEC      = 1.0   -- length of winner-glow before clearing the trick
K.CARD_ANIM_SEC       = 0.18  -- duration of the card-land scale+fade animation
-- User-requested SWA timeout: when a permission-required SWA is in
-- flight, the host auto-approves after this many seconds unless an
-- opponent counters with Takweesh (which scans prior tricks for any
-- illegal play by the SWA caller's team and applies the qaid penalty
-- instead). Replaces the indefinite Accept/Deny vote wait — humans
-- now need only inspect the displayed claim and decide whether to
-- counter via Takweesh; explicit Deny still works as a manual cancel.
K.SWA_TIMEOUT_SEC     = 5

-- v0.7 Sun-overcall window. After any Hokm bid resolves (R1 or R2),
-- the host opens a 5-second window during which:
--   • The bidder may UPGRADE their own Hokm to Sun — UNLESS the R1
--     bid card was an Ace (anti-trap rule: bidder shouldn't be able
--     to bid weak Hokm-on-Ace then upgrade once the Ace is locked).
--   • Any non-bidder seat may TAKE the contract as THEIR Sun. The
--     taker becomes the new bidder; the original Hokm bidder becomes
--     a defender.
-- Auto-WAIVE on timeout. Conflict resolution: bidder UPGRADE wins;
-- otherwise bid-order priority (earliest in turn order from dealer)
-- among non-bidder TAKE'rs.
-- Forced/Takweesh-recovery contracts do NOT trigger overcall.
-- Bot tier gating: only M3lm+ bots act on the overcall (Basic /
-- Advanced auto-WAIVE — this is a tournament-strategy nuance).
K.OVERCALL_TIMEOUT_SEC = 5

-- v1.8.0 host-alive heartbeat (audit v1.6.1 MP-21 CRITICAL). Pre-fix
-- there was no host-alive signal — when the host crashed or quit, the
-- 3 remaining clients stared at a frozen UI forever with no indication
-- the host was gone. Host now broadcasts MSG_HEARTBEAT every
-- HOST_HEARTBEAT_SEC. Remotes track the last-seen heartbeat timestamp
-- and surface a warning banner if HOST_HEARTBEAT_TIMEOUT_SEC elapses
-- with no signal. The timeout is generous (45s) — well above any
-- legitimate slow-server stall but well below "I've been waiting forever".
K.HOST_HEARTBEAT_SEC          = 15  -- broadcast cadence
K.HOST_HEARTBEAT_TIMEOUT_SEC  = 45  -- 3 missed heartbeats before alert

-- v3.0 (audit v1.6.1 UX-35 LOW): UI pulse cadence pulled out as
-- constants. Pre-fix the AFK turn-warn pulse hardcoded `8 ticks ×
-- 0.18s = 1.4s` inline; not configurable and not documented as a
-- product knob. Now exposed for tunability + clarity. Same defaults.
K.UI_AFK_PULSE_TICKS  = 8
K.UI_AFK_PULSE_PERIOD = 0.18

-- Bot AI thresholds (raw "strength score" units; see Bot.lua for the
-- per-suit and Sun strength formulas). Tuned for the canonical 4-rung
-- ×2/×3/×4/match-win economy (post-v0.1.34 escalation rewrite).
K.BOT_BEL_TH          = 62    -- defenders bel with own strength >= TH.
                              -- v1.3.2 (post-v1.3.0 harness fix calibration):
                              -- the v0.11.20 drop to 35 was tuned against
                              -- the BUG-ZEROED multiseed harness (test
                              -- fixture pre-v1.3.0 read empty hands and
                              -- always returned false). Once the harness
                              -- was fixed in v1.3.0, the corrected probe
                              -- showed TH=35 fires Bel at ~92% (defender
                              -- p25=30, p50=41, p75=53, p90=65 across
                              -- 4000 evals; jitter band [25,45] catches
                              -- 65% of single-defender rolls; round-level
                              -- with 2 defenders + early-return = 92%).
                              -- The v0.11.20 calibration was an
                              -- over-correction against a null measurement.
                              -- Re-anchored to p75=53 + jitter ±10 ≈
                              -- jth_max 72; targets ~8% natural Bel rate
                              -- (escalation.md target). v0.11.19/0.11.20
                              -- history: 60 -> 45 -> 35 -> 62.
K.BOT_TRIPLE_TH       = 82    -- bidder triples (×3) — needs strong hand.
                              -- v1.3.4 (Saudi-pro adherence audit
                              -- walkback): 65 -> 82. The v1.3.2
                              -- empirical re-anchor to p75=50 +
                              -- jitter ±12 produced jth_max=77 — only
                              -- 3 points above BOT_BEL_TH=62, meaning
                              -- a defender able to Bel could nearly
                              -- always trigger bidder Triple. Per
                              -- escalation.md mandatory-Triple
                              -- patterns ("J+9+A of trump or
                              -- Belote"), Triple-worthy hands sit
                              -- meaningfully above Bel-worthy hands,
                              -- not 3 points above. 82 puts jth_max
                              -- at 94, leaving a 17-point Bel→Triple
                              -- gap that better matches the prose
                              -- description. Note: no video frequency
                              -- citation exists for either value
                              -- (escalation.md explicitly says video
                              -- sources don't supply hand-strength
                              -- thresholds); both are empirical, but
                              -- 82 better honors the relative-spacing
                              -- documented in prose.
                              -- v1.3.2 history: 90 -> 65 (corrected
                              -- v0.11.x harness-bug-driven calibration).
K.BOT_FOUR_TH         = 80    -- defenders four (×4) — very strong hand.
                              -- v1.3.2: 110 -> 80. Above proposed Triple
                              -- band (jth_max 77) so Four still requires
                              -- escalation pressure; below the 8-card
                              -- ceiling so it's reachable. Targets <5%.
                              --
                              -- ⚠ v1.4.2 audit clarification — chain
                              -- ordering note: after v1.3.4's walkback
                              -- raised BOT_TRIPLE_TH 65 → 82, this
                              -- raw constant (80) sits BELOW Triple's
                              -- raw threshold. This LOOKS inverted but
                              -- is mitigated by `Bot.PickFour` adding
                              -- a +5 strength bonus before threshold
                              -- comparison (Bot.lua:6552 — partner-
                              -- kept-chain-open signal, unconditional
                              -- since DEAD-1 audit). Net effect:
                              -- defender effective Four firing range
                              -- (TH-5±jitter15) overlaps Triple's
                              -- bidder firing range (TH±jitter12).
                              -- The +5 bonus + small overlap is by
                              -- design — the chain rungs evaluate
                              -- DIFFERENT teams (bidder vs defender)
                              -- with similar strength distributions
                              -- (defender p90=65, bidder p90=108 from
                              -- v1.3.0 calibration probe), so direct
                              -- raw-TH comparison isn't meaningful.
                              -- DO NOT raise this constant naively
                              -- to "fix the inversion" — that would
                              -- collapse Four firing to ~0% in
                              -- forced-mode probe (currently 3-7%
                              -- per multiseed measurement). Any
                              -- future re-calibration must consider
                              -- the +5 bonus + per-team strength
                              -- distributions together.
K.BOT_GAHWA_TH        = 95    -- bidder gahwa (match-win) — terminal, near-certain.
                              -- v1.3.2: 120 -> 95. Above Four band; stays
                              -- terminal-rare (<2%) but reachable on
                              -- top-tier hands.
                              -- v0.11.17 EV-2 (audit): lowered 135 -> 120. The
                              -- escalation chain runs on the FULL 8-card hand
                              -- (post-HostDealRest) by the time PHASE_GAHWA
                              -- fires, so the relevant max is the 8-card
                              -- escalationStrength ceiling. With v0.11.17 EV-1
                              -- (void/side-Ace bonuses added to
                              -- escalationStrength) effective max sits around
                              -- ~140; threshold 120 keeps Gahwa as the rarest
                              -- rung but actually reachable on top-tier hands.
                              -- escalation.md "0% in symmetric pure-bot play"
                              -- diagnostic should now show Gahwa firing on
                              -- extreme outliers (1-3% of bidder rounds).
                              -- v1.0.3 (CONSTANT-COMMENT-DRIFT): refreshed
                              -- comment to reflect the 8-card-hand evaluation
                              -- context — the prior "5-card hand evaluation,
                              -- max ~99" reasoning was the original v0.11.17
                              -- justification but referenced the bidding-time
                              -- 5-card window, not the escalation-time 8-card
                              -- window where this threshold actually fires.
K.BOT_ASHKAL_TH       = 65    -- partner-of-Hokm-bidder calls Ashkal with Sun-strong hand
K.BOT_PREEMPT_TH      = 60    -- earlier seat pre-empts a Sun-on-Ace bid.
                              -- v0.11.20 (Agent 1 calibration math):
                              -- 75 was structurally unreachable —
                              -- 2A post-bidcard hands have median
                              -- sun=24, p95=37; jitter band [65, 85]
                              -- meant <0.01% fire rate. Sim shows
                              -- TH=60 + 2-Ace bonus +15 produces
                              -- ~0.72% fire per A-bidcard, matching
                              -- canonical Saudi 1-3% rate. Both
                              -- changes required (TH alone or bonus
                              -- alone is insufficient).

-- v0.5.13 PickBid magic-number promotion: pulled out of Bot.lua
-- inline literals so they're tunable from one place. Each maps to
-- a named patch in decision-trees.md Section 1.
K.BOT_SUN_3ACE_BONUS                = 15  -- S-3 (was inline +12; bumped per Wave-2
                                          --  audit calibration — 3-Ace hands without
                                          --  AKQ triple now reliably clear thSun)
K.BOT_SUN_2ACE_BONUS                = 15  -- v0.11.14 user-bidcalc trace evidence:
                                          --  2-Ace hands without mardoofa or AKQ
                                          --  triple consistently scored 17-21
                                          --  (well below thSun=38-46 jitter band)
                                          --  and were rejected. Per Saudi rule
                                          --  S-1, 2 Aces IS the canonical Sun
                                          --  shape — these hands SHOULD bid.
                                          --  Specific user-trace examples:
                                          --    [7D AD QC AC 9H] sun=17 (skipped)
                                          --    [AH AD KC 7H QS] sun=21 (skipped)
                                          --  +15 mirrors the 3-Ace bonus magnitude
                                          --  (both are "shape-pass" signals, not
                                          --  "guaranteed-win" markers). After
                                          --  bonus: hands score 32/36, firing
                                          --  17%/39% of jitter rolls at thSun=40.
                                          --  Sim: total R1 fire rate goes
                                          --  5.67% -> 7.39% per-bot per-round.
K.BOT_SUN_MARDOOFA_BONUS            = 20  -- S-8 per A+T mardoofa pair.
                                          -- v0.10.4: 5 → 10 (under-rewarded
                                          -- canonical Saudi A+T cover pattern).
                                          -- v0.11.9 user-arbitrated (bidcalc
                                          -- trace): 10 → 20. The v0.10.4
                                          -- bump was insufficient — even after
                                          -- the +10 bonus, sun=20 was still
                                          -- ~25 points below thSun (47-50)
                                          -- for hands like [QS TH AH 8C KH]
                                          -- (A+T+K hearts mardoofa) and
                                          -- [8H JC AC TC 7S] (A+T+J clubs
                                          -- mardoofa). The canonical Saudi
                                          -- name "إكة مردوفة" (covered Ace)
                                          -- describes a near-guaranteed
                                          -- trick pair; +20 reflects that
                                          -- Saudi-pro weight more accurately.
                                          -- Pair-cap (2) preserved so 2-pair
                                          -- hands cap at +40, not unbounded.
K.BOT_SUN_MARDOOFA_PAIR_CAP         = 2   -- S-8 pair count cap (2 pairs = +20
                                          -- max post-v0.10.4 bonus bump).
K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN  = 5   -- B-5 (round 2 Sun must beat best Hokm by ≥ this)
K.BOT_ASHKAL_DIRECT_SUN_PIVOT       = 85  -- A-6 (sun >= this → skip Ashkal, prefer direct Sun)
K.BOT_PICKBID_BELOTE_BONUS          = K.MELD_BELOTE  -- B-6 (mirrors meld scoring;
                                                    --  +20 raw multiplier-immune)
-- v0.11.11 XU-07: promoted bidding thresholds from Bot.lua locals.
-- Calibration trail for these constants:
--   K.BOT_TH_HOKM_R1_BASE: 36 (v0.5) → 42 (v0.5.5)
--   K.BOT_TH_HOKM_R2_BASE: 32 (v0.5) → 36 (v0.5.5)
--   K.BOT_TH_SUN_BASE:     50 (v0.4) → 47 (v0.10.6) → 40 (v0.11.10)
--   K.BOT_BID_JITTER:      ±6 (since v0.5)
--   K.BOT_SUN_VOID_PENALTY_CAP: 25 (v0.4) → 18 (Gemini softening) → 8 (v0.11.9)
-- See `Bot.lua:35-50` (legacy locals retained as aliases for the
-- existing call sites; values now sourced from K.*).
K.BOT_TH_HOKM_R1_BASE       = 42
K.BOT_TH_HOKM_R2_BASE       = 36
K.BOT_TH_SUN_BASE           = 40
K.BOT_BID_JITTER            = 6
K.BOT_SUN_VOID_PENALTY_CAP  = 8

-- v0.5.13: Sun Bel-100 cumulative gate constant (E-1 / R.CanBel).
-- Pulled from inline `mine < 100` literal in Rules.lua so it's
-- tunable per ruleset variant. Saudi Bel-legality threshold —
-- only the Sun-defender team currently at <100 may Bel.
K.SUN_BEL_CUMULATIVE_GATE = 100

-- v0.7 Sun-overcall bot strength thresholds. Used by Bot.PickOvercall.
-- Bidder self-upgrade requires CLEARLY exceeding the regular Sun-bid
-- threshold (~50 in normal bidding) — they already committed to Hokm,
-- so the upgrade implies "I underbid; my hand is actually Sun-strong."
-- Non-bidder TAKE is stricter still (BOT_OVERCALL_TAKE_TH > BOT_OVERCALL_SELF_TH)
-- because taking another seat's contract is a high-commitment move
-- that puts you on the hook for a Sun's full handTotal=130 ×2 = 260
-- effective points if you fail.
K.BOT_OVERCALL_SELF_TH = 75   -- bidder upgrade Hokm→Sun threshold
K.BOT_OVERCALL_TAKE_TH = 80   -- non-bidder take-as-Sun threshold
-- v1.5.3: K.BOT_OVERCALL_TAKE_HOKM_TH removed. The v0.8 cross-trump
-- Hokm-take feature it gated was non-canonical (saudi-rules.md:26-28);
-- non-bidder seats can no longer take the contract with a different
-- Hokm trump suit. Sun-overcall (UPGRADE / TAKE) remains.

-- v1.0.3 (U-8): AKA late-round clutch threshold. Bot.PickAKA fires AKA
-- on tricks 6-8 only when the round is "decisive" — opp near-win,
-- self near-clinch, or close race. Pre-v1.0.3 this was a magic 25
-- inline. Pulled to a constant for tunability and pinned from the
-- 152 game target: 25/152 ≈ 16.4% of the target as the "clutch
-- distance". Future calibration may vary it; the inline literal is
-- now a single tweak point.
K.BOT_AKA_CLUTCH_DISTANCE   = 25
K.BOT_AKA_CLUTCH_RACE_GAP   = 20  -- "close race" tolerance: |myCum-oppCum| <= GAP

-- v0.11.15 user-audit Q1: void-in-trump bonus for Sun overcall.
-- Saudi canonical signal: when the opp bid Hokm in a suit where
-- you have ZERO (or one) cards, that's a strong Sun overcall
-- trigger — in no-trump, your void/short suit doesn't matter
-- because there IS no trump. Pre-v0.11.15 the bot used raw
-- sunStrength() with no contextual awareness of the opp's
-- trump suit; hands like [AH AS QD JD 7C] against Hokm-Spades
-- (1 spade only) didn't get any signal that this was a textbook
-- Sun overcall opportunity. Bonuses applied additively to the
-- pre-threshold score so the existing TAKE_TH / SELF_TH stay
-- meaningful for normal (non-void) overcall decisions.
K.BOT_OVERCALL_VOID_TRUMP_BONUS  = 15  -- 0 cards in opp's trump suit
K.BOT_OVERCALL_SHORT_TRUMP_BONUS =  8  -- 1 card in opp's trump suit

-- v0.11.17 audit B2: ISMCTS wall-clock budget per Saudi Master move.
-- Pre-v0.11.17 the world loop ran fixed 100/60/30 worlds with no time
-- cap, producing 3-15s pauses on early-trick moves (16,800 full
-- Bot.PickPlay invocations per move). Budget caps per-move latency;
-- completed worlds vote, remaining skipped. UI responsiveness chosen
-- over marginal accuracy at world 80-100. Set to 0 to disable cap
-- (full numWorlds always).
--
-- v3.0.5 (watchdog hotfix): lowered from 0.5s → 0.12s. WoW's CPU
-- watchdog kills any single script execution that exceeds ~200ms;
-- the prior 500ms cap could deliberately spend MORE than the watchdog
-- allowed. User-reported repeat "script ran too long" crashes during
-- Saudi-Master bot thinking in 3-bots-vs-human configurations (bot
-- teammate of human at trick 1-2 with maximum world uncertainty).
-- 0.12s = 60% of watchdog limit, leaving headroom for ApplyPlay /
-- SendPlay / _HostStepPlay state mutation that follows the picker
-- call inside the same C_Timer.After callback. The per-card inner-
-- loop check at BotMaster.lua:1117-1119 (also v3.0.5) handles the
-- single-world overshoot case.
K.BOT_ISMCTS_BUDGET_SEC = 0.12
