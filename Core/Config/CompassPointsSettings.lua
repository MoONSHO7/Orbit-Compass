local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller
local ROW_HEIGHT = 28
local COLUMN_WIDTH = 60
local CHECKBOX_SIZE = 26
local LAYOUT_PADDING = 10
local TEXT_PADDING = 4
local HEADER_GAP = 2
local RANGE_BAND_HEIGHT = 16
local RANGE_HIT_HEIGHT = 12
local RANGE_TRACK_PX = 2
local RANGE_THUMB_WIDTH_PX = 4
local RANGE_THUMB_HEIGHT_PX = 10
local RANGE_VALUE_GAP_PX = 6
local ROW_SHADE = { r = 1, g = 1, b = 1, a = 0.035 }
local RANGE_TRACK_COLOR = { r = 1, g = 1, b = 1, a = 0.15 }
local RANGE_OWN_COLOR = { r = 1, g = 0.82, b = 0, a = 1 }
local RANGE_INHERITED_COLOR = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
local RANGE_HOVER_COLOR = { r = 1, g = 1, b = 1, a = 1 }
local COLUMNS = {
    { key = "city", labelKey = "PLU_COMPASS_CITIES", tooltipKey = "PLU_COMPASS_CITIES_TT" },
    { key = "world", labelKey = "PLU_COMPASS_OPEN_WORLD", tooltipKey = "PLU_COMPASS_OPEN_WORLD_TT" },
    { key = "toggle", labelKey = "PLU_COMPASS_TOGGLE", tooltipKey = "PLU_COMPASS_TOGGLE_TT" },
}
local POINTS = Addon.CompassPointTypes
local FOREVER = Addon.ClientFeatures.family == "forever"
-- Forever's quest-offer APIs return no givers, so its Available Quests exist only through QuestieDB.
local REQUIRED_ADDONS = {
    ShowGatherMate = "GatherMate2",
    ShowHandyNotes = "HandyNotes",
    ShowServices = "QuestieDB",
    ShowQuestOffers = FOREVER and "QuestieDB" or nil,
}

-- [ RANGE SLIDER ]-----------------------------------------------------------------------------------------------------
local function SetColor(texture, color)
    texture:SetColorTexture(color.r, color.g, color.b, color.a)
end

local function PaintRange(range, yards, own)
    range.yards, range.own, range.color = yards, own, own and RANGE_OWN_COLOR or RANGE_INHERITED_COLOR
    local travel = range:GetWidth() - range.thumb:GetWidth()
    local fraction = (yards - C.RANGE_MIN) / (C.RANGE_MAX - C.RANGE_MIN)
    range.fill:SetWidth(math.max(range.fill:GetHeight(), range.thumb:GetWidth() / 2 + travel * fraction))
    SetColor(range.fill, range.color)
    SetColor(range.thumb, range:IsMouseOver() and RANGE_HOVER_COLOR or range.color)
    range.valueText:SetText(Plugin:FormatCompassDistance(yards, "yards"))
    range.valueText:SetTextColor(range.color.r, range.color.g, range.color.b)
end

-- SetValue fires OnValueChanged synchronously; the guard keeps a displayed value from becoming a saved override.
local function ShowRange(range, pointKey)
    local yards, own = Plugin:GetCompassPointRange(pointKey)
    range.pointKey, range.initializing = pointKey, true
    range:SetValue(yards)
    range.initializing = false
    PaintRange(range, yards, own)
end

local function CommitRange(range, yards)
    Plugin:SetCompassPointRange(range.pointKey, yards)
    if Addon.OrbitBridge then
        Addon.App:Apply()
    end
end

