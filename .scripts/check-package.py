"""Validate a standalone Orbit addon source or materialized runtime package."""

import argparse
import importlib.util
import posixpath
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = {
    "Orbit_Compass": ("OrbitCompassDB", False, "1689597", 8),
    "Orbit_StatusWidget": ("OrbitStatusWidgetDB", True, "1688135", 6),
}
UI_DIRECTORY = "Libs/LibOrbitUI-1.0/"
PICKER_DIRECTORY = "Libs/LibOrbitColorPicker-1.0/"
TEXTURE_EXTENSIONS = (".tga", ".blp", ".png")

spec = importlib.util.spec_from_file_location("fetch_libraries", ROOT / ".scripts/fetch-libs.py")
fetcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetcher)


def strip_development(text, name):
    result = []
    skipping = False
    for line in text.splitlines(keepends=True):
        if "@end-do-not-package@" in line:
            if not skipping:
                raise ValueError(f"Unmatched do-not-package end marker: {name}")
            skipping = False
        elif "@do-not-package@" in line:
            if skipping:
                raise ValueError(f"Nested do-not-package marker: {name}")
            skipping = True
        elif not skipping:
            result.append(line)
    if skipping:
        raise ValueError(f"Unterminated do-not-package block: {name}")
    return "".join(result)


