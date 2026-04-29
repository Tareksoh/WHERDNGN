-- Tiny ring-buffer logger. Mirrors GOBIGnINTERRUPT's pattern so
-- /baloot log dumps recent events.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Log = B.Log or {}
local L = B.Log

local BUF_SIZE = 200
local buf = {}
local idx = 0

local function push(level, tag, fmt, ...)
    -- Capture varargs HERE — `...` does not cross into the inner closure
    -- below (which would be a parse error).
    local args = { ... }
    local n = select("#", ...)
    local ok, msg = pcall(function()
        if n == 0 then return tostring(fmt) end
        return string.format(tostring(fmt), unpack(args))
    end)
    local line = ("%.3f [%s] %s: %s"):format(GetTime(), level, tag or "?", ok and msg or tostring(fmt))
    idx = idx + 1
    buf[((idx - 1) % BUF_SIZE) + 1] = line
end

function L.Debug(tag, fmt, ...)
    if not WHEREDNGNDB or not WHEREDNGNDB.debug then return end
    push("D", tag, fmt, ...)
end

function L.Info(tag, fmt, ...)
    push("I", tag, fmt, ...)
end

function L.Warn(tag, fmt, ...)
    push("W", tag, fmt, ...)
end

function L.Error(tag, fmt, ...)
    push("E", tag, fmt, ...)
end

function L.Dump(n)
    n = tonumber(n) or 50
    local count = math.min(n, idx, BUF_SIZE)
    local start = idx - count + 1
    for i = start, idx do
        local line = buf[((i - 1) % BUF_SIZE) + 1]
        if line then print(line) end
    end
end

function L.Clear()
    buf = {}
    idx = 0
end
