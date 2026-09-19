local _, Addon = ...
local DIACRITICS = {
    ["à"] = "a",
    ["á"] = "a",
    ["â"] = "a",
    ["ã"] = "a",
    ["ä"] = "a",
    ["å"] = "a",
    ["æ"] = "ae",
    ["ç"] = "c",
    ["è"] = "e",
    ["é"] = "e",
    ["ê"] = "e",
    ["ë"] = "e",
    ["ì"] = "i",
    ["í"] = "i",
    ["î"] = "i",
    ["ï"] = "i",
    ["ñ"] = "n",
    ["ò"] = "o",
    ["ó"] = "o",
    ["ô"] = "o",
    ["õ"] = "o",
    ["ö"] = "o",
    ["ø"] = "o",
    ["ù"] = "u",
    ["ú"] = "u",
    ["û"] = "u",
    ["ü"] = "u",
    ["ý"] = "y",
    ["ÿ"] = "y",
    ["ß"] = "ss",
    ["À"] = "a",
    ["Á"] = "a",
    ["Â"] = "a",
    ["Ã"] = "a",
    ["Ä"] = "a",
    ["Å"] = "a",
    ["Æ"] = "ae",
    ["Ç"] = "c",
    ["È"] = "e",
    ["É"] = "e",
    ["Ê"] = "e",
    ["Ë"] = "e",
    ["Ì"] = "i",
    ["Í"] = "i",
    ["Î"] = "i",
    ["Ï"] = "i",
    ["Ñ"] = "n",
    ["Ò"] = "o",
    ["Ó"] = "o",
    ["Ô"] = "o",
    ["Õ"] = "o",
    ["Ö"] = "o",
    ["Ø"] = "o",
    ["Ù"] = "u",
    ["Ú"] = "u",
    ["Û"] = "u",
    ["Ü"] = "u",
    ["Ý"] = "y",
}
local MULTIBYTE_PATTERN = "[\194-\244][\128-\191]*"
local CYRILLIC_UPPER_PATTERN = "\208[\128-\175]"
local ASCII_UPPER_PATTERN = "[A-Z]"
local SEPARATOR_PATTERN = "[\9-\13 !-/:-@\91-\96{-~]+"
local LEADING_SEPARATOR = "^ "
local TRAILING_SEPARATOR = " $"
local WORD_PATTERN = "[^ ]+"
local CYRILLIC_LOWER_LEAD = "\209"
local CYRILLIC_SAME_LEAD = "\208"
local CYRILLIC_EXTENDED_LIMIT = 0x90
local CYRILLIC_BASIC_LIMIT = 0xA0
local CYRILLIC_EXTENDED_SHIFT = 0x10
local CYRILLIC_BASIC_SHIFT = 0x20
local ASCII_LOWER = {}
for byte = string.byte("A"), string.byte("Z") do
    ASCII_LOWER[string.char(byte)] = string.char(byte + CYRILLIC_BASIC_SHIFT)
end

local function FoldCharacter(character)
    return DIACRITICS[character] or character
end

local function LowerCyrillic(character)
    local byte = string.byte(character, 2)
    if byte < CYRILLIC_EXTENDED_LIMIT then
        return CYRILLIC_LOWER_LEAD .. string.char(byte + CYRILLIC_EXTENDED_SHIFT)
    elseif byte < CYRILLIC_BASIC_LIMIT then
        return CYRILLIC_SAME_LEAD .. string.char(byte + CYRILLIC_BASIC_SHIFT)
    end
    return CYRILLIC_LOWER_LEAD .. string.char(byte - CYRILLIC_BASIC_SHIFT)
end

local Text = {}

-- Locale-aware string.lower and %s/%p classes can match UTF-8 bytes, so every pattern uses explicit byte ranges.
function Text.Fold(value)
    local folded = string.gsub(value, MULTIBYTE_PATTERN, FoldCharacter)
    folded = string.gsub(folded, CYRILLIC_UPPER_PATTERN, LowerCyrillic)
    folded = string.gsub(folded, ASCII_UPPER_PATTERN, ASCII_LOWER)
    folded = string.gsub(folded, SEPARATOR_PATTERN, " ")
    folded = string.gsub(folded, LEADING_SEPARATOR, "")
    return (string.gsub(folded, TRAILING_SEPARATOR, ""))
end

function Text.Words(folded)
    local words = {}
    for word in string.gmatch(folded, WORD_PATTERN) do
        words[#words + 1] = word
    end
    return words
end

function Text.AddSearchFields(target, name, place)
    local foldedName, foldedPlace = Text.Fold(name), Text.Fold(place or "")
    target.searchText, target.search, target.nameWords = foldedName, " " .. foldedName, Text.Words(foldedName)
    target.place, target.placeWords = " " .. foldedPlace, Text.Words(foldedPlace)
    return target
end

Addon.Text = table.freeze(Text)
