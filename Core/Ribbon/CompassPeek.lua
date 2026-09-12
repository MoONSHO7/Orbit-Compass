local _, Addon = ...
local Plugin = Addon.Controller
local Services = Addon.Services
local Pixel = Services.pixel
local PEEK_LEVEL = 26
local MAX_WIDTH = 240
local PADDING = 6
local HEADING_GAP = 6
local TEXT_GAP = 2
local CONNECTOR_WIDTH = 1
local NAME_LINES = 2
local BACKGROUND = { r = 0.025, g = 0.035, b = 0.055, a = 0.88 }
local NAME_COLOR = { r = 1, g = 1, b = 1 }
local DISTANCE_COLOR = { r = 0.8, g = 0.82, b = 0.84 }
local CONNECTOR_COLOR = { r = 1, g = 0.82, b = 0.46, a = 0.7 }

function Plugin:CreateCompassPeek()
    local frame = CreateFrame("Frame", nil, self.frame)
    frame:EnableMouse(false)
    frame:Hide()
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, BACKGROUND.a)
    local connector = frame:CreateTexture(nil, "BACKGROUND")
    connector:SetColorTexture(CONNECTOR_COLOR.r, CONNECTOR_COLOR.g, CONNECTOR_COLOR.b, CONNECTOR_COLOR.a)
    connector:SetSnapToPixelGrid(true)
    connector:SetTexelSnappingBias(0)
    local name = frame:CreateFontString(nil, "OVERLAY")
    name:SetMaxLines(NAME_LINES)
    name:SetJustifyH("CENTER")
    name:SetJustifyV("TOP")
    name:SetWordWrap(true)
    name:SetNonSpaceWrap(true)
    local distance = frame:CreateFontString(nil, "OVERLAY")
    distance:SetMaxLines(1)
    distance:SetJustifyH("CENTER")
    self.compassPeek = {
        frame = frame,
        name = name,
        distance = distance,
        connector = connector,
        shown = false,
        measureDirty = true,
    }
end

function Plugin:StyleCompassPeek(font, fontSize, refresh)
    local peek = self.compassPeek
    local scale = peek.frame:GetEffectiveScale()
    if not refresh and peek.font == font and peek.fontSize == fontSize and peek.fontScale == scale then
        return
    end
    Services.StyleText(peek.name, { font = font, textSize = fontSize, textColor = NAME_COLOR })
    Services.StyleText(peek.distance, { font = font, textSize = fontSize, textColor = DISTANCE_COLOR })
    peek.font, peek.fontSize, peek.fontScale = font, fontSize, scale
    peek.measureDirty = true
end

function Plugin:HideCompassPeek()
    local peek = self.compassPeek
    if peek.shown then
        peek.frame:Hide()
        peek.shown = false
    end
end

