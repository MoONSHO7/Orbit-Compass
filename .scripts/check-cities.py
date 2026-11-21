"""Check Compass city grouping in Lua 5.1 through the shipped Discovery, Sources, Bearings and menu owners."""

from compass_harness import client, load_modules

MODULES = (
    "Foundation/CompassMath.lua",
    "Discovery/CompassSources.lua",
    "Navigation/CompassBearings.lua",
    "Navigation/CompassPointMenu.lua",
)

# A 1000-yard zone (map 3) on continent 42 with Ironforge (Forever 1455, Retail 87) projecting to x 0.4-0.5, y 0.3-0.4.
SETUP = r'''
mock.cityMap = Addon.ClientFeatures.family == "retail" and 87 or 1455
mock.maps[mock.cityMap] = { mapID=mock.cityMap, mapType=3, parentMapID=2, name="Ironforge" }
mock.worldRects = { [mock.cityMap] = { 400, 500, 300, 400 } }
-- Real towns stay on another continent unless a scenario places their zone over map 3.
function Town(area)
 for _, town in ipairs(Addon.CompassTownCatalog[Addon.ClientFeatures.family]) do
  if town.area == area then mock.worldRects[town.map] = { 0, 1000, 0, 1000 }; return town end
 end
end
mock.areaNames = { [159] = "Brill", [35] = "Booty Bay" }
C_Map.GetAreaInfo = function(area) return mock.areaNames[area] or ("Area " .. area) end
mock.worldReads = 0
C_Map.GetWorldPosFromMapPos = function(id, p)
 mock.worldReads = mock.worldReads + 1
 local r = mock.worldRects[id]
 if r then return 42, { x = r[1] + p.x * (r[2] - r[1]), y = r[3] + p.y * (r[4] - r[3]) } end
 return id == 3 and 42 or 99, { x = p.x * 1000, y = p.y * 1000 }
end
C_Map.GetMapPosFromWorldPos = function(_, world, override) return override, { x = world.x / 1000, y = world.y / 1000 } end
C_Map.GetUserWaypoint = function() return nil end
UIParent = { GetEffectiveScale = function() return 1 end }
Addon.Services.pixel = { Snap = function(_, v) return v end }
Addon.L.PLU_COMPASS_DETAIL_F = "%s - %s"
MenuUtil = { CreateContextMenu = function(_, build)
 mock.menu = { titles = {}, buttons = {} }
 local root = { CreateTitle = function(_, t) mock.menu.titles[#mock.menu.titles + 1] = t end,
  SetScrollMode = function() end,
  CreateButton = function(_, label, fn) mock.menu.buttons[#mock.menu.buttons + 1] = { label = label, fn = fn }
   return { AddInitializer = function() end } end }
 build(nil, root)
end }
function P:ReadCompassPosition() return mock.px, mock.py end
function P:FormatCompassDistance(d) return tostring(math.floor(d + 0.5)) end
P.bearings, P.markerSlots, P.sortElapsed, P.bearingNextRefresh = {}, {}, 0, 0
P.markerClock, P.selectionKeys = 0, {}
C = Addon.Constants
P.frame = {}
mock.px, mock.py = 0.45, 0.65
function Marker(key, x, y, kind)
 return { key=key, x=x, y=y, name=key, atlas="test", sizeScale=1, priority=6, kind=kind or "service",
  destination={ mapID=3, x=x, y=y } }
end
function Publish(markers)
 for _, source in pairs(P.compassSources) do wipe(source.markers) end
 for _, marker in ipairs(markers) do P.compassSources.map.markers[#P.compassSources.map.markers + 1] = marker end
 P:RebuildCompassMarkers()
 P.discoveryClock = P.discoveryClock + 1
 P:RefreshCompassBearings()
end
function Shown()
 local keys = {}
 for _, marker in ipairs(P.bearings) do keys[#keys + 1] = marker.key end
 table.sort(keys)
 return table.concat(keys, ",")
end
-- Lets a fold transition finish and reorders, as the render does once the last frame settles.
function Settle()
 P.markerClock = P.markerClock + 1
 P.bearingsDirty = true
 P.discoveryClock = P.discoveryClock + 1
 P:RefreshCompassBearings()
end
function Area(mapID)
 mock.playerMap = mapID
 P:RefreshCompassPointArea(mapID)
 P.discoveryClock = P.discoveryClock + 1
 P:RefreshCompassBearings()
end
function Enter(mapID) Area(mapID); Settle() end
-- Projects the ribbon with the place icon at x 0 and its points at x 100, then applies the fold blend.
function Blend()
 local selection, byKey = {}, {}
 wipe(P.selectionKeys)
 for _, marker in ipairs(P.bearings) do
  marker.projectedX, marker.projectedAlpha = marker.kind == "city" and 0 or 100, 1
  selection[#selection + 1], byKey[marker.key], P.selectionKeys[marker.key] = marker, marker, true
 end
 P:BlendCompassCityFolds(selection)
 return byKey
end
function Near(a, b) return math.abs(a - b) < 1e-9 end
-- Places a town's zone at real scale (a 33.3-yard terrain chunk) on map 3; At gives a chunk centre in map 3.
function TownAtScale(area)
 local town, place = Town(area)
 for _, candidate in ipairs(Addon.CompassCityCatalog.places) do if candidate.areaID == area then place = candidate end end
 local left, top, right, bottom = unpack(town.rect)
 local width, height = place.columns * 1600 / 48 / (right - left), place.rows * 1600 / 48 / (bottom - top)
 mock.worldRects[town.map] = { 0, width, 0, height }
 return function(column, row)
  return (left + (column + 0.5) / place.columns * (right - left)) * width / 1000,
   (top + (row + 0.5) / place.rows * (bottom - top)) * height / 1000
 end
end
function Walk(px, py)
 mock.px, mock.py = px, py
 P.discoveryClock = P.discoveryClock + 1
 P:RefreshCompassBearings()
 Settle()
end
function BrillPoints()
 local brill = Town(159)
 local x, y = (brill.rect[1] + brill.rect[3]) / 2, (brill.rect[2] + brill.rect[4]) / 2
 mock.px, mock.py = 0.02, 0.02
 Publish({ Marker("inn", x, y), Marker("vendor", x + 0.001, y) })
 return brill
end
P:RefreshCompassPointArea(3)
-- Places also stand alone within their own range; most scenarios keep it below the distances they use.
P:SetCompassPointRange("ShowPlaces", C.RANGE_MIN)
P:CacheCompassRanges()
'''

