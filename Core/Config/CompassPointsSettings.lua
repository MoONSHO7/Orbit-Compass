local _, Addon = ...
local L = Addon.L
local Plugin = Addon.Controller
local ROW_HEIGHT = 28
local COLUMN_WIDTH = 60
local CHECKBOX_SIZE = 26
local LAYOUT_PADDING = 10
local TEXT_PADDING = 4
local HEADER_GAP = 2
local ROW_SHADE = { r = 1, g = 1, b = 1, a = 0.035 }
local COLUMNS = {
    { key = "city", labelKey = "PLU_COMPASS_CITIES", tooltipKey = "PLU_COMPASS_CITIES_TT" },
    { key = "world", labelKey = "PLU_COMPASS_OPEN_WORLD", tooltipKey = "PLU_COMPASS_OPEN_WORLD_TT" },
    { key = "toggle", labelKey = "PLU_COMPASS_TOGGLE", tooltipKey = "PLU_COMPASS_TOGGLE_TT" },
}
local POINTS = Addon.CompassPointTypes
local REQUIRED_ADDONS = { ShowGatherMate = "GatherMate2", ShowHandyNotes = "HandyNotes" }

local function ReleaseRow(_, row)
    row:Hide()
    row:ClearAllPoints()
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
            Addon.ClientFeatures.AllowsPoint(point.key) and (not requiredAddon or C_AddOns.IsAddOnLoaded(requiredAddon))
        then
            visibleIndex = visibleIndex + 1
            local row = frame.rows:Acquire()
            if not row.label then
                row.label = row:CreateFontString(nil, "ARTWORK", layout.constants.UI.LabelFont)
                row.label:SetJustifyH("LEFT")
                row.label:SetWordWrap(true)
                pixel:Point(row.label, "LEFT", row, "LEFT", TEXT_PADDING, 0)
                row.shade = row:CreateTexture(nil, "BACKGROUND")
                row.shade:SetAllPoints()
                row.shade:SetColorTexture(ROW_SHADE.r, ROW_SHADE.g, ROW_SHADE.b, ROW_SHADE.a)
            end
            row.label:SetText(L[point.labelKey])
            row.label:SetWidth(labelWidth - textPadding * 2)
            local height = pixel:Snap(math.max(ROW_HEIGHT, row.label:GetStringHeight() + textPadding * 2), scale)
            row:SetSize(width, height)
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
            row.shade:SetShown(visibleIndex % 2 == 0)
            for columnIndex, column in ipairs(COLUMNS) do
                local cell = CreateCell(layout, frame, row, point, column)
                cell:SetPoint(
                    "CENTER",
                    row,
                    "LEFT",
                    pixel:Snap(labelWidth + (columnIndex - 0.5) * columnWidth, scale),
                    0
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
