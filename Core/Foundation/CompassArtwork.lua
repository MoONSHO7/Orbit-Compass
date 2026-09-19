local addonName, Addon = ...
local FALLBACK_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Assets\\orbit-compass-arrow.tga"
local knownAtlases = {}
local Artwork = { fallbackTexture = FALLBACK_TEXTURE }

function Artwork.Exists(atlas)
    if type(atlas) ~= "string" or atlas == "" then
        return false
    end
    local exists = knownAtlases[atlas]
    if exists == nil then
        exists = C_Texture.GetAtlasInfo(atlas) ~= nil
        knownAtlases[atlas] = exists
    end
    return exists
end

function Artwork.Resolve(atlas)
    if Artwork.Exists(atlas) then
        return atlas
    end
    return Addon.Constants.FALLBACK_ATLAS
end

function Artwork.Apply(region, atlas, useSize)
    atlas = Artwork.Resolve(atlas)
    if Artwork.Exists(atlas) then
        region:SetAtlas(atlas, useSize)
    else
        region:SetTexture(FALLBACK_TEXTURE)
        region:SetTexCoord(0, 1, 0, 1)
    end
end

function Artwork.ApplyTexture(region, texture)
    local success = region:SetTexture(texture)
    if not success then
        Artwork.Apply(region, Addon.Constants.FALLBACK_ATLAS)
    end
    return success
end

Addon.Artwork = table.freeze(Artwork)
