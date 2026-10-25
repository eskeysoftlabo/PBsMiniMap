-- Cosmetic HUD presentation only. Map selection, zoom and pin positions remain native.
local addon = PBS_MINIMAP
if not addon then return end

function addon:ApplyLiteMapStyle()
    local scroll = ZO_WorldMapScroll
    if not scroll then return end
    local active = self.account and self.account.enableMap and not self.dormant
        and (self.initLevel or 0) < 3
        and not self.IsWorldMapInFront()
        and not self.IsWorldMapShownElsewhere()
    local circular = active and self.account.mapStyle == "compass"
    if not circular then
        if self.compassClipApplied then
            scroll:ClearCircularClip()
            self.compassClipApplied = false
        end
        if self.compassFrame then self.compassFrame:SetHidden(true) end
        return
    end

    if not self.compassFrame then
        local frame = WINDOW_MANAGER:CreateControl("PBsMiniMapCompassFrame", ZO_WorldMap, CT_TEXTURE)
        frame:SetTexture("PBsMiniMap/assets/compass-frame.dds")
        frame:SetMouseEnabled(false)
        frame:SetDrawTier(DT_HIGH)
        frame:SetDrawLayer(DL_OVERLAY)
        frame:SetDrawLevel(200)
        frame:SetAnchor(CENTER, scroll, CENTER)
        self.compassFrame = frame
    end
    local width, height = scroll:GetDimensions()
    local diameter = math.min(width, height)
    local x, y = scroll:GetCenter()
    -- Clip coordinates are screen UI units (as in ESO's ZO_RevealingControl).
    -- The cut lies beneath the opaque metal annulus, not in the transparent aperture.
    scroll:SetCircularClip(x, y, diameter * (self.account.showBorder and 0.42 or 0.49))
    self.compassClipApplied = true
    self.compassFrame:SetDimensions(diameter, diameter)
    self.compassFrame:SetHidden(not self.account.showBorder)
end

-- Nothing is hooked on the game's own controls.
--
-- The first version post-hooked ZO_WorldMapScroll's OnRectChanged handler. This add-on keeps
-- every hook it installs in one registry (HookHotPath / SwapHook) and swaps them out while the
-- standard map is in front, because writing a shared slot that does not belong to us is how
-- HarvestMap's pins were silently broken in 2.0.13. That handler sat outside the registry and
-- was never removed, so another add-on setting the same handler would stop the clip updating
-- without a trace.
--
-- It is not needed: the only things that resize the viewport are ApplyLiteMinimapLayout, which
-- now re-cuts the circle itself, and the standard map coming forward, which runs ApplyLiteBorder
-- on the way into dormancy. ApplyLiteBorder calls this too, so settings changes are covered.
