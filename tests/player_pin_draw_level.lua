-- Run from the repository root: lua tests/player_pin_draw_level.lua
local f = assert(io.open("Main.lua", "rb"))
local source = f:read("*a")
f:close()
local first = assert(source:find("function addon:RestoreLitePlayerPinDrawLevel()", 1, true))
local last = assert(source:find("-- Swapping a hook in or out", first, true))
local addon = {account = {enableMap = true, followPlayer = false}, version = "test"}
local foreign, hidden, now = false, false, 1000
local control = {level = 0, writes = 0}
function control:GetDrawLevel() return self.level end
function control:SetDrawLevel(level) self.level = level; self.writes = self.writes + 1 end
function control:GetNamedChild() return nil end
function control:GetCenter() return 100, 100 end
function control:GetWidth() return 16 end
function control:GetHeight() return 16 end
function control:GetAlpha() return 1 end
function control:IsHidden() return false end
local pin = {GetControl = function() return control end}
addon.pinManager = {GetPlayerPin = function() return pin end}
local output = {}
local env = setmetatable({addon = addon, zo_max = math.max,
    IsWorldMapShownElsewhere = function() return foreign end,
    MAP_PIN_TYPE_PLAYER = 1, ZO_MapPin = {PIN_DATA = {{level = 170}}},
    ZO_WorldMap = {IsHidden = function() return hidden end},
    ZO_WorldMapScroll = {GetCenter = function() return 100, 100 end},
    GetFrameTimeMilliseconds = function() return now end,
    GetMapPlayerPosition = function() return 0.5, 0.5, 0, true, false end,
    GetMapName = function() return "test dungeon" end,
    GetCurrentMapId = function() return 1 end,
    GetMapFloorInfo = function() return 1, 1 end,
    DoesCurrentMapMatchMapForPlayerLocation = function() return true end,
    DoesCurrentMapShowPlayerWorld = function() return true end,
    d = function(line) output[#output + 1] = line end,
}, {__index = _G})
assert(load(source:sub(first, last - 1), "player-pin", "t", env))()

-- Native SetData assigns 0 to the non-clickable player pin parent; textures use 170.
addon:ApplyLitePlayerPinDrawLevel()
assert(control.level == 170, "raise the parent even when follow player is disabled")
addon:ApplyLitePlayerPinDrawLevel()
assert(control.writes == 1, "unchanged levels must not be written again")
control.level = 0 -- native refresh
addon:ApplyLitePlayerPinDrawLevel()
assert(control.level == 170)
foreign = true
addon:ApplyLitePlayerPinDrawLevel()
assert(control.level == 0 and addon.litePlayerPinDrawLevel == nil, "restore for full map")
foreign = false
addon:ApplyLitePlayerPinDrawLevel()
control.level = 190 -- another add-on takes ownership
addon:RestoreLitePlayerPinDrawLevel()
assert(control.level == 190, "do not overwrite another add-on's later change")
addon.dormant = true
addon:ApplyLitePlayerPinDrawLevel()
assert(control.level == 190)
addon.dormant = false
addon:ApplyLitePlayerPinDrawLevel()
addon.account.enableMap = false
addon:ApplyLitePlayerPinDrawLevel()
assert(control.level == 190, "disable restores the captured level")
addon.account.enableMap = true

addon:CaptureLitePlayerPinDiagnostic()
local sample = addon.playerPinDiagnostic
assert(#sample == 4 and sample[3]:find("offset=0.0,0.0", 1, true))
now = 1500
addon:CaptureLitePlayerPinDiagnostic()
assert(addon.playerPinDiagnostic == sample, "limit samples to once per second")
now = 2000; foreign = true
addon:CaptureLitePlayerPinDiagnostic()
addon:PrintLitePlayerPinDiagnostic()
assert(addon.playerPinDiagnostic == sample and #output == 4, "Settings must report the HUD sample")
foreign = false; hidden = true
addon:CaptureLitePlayerPinDiagnostic()
assert(addon.playerPinDiagnostic == sample)
print("PASS: player pin draw order, native refresh, restoration and HUD diagnostics")
