-- Run from the repository root: lua tests/standard_map_zoom.lua
--
-- The zoom the standard map comes up at. Runs the real SetDormant(true) and the post-opening
-- tidy-up out of Main.lua, against a stand-in for ZO_MapPanAndZoom that keeps the game's own
-- zoom arithmetic where it matters here: JumpToPin without useCurrentZoom goes to the maximum
-- (GetNormalizedPositionFocusZoomAndOffset, worldmap.lua), and SetZoomMinMax leaves the
-- normalized zoom exactly as it was.
local file = assert(io.open("Main.lua", "rb"))
local source = file:read("*a")
file:close()
assert(load((source:gsub("^\239\187\191", "")), "Main.lua"))
local first = assert(source:find("-- Drop the gamepad map's sticky pin before centring.", 1, true))
local last = assert(source:find("addon.pinManager = ZO_WorldMap_GetPinManager()", first, true))
local slice = source:sub(first, last - 1)

local MAP_MODE_LARGE_CUSTOM, MAP_MODE_FAST_TRAVEL, MAP_MODE_KEEP_TRAVEL, MAP_MODE_DIG_SITES = 2, 4, 3, 7

-- A fresh copy of the code and a fresh game for every case: SetDormant keeps its state in a
-- file-level local, so a second call on the same copy would be a no-op.
local function fixture(options)
    options = options or {}
    local game = {order = {}, now = 0, stickyEnabled = true, playerChose = options.playerChose or false,
        inSpecialMode = options.mode ~= nil, mode = options.mode or MAP_MODE_LARGE_CUSTOM,
        pinHidden = options.pinHidden or false}

    local function note(entry) game.order[#game.order + 1] = entry end

    local panZoom = {currentNormalizedZoom = options.zoom or 1, minZoom = 0.3, maxZoom = 0.6,
        pendingInitializeMap = options.pendingInitializeMap or false,
        targetNormalizedZoom = options.staleTarget}
    function panZoom:GetCurrentNormalizedZoom() return self.currentNormalizedZoom end
    function panZoom:SetCurrentNormalizedZoomInternal(z)
        self.currentNormalizedZoom = math.max(0, math.min(1, z)); note("relayout")
    end
    function panZoom:SetCurrentNormalizedZoom(z)
        self.targetNormalizedZoom = nil           -- ClearTargetNormalizedZoom
        self:SetCurrentNormalizedZoomInternal(z)
    end
    function panZoom:ComputeMinZoom() return 1 end
    function panZoom:ComputeMaxZoom() return 8.66 end
    -- Leaves the normalized zoom alone, as the game does: the same 1 is simply the top of a
    -- different range afterwards.
    function panZoom:SetMapZoomMinMax(lo, hi) self.minZoom, self.maxZoom = lo, hi; note("range") end
    function panZoom:ClearTargetOffset() note("clearTarget") end
    function panZoom:OnWorldMapShowing()
        game.zoomAtShowing = self.currentNormalizedZoom; note("showing")
    end
    -- worldmap.lua: targetNormalizedZoom = useCurrentZoom and current or 1
    function panZoom:JumpToPin(pin, useCurrentZoom)
        assert(pin == game.pin, "jumped to something that is not the player pin")
        game.jumps = (game.jumps or 0) + 1
        game.lastJumpUsedCurrentZoom = useCurrentZoom
        self.currentNormalizedZoom = useCurrentZoom and self.currentNormalizedZoom or 1
        self.targetNormalizedZoom = nil
        note("jump")
    end
    function panZoom:SetNormalizedZoomAndOffsetInNewMap(z)
        game.navigatedTo = z
        self.currentNormalizedZoom = z; self.targetNormalizedZoom = nil
        self:JumpToPin(game.pin, true)
        note("navigate")
    end

    game.pin = {GetControl = function() return {IsHidden = function() return game.pinHidden end} end}
    local sticky = {pin = "stale"}
    function sticky:ClearStickyPin() self.pin = nil; note("clearSticky") end
    function sticky:SetEnabled(v) game.stickyEnabled = v end

    local addon = {account = {}, panZoom = panZoom, initLevel = 2, version = "test",
        pinManager = {GetPlayerPin = function() return game.pin end}}
    -- Methods (capitalised) that have nothing to do with the zoom are no-ops; fields are not.
    setmetatable(addon, {__index = function(_, k)
        if type(k) == "string" and k:match("^[A-Z]") then return function() end end
    end})

    local env = setmetatable({
        addon = addon,
        IsWorldMapInFront = function() return options.inFront ~= false end,
        IsWorldMapShownElsewhere = function() return false end,
        WORLD_MAP_MANAGER = {inSpecialMode = game.inSpecialMode, GetMode = function() return game.mode end},
        MAP_MODE_FAST_TRAVEL = MAP_MODE_FAST_TRAVEL, MAP_MODE_KEEP_TRAVEL = MAP_MODE_KEEP_TRAVEL,
        ZO_WorldMap_DidPlayerChooseCurrentMap = function() return game.playerChose end,
        ZO_WorldMap_ClearCustomZoomLevels = function() note("clearCustom") end,
        ZO_WorldMap_GetStickyPin = function() return sticky end,
        -- worldmap.lua: JumpToPin(pin) with no useCurrentZoom, so the maximum zoom. Anything
        -- reaching this from the standard-map path is the bug.
        ZO_WorldMap_JumpToPlayer = function()
            game.jumpToPlayerCalls = (game.jumpToPlayerCalls or 0) + 1
            panZoom.currentNormalizedZoom = 1
        end,
        ZO_MapPanAndZoom = {NAVIGATE_IN_OR_OUT_NORMALIZED_ZOOM_ADJUSTMENT = 0.1},
        IsInGamepadPreferredMode = function() return true end,
        GetFrameTimeMilliseconds = function() return game.now end,
        zo_round = function(v) return math.floor(v + 0.5) end,
    }, {__index = _G})
    assert(load(slice, "Main.lua slice", "t", env))()
    game.addon, game.panZoom, game.sticky = addon, panZoom, sticky
    return game
end

local function open(game) game.addon:SetDormant(true); return game end
local function pending(game) return game.addon.pendingCentreTicks end

-- ---------------------------------------------------------------------------------------------
-- The map the player opens
-- ---------------------------------------------------------------------------------------------
do
    local g = open(fixture({zoom = 1}))        -- the minimap leaves its own zoom at the top of its range
    assert(g.zoomAtShowing == 0, "the standard map opened at the minimap's zoom: " .. tostring(g.zoomAtShowing))
    assert(g.panZoom.currentNormalizedZoom == 0, "left magnified: " .. g.panZoom.currentNormalizedZoom)
    assert(g.panZoom.minZoom == 1 and g.panZoom.maxZoom == 8.66, "the game's own range has to come back")
    local seq = table.concat(g.order, ",")
    local relayout, range, showing = seq:find("relayout", 1, true), seq:find("range", 1, true), seq:find("showing", 1, true)
    assert(relayout < range and range < showing, "order must stay relayout, range, showing: " .. seq)
    assert(not g.jumpToPlayerCalls, "ZO_WorldMap_JumpToPlayer jumps to the maximum zoom")
end

do -- a zoom target left over from the HUD would ease the map back up
    local g = open(fixture({zoom = 1, staleTarget = 1}))
    assert(g.panZoom.targetNormalizedZoom == nil, "a stale zoom target survives and pulls the zoom back")
end

do -- already at the bottom of the range: nothing to correct, still fine
    local g = open(fixture({zoom = 0}))
    assert(g.panZoom.currentNormalizedZoom == 0)
end

-- ---------------------------------------------------------------------------------------------
-- Other ways the map comes up
-- ---------------------------------------------------------------------------------------------
for _, mode in ipairs({MAP_MODE_FAST_TRAVEL, MAP_MODE_KEEP_TRAVEL}) do
    -- The game resets the zoom itself when a travel map is pushed; the HUD can put the minimap's
    -- back in the instant before dormancy, so it is set again to what the game chose.
    local g = open(fixture({zoom = 1, mode = mode}))
    assert(g.zoomAtShowing == 0, "travel map opened magnified: " .. tostring(g.zoomAtShowing))
end

do -- a view the game sets up itself (antiquity dig) is its to zoom
    local g = open(fixture({zoom = 0.7, mode = MAP_MODE_DIG_SITES}))
    assert(g.panZoom.currentNormalizedZoom == 0.7, "reset a zoom the game chose for the dig site")
    assert(g.zoomAtShowing == nil, "centred a view the game sets up itself")
    assert(table.concat(g.order, ","):find("range", 1, true), "the zoom range is still handed back")
end

do -- the player already chose a map: that view, and its zoom, are left as they are
    local g = open(fixture({zoom = 0.4, playerChose = true}))
    assert(g.panZoom.currentNormalizedZoom == 0.4, "reset the zoom of a map the player chose")
end

do -- the log the report prints
    local g = open(fixture({zoom = 1}))
    local line = assert(g.addon.mapZoomLog[1], "nothing recorded for the report")
    assert(line:find("^open ") and line:find("zoom 1.00->0.00", 1, true) and line:find("rng=1.00-8.66", 1, true),
        "the line must show the zoom before and after and the range it opened with: " .. line)
end

-- ---------------------------------------------------------------------------------------------
-- The tidy-up after a held-back opening or level change
-- ---------------------------------------------------------------------------------------------
do -- first opening after a reload: held back, then lands. Must not zoom in.
    local g = open(fixture({zoom = 1, pendingInitializeMap = true}))
    assert(pending(g), "a held-back opening was not noticed")
    g.panZoom.pendingInitializeMap = false
    g.addon:UpdatePendingCentre()
    assert(g.jumps == 1 and g.lastJumpUsedCurrentZoom == true, "the tidy-up must jump at the current zoom")
    assert(not g.jumpToPlayerCalls, "the tidy-up called ZO_WorldMap_JumpToPlayer")
    assert(g.panZoom.currentNormalizedZoom == 0, "the tidy-up changed the zoom to " .. g.panZoom.currentNormalizedZoom)
    assert(g.sticky.pin == nil, "the stale sticky pin survived")
    assert(g.stickyEnabled == false, "the sticky pin may re-grab on the frame it was dropped")
    assert(g.addon.mapZoomLog[#g.addon.mapZoomLog]:find("^tidy "), "the tidy-up is not in the report")
end

do -- zooming out to the parent map while it loads: what InitializeMap's navigate branch gives
    local g = open(fixture({zoom = 0.5}))
    g.panZoom.pendingInitializeMap = true
    g.addon:ArmCentreTidyUp(false)
    assert(pending(g))
    g.panZoom.pendingInitializeMap = false
    g.addon:UpdatePendingCentre()
    assert(math.abs(g.navigatedTo - 0.9) < 1e-9, "zooming out should land at 0.9, got " .. tostring(g.navigatedTo))
    assert(math.abs(g.panZoom.currentNormalizedZoom - 0.9) < 1e-9)
    assert(not g.jumpToPlayerCalls, "called ZO_WorldMap_JumpToPlayer")
    assert(g.sticky.pin == nil and g.addon.pendingCentreNavigateIn == nil)
end

do -- and in
    local g = open(fixture({zoom = 0.5}))
    g.panZoom.pendingInitializeMap = true
    g.addon:ArmCentreTidyUp(true)
    g.panZoom.pendingInitializeMap = false
    g.addon:UpdatePendingCentre()
    assert(math.abs(g.navigatedTo - 0.1) < 1e-9, "zooming in should land at 0.1, got " .. tostring(g.navigatedTo))
end

do -- not held up: nothing is armed and nothing is touched
    local g = open(fixture({zoom = 1}))
    g.panZoom.pendingInitializeMap = false
    g.addon:ArmCentreTidyUp(false)
    assert(not pending(g), "armed a tidy-up for a change the game handled itself")
    g.addon:UpdatePendingCentre()
    assert(not g.jumps and not g.navigatedTo, "touched a map the game had already placed")
end

do -- still loading: waits, and gives up after the window
    local g = open(fixture({zoom = 1, pendingInitializeMap = true}))
    for _ = 1, 10 do g.addon:UpdatePendingCentre() end
    assert(not g.jumps, "tidied up before the map had loaded")
    for _ = 1, 60 do g.addon:UpdatePendingCentre() end
    assert(not pending(g) and not g.jumps, "never gave up on a map that never loaded")
end

do -- the player pin is not on screen: the game leaves the view alone there too
    local g = open(fixture({zoom = 1, pendingInitializeMap = true, pinHidden = true}))
    g.panZoom.pendingInitializeMap = false
    g.addon:UpdatePendingCentre()
    assert(not g.jumps and not g.navigatedTo, "jumped to a player pin that is not shown")
end

do -- the player chose the map themselves: no tidy-up is armed for it
    local g = open(fixture({zoom = 0.4, pendingInitializeMap = true, playerChose = true}))
    assert(not pending(g), "armed a tidy-up on a map the player chose")
end

print("PASS: standard map opens at the whole-map zoom, and the tidy-up keeps it")