local function CreateRange(layout, row)
    local GameTooltip, GameTooltip_Hide = layout.tooltip, layout.tooltipHide
    local range = CreateFrame("Slider", nil, row)
    range:SetOrientation("HORIZONTAL")
    range:SetMinMaxValues(C.RANGE_MIN, C.RANGE_MAX)
    range:SetValueStep(C.RANGE_STEP)
    range:SetObeyStepOnDrag(true)
    range:EnableMouse(true)
    range.track = range:CreateTexture(nil, "BACKGROUND")
    range.track:SetPoint("LEFT")
    range.track:SetPoint("RIGHT")
    SetColor(range.track, RANGE_TRACK_COLOR)
    range.fill = range:CreateTexture(nil, "ARTWORK")
    range.fill:SetPoint("LEFT")
    range.thumb = range:CreateTexture(nil, "OVERLAY")
    range:SetThumbTexture(range.thumb)
    range.valueText = row:CreateFontString(nil, "ARTWORK", layout.constants.UI.ValueFont)
    range.valueText:SetJustifyH("RIGHT")
    range:SetScript("OnValueChanged", function(self, value)
        if self.initializing or not self.pointKey then
            return
        end
        local yards = math.floor(value / C.RANGE_STEP + 0.5) * C.RANGE_STEP
        if yards ~= self.yards then
            CommitRange(self, yards)
            PaintRange(self, yards, true)
        end
    end)
    range:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self.pointKey and self.own then
            CommitRange(self, nil)
            ShowRange(self, self.pointKey)
        end
    end)
    range:SetScript("OnEnter", function(self)
        SetColor(self.thumb, RANGE_HOVER_COLOR)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.PLU_COMPASS_POINT_RANGE_F:format(self.pointLabel))
        GameTooltip:AddLine(L.PLU_COMPASS_POINT_RANGE_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    range:SetScript("OnLeave", function(self)
        SetColor(self.thumb, self.color)
        GameTooltip_Hide()
    end)
    range:SetScript("OnHide", GameTooltip_Hide)
    return range
end

local function LayoutRange(layout, row, point, top, width, scale)
    local pixel = layout.pixel
    local range = row.range or CreateRange(layout, row)
    row.range = range
    local textPadding = pixel:Multiple(TEXT_PADDING, scale)
    local valueWidth = pixel:Snap(COLUMN_WIDTH, scale)
    local center = top + pixel:EvenSnap(RANGE_BAND_HEIGHT, scale) / 2
    range:SetSize(
        width - textPadding * 2 - valueWidth - pixel:Multiple(RANGE_VALUE_GAP_PX, scale),
        pixel:EvenSnap(RANGE_HIT_HEIGHT, scale)
    )
    range:ClearAllPoints()
    range:SetPoint("LEFT", row, "TOPLEFT", textPadding, -center)
    range.track:SetHeight(pixel:Multiple(RANGE_TRACK_PX, scale))
    range.fill:SetHeight(pixel:Multiple(RANGE_TRACK_PX, scale))
    range.thumb:SetSize(pixel:Multiple(RANGE_THUMB_WIDTH_PX, scale), pixel:Multiple(RANGE_THUMB_HEIGHT_PX, scale))
    range.valueText:SetWidth(valueWidth)
    range.valueText:ClearAllPoints()
    range.valueText:SetPoint("RIGHT", row, "TOPRIGHT", -textPadding, -center)
    range.pointLabel = L[point.labelKey]
    ShowRange(range, point.key)
    range:Show()
    range.valueText:Show()
end

-- [ POINTS TABLE ]-----------------------------------------------------------------------------------------------------
local function ReleaseRow(_, row)
    row:Hide()
    row:ClearAllPoints()
    if row.range then
        row.range.pointKey = nil
        row.range:Hide()
        row.range.valueText:Hide()
    end
end

local function CreateTable(layout, container)
    local GameTooltip, GameTooltip_Hide = layout.tooltip, layout.tooltipHide
    local frame = CreateFrame("Frame", nil, container)
    frame.OrbitType = "CompassPoints"
    frame.cells = {}
    frame.rows = CreateFramePool("Frame", frame, nil, ReleaseRow)
    frame.heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.heading:SetJustifyH("LEFT")
    frame.heading:SetWordWrap(true)
    frame.columns = {}
    for index, column in ipairs(COLUMNS) do
        local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        heading:SetJustifyH("CENTER")
        heading:SetWordWrap(true)
        local hover = CreateFrame("Frame", nil, frame)
        hover:SetAllPoints(heading)
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L[column.labelKey])
            GameTooltip:AddLine(L[column.tooltipKey], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        hover:SetScript("OnLeave", GameTooltip_Hide)
        hover:SetScript("OnHide", GameTooltip_Hide)
        frame.columns[index] = heading
    end
    return frame
end

local function CreateRowHover(layout, row)
    local GameTooltip, GameTooltip_Hide = layout.tooltip, layout.tooltipHide
    local hover = CreateFrame("Frame", nil, row)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.title)
        GameTooltip:AddLine(self.description, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", GameTooltip_Hide)
    hover:SetScript("OnHide", GameTooltip_Hide)
    return hover
end

local function CreateCell(layout, frame, row, point, column)
    local cell = layout:CreateCheckbox(
        row,
        L.PLU_COMPASS_POINT_AREA_F:format(L[point.labelKey], L[column.labelKey]),
        L.PLU_COMPASS_POINT_AREAS_TT,
        Plugin:GetCompassPointVisibility(point.key, column.key),
        function(value)
            Plugin:SetCompassPointVisibility(point.key, column.key, value)
            if Addon.OrbitBridge then
                Addon.App:Apply()
            end
        end,
        { compact = true }
    )
    cell:SetLabel("")
    cell:SetWidth(layout.pixel:Snap(CHECKBOX_SIZE, cell:GetEffectiveScale()))
    cell:Show()
    frame.cells[#frame.cells + 1] = cell
    return cell
end

local function RenderTable(layout, container)
    local frame = table.remove(layout.compassPointsPool) or CreateTable(layout, container)
    frame:SetParent(container)
    local pixel = layout.pixel
    local scale = frame:GetEffectiveScale()
    local width = pixel:Snap(container:GetWidth() - LAYOUT_PADDING * 2, scale)
    local columnWidth = pixel:EvenSnap(COLUMN_WIDTH, scale)
    local labelWidth = width - columnWidth * #COLUMNS
    local textPadding = pixel:Multiple(TEXT_PADDING, scale)
    frame:SetWidth(width)
    frame.heading:SetText(L.PLU_COMPASS_POINT_TYPE)
    frame.heading:SetWidth(labelWidth - textPadding * 2)
    frame.heading:ClearAllPoints()
    pixel:Point(frame.heading, "TOPLEFT", frame, "TOPLEFT", TEXT_PADDING, -TEXT_PADDING)
    local headingHeight = frame.heading:GetStringHeight() + textPadding
    for index, column in ipairs(COLUMNS) do
        local heading = frame.columns[index]
        heading:SetText(L[column.labelKey])
        heading:SetWidth(columnWidth)
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", frame, "TOPLEFT", labelWidth + (index - 1) * columnWidth, -textPadding)
        headingHeight = math.max(headingHeight, heading:GetStringHeight() + textPadding)
    end
    local y = pixel:Snap(headingHeight, scale) + pixel:Multiple(HEADER_GAP, scale)
    local visibleIndex = 0
    for _, point in ipairs(POINTS) do
        local requiredAddon = REQUIRED_ADDONS[point.key]
        if
            Addon.ClientFeatures.AllowsPoint(point.key)
            and (not requiredAddon or C_AddOns.IsAddOnLoaded(requiredAddon))
        then
            visibleIndex = visibleIndex + 1
            local row = frame.rows:Acquire()
            if not row.label then
                row.label = row:CreateFontString(nil, "ARTWORK", layout.constants.UI.LabelFont)
                row.label:SetJustifyH("LEFT")
                row.label:SetWordWrap(true)
                row.shade = row:CreateTexture(nil, "BACKGROUND")
                row.shade:SetAllPoints()
                row.shade:SetColorTexture(ROW_SHADE.r, ROW_SHADE.g, ROW_SHADE.b, ROW_SHADE.a)
                row.hover = CreateRowHover(layout, row)
            end
            row.label:SetText(L[point.labelKey])
            row.hover.title = L[point.labelKey]
            row.hover.description = L[FOREVER and point.foreverTooltipKey or point.tooltipKey]
            row.label:SetWidth(labelWidth - textPadding * 2)
            local top = pixel:Snap(math.max(ROW_HEIGHT, row.label:GetStringHeight() + textPadding * 2), scale)
            local middle = pixel:Snap(top / 2, scale)
            local height = top
            if not point.ignoresRange then
                LayoutRange(layout, row, point, top, width, scale)
                height = top + pixel:EvenSnap(RANGE_BAND_HEIGHT, scale)
            end
            row:SetSize(width, height)
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row, "TOPLEFT", textPadding, -middle)
            row.hover:SetAllPoints(row.label)
            row.shade:SetShown(visibleIndex % 2 == 0)
            for columnIndex, column in ipairs(COLUMNS) do
                local cell = CreateCell(layout, frame, row, point, column)
                cell:SetPoint(
                    "CENTER",
                    row,
                    "TOPLEFT",
                    pixel:Snap(labelWidth + (columnIndex - 0.5) * columnWidth, scale),
                    -middle
                )
            end
            row:Show()
            y = y + height
        end
    end
    frame:SetHeight(y)
    return frame
end

function Addon.RegisterSettingsWidgets(layout)
    Addon.RegisterPointHotkeyWidget(layout)
    if layout:HasWidgetType("compasspoints") then
        return
    end
    layout:RegisterControlPool("CompassPoints", "compassPointsPool", function(frame)
        layout.tooltipHide()
        for _, cell in ipairs(frame.cells) do
            layout:ReleaseControl(cell)
        end
        wipe(frame.cells)
        frame.rows:ReleaseAll()
    end)
    layout:RegisterWidgetType("compasspoints", function(container)
        return RenderTable(layout, container)
    end)
end

function Addon.PointsSettings()
    return {
        { type = "compasspointhotkey", label = L.PLU_COMPASS_POINT_HOTKEY },
        { type = "compasspoints", key = "PointVisibility", label = L.PLU_COMPASS_POINTS },
    }
end
