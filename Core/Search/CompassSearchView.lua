local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Services = Addon.Services
local Pixel = Services.pixel
local Plugin = Addon.Controller
local GameTooltip = Services.tooltip
local ICON_SIZE = 10
local ICON_GAP = 12
local SEARCH_LEVEL = 27
local FIELD_GAP = 4
local FIELD_WIDTH = 200
local FIELD_HEIGHT = 16
local LIST_GAP = 8
local LIST_WIDTH = 380
local ROW_HEIGHT = 24
local ROW_ICON_SIZE = 16
local ROW_TEXT_GAP = 8
local ROW_DETAIL_GAP = 12
local ROW_NAME_MAX_WIDTH = 210
local MAX_ROWS = 12
local NAME_FONT_SIZE = 14
local DETAIL_FONT_SIZE = 12
local ICON_ALPHA = 0.55
local ICON_ACTIVE_ALPHA = 1
local REFRESH_INTERVAL = 0.25
local TYPING_DELAY = 0.08
local SEARCH_ATLAS = "common-search-magnifyingglass"
local WHITE = { r = 1, g = 1, b = 1, a = 1 }
local GOLD = C.NAVIGATION_TEXT_COLOR
local DETAIL_COLOR = { r = 0.66, g = 0.66, b = 0.66, a = 1 }

local function SetResultIcon(texture, result)
    if result.texture then
        if Addon.Artwork.ApplyTexture(texture, result.texture) then
            texture:SetTexCoord(result.texLeft or 0, result.texRight or 1, result.texTop or 0, result.texBottom or 1)
        end
        texture:SetVertexColor(result.colorR or 1, result.colorG or 1, result.colorB or 1)
    else
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(1, 1, 1)
        Addon.Artwork.Apply(texture, result.atlas)
    end
end

local function PaintRow(row, active)
    local color = active and GOLD or WHITE
    row.name:SetTextColor(color.r, color.g, color.b, color.a)
end

