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

-- Switch theme for every window: "RobScript", "Light", "Graphite", "Midnight",
-- a custom registered name, or a colour table.
function Robly:SetTheme(theme)
	Theme.apply(theme)
end

-- Register a theme preset: colours as Color3 or "#RRGGBB"; missing tokens
-- fall back to RobScript.
function Robly:AddTheme(name, colors)
	local out = table.clone(Theme.Presets.RobScript)
	for key, value in pairs(colors) do
		out[key] = Util.hex(value) or value
	end
	if colors.accent and not colors.accentInk then
		out.accentInk = Util.inkFor(out.accent)
		out.accentPressed = Util.darken(out.accent, 0.12)
	end
	Theme.Presets[name] = out
	if not table.find(Theme.PresetOrder, name) then
		table.insert(Theme.PresetOrder, name)
	end
	return out
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
