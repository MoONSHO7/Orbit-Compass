"""Generate Compass's town catalogue from each client's map tables.

Run `python .scripts/build-town-catalog.py` (add `--check` to verify the committed file). Downloads the needed DB2
exports from wago.tools into `.scripts/.cache/db2/<build>/` once, then writes `Core/Foundation/CompassTownCatalog.lua`.

A town is a named subzone: the curated hubs below on both clients, plus every Forever subzone that holds a flight
master. Its outline is the terrain chunks the game assigns to that subzone, read from the installed client through
NavBuilder's CascLib (`--wow`, `--casc-dll`) and cached per ADT in `.scripts/.cache/terrain/<build>/`. The world-map
overlay hit rectangle, a square around its flight master or a known centre only locates those chunks, and stays its
bounds when none are found. Its faction comes from the flight masters inside it, else from its zone.
"""

import argparse
import csv
import ctypes
import struct
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".scripts/.cache/db2"
OUTPUT = ROOT / "Core/Foundation/CompassTownCatalog.lua"
WAGO = "https://wago.tools/db2/{table}/csv?build={build}"
BUILDS = {"forever": "1.60.1.70959", "retail": "12.1.5.70575"}
TABLES = ("AreaTable", "WorldMapOverlay", "UiMapXMapArt", "UiMapArt", "UiMapArtStyleLayer", "UiMap", "UiMapAssignment",
          "TaxiNodes", "Map")
TERRAIN_CACHE = ROOT / ".scripts/.cache/terrain"
WOW_ROOT = Path(r"C:\Program Files (x86)\World of Warcraft")
CASC_DLL = ROOT.parent / "Orbit-NavBuilder/.tools/native/CascLib.dll"
PRODUCTS = {"forever": "wowf", "retail": "wow"}
CASC_LOCALE_ENUS, CASC_OPEN_BY_FILE_ID = 2, 3
TILES_PER_AXIS, CHUNKS_PER_TILE = 64, 16
TILE_YARDS = 1600 / 3
CHUNK_YARDS = TILE_YARDS / CHUNKS_PER_TILE
ORIGIN = TILES_PER_AXIS / 2 * TILE_YARDS
MAID_RECORD_BYTES, MCNK_AREA_OFFSET = 32, 52
# A subzone's chunks are sought this far around the rectangle that locates it; a flood past MAX_CHUNKS is rejected.
SEARCH_YARDS = 100
MAX_CHUNKS = 4096
SPAN_DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
ZONE_MAP_TYPE = 3
FLIGHT_TOWN_YARDS = 90
FLIGHT_TOWN_FAMILIES = ("forever",)
# Flight masters whose node name differs from their subzone's name.
TAXI_ALIASES = {"Feathermoon": "Feathermoon Stronghold", "Grom'gol": "Grom'gol Base Camp", "Theramore": "Theramore Isle"}
# World north/west centres for hubs with neither a usable overlay nor a flight master: Kharanos is innkeeper Belm.
KNOWN_CENTRES = {("forever", 131): (-5601.6, -531.2)}
# TaxiNodes flag bits for the factions a flight master serves, and AreaTable zone faction masks.
TAXI_ALLIANCE, TAXI_HORDE = 0x1, 0x2
ZONE_FACTIONS = {2: "Alliance", 4: "Horde"}
# Camps with no flight master whose zone faction is wrong or missing.
FACTION_OVERRIDES = {"Rebel Camp": "Alliance", "Talrendis Point": "Alliance"}
GOBLIN_TOWNS = {"Booty Bay", "Gadgetzan", "Ratchet", "Everlook", "Steamwheedle Port", "Mudsprocket", "Bilgewater Harbor"}
HUBS = (
    "Goldshire", "Kharanos", "Brill", "Sentinel Hill", "Thelsamar", "Lakeshire", "Darkshire", "The Sepulcher",
    "Menethil Harbor", "Southshore", "Tarren Mill", "Refuge Pointe", "Hammerfall", "Aerie Peak", "Revantusk Village",
    "Booty Bay", "Grom'gol Base Camp", "Kargath", "Thorium Point", "Morgan's Vigil", "Flame Crest", "Stonard",
    "Nethergarde Keep", "Chillwind Camp", "Light's Hope Chapel", "Razor Hill", "Sen'jin Village", "Bloodhoof Village",
    "Dolanaar", "The Crossroads", "Ratchet", "Camp Taurajo", "Auberdine", "Astranaar", "Splintertree Post",
    "Zoram'gar Outpost", "Stonetalon Peak", "Sun Rock Retreat", "Nijel's Point", "Shadowprey Village", "Freewind Post",
    "Theramore Isle", "Brackenwall Village", "Feathermoon Stronghold", "Camp Mojache", "Gadgetzan", "Steamwheedle Port",
    "Valormok", "Talrendis Point", "Marshal's Refuge", "Nighthaven", "Cenarion Hold", "Everlook", "Deathknell",
    "Anvilmar", "Shadowglen", "Valley of Trials", "Rebel Camp", "Nesingwary's Expedition", "Thalanaar", "Mudsprocket",
)


