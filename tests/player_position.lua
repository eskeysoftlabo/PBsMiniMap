-- Run from the repository root: lua tests/player_position.lua
-- Exercise the production follow loop without loading ESO's scene/UI managers.
local file = assert(io.open("Main.lua", "rb"))
local source = file:read("*a")
file:close()
assert(load((source:gsub("^\239\187\191", "")), "Main.lua"))
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start, true)) - 1)
end
local code = section("function addon:IsLitePlayerPositionUsable", "-- Votan's UpdatePinsForMapSizeChange")
    .. section("\tlocal lastPlayerX, lastPlayerY", "\tfunction addon:StartLiteZoneWatch()")
    .. section("\tfunction addon:FollowPlayerTick()", "\t-- Hooks the lite path needs.")

local function fixture()
    local state = {x = 0.4, y = 0.6, shown = true, symbolic = false, now = 0,
        matches = true, selects = 0, centres = 0, refreshes = 0, hidden = false}
    local pin = {IsHidden = function() return state.hidden end,
        SetOriginalPosition = function(_, x, y) state.pinX, state.pinY = x, y end,
        SetIsSymbolicPosition = function(_, value) assert(not value) end,
        SetLocation = function(_, x, y) assert(x == state.x and y == state.y) end,
        SetRotation = function(_, heading) assert(heading == 1.2) end,
        SetHidden = function(_, value) state.hidden = value end}
    local addon = {account = {enableMap = true, followPlayer = true}, pinManager = {GetPlayerPin = function() return pin end},
        CheckLiteMapPicture = function() end, AdjustLiteZoom = function() return false end,
        ResetLiteLayoutBackoff = function() end, IsLiteSizeCurrent = function() return true end,
        IsLitePositionCurrent = function() return true end,
        CentreOnPlayer = function(_, x, y)
            state.centres = state.centres + 1
            assert(x == state.x and y == state.y)
        end,
        IsWorldMapShownElsewhere = function() return state.foreign end}
    local env = setmetatable({addon = addon, zo_abs = math.abs,
        ZO_WorldMap = {IsHidden = function() return state.mapHidden end},
        ZO_WorldMapContainer = {GetDimensions = function() return 1000, 1000 end},
        GetMapTileTexture = function() return "tile" end,
        GetFrameTimeMilliseconds = function() return state.now end,
        GetMapPlayerPosition = function() return state.x, state.y, 0, state.shown, state.symbolic end,
        GetPlayerCameraHeading = function() return 1.2 end,
        DoesCurrentMapMatchMapForPlayerLocation = function() return state.matches end,
        IsWorldMapInFront = function() return state.inFront end,
        IsWorldMapShownElsewhere = function() return state.foreign end,
        SET_MAP_RESULT_MAP_CHANGED = 1,
        SetMapToPlayerLocation = function()
            state.selects = state.selects + 1
            if state.recover then state.shown = true; state.matches = true; return 1 end
            return 0
        end,
        CALLBACK_MANAGER = {FireCallbacks = function(_, event)
            assert(event == "OnWorldMapChanged"); state.refreshes = state.refreshes + 1
        end}}, {__index = _G})
    env.ZO_WorldMapPins_Manager = {UpdateMovingPins = function()
        state.nativeCalls = (state.nativeCalls or 0) + 1
        state.hidden = not state.shown
        return "native result"
    end}
    env.HookHotPath = function(target, name, wrapper)
        local original = target[name]
        state.original = original
        target[name] = wrapper
        return original
    end
    assert(load(code, "follow-loop", "t", env))()
    addon:InitLitePlayerPinVisibilityHook()
    state.nativeUpdate = function(manager)
        return env.ZO_WorldMapPins_Manager.UpdateMovingPins(manager or addon.pinManager)
    end
    return addon, state
end

