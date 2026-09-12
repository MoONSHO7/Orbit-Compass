local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Services = Addon.Services
local Pixel = Services.pixel
local Plugin = Addon.Controller
local GameTooltip = Services.tooltip
local TYPE_COLOR = { r = 1, g = 0.82, b = 0 }
local FAILURE_COLOR = { r = 1, g = 0.2, b = 0.2 }
local ICON_COLOR = { r = 1, g = 1, b = 1 }
local FULL_TEX_COORDS = { left = 0, right = 1, top = 0, bottom = 1 }
local TYPE_LABELS = {
    quest = "PLU_COMPASS_TYPE_QUEST",
    worldQuest = "PLU_COMPASS_TYPE_WORLD_QUEST",
    treasure = "PLU_COMPASS_TYPE_TREASURE",
    rare = "PLU_COMPASS_TYPE_RARE",
    rareElite = "PLU_COMPASS_TYPE_RARE_ELITE",
    worldBoss = "PLU_COMPASS_TYPE_WORLD_BOSS",
    flightMaster = "PLU_COMPASS_TYPE_FLIGHT_MASTER",
    event = "PLU_COMPASS_TYPE_EVENT",
    race = "PLU_COMPASS_TYPE_RACE",
    questHub = "PLU_COMPASS_TYPE_QUEST_HUB",
    delve = "PLU_COMPASS_TYPE_DELVE",
    poi = "PLU_COMPASS_TYPE_POI",
    waypoint = "PLU_COMPASS_WAYPOINT",
    directions = "PLU_COMPASS_DIRECTIONS",
    mapLink = "PLU_COMPASS_MAP_LINKS",
    petTamer = "PLU_COMPASS_PET_TAMERS",
    digSite = "PLU_COMPASS_DIG_SITES",
    content = "PLU_COMPASS_TRACKED_CONTENT",
    questOffer = "PLU_COMPASS_QUEST_OFFERS",
    corpse = "PLU_COMPASS_CORPSE",
    saved = "PLU_COMPASS_SAVED_LOCATIONS",
    handynotes = "PLU_COMPASS_HANDYNOTES",
}
local QUEST_BACKGROUND_ATLAS = "UI-QuestPoi-QuestNumber"
local QUEST_SYMBOL_ATLASES = {
    ["Quest-In-Progress-Icon-yellow"] = true,
    ["UI-QuestIcon-TurnIn-Normal"] = true,
    ["Worldquest-icon"] = true,
}

local function LeaveMarker(button)
    Plugin:HideCompassHandyNotesTooltip(button)
    if Plugin.hoveredCompassMarker == button then
        Plugin.hoveredCompassMarker = nil
    end
    if GameTooltip:IsOwned(button) then
        Services.tooltipHide()
    end
    button.pressedMarker, button.tooltipDistance, button.failureReason = nil, nil, nil
    button.tooltipMarker, button.tooltipGroupCount = nil, nil
    button.handynotesTooltipFailed = nil
end

local function ShowMarkerTooltip(button)
    local marker = button.marker
    if not marker or Addon.Services.IsEditMode() then
        return
    end
    button.tooltipMarker = marker
    button.tooltipDistance = Plugin:CompassDisplayDistance(marker.distance)
    button.tooltipUnits = Plugin.distanceUnits
    button.tooltipGroupCount = #marker.overlapGroup.markers
    Plugin.hoveredCompassMarker = button
    if
        not button.failureReason
        and button.handynotesTooltipFailed ~= marker
        and Plugin:ShowCompassHandyNotesTooltip(button, marker, ShowMarkerTooltip)
    then
        return
    end
    Plugin:HideCompassHandyNotesTooltip(button)
    if GameTooltip:IsShown() and GameTooltip:IsOwned(button) then
        GameTooltip:ClearLines()
    else
        Services.AnchorTooltip(GameTooltip, button)
    end
    GameTooltip:SetText(marker.name, 1, 1, 1)
    GameTooltip:AddLine(Plugin:FormatCompassDistance(marker.distance), 1, 1, 1)
    GameTooltip:AddLine(L[TYPE_LABELS[marker.kind]], TYPE_COLOR.r, TYPE_COLOR.g, TYPE_COLOR.b)
    if button.tooltipGroupCount > 1 then
        GameTooltip:AddLine(L.PLU_COMPASS_OVERLAP_HINT_F:format(button.tooltipGroupCount), 1, 1, 1, true)
    end
    if button.failureReason then
        GameTooltip:AddLine(button.failureReason, FAILURE_COLOR.r, FAILURE_COLOR.g, FAILURE_COLOR.b, true)
    end
    GameTooltip:Show()
