local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Services = Addon.Services
local Bridge = Addon.OrbitBridge
local Pixel = Services.pixel
local CompassMath = Addon.Math
local Plugin = Addon.Controller
local HEADING_ALPHA = 0.495
local MINOR_TICK_ALPHA = 0.1
local POINTER_ALPHA = 0.4
local WHITE = { r = 0.8, g = 0.82, b = 0.84 }
local PEEK_DESTINATION_EPSILON = 0.00001

local function IsTrackedPoint(marker, target)
    if marker.navigation then
        return true
    end
    if not target then
        return false
    end
    if marker.key == target.key or (marker.sourceKey or marker.key) == (target.sourceKey or target.key) then
        return true
    end
    local destination, tracked = marker.destination, target.destination
    return destination.mapID == tracked.mapID
        and math.abs(destination.x - tracked.x) < PEEK_DESTINATION_EPSILON
        and math.abs(destination.y - tracked.y) < PEEK_DESTINATION_EPSILON
end

function Plugin:FindCompassPeekMarker()
    local target = self.navigationTarget
    local trackedLeft, trackedRight, trackedSize, trackedLevel
    for _, marker in ipairs(self.markerGroupOrder) do
        local slot = self.markerSlotsByKey[marker.key]
        if slot.marker == marker and slot.renderShown and slot.renderAlpha > 0 and IsTrackedPoint(marker, target) then
            trackedLeft = trackedLeft and math.min(trackedLeft, marker.projectedLeftPx) or marker.projectedLeftPx
            trackedRight = trackedRight and math.max(trackedRight, marker.projectedRightPx) or marker.projectedRightPx
            trackedSize = math.max(trackedSize or 0, marker.projectedHitSize)
            trackedLevel = math.max(trackedLevel or 0, marker.depthLevel)
        end
    end
    for _, marker in ipairs(self.markerGroupOrder) do
        local slot = self.markerSlotsByKey[marker.key]
        if
            slot.marker == marker
            and slot.renderShown
            and slot.renderAlpha > 0
            and not IsTrackedPoint(marker, target)
        then
            local covered = trackedLeft
                and marker.depthLevel < trackedLevel
                and marker.projectedLeftPx >= trackedLeft
                and marker.projectedRightPx <= trackedRight
                and marker.projectedHitSize <= trackedSize
            if not covered then
                return marker, slot
            end
        end
    end
end