CITY_POINTS = 'Publish({ Marker("bank",0.45,0.35), Marker("mail",0.42,0.32), Marker("inn",0.48,0.38), Marker("farm",0.2,0.8) })'

# Ribbon owners load after these doubles, since they capture the pixel service when their file runs.
RIBBON = r'''
Addon.Services.pixel = { Snap = function(_, v) return v end, Multiple = function(_, v) return v end,
 ToCount = function(_, v) return v end }
P.iconSize = 20
P.artworkLayout = { scale = 1, centerX = 0, centerY = 384, labelY = -30, markerY = 2 }
UIParent = { GetEffectiveScale = function() return 1 end, GetHeight = function() return 768 end }
P.markerGroupOrder, P.markerGroups, P.markerLeftOrder, P.markerGroupMembers = {}, {}, {}, {}
function FontString()
 local text = { alpha = 1, shown = false }
 function text:SetMaxLines() end
 function text:SetJustifyH(value) self.justify = value end
 function text:SetText(value) self.text = value end
 function text:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end
 function text:SetAlpha(value) self.alpha = value end
 function text:SetFontObject(name) self.fontObject, self.r, self.g, self.b, self.justify = name, 1, 0.82, 0, nil end
 function text:ClearAllPoints() self.point = nil end
 function text:SetPoint(point, _, _, x, y) self.point, self.x, self.y = point, x, y end
 function text:Show() self.shown = true end
 function text:SetShown(value) self.shown = value == true end
 function text:Hide() self.shown = false end
 function text:GetUnboundedStringWidth() return #(self.text or "") * 8 end
 function text:GetFont() return self.fontPath or "object", 16, "" end
 function text:SetFont(path, height, flags) self.fontPath, self.fontHeight, self.fontFlags = path, height, flags end
 function text:GetStringHeight() return 16 end
 return text
end
function Texture()
 local texture = FontString()
 function texture:SetAtlas(name) self.atlas = name end
 function texture:SetDesaturated(value) self.desaturated = value end
 function texture:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
 function texture:SetSize(width, height) self.width, self.height = width, height end
 function texture:SetWidth(width) self.width = width end
 return texture
end
P.frame = { CreateFontString = FontString, CreateTexture = Texture }
function P:CompassDisplayDistance(yards) return math.floor(yards + 0.5) end
P.distanceUnits, P.placeNameMode = "yards", "below"
'''
RIBBON_MODULES = ("Ribbon/Markers/CompassMarkerGroups.lua", "Ribbon/CompassPlaceLabel.lua")

