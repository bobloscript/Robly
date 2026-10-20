-- Keybind panel (PC): a small window at the screen edge — key → function →
-- state. Works while the main window is minimised. Pauses (dims) while the
-- player types. Modes: all / only enabled; can fold into a tab at the edge.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Device = import("core/Device")
local Localization = import("core/Localization")
local Maid = import("util/Maid")
local Binds = import("system/Binds")

local New = Create.New
local C, S = Theme.c, Theme.s
local L = Localization.L

local Hud = {}
Hud.__index = Hud

function Hud.new(window)
	local self = setmetatable({}, Hud)
	self.Window = window
	self.Maid = Maid.new()
	self.Hidden = false
	self.Collapsed = window.Config:GetMeta("hudCollapsed") == true
	self.Rows = {}

	self.Frame = self.Maid:Add(New("Frame", {
		Name = "KeybindPanel",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(230, 0),
		BackgroundColor3 = C("overlay"),
		Visible = false,
		Parent = window.Root.Windows,
	}, {
		Create.corner(14),
		Create.stroke("borderStrong"),
		Create.pad(8),
		Create.list("Vertical", 2),
	}))
	self.Tab = self.Maid:Add(New("TextButton", {
		Name = "KeybindTab",
		Size = UDim2.fromOffset(34, 52),
		BackgroundColor3 = C("overlay"),
		Visible = false,
		Parent = window.Root.Windows,
	}, {
		Create.corner(12),
		Create.stroke("borderStrong"),
		Create.list("Vertical", 2, { align = "Center", valign = "Center" }),
	}))
	Icons.new("keyboard", 16, C("textMuted")).Frame.Parent = self.Tab
	self.TabCount = New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		TextColor3 = C("accent"),
		TextSize = 12,
		Weight = "Bold",
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = self.Tab,
	})
	self.TabCount.TextXAlignment = Enum.TextXAlignment.Center
	self.Maid:Add(self.Tab.Activated:Connect(function()
		self:SetCollapsed(false)
	end))

	local store = window.Store
	local function flag(name, default)
		local value = store:Get(name)
		if value == nil then
			return default
		end
		return value
	end
	self.flag = flag

	self.Maid:Add(window.Binds.Changed:Connect(function()
		self:Refresh()
	end))
	self.Maid:Add(window.Binds.Fired:Connect(function(entry, state)
		self:_fired(entry, state)
	end))
	self.Maid:Add(window.Binds.PausedChanged:Connect(function()
		self:_paused()
	end))
	self.Maid:Add(store.Changed:Connect(function(name)
		if type(name) == "string" and name:find("^robly:hud") then
			self:Refresh()
		end
	end))
	self.Maid:Add(window.Loc.Changed:Connect(function()
		self:Refresh()
	end))
	self.Maid:Add(window.VisibilityChanged:Connect(function()
		self:_applyVisibility()
	end))
	self.Maid:Add(Theme.Changed:Connect(function(what)
		if what == "sizes" then
			self:Refresh()
		end
	end))

	-- cooldown ticker
	self.Maid:Add(task.spawn(function()
		while true do
			task.wait(0.25)
			for entry, row in pairs(self.Rows) do
				if entry.Cooldown and row.cooldown then
					local left = window.Binds:CooldownLeft(entry)
					row.cooldown.Visible = left > 0
					row.bolt.Frame.Visible = left <= 0
					if left > 0 then
						row.cooldown.Text = window.Loc:Lib("seconds", { n = math.ceil(left) })
					end
				end
			end
		end
	end))

	task.defer(function()
		self:Refresh()
	end)
	return self
end

function Hud:ToggleHidden()
	self.Hidden = not self.Hidden
	self:_applyVisibility()
end

function Hud:SetCollapsed(collapsed)
	self.Collapsed = collapsed
	self.Window.Config:SetMeta("hudCollapsed", collapsed)
	self:_applyVisibility()
end

