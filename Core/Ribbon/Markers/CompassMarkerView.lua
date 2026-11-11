local _, Addon = ...
local C = Addon.Constants
local Pixel = Addon.Services.pixel
local Plugin = Addon.Controller
local Art = Addon.CompassMarkerArt
local MarkerArtChanged = Art.Changed
local BindMarkerArt = Art.Bind
local QUEST_BACKGROUND_ATLAS = Art.QuestBackgroundAtlas
local BindInput = Addon.CompassMarkerInput.Bind
local TRACKED_GLOW_Y_OFFSET = -2
local FLIPPED_SELECTION_ROTATION = math.pi
local QUEST_SYMBOL_ATLASES = {
    ["Quest-In-Progress-Icon-yellow"] = true,
    ["UI-QuestIcon-TurnIn-Normal"] = true,
    ["Worldquest-icon"] = true,
}

function Plugin:RenderCompassMarker(button, marker, interactive, x, alpha, markerY, outline, scale)
    local questSymbol = not marker.texture
        and (marker.kind == "quest" or marker.kind == "worldQuest" or QUEST_SYMBOL_ATLASES[marker.atlas] == true)
        and Addon.Artwork.Exists(QUEST_BACKGROUND_ATLAS)
        and Addon.Artwork.Exists(marker.atlas)
    if MarkerArtChanged(button, marker, questSymbol) then
        BindMarkerArt(button, marker, questSymbol)
    end
    if button.marker ~= marker or button.interactive ~= interactive then
        BindInput(self, button, marker, interactive)
    end
    if #marker.overlapGroup.markers > 1 then
        button.revealAt = nil
    end
    if button.revealAt and self.markerClock < button.revealAt then
        self.markerRevealPending = true
        if button.renderShown then
            button:Hide()
            button.renderShown = false
        end
        return false
    end
    button.revealAt = nil
    local baseLevel = self.frame:GetFrameLevel()
    local level = baseLevel + marker.depthLevel
    if button:GetFrameLevel() ~= level then
        button:SetFrameLevel(level)
    end
    local selectionLevel = baseLevel + C.MARKER_BASE_LEVEL + C.MAX_MARKERS
    if button.selectionFrame:GetFrameLevel() ~= selectionLevel then
        button.selectionFrame:SetFrameLevel(selectionLevel)
    end
    local markerSize, hitSize = marker.projectedIconSize, marker.projectedHitSize
    if
        button.layoutSize ~= markerSize
        or button.layoutOutline ~= outline
        or button.layoutHitSize ~= hitSize
        or button.layoutScale ~= scale
        or button.layoutAtlas ~= marker.atlas
        or button.layoutBelowLine ~= marker.projectedBelowLine
    then
        button:SetSize(hitSize, hitSize)
        button.icon:SetSize(markerSize, markerSize)
        button.shadow:SetSize(markerSize + outline, markerSize + outline)
        local inset = Pixel:Snap((hitSize - markerSize) / 2, scale)
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        local shadowInset = Pixel:Snap((hitSize - markerSize - outline) / 2, scale)
        button.shadow:SetPoint("TOPLEFT", button, "TOPLEFT", shadowInset, -shadowInset)
        if button.resourceMasked then
            local borderSize = marker.projectedResourceBorderSize
            local borderInset = Pixel:Snap((hitSize - borderSize) / 2, scale)
            button.resourceBorder:SetSize(borderSize, borderSize)
            button.resourceBorder:SetPoint("TOPLEFT", button, "TOPLEFT", borderInset, -borderInset)
        end
        if button.symbol:IsShown() then
            local symbolWidth = Pixel:Snap(markerSize * button.symbolWidthScale, scale)
            local symbolHeight = Pixel:Snap(markerSize * button.symbolHeightScale, scale)
            button.symbol:SetSize(symbolWidth, symbolHeight)
            button.symbol:SetPoint(
                "TOPLEFT",
                button,
                "TOPLEFT",
                Pixel:Snap((hitSize - symbolWidth) / 2, scale),
                -Pixel:Snap((hitSize - symbolHeight) / 2, scale)
            )
        end
        local selectionSize = Pixel:Snap(markerSize * C.SELECTION_MARKER_SCALE, scale)
        local belowLine = marker.projectedBelowLine
        local rotation = belowLine and FLIPPED_SELECTION_ROTATION or 0
        button.selection:SetRotation(rotation)
        button.trackedGlow:SetRotation(rotation)
        button.selection:SetSize(selectionSize, selectionSize)
        button.selection:ClearAllPoints()
        button.selection:SetPoint(
            belowLine and "BOTTOMLEFT" or "TOPLEFT",
            button.icon,
            belowLine and "TOPLEFT" or "BOTTOMLEFT",
            Pixel:Snap((markerSize - selectionSize) / 2, scale),
            Pixel:Snap(selectionSize / 2, scale) * (belowLine and -1 or 1)
        )
        button.trackedGlow:SetSize(
            Pixel:Snap(markerSize * C.TRACKED_GLOW_WIDTH_SCALE, scale),
            Pixel:Snap(markerSize * C.TRACKED_GLOW_HEIGHT_SCALE, scale)
        )
        button.layoutSize, button.layoutOutline, button.layoutHitSize = markerSize, outline, hitSize
        button.layoutScale, button.layoutAtlas = scale, marker.atlas
        button.layoutBelowLine = belowLine
    end
    local centerX, centerY = self.artworkLayout.centerX, self.artworkLayout.centerY
    if marker.projectedBelowLine then
        markerY = self.lineY - Pixel:Multiple(C.LINE_THICKNESS + C.MARKER_BELOW_LINE_GAP, scale) - hitSize / 2
    end
    local left = marker.projectedLeft - centerX
    local top = Pixel:Snap(centerY + markerY + hitSize / 2, scale) - centerY
    if button.renderLeft ~= left or button.renderTop ~= top then
        button:SetPoint("TOPLEFT", self.frame, "CENTER", left, top)
        button.renderLeft, button.renderTop = left, top
    end
    button.renderX, button.renderY = left + hitSize / 2, top - hitSize / 2
    x = button.renderX
    local waypoint = marker.navigation == true
    if button.renderWaypoint ~= waypoint then
        button.selection:SetShown(waypoint)
        button.trackedGlow:SetShown(waypoint)
        button.renderWaypoint = waypoint
    end
    local glowY = self.lineY + Pixel:Multiple(TRACKED_GLOW_Y_OFFSET, scale)
    local glowAnchor = marker.projectedBelowLine and "TOP" or "BOTTOM"
    if waypoint and (button.glowX ~= x or button.glowY ~= glowY or button.glowAnchor ~= glowAnchor) then
        button.trackedGlow:ClearAllPoints()
        button.trackedGlow:SetPoint(glowAnchor, self.frame, "CENTER", x, glowY)
        button.glowX, button.glowY = x, glowY
        button.glowAnchor = glowAnchor
    end
    if not waypoint and marker.distance > self.range * (1 - C.MARKER_RANGE_FADE_FRACTION) then
        local fadeWidth = math.min(self.range * C.MARKER_RANGE_FADE_FRACTION, C.MARKER_RANGE_FADE_YARDS)
        local progress = math.max(0, math.min(1, (self.range - marker.distance) / fadeWidth))
        alpha = alpha * progress * progress * (3 - 2 * progress)
    end
    alpha = alpha * (marker.sourceAlpha or 1)
    if button.renderAlpha ~= alpha then
        button:SetAlpha(alpha)
        button.renderAlpha = alpha
    end
    if not button.renderShown then
        button.renderShown = true
        button:Show()
    end
    return true
end
