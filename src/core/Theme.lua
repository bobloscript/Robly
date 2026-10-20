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

Theme.BaseKeys = { "accent", "accent2", "bg", "text", "success", "warning", "danger" }

-- Editable in the theme editor's main list (base + the most visible derived ones)
Theme.MainKeys = { "accent", "accent2", "bg", "nav", "surface", "border", "text" }

-- Every token, in export / "All colours" order.
Theme.TokenOrder = {
	"accent", "accent2", "bg", "nav", "surface", "border", "text",
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
	local h, sat, val = accent:ToHSV()
	local c = {
		accent = accent,
		-- second accent for gradients and background effects (default: a
		-- neighbouring hue of the accent)
		accent2 = get("accent2", Color3.fromHSV((h + 0.09) % 1, math.min(1, sat * 0.95), math.min(1, val * 1.02))),
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
-- Each preset also has a default background effect.
local PRESETS = {
	{ "RobScript", { accent = "FF3B7F", accent2 = "9B5CFF", bg = "121216", text = "F2F2F5", accentInk = "1A0610" }, "Aurora" },
	{ "Light", { accent = "E0245E", accent2 = "FF7A59", bg = "FFFFFF", text = "16161A", success = "0E9F6E", warning = "B7791F", danger = "E5484D" }, "None" },
	{ "Graphite", { accent = "E6E6E8", accent2 = "9A9AA2", bg = "1B1B1D", text = "EDEDEE" }, "Grid" },
	{ "Midnight", { accent = "4C8DFF", accent2 = "8B5CF6", bg = "0E1320", text = "E8EDF7" }, "Stars" },
	{ "Sakura", { accent = "FF8FB8", accent2 = "FFC2D6", bg = "1A1216", text = "F7EEF2" }, "Petals" },
	{ "Ocean", { accent = "22D3EE", accent2 = "3B82F6", bg = "0A1620", text = "E6F4F8" }, "Aurora" },
	{ "Matcha", { accent = "7BD389", accent2 = "C3E88D", bg = "111712", text = "ECF3EC" }, "Fireflies" },
	{ "Sunset", { accent = "FF7A45", accent2 = "FF3D7F", bg = "1A1012", text = "FBEDE7" }, "Gradient" },
	{ "Amber", { accent = "FFB020", accent2 = "FF7A00", bg = "16130C", text = "F7F1E3" }, "Gradient" },
	{ "Crimson", { accent = "FF4D4D", accent2 = "B3123A", bg = "140C0D", text = "F5ECEC" }, "Grid" },
	{ "Cyber", { accent = "00F0FF", accent2 = "FF00C8", bg = "0A0A12", text = "E8F7FF" }, "Grid" },
	{ "Synthwave", { accent = "FF2E97", accent2 = "7B61FF", bg = "140A24", text = "F5E9FF" }, "Stars" },
	{ "Dracula", { accent = "BD93F9", accent2 = "FF79C6", bg = "1E1F29", text = "F8F8F2" }, "Stars" },
	{ "Nord", { accent = "88C0D0", accent2 = "81A1C1", bg = "1F2430", text = "ECEFF4" }, "Snow" },
	{ "Frost", { accent = "7DD3FC", accent2 = "C4B5FD", bg = "0D1117", text = "E6EDF3" }, "Snow" },
	{ "Lavender", { accent = "B794F6", accent2 = "F0ABFC", bg = "15121D", text = "F3EEFB" }, "Aurora" },
	{ "Coffee", { accent = "D4A373", accent2 = "A47148", bg = "16110D", text = "F1E9E1" }, "Particles" },
	{ "Mono", { accent = "FFFFFF", accent2 = "8A8A8A", bg = "0E0E0E", text = "F2F2F2" }, "None" },
}
Theme.PresetSpecs = {}
Theme.PresetEffects = {}
Theme.PresetOrder = {}
for _, entry in ipairs(PRESETS) do
	Theme.PresetSpecs[entry[1]] = entry[2]
	Theme.PresetEffects[entry[1]] = entry[3]
	table.insert(Theme.PresetOrder, entry[1])
end
Theme.Presets = {}
for name, spec in pairs(Theme.PresetSpecs) do
	Theme.Presets[name] = Theme.derive(spec)
end

-- Background effect inside the window and "glass" (translucent panels).
Theme.Effects = { "None", "Aurora", "Stars", "Snow", "Petals", "Fireflies", "Particles", "Grid", "Gradient" }
Theme.Effect = "Aurora"
Theme.Glass = true
-- 0.25 … 2: multiplies how opaque the effect is (1 = default)
Theme.EffectStrength = 1

function Theme.setEffectStrength(value)
	Theme.EffectStrength = math.clamp(tonumber(value) or 1, 0.25, 2)
	Theme.Changed:Fire("effect")
end

function Theme.setEffect(effect)
	if not table.find(Theme.Effects, effect) then
		effect = "None"
	end
	Theme.Effect = effect
	Theme.refresh()
	Theme.Changed:Fire("effect")
end

function Theme.setGlass(enabled)
	Theme.Glass = enabled == true
	Theme.refresh()
	Theme.Changed:Fire("effect")
end

-- Transparency for panels that let the background effect show through.
function Theme.glass(amount)
	return Theme.f(function()
		if Theme.Glass and Theme.Effect ~= "None" then
			return amount or 0.3
		end
		return 0
	end)
end

-- Accent → accent2 gradient (UIGradient.Color); the element itself must be white.
function Theme.gradient()
	return Theme.f(function(c)
		return ColorSequence.new(c.accent, c.accent2)
	end)
end

-- Card outline: accent in the top-left corner fading into the normal border.
function Theme.edge()
	return Theme.f(function(c)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, c.accent),
			ColorSequenceKeypoint.new(0.35, c.border),
			ColorSequenceKeypoint.new(1, c.border),
		})
	end)