function Hud:_entries()
	local binds = self.Window.Binds
	local mode = self.flag("robly:hud.mode", "all")
	local user, system = {}, {}
	for _, entry in ipairs(binds.Entries) do
		local key = binds:KeyOf(entry)
		if entry.ShowInHud and key ~= "" then
			if entry.System then
				if mode == "all" then
					table.insert(system, entry)
				end
			elseif mode == "all" or (entry.Target and binds:IsOn(entry)) then
				table.insert(user, entry)
			end
		end
	end
	return user, system
end

function Hud:_applyVisibility()
	local window = self.Window
	local show = Theme.Mode == "pc" and self.flag("robly:hud.show", true) and not self.Hidden and not window.Destroyed
	if show and window.Minimized and self.flag("robly:hud.hideWithWindow", false) then
		show = false
	end
	local user, system = self:_entries()
	local mode = self.flag("robly:hud.mode", "all")
	if #user == 0 and (mode == "enabled" or #system == 0) then
		show = false
	end
	local edge = self.flag("robly:hud.edge", "right")
	local vp = Device.viewport()
	local top = math.floor(math.max(Device.inset() + 120, vp.Y * 0.36))
	if edge == "left" then
		self.Frame.AnchorPoint = Vector2.new(0, 0)
		self.Frame.Position = UDim2.fromOffset(12, top)
		self.Tab.AnchorPoint = Vector2.new(0, 0)
		self.Tab.Position = UDim2.fromOffset(0, top)
	else
		self.Frame.AnchorPoint = Vector2.new(1, 0)
		self.Frame.Position = UDim2.new(1, -12, 0, top)
		self.Tab.AnchorPoint = Vector2.new(1, 0)
		self.Tab.Position = UDim2.new(1, 0, 0, top)
	end
	self.Frame.Visible = show and not self.Collapsed
	self.Tab.Visible = show and self.Collapsed
	local on = 0
	for _, entry in ipairs(window.Binds.Entries) do
		if entry.Target and window.Binds:IsOn(entry) then
			on += 1
		end
	end
	self.TabCount.Text = tostring(on)
	self.Frame.BackgroundTransparency = math.clamp((self.flag("robly:hud.alpha", 8) or 8) / 100, 0, 0.9)
	self:_paused()
end

function Hud:_row(entry, order)
	local window = self.Window
	local binds = window.Binds
	local maid = self._rowsMaid
	local row = maid:Add(New("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = C("accent"),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = self.Frame,
	}, { Create.corner(8), Create.pad(0, 6), Create.list("Horizontal", 8, { valign = "Center" }) }))
	local chip = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = C("sunken"),
		Text = Binds.display(binds:KeyOf(entry)) or "",
		Mono = true,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = row,
	}, { Create.corner(6), Create.pad(0, 6), Create.minSize(22, 0), Create.stroke("segment") })
	chip.TextXAlignment = Enum.TextXAlignment.Center
	local chipScale = New("UIScale", { Parent = chip })
	local title = New("TextLabel", {
		Size = UDim2.fromScale(0, 1),
		TextSize = 12.5,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = entry.System and C("textMuted") or C("text"),
		LayoutOrder = 2,
		Parent = row,
	}, { Create.flex() })
	window.Loc:Bind(title, "Text", entry.Title or "")
	local value = window.Store:Get(entry.Flag)
	if type(value) == "table" and not value.Override and binds:GameConflict(value.Key) then
		local warning = Icons.new("warning", 13, C("warning"))
		warning.Frame.LayoutOrder = 3
		warning.Frame.Parent = row
	end
	local info = { row = row, chip = chip, chipScale = chipScale }
	if entry.Target then
		local on = binds:IsOn(entry)
		local dot = New("Frame", {
			Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = C("success"),
			BackgroundTransparency = on and 0 or 1,
			LayoutOrder = 4,
			Parent = row,
		}, { Create.corner("full") })
		local ring = Create.stroke("textSubtle", 1.5)
		ring.Transparency = on and 1 or 0
		ring.Parent = dot
		info.dot, info.ring = dot, ring
	else
		local bolt = Icons.new("bolt", 14, C("textMuted"))
		bolt.Frame.LayoutOrder = 4
		bolt.Frame.Parent = row
		info.bolt = bolt
		if entry.Cooldown then
			local cooldown = New("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				TextColor3 = C("textMuted"),
				TextSize = 11.5,
				Visible = false,
				LayoutOrder = 5,
				Parent = row,
			})
			info.cooldown = cooldown
		end
	end
	self.Rows[entry] = info
