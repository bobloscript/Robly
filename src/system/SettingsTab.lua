-- Built-in "Settings" tab, made with Robly's own controls:
-- theme (presets + live editor + export/import), configs (profiles,
-- autosave, autoload), interface (show/hide key, language, animations,
-- keybind panel on PC, quick buttons on touch), about.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Localization = import("core/Localization")
local Compat = import("util/Compat")
local Util = import("util/Util")
local Control = import("controls/Base")

local New = Create.New
local C, S = Theme.c, Theme.s
local L = Localization.L

local SettingsTab = {}
SettingsTab.__index = SettingsTab

local function pcOnly(_, mode)
	return mode == "pc"
end

local function touchOnly(_, mode)
	return mode ~= "pc"
end

local EDITABLE = {
	{ key = "accent", text = L("accent") },
	{ key = "bg", text = L("background") },
	{ key = "surface", text = L("surface") },
	{ key = "text", text = L("text") },
}

function SettingsTab.new(window)
	local self = setmetatable({}, SettingsTab)
	self.Window = window
	local tab = window:_internalTab({ Title = L("settings"), Icon = "sliders", Id = "robly_settings" })
	self.Tab = tab
	self:_buildTheme()
	self:_buildConfigs()
	self:_buildInterface()
	if window.Branding then
		self:_buildAbout()
	end
	return self
end

-- Theme ---------------------------------------------------------------------------------

local ThemeGrid = Control.extend("ThemeGrid")

local function miniPreview(colors)
	local card = New("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = colors.bg,
	}, { Create.corner(10), Create.list("Horizontal", 0) })
	New("Frame", {
		Size = UDim2.new(0, 22, 1, 0),
		BackgroundColor3 = colors.nav,
		Parent = card,
	}, { Create.corner(10), Create.pad(8, 5), Create.list("Vertical", 4),
		New("Frame", { Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = colors.raised }, { Create.corner(2) }),
		New("Frame", { Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = colors.surface, LayoutOrder = 2 }, { Create.corner(2) }),
	})
	local body = New("Frame", { Size = UDim2.fromScale(0, 1), LayoutOrder = 2, Parent = card }, {
		Create.flex(), Create.pad(8), Create.list("Vertical", 6),
	})
	New("Frame", { Size = UDim2.new(0.6, 0, 0, 5), BackgroundColor3 = colors.text, Parent = body }, { Create.corner(2) })
	local row = New("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = colors.surface,
		LayoutOrder = 2,
		Parent = body,
	}, { Create.corner(5), Create.pad(0, 5), Create.list("Horizontal", 4, { valign = "Center" }) })
	New("Frame", { Size = UDim2.new(0, 0, 0, 4), BackgroundColor3 = colors.textSubtle, Parent = row }, { Create.corner(2), Create.flex() })
	New("Frame", { Size = UDim2.fromOffset(16, 10), BackgroundColor3 = colors.accent, LayoutOrder = 2, Parent = row }, { Create.corner("full") })
	return card
end