end

local function SameDestination(a, b)
    return a.key == b.key
        and a.destination.mapID == b.destination.mapID
        and a.destination.x == b.destination.x
        and a.destination.y == b.destination.y
        and Addon.HandyNotesClick:Matches(a.handynotesPoint, b.handynotesPoint)
end

local function ClickMarker(button)
    local pressed, marker = button.pressedMarker, button.marker
    button.pressedMarker = nil
    if not pressed or not marker or Addon.Services.IsEditMode() or not SameDestination(pressed, marker) then
        return
    end
    local markers = marker.overlapGroup.markers
    if #markers > 1 then
        LeaveMarker(button)
        Plugin:ShowCompassOverlapMenu(markers)
        return
    end
    local destination = marker.destination
    local success, reason = Plugin:SetWaypoint(
        destination.mapID,
        destination.x,
        destination.y,
        marker.name,
        marker.description,
        marker.sourceKey or marker.key,
        marker.handynotesPoint
    )
    if not success then
        button.failureReason = reason
        ShowMarkerTooltip(button)
    end
end

function Plugin:CreateCompassMarkerPool()
    self.markerPool = CreateObjectPool(function()
        local button = CreateFrame("Button", nil, self.frame, "OrbitCompassMarkerButtonTemplate")
        button.icon = button:CreateTexture(nil, "OVERLAY", nil, C.MARKER_ICON_SUBLEVEL)
        button.shadow = button:CreateTexture(nil, "OVERLAY", nil, C.MARKER_SHADOW_SUBLEVEL)
        button.shadow:SetAlpha(C.MARKER_OUTLINE_ALPHA)
        button.shadow:SetVertexColor(0, 0, 0)
        button.icon:SetRotation(0)
        button.shadow:SetRotation(0)
        button.icon:Show()
        button.shadow:Show()
        button.symbol = button:CreateTexture(nil, "OVERLAY", nil, C.MARKER_SYMBOL_SUBLEVEL)
        button.symbol:Hide()
        button.trackedGlow = button:CreateTexture(nil, "BACKGROUND")
        button.trackedGlow:SetAtlas(C.TRACKED_GLOW_ATLAS)
        button.trackedGlow:Hide()
        button.selectionFrame = CreateFrame("Frame", nil, button)
        button.selectionFrame:SetAllPoints(button)
        button.selectionFrame:EnableMouse(false)
        button.selection = button.selectionFrame:CreateTexture(nil, "OVERLAY", nil, C.SELECTION_MARKER_SUBLEVEL)
        button.selection:SetAtlas(C.SELECTION_MARKER_ATLAS)
        button.selection:SetRotation(0)
        button.selection:Hide()
        for _, texture in ipairs({ button.icon, button.shadow, button.symbol, button.selection }) do
            texture:SetSnapToPixelGrid(true)
            texture:SetTexelSnappingBias(0)
        end
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnEnter", ShowMarkerTooltip)
        button:SetScript("OnLeave", LeaveMarker)
        button:SetScript("OnHide", LeaveMarker)
        button:SetScript("OnMouseDown", function(frame, mouseButton)
            if mouseButton == "LeftButton" and not Addon.Services.IsEditMode() then
                frame.pressedMarker = frame.marker
            end
        end)
        button:SetScript("OnClick", ClickMarker)
        button:Hide()
        button.renderShown = false
        return button
    end, function(_, button)
        button:Hide()
        button:ClearAllPoints()
        if button.marker then
            button.marker.renderShown = false
        end
        button.marker, button.atlas = nil, nil
        button.sourceTexture, button.texLeft, button.texRight, button.texTop, button.texBottom = nil, nil, nil, nil, nil
        button.colorR, button.colorG, button.colorB = nil, nil, nil
        button.markerKey, button.revealAt, button.selected = nil, nil, false
        button.renderX, button.renderAlpha, button.renderWaypoint, button.renderShown = nil, nil, nil, false
        button.renderLeft, button.renderTop = nil, nil
        button.symbol:Hide()
        button.selection:Hide()
        LeaveMarker(button)
        button.trackedGlow:Hide()
    end)
