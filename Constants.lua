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
K.SUIT_COLOR  = { S = "ffffffff", H = "ffff5555", D = "ffff8800", C = "ff66ff66" }

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
K.MULT_BEL    = 2  -- doubled
K.MULT_BELRE  = 4  -- redoubled

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
K.MELD_CARRE_A_SUN = 200   -- "Four Hundred" — Sun only
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
K.PHASE_DOUBLE   = "double"      -- contract decided, opp window for Bel
K.PHASE_REDOUBLE = "redouble"    -- Bel happened, contracting team window for Bel-Re
K.PHASE_DEAL3    = "deal3"       -- final 3 cards out, optional meld declarations
K.PHASE_PLAY     = "play"        -- trick play
K.PHASE_SCORE    = "score"       -- showing score, host advances to next round
K.PHASE_GAME_END = "gameend"

-- -- Networking -------------------------------------------------------

K.PREFIX = "BLT"   -- C_ChatInfo prefix; max 16 chars

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
K.MSG_DOUBLE   = "X"   -- Bel
K.MSG_REDOUBLE = "Y"   -- Bel-Re
K.MSG_MELD     = "M"   -- meld declaration in trick 1
K.MSG_PLAY     = "P"   -- card played
K.MSG_TRICK    = "W"   -- trick winner + points
K.MSG_ROUND    = "R"   -- round ended; per-team points
K.MSG_GAMEEND  = "G"   -- game ended
K.MSG_RESYNC_REQ = "?" -- request state from host
K.MSG_RESYNC_RES = "="  -- host's resync payload
K.MSG_SKIP_DBL   = "n"  -- defender voted skip on double window
K.MSG_SKIP_RDBL  = "m"  -- bidder voted skip on redouble window
K.MSG_TAKWEESH     = "k"  -- player calls Takweesh (catches an illegal play)
K.MSG_TAKWEESH_OUT = "z"  -- host's outcome: caught or false-call
K.MSG_KAWESH       = "a"  -- player calls Kawesh/Saneen (5-card 7/8/9 annul)

-- -- Tunables ---------------------------------------------------------

K.LOBBY_BROADCAST_SEC = 3.0   -- host re-announces lobby every N sec until full
K.TURN_TIMEOUT_SEC    = 60    -- host auto-acts on this seat after N seconds
K.HEARTBEAT_SEC       = 5.0
K.LAST_TRICK_PEEK_SEC = 3.0   -- duration of the once-per-hand last-trick peek
K.TRICK_GLOW_SEC      = 1.0   -- length of winner-glow before clearing the trick
K.CARD_ANIM_SEC       = 0.18  -- duration of the card-land scale+fade animation

-- Bot AI thresholds (raw "strength score" units; see Bot.lua for the
-- per-suit and Sun strength formulas).
K.BOT_BEL_TH          = 70    -- defender bels with own strength >= TH
K.BOT_BELRE_TH        = 90    -- bidder redoubles with own strength >= TH
