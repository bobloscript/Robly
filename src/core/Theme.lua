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
--
-- A theme is a few BASE colours; every other token is DERIVED from them, so
-- changing the background (or the accent, or the text) repaints the whole
-- window: sidebar, cards, outlines, popups, tracks… Any derived token can still
-- be overridden on its own (theme editor, "All colours"); overrides survive
-- base changes until the theme is reset.

Theme.BaseKeys = { "accent", "bg", "text", "success", "warning", "danger" }

-- Editable in the theme editor's main list (base + the most visible derived ones)
Theme.MainKeys = { "accent", "bg", "nav", "surface", "border", "text" }

-- Every token, in export / "All colours" order.
Theme.TokenOrder = {
	"accent", "bg", "nav", "surface", "border", "text",
	"raised", "overlay", "sunken", "selected", "segment", "borderStrong", "divider",
	"textMuted", "textSubtle", "accentInk", "accentPressed", "track", "toggleOff",
	"knobOn", "knobOff", "checkBorder", "success", "warning", "danger", "dangerInk",
	"tooltip", "tooltipText", "backdrop", "code", "codeText",
}

local function isBase(key)
	return table.find(Theme.BaseKeys, key) ~= nil
end
Theme.isBase = isBase

-- Builds the full token table from a spec (base colours + optional overrides).
function Theme.derive(spec)
	local function get(key, fallback)
		local value = spec[key]
		if typeof(value) == "Color3" then
			return value
		end
		return Util.hex(value) or fallback
	end
	local bg = get("bg", Color3.fromRGB(18, 18, 22))
	local text = get("text", Color3.fromRGB(242, 242, 245))
	local accent = get("accent", Color3.fromRGB(255, 59, 127))
	local dark = Util.luminance(bg) < 0.4
	local black = Color3.new(0, 0, 0)
	local white = Color3.new(1, 1, 1)
	local c = {
		accent = accent,
		bg = bg,
		text = text,
		success = get("success", Color3.fromRGB(52, 211, 153)),
		warning = get("warning", Color3.fromRGB(251, 191, 36)),
		danger = get("danger", Color3.fromRGB(255, 90, 90)),
	}
	local function d(key, value)
		c[key] = get(key, nil) or value
	end
	-- surfaces step away from the background towards the text colour
	d("nav", dark and bg:Lerp(black, 0.18) or bg:Lerp(text, 0.045))
	d("surface", bg:Lerp(text, dark and 0.028 or 0.035))
	d("border", bg:Lerp(text, dark and 0.075 or 0.1))
	d("raised", c.surface:Lerp(text, dark and 0.055 or 0.05))
	d("overlay", dark and bg:Lerp(text, 0.045) or bg)
	d("sunken", dark and c.nav or bg:Lerp(text, 0.07))
	d("selected", c.nav:Lerp(text, dark and 0.085 or 0.08))
	d("segment", dark and c.surface:Lerp(text, 0.09) or white)
	d("borderStrong", c.border:Lerp(text, dark and 0.035 or 0.08))
	d("divider", bg:Lerp(c.border, 0.75))
	d("textMuted", text:Lerp(bg, 0.34))
	d("textSubtle", text:Lerp(bg, 0.47))
	d("accentInk", Util.inkFor(accent))
	d("accentPressed", Util.darken(accent, 0.12))
	d("track", c.borderStrong)
	d("toggleOff", c.surface:Lerp(text, dark and 0.15 or 0.16))
	-- a pale accent (Graphite) needs a dark knob to stay visible
	d("knobOn", Util.contrast(accent, white) < 1.6 and bg or white)
	d("knobOff", white)
	d("checkBorder", c.surface:Lerp(text, dark and 0.22 or 0.28))
	d("dangerInk", Util.inkFor(c.danger))
	d("tooltip", text)
	d("tooltipText", bg)
	d("backdrop", bg:Lerp(black, 0.6))
	d("code", dark and c.nav:Lerp(black, 0.2) or c.sunken)
	d("codeText", text:Lerp(bg, 0.12))
	return c
end

-- Presets are specs; Theme.Presets holds their derived colours for previews.
Theme.PresetSpecs = {
	RobScript = { accent = "FF3B7F", bg = "121216", text = "F2F2F5", accentInk = "1A0610" },
	Light = { accent = "E0245E", bg = "FFFFFF", text = "16161A", success = "0E9F6E", warning = "B7791F", danger = "E5484D" },
	Graphite = { accent = "E6E6E8", bg = "1B1B1D", text = "EDEDEE" },
	Midnight = { accent = "4C8DFF", bg = "0E1320", text = "E8EDF7" },
}
Theme.Presets = {}
for name, spec in pairs(Theme.PresetSpecs) do
	Theme.Presets[name] = Theme.derive(spec)
end

Theme.PresetOrder = { "RobScript", "Light", "Graphite", "Midnight" }

Theme.Name = "RobScript"
Theme.Spec = table.clone(Theme.PresetSpecs.RobScript)
Theme.Colors = Theme.derive(Theme.Spec)

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

-- Strong tables on purpose: Roblox may garbage-collect the Lua wrapper of an
-- Instance that is still alive in the game, so a weak-keyed table would
-- silently lose bindings of labels nobody keeps a reference to. Entries are
-- removed when the instance is destroyed.
local bindings = {}
-- colour tweens started by Theme.set; cancelled on refresh so an old tween
-- can't finish on a colour from the previous theme
local tweens = {}
local watched = {}

local function watch(instance)
	if watched[instance] then
		return
	end
	watched[instance] = true
	pcall(function()
		instance.Destroying:Connect(function()
			bindings[instance] = nil
			tweens[instance] = nil
			watched[instance] = nil
		end)
	end)