function SettingsTab:_buildTheme()
	local window = self.Window
	local section = self.Tab:Section({ Title = L("theme") })
	local grid = Control.new(section, { Title = L("theme") }, { class = ThemeGrid, kind = "ThemeGrid", layout = "custom", searchable = false })
	grid.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
	local holder = New("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = grid.Inner,
	}, { Create.list("Horizontal", 10) })
	local cards = {}
	for index, name in ipairs(Theme.PresetOrder) do
		local colors = Theme.Presets[name]
		local button = New("TextButton", {
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
			Parent = holder,
		}, { Create.flex(), Create.list("Vertical", 6) })
		local preview = miniPreview(colors)
		preview.Parent = button
		local stroke = Create.stroke("accent", 2)
		stroke.Parent = preview
		local label = New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16),
			Text = name == "RobScript" and "RobScript" or name,
			TextSize = 12.5,
			Weight = "SemiBold",
			LayoutOrder = 2,
			Parent = button,
		})
		label.TextTruncate = Enum.TextTruncate.AtEnd
		Motion.pressable(button, preview, 0.96, grid.Maid)
		grid.Maid:Add(button.Activated:Connect(function()
			window:SetTheme(name)
		end))
		cards[name] = { stroke = stroke, label = label }
	end
	local function refresh()
		for name, card in pairs(cards) do
			local on = Theme.Name == name
			card.stroke.Transparency = on and 0 or 1
		end
	end
	refresh()
	grid.Maid:Add(Theme.Changed:Connect(refresh))
	local function relabel()
		cards.Light.label.Text = window.Loc:Get({ en = "Light", ru = "Светлая", es = "Clara", pt = "Clara", de = "Hell", fr = "Clair" })
		cards.Graphite.label.Text = window.Loc:Get({ en = "Graphite", ru = "Графит", es = "Grafito", pt = "Grafite", de = "Graphit", fr = "Graphite" })
		cards.Midnight.label.Text = window.Loc:Get({ en = "Midnight", ru = "Полночь", es = "Medianoche", pt = "Meia-noite", de = "Mitternacht", fr = "Minuit" })
	end
	relabel()
	grid.Maid:Add(window.Loc.Changed:Connect(relabel))

	-- Live editor
	local pickers = {}
	local syncing = false
	local function addPicker(target, key, text)
		local picker = target:ColorPicker({
			Title = text,
			Flag = "robly:color." .. key,
			Default = Theme.Colors[key],
			Save = false,
		})
		picker.Maid:Add(picker.Changed:Connect(function(color, _, source)
			if not syncing and source ~= "silent" and typeof(color) == "Color3" then
				Theme.setToken(key, color)
			end
		end))
		pickers[key] = picker
	end
	for _, entry in ipairs(EDITABLE) do
		addPicker(section, entry.key, entry.text)
	end
	section:Buttons({
		{ Title = L("export"), Icon = "upload", Callback = function()
			local text = Theme.export()
			if Compat.clipboard(text) then
				window:Notify({ Title = L("theme_copied"), Content = L("theme_copied_desc"), Type = "success", Duration = 3 })
			else
				window:Dialog({ Title = L("copy_failed"), Input = { Default = text, Mono = true }, Buttons = { { Text = L("ok"), Variant = "Primary" } } })
			end
		end },
		{ Title = L("import"), Icon = "download", Callback = function()
			window:Dialog({
				Title = L("import_theme"),
				Input = { Placeholder = L("paste_theme"), Mono = true },
				Buttons = {
					{ Text = L("cancel"), Variant = "Secondary" },
					{ Text = L("import"), Variant = "Primary", Callback = function(text)
						local colors = Theme.import(text)
						if not colors then
							window:Notify({ Title = L("theme_invalid"), Type = "error", Duration = 3 })
							return false
						end
						window:SetTheme(colors)
						window:Notify({ Title = L("theme_imported"), Type = "success", Duration = 2 })
						return true
					end },
				},
			})
		end },
	})

	local more = self.Tab:Section({ Title = L("more_colors"), Collapsed = true })
	for _, key in ipairs(Theme.TokenOrder) do
		local editable = false
		for _, entry in ipairs(EDITABLE) do
			if entry.key == key then
				editable = true
			end
		end
		if not editable then
			addPicker(more, key, key)
		end
	end
	more:Button({ Title = L("reset_theme"), Variant = "Secondary", Icon = "refresh", Callback = function()
		window:SetTheme("RobScript")
	end })

	self.Maid = grid.Maid
	grid.Maid:Add(Theme.Changed:Connect(function(what)
		if what ~= "colors" then
			return
		end
		syncing = true
		for key, picker in pairs(pickers) do
			if Theme.Colors[key] then
				window.Store:Set(picker.Flag, Theme.Colors[key], "silent")
			end
		end
		syncing = false
	end))
end

-- Configs --------------------------------------------------------------------------------

local function relativeTime(loc, saved)
	if not saved then
		return nil
	end
	local diff = os.time() - saved
	if diff < 60 then
		return loc:Lib("just_now")
	elseif diff < 3600 then
		return loc:Lib("minutes_ago", { n = math.floor(diff / 60) })
	elseif diff < 86400 then
		return loc:Lib("hours_ago", { n = math.floor(diff / 3600) })
	elseif diff < 172800 then
		return loc:Lib("yesterday")
	end
	return loc:Lib("days_ago", { n = math.floor(diff / 86400) })
end

local ProfileRow = Control.extend("Profile")

