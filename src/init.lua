-- Robly — UI library for Roblox scripts by RobScript (https://robscript.com)
-- Public domain (The Unlicense). See README.md for the full API.

local Theme = import("core/Theme")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Localization = import("core/Localization")
local Util = import("util/Util")
local Window = import("ui/Window")

local Robly = {
	Version = "__VERSION__",
	Windows = {},
	Themes = Theme.Presets,
	Effects = Theme.Effects,
	ThemeOrder = Theme.PresetOrder,
	Icons = Icons.Data,
	L = Localization.L,
}

-- Robly:CreateWindow({ Title, Subtitle, Logo, Folder, Theme, Language, ToggleKey, Branding, ... })
function Robly:CreateWindow(options)
	local window = Window.new(self, options)
	table.insert(self.Windows, window)
	return window
end
Robly.Window = Robly.CreateWindow
Robly.New = Robly.CreateWindow

function Robly:_windowClosed(window)
	local index = table.find(self.Windows, window)
	if index then
		table.remove(self.Windows, index)
	end
end

-- Switch theme for every window: a preset name (see Robly.Themes / the 18
-- built-in presets), a custom registered name, or a colour table.
function Robly:SetTheme(theme)
	Theme.apply(theme)
end

-- Register a theme preset: colours as Color3 or "#RRGGBB"; missing tokens
-- fall back to RobScript.
function Robly:AddTheme(name, colors)
	-- a theme is its base colours (accent, bg, text, …); the rest is derived,
	-- and any token given here overrides the derived value
	local spec = {}
	for key, value in pairs(Theme.PresetSpecs.RobScript) do
		if Theme.isBase(key) then
			spec[key] = value
		end
	end
	for key, value in pairs(colors) do
		if key == "Effect" or key == "effect" then
			Theme.PresetEffects[name] = value
		else
			spec[key] = typeof(value) == "Color3" and value or Util.hex(value)
		end
	end
	Theme.PresetSpecs[name] = spec
	local out = Theme.derive(spec)
	Theme.Presets[name] = out
	if not table.find(Theme.PresetOrder, name) then
		table.insert(Theme.PresetOrder, name)
	end
	return out
end

-- Background effect inside every window: "None", "Aurora", "Stars", "Snow",
-- "Grid", "Gradient".
function Robly:SetEffect(effect)
	Theme.setEffect(effect)
end

-- Glass: panels become translucent so the background effect shows through.
function Robly:SetGlass(enabled)
	Theme.setGlass(enabled)
end

function Robly:SetAnimations(mode)
	Motion.setMode(mode)
end

function Robly:Notify(options)
	local window = self.Windows[#self.Windows]
	if window then
		return window:Notify(options)
	end
	return nil
end

function Robly:Destroy()
	for _, window in ipairs(table.clone(self.Windows)) do
		window:Destroy()
	end
end

return Robly
