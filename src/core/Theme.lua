-- Theme: a theme is a table of semantic colour tokens; sizes are a second
-- table chosen by device (one code, two/three sets of size tokens).
--
-- Components never hard-code colours or sizes. Instead they bind a property
-- to a token:
--     Theme.bind(frame, "BackgroundColor3", Theme.c("surface"))
--     Theme.bind(frame, "Size", Theme.sz(1, 0, 0, "row"))
-- When the theme or the device mode changes, every bound property is
-- re-applied in place — no window re-creation, no restart.

local Signal = import("util/Signal")
local Util = import("util/Util")
local Motion = import("core/Motion")

local Theme = {}

Theme.Changed = Signal.new()

-- Colour tokens ------------------------------------------------------------

-- Order matters: it is the order used by the export string.
Theme.TokenOrder = {
	"accent", "bg", "nav", "surface", "raised", "overlay", "sunken", "selected", "segment",
	"border", "borderStrong", "divider", "text", "textMuted", "textSubtle",
	"accentInk", "accentPressed", "track", "toggleOff", "knobOn", "knobOff", "checkBorder",
	"success", "warning", "danger", "dangerInk", "tooltip", "tooltipText", "backdrop", "code", "codeText",
}

local function preset(hexes)
	local out = {}
	for key, value in pairs(hexes) do
		out[key] = Util.hex(value)
	end
	return out
end

Theme.Presets = {
	RobScript = preset({
		accent = "FF3B7F", bg = "121216", nav = "0F0F13", surface = "18181D", raised = "24242C",
		overlay = "1C1C22", sunken = "0F0F13", selected = "22222A", segment = "2C2C35",
		border = "23232A", borderStrong = "2A2A33", divider = "1F1F26",
		text = "F2F2F5", textMuted = "A3A3AE", textSubtle = "85858F",
		accentInk = "1A0610", accentPressed = "E2306F", track = "2A2A33", toggleOff = "3A3A44",
		knobOn = "FFFFFF", knobOff = "FFFFFF", checkBorder = "4A4A55",
		success = "34D399", warning = "FBBF24", danger = "FF5A5A", dangerInk = "1F0505",
		tooltip = "F2F2F5", tooltipText = "121216", backdrop = "060608", code = "0B0B0E", codeText = "D4D4DC",
	}),
	Light = preset({
		accent = "E0245E", bg = "FFFFFF", nav = "F3F3F6", surface = "F6F6F8", raised = "EBEBF0",
		overlay = "FFFFFF", sunken = "ECECF1", selected = "E4E4EA", segment = "FFFFFF",
		border = "E4E4EA", borderStrong = "D4D4DC", divider = "EBEBF0",
		text = "16161A", textMuted = "55555F", textSubtle = "6B6B76",
		accentInk = "FFFFFF", accentPressed = "C81E52", track = "DCDCE3", toggleOff = "D4D4DC",
		knobOn = "FFFFFF", knobOff = "FFFFFF", checkBorder = "B4B4BE",
		success = "0E9F6E", warning = "B7791F", danger = "E5484D", dangerInk = "FFFFFF",
		tooltip = "16161A", tooltipText = "FFFFFF", backdrop = "000000", code = "F3F3F6", codeText = "2A2A33",
	}),
	Graphite = preset({
		accent = "E6E6E8", bg = "1B1B1D", nav = "161618", surface = "222225", raised = "2C2C2F",
		overlay = "262629", sunken = "161618", selected = "2C2C2F", segment = "38383B",
		border = "2C2C2F", borderStrong = "333336", divider = "28282B",
		text = "EDEDEE", textMuted = "A1A1A6", textSubtle = "8E8E93",
		accentInk = "161618", accentPressed = "CFCFD2", track = "333336", toggleOff = "3A3A3E",
		knobOn = "1B1B1D", knobOff = "EDEDEE", checkBorder = "4A4A4E",
		success = "34D399", warning = "FBBF24", danger = "FF5A5A", dangerInk = "1F0505",
		tooltip = "EDEDEE", tooltipText = "1B1B1D", backdrop = "0A0A0B", code = "141416", codeText = "D4D4D8",
	}),
	Midnight = preset({
		accent = "4C8DFF", bg = "0E1320", nav = "0A0F1A", surface = "141B2B", raised = "1C2436",
		overlay = "172033", sunken = "0A0F1A", selected = "1C2436", segment = "25304A",
		border = "1C2436", borderStrong = "25304A", divider = "172033",
		text = "E8EDF7", textMuted = "A3AEC4", textSubtle = "8792A8",
		accentInk = "06102A", accentPressed = "3B78E6", track = "25304A", toggleOff = "2A3550",
		knobOn = "FFFFFF", knobOff = "FFFFFF", checkBorder = "3A4766",
		success = "34D399", warning = "FBBF24", danger = "FF5A5A", dangerInk = "1F0505",
		tooltip = "E8EDF7", tooltipText = "0E1320", backdrop = "04060C", code = "0A0F1A", codeText = "CBD5E8",
	}),
}