end
Theme.watchDestroy = watch

function Theme.bind(instance, prop, token)
	local props = bindings[instance]
	if not props then
		props = {}
		bindings[instance] = props
		watch(instance)
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
		watch(instance)
	end
	props[prop] = token
	local tween = Motion.tween(instance, { [prop] = Theme.resolve(token) }, preset or "color")
	if tween then
		local running = tweens[instance]
		if not running then
			running = {}
			tweens[instance] = running
		end
		running[prop] = tween
	end
end

function Theme.refresh()
	for _, running in pairs(tweens) do
		for _, tween in pairs(running) do
			pcall(tween.Cancel, tween)
		end
	end
	table.clear(tweens)
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

local function toSpec(colors)
	local spec = {}
	for key, value in pairs(colors) do
		local color = typeof(value) == "Color3" and value or Util.hex(value)
		if color then
			spec[key] = color
		end
	end
	return spec
end

local function commit()
	Theme.Colors = Theme.derive(Theme.Spec)
	Theme.refresh()
	Theme.Changed:Fire("colors")
end

-- apply("Midnight") · apply({ accent = …, bg = … }) (missing base colours come
-- from RobScript, everything else is derived)
function Theme.apply(nameOrColors)
	if type(nameOrColors) == "string" then
		local found = Theme.PresetSpecs[nameOrColors]
		if not found then
			warn("[Robly] unknown theme: " .. nameOrColors)
			return false
		end
		Theme.Name = nameOrColors
		Theme.Spec = toSpec(found)
	elseif type(nameOrColors) == "table" then
		local spec = toSpec(Theme.PresetSpecs.RobScript)
		spec.accentInk = nil
		for key, value in pairs(toSpec(nameOrColors)) do
			spec[key] = value
		end
		Theme.Name = "Custom"
		Theme.Spec = spec
	else
		return false
	end
	commit()
	return true
end

-- Change one token (theme editor). A base colour re-derives everything that
-- isn't overridden; any other token becomes an override.
function Theme.setToken(name, color)
	Theme.Spec[name] = color
	if name == "accent" then
		Theme.Spec.accentInk = nil
		Theme.Spec.accentPressed = nil
		Theme.Spec.knobOn = nil
	end
	Theme.Name = "Custom"
	commit()
end

-- Drop the override of a derived token (back to "follows the base colours").
function Theme.clearToken(name)
	if not isBase(name) then
		Theme.Spec[name] = nil
		commit()
	end
end

function Theme.isOverridden(name)
	return not isBase(name) and Theme.Spec[name] ~= nil
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

-- Export / import as a short string to share on Discord:
--   robly2:<base64 of "name;key=RRGGBB;key=RRGGBB…"> — only the spec
--   robly1:<base64 of "name;hex;hex…">            — old full list, still imported
function Theme.export(spec, name)
	spec = spec or Theme.Spec
	local parts = { (tostring(name or Theme.Name):gsub("[;=]", "")) }
	for _, key in ipairs(Theme.TokenOrder) do
		local value = spec[key]
		if typeof(value) == "Color3" then
			table.insert(parts, key .. "=" .. Util.toHex(value))
		end
	end
	return "robly2:" .. Util.base64Encode(table.concat(parts, ";"))
end

function Theme.import(text)
	text = Util.trim(tostring(text or ""))
	local version, payload = text:match("^robly([12]):(.+)$")
	if not payload then
		return nil, "format"
	end
	local ok, decoded = pcall(Util.base64Decode, payload)
	if not ok then
		return nil, "decode"
	end
	local parts = string.split(decoded, ";")
	local spec = {}
	if version == "2" then
		for index = 2, #parts do
			local key, hex = parts[index]:match("^(%w+)=(%x+)$")
			if key and table.find(Theme.TokenOrder, key) then
				spec[key] = Util.hex(hex)
			end
		end
	else
		local old = {
			"accent", "bg", "nav", "surface", "raised", "overlay", "sunken", "selected", "segment",
			"border", "borderStrong", "divider", "text", "textMuted", "textSubtle",
			"accentInk", "accentPressed", "track", "toggleOff", "knobOn", "knobOff", "checkBorder",
			"success", "warning", "danger", "dangerInk", "tooltip", "tooltipText", "backdrop", "code", "codeText",
		}
		for index, key in ipairs(old) do
			local color = parts[index + 1] and Util.hex(parts[index + 1])
			if color then
				spec[key] = color
			end
		end
	end
	if not (spec.accent and spec.bg and spec.text) then
		return nil, "incomplete"
	end
	return spec, parts[1]
end

function Theme.serialize()
	local out = { name = Theme.Name }
	if Theme.Name == "Custom" then
		out.spec = {}
		for key, color in pairs(Theme.Spec) do
			out.spec[key] = Util.toHex(color)
		end
	end
	return out
end

function Theme.deserialize(data)
	if type(data) ~= "table" then
		return
	end
	local raw = data.spec or data.colors -- "colors" = 1.0 full list
	if data.name == "Custom" and type(raw) == "table" then
		local spec = toSpec(raw)
		if data.colors and not data.spec then
			-- 1.0 saved every token; keep only the base so everything follows
			local base = {}
			for _, key in ipairs(Theme.BaseKeys) do
				base[key] = spec[key]
			end
			spec = base
		end
		Theme.Name = "Custom"
		Theme.Spec = spec
		commit()
	elseif type(data.name) == "string" and Theme.PresetSpecs[data.name] then
		Theme.apply(data.name)
	end
end

return Theme