end

function Plugin:AssignCompassMarkerSlots(selection, live)
    if not self.markerSlotsDirty and self.markerSlotsLive == live then
        return
    end
    self.markerSlotsDirty, self.markerSlotsLive = false, live
    local slots, nextSlots, byKey = self.markerSlots, self.nextMarkerSlots, self.markerSlotsByKey
    local generation = self.markerGeneration + 1
    self.markerGeneration = generation
    wipe(nextSlots)
    for index, marker in ipairs(selection) do
        local slot = byKey[marker.key]
        if slot then
            slot.markerGeneration = generation
            nextSlots[index] = slot
        end
    end
    local freeIndex = 1
    for index, marker in ipairs(selection) do
        local slot = nextSlots[index]
        if not slot then
            while slots[freeIndex] and slots[freeIndex].markerGeneration == generation do
                freeIndex = freeIndex + 1
            end
            slot = slots[freeIndex] or self.markerPool:Acquire()
            freeIndex = freeIndex + 1
            if slot.markerKey then
                byKey[slot.markerKey] = nil
            end
            slot.markerKey, slot.markerGeneration = marker.key, generation
            byKey[marker.key], nextSlots[index] = slot, slot
        end
        if not live or marker.navigation or marker.priority <= C.TRACKED_QUEST_PRIORITY then
            slot.revealAt = nil
        elseif not slot.selected or not slot.marker or slot.marker.key ~= marker.key then
            slot.revealAt = self.markerClock + C.MARKER_REVEAL_DELAY
        end
        slot.selected = true
    end
    for _, slot in ipairs(slots) do
        if slot.markerGeneration ~= generation then
            slot.selected, slot.revealAt = false, nil
            slot.marker.renderShown = false
            if slot.renderShown then
                slot:Hide()
                slot.renderShown = false
            end
            nextSlots[#nextSlots + 1] = slot
        end
    end
    self.markerSlots, self.nextMarkerSlots = nextSlots, slots
end

local function MarkerArtChanged(button, marker, questSymbol)
    return button.atlas ~= marker.atlas
        or button.sourceTexture ~= marker.texture
        or button.questSymbol ~= questSymbol
        or button.texLeft ~= marker.texLeft
        or button.texRight ~= marker.texRight
        or button.texTop ~= marker.texTop
        or button.texBottom ~= marker.texBottom
        or button.colorR ~= marker.colorR
        or button.colorG ~= marker.colorG
        or button.colorB ~= marker.colorB
end

local function BindMarkerArt(button, marker, questSymbol)
    if marker.texture then
        button.icon:SetTexture(marker.texture)
        button.shadow:SetTexture(marker.texture)
        local left, right = marker.texLeft or FULL_TEX_COORDS.left, marker.texRight or FULL_TEX_COORDS.right
        local top, bottom = marker.texTop or FULL_TEX_COORDS.top, marker.texBottom or FULL_TEX_COORDS.bottom
        button.icon:SetTexCoord(left, right, top, bottom)
        button.shadow:SetTexCoord(left, right, top, bottom)
        button.icon:SetVertexColor(
            marker.colorR or ICON_COLOR.r,
            marker.colorG or ICON_COLOR.g,
            marker.colorB or ICON_COLOR.b
        )
    else
        button.icon:SetTexCoord(
            FULL_TEX_COORDS.left,
            FULL_TEX_COORDS.right,
            FULL_TEX_COORDS.top,
            FULL_TEX_COORDS.bottom
        )
        button.shadow:SetTexCoord(
            FULL_TEX_COORDS.left,
            FULL_TEX_COORDS.right,
            FULL_TEX_COORDS.top,
            FULL_TEX_COORDS.bottom
        )
        local baseAtlas = questSymbol and QUEST_BACKGROUND_ATLAS or marker.atlas
        button.icon:SetAtlas(baseAtlas, questSymbol)
        button.shadow:SetAtlas(baseAtlas)
        button.icon:SetVertexColor(ICON_COLOR.r, ICON_COLOR.g, ICON_COLOR.b)
        if questSymbol then
            button.symbol:SetAtlas(marker.atlas, true)
            local width, height = button.icon:GetSize()
            local symbolWidth, symbolHeight = button.symbol:GetSize()
            button.symbolWidthScale, button.symbolHeightScale = symbolWidth / width, symbolHeight / height
        end
    end
    button.symbol:SetShown(questSymbol)
    button.atlas, button.sourceTexture, button.questSymbol = marker.atlas, marker.texture, questSymbol
    button.texLeft, button.texRight, button.texTop, button.texBottom =
        marker.texLeft, marker.texRight, marker.texTop, marker.texBottom
    button.colorR, button.colorG, button.colorB = marker.colorR, marker.colorG, marker.colorB
    button.layoutAtlas, button.renderAlpha = nil, nil
end

function Plugin:BindCompassMarker(button, marker, interactive)
    local changed = button.marker ~= marker
    if changed then
        self:HideCompassHandyNotesTooltip(button)
        button.handynotesTooltipFailed = nil
    end
    if changed and button.marker then
        button.marker.renderShown = false
    end
    button.marker = marker
    if changed then
        button.failureReason = nil
    end
    if button.interactive ~= interactive then
        button.interactive = interactive
        button:EnableMouse(interactive)
        if not interactive then
            LeaveMarker(button)
        end
    end
    if changed and interactive and self.hoveredCompassMarker == button then
        ShowMarkerTooltip(button)
    end
end

function Plugin:RefreshCompassTooltip()
    local button = self.hoveredCompassMarker
    if button and button.handynotesTooltip then
        if button.tooltipMarker ~= button.marker then
            self:HideCompassHandyNotesTooltip(button)
            ShowMarkerTooltip(button)
        end
        return
    end
    if button and GameTooltip:IsShown() and GameTooltip:IsOwned(button) then
        local marker = button.marker
        if
            button.tooltipMarker ~= marker
            or button.tooltipDistance ~= self:CompassDisplayDistance(marker.distance)
            or button.tooltipUnits ~= self.distanceUnits
            or button.tooltipGroupCount ~= #marker.overlapGroup.markers
        then
            ShowMarkerTooltip(button)
        end
    end
end

function Plugin:RenderCompassMarker(button, marker, interactive, x, alpha, markerY, outline, scale)
    local questSymbol = not marker.texture
        and (marker.kind == "quest" or marker.kind == "worldQuest" or QUEST_SYMBOL_ATLASES[marker.atlas] == true)
    if MarkerArtChanged(button, marker, questSymbol) then
        BindMarkerArt(button, marker, questSymbol)
    end
    if button.marker ~= marker or button.interactive ~= interactive then
        self:BindCompassMarker(button, marker, interactive)
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
    then
        button:SetSize(hitSize, hitSize)
        button.icon:SetSize(markerSize, markerSize)
        button.shadow:SetSize(markerSize + outline, markerSize + outline)
        local inset = Pixel:Snap((hitSize - markerSize) / 2, scale)
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        local shadowInset = Pixel:Snap((hitSize - markerSize - outline) / 2, scale)
        button.shadow:SetPoint("TOPLEFT", button, "TOPLEFT", shadowInset, -shadowInset)
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
        button.selection:SetSize(selectionSize, selectionSize)
        button.selection:SetPoint(
            "TOPLEFT",
            button.icon,
            "BOTTOMLEFT",
            Pixel:Snap((markerSize - selectionSize) / 2, scale),
            Pixel:Snap(selectionSize / 2, scale)
        )
        button.trackedGlow:SetSize(
            Pixel:Snap(markerSize * C.TRACKED_GLOW_WIDTH_SCALE, scale),
            Pixel:Snap(markerSize * C.TRACKED_GLOW_HEIGHT_SCALE, scale)
        )
        button.layoutSize, button.layoutOutline, button.layoutHitSize = markerSize, outline, hitSize
        button.layoutScale, button.layoutAtlas = scale, marker.atlas
    end
    local centerX, centerY = self.artworkLayout.centerX, self.artworkLayout.centerY
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
    if waypoint and (button.glowX ~= x or button.glowY ~= self.lineY) then
        button.trackedGlow:SetPoint("BOTTOM", self.frame, "CENTER", x, self.lineY)
        button.glowX, button.glowY = x, self.lineY
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
