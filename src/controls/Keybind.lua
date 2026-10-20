-- Keybind: key chip with capture, conflict checks (game + other binds) and
-- registration in the bind panel.
--   section:Keybind({
--     Title = "Teleport to quest", Default = "Q",            -- "Ctrl+X", Enum.KeyCode.Q
--     Mode = "Action" | "Toggle" | "Hold",
--     Target = "autoFarm",       -- Toggle mode: flips this flag (a Toggle's Flag)
--     Callback = function(state) end,  -- runs on key press
--     Changed = function(key) end,     -- runs when the player assigns a new key
--     Cooldown = 3, ShowInHud = true,
--   })

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Control = import("controls/Base")
local Binds = import("system/Binds")

local New = Create.New
local C, S = Theme.c, Theme.s

local Keybind = Control.extend("Keybind")

local function validate(value)
	if type(value) == "table" then
		return { Key = Binds.normalize(value.Key), Override = value.Override == true }
	end
	return { Key = Binds.normalize(value), Override = false }
end

local function constructor(section, opts)
	local baseOpts = table.clone(opts)
	baseOpts.Callback = opts.Changed and function(value)
		opts.Changed(value.Key)
	end or nil
	local self = Control.new(section, baseOpts, {
		class = Keybind, kind = "Keybind", value = true,
		default = validate(opts.Default), persist = opts.System and "ui" or nil,
		validate = validate,
	})
	local chip = New("TextButton", {
		Name = "Key",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = Theme.sz(0, 0, 0, "chip"),
		BackgroundColor3 = C("sunken"),
		LayoutOrder = 5,
		Parent = self.Right,
	}, {
		Create.corner(8),
		Create.pad(0, 10),
		Create.list("Horizontal", 6, { valign = "Center" }),
		Create.minSize(36, 0),
	})
	self.Stroke = Create.stroke("segment", 1)
	self.Stroke.Parent = chip
	self.Warning = Icons.new("warning", 14, C("warning"))
	self.Warning.Frame.LayoutOrder = 0
	self.Warning.Frame.Visible = false
	self.Warning.Frame.Parent = chip
	self.KeyLabel = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Mono = true,
		TextSize = 12,
		LayoutOrder = 1,
		Parent = chip,
	})
	self.Chip = chip
	Motion.pressable(chip, nil, 0.95, self.Maid)
	self.Maid:Add(chip.Activated:Connect(function()
		if self.Enabled then
			self:StartCapture()
		end
	end))

	self.Entry = self.Window.Binds:Add({
		Flag = self.Flag,
		Title = opts.HudTitle or self.TitleSpec,
		Mode = opts.Mode,
		Target = opts.Target,
		Callback = opts.Callback,
		Cooldown = opts.Cooldown,
		ShowInHud = opts.ShowInHud ~= false,
		System = opts.System == true,
		Control = self,
	})
	self.Maid:Add(function()
		self.Window.Binds:Remove(self.Entry)
	end)
	self.Maid:Add(self.Loc.Changed:Connect(function()
		self:_render(self:Get())
	end))
	self:_finish()
	return self
end

function Keybind:_validate(value)
	return validate(value)
end

function Keybind:_render(value)
	if self.Capturing then
		return
	end
	local key = type(value) == "table" and value.Key or ""
	self.KeyLabel.FontFace = Theme.font("Regular", true)
	self.KeyLabel.Text = Binds.display(key) or self.Loc:Lib("none")
	Theme.bind(self.KeyLabel, "TextColor3", key ~= "" and C("text") or C("textSubtle"))
	Theme.bind(self.Chip, "BackgroundColor3", C("sunken"))
	Theme.bind(self.Stroke, "Color", C("segment"))
	self.Stroke.Thickness = 1
	self.Warning.Frame.Visible = key ~= "" and not value.Override and self.Window.Binds:GameConflict(key)
end

function Keybind:StartCapture()
	local binds = self.Window.Binds
	self.Capturing = true
	self.KeyLabel.FontFace = Theme.font("SemiBold")
	self.KeyLabel.Text = self.Loc:Lib("press_key")
	Theme.set(self.KeyLabel, "TextColor3", C("accent"))
	Theme.set(self.Stroke, "Color", C("accent"))
	self.Stroke.Thickness = 1.5
	self.Chip.BackgroundTransparency = 0
	Theme.set(self.Chip, "BackgroundColor3", Theme.f(function(c)
		return c.accent:Lerp(c.sunken, 0.88)
	end))
	binds:Capture(function(key)
		self.Capturing = false
		if key == nil or self.Destroyed then
			self:_render(self:Get())
			return
		end
		self:_assign(key)
	end)
end

function Keybind:_assign(key)
	local binds = self.Window.Binds
	local window = self.Window
	if key == "" then
		self:Set({ Key = "", Override = false })
		self:_render(self:Get())
		return
	end
	local other = binds:BindConflict(key, self.Entry)
	if other then
		window:Dialog({
			Title = { __lib = "key_taken_bind" },
			Vars = { key = Binds.display(key), name = self.Loc:Get(other.Title) },
			Content = { __lib = "key_taken_bind_desc" },
			Buttons = {
				{ Text = { __lib = "other_key" }, Variant = "Secondary", Callback = function()
					task.defer(function()
						self:StartCapture()
					end)
				end },
				{ Text = { __lib = "replace" }, Variant = "Primary", Callback = function()
					self.Store:Set(other.Flag, { Key = "", Override = false }, "api")
					self:_assignGame(key)
				end },
			},
		})
		return
	end
	self:_assignGame(key)
end

function Keybind:_assignGame(key)
	local window = self.Window
	if self.Window.Binds:GameConflict(key) then
		local chosen = false
		window:Dialog({
			Title = { __lib = "key_taken_game" },
			Vars = { key = Binds.display(key) },
			Content = { __lib = "key_taken_game_desc" },
			Buttons = {
				{ Text = { __lib = "other_key" }, Variant = "Secondary", Callback = function()
					chosen = true
					task.defer(function()
						self:StartCapture()
					end)
				end },
				{ Text = { __lib = "take_key" }, Variant = "Primary", Callback = function()
					chosen = true
					self:Set({ Key = key, Override = true })
					self:_render(self:Get())
				end },
			},
			OnClose = function()
				if self.Destroyed then
					return
				end
				if not chosen then
					-- Closed without choosing: keep the key; the game keeps priority.
					self:Set({ Key = key, Override = false })
				end
				self:_render(self:Get())
			end,
		})
		return
	end
	self:Set({ Key = key, Override = false })
	self:_render(self:Get())
end

function Keybind:GetKey()
	local value = self:Get()
	return value and value.Key or ""
end

function Keybind:StateText()
	return Binds.display(self:GetKey())
end

function Keybind:QuickState()
	if self.Entry.Target then
		return self.Store:Get(self.Entry.Target) == true
	end
	return "action"
end

function Keybind:QuickActivate()
	self.Window.Binds:Trigger(self.Entry, true)
	if self.Entry.Mode == "Hold" then
		self.Window.Binds:Trigger(self.Entry, false)
	end
	return self:QuickState()
end

return constructor
