local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Input = Addon.CompassMarkerInput
local LeaveMarker = Input.Leave
local SetResourceStyle = Addon.CompassMarkerArt.SetResourceStyle

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
        Addon.Artwork.Apply(button.selection, C.SELECTION_MARKER_ATLAS)
        button.selection:SetRotation(0)
        button.selection:Hide()
        for _, texture in ipairs({ button.icon, button.shadow, button.symbol, button.selection }) do
            texture:SetSnapToPixelGrid(true)
            texture:SetTexelSnappingBias(0)
        end
        Input.Install(button)
        button:Hide()
        button.renderShown = false
        button.resourceMasked = false
        return button
    end, function(_, button)
        button:Hide()
        button:ClearAllPoints()
        SetResourceStyle(button, false)
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