function Plugin:CreateCompassView()
    local frame = self.frame
    self.artwork, self.artworkLayout = {}, {}
    self.headingsDirty = true
    self.iconSize = C.DEFAULT_ICON_SIZE
    self.headingHeight = C.DEFAULT_FONT_SIZE
    local clear = CreateColor(WHITE.r, WHITE.g, WHITE.b, 0)
    local solid = CreateColor(WHITE.r, WHITE.g, WHITE.b, C.LINE_ALPHA)
    for index = 1, 3 do
        local texture = frame:CreateTexture(nil, "BORDER")
        texture:SetColorTexture(1, 1, 1)
        texture:SetSnapToPixelGrid(true)
        texture:SetTexelSnappingBias(0)
        texture:SetGradient("HORIZONTAL", index == 1 and clear or solid, index == 3 and clear or solid)
        self.artwork[index] = texture
    end
    self.pointer = frame:CreateTexture(nil, "OVERLAY")
    self.pointer:SetColorTexture(WHITE.r, WHITE.g, WHITE.b)
    self.pointer:SetSnapToPixelGrid(true)
    self.pointer:SetTexelSnappingBias(0)
    self.ticks, self.markerSlots, self.selectedMarkers = {}, {}, {}
    self.nextMarkerSlots, self.markerSlotsByKey = {}, {}
    self.markerGroupOrder, self.markerGroups = {}, {}
    self.markerLeftOrder, self.markerGroupMembers = {}, {}
    self.markerGeneration, self.markerClock = 0, 0
    local directions = {
        L.PLU_COMPASS_N,
        L.PLU_COMPASS_W,
        L.PLU_COMPASS_S,
        L.PLU_COMPASS_E,
    }
    for degrees = 0, C.FULL_TURN - C.TICK_STEP, C.TICK_STEP do
        local tick = { bearing = degrees, texture = frame:CreateTexture(nil, "ARTWORK") }
        tick.texture:SetColorTexture(WHITE.r, WHITE.g, WHITE.b)
        tick.texture:SetSnapToPixelGrid(true)
        tick.texture:SetTexelSnappingBias(0)
        if degrees % C.CARDINAL_STEP == 0 then
            tick.label = frame:CreateFontString(nil, "OVERLAY")
            tick.labelText = directions[degrees / C.CARDINAL_STEP + 1]
        end
        self.ticks[#self.ticks + 1] = tick
    end
    self:CreateCompassMarkerPool()
    self.detail = frame:CreateFontString(nil, "OVERLAY")
    self.detail:SetMaxLines(1)
    self.detail:Hide()
    self:CreateCompassPeek()
end

function Plugin:LayoutCompassArtwork()
    local frame = self.frame
    local scale = frame:GetEffectiveScale()
    local frameWidth, frameHeight = frame:GetSize()
    local centerX, centerY = frame:GetCenter()
    if not centerX or not centerY then
        return false
    end
    local thickness = Pixel:Multiple(C.LINE_THICKNESS, scale)
    local layout = self.artworkLayout
    if
        layout.width == frameWidth
        and layout.height == frameHeight
        and layout.centerX == centerX
        and layout.centerY == centerY
        and layout.scale == scale
        and layout.thickness == thickness
        and layout.headingHeight == self.headingHeight
        and layout.iconSize == self.iconSize
    then
        return true
    end
    layout.width, layout.height, layout.centerX, layout.centerY = frameWidth, frameHeight, centerX, centerY
    layout.scale, layout.thickness = scale, thickness
    layout.headingHeight, layout.iconSize = self.headingHeight, self.iconSize
    self.renderDirty, self.selectionDirty, self.headingsDirty = true, true, true
    self.detail:SetWidth(frameWidth)
    local width = math.max(0, frameWidth - Pixel:Multiple(C.EDGE_INSET * 2, scale))
    layout.contentWidth = width
    layout.markerY = Pixel:Snap(frameHeight * C.CONTENT_Y_FRACTION, scale)
    layout.halfTickWidth = Pixel:Multiple(C.TICK_WIDTH, scale) / 2
    -- Snap absolute edges so thin textures remain on the pixel grid at fractional frame positions.
    local lineY = Pixel:Snap(centerY + frameHeight * C.LINE_Y_FRACTION, scale) - centerY
    self.lineY = lineY
    local pointerHeight = Pixel:Multiple(C.POINTER_HEIGHT, scale)
    local pointerY = lineY - thickness - Pixel:Multiple(C.POINTER_GAP, scale)
    local maxMarkerSize = Pixel:Snap(self.iconSize * C.MARKER_NEAR_SCALE, scale)
    local markerBottom = layout.markerY
        - maxMarkerSize * (1 + C.SELECTION_MARKER_SCALE) / 2
        - Pixel:Multiple(C.MARKER_OUTLINE, scale)
    layout.headingY = Pixel:Snap(
        centerY + math.min(pointerY - pointerHeight, markerBottom) - Pixel:Multiple(C.HEADING_GAP, scale),
        scale
    ) - centerY
    self.detail:ClearAllPoints()
    self.detail:SetPoint(
        "TOP",
        frame,
        "CENTER",
        0,
        layout.headingY - Pixel:Snap(self.headingHeight, scale) - Pixel:Multiple(C.LABEL_GAP, scale)
    )
    local fadeWidth = width * C.LINE_FADE_FRACTION
    local sizes = { fadeWidth, width - fadeWidth * 2, fadeWidth }
    local left = -width / 2
    for index, texture in ipairs(self.artwork) do
        local right = left + sizes[index]
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", frame, "CENTER", Pixel:Snap(centerX + left, scale) - centerX, lineY)
        texture:SetPoint("TOPRIGHT", frame, "CENTER", Pixel:Snap(centerX + right, scale) - centerX, lineY)
        texture:SetHeight(thickness)
        left = right
    end
    self.pointer:SetSize(thickness, pointerHeight)
    self.pointer:ClearAllPoints()
    self.pointer:SetPoint("TOPLEFT", frame, "CENTER", Pixel:Snap(centerX - thickness / 2, scale) - centerX, pointerY)
    for _, tick in ipairs(self.ticks) do
        tick.texture:SetSize(Pixel:Multiple(C.TICK_WIDTH, scale), Pixel:Multiple(C.TICK_HEIGHT, scale))
    end
    return true
end

function Plugin:StyleCompassView()
    self.renderDirty, self.selectionDirty, self.headingsDirty = true, true, true
    local font = Services.GetFont()
    local fontSize = self:GetSetting(C.SYSTEM_INDEX, "FontSize")
    self.headingHeight = 0
    for _, tick in ipairs(self.ticks) do
        if tick.label then
            Services.StyleText(tick.label, { font = font, textSize = fontSize, textColor = WHITE })
            tick.label:SetText(tick.labelText)
            self.headingHeight = math.max(self.headingHeight, tick.label:GetStringHeight())
            tick.labelAlpha = nil
        end
    end
    Services.StyleText(self.detail, { font = font, textSize = fontSize, textColor = WHITE })
    self:StyleCompassPeek(font, fontSize, true)
    self:StyleNavigationView(font)
    for _, texture in ipairs(self.artwork) do
        texture:SetAlpha(1)
    end
    self.pointer:SetAlpha(POINTER_ALPHA)
    self:LayoutCompassArtwork()
end

function Plugin:ClearCompassMarkers()
    self:HideCompassPeek()
    self.markerPool:ReleaseAll()
    wipe(self.markerSlots)
    wipe(self.nextMarkerSlots)
    wipe(self.markerSlotsByKey)
    wipe(self.selectedMarkers)
    wipe(self.selectionKeys)
    wipe(self.markerGroupOrder)
    wipe(self.markerGroups)
    wipe(self.markerLeftOrder)
    wipe(self.markerGroupMembers)
    self.markerRevealPending = false
    self.selectionDirty = true
    self.detail:Hide()
    self.detailShown, self.renderDirty = false, true
end

function Plugin:RenderCompassHeadings(facing)
    if not self.headingsDirty and self.renderFacing == facing then
        return
    end
    local frame = self.frame
    local layout = self.artworkLayout
    local scale, width = layout.scale, layout.contentWidth
    local headingY, halfTickWidth = layout.headingY, layout.halfTickWidth
    for _, tick in ipairs(self.ticks) do
        local x, alpha
        if facing then
            x, alpha = CompassMath:Project(tick.bearing, facing, self.viewAngle, width)
        end
        local visible = x ~= nil
        if tick.visible ~= visible then
            tick.texture:SetShown(visible and not tick.label)
            if tick.label then
                tick.label:SetShown(visible)
            end
            tick.visible = visible
        end
        if x then
            x = Pixel:Snap(x, scale)
            local centerX = self.artworkLayout.centerX
            local tickX = Pixel:Snap(centerX + x - halfTickWidth, scale) - centerX
            if not tick.label then
                if tick.x ~= tickX or tick.y ~= self.lineY then
                    tick.texture:SetPoint("TOPLEFT", frame, "CENTER", tickX, self.lineY)
                    tick.x, tick.y = tickX, self.lineY
                end
                if tick.alpha ~= alpha then
                    tick.texture:SetAlpha(alpha * MINOR_TICK_ALPHA)
                    tick.alpha = alpha
                end
            end
            if tick.label then
                if tick.x ~= x or tick.y ~= headingY then
                    tick.label:SetPoint("TOP", frame, "CENTER", x, headingY)
                    tick.x, tick.y = x, headingY
                end
                local labelAlpha = alpha * HEADING_ALPHA
                if tick.labelAlpha ~= labelAlpha then
                    tick.label:SetAlpha(labelAlpha)
                    tick.labelAlpha = labelAlpha
                end
            end
        end
    end
    self.headingsDirty = false
end

function Plugin:RenderCompass(facing, live)
    if not live and not self:LayoutCompassArtwork() then
        return
    end
    local layout = self.artworkLayout
    local scale, width = layout.scale, layout.contentWidth
    self:RenderCompassHeadings(facing)
    local nearest, nearestDelta
    local outline = Pixel:Multiple(C.MARKER_OUTLINE * 2, scale)
    local interactive = not Addon.Services.IsEditMode()
    local selection = self:SelectCompassMarkers(facing, width, live)
    local profiler = Services.profiler
    local start, startKB
    if profiler and profiler.active then
        start, startKB = profiler:Begin()
    end
    self:LayoutCompassMarkerGroups(selection)
    if start then
        profiler:End(self, "Compass.Groups", start, startKB)
    end
    start, startKB = nil, nil
    if profiler and profiler.active then
        start, startKB = profiler:Begin()
    end
    self:AssignCompassMarkerSlots(selection, live)
    self.markerRevealPending = false
    for index, marker in ipairs(selection) do
        local slot = self.markerSlots[index]
        marker.renderShown = self:RenderCompassMarker(
            slot,
            marker,
            interactive,
            marker.projectedX,
            marker.projectedAlpha,
            layout.markerY,
            outline,
            scale
        )
        local absoluteDelta = math.abs(marker.projectedDelta)
        if
            marker.renderShown
            and absoluteDelta <= C.DETAIL_ANGLE
            and (
                not nearestDelta
                or absoluteDelta < nearestDelta
                or (absoluteDelta == nearestDelta and marker.distanceSquared < nearest.distanceSquared)
            )
        then
            nearest, nearestDelta = marker, absoluteDelta
        end
    end
    if start then
        profiler:End(self, "Compass.Markers", start, startKB)
    end
    self:RefreshCompassTooltip()
    local navigating = self:RenderNavigation(facing)
    if self.peekAltHeld and interactive then
        local marker, slot = self:FindCompassPeekMarker()
        if marker then
            self:ShowCompassPeek(marker, slot)
        else
            self:HideCompassPeek()
        end
    else
        self:HideCompassPeek()
    end
    if nearest and self.showLabel and not navigating and not self.peekAltHeld then
        local distance = self:CompassDisplayDistance(nearest.distance)
        if
            self.detailName ~= nearest.name
            or self.detailDistance ~= distance
            or self.detailUnits ~= self.distanceUnits
        then
            self.detail:SetText(
                L.PLU_COMPASS_DETAIL_F:format(nearest.name, self:FormatCompassDistance(nearest.distance))
            )
            self.detailName, self.detailDistance = nearest.name, distance
            self.detailUnits = self.distanceUnits
        end
        if not self.detailShown then
            self.detail:Show()
        end
        self.detailShown = true
    else
        if self.detailShown then
            self.detail:Hide()
        end
        self.detailShown = false
    end
    self.renderDirty, self.renderFacing, self.renderInteractive = false, facing, interactive
end