def table(family, name):
    build = BUILDS[family]
    path = CACHE / build / f"{name}.csv"
    if not path.is_file():
        path.parent.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(WAGO.format(table=name, build=build), headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=120) as response:
            path.write_bytes(response.read())
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def number(value):
    return float(value) if "." in value or "e" in value.lower() else int(value)


def chunks(data):
    offset = 0
    while offset + 8 <= len(data):
        size = struct.unpack_from("<I", data, offset + 4)[0]
        yield data[offset:offset + 4][::-1], offset + 8, size
        offset += 8 + size


class Storage:
    """Reads files by ID from an installed client through NavBuilder's CascLib."""

    def __init__(self, dll, root, product):
        self.casc = casc = ctypes.CDLL(str(dll))
        casc.CascOpenStorage.argtypes = [ctypes.c_char_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
        casc.CascOpenStorage.restype = ctypes.c_bool
        casc.CascOpenFile.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32,
                                      ctypes.POINTER(ctypes.c_void_p)]
        casc.CascOpenFile.restype = ctypes.c_bool
        casc.CascGetFileSize64.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64)]
        casc.CascReadFile.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32)]
        casc.CascReadFile.restype = ctypes.c_bool
        casc.CascCloseFile.argtypes = [ctypes.c_void_p]
        self.handle = ctypes.c_void_p()
        if not casc.CascOpenStorage(f"{root}\\*{product}".encode("mbcs"), CASC_LOCALE_ENUS, ctypes.byref(self.handle)):
            raise SystemExit(f"CascLib could not open the {product} client under {root}")

    def read(self, file_id):
        handle = ctypes.c_void_p()
        if not self.casc.CascOpenFile(self.handle, ctypes.c_void_p(file_id), CASC_LOCALE_ENUS, CASC_OPEN_BY_FILE_ID,
                                      ctypes.byref(handle)):
            return None
        size = ctypes.c_uint64()
        self.casc.CascGetFileSize64(handle, ctypes.byref(size))
        buffer = ctypes.create_string_buffer(size.value)
        read = ctypes.c_uint32()
        ok = self.casc.CascReadFile(handle, buffer, size.value, ctypes.byref(read))
        self.casc.CascCloseFile(handle)
        return buffer.raw[:read.value] if ok else None