local addon, s = fixture()
addon:FollowPlayerTick()
addon:FollowPlayerTick()
assert(s.selects == 0 and s.centres == 1, "normal follow must not refresh repeatedly")
s.shown = false; s.matches = false
addon:FollowPlayerTick()
assert(s.selects == 1 and addon.followSkip == "noposition")
for i = 1, 9 do s.now = i * 100; addon:FollowPlayerTick() end
assert(s.selects == 1, "unavailable positions must not cause 10Hz resyncs")
s.now = 1000; s.recover = true; s.hidden = true
addon:FollowPlayerTick()
assert(s.selects == 2 and s.refreshes == 1 and s.centres == 2)
assert(not s.hidden and s.pinX == s.x, "restore the hidden pin after valid coordinates return")

addon, s = fixture()
addon:FollowPlayerTick()
s.symbolic = true; s.hidden = true
addon:FollowPlayerTick()
s.symbolic = false; s.now = 100
addon:FollowPlayerTick()
assert(s.selects == 1 and s.refreshes == 0 and s.centres == 2 and not s.hidden,
    "stationary players must recover on the same map without a full map refresh")
s.hidden = true
addon:FollowPlayerTick()
assert(not s.hidden and s.centres == 2, "hidden-pin recovery must work without movement")

for _, position in ipairs({
    {0, 0, true, false}, {1, 0.5, true, false}, {-1, 0.5, true, false},
    {0.4, 0.6, true, true}, {0/0, 0.5, true, false},
}) do
    addon, s = fixture()
    s.x, s.y, s.shown, s.symbolic = table.unpack(position)
    s.hidden = true
    addon:FollowPlayerTick()
    assert(s.selects == 1 and s.centres == 0 and s.hidden)
end

-- Exact visibility discrepancy from the user's Shadow Cleft diagnostic image.
addon, s = fixture()
s.x, s.y, s.shown, s.hidden = 0.2113, 0.8483, false, true
addon:FollowPlayerTick()
assert(s.selects == 0 and s.centres == 1 and not s.hidden)
for i = 1, 20 do
    assert(s.nativeUpdate() == "native result")
    assert(not s.hidden and s.pinX == s.x and s.pinY == s.y,
        "repair must survive every native update, not only the follow timer")
end
assert(s.nativeCalls == 20)
addon.account.followPlayer = false
s.nativeUpdate()
assert(not s.hidden, "marker visibility is independent of automatic centring")
addon.account.followPlayer = true
s.matches = false
s.nativeUpdate()
assert(s.hidden, "never override visibility for a different map/floor")
s.matches = true; s.symbolic = true
s.nativeUpdate()
assert(s.hidden, "never turn a symbolic entrance into a player marker")
s.symbolic = false; s.x = 0
s.nativeUpdate()
assert(s.hidden, "loading sentinels must stay hidden")
s.x = 0.2113
for _, guard in ipairs({"dormant", "foreign", "inFront", "mapHidden", "disabled"}) do
    addon.dormant = guard == "dormant"
    addon.account.enableMap = guard ~= "disabled"
    s.foreign, s.inFront, s.mapHidden = guard == "foreign", guard == "inFront", guard == "mapHidden"
    s.nativeUpdate()
    assert(s.hidden, guard)
end
addon.dormant = false; addon.account.enableMap = true
s.foreign, s.inFront, s.mapHidden = false, false, false
s.nativeUpdate({})
assert(s.hidden, "do not repair pins belonging to a different manager")
s.original()
assert(s.hidden, "the original full-map update remains unchanged")

for _, guard in ipairs({"dormant", "foreign", "mapHidden", "off"}) do
    addon, s = fixture()
    s.shown = false
    if guard == "dormant" then addon.dormant = true
    elseif guard == "off" then addon.account.followPlayer = false
    else s[guard] = true end
    addon:RequestMapResync()
    addon:FollowPlayerTick()
    assert(s.selects == 0 and s.centres == 0, guard)
end

addon, s = fixture()
s.matches = false
addon:FollowPlayerTick()
addon:FollowPlayerTick()
assert(s.selects == 1, "map mismatch retries must also be throttled")
addon:RequestMapResync()
addon:FollowPlayerTick()
assert(s.selects == 2, "a new zone event must bypass the previous retry delay")
print("PASS: player position recovery, retry limits, visibility and scene guards")
