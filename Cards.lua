-- Card helpers: deck construction, shuffle, encode/decode, display.
--
-- A "card" is the 2-char string "<rank><suit>" e.g. "JH", "TS", "7C".
-- A "hand" is an array of cards.
--
-- Wire encoding: cards joined with no separator (each is exactly 2 chars).
-- Eight cards = 16 chars. Five cards = 10 chars. Single card = 2 chars.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Cards = B.Cards or {}
local M = B.Cards
local K = B.K

-- -- Deck construction --------------------------------------------------

function M.NewDeck()
    local d = {}
    for _, s in ipairs(K.SUITS) do
        for _, r in ipairs(K.RANKS) do
            d[#d + 1] = r .. s
        end
    end
    return d
end

-- Deterministic Fisher-Yates using a private LCG. We deliberately do
-- NOT call math.randomseed() — WoW's lua state is shared across addons
-- and resetting the global RNG can disrupt others' math.random use.
local lcgState = nil
local function lcgSeed(seed)
    -- Mix the seed through Knuth's multiplicative hash so that
    -- adjacent seed values (e.g. consecutive GetTime() ms ticks)
    -- produce well-spread RNG starts instead of similar sequences.
    seed = seed or 1
    seed = (seed * 2654435761) % 2147483647
    if seed == 0 then seed = 1 end
    lcgState = seed
end
local function lcgNext(maxN)
    -- Park-Miller minimal LCG, period ~2^31 - 1
    lcgState = (lcgState * 48271) % 2147483647
    return (lcgState % maxN) + 1
end

function M.Shuffle(deck, seed)
    lcgSeed(seed)
    -- Warmup: discard the first several outputs so the very first card
    -- positions don't reflect any structure from the raw seed mix.
    for _ = 1, 16 do lcgNext(2) end
    for i = #deck, 2, -1 do
        local j = lcgNext(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

-- Deal a slice. Mutates deck (pops from end).
function M.DealCount(deck, n)
    local out = {}
    for _ = 1, n do
        local c = table.remove(deck)
        if not c then break end
        out[#out + 1] = c
    end
    return out
end

-- -- Encoding ---------------------------------------------------------

function M.EncodeHand(cards)
    return table.concat(cards or {})
end

function M.DecodeHand(s)
    local out = {}
    if not s or #s == 0 then return out end
    for i = 1, #s, 2 do
        local c = s:sub(i, i + 1)
        if #c == 2 then out[#out + 1] = c end
    end
    return out
end

-- -- Card properties --------------------------------------------------

function M.Rank(card)
    return card and card:sub(1, 1) or nil
end

function M.Suit(card)
    return card and card:sub(2, 2) or nil
end

function M.IsValid(card)
    if type(card) ~= "string" or #card ~= 2 then return false end
    return K.RANK_INDEX[card:sub(1, 1)] ~= nil and K.SUIT_INDEX[card:sub(2, 2)] ~= nil
end

-- Trick-resolution numeric rank: higher = stronger. Considers contract.
--   contract: { type = "HOKM"|"SUN", trump = "S"|"H"|"D"|"C"|nil }
-- Nil-contract guards (post-audit hardening): all three functions are
-- called from many places in the codebase and most callers already
-- check `contract` is non-nil first. But the absence of a defensive
-- guard here means any future caller that drops the check would crash
-- on `contract.type` indexing nil. Keep these branches forgiving.
function M.TrickRank(card, contract)
    local r, s = M.Rank(card), M.Suit(card)
    if contract and contract.type == K.BID_HOKM
       and s == contract.trump then
        return K.RANK_TRUMP_HOKM[r] or 0
    end
    return K.RANK_PLAIN[r] or 0
end

function M.PointValue(card, contract)
    local r, s = M.Rank(card), M.Suit(card)
    if contract and contract.type == K.BID_HOKM
       and s == contract.trump then
        return K.POINTS_TRUMP_HOKM[r] or 0
    end
    return K.POINTS_PLAIN[r] or 0
end

function M.IsTrump(card, contract)
    if not contract or contract.type ~= K.BID_HOKM then return false end
    return M.Suit(card) == contract.trump
end

-- -- Display ---------------------------------------------------------

function M.RankGlyph(r)
    if r == "T" then return "10" end
    return r
end

function M.Pretty(card)
    if not M.IsValid(card) then return tostring(card) end
    local r, s = M.Rank(card), M.Suit(card)
    return ("|c%s%s%s|r"):format(K.SUIT_COLOR[s], M.RankGlyph(r), K.SUIT_GLYPH[s])
end

-- Variant for rendering on a cream / white card face. Uses the
-- four-color-deck convention so same-shape suits (♠/♣, ♥/♦) are
-- unambiguous at a glance.
function M.PrettyOnCard(card)
    if not M.IsValid(card) then return tostring(card) end
    local r, s = M.Rank(card), M.Suit(card)
    local color = K.SUIT_COLOR_ONCARD[s] or "ff0a0a0a"
    return ("|c%s%s%s|r"):format(color, M.RankGlyph(r), K.SUIT_GLYPH[s])
end

function M.PrettyList(cards)
    if not cards or #cards == 0 then return "(empty)" end
    local parts = {}
    for i, c in ipairs(cards) do parts[i] = M.Pretty(c) end
    return table.concat(parts, " ")
end

-- "Kawesh" / "Saneen" eligibility: a player whose first-five-dealt
-- hand contains only 7s, 8s, and 9s may annul during round 1 bidding.
-- Returns false if hand has 0 cards (game hasn't dealt yet) or any rank
-- outside {7, 8, 9}.
function M.IsKaweshHand(hand)
    if not hand or #hand == 0 then return false end
    for _, card in ipairs(hand) do
        local r = M.Rank(card)
        if r ~= "7" and r ~= "8" and r ~= "9" then return false end
    end
    return true
end

-- Sort a hand visually: by display-suit order, then by trick rank
-- descending. Display order *strictly alternates* colours so no two
-- adjacent suits share a colour — every boundary in the hand goes
-- black-red-black-red. Easier to scan than the BBRR group-by-colour
-- layout. Stable for display only — doesn't affect game state.
local SUIT_DISPLAY = { S = 1, H = 2, C = 3, D = 4 }  -- ♠ ♥ ♣ ♦  (B R B R)

function M.SortHand(cards, contract)
    contract = contract or { type = K.BID_SUN }
    table.sort(cards, function(a, b)
        local sa, sb = M.Suit(a), M.Suit(b)
        -- Audit fix: nil-safe SUIT_DISPLAY lookup. An invalid card with
        -- an unknown suit char would otherwise return nil here and Lua
        -- raises a "compare nil with number" runtime error inside
        -- table.sort. Coerce unknowns to a sentinel that sorts last.
        if sa ~= sb then
            return (SUIT_DISPLAY[sa] or 99) < (SUIT_DISPLAY[sb] or 99)
        end
        return M.TrickRank(a, contract) > M.TrickRank(b, contract)
    end)
    return cards
end