function Plugin:CreateCompassSearch()
    local profiler = Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    self.compassSearchScratch, self.compassSearchResults = self:NewCompassSearchScratch(), {}
    local frame = self.frame
    local icon = CreateFrame("Button", nil, frame)
    Pixel:Enforce(icon)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    Pixel:Point(icon, "TOPLEFT", frame, "BOTTOMLEFT", 0, -ICON_GAP)
    icon:SetAlpha(ICON_ALPHA)
    icon:RegisterForClicks("LeftButtonUp")
    local iconTexture = icon:CreateTexture(nil, "ARTWORK")
    Addon.Artwork.Apply(iconTexture, SEARCH_ATLAS)
    iconTexture:SetAllPoints()

    local field = CreateFrame("EditBox", nil, frame)
    Pixel:Enforce(field)
    field:SetSize(FIELD_WIDTH, FIELD_HEIGHT)
    Pixel:Point(field, "LEFT", icon, "RIGHT", FIELD_GAP, 0)
    field:SetAutoFocus(false)
    field:SetMultiLine(false)
    field:EnableMouse(true)
    field:SetTextInsets(0, 0, 0, 0)

    local list = CreateFrame("Frame", nil, frame)
    Pixel:Enforce(list)
    list:SetWidth(LIST_WIDTH)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list:Hide()
    local status = list:CreateFontString(nil, "ARTWORK")
    status:SetJustifyH("LEFT")
    local rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, list)
        Pixel:Enforce(row)
        row:SetHeight(ROW_HEIGHT)
        Pixel:Point(row, "TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        Pixel:Point(row, "TOPRIGHT", list, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
        Pixel:Point(row.icon, "LEFT", row, "LEFT", 0, 0)
        row.name = row:CreateFontString(nil, "ARTWORK")
        row.name:SetJustifyH("LEFT")
        row.name:SetMaxLines(1)
        Pixel:Point(row.name, "LEFT", row.icon, "RIGHT", ROW_TEXT_GAP, 0)
        row.detail = row:CreateFontString(nil, "ARTWORK")
        row.detail:SetJustifyH("LEFT")
        row.detail:SetMaxLines(1)
        Pixel:Point(row.detail, "LEFT", row.name, "RIGHT", ROW_DETAIL_GAP, 0)
        Pixel:Point(row.detail, "RIGHT", row, "RIGHT", 0, 0)
        row.index = index
        row:SetScript("OnEnter", function()
            self:HighlightCompassSearchResult(self.compassSearch.offset + index)
        end)
        row:SetScript("OnClick", function()
            self:ActivateCompassSearchResult(row.result)
        end)
        row:Hide()
        rows[index] = row
    end

    self.compassSearch = {
        icon = icon,
        field = field,
        list = list,
        status = status,
        rows = rows,
        offset = 0,
        highlight = 1,
    }

    icon:SetScript("OnEnter", function()
        icon:SetAlpha(ICON_ACTIVE_ALPHA)
        Services.AnchorTooltip(GameTooltip, icon)
        GameTooltip:SetText(L.PLU_COMPASS_SEARCH, 1, 1, 1)
        GameTooltip:AddLine(L.PLU_COMPASS_SEARCH_TT, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function()
        if not field:HasFocus() then
            icon:SetAlpha(ICON_ALPHA)
        end
        if GameTooltip:IsOwned(icon) then
            Services.tooltipHide()
        end
    end)
    icon:SetScript("OnClick", function()
        if field:HasFocus() then
            self:CloseCompassSearch()
        else
            self:FocusCompassSearch()
        end
    end)
    field:SetScript("OnEditFocusGained", function()
        self:AcquireCompassLandmarkDemand(self.compassSearch, true)
        icon:SetAlpha(ICON_ACTIVE_ALPHA)
        self:RefreshCompassSearchResults()
    end)
    field:SetScript("OnEditFocusLost", function()
        if self.compassSearch.list:IsShown() then
            self:AcquireCompassLandmarkDemand(self.compassSearch, false)
        else
            self:ReleaseCompassLandmarkDemand(self.compassSearch)
        end
        if not icon:IsMouseOver() then
            icon:SetAlpha(ICON_ALPHA)
        end
    end)
    local function SearchAfterTyping(_, elapsed)
        local view = self.compassSearch
        view.typingDelay = view.typingDelay - elapsed
        if view.typingDelay <= 0 then
            self:FlushCompassSearch()
        end
    end
    field:SetScript("OnTextChanged", function()
        local view = self.compassSearch
        view.offset, view.highlight = 0, 1
        if field:GetText() == "" then
            view.typingDelay = nil
            field:SetScript("OnUpdate", nil)
            self:RefreshCompassSearchResults()
        else
            view.typingDelay = TYPING_DELAY
            field:SetScript("OnUpdate", SearchAfterTyping)
        end
    end)
    field:SetScript("OnEscapePressed", function()
        self:CloseCompassSearch()
    end)
    field:SetScript("OnEnterPressed", function()
        self:FlushCompassSearch()
        self:ActivateCompassSearchResult(self.compassSearchResults[self.compassSearch.highlight])
    end)
    field:SetScript("OnTabPressed", function()
        self:FlushCompassSearch()
        self:MoveCompassSearchHighlight(IsShiftKeyDown() and -1 or 1)
    end)
    field:SetScript("OnArrowPressed", function(_, key)
        self:FlushCompassSearch()
        if key == "UP" then
            self:MoveCompassSearchHighlight(-1)
        elseif key == "DOWN" then
            self:MoveCompassSearchHighlight(1)
        end
    end)
    list:SetScript("OnMouseWheel", function(_, delta)
        self:ScrollCompassSearch(-delta)
    end)
    local elapsedSinceRefresh = 0
    list:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRefresh = elapsedSinceRefresh + elapsed
        if elapsedSinceRefresh < REFRESH_INTERVAL then
            return
        end
        elapsedSinceRefresh = 0
        local view = self.compassSearch
        local _, revision = self:GetCompassLandmarks()
        if view.revision ~= revision or view.building ~= self:IsCompassLandmarkCatalogBuilding() then
            self:RefreshCompassSearchResults()
        end
    end)
    list:SetScript("OnEvent", function()
        if not list:IsMouseOver() and not field:IsMouseOver() and not icon:IsMouseOver() then
            self:CloseCompassSearch()
        end
    end)
    list:SetScript("OnShow", function()
        list:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    list:SetScript("OnHide", function()
        list:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    if start then
        profiler:End(self, "Compass.Search.Build", start, startKB)
    end
end

function Plugin:StyleCompassSearch()
    local view = self.compassSearch
    local font = Services.searchFont
    Services.StyleText(view.field, { font = font, textSize = NAME_FONT_SIZE, textColor = WHITE })
    Services.StyleText(view.status, { font = font, textSize = DETAIL_FONT_SIZE, textColor = DETAIL_COLOR })
    for _, row in ipairs(view.rows) do
        Services.StyleText(row.name, { font = font, textSize = NAME_FONT_SIZE, textColor = WHITE })
        Services.StyleText(row.detail, { font = font, textSize = DETAIL_FONT_SIZE, textColor = DETAIL_COLOR })
    end
    self:RefreshCompassSearchResults()
end

function Plugin:FlushCompassSearch()
    local view = self.compassSearch
    if view.typingDelay then
        view.typingDelay = nil
        view.field:SetScript("OnUpdate", nil)
        self:RefreshCompassSearchResults()
    end
end

function Plugin:FocusCompassSearch()
    local view = self.compassSearch
    if Services.IsEditMode() or not view.field:IsVisible() then
        return
    end
    local profiler = Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    view.field:SetFocus()
    view.field:HighlightText()
    if start then
        profiler:End(self, "Compass.Search.Open", start, startKB)
    end
end

function Plugin:CloseCompassSearch()
    local view = self.compassSearch
    local profiler = Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    view.typingDelay = nil
    view.field:SetScript("OnUpdate", nil)
    view.list:Hide()
    view.field:ClearFocus()
    if view.field:GetText() ~= "" then
        view.field:SetText("")
    end
    self:ReleaseCompassLandmarkDemand(view)
    if start then
        profiler:End(self, "Compass.Search.Close", start, startKB)
    end
end

function Plugin:RefreshCompassSearchButton(interactive)
    local view = self.compassSearch
    local shown = interactive and not self:IsCompassSearchHosted()
    if view.icon:IsShown() ~= shown then
        if not shown then
            self:CloseCompassSearch()
        end
        view.icon:SetShown(shown)
        view.field:SetShown(shown)
    end
    if not shown and (view.list:IsShown() or view.field:HasFocus() or view.typingDelay) then
        self:CloseCompassSearch()
    end
    local level = self.frame:GetFrameLevel() + SEARCH_LEVEL
    if view.icon:GetFrameLevel() ~= level then
        view.icon:SetFrameLevel(level)
        view.field:SetFrameLevel(level)
        view.list:SetFrameLevel(level)
    end
end

function Plugin:AnchorCompassSearchList(height)
    local view = self.compassSearch
    local list, icon = view.list, view.icon
    list:SetHeight(height)
    list:ClearAllPoints()
    local below = (icon:GetBottom() or 0) * icon:GetEffectiveScale()
    if below >= height * list:GetEffectiveScale() then
        Pixel:Point(list, "TOPLEFT", icon, "BOTTOMLEFT", 0, -LIST_GAP)
    else
        Pixel:Point(list, "BOTTOMLEFT", icon, "TOPLEFT", 0, LIST_GAP)
    end
end

function Plugin:RefreshCompassSearchResults()
    local view = self.compassSearch
    local query = view.field:GetText()
    if query == "" then
        wipe(self.compassSearchResults)
        view.list:Hide()
        if not view.field:HasFocus() then
            self:ReleaseCompassLandmarkDemand(view)
        end
        return
    end
    local _, revision = self:GetCompassLandmarks()
    view.revision, view.building = revision, self:IsCompassLandmarkCatalogBuilding()
    self:SearchCompassLandmarks(query, self.compassSearchResults, self.compassSearchScratch)
    self:RenderCompassSearchRows()
end

function Plugin:RenderCompassSearchRows()
    local profiler = Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    local view = self.compassSearch
    local results = self.compassSearchResults
    local count = #results
    view.offset = math.max(0, math.min(view.offset, count - MAX_ROWS))
    view.highlight = math.max(1, math.min(view.highlight, count))
    local shown = math.min(MAX_ROWS, count)
    for index, row in ipairs(view.rows) do
        local result = results[view.offset + index]
        row.result = result
        if result then
            SetResultIcon(row.icon, result)
            row.name:SetText(result.name)
            row.name:SetWidth(math.min(row.name:GetUnboundedStringWidth(), ROW_NAME_MAX_WIDTH))
            row.detail:SetText(result.zone or result.continent or "")
            PaintRow(row, view.offset + index == view.highlight)
            row:Show()
        else
            row:Hide()
        end
    end
    local statusText
    if count == 0 then
        statusText = view.building and L.PLU_COMPASS_SEARCH_INDEXING or L.PLU_COMPASS_SEARCH_NO_RESULTS
    end
    view.status:SetText(statusText or "")
    view.status:ClearAllPoints()
    Pixel:Point(view.status, "TOPLEFT", view.list, "TOPLEFT", 0, 0)
    view.status:SetShown(statusText ~= nil)
    self:AnchorCompassSearchList(math.max(shown, 1) * ROW_HEIGHT)
    view.list:Show()
    if start then
        profiler:End(self, "Compass.Search.Render", start, startKB)
    end
end

function Plugin:HighlightCompassSearchResult(index)
    local view = self.compassSearch
    view.highlight = index
    for rowIndex, row in ipairs(view.rows) do
        if row.result then
            PaintRow(row, view.offset + rowIndex == index)
        end
    end
end

function Plugin:MoveCompassSearchHighlight(step)
    local view = self.compassSearch
    local count = #self.compassSearchResults
    if count == 0 then
        return
    end
    local index = math.max(1, math.min(count, view.highlight + step))
    if index <= view.offset then
        view.offset = index - 1
    elseif index > view.offset + MAX_ROWS then
        view.offset = index - MAX_ROWS
    end
    view.highlight = index
    self:RenderCompassSearchRows()
end

function Plugin:ScrollCompassSearch(step)
    local view = self.compassSearch
    local count = #self.compassSearchResults
    view.offset = math.max(0, math.min(count - MAX_ROWS, view.offset + step))
    self:RenderCompassSearchRows()
end

function Plugin:ActivateCompassSearchResult(result)
    if not result then
        return
    end
    local view = self.compassSearch
    if result.kind == "continent" then
        view.field:SetText(result.name .. " ")
        view.field:SetFocus()
        return
    end
    self:CloseCompassSearch()
    local success, reason = self:ChooseCompassSearchResult(result)
    if not success then
        print(reason)
    end
end