end

function Hud:Refresh()
	if self._rowsMaid then
		self._rowsMaid:Clean()
	end
	self._rowsMaid = Maid.new()
	self.Rows = {}
	local window = self.Window
	local mode = self.flag("robly:hud.mode", "all")
	local user, system = self:_entries()
	local maid = self._rowsMaid

	if mode == "all" then
		local header = maid:Add(New("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 0,
			Parent = self.Frame,
		}, { Create.pad(0, 4, 0, 6), Create.list("Horizontal", 6, { valign = "Center" }) }))
		local title = New("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C("textSubtle"),
			TextSize = 11.5,
			Weight = "SemiBold",
			Parent = header,
		}, { Create.flex() })
		window.Loc:Bind(title, "Text", function()
			return string.upper(window.Loc:Lib("binds"))
		end)
		self.PauseLabel = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C("warning"),
			TextSize = 11,
			Visible = false,
			LayoutOrder = 2,
			Parent = header,
		})
		window.Loc:Bind(self.PauseLabel, "Text", L("paused"))
		local fold = New("TextButton", {
			Size = UDim2.fromOffset(22, 22),
			LayoutOrder = 3,
			Parent = header,
		}, { Create.corner(6) })
		local chevron = Icons.new(self.flag("robly:hud.edge", "right") == "left" and "chevronLeft" or "chevronRight", 14, C("textSubtle"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		chevron.Frame.Parent = fold
		maid:Add(fold.Activated:Connect(function()
			self:SetCollapsed(true)
		end))
	else
		self.PauseLabel = nil
	end
	for index, entry in ipairs(user) do
		self:_row(entry, index)
	end
	if #system > 0 and #user > 0 then
		maid:Add(New("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = C("divider"),
			LayoutOrder = 500,
			Parent = self.Frame,
		}))
	end
	for index, entry in ipairs(system) do
		self:_row(entry, 600 + index)
	end
	self:_applyVisibility()
end

function Hud:_fired(entry, state)
	local row = self.Rows[entry]
	local window = self.Window
	if row then
		row.row.BackgroundTransparency = 0.8
		Motion.tween(row.row, { BackgroundTransparency = 1 }, "flash")
		row.chipScale.Scale = 0.94
		Motion.tween(row.chipScale, { Scale = 1 }, "spring")
		if row.dot then
			local on = state == true
			Motion.tween(row.dot, { BackgroundTransparency = on and 0 or 1 }, "fade")
			Motion.tween(row.ring, { Transparency = on and 1 or 0 }, "fade")
		end
	end
	if self.flag("robly:hud.mode", "all") == "enabled" then
		self:Refresh()
	else
		self:_applyVisibility()
	end
	if not entry.System and Theme.Mode == "pc" then
		local text = window.Loc:Get(entry.Title)
		local content = nil
		if entry.Target then
			content = window.Loc:Lib(state and "on" or "off")
		end
		window:Notify({
			Title = text,
			Content = content,
			Type = "bind",
			Icon = entry.Target and (state and "check" or "minus") or "bolt",
			Duration = 1.6,
		})
	end
end

function Hud:_paused()
	local paused = self.Window.Binds.Paused
	if self.PauseLabel then
		self.PauseLabel.Visible = paused
	end
	local base = math.clamp((self.flag("robly:hud.alpha", 8) or 8) / 100, 0, 0.9)
	self.Frame.BackgroundTransparency = paused and math.max(base, 0.35) or base
	for _, child in ipairs(self.Frame:GetDescendants()) do
		if child:IsA("TextLabel") and child ~= self.PauseLabel then
			child.TextTransparency = paused and 0.5 or 0
		end
	end
end

function Hud:Destroy()
	if self._rowsMaid then
		self._rowsMaid:Clean()
	end
	self.Maid:Clean()
end

return Hud