function SettingsTab:_buildConfigs()
	local window = self.Window
	local config = window.Config
	local loc = window.Loc
	local section = self.Tab:Section({ Title = L("configs") })
	self.ConfigSection = section
	local list = {}

	local function rebuild()
		for _, row in ipairs(list) do
			row:Destroy()
		end
		table.clear(list)
		for _, name in ipairs(config:List()) do
			local info = config:Info(name)
			local desc = function()
				local parts = {}
				if info.Active then
					table.insert(parts, loc:Lib("active"))
				end
				if info.Autoload then
					table.insert(parts, loc:Lib("autoload"))
				end
				local time = relativeTime(loc, info.Saved)
				if time then
					table.insert(parts, time)
				end
				return table.concat(parts, " · ")
			end
			local row = Control.new(section, { Title = function()
				return name
			end, Description = desc }, { class = ProfileRow, kind = "Profile", rowClick = true, searchable = false })
			row.Holder.LayoutOrder = -100 + #list
			if info.Active then
				local check = Icons.new("check", 18, C("accent"))
				check.Frame.LayoutOrder = 1
				check.Frame.Parent = row.Right
			end
			local more = New("TextButton", {
				Size = Theme.f(function(_, s)
					return UDim2.fromOffset(s.touch and 44 or 32, s.touch and 44 or 32)
				end),
				BackgroundColor3 = C("raised"),
				LayoutOrder = 2,
				Parent = row.Right,
			}, { Create.corner(9) })
			Icons.new("more", 16, C("textMuted"), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }).Frame.Parent = more
			Motion.pressable(more, nil, 0.9, row.Maid)
			local function load()
				local ok, count = config:Load(name)
				if ok then
					window:Notify({ Title = L("config_loaded"), Content = L("profile_values"), ContentVars = { name = name, n = count }, Type = "success", Duration = 3 })
				end
			end
			row.Maid:Add(row.Hit.Activated:Connect(load))
			row.Maid:Add(more.Activated:Connect(function()
				window.Popup:Menu(more, {
					{ Text = L("load"), Icon = "download", Callback = load },
					{ Text = L("overwrite"), Icon = "save", Callback = function()
						config:Save(name)
						window:Notify({ Title = L("config_saved"), Content = L("profile_saved"), ContentVars = { name = name }, Type = "success", Duration = 2 })
					end },
					{ Text = L("set_autoload"), Icon = "star", Checked = info.Autoload, Callback = function()
						config:SetAutoload(name)
					end },
					"divider",
					{ Text = L("delete"), Icon = "trash", Danger = true, Callback = function()
						window:Dialog({
							Title = L("delete_profile_q"),
							Vars = { name = name },
							Content = L("delete_profile_desc"),
							Buttons = {
								{ Text = L("cancel"), Variant = "Secondary" },
								{ Text = L("delete"), Variant = "Danger", Callback = function()
									config:Delete(name)
								end },
							},
						})
					end },
				}, { width = 240 })
			end))
			table.insert(list, row)
		end
	end

	section:Button({ Title = L("new_profile"), Icon = "plus", Variant = "Secondary", Callback = function()
		window:Dialog({
			Title = L("new_profile"),
			Input = { Placeholder = L("profile_name") },
			Buttons = {
				{ Text = L("cancel"), Variant = "Secondary" },
				{ Text = L("create"), Variant = "Primary", Callback = function(text)
					local name = Util.trim(text or "")
					if name == "" then
						return false
					end
					config:Save(name)
					window:Notify({ Title = L("config_saved"), Content = L("profile_saved"), ContentVars = { name = name }, Type = "success", Duration = 2 })
					return true
				end },
			},
		})
	end })
	local autosave = section:Toggle({
		Title = L("autosave"),
		Description = L("autosave_desc"),
		Flag = "robly:autosave",
		Default = config.Meta.autosave ~= false,
		Save = false,
		Callback = function(value)
			config:SetAutosave(value)
		end,
	})
	local _ = autosave
	rebuild()
	window.Maid:Add(config.Changed:Connect(function(kind)
		if kind == "list" then
			rebuild()
		end
	end))
	window.Maid:Add(loc.Changed:Connect(rebuild))
end

-- Interface ------------------------------------------------------------------------------

