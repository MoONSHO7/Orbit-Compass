local _, Addon = ...
local C = Addon.Constants
local Pixel = Addon.Services.pixel
local Plugin = Addon.Controller
local BELOW = "below"
local NAME_FONT = "GameFontNormalLarge"
local DISTANCE_FONT = "GameFontHighlightSmall"
local NAME_COLOR = { r = 1, g = 0.82, b = 0 }
local DISTANCE_COLOR = { r = 0.8, g = 0.82, b = 0.84 }
local FADE_SECONDS = 0.2
local SLIDE = 4
local GAP_ABOVE = 20
local GAP_BELOW = 16
local LINE_GAP = 1
local MIN_FACING_ANGLE = 3
local MAX_FACING_ANGLE = 15
local SMOKE_ATLAS = "BonusChest-OrangeSmoke-Wide"
local SMOKE_SHADE = 0.1
local SMOKE_ALPHA = 0.6
local SMOKE_PAD_X = 28
local SMOKE_PAD_Y = 10
local SMOKE_MIN_WIDTH = 110
local QUEST_ATLAS = "QuestNormal"
local QUEST_SCALE = 1.2
local QUEST_GAP = 2

local function CreateLine(frame, fontObject)
    local line = frame:CreateFontString(nil, "OVERLAY")
    line:SetFontObject(fontObject)
    line:SetMaxLines(1)
    line:SetJustifyH("CENTER")
    line:Hide()
    return line
end

function Plugin:CreateCompassPlaceLabel()
    local text, distance = CreateLine(self.frame, NAME_FONT), CreateLine(self.frame, DISTANCE_FONT)
    distance:SetTextColor(DISTANCE_COLOR.r, DISTANCE_COLOR.g, DISTANCE_COLOR.b)
    -- Blizzard's wide orange smoke, desaturated and darkened into a soft backdrop behind both lines.
    local smoke = self.frame:CreateTexture(nil, "BACKGROUND")
    smoke:SetAtlas(SMOKE_ATLAS)
    smoke:SetDesaturated(true)
    smoke:SetVertexColor(SMOKE_SHADE, SMOKE_SHADE, SMOKE_SHADE)
    smoke:SetPoint("TOP", text, "TOP", 0, SMOKE_PAD_Y)
    smoke:SetPoint("BOTTOM", distance, "BOTTOM", 0, -SMOKE_PAD_Y)
    smoke:Hide()
    local quest = self.frame:CreateTexture(nil, "ARTWORK")
    Addon.Artwork.Apply(quest, QUEST_ATLAS)
    quest:Hide()
    self.compassPlaceLabel = {
        text = text,
        distance = distance,
        smoke = smoke,
        quest = quest,
        alpha = 0,
        color = NAME_COLOR,
        quests = false,
        questShown = false,
    }
end

-- Blizzard's own large and small text by default; Compass's font override swaps only their face. A font object also
-- resets colour and justification, so both are restored, keeping an enemy place's red.
function Plugin:StyleCompassPlaceLabel(fontOverride)
    local label = self.compassPlaceLabel
    for line, fontObject in pairs({ [label.text] = NAME_FONT, [label.distance] = DISTANCE_FONT }) do
        line:SetFontObject(fontObject)
        line:SetJustifyH("CENTER")
        if fontOverride then
            local _, height, flags = line:GetFont()
            line:SetFont(Addon.Services.FontPath(fontOverride), height, flags)
        end
    end
    label.text:SetTextColor(label.color.r, label.color.g, label.color.b)
    label.distance:SetTextColor(DISTANCE_COLOR.r, DISTANCE_COLOR.g, DISTANCE_COLOR.b)
    label.smokeScale = nil
end

function Plugin:HideCompassPlaceLabel()
    local label = self.compassPlaceLabel
    label.text:Hide()
    label.distance:Hide()
    label.smoke:Hide()
    label.quest:Hide()
    label.alpha, label.name, label.clock, label.shown = 0, nil, nil, false
    label.quests, label.questShown = false, false
    self.compassPlaceLabelAnimating = false
end

-- The view centre must fall on the place itself: its angular half-width, kept within the minimum and maximum.
function Plugin:FindCompassFacedPlace(selection)
    local best, bestDelta
    for _, marker in ipairs(selection) do
        if marker.cityRegion and marker.renderShown and not marker.projectedRetiring then
            local region = marker.cityRegion
            local width, height =
                (region.right - region.left) * self.mapWidth, (region.bottom - region.top) * self.mapHeight
            local halfAngle = math.deg(math.atan((width + height) / 4 / math.max(marker.distance, 1)))
            halfAngle = math.max(MIN_FACING_ANGLE, math.min(MAX_FACING_ANGLE, halfAngle))
            local delta = math.abs(marker.projectedDelta)
            if delta <= halfAngle and (not best or delta < bestDelta) then
                best, bestDelta = marker, delta
            end
        end
    end
    return best
end

local function SetDistance(plugin, label, place)
    local shown = plugin:CompassDisplayDistance(place.distance)
    if label.distanceShown ~= shown or label.distanceUnits ~= plugin.distanceUnits then
        label.distance:SetText(plugin:FormatCompassDistance(place.distance))
        label.distanceShown, label.distanceUnits = shown, plugin.distanceUnits
    end