class Terrain:
    """The area ID the game assigns to each terrain chunk of a continent, cached per ADT tile."""

    def __init__(self, family, wdts, open_storage):
        self.cache = TERRAIN_CACHE / BUILDS[family]
        self.wdts, self.open_storage = wdts, open_storage
        self.storage, self.records, self.tiles = None, {}, {}

    def read_tile(self, continent, x, y):
        if self.storage is None:
            self.storage = self.open_storage()
        if continent not in self.records:
            wdt = self.storage.read(self.wdts[continent])
            maid = next(offset for tag, offset, _ in chunks(wdt) if tag == b"MAID")
            self.records[continent] = [struct.unpack_from("<I", wdt, maid + i * MAID_RECORD_BYTES)[0]
                                       for i in range(TILES_PER_AXIS * TILES_PER_AXIS)]
        file_id = self.records[continent][y * TILES_PER_AXIS + x]
        data = file_id and self.storage.read(file_id)
        if not data:
            return []
        areas = [0] * CHUNKS_PER_TILE * CHUNKS_PER_TILE
        for tag, offset, _ in chunks(data):
            if tag == b"MCNK":
                column, row = struct.unpack_from("<II", data, offset + 4)
                areas[row * CHUNKS_PER_TILE + column] = struct.unpack_from("<I", data, offset + MCNK_AREA_OFFSET)[0]
        return areas

    def tile(self, continent, x, y):
        key = (continent, x, y)
        if key not in self.tiles:
            path = self.cache / f"{continent}_{x}_{y}.bin"
            if path.is_file():
                data = path.read_bytes()
                self.tiles[key] = list(struct.unpack(f"<{len(data) // 4}I", data))
            else:
                self.tiles[key] = self.read_tile(continent, x, y)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(struct.pack(f"<{len(self.tiles[key])}I", *self.tiles[key]))
        return self.tiles[key]

    def area(self, continent, row, column):
        span = TILES_PER_AXIS * CHUNKS_PER_TILE
        if not (0 <= row < span and 0 <= column < span):
            return None
        areas = self.tile(continent, column // CHUNKS_PER_TILE, row // CHUNKS_PER_TILE)
        return areas[row % CHUNKS_PER_TILE * CHUNKS_PER_TILE + column % CHUNKS_PER_TILE] if areas else None


class Client:
    def __init__(self, family, open_storage):
        self.family = family
        self.areas = {int(r["ID"]): r for r in table(family, "AreaTable")}
        self.maps = {int(r["ID"]): r for r in table(family, "UiMap")}
        self.overlays = table(family, "WorldMapOverlay")
        self.art_maps = {}
        for row in table(family, "UiMapXMapArt"):
            self.art_maps.setdefault(int(row["UiMapArtID"]), []).append(int(row["UiMapID"]))
        self.art_style = {int(r["ID"]): int(r["UiMapArtStyleID"]) for r in table(family, "UiMapArt")}
        self.style_size = {}
        for row in table(family, "UiMapArtStyleLayer"):
            if int(row["LayerIndex"]) == 0:
                self.style_size[int(row["UiMapArtStyleID"])] = (int(row["LayerWidth"]), int(row["LayerHeight"]))
        self.zone_maps = {}
        self.regions = {}
        for row in table(family, "UiMapAssignment"):
            map_id = int(row["UiMapID"])
            info = self.maps.get(map_id)
            if not info or int(info["Type"]) != ZONE_MAP_TYPE or int(info["System"]) != 0:
                continue
            area = int(row["AreaID"])
            self.zone_maps.setdefault(area, map_id)
            self.regions.setdefault(map_id, (int(row["MapID"]), *[number(row[f"Region_{i}"]) for i in (0, 1, 3, 4)]))
        wdts = {int(r["ID"]): int(r["WdtFileDataID"]) for r in table(family, "Map")}
        self.terrain = Terrain(family, wdts, open_storage)
        self.taxis = table(family, "TaxiNodes")
        self.by_name = {}
        for area in self.areas.values():
            self.by_name.setdefault(area["AreaName_lang"], []).append(area)

    def zone_of(self, area):
        parent = int(area["ParentAreaID"])
        return self.zone_maps.get(parent)

    def overlay_rect(self, area_id, map_id):
        for row in self.overlays:
            if area_id not in {int(row[f"AreaID_{i}"]) for i in range(4)}:
                continue
            art = int(row["UiMapArtID"])
            if map_id not in self.art_maps.get(art, ()):
                continue
            width, height = self.style_size[self.art_style[art]]
            left, right = int(row["HitRectLeft"]) / width, int(row["HitRectRight"]) / width
            top, bottom = int(row["HitRectTop"]) / height, int(row["HitRectBottom"]) / height
            # Rows whose edges are swapped (Forever's Kharanos) do not bound the subzone; a known centre replaces them.
            if right > left and bottom > top:
                return left, top, right, bottom

    def world_rect(self, map_id, north, west, yards):
        _, min_north, min_west, max_north, max_west = self.regions[map_id]
        width, height = max_west - min_west, max_north - min_north
        x, y = (max_west - west) / width, (max_north - north) / height
        dx, dy = yards / width, yards / height
        return x - dx, y - dy, x + dx, y + dy

    def chunk(self, map_id, x, y):
        _, min_north, min_west, max_north, max_west = self.regions[map_id]
        west, north = max_west - x * (max_west - min_west), max_north - y * (max_north - min_north)
        return (ORIGIN - north) / CHUNK_YARDS, (ORIGIN - west) / CHUNK_YARDS

    def map_point(self, map_id, row, column):
        _, min_north, min_west, max_north, max_west = self.regions[map_id]
        north, west = ORIGIN - row * CHUNK_YARDS, ORIGIN - column * CHUNK_YARDS
        return (max_west - west) / (max_west - min_west), (max_north - north) / (max_north - min_north)

    # The subzone's own chunks, flooded from those near the rectangle that locates it; a copy elsewhere stays out.
    def footprint(self, area_ids, map_id, rect):
        continent = self.regions[map_id][0]
        top, left = self.chunk(map_id, rect[0], rect[1])
        bottom, right = self.chunk(map_id, rect[2], rect[3])
        reach = SEARCH_YARDS / CHUNK_YARDS
        queue = [(row, column) for row in range(int(top - reach), int(bottom + reach) + 1)
                 for column in range(int(left - reach), int(right + reach) + 1)
                 if self.terrain.area(continent, row, column) in area_ids]
        found = set(queue)
        while queue and len(found) <= MAX_CHUNKS:
            row, column = queue.pop()
            for step in ((row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)):
                if step not in found and self.terrain.area(continent, *step) in area_ids:
                    found.add(step)
                    queue.append(step)
        return found if len(found) <= MAX_CHUNKS else set()

    def outline(self, map_id, found):
        rows, columns = [r for r, _ in found], [c for _, c in found]
        top, bottom, left, right = min(rows), max(rows), min(columns), max(columns)
        if right - left >= len(SPAN_DIGITS):
            return None
        lines = []
        for row in range(top, bottom + 1):
            runs, column = [], left
            while column <= right:
                if (row, column) in found:
                    start = column
                    while (row, column + 1) in found:
                        column += 1
                    runs.append(SPAN_DIGITS[start - left] + SPAN_DIGITS[column - left])
                column += 1
            lines.append("".join(runs))
        corner, far = self.map_point(map_id, top, left), self.map_point(map_id, bottom + 1, right + 1)
        return (*corner, *far), f"{right - left + 1}:" + "/".join(lines)

    def flight_towns(self):
        towns, sides = {}, {}
        for node in self.taxis:
            name = node["Name_lang"].split(",")[0].strip()
            name = TAXI_ALIASES.get(name, name)
            continent, north, west = int(node["ContinentID"]), float(node["Pos_0"]), float(node["Pos_1"])
            for area in self.by_name.get(name, ()):
                map_id = self.zone_of(area)
                region = map_id and self.regions.get(map_id)
                if region and region[0] == continent and region[1] <= north <= region[3] and region[2] <= west <= region[4]:
                    towns[int(area["ID"])] = (north, west)
                    sides[int(area["ID"])] = sides.get(int(area["ID"]), 0) | int(node["Flags"]) & (TAXI_ALLIANCE | TAXI_HORDE)
        return towns, sides

    def faction(self, area, sides):
        if area["AreaName_lang"] in FACTION_OVERRIDES:
            return FACTION_OVERRIDES[area["AreaName_lang"]]
        side = sides.get(int(area["ID"]), 0)
        if side == TAXI_ALLIANCE:
            return "Alliance"
        if side == TAXI_HORDE:
            return "Horde"
        if side:
            return None
        zone = self.areas.get(int(area["ParentAreaID"]))
        return ZONE_FACTIONS.get(int(zone["FactionGroupMask"])) if zone else None

    def towns(self, problems):
        flights, sides = self.flight_towns()
        wanted = {}
        for name in HUBS:
            matches = [a for a in self.by_name.get(name, ()) if self.zone_of(a)]
            if not matches:
                problems.append(f"{self.family}: no zone subzone named {name}")
            for area in matches:
                wanted[int(area["ID"])] = area
        if self.family in FLIGHT_TOWN_FAMILIES:
            for area_id in flights:
                wanted.setdefault(area_id, self.areas[area_id])
        towns, named = [], set()
        for area_id, area in sorted(wanted.items()):
            map_id = self.zone_of(area)
            # Later copies of a subzone on the same map (phased rebuilds) share its name, so the original stands for both.
            if (map_id, area["AreaName_lang"]) in named:
                continue
            named.add((map_id, area["AreaName_lang"]))
            rect = self.overlay_rect(area_id, map_id)
            centre = flights.get(area_id) or KNOWN_CENTRES.get((self.family, area_id))
            if not rect and centre:
                rect = self.world_rect(map_id, *centre, FLIGHT_TOWN_YARDS)
            if not rect:
                problems.append(f"{self.family}: {area['AreaName_lang']} ({area_id}) has no overlay or flight master")
                continue
            same = {int(a["ID"]) for a in self.by_name[area["AreaName_lang"]] if self.zone_of(a) == map_id}
            found = self.footprint(same, map_id, rect)
            shape = found and self.outline(map_id, found)
            mask = None
            if shape:
                rect, mask = shape
            else:
                problems.append(f"{self.family}: {area['AreaName_lang']} ({area_id}) has no terrain outline; keeps its rectangle")
            goblin = area["AreaName_lang"] in GOBLIN_TOWNS
            faction = None if goblin else self.faction(area, sides)
            icon = "goblin" if goblin else "horde" if faction == "Horde" else "town"
            towns.append((area_id, map_id, rect, mask, icon, faction, area["AreaName_lang"]))
        return towns


def render(families):
    lines = [
        "-- Generated by .scripts/build-town-catalog.py from each client's map tables; do not edit by hand.",
        "local _, Addon = ...",
        "",
        "Addon.CompassTownCatalog = {",
    ]
    for family, towns in families.items():
        lines.append(f"    {family} = {{")
        for area_id, map_id, rect, _, icon, faction, name in towns:
            numbers = ", ".join(f"{v:.4f}" for v in rect)
            side = f', faction = "{faction}"' if faction else ""
            lines.append(f'        {{ area = {area_id}, map = {map_id}, rect = {{ {numbers} }}, icon = "{icon}"{side} }}, -- {name}')
        lines.append("    },")
    lines += ["}", "", "-- Chunk columns, then per chunk row from the north each run's first and last column (A = 0).",
              "Addon.CompassTownMasks = {"]
    for family, towns in families.items():
        lines.append(f"    {family} = {{")
        for area_id, _, _, mask, _, _, name in towns:
            if mask:
                lines.append(f'        [{area_id}] = "{mask}", -- {name}')
        lines.append("    },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail when the committed catalogue is stale")
    parser.add_argument("--wow", type=Path, default=WOW_ROOT, help="installed World of Warcraft folder")
    parser.add_argument("--casc-dll", type=Path, default=CASC_DLL, help="CascLib.dll that reads the installed client")
    arguments = parser.parse_args()
    problems = []
    families = {}
    for family in BUILDS:
        def open_storage(product=PRODUCTS[family]):
            return Storage(arguments.casc_dll, arguments.wow, product)
        families[family] = Client(family, open_storage).towns(problems)
    for problem in problems:
        print("note:", problem)
    text = render(families)
    if arguments.check:
        if OUTPUT.read_text(encoding="utf-8") != text:
            print(f"{OUTPUT.relative_to(ROOT)} is stale; run without --check")
            return 1
        print("Town catalogue is current.")
        return 0
    OUTPUT.write_bytes(text.encode("utf-8"))
    print(f"Wrote {sum(len(t) for t in families.values())} towns: " + ", ".join(f"{f} {len(t)}" for f, t in families.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
