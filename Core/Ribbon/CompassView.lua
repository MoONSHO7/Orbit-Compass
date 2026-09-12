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
    self.ticks, self.markerSlots, self.occupiedCells, self.selectedMarkers = {}, {}, {}, {}
    self.nextMarkerSlots, self.markerSlotsByKey = {}, {}
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
    layout.markerSourceSize = nil
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
    self:StyleNavigationView(font)
    for _, texture in ipairs(self.artwork) do
        texture:SetAlpha(1)
    end
    self.pointer:SetAlpha(POINTER_ALPHA)
    self:LayoutCompassArtwork()
end

function Plugin:ClearCompassMarkers()
    self.markerPool:ReleaseAll()
    wipe(self.markerSlots)
    wipe(self.nextMarkerSlots)
    wipe(self.markerSlotsByKey)
    wipe(self.selectedMarkers)
    wipe(self.selectionKeys)
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
    local markerY = layout.markerY
    self:RenderCompassHeadings(facing)
    local nearest, nearestDelta
    if layout.markerSourceSize ~= self.iconSize then
        -- Reserve the largest marker footprint so distance changes preserve spacing and click areas.
        layout.maxIconSize = Pixel:Snap(self.iconSize * C.MARKER_NEAR_SCALE, scale)
        layout.outline = Pixel:Multiple(C.MARKER_OUTLINE * 2, scale)
        layout.gap = Pixel:Multiple(C.MARKER_GAP, scale)
        layout.pitch = layout.maxIconSize + layout.outline + layout.gap
        layout.retainedPitch = layout.maxIconSize + layout.outline + layout.gap * C.MARKER_RETAINED_GAP_FRACTION
        layout.markerSourceSize = self.iconSize
    end
    local maxIconSize, outline = layout.maxIconSize, layout.outline
    local pitch, retainedPitch = layout.pitch, layout.retainedPitch
    local interactive = not Addon.Services.IsEditMode()
    local selection = self:SelectCompassMarkers(facing, width, pitch, live, retainedPitch)
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
            markerY,
            maxIconSize,
            outline,
            scale
        )
        local absoluteDelta = math.abs(marker.projectedDelta)
        if
            marker.renderShown
            and absoluteDelta <= C.DETAIL_ANGLE
            and (not nearestDelta or absoluteDelta < nearestDelta)
        then
            nearest, nearestDelta = marker, absoluteDelta
        end
    end
    self:RefreshCompassTooltip()
    local navigating = self:RenderNavigation(facing)
    if nearest and self.showLabel and not navigating then
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