def validate(root, release=False):
    root = root.absolute()
    metadata = (ROOT / ".pkgmeta").read_text(encoding="utf-8-sig")
    package = re.search(r"^package-as:\s*([A-Za-z0-9_-]+)\s*$", metadata, re.MULTILINE)
    if not package or package[1] not in CONTRACTS:
        raise ValueError(".pkgmeta must declare the supported standalone package-as name")
    addon = package[1]
    saved_variable, needs_picker, curse_project_id, ui_minor = CONTRACTS[addon]
    externals = fetcher.dependencies(ROOT)
    required = {UI_DIRECTORY.rstrip("/")}
    if addon == "Orbit_Compass" and release:
        required.update({"Libs/LibOrbitSearch-1.0", "Libs/LibStub"})
    if needs_picker:
        required.update({PICKER_DIRECTORY.rstrip("/"), "Libs/LibStub"})
    if not required <= externals.keys():
        raise ValueError(f"Required immutable externals are missing: {sorted(required - externals.keys())}")
    if release:
        fetcher.plain_tree(root)
    compile_lua = LuaRuntime().eval("function(code, name) assert(loadstring(code, name)) end")
    loaded = {}
    asset_paths = set()

    def normalize(relative):
        value = str(relative).replace("\\", "/")
        value = posixpath.normpath(value)
        if value.startswith(("/", "../")) or value in (".", "..") or ":" in value:
            raise ValueError(f"Runtime reference escapes the addon: {relative}")
        return value

    def read(relative):
        relative = normalize(relative)
        return relative, (root / relative).read_bytes()

    def asset(relative):
        relative = normalize(relative)
        if not (root / relative).is_file() and not Path(relative).suffix:
            candidates = [relative + extension for extension in TEXTURE_EXTENSIONS]
            relative = next((name for name in candidates if (root / name).is_file()), relative)
        read(relative)
        asset_paths.add(relative)

    def inspect_assets(text):
        for value in re.findall(r'["\']([^"\'\r\n]+)["\']', text):
            value = value.replace("\\\\", "/").replace("\\", "/")
            prefix = f"Interface/AddOns/{addon}/"
            if value.startswith(prefix) and not value.endswith(("/", "-")):
                asset(value[len(prefix):])
            elif value.startswith("/Assets/") and not value.endswith(("/", "-")):
                asset(value[1:])
        for value in re.findall(r'(?:addon\.assetPath|mediaPath)\s*\.\.\s*"([^"\r\n]+)"', text):
            value = value.replace("\\\\", "/").replace("\\", "/")
            if not value.endswith(("/", "-")):
                asset("Assets/" + value)

    def visit(relative):
        relative, content = read(relative)
        if relative in loaded:
            raise ValueError(f"Duplicate or cyclic runtime inclusion: {relative}")
        text = strip_development(content.decode("utf-8-sig"), relative)
        loaded[relative] = text
        if relative.lower().endswith(".xml"):
            for node in ET.fromstring(text).iter():
                tag = node.tag.rsplit("}", 1)[-1]
                if tag in ("Script", "Include") and "file" in node.attrib:
                    visit(posixpath.join(posixpath.dirname(relative), node.attrib["file"].replace("\\", "/")))
                elif tag == "Binding" or tag.startswith("On"):
                    if node.text and node.text.strip():
                        compile_lua(node.text, "@" + relative + ":" + tag)
                elif tag == "Script" and node.text and node.text.strip():
                    compile_lua(node.text, "@" + relative + ":Script")
        elif relative.lower().endswith(".lua"):
            compile_lua(text, "@" + relative)
            if not relative.startswith("Libs/"):
                inspect_assets(text)
        else:
            raise ValueError(f"Unsupported runtime entry: {relative}")

    toc_name = addon + ".toc"
    _, toc_bytes = read(toc_name)
    toc = strip_development(toc_bytes.decode("utf-8-sig"), toc_name)
    headers = {}
    for line in toc.splitlines():
        line = line.strip()
        if line.startswith("##") and ":" in line:
            key, value = line[2:].split(":", 1)
            key = key.strip().lower()
            if key in headers:
                raise ValueError(f"Duplicate TOC header: {key}")
            headers[key] = value.strip()
        elif line and not line.startswith("#"):
            visit(line)
    interfaces = [value.strip() for value in headers.get("interface", "").split(",")]
    if "120100" not in interfaces or any(not value.isdecimal() or int(value) <= 0 for value in interfaces):
        raise ValueError("Interface must contain 120100 and only positive numeric client versions")
    if len(interfaces) != len(set(interfaces)):
        raise ValueError("Duplicate Interface version")
    if headers.get("x-curse-project-id") != curse_project_id:
        raise ValueError(f"{addon} must declare X-Curse-Project-ID: {curse_project_id}")
    if headers.get("savedvariables") != saved_variable:
        raise ValueError(f"The standalone store must be SavedVariables: {saved_variable}")
    hard_dependencies = ",".join(headers.get(key, "") for key in ("dependencies", "requireddeps", "deps"))
    if "Orbit" in re.split(r"[,\s]+", hard_dependencies):
        raise ValueError("Orbit must remain optional, never a hard dependency")
    if "Orbit" not in re.split(r"[,\s]+", headers.get("optionaldeps", "")):
        raise ValueError("Orbit must be declared as an optional host")
    version = headers.get("version", "")
    if version == "@project-version@":
        if root != ROOT.absolute():
            raise ValueError("The packaged Version still contains @project-version@")
    elif not version or "@" in version:
        raise ValueError("The TOC must declare a source token or substituted Version")
    icon = headers.get("icontexture", "").replace("\\", "/")
    prefix = f"Interface/AddOns/{addon}/"
    if not icon.startswith(prefix):
        raise ValueError("IconTexture must reference this installed addon's assets")
    asset(icon[len(prefix):])
    asset("LICENSE")
    if (root / "Bindings.xml").is_file() and "Bindings.xml" not in loaded:
        visit("Bindings.xml")

    library = "\n".join(code for name, code in loaded.items() if name.startswith(UI_DIRECTORY))
    major = re.search(r"\bVERSION_MAJOR\s*=\s*(\d+)", library)
    minor = re.search(r"\bVERSION_MINOR\s*=\s*(\d+)", library)
    if not major or not minor or int(major[1]) != 1 or int(minor[1]) < ui_minor:
        raise ValueError(f"{addon} requires loaded LibOrbitUI API 1.{ui_minor} or newer within major 1")
    for api in ("UI.Controller:Create", "UI.Addon:Create", "UI.SettingsStore:Create", "Config.CreateColorProvider"):
        if not re.search(r"\bfunction\s+" + re.escape(api) + r"\s*\(", library):
            raise ValueError(f"Required API is absent from the loaded LibOrbitUI manifest: {api}")
    if not re.search(r"\bUI\.Client\s*=", library):
        raise ValueError(f"{addon} requires the shared LibOrbitUI client identity")
    if addon == "Orbit_Compass":
        settings = loaded.get(UI_DIRECTORY + "Addon/AddonSettings.lua", "")
        if not re.search(r"\bregisterWidgets\s*=\s*options\.registerWidgets\b", settings):
            raise ValueError("Compass requires Addon settings to forward the consumer registerWidgets hook")
    asset(UI_DIRECTORY + "LICENSE")
    for destination in externals:
        if not any(name.startswith(destination + "/") for name in loaded):
            raise ValueError(f"Pinned dependency is not loaded by the runtime manifest: {destination}")
    if needs_picker:
        picker = "\n".join(code for name, code in loaded.items() if name.startswith(PICKER_DIRECTORY))
        revision = re.search(r'local\s+MAJOR\s*,\s*MINOR\s*=\s*"LibOrbitColorPicker-1\.0"\s*,\s*(\d+)', picker)
        if not revision or int(revision[1]) < 10:
            raise ValueError("The loaded color picker requires revision 10; published revision 9 is incompatible")
        for api in ("lib:Open", "lib:GetCheckerboardTexture"):
            if not re.search(r"\bfunction\s+" + re.escape(api) + r"\s*\(", picker):
                raise ValueError(f"Required picker API is absent from the loaded manifest: {api}")
        asset(PICKER_DIRECTORY + "LICENSE")
        asset(PICKER_DIRECTORY + "checkerboard.tga")
        order = list(loaded)
        if order.index("Libs/LibStub/LibStub.lua") > next(i for i, name in enumerate(order) if name.startswith(PICKER_DIRECTORY)):
            raise ValueError("LibStub must load before the color picker")
    if addon == "Orbit_Compass":
        search = "\n".join(code for name, code in loaded.items() if name.startswith("Libs/LibOrbitSearch-1.0/"))
        asset("Libs/LibOrbitSearch-1.0/LICENSE")
        order = list(loaded)
        first_search = next(i for i, name in enumerate(order) if name.startswith("Libs/LibOrbitSearch-1.0/"))
        if order.index("Libs/LibStub/LibStub.lua") > first_search:
            raise ValueError("LibStub must load before LibOrbitSearch")
        revision = re.search(r'local\s+MAJOR\s*,\s*MINOR\s*=\s*"LibOrbitSearch-1\.0"\s*,\s*(\d+)', search)
        if not revision or int(revision[1]) < 2 or not re.search(r'lib\.PROVIDER_CONTRACT\s*=\s*1\b', search):
            raise ValueError("Compass requires LibOrbitSearch revision 2 and provider contract 1")
        for method in ("RegisterProvider", "UnregisterProvider", "IsKindIncluded", "NotifyProviderChanged"):
            if not re.search(r"function\s+lib:" + method + r"\s*\(", search):
                raise ValueError(f"Required LibOrbitSearch API is absent: {method}")
    print(f"PASS: {addon}; {len(loaded)} runtime files; Lua 5.1; {len(asset_paths)} assets; required library APIs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Materialized package directory; metadata stays in this checkout")
    parser.add_argument("--release", action="store_true", help="Reject symlinks/junctions anywhere beneath the checked root")
    args = parser.parse_args()
    try:
        validate(args.root, args.release)
    except Exception as error:
        parser.exit(1, f"Addon package validation failed: {error}\n")