end

Theme.Name = "RobScript"
Theme.Spec = table.clone(Theme.PresetSpecs.RobScript)
Theme.Colors = Theme.derive(Theme.Spec)

-- Size tokens ------------------------------------------------------------------

-- PC has two densities: "compact" (default, Obsidian-like dense rows) and
-- "comfortable" (the roomier original). Touch sizes keep 44 px targets.
local PC_COMFORTABLE = {
	header = 56, sidebar = 200, navItem = 38, rail = 56, tabbar = 60,
	row = 46, rowDesc = 54, control = 32, button = 34, input = 36,
	toggleW = 44, toggleH = 26, knob = 22, checkbox = 20,
	track = 6, sliderKnob = 18, sliderHit = 24, segment = 28, stepperBtn = 32, chip = 30, hit = 32,
	font = 14, fontDesc = 12, fontSmall = 11, fontSection = 14, fontTitle = 22, fontHeader = 14,
	padX = 14, padY = 7, gap = 14, contentX = 22, contentTop = 18, contentBottom = 20, sectionGap = 12,
	rWindow = 16, rSection = 12, rControl = 9, rSmall = 8, rBadge = 6,
	icon = 18, iconSmall = 16, item = 34, toastWidth = 280, scrollBar = 3,
	groupHeader = 40, groupPad = 4, columnGap = 12, dividers = true,
	touch = false, pageHeader = true, dropdownFlat = false,
}

local PC = {
	header = 48, sidebar = 186, navItem = 34, rail = 56, tabbar = 60,
	row = 36, rowDesc = 44, control = 26, button = 30, input = 30,
	toggleW = 34, toggleH = 20, knob = 16, checkbox = 16,
	track = 4, sliderKnob = 14, sliderHit = 18, segment = 24, stepperBtn = 26, chip = 24, hit = 30,
	font = 13, fontDesc = 11, fontSmall = 11, fontSection = 13, fontTitle = 18, fontHeader = 13,
	padX = 12, padY = 5, gap = 12, contentX = 14, contentTop = 12, contentBottom = 14, sectionGap = 10,
	rWindow = 12, rSection = 10, rControl = 7, rSmall = 6, rBadge = 5,
	icon = 16, iconSmall = 14, item = 28, toastWidth = 270, scrollBar = 3,
	groupHeader = 34, groupPad = 3, columnGap = 10, dividers = false,
	touch = false, pageHeader = true, dropdownFlat = false,
}

local PHONE = {
	header = 44, sidebar = 56, navItem = 44, rail = 56, tabbar = 60,
	row = 52, rowDesc = 56, control = 44, button = 44, input = 44,
	toggleW = 51, toggleH = 31, knob = 27, checkbox = 24,
	track = 6, sliderKnob = 28, sliderHit = 44, segment = 40, stepperBtn = 44, chip = 36, hit = 44,
	font = 15, fontDesc = 13, fontSmall = 12, fontSection = 14, fontTitle = 16, fontHeader = 16,
	padX = 12, padY = 4, gap = 12, contentX = 12, contentTop = 0, contentBottom = 12, sectionGap = 8,
	rWindow = 18, rSection = 14, rControl = 10, rSmall = 10, rBadge = 6,
	icon = 20, iconSmall = 18, item = 44, toastWidth = 300, scrollBar = 0,
	groupHeader = 44, groupPad = 2, columnGap = 8, dividers = true,
	touch = true, pageHeader = false, dropdownFlat = true,
}

local TABLET = Util.merge(PHONE, {
	header = 52, fontTitle = 18, contentX = 16, contentTop = 4, contentBottom = 16,
	rWindow = 22, rSection = 16, padX = 14, sectionGap = 10,
})

Theme.Densities = { compact = PC, comfortable = PC_COMFORTABLE }
Theme.Density = "compact"
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
		Theme.Effect = Theme.PresetEffects[nameOrColors] or Theme.Effect
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

function Theme.setDensity(density)
	local sizes = Theme.Densities[density]
	if not sizes or Theme.Density == density then
		return
	end
	Theme.Density = density
	Theme.SizeSets.pc = sizes
	if Theme.Mode == "pc" then
		Theme.Sizes = sizes
		Theme.refresh()
		Theme.Changed:Fire("density")
	end
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
	local out = { name = Theme.Name, effect = Theme.Effect, glass = Theme.Glass, strength = Theme.EffectStrength }
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
	if type(data.effect) == "string" then
		Theme.Effect = table.find(Theme.Effects, data.effect) and data.effect or Theme.Effect
	end
	if data.glass ~= nil then
		Theme.Glass = data.glass == true
	end
	if tonumber(data.strength) then
		Theme.EffectStrength = math.clamp(tonumber(data.strength), 0.25, 2)
	end
	local raw = data.spec or data.colors -- "colors" = 1.0 full list
	if data.name == "Custom" and type(raw) == "table" then
		local effect = Theme.Effect
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
		local effect = Theme.Effect
		Theme.apply(data.name)
		if type(data.effect) == "string" then
			Theme.setEffect(effect)
		end
	end
end

return Theme