function SettingsTab:_buildInterface()
	local window = self.Window
	local loc = window.Loc
	local section = self.Tab:Section({ Title = L("interface") })

	section:Keybind({
		Title = L("toggle_key"),
		HudTitle = L("show_window"),
		Flag = "robly:toggleKey",
		Default = window.Options.ToggleKey or "RightShift",
		System = true,
		Mode = "Action",
		VisibleWhen = pcOnly,
		Callback = function()
			window:Toggle()
		end,
	})
	if loc:IsMultilingual() then
		local options = {}
		for _, language in ipairs(loc:Languages()) do
			table.insert(options, { Value = language.Code, Text = language.Name })
		end
		local dropdown = section:Dropdown({
			Title = L("language"),
			Icon = "globe",
			Flag = "robly:language",
			Options = options,
			Default = loc.Current,
			Save = false,
			Callback = function(code)
				if code and code ~= loc.Current then
					window:SetLanguage(code)
				end
			end,
		})
		window.Maid:Add(loc.Changed:Connect(function(code)
			window.Store:Set(dropdown.Flag, code, "silent")
		end))
	end
	local animations = section:Segmented({
		Title = L("animations"),
		Flag = "robly:animations",
		Options = {
			{ Value = "Full", Text = L("anim_full") },
			{ Value = "Soft", Text = L("anim_soft") },
			{ Value = "Off", Text = L("anim_off") },
		},
		Default = Motion.Mode,
		Save = false,
		Callback = function(mode)
			window:SetAnimations(mode)
		end,
	})
	local _ = animations
	section:Toggle({
		Title = L("detached_hide"),
		Flag = "robly:hideDetached",
		Default = window.Config:GetMeta("hideDetached") == true,
		Save = false,
		Callback = function(value)
			window.Config:SetMeta("hideDetached", value)
		end,
	})

	-- Keybind panel (PC)
	local hud = self.Tab:Section({ Title = L("binds_panel") })
	self.HudSection = hud
	hud:Toggle({ Title = L("binds_panel"), Flag = "robly:hud.show", Default = true, Persist = "ui", VisibleWhen = pcOnly })
	hud:Segmented({
		Title = L("show"),
		Flag = "robly:hud.mode",
		Options = { { Value = "all", Text = L("all") }, { Value = "enabled", Text = L("enabled_only") } },
		Default = "all",
		Persist = "ui",
		VisibleWhen = pcOnly,
	})
	hud:Segmented({
		Title = L("screen_edge"),
		Flag = "robly:hud.edge",
		Options = { { Value = "left", Text = L("left") }, { Value = "right", Text = L("right") } },
		Default = "right",
		Persist = "ui",
		VisibleWhen = pcOnly,
	})
	hud:Slider({ Title = L("bg_opacity"), Flag = "robly:hud.alpha", Min = 0, Max = 60, Step = 2, Default = 8, Suffix = "%", Persist = "ui", VisibleWhen = pcOnly })
	hud:Keybind({
		Title = L("hud_hide_key"),
		Flag = "robly:hud.key",
		Default = "Ctrl+B",
		System = true,
		ShowInHud = false,
		VisibleWhen = pcOnly,
		Callback = function()
			if window.Hud then
				window.Hud:ToggleHidden()
			end
		end,
	})
	hud:Toggle({ Title = L("hide_with_window"), Flag = "robly:hud.hideWithWindow", Default = false, Persist = "ui", VisibleWhen = pcOnly })

	-- Quick buttons (touch)
	self.QuickSection = self.Tab:Section({ Title = L("quick_buttons") })
	self.QuickSection:Paragraph({ Content = L("quick_buttons_desc"), VisibleWhen = touchOnly })
	self._quickRows = {}
end

-- Rebuild the list of functions the player can pin as quick buttons.
function SettingsTab:RefreshQuick()
	local window = self.Window
	local signature = {}
	for _, control in ipairs(window.Quick) do
		table.insert(signature, tostring(control.Flag or control.TitleSpec) .. (control.Destroyed and "x" or ""))
	end
	signature = table.concat(signature, "|")
	if signature == self._quickSignature then
		return
	end
	self._quickSignature = signature
	for _, row in ipairs(self._quickRows) do
		row:Destroy()
	end
	table.clear(self._quickRows)
	for index, control in ipairs(window.Quick) do
		if control.Flag and not control.Destroyed then
			local row = self.QuickSection:Checkbox({
				Title = control.TitleSpec,
				Flag = "robly:quick:" .. control.Flag,
				Default = index <= 4,
				Persist = "ui",
				VisibleWhen = touchOnly,
			})
			table.insert(self._quickRows, row)
		elseif not control.Flag and not control.Destroyed then
			local flag = "robly:quick:" .. (control.TitleSpec and window.Loc:Get(control.TitleSpec) or tostring(index))
			control.QuickFlag = flag
			local row = self.QuickSection:Checkbox({
				Title = control.TitleSpec,
				Flag = flag,
				Default = index <= 4,
				Persist = "ui",
				VisibleWhen = touchOnly,
			})
			table.insert(self._quickRows, row)
		end
	end
	self.QuickSection.Frame.Visible = #window.Quick > 0
end

-- About ----------------------------------------------------------------------------------

function SettingsTab:_buildAbout()
	local window = self.Window
	local section = self.Tab:Section({ Title = L("about") })
	section:Paragraph({ Title = "Robly by RobScript", Content = {
		en = "UI library for Roblox scripts. Open source, free to use.",
		ru = "UI-библиотека для Roblox-скриптов. Открытый код, свободное использование.",
		es = "Biblioteca de interfaz para scripts de Roblox. Código abierto y libre.",
		pt = "Biblioteca de interface para scripts Roblox. Código aberto e livre.",
		de = "UI-Bibliothek für Roblox-Skripte. Open Source, frei nutzbar.",
		fr = "Bibliothèque d'interface pour scripts Roblox. Open source, libre d'usage.",
	} })
	section:Button({ Title = "robscript.com", Icon = "link", Variant = "Text", Callback = function()
		window:_copyLink()
	end })
end

return SettingsTab
