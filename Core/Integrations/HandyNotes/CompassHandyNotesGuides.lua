local _, Addon = ...
local L = Addon.L
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local IsSecret = Addon.Services.IsSecret
local Guides = {}
local COORDINATE_PERCENT = 100
local DEFAULT_COLOR = table.freeze({ r = 0, g = 0.5, b = 1, a = 1 })

local function ReadTable(value)
    value = Readable(value)
    if type(value) == "table" then
        return value
    end
end

local function ReadString(value)
    value = Readable(value)
    if type(value) == "string" and value:find("%S") then
        return value
    end
end

local function ReadFunction(value)
    value = Readable(value)
    if type(value) == "function" then
        return value
    end
end

local function ReadComponent(value, default)
    if IsSecret(value) then
        return
    elseif value == nil then
        return default
    end
    value = Number(value)
    if value and value >= 0 and value <= 1 then
        return value
    end
end

local function IsDiscrete(poi)
    local class = ReadTable(poi.__class)
    local seen = {}
    while class and not seen[class] do
        seen[class] = true
        local parent = class.__parent
        if IsSecret(parent) then
            return false
        elseif parent == nil then
            local render, draw = ReadFunction(class.Render), ReadFunction(class.Draw)
            return render ~= nil
                and draw ~= nil
                and ReadFunction(poi.Render) == render
                and ReadFunction(poi.Draw) == draw
        end
        class = ReadTable(parent)
    end
    return false
end

local function ReadStyle(poi, profile, circleTexture)
    local icon, color = poi.icon, poi.color
    if IsSecret(icon) or IsSecret(color) then
        return
    end
    if icon then
        icon = Number(icon)
        if icon and icon > 0 and icon % 1 == 0 then
            return icon, 1, 1, 1, 1
        end
        return
    end
    local red = ReadComponent(profile and profile.poi_color_R, DEFAULT_COLOR.r)
    local green = ReadComponent(profile and profile.poi_color_G, DEFAULT_COLOR.g)
    local blue = ReadComponent(profile and profile.poi_color_B, DEFAULT_COLOR.b)
    local alpha = ReadComponent(profile and profile.poi_color_A, DEFAULT_COLOR.a)
    if color then
        if not ReadString(color) then
            return
        end
        red, green, blue = ReadComponent(poi.r), ReadComponent(poi.g), ReadComponent(poi.b)
    end
    if red and green and blue and alpha and alpha > 0 then
        return circleTexture, red, green, blue, alpha
    end
end

function Guides:Read(action, parentName, parentDescription)
    local records, seen, pending = {}, {}, false
    action = ReadTable(action)
    local provider = action and Addon.HandyNotesZarillion:Get(action.providerName)
    if not provider then
        return records, pending
    end
    local addon, handler, node = ReadTable(action.addon), ReadTable(action.handler), ReadTable(action.node)
    local mapID, parentCoord = Number(action.mapID), Number(action.coord)
    if not addon or not handler or not node or not mapID or mapID <= 0 or mapID % 1 ~= 0 then
        return records, pending
    end
    if not parentCoord or parentCoord < 0 or parentCoord % 1 ~= 0 then
        return records, pending
    end
    local getXY, pois = ReadFunction(addon.getXY), ReadTable(node.pois)
    if not getXY or not pois then
        return records, pending
    end
    local database = ReadTable(handler.db)
    local profile = database and ReadTable(database.profile)
    if not profile then
        return records, pending
    end
    parentName = ReadString(parentName) or provider.name
    parentDescription = ReadString(parentDescription)
    for poiIndex, value in ipairs(pois) do
        local poi = ReadTable(value)
        local isEnabled = poi and ReadFunction(poi.IsEnabled)
        if poi and IsDiscrete(poi) and isEnabled and Readable(isEnabled(poi)) == true then
            local texture, red, green, blue, alpha = ReadStyle(poi, profile, provider.circleTexture)
            if texture then
                local name, description, incomplete = Addon.HandyNotesText:Read(poi, provider)
                pending = pending or incomplete
                for _, value in ipairs(poi) do
                    local coord = Number(value)
                    if coord and coord >= 0 and coord % 1 == 0 then
                        local x, y = getXY(addon, coord)
                        x, y = Number(x), Number(y)
                        if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                            local key = "handynotes-guide:"
                                .. provider.name
                                .. ":"
                                .. mapID
                                .. ":"
                                .. parentCoord
                                .. ":"
                                .. poiIndex
                                .. ":"
                                .. coord
                            if not seen[key] then
                                seen[key] = true
                                records[#records + 1] = {
                                    key = key,
                                    mapID = mapID,
                                    x = x,
                                    y = y,
                                    name = name
                                        or L.PLU_COMPASS_HANDYNOTES_POINT_F:format(
                                            parentName,
                                            x * COORDINATE_PERCENT,
                                            y * COORDINATE_PERCENT
                                        ),
                                    description = parentDescription or description,
                                    texture = texture,
                                    texLeft = 0,
                                    texRight = 1,
                                    texTop = 0,
                                    texBottom = 1,
                                    colorR = red,
                                    colorG = green,
                                    colorB = blue,
                                    sourceAlpha = alpha,
                                    sizeScale = 1,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return records, pending
end

Addon.HandyNotesGuides = table.freeze(Guides)
