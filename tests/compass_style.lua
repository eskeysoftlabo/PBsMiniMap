-- Run from the repository root: lua tests/compass_style.lua
local addon = {account = {enableMap = true, mapStyle = "square", showBorder = true}, initLevel = 2}
local foreign, full = false, false
addon.IsWorldMapInFront = function() return full end
addon.IsWorldMapShownElsewhere = function() return foreign end
local scroll = {width = 304, height = 368, x = 600, y = 400, clears = 0}
function scroll:GetDimensions() return self.width, self.height end
function scroll:GetCenter() return self.x, self.y end
function scroll:SetCircularClip(x, y, radius) self.clip = {x, y, radius} end
function scroll:ClearCircularClip() self.clip = nil; self.clears = self.clears + 1 end
local frame, allocations
allocations = 0
local wm = {}
function wm:CreateControl(name, parent, kind)
    allocations = allocations + 1
    frame = {parent = parent}
    function frame:SetTexture(path) self.texture = path end
    function frame:SetMouseEnabled(enabled) self.mouse = enabled end
    function frame:SetDrawTier(value) self.tier = value end
    function frame:SetDrawLayer(value) self.layer = value end
    function frame:SetDrawLevel(value) self.level = value end
    function frame:SetAnchor(_, relative) self.relative = relative end
    function frame:SetDimensions(w, h) self.width, self.height = w, h end
    function frame:SetHidden(value) self.hidden = value end
    return frame
end
local env = setmetatable({PBS_MINIMAP = addon, ZO_WorldMapScroll = scroll, ZO_WorldMap = {},
    WINDOW_MANAGER = wm, CT_TEXTURE = 1, DT_HIGH = 3, DL_OVERLAY = 4, CENTER = 5},
    {__index = _G})
assert(loadfile("Compass.lua", "t", env))()
-- Nothing is hooked on the game's own controls: the style is re-applied from the add-on's own
-- layout and border paths, so the only entry point is ApplyLiteMapStyle.
assert(rawget(addon, "InitCompassStyle") == nil, "no handler is installed on a client control")
addon:ApplyLiteMapStyle()
addon:ApplyLiteMapStyle()
assert(allocations == 0 and not scroll.clip, "existing square style stays unchanged")
addon.account.mapStyle = "compass"
addon:ApplyLiteMapStyle()
assert(frame.width == 304 and frame.height == 304 and not frame.hidden and not frame.mouse)
assert(scroll.clip[1] == 600 and scroll.clip[2] == 400 and scroll.clip[3] == 304 * 0.42)
assert(frame.parent == env.ZO_WorldMap and frame.relative == scroll, "frame must not be circularly clipped")
-- A resize: ApplyLiteMinimapLayout re-cuts the circle itself once it has sized the viewport.
scroll.x, scroll.y, scroll.width, scroll.height = 800, 550, 500, 200
addon:ApplyLiteMapStyle()
assert(scroll.clip[1] == 800 and scroll.clip[2] == 550 and scroll.clip[3] == 84)
assert(frame.width == 200 and frame.height == 200)
addon.account.showBorder = false
addon:ApplyLiteMapStyle()
assert(frame.hidden and scroll.clip[3] == 98, "border off keeps a circular map")
addon.account.showBorder = true
for _, condition in ipairs({"dormant", "full", "foreign", "disabled", "square"}) do
    addon:ApplyLiteMapStyle()
    assert(scroll.clip and not frame.hidden)
    if condition == "dormant" then addon.dormant = true
    elseif condition == "full" then full = true
    elseif condition == "foreign" then foreign = true
    elseif condition == "disabled" then addon.account.enableMap = false
    else addon.account.mapStyle = "square" end
    addon:ApplyLiteMapStyle()
    assert(not scroll.clip and frame.hidden, condition .. " must restore the full viewport")
    local clears = scroll.clears
    addon:ApplyLiteMapStyle()
    assert(scroll.clears == clears, "do not repeatedly clear another owner's clipping")
    addon.dormant, full, foreign = false, false, false
    addon.account.enableMap, addon.account.mapStyle = true, "compass"
end
assert(allocations == 1, "reuse the texture across settings and scene changes")
-- The texture has to exist, be a DXT5 DDS with a mip chain, and be listed in the manifest --
-- an unlisted file is inaccessible at runtime and draws as a 1x1 pixel.
local path = frame.texture:gsub("^PBsMiniMap/", "")
local f = assert(io.open(path, "rb"))
local header = f:read(128); f:close()
assert(header:sub(1, 4) == "DDS ", "not a DDS file")
assert(header:sub(85, 88) == "DXT5", "not DXT5")
assert(header:byte(29) > 1, "no mip chain: the frame shimmers when drawn small")
local manifest = assert(io.open("PBsMiniMap.addon", "rb")):read("a")
assert(manifest:find(path, 1, true), "the texture is not listed in the manifest")
print("PASS: compass geometry, settings, clipping restoration, resize and asset reference")