Theme.PresetOrder = { "RobScript", "Light", "Graphite", "Midnight" }

Theme.Name = "RobScript"
Theme.Colors = table.clone(Theme.Presets.RobScript)

-- Size tokens ------------------------------------------------------------------

local PC = {
	header = 56, sidebar = 200, navItem = 38, rail = 56, tabbar = 60,
	row = 50, rowDesc = 54, control = 32, button = 36, input = 38,
	toggleW = 44, toggleH = 26, knob = 22, checkbox = 20,
	track = 6, sliderKnob = 20, sliderHit = 24, segment = 28, stepperBtn = 34, chip = 30, hit = 32,
	font = 14, fontDesc = 12, fontSmall = 11, fontSection = 12, fontTitle = 22, fontHeader = 14,
	padX = 14, padY = 8, gap = 16, contentX = 24, contentTop = 20, contentBottom = 20, sectionGap = 14,
	rWindow = 18, rSection = 14, rControl = 10, rSmall = 9, rBadge = 6,
	icon = 18, iconSmall = 16, item = 34, toastWidth = 280, scrollBar = 3,
	touch = false, pageHeader = true, dropdownFlat = false,
}

local PHONE = {
	header = 44, sidebar = 56, navItem = 44, rail = 56, tabbar = 60,
	row = 52, rowDesc = 56, control = 44, button = 44, input = 44,
	toggleW = 51, toggleH = 31, knob = 27, checkbox = 24,
	track = 6, sliderKnob = 28, sliderHit = 44, segment = 40, stepperBtn = 44, chip = 36, hit = 44,
	font = 15, fontDesc = 13, fontSmall = 12, fontSection = 12, fontTitle = 16, fontHeader = 16,
	padX = 12, padY = 4, gap = 12, contentX = 12, contentTop = 0, contentBottom = 12, sectionGap = 8,
	rWindow = 18, rSection = 14, rControl = 10, rSmall = 10, rBadge = 6,
	icon = 20, iconSmall = 18, item = 44, toastWidth = 300, scrollBar = 0,
	touch = true, pageHeader = false, dropdownFlat = true,
}

local TABLET = Util.merge(PHONE, {
	header = 52, fontTitle = 18, contentX = 16, contentTop = 4, contentBottom = 16,
	rWindow = 22, rSection = 16, padX = 14, sectionGap = 10,
})

Theme.SizeSets = { pc = PC, phone = PHONE, tablet = TABLET }
Theme.Mode = "pc"
Theme.Sizes = PC

-- Fonts -------------------------------------------------------------------------

local FONT_UI = "rbxasset://fonts/families/BuilderSans.json"
local FONT_MONO = "rbxasset://fonts/families/RobotoMono.json"
local fontCache = {}

function Theme.font(weight, mono)
	weight = weight or "Regular"
	local key = (mono and "m" or "u") .. weight
	local cached = fontCache[key]
	if cached then
		return cached
	end
	local ok, font = pcall(function()
		return Font.new(mono and FONT_MONO or FONT_UI, Enum.FontWeight[weight] or Enum.FontWeight.Regular)
	end)
	if not ok then
		ok, font = pcall(Font.fromEnum, mono and Enum.Font.RobotoMono or Enum.Font.BuilderSans)
	end
	if ok then
		fontCache[key] = font
		return font
	end
	return nil
end

-- Tokens ---------------------------------------------------------------------------

local Token = {}
Token.__index = Token

function Theme.c(name)
	return setmetatable({ kind = "c", name = name }, Token)
end

function Theme.s(name)
	return setmetatable({ kind = "s", name = name }, Token)
end

function Theme.f(fn)
	return setmetatable({ kind = "f", fn = fn }, Token)
end

function Theme.isToken(value)
	return getmetatable(value) == Token
end

local MISSING = Color3.fromRGB(255, 0, 255)

function Theme.resolve(token)
	if token.kind == "c" then
		local color = Theme.Colors[token.name]
		if color == nil then
			warn("[Robly] unknown colour token: " .. tostring(token.name))
			return MISSING
		end
		return color
	elseif token.kind == "s" then
		return Theme.Sizes[token.name]
	end
	return token.fn(Theme.Colors, Theme.Sizes, Theme.Mode)
end

-- Helpers that build common computed tokens.
local function num(value, sizes)
	if type(value) == "string" then
		return sizes[value]
	end
	return value or 0
end