function Plugin:ShowCompassPeek(marker, slot)
    local peek, layout = self.compassPeek, self.artworkLayout
    local scale, centerX, centerY = layout.scale, layout.centerX, layout.centerY
    if peek.fontScale ~= scale then
        self:StyleCompassPeek(peek.font, peek.fontSize)
    end
    if peek.lastName ~= marker.name then
        peek.name:SetText(marker.name)
        peek.lastName, peek.measureDirty = marker.name, true
    end
    local displayDistance = self:CompassDisplayDistance(marker.distance)
    if peek.lastDistance ~= displayDistance or peek.lastUnits ~= self.distanceUnits then
        peek.distance:SetText(self:FormatCompassDistance(marker.distance))
        peek.lastDistance, peek.lastUnits = displayDistance, self.distanceUnits
        peek.measureDirty = true
    end
    local measured = peek.measureDirty
    if measured then
        peek.nameWidth = peek.name:GetUnboundedStringWidth()
        peek.distanceWidth = peek.distance:GetUnboundedStringWidth()
        peek.measureDirty = false
    end
    local padding = Pixel:Multiple(PADDING, scale)
    local textGap = Pixel:Multiple(TEXT_GAP, scale)
    local ribbonLeft = Pixel:Snap(centerX - layout.contentWidth / 2, scale)
    local ribbonRight = Pixel:Snap(centerX + layout.contentWidth / 2, scale)
    local width = math.min(
        Pixel:Snap(MAX_WIDTH, scale),
        ribbonRight - ribbonLeft,
        Pixel:Snap(math.max(peek.nameWidth, peek.distanceWidth) + padding * 2, scale)
    )
    if width <= padding * 2 then
        self:HideCompassPeek()
        return
    end
    if measured or peek.width ~= width or peek.scale ~= scale then
        local textWidth = width - padding * 2
        if peek.textWidth ~= textWidth then
            peek.name:SetWidth(textWidth)
            peek.distance:SetWidth(textWidth)
            peek.textWidth = textWidth
        end
        local nameHeight = Pixel:Snap(peek.name:GetStringHeight(), scale)
        local distanceHeight = Pixel:Snap(peek.distance:GetStringHeight(), scale)
        if peek.scale ~= scale then
            Pixel:Point(peek.name, "TOPLEFT", peek.frame, "TOPLEFT", PADDING, -PADDING)
        end
        if peek.nameHeight ~= nameHeight or peek.scale ~= scale then
            peek.distance:SetPoint("TOPLEFT", peek.frame, "TOPLEFT", padding, -padding - nameHeight - textGap)
            peek.nameHeight = nameHeight
        end
        local height = Pixel:Snap(nameHeight + distanceHeight + textGap + padding * 2, scale)
        if peek.width ~= width or peek.height ~= height then
            peek.frame:SetSize(width, height)
            peek.width, peek.height = width, height
        end
    end
    local hitSize, iconSize = marker.projectedHitSize, marker.projectedIconSize
    local inset = Pixel:Snap((hitSize - iconSize) / 2, scale)
    local iconX = slot.renderX - hitSize / 2 + inset + iconSize / 2
    local iconBottom = Pixel:Snap(centerY + slot.renderY + hitSize / 2 - inset - iconSize, scale)
    local left = math.max(ribbonLeft, math.min(ribbonRight - width, Pixel:Snap(centerX + iconX - width / 2, scale)))
    local top = Pixel:Snap(centerY + layout.headingY - self.headingHeight - Pixel:Multiple(HEADING_GAP, scale), scale)
    if peek.left ~= left or peek.top ~= top or peek.centerX ~= centerX or peek.centerY ~= centerY then
        peek.frame:SetPoint("TOPLEFT", self.frame, "CENTER", left - centerX, top - centerY)
        peek.left, peek.top = left, top
    end
    local lineWidth = Pixel:Multiple(CONNECTOR_WIDTH, scale)
    local lineLeft = Pixel:Snap(centerX + iconX - lineWidth / 2, scale)
    if
        peek.lineLeft ~= lineLeft
        or peek.lineTop ~= iconBottom
        or peek.centerX ~= centerX
        or peek.centerY ~= centerY
    then
        peek.connector:SetPoint("TOPLEFT", self.frame, "CENTER", lineLeft - centerX, iconBottom - centerY)
        peek.lineLeft, peek.lineTop = lineLeft, iconBottom
    end
    local lineHeight = math.max(lineWidth, iconBottom - top)
    if peek.lineWidth ~= lineWidth or peek.lineHeight ~= lineHeight then
        peek.connector:SetSize(lineWidth, lineHeight)
        peek.lineWidth, peek.lineHeight = lineWidth, lineHeight
    end
    peek.scale, peek.centerX, peek.centerY = scale, centerX, centerY
    local level = self.frame:GetFrameLevel() + PEEK_LEVEL
    if peek.frame:GetFrameLevel() ~= level then
        peek.frame:SetFrameLevel(level)
    end
    if not peek.shown then
        peek.frame:Show()
        peek.shown = true
    end
end
