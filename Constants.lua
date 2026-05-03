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
-- "game points": Hokm = raw/10, Sun = raw/10 * 2.
-- Pagat-strict Saudi values:
--   3-seq:        2 gp / 4 gp     = 20 raw
--   4-seq:        5 / 10           = 50
--   5+seq or
--   4-of-K/Q/J/T: 10 / 20          = 100  ("One Hundred")
--   4 of A:       —  / 40          = Hokm 0, Sun 200  ("Four Hundred")
--   4 of 9, 8, 7: don't score
--   Belote (K+Q of trump): 2 gp = 20 raw, scored independently
K.MELD_SEQ3        = 20
K.MELD_SEQ4        = 50
K.MELD_SEQ5        = 100
K.MELD_CARRE_OTHER = 100   -- T, K, Q, J (any contract type)
K.MELD_CARRE_A_SUN = 200   -- "Four Hundred" (الأربع مئة) — four Aces in Sun.
                           -- Stored as 200 raw so the Sun ×2 multiplier
                           -- in R.ScoreRound brings the final raw to 400
                           -- (= 40 gp after div10), matching the canonical
                           -- "أربع مئة" Saudi value. Previously stored as
                           -- 400 raw which double-counted with Sun mult
                           -- and produced 800 raw / 80 gp — twice the
                           -- intended value (Gemini scoring-audit catch).
K.MELD_BELOTE      = 20    -- K+Q of trump in same hand, Hokm only

K.CARRE_RANKS = { A=true, T=true, K=true, Q=true, J=true }   -- 9 dropped

-- Al-kaboot (sweep all 8 tricks): replaces normal scoring entirely.
-- Pagat: 25 game points (Hokm) or 44 game points (Sun).
-- Raw form (will be * mult / 10 at the end): 250 (Hokm), 220 (Sun, since 220 * 2 / 10 = 44).
K.AL_KABOOT_HOKM = 250
K.AL_KABOOT_SUN  = 220

-- -- Game phases ------------------------------------------------------

K.PHASE_IDLE     = "idle"        -- no game, lobby visible
K.PHASE_LOBBY    = "lobby"       -- host has invited, waiting on players to claim seats
K.PHASE_DEAL1    = "deal1"       -- 5 cards out, bid card up, round-1 bidding
K.PHASE_DEAL2BID = "deal2bid"    -- all passed round 1, round-2 bidding
K.PHASE_PREEMPT  = "preempt"     -- round-2 Sun on Ace bid card: earlier seats may pre-empt (الثالث)
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
K.MSG_KICK     = "K"   -- host kicks a seat
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
K.SND_BALOOT    = SND_BASE .. "baloot.ogg"        -- four-note fanfare

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
K.SND_VOICE_TRIPLE = SND_BASE .. "triple.ogg"     -- "ثري" (×3 — bidder's counter to Bel)
K.SND_VOICE_FOUR   = SND_BASE .. "four.ogg"       -- "فور" (×4 — defenders' counter to Triple)
K.SND_VOICE_GAHWA  = SND_BASE .. "gahwa.ogg"      -- "قهوة" (Coffee — bidder's terminal, match-win)
K.SND_VOICE_AKA    = SND_BASE .. "aka.ogg"        -- "إكَهْ" (AKA signal)

-- -- Tunables ---------------------------------------------------------

K.LOBBY_BROADCAST_SEC = 3.0   -- host re-announces lobby every N sec until full
K.TURN_TIMEOUT_SEC    = 60    -- host auto-acts on this seat after N seconds
K.HEARTBEAT_SEC       = 5.0
K.LAST_TRICK_PEEK_SEC = 3.0   -- duration of the once-per-hand last-trick peek
K.TRICK_GLOW_SEC      = 1.0   -- length of winner-glow before clearing the trick
K.CARD_ANIM_SEC       = 0.18  -- duration of the card-land scale+fade animation

-- Bot AI thresholds (raw "strength score" units; see Bot.lua for the
-- per-suit and Sun strength formulas). Tuned for the canonical 4-rung
-- ×2/×3/×4/match-win economy (post-v0.1.34 escalation rewrite).
K.BOT_BEL_TH          = 70    -- defenders bel with own strength >= TH
K.BOT_TRIPLE_TH       = 90    -- bidder triples (×3) — needs strong hand
K.BOT_FOUR_TH         = 110   -- defenders four (×4) — very strong hand
K.BOT_GAHWA_TH        = 135   -- bidder gahwa (match-win) — terminal, near-certain
K.BOT_ASHKAL_TH       = 65    -- partner-of-Hokm-bidder calls Ashkal with Sun-strong hand
K.BOT_PREEMPT_TH      = 75    -- earlier seat pre-empts a Sun-on-Ace bid