function Theme.ud(scale, offset)
	if offset == nil then
		offset, scale = scale, 0
	end
	return Theme.f(function(_, s)
		return UDim.new(scale, num(offset, s))
	end)
end

function Theme.sz(xs, xo, ys, yo)
	return Theme.f(function(_, s)
		return UDim2.new(xs, num(xo, s), ys, num(yo, s))
	end)
end

function Theme.v2(x, y)
	return Theme.f(function(_, s)
		return Vector2.new(num(x, s), num(y, s))
	end)
end

-- Bindings -------------------------------------------------------------------------

local bindings = setmetatable({}, { __mode = "k" })

function Theme.bind(instance, prop, token)
	local props = bindings[instance]
	if not props then
		props = {}
		bindings[instance] = props
	end
	props[prop] = token
	instance[prop] = Theme.resolve(token)
end

function Theme.unbind(instance, prop)
	local props = bindings[instance]
	if props then
		props[prop] = nil
	end
end

-- Re-bind to a new token and animate to its value (state changes such as a
-- toggle turning on).
function Theme.set(instance, prop, token, preset)
	local props = bindings[instance]
	if not props then
		props = {}
		bindings[instance] = props
	end
	props[prop] = token
	Motion.tween(instance, { [prop] = Theme.resolve(token) }, preset or "color")
end

function Theme.refresh()
	for instance, props in pairs(bindings) do
		for prop, token in pairs(props) do
			local ok, value = pcall(Theme.resolve, token)
			if ok and value ~= nil then
				instance[prop] = value
			end
		end
	end
end

-- Theme switching ------------------------------------------------------------------

local function complete(colors)
	local out = table.clone(Theme.Presets.RobScript)
	for key, value in pairs(colors) do
		out[key] = value
	end
	return out
end

function Theme.apply(nameOrColors)
	if type(nameOrColors) == "string" then
		local found = Theme.Presets[nameOrColors]
		if not found then
			warn("[Robly] unknown theme: " .. nameOrColors)
			return false
		end
		Theme.Name = nameOrColors
		Theme.Colors = table.clone(found)
	elseif type(nameOrColors) == "table" then
		Theme.Name = "Custom"
		Theme.Colors = complete(nameOrColors)
	else
		return false
	end
	Theme.refresh()
	Theme.Changed:Fire("colors")
	return true
end

-- Change one token (theme editor). Accent edits keep readable ink colours.
function Theme.setToken(name, color)
	Theme.Colors[name] = color
	if name == "accent" then
		Theme.Colors.accentInk = Util.inkFor(color)
		Theme.Colors.accentPressed = Util.darken(color, 0.12)
	end
	Theme.Name = "Custom"
	Theme.refresh()
	Theme.Changed:Fire("colors")
end

function Theme.setMode(mode)
	local sizes = Theme.SizeSets[mode]
	if not sizes or Theme.Mode == mode then
		return
	end
	Theme.Mode = mode
	Theme.Sizes = sizes
	Theme.refresh()
	Theme.Changed:Fire("sizes")
end

-- Export / import as a short string ("robly1:<base64>") to share on Discord.
function Theme.export(colors, name)
	colors = colors or Theme.Colors
	local parts = { (tostring(name or Theme.Name):gsub(";", "")) }
	for _, key in ipairs(Theme.TokenOrder) do
		table.insert(parts, Util.toHex(colors[key] or MISSING))
	end
	return "robly1:" .. Util.base64Encode(table.concat(parts, ";"))
end

function Theme.import(text)
	text = Util.trim(tostring(text or ""))
	local payload = text:match("^robly1:(.+)$")
	if not payload then
		return nil, "format"
	end
	local ok, decoded = pcall(Util.base64Decode, payload)
	if not ok then
		return nil, "decode"
	end
	local parts = string.split(decoded, ";")
	if #parts < 4 then
		return nil, "short"
	end
	local colors = {}
	for index, key in ipairs(Theme.TokenOrder) do
		local hex = parts[index + 1]
		local color = hex and Util.hex(hex)
		if color then
			colors[key] = color
		end
	end
	if not colors.accent then
		return nil, "accent"
	end
	return complete(colors), parts[1]
end

function Theme.serialize()
	local out = { name = Theme.Name }
	if Theme.Name == "Custom" then
		out.colors = {}
		for key, color in pairs(Theme.Colors) do
			out.colors[key] = Util.toHex(color)
		end
	end
	return out
end

function Theme.deserialize(data)
	if type(data) ~= "table" then
		return
	end
	if data.name == "Custom" and type(data.colors) == "table" then
		local colors = {}
		for key, hex in pairs(data.colors) do
			colors[key] = Util.hex(hex)
		end
		Theme.apply(colors)
	elseif type(data.name) == "string" and Theme.Presets[data.name] then
		Theme.apply(data.name)
	end
end

return Theme