SCENARIOS = [
    ("outside a city its points fold into one city marker", f'''
{CITY_POINTS}
local city = "city:" .. mock.cityMap
assert(Shown() == city .. ",farm", Shown())
local marker = P.bearings[1].kind == "city" and P.bearings[1] or P.bearings[2]
assert(marker.name == "Ironforge" and marker.bearing and marker.distance)
assert(marker.texture:find("Assets\\\\Cities\\\\ironforge.tga", 1, true), marker.texture)
assert(math.abs(marker.x - 0.45) < 1e-9 and math.abs(marker.y - 0.35) < 1e-9)
assert(marker.textureFilter == "TRILINEAR" and marker.sizeScale > 1)
'''),
    ("inside the city every point shows on its own", f'''
{CITY_POINTS}
Enter(mock.cityMap)
assert(Shown() == "bank,farm,inn,mail", Shown())
Enter(3)
assert(Shown() == "city:" .. mock.cityMap .. ",farm", Shown())
'''),
    ("a child floor of the city counts as inside", f'''
mock.maps[9001] = {{ mapID=9001, mapType=6, parentMapID=mock.cityMap, name="Lower Level" }}
{CITY_POINTS}
Enter(9001)
assert(Shown() == "bank,farm,inn,mail", Shown())
'''),
    ("the current destination keeps its own icon", f'''
{CITY_POINTS}
local select = P.SelectCompassNavigation
function P:SelectCompassNavigation() select(self); self.navigationKey = "bank" end
Publish({{ Marker("bank",0.45,0.35), Marker("mail",0.42,0.32), Marker("farm",0.2,0.8) }})
assert(Shown() == "bank,city:" .. mock.cityMap .. ",farm", Shown())
'''),
    ("waypoints and route steps are never folded", '''
local waypoint, step = Marker("waypoint",0.46,0.36,"waypoint"), Marker("step",0.47,0.37,"route")
waypoint.priority = 1
Publish({ waypoint, step, Marker("mail",0.42,0.32) })
assert(Shown() == "city:" .. mock.cityMap .. ",step,waypoint", Shown())
'''),
    ("members out of range raise no city marker", '''
P.range = 250
P.compassPointRanges = {}
mock.px, mock.py = 0.45, 0.95
Publish({ Marker("bank",0.45,0.35), Marker("farm",0.4,0.9) })
assert(Shown() == "farm", Shown())
'''),
    ("the city menu lists the city first, then its points by distance", f'''
{CITY_POINTS}
local city
for _, marker in ipairs(P.bearings) do if marker.kind == "city" then city = marker end end
local points = P:CollectCompassCityPoints(city)
assert(#points == 3 and points[1].key == "inn" and points[2].key == "bank" and points[3].key == "mail")
P:ShowCompassCityMenu(city)
assert(mock.menu.titles[1] == "Ironforge", tostring(mock.menu.titles[1]))
assert(#mock.menu.buttons == 4 and mock.menu.buttons[1].label:find("Ironforge", 1, true))
mock.menu.buttons[3].fn()
assert(mock.waypoint and math.abs(mock.waypoint.position.x - 0.45) < 1e-9, "choosing a point sets its waypoint")
'''),
    ("city bounds are read once per map and markers are matched once per position", f'''
{CITY_POINTS}
local reads = mock.worldReads
Publish({{ Marker("bank",0.45,0.35), Marker("mail",0.42,0.32), Marker("farm",0.2,0.8) }})
assert(mock.worldReads == reads, "unchanged map re-read city bounds")
local moved = Marker("bank",0.45,0.35)
Publish({{ moved }})
moved.x = 0.1
Publish({{ moved }})
assert(Shown() == "bank", Shown())
P:InitializeCompassDiscovery()
Publish({{ Marker("mail",0.42,0.32) }})
assert(mock.worldReads > reads, "a discovery context reset rebuilds city bounds")
'''),
    ("entering or leaving a city reorders the ribbon", f'''
{CITY_POINTS}
P.bearingsDirty = false
P:RefreshCompassCityArea(mock.cityMap)
assert(P.bearingsDirty, "entering did not dirty the ribbon")
P.bearingsDirty = false
P:RefreshCompassCityArea(mock.cityMap)
assert(not P.bearingsDirty, "an unchanged city dirtied the ribbon")
'''),
    ("towns fold into their own icon: Horde huts, goblin towns a goblin, other towns the town icon", '''
local brill, bay = Town(159), Town(35)
local function Centre(town) return (town.rect[1] + town.rect[3]) / 2, (town.rect[2] + town.rect[4]) / 2 end
local bx, by = Centre(brill)
local gx, gy = Centre(bay)
mock.px, mock.py = 0.02, 0.02
Publish({ Marker("inn", bx, by), Marker("vendor", bx + 0.001, by), Marker("bank", gx, gy) })
assert(Shown() == "town:159,town:35", Shown())
local art = { ["town:159"] = "horde.tga", ["town:35"] = "goblin.tga" }
for _, marker in ipairs(P.bearings) do
 assert(marker.texture:find(art[marker.key], 1, true), marker.key .. " " .. marker.texture)
 assert(marker.name == (marker.key == "town:35" and "Booty Bay" or "Brill"), marker.name)
end
local alliance = 0
for _, place in ipairs(Addon.CompassCityCatalog.places) do
 if place.areaID then
  local icon = place.texture:match("(%a+)%.tga$")
  assert(icon == "goblin" or (icon == "horde") == (place.faction == "Horde"), place.areaID .. " " .. icon)
  if place.faction == "Alliance" then alliance = alliance + 1 assert(icon == "town", place.areaID .. " " .. icon) end
 end
end
assert(alliance > 0, "Alliance towns keep the town icon")
'''),
    ("the client's subzone name places the player inside a town", '''
local brill = Town(159)
local x, y = (brill.rect[1] + brill.rect[3]) / 2, (brill.rect[2] + brill.rect[4]) / 2
mock.px, mock.py = 0.02, 0.02
Publish({ Marker("inn", x, y), Marker("vendor", x + 0.001, y) })
assert(Shown() == "town:159", Shown())
mock.subzone = "Brill"
Enter(3)
assert(Shown() == "inn,vendor", Shown())
mock.subzone = "Gallows' End Tavern"
Enter(3)
assert(Shown() == "town:159", Shown())
'''),
    ("standing inside a town's bounds counts as inside, with a margin on the way out", '''
mock.worldRects[mock.cityMap] = nil
local brill = Town(159)
local left, top, right, bottom = unpack(brill.rect)
local x, y = (left + right) / 2, (top + bottom) / 2
mock.px, mock.py = 0.02, 0.02
Publish({ Marker("inn", x, y) })
local function Walk(px, py)
 mock.px, mock.py = px, py
 P.discoveryClock = P.discoveryClock + 1
 P:RefreshCompassBearings()
 Settle()
end
Walk(x, y + 0.01)
assert(Shown() == "inn", "inside the bounds: " .. Shown())
Walk(right + 0.01, y + 0.01)
assert(Shown() == "inn", "inside the exit margin: " .. Shown())
Walk(right + 0.05, y + 0.01)
assert(Shown() == "town:159", "past the exit margin: " .. Shown())
Walk(right + 0.01, y + 0.01)
assert(Shown() == "town:159", "re-entry needs the bounds themselves: " .. Shown())
'''),
    ("a town's terrain outline, not its rectangle, decides which points it holds and where it starts", '''
local At = TownAtScale(976)
mock.px, mock.py = At(6, 40)
Publish({ Marker("corner", At(1, 0)), Marker("bank", At(6, 6)) })
assert(Shown() == "corner,town:976", "only points on the outline fold: " .. Shown())
Walk(At(2, 1))
assert(Shown() == "corner,town:976", "the rectangle's empty corner is outside the town: " .. Shown())
Walk(At(7, 7))
assert(Shown() == "bank,corner", "on the outline: " .. Shown())
'''),
    ("past a town's outline and exit margin it stays folded, even where its map overlay reached", '''
local At = TownAtScale(976)
mock.px, mock.py = At(6, 40)
Publish({ Marker("bank", At(6, 6)), Marker("inn", At(8, 8)) })
Walk(At(6, 12))
assert(Shown() == "bank,inn", "on the outline's last row: " .. Shown())
Walk(At(6, 12.8))
assert(Shown() == "bank,inn", "10 yards out, inside the exit margin: " .. Shown())
Walk(At(6, 14.3))
assert(Shown() == "town:976", "60 yards out: " .. Shown())
Walk(At(6, 12.8))
assert(Shown() == "town:976", "re-entry needs the outline itself: " .. Shown())
'''),
    ("entering a town fades its icon out while its points glide out of it", '''
BrillPoints()
assert(Shown() == "town:159", Shown())
mock.subzone = "Brill"
Area(3)
assert(Shown() == "inn,town:159,vendor", "both sides show while it unfolds: " .. Shown())
P.markerClock = P.markerClock + C.CITY_FOLD_SECONDS / 2
local shown = Blend()
local city, inn = shown["town:159"], shown.inn
assert(Near(city.projectedAlpha, 0.5) and Near(inn.projectedAlpha, 0.5), city.projectedAlpha .. " " .. inn.projectedAlpha)
assert(inn.projectedX > 50 and inn.projectedX < 100, "points glide out from the icon: " .. inn.projectedX)
assert(city.projectedRetiring and not inn.projectedRetiring and inn.projectedMoving and P.compassCityFoldAnimating)
P.markerClock = P.markerClock + C.CITY_FOLD_SECONDS
shown = Blend()
assert(shown["town:159"].projectedAlpha == 0 and shown.inn.projectedX == 100 and not P.compassCityFoldAnimating)
P.bearingsDirty = false
P:RefreshCompassBearings()
assert(Shown() == "inn,vendor", "a settled fold reorders by itself: " .. Shown())
'''),
    ("leaving folds points back in, and turning round mid-way continues from where it was", '''
BrillPoints()
mock.subzone = "Brill"
Enter(3)
assert(Shown() == "inn,vendor", Shown())
mock.subzone = "Tirisfal Glades"
Area(3)
assert(Shown() == "inn,town:159,vendor", "both sides show while it folds: " .. Shown())
P.markerClock = P.markerClock + C.CITY_FOLD_SECONDS / 3
local shown = Blend()
assert(Near(shown.inn.projectedAlpha, 2 / 3) and shown.inn.projectedRetiring, shown.inn.projectedAlpha)
mock.subzone = "Brill"
Area(3)
shown = Blend()
assert(Near(shown.inn.projectedAlpha, 2 / 3) and not shown.inn.projectedRetiring, "reversal jumped")
P.markerClock = P.markerClock + C.CITY_FOLD_SECONDS / 3
shown = Blend()
assert(Near(shown.inn.projectedAlpha, 1) and not P.compassCityFoldAnimating, shown.inn.projectedAlpha)
'''),
    ("a place first seen, or out of view for an ordering, snaps without animating", '''
mock.subzone = "Brill"
P:RefreshCompassPointArea(3)
BrillPoints()
assert(Shown() == "inn,vendor", "first sight: " .. Shown())
-- An ordering on a map without the place (another continent) breaks its continuity.
P.compassCityFoldRevision = P.compassCityFoldRevision + 1
mock.subzone = "Tirisfal Glades"
Area(3)
assert(Shown() == "town:159", "after a gap: " .. Shown())
'''),
    ("an enemy place drops its own entry and shows its name in red", f'''
mock.faction = "Horde"
{CITY_POINTS}
local city
for _, marker in ipairs(P.bearings) do if marker.kind == "city" then city = marker end end
assert(P:IsCompassPlaceHostile(city))
P:ShowCompassCityMenu(city)
assert(mock.menu.titles[1] == "|cffff2020Ironforge|r", tostring(mock.menu.titles[1]))
assert(#mock.menu.buttons == 3 and not mock.menu.buttons[1].label:find("Ironforge", 1, true))
mock.faction = "Alliance"
assert(not P:IsCompassPlaceHostile(city))
'''),
    ("towns take their flight masters' faction, else their zone's; goblin towns stay neutral", '''
local brill, goldshire, bay, ratchet = Town(159), Town(87), Town(35), Town(392)
assert(brill.faction == "Horde" and goldshire.faction == "Alliance", "zone faction")
assert(bay.faction == nil and ratchet.faction == nil, "goblin towns")
for _, place in ipairs(Addon.CompassCityCatalog.places) do
 if place.areaID == 159 then assert(place.faction == "Horde") end
end
'''),
    ("walking in and out of a town rebuilds no bounds and re-stamps no points", '''
mock.counts = {}
Addon.Services.profiler = { active = true, Begin = function() return 0, 0 end, End = function() end,
 Count = function(_, _, label, amount) mock.counts[label] = (mock.counts[label] or 0) + (amount or 1) end }
BrillPoints()
for _ = 1, 3 do
 mock.subzone = "Brill"
 Enter(3)
 assert(Shown() == "inn,vendor", Shown())
 mock.subzone = "Tirisfal Glades"
 Enter(3)
 assert(Shown() == "town:159", Shown())
end
Publish({ P.markers[1], P.markers[2] })
assert(mock.counts["Cities/Bounds"] == 1, "bounds built " .. tostring(mock.counts["Cities/Bounds"]))
assert(mock.counts["Cities/Stamped"] == 2, "points stamped " .. tostring(mock.counts["Cities/Stamped"]))
assert(mock.counts["Cities/FoldStarted"] == 6, "transitions " .. tostring(mock.counts["Cities/FoldStarted"]))
'''),
    ("Cities & Towns off hides place icons and leaves their points unfolded", f'''
{CITY_POINTS}
assert(Shown() == "city:" .. mock.cityMap .. ",farm", Shown())
P.waypointDirty, P.bearingsDirty = false, false
P:SetCompassPointVisibility("ShowPlaces", "world", false)
P:CacheCompassPointVisibility()
assert(P.showPlaces == false and P.bearingsDirty and not P.waypointDirty, "only the ribbon order is redone")
Settle()
assert(Shown() == "bank,farm,inn,mail", "unfolded: " .. Shown())
P:SetCompassPointVisibility("ShowPlaces", "world", true)
P:CacheCompassPointVisibility()
Settle()
assert(Shown() == "city:" .. mock.cityMap .. ",farm", "folded again: " .. Shown())
'''),
    ("inside a capital, towns stay off the ribbon: neither their icon nor the points folded into it", '''
P:SetCompassPointRange("ShowPlaces", C.RANGE_MAX)
P:CacheCompassRanges()
BrillPoints()
assert(Shown():find("town:159", 1, true), "outside every city: " .. Shown())
Enter(mock.cityMap)
local shown = Shown()
assert(not shown:find("town:159", 1, true) and not shown:find("inn", 1, true) and not shown:find("vendor", 1, true),
 "inside a capital: " .. shown)
Enter(3)
assert(Shown():find("town:159", 1, true), "back outside: " .. Shown())
'''),
    ("a place within its own range shows alone, with none of its points on the ribbon", '''
Publish({ Marker("farm", 0.2, 0.8) })
assert(Shown() == "farm", "300 yards away, past a 250-yard range: " .. Shown())
P:SetCompassPointRange("ShowPlaces", 400)
P:CacheCompassRanges()
Settle()
assert(Shown() == "city:" .. mock.cityMap .. ",farm", "inside a 400-yard range: " .. Shown())
Enter(mock.cityMap)
assert(Shown() == "farm", "never while inside it: " .. Shown())
'''),
    ("icons shrink across each point type's own range, and town icons at half that rate", '''
local function Size(kind, distance, point)
 local marker = { key = kind .. distance, kind = kind, point = point, sizeScale = 1, distance = distance,
  distanceSquared = distance * distance, projectedX = 0, cityRegion = kind == "city" and {} or nil }
 P:LayoutCompassMarkerGroups({ marker })
 return marker.projectedIconSize
end
local near, far = P.iconSize * C.MARKER_NEAR_SCALE, P.iconSize * C.MARKER_FAR_SCALE
local middle = (near + far) / 2
P.range, P.compassPointRanges = C.RANGE_MAX, { ShowPlaces = C.RANGE_MAX, ShowServices = 1000 }
local edge = C.RANGE_MAX
local halfway = C.MARKER_NEAR_DISTANCE + (edge - C.MARKER_NEAR_DISTANCE) / 2
assert(Near(Size("service", C.MARKER_NEAR_DISTANCE), near) and Near(Size("city", 100, "ShowPlaces"), near), "close")
assert(Near(Size("poi", halfway), middle) and Near(Size("poi", edge), far), "Marker Range stretches the curve")
assert(Near(Size("service", 1000, "ShowServices"), far), "a row's own range sets its far end")
assert(Near(Size("city", edge, "ShowPlaces"), middle), "a town at its range edge has shrunk half as far")
local twice = C.MARKER_NEAR_DISTANCE + 2 * (edge - C.MARKER_NEAR_DISTANCE)
assert(Near(Size("city", twice, "ShowPlaces"), far) and Near(Size("city", twice * 2, "ShowPlaces"), far), "floor")
''', RIBBON_MODULES),
    ("facing a place names it under the ribbon, fading in and out; other points never", '''
P:CreateCompassPlaceLabel()
local label = P.compassPlaceLabel
local region = { left = 0.4, right = 0.5, top = 0.3, bottom = 0.4, place = {} }
local town = { key = "town:1", kind = "city", name = "Brill", cityRegion = region, renderShown = true,
 distance = 500, projectedDelta = 2 }
local inn = { key = "inn", kind = "service", name = "Inn", renderShown = true, distance = 100, projectedDelta = 0 }
local function Frame(seconds, ...)
 P.markerClock = P.markerClock + seconds
 return P:RenderCompassPlaceLabel(P:FindCompassFacedPlace({ ... }))
end
assert(not Frame(0, inn) and not label.text.shown, "another point never gets the label")
assert(Frame(0, inn, town) == true, "below, the faced place holds Show Label's line from its first frame")
assert(label.text.text == "Brill" and label.alpha == 0 and P.compassPlaceLabelAnimating, "facing starts the fade")
assert(Near(label.text.r, 1) and Near(label.text.b, 0), "a friendly or neutral place is gold")
Frame(0.1, inn, town)
assert(Near(label.alpha, 0.5) and label.text.shown and label.text.y > -46, "half-way and still sliding in")
local smoke, distance = label.smoke, label.distance
assert(distance.text == "500" and distance.shown and Near(distance.alpha, 0.5), "its distance fades in underneath")
assert(smoke.atlas == "BonusChest-OrangeSmoke-Wide" and smoke.desaturated and smoke.r < 0.2, "darkened Blizzard smoke")
assert(smoke.shown and Near(smoke.alpha, 0.5 * 0.6) and smoke.width >= 110, "fades with the name")
Frame(0.2, inn, town)
assert(label.alpha == 1 and label.text.y == -46 and not P.compassPlaceLabelAnimating, "settled 16 below the line")
town.distance = 420
Frame(0, inn, town)
assert(distance.text == "420", "the distance follows the player")
town.distance = 500
town.projectedDelta = 6
Frame(5, inn, town)
assert(label.alpha == 1 and P.compassPlaceLabelAnimating, "past its half-width it fades, from that frame")
Frame(0.1, inn, town)
assert(Near(label.alpha, 0.5), "half-way out: " .. label.alpha)
Frame(0.2, inn, town)
assert(label.alpha == 0 and not label.text.shown and not P.compassPlaceLabelAnimating, "gone")
assert(not smoke.shown and not distance.shown, "the smoke and distance leave with the name")
local enemy = { key = "city:1", kind = "city", name = "Orgrimmar", renderShown = true, distance = 150,
 projectedDelta = 10, cityRegion = { left = 0.4, right = 0.5, top = 0.3, bottom = 0.4, place = { faction = "Horde" } } }
Frame(0, inn, enemy)
assert(label.text.text == "Orgrimmar" and Near(label.text.g, 0.125), "near, its half-width covers 10 degrees; enemy red")
P:StyleCompassPlaceLabel(nil)
assert(Near(label.text.g, 0.125) and label.text.justify == "CENTER", "a restyle keeps the enemy red and the centring")
enemy.projectedRetiring = true
Frame(0.1, inn, enemy)
assert(label.alpha == 0 and not P.compassPlaceLabelAnimating, "a place being entered is not named")
''', RIBBON_MODULES),
    ("Place Names sets the title above or below the ribbon, its distance underneath in Blizzard's small text", '''
P:CreateCompassPlaceLabel()
local label = P.compassPlaceLabel
local text, distance = label.text, label.distance
assert(text.fontObject == "GameFontNormalLarge" and distance.fontObject == "GameFontHighlightSmall")
local town = { key = "town:1", kind = "city", name = "Brill", renderShown = true, distance = 500, projectedDelta = 0,
 cityRegion = { left = 0.4, right = 0.5, top = 0.3, bottom = 0.4, place = {} } }
local function Frame(seconds, peeking)
 P.markerClock = P.markerClock + seconds
 return P:RenderCompassPlaceLabel(P:FindCompassFacedPlace({ town }), peeking)
end
P.placeNameMode = "above"
P.artworkLayout.centerY = 100
Frame(0, true)
Frame(0.1, true)
local rest = 2 + P.iconSize * C.MARKER_NEAR_SCALE * C.CITY_MARKER_SCALE / 2 + C.MARKER_OUTLINE + 20
assert(distance.point == "BOTTOM" and distance.y < rest, "rising out of the ribbon: " .. distance.y)
assert(text.point == "BOTTOM" and text.y > 0, "the name sits on top of its distance")
Frame(0.2, true)
assert(label.alpha == 1 and Near(distance.y, rest), "above it wherever the ribbon is, clear of a town icon, despite Alt")
assert(Frame(0, false) == false, "above, Show Label keeps its line")
P.placeNameMode = "below"
P.artworkLayout.centerY = 600
assert(Frame(0, false) == true and text.point == "TOP" and text.y == -46, "below wherever the ribbon is")
assert(distance.point == "TOP" and distance.y < 0, "the distance under the name")
Frame(0, true)
Frame(0.3, true)
assert(label.alpha == 0, "below, Alt's callout takes the line")
P.artworkLayout.centerY = 10
Frame(0, false)
Frame(0.3, false)
assert(label.alpha == 1 and text.y - label.height >= -10, "at the screen's bottom edge it stays on screen: " .. text.y)
P.placeNameMode = "above"
P.artworkLayout.centerY = 760
Frame(0, false)
assert(distance.y + label.height <= 768 - 760, "at the screen's top edge it stays on screen: " .. distance.y)
''', RIBBON_MODULES),
    ("Compass's font override swaps the title's face and keeps Blizzard's size; clearing it restores the object", '''
Addon.Services.FontPath = function(name) return "path:" .. name end
P:CreateCompassPlaceLabel()
local text, distance = P.compassPlaceLabel.text, P.compassPlaceLabel.distance
P:StyleCompassPlaceLabel("Blizzard")
assert(text.fontObject == "GameFontNormalLarge" and text.fontPath == "path:Blizzard" and text.fontHeight == 16)
assert(distance.fontObject == "GameFontHighlightSmall" and distance.fontPath == "path:Blizzard", "both lines")
text.fontPath = nil
P:StyleCompassPlaceLabel(nil)
assert(text.fontObject == "GameFontNormalLarge" and text.fontPath == nil, "no override, Blizzard's own text")
''', RIBBON_MODULES),
    ("a fold settling off screen still drops the side that faded out", '''
BrillPoints()
mock.subzone = "Brill"
Area(3)
assert(Shown() == "inn,town:159,vendor", Shown())
P.markerClock = P.markerClock + C.CITY_FOLD_SECONDS / 2
P.bearingsDirty = false
P:RefreshCompassBearings()
assert(Shown() == "inn,town:159,vendor", "still unfolding: " .. Shown())
P.markerClock = P.markerClock + C.CITY_FOLD_SECONDS
P:RefreshCompassBearings()
assert(Shown() == "inn,vendor" and P.compassFoldSettlesAt == nil, "settled without a frame drawn: " .. Shown())
'''),
    ("points glide from their place icon even once it leaves the selection", '''
BrillPoints()
mock.subzone = "Brill"
Area(3)
P.markerClock = P.markerClock + C.CITY_FOLD_SECONDS / 2
local inn, town
for _, marker in ipairs(P.bearings) do
 if marker.key == "inn" then inn = marker elseif marker.key == "town:159" then town = marker end
end
wipe(P.selectionKeys)
P.selectionKeys.inn, inn.projectedX, inn.projectedAlpha, P.viewAngle = true, 100, 1, 90
P:BlendCompassCityFolds({ inn }, town.bearing + 60, 200)
local townX = 60 / 90 * 200
assert(Near(inn.projectedX, townX + (100 - townX) * 0.875), "from the icon past the view's edge: " .. inn.projectedX)
'''),
    ("a place icon past its own range stays lit by its deepest member in range", f'''
{CITY_POINTS}
local city
for _, marker in ipairs(P.bearings) do if marker.cityRegion then city = marker end end
assert(city.distance > P:GetCompassMarkerRange(city), "the icon is past its own range")
assert(city.compassRaisedBy and city.compassRaisedBy.key == "inn", tostring(city.compassRaisedBy and city.compassRaisedBy.key))
Publish({{ Marker("farm", 0.2, 0.8) }})
assert(city.compassRaisedBy == nil, "no member, no raise")
'''),
    ("a place's destination sits on its own map, inside its bounds", '''
local brill = BrillPoints()
local town, city
for _, marker in ipairs(P:GetCompassPlaceMarkers()) do
 if marker.key == "town:159" then town = marker elseif marker.key == "city:" .. mock.cityMap then city = marker end
end
local x, y = (brill.rect[1] + brill.rect[3]) / 2, (brill.rect[2] + brill.rect[4]) / 2
assert(town.destination.mapID == brill.map and Near(town.destination.x, x) and Near(town.destination.y, y))
assert(city.destination.mapID == mock.cityMap and city.destination.x == 0.5 and city.destination.y == 0.5)
'''),
    ("with Cities & Towns off no place work runs", f'''
{CITY_POINTS}
P:SetCompassPointVisibility("ShowPlaces", "world", false)
P:CacheCompassPointVisibility()
local folds, bearings = 0, 0
local update, refresh = P.UpdateCompassPlaceFolds, P.RefreshCompassMarkerBearing
function P:UpdateCompassPlaceFolds(...) folds = folds + 1 return update(self, ...) end
function P:RefreshCompassMarkerBearing(marker)
 if marker.cityRegion then bearings = bearings + 1 end
 return refresh(self, marker)
end
Walk(0.46, 0.66)
assert(folds == 0 and bearings == 0 and P.compassPositionTown == nil, folds .. " " .. bearings)
P:SetCompassPointVisibility("ShowPlaces", "world", true)
P:CacheCompassPointVisibility()
Settle()
assert(folds > 0 and bearings > 0, "back on, places order again")
'''),
    ("a point fading out with its fold offers no choice, menu entry or target", '''
local inn = { key = "inn", kind = "service", sizeScale = 1, distance = 100, distanceSquared = 1e4, projectedX = 0 }
local bank = { key = "bank", kind = "service", sizeScale = 1, distance = 110, distanceSquared = 12100, projectedX = 1,
 projectedRetiring = true }
P:LayoutCompassMarkerGroups({ inn, bank })
local group = inn.overlapGroup
assert(group == bank.overlapGroup and #group.markers == 2 and #group.actions == 1 and group.actions[1] == inn)
''', RIBBON_MODULES),
    ("the target hotkey skips a point folding away", '''
Publish({ Marker("inn", 0.45, 0.6) })
local inn = P.markers[1]
function P:GetCompassFacing() return inn.bearing end
inn.renderShown = true
assert(P:FindCompassPoint(true) == inn, "the point ahead is the target")
inn.projectedRetiring = true
assert(P:FindCompassPoint(true) == nil, "a point folding away is not")
'''),
    ("a place holding an Available Quests point offers quests, at any distance", '''
local brill = Town(159)
local x, y = (brill.rect[1] + brill.rect[3]) / 2, (brill.rect[2] + brill.rect[4]) / 2
mock.px, mock.py = 0.02, 0.02
local function Offers(key)
 for _, marker in ipairs(P:GetCompassPlaceMarkers()) do
  if marker.key == key then return marker.cityRegion.offersQuests end
 end
end
P.range = 1
Publish({ Marker("giver", x, y, "questOffer"), Marker("vendor", x + 0.001, y) })
assert(Offers("town:159") == true and Offers("city:" .. mock.cityMap) == false, "only the town holding the giver")
assert(P.markers[1].key == "giver" and P.markers[1].distance > P.range, "the giver itself is beyond its range")
Publish({ Marker("vendor", x + 0.001, y) })
assert(Offers("town:159") == false, "the bang leaves with the last giver")
'''),
    ("a place with quests puts Blizzard's quest bang left of its name, fading with it", '''
P:CreateCompassPlaceLabel()
local label = P.compassPlaceLabel
local quest = label.quest
local region = { left = 0.4, right = 0.5, top = 0.3, bottom = 0.4, place = {}, offersQuests = true }
local town = { key = "town:1", kind = "city", name = "Brill", cityRegion = region, renderShown = true,
 distance = 500, projectedDelta = 0 }
local other = { key = "town:2", kind = "city", name = "Tarren Mill", renderShown = true, distance = 500,
 projectedDelta = 0, cityRegion = { left = 0.4, right = 0.5, top = 0.3, bottom = 0.4, place = {} } }
local function Frame(seconds, place)
 P.markerClock = P.markerClock + seconds
 return P:RenderCompassPlaceLabel(P:FindCompassFacedPlace({ place }))
end
assert(quest.atlas == "QuestNormal" and not quest.shown, "Blizzard's available-quest bang, hidden at first")
Frame(0, town)
Frame(0.1, town)
assert(quest.shown and Near(quest.alpha, 0.5) and quest.point == "RIGHT" and quest.x < 0, "fades in left of the name")
assert(quest.width == quest.height and quest.width > 16, "a square a little taller than the name")
region.offersQuests = false
Frame(0.2, town)
assert(not quest.shown and label.text.shown, "taking the last quest drops the bang, not the name")
region.offersQuests = true
Frame(0, town)
assert(quest.shown and quest.alpha == 1, "a new quest brings it back at the title's strength")
Frame(0, other)
Frame(0.1, other)
assert(quest.shown and label.text.text == "Brill", "it fades out with its own name")
Frame(0.2, other)
assert(label.text.text == "Tarren Mill" and not quest.shown, "a place without quests shows none")
P:HideCompassPlaceLabel()
assert(not quest.shown and not label.quests, "hiding the title hides the bang")
''', RIBBON_MODULES),
    ("a shown town lists every point inside it, and shows them all once entered, whatever their range", '''
local brill = Town(159)
local x, y = (brill.rect[1] + brill.rect[3]) / 2, (brill.rect[2] + brill.rect[4]) / 2
mock.px, mock.py, mock.faction = 0.02, 0.02, "Horde"
P:SetCompassPointRange("ShowPlaces", C.RANGE_MAX)
P:CacheCompassRanges()
P.range = C.RANGE_MIN
Publish({ Marker("inn", x, y), Marker("vendor", x + 0.001, y), Marker("farm", 0.9, 0.9) })
local shown = Shown()
assert(shown:find("town:159", 1, true) and not shown:find("inn", 1, true) and not shown:find("vendor", 1, true),
 "the town by its own range, its points folded: " .. shown)
local town
for _, marker in ipairs(P.bearings) do if marker.key == "town:159" then town = marker end end
assert(town.distance > C.RANGE_MIN, "its points lie beyond their own range")
P:ShowCompassCityMenu(town)
assert(#mock.menu.buttons == 3, "the town and both of its points: " .. #mock.menu.buttons)
mock.subzone = "Brill"
Enter(3)
shown = Shown()
assert(shown:find("inn,", 1, true) and shown:find("vendor", 1, true) and not shown:find("town:159", 1, true),
 "inside, every point in it shows: " .. shown)
'''),
    ("a town past its own range stays hidden while none of its points is within theirs", '''
local brill = BrillPoints()
P.range = C.RANGE_MIN
Settle()
assert(Shown() == "", "nothing raises it: " .. Shown())
P.range = C.RANGE_MAX
Settle()
assert(Shown() == "town:159", "a point within its range raises it: " .. Shown())
'''),
    ("a capital's points keep their own range, even inside it", f'''
{CITY_POINTS}
P.range = 100
Enter(mock.cityMap)
assert(Shown() == "", "no capital point is within 100 yards: " .. Shown())
'''),
    ("towns on other maps within the farthest range are offered to collectors, by map", '''
local brill = Town(159)
local function Listed()
 for _, entry in ipairs(P:GetCompassTownMaps()) do
  if entry.mapID == brill.map then
   for _, rect in ipairs(entry.rects) do if rect == brill.rect then return #entry.rects end end
  end
 end
end
assert(Listed(), "a town over this map")
P:InitializeCompassDiscovery()
mock.worldRects[brill.map] = { 4000, 5000, 0, 1000 }
assert(Listed(), "a town about 3.5 km past this map's edge")
P:InitializeCompassDiscovery()
mock.worldRects[brill.map] = { 6500, 7500, 0, 1000 }
assert(not Listed(), "a town farther than any range could show it")
'''),
    ("cities on another continent are ignored", '''
local base = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = function(id, p) if id == mock.cityMap then return 7, { x = 1, y = 1 } end return base(id, p) end
P:InitializeCompassDiscovery()
Publish({ Marker("bank",0.45,0.35) })
assert(Shown() == "bank", Shown())
'''),
]


def run():
    failures, total = [], 0
    for family in ("forever", "retail"):
        for name, code, *ribbon in SCENARIOS:
            total += 1
            label = f"{family}: {name}"
            try:
                lua = client(family)
                load_modules(lua, MODULES)
                lua.execute(SETUP)
                if ribbon:
                    lua.execute(RIBBON)
                    load_modules(lua, ribbon[0])
                lua.execute(code)
                print(f"PASS {label}")
            except Exception as error:  # noqa: BLE001 - report every scenario
                failures.append(label)
                print(f"FAIL {label}: {error}")
    unknown = client("unknown")
    load_modules(unknown, MODULES)
    total += 1
    if unknown.eval("#Addon.CompassCityCatalog.places") == 0:
        print("PASS unknown clients carry no cities")
    else:
        failures.append("unknown")
        print("FAIL unknown clients carry no cities")
    print(f"{total - len(failures)}/{total} Compass city scenarios passed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(run())
