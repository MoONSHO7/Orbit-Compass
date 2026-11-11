local _, Addon = ...
local C = Addon.Constants
local ICON_COLOR = { r = 1, g = 1, b = 1 }
local FULL_TEX_COORDS = { left = 0, right = 1, top = 0, bottom = 1 }
local RESOURCE_MASK_ATLAS = "CircleMaskScalable"
local RESOURCE_BORDER_ATLAS = "ChallengeMode-AffixRing-Sm"
local QUEST_BACKGROUND_ATLAS = "UI-QuestPoi-QuestNumber"

local Art = {}
Addon.CompassMarkerArt = Art

local function SetResourceStyle(button, active)
    if button.resourceMasked == active then
        return
    end
    for _, texture in ipairs({ button.icon, button.shadow }) do
        if active then
            if not texture.resourceMask then
                local mask = button:CreateMaskTexture()
                mask:SetAtlas(RESOURCE_MASK_ATLAS, false, nil, true, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(texture)
                texture.resourceMask = mask
            end
            texture:AddMaskTexture(texture.resourceMask)
        else
            texture:RemoveMaskTexture(texture.resourceMask)
        end
    end
    if active then
        if not button.resourceBorder then
            local border = button:CreateTexture(nil, "OVERLAY", nil, C.MARKER_SYMBOL_SUBLEVEL)
            border:SetAtlas(RESOURCE_BORDER_ATLAS)
            border:SetSnapToPixelGrid(true)
            border:SetTexelSnappingBias(0)
            button.resourceBorder = border
        end
        button.resourceBorder:Show()
    else
        button.resourceBorder:Hide()
    end
    button.resourceMasked = active
end

Art.SetResourceStyle = SetResourceStyle

local function MarkerArtChanged(button, marker, questSymbol)
    return button.atlas ~= marker.atlas
        or button.resourceMasked ~= (marker.kind == "resource")
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
    SetResourceStyle(button, marker.kind == "resource")
    if marker.texture then
        local valid = Addon.Artwork.ApplyTexture(button.icon, marker.texture)
        Addon.Artwork.ApplyTexture(button.shadow, marker.texture)
        if valid then
            local left, right = marker.texLeft or FULL_TEX_COORDS.left, marker.texRight or FULL_TEX_COORDS.right
            local top, bottom = marker.texTop or FULL_TEX_COORDS.top, marker.texBottom or FULL_TEX_COORDS.bottom
            button.icon:SetTexCoord(left, right, top, bottom)
            button.shadow:SetTexCoord(left, right, top, bottom)
        end
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
        Addon.Artwork.Apply(button.icon, baseAtlas, questSymbol)
        Addon.Artwork.Apply(button.shadow, baseAtlas)
        button.icon:SetVertexColor(ICON_COLOR.r, ICON_COLOR.g, ICON_COLOR.b)
        if questSymbol then
            Addon.Artwork.Apply(button.symbol, marker.atlas, true)
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

Art.QuestBackgroundAtlas = QUEST_BACKGROUND_ATLAS
Art.Changed = MarkerArtChanged
Art.Bind = BindMarkerArt

table.freeze(Art)