end

-- Above, the distance line sits nearest the ribbon with the name over it, clear of the largest place icon; below, the
-- name leads under the headings on Show Label's line. Both slide in from the ribbon's side.
local function Place(plugin, label, layout, below, rest)
    local scale, centerY = layout.scale, layout.centerY
    local anchor, restY, toward
    -- Either way the title stays on screen, nearer the ribbon when the compass sits at the screen's edge.
    if below then
        anchor, toward = "TOP", 1
        restY = math.max(layout.labelY - Pixel:Multiple(GAP_BELOW, scale), label.height - centerY)
    else
        local icon = Pixel:Snap(plugin.iconSize * C.MARKER_NEAR_SCALE * C.CITY_MARKER_SCALE, scale)
        local screenTop = UIParent:GetHeight() * UIParent:GetEffectiveScale() / scale - centerY
        anchor, toward = "BOTTOM", -1
        restY = math.min(
            layout.markerY + icon / 2 + Pixel:Multiple(C.MARKER_OUTLINE + GAP_ABOVE, scale),
            screenTop - label.height
        )
    end
    local slide = toward * Pixel:Multiple(SLIDE, scale) * rest * rest
    local y = Pixel:Snap(centerY + restY + slide, scale) - centerY
    local text, distance = label.text, label.distance
    if label.anchor ~= anchor then
        text:ClearAllPoints()
        distance:ClearAllPoints()
        if below then
            distance:SetPoint("TOP", text, "BOTTOM", 0, -LINE_GAP)
        else
            text:SetPoint("BOTTOM", distance, "TOP", 0, LINE_GAP)
        end
        label.anchor, label.y = anchor, nil
    end
    if label.y ~= y then
        local lead = below and text or distance
        lead:SetPoint(anchor, plugin.frame, "CENTER", 0, y)
        label.y = y
    end
end

-- Fades toward the faced place; another place first fades the old name out. A settled title stops its clock so the
-- next fade starts from that frame. Returns whether it holds Show Label's line, where Alt's callout also draws.
function Plugin:RenderCompassPlaceLabel(place, peeking)
    local label, layout = self.compassPlaceLabel, self.artworkLayout
    local below = self.placeNameMode == BELOW
    if peeking and below then
        place = nil
    end
    local clock = self.markerClock
    local step = label.clock and (clock - label.clock) / FADE_SECONDS or 0
    local alpha = label.alpha
    if place and place.name == label.name then
        alpha = math.min(1, alpha + step)
        SetDistance(self, label, place)
        label.quests = place.cityRegion.offersQuests == true
    else
        alpha = math.max(0, alpha - step)
        if alpha == 0 and place then
            local color = self:IsCompassPlaceHostile(place) and C.HOSTILE_PLACE_COLOR or NAME_COLOR
            label.name, label.smokeScale, label.color = place.name, nil, color
            label.text:SetText(place.name)
            label.text:SetTextColor(color.r, color.g, color.b)
            SetDistance(self, label, place)
            label.quests = place.cityRegion.offersQuests == true
        end
    end
    label.alpha = alpha
    local animating = alpha ~= (place and 1 or 0) or (place ~= nil and place.name ~= label.name)
    self.compassPlaceLabelAnimating = animating
    label.clock = animating and clock or nil
    if alpha == 0 then
        if label.shown then
            label.text:Hide()
            label.distance:Hide()
            label.smoke:Hide()
            label.quest:Hide()
            label.shown, label.questShown = false, false
        end
        return below and place ~= nil
    end
    local scale = layout.scale
    if label.smokeScale ~= scale then
        local width = math.max(label.text:GetUnboundedStringWidth(), label.distance:GetUnboundedStringWidth())
        label.smoke:SetWidth(Pixel:Snap(math.max(SMOKE_MIN_WIDTH, width + SMOKE_PAD_X * 2), scale))
        local nameHeight = label.text:GetStringHeight()
        label.height = nameHeight + LINE_GAP + label.distance:GetStringHeight()
        local questSize = Pixel:Snap(nameHeight * QUEST_SCALE, scale)
        label.quest:SetSize(questSize, questSize)
        -- The quest bang hangs off the name's left edge, so the name itself stays centred on the view.
        label.quest:SetPoint("RIGHT", label.text, "LEFT", -Pixel:Multiple(QUEST_GAP, scale), 0)
        label.smokeScale = scale
    end
    Place(self, label, layout, below, 1 - alpha)
    if label.shownAlpha ~= alpha then
        label.text:SetAlpha(alpha)
        label.distance:SetAlpha(alpha)
        label.smoke:SetAlpha(alpha * SMOKE_ALPHA)
        label.quest:SetAlpha(alpha)
        label.shownAlpha = alpha
    end
    if not label.shown then
        label.text:Show()
        label.distance:Show()
        label.smoke:Show()
        label.shown = true
    end
    if label.questShown ~= label.quests then
        label.quest:SetShown(label.quests)
        label.questShown = label.quests
    end
    return below
end
