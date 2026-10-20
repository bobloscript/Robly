-- Quick buttons (touch): a column of 44×44 buttons at the screen edge, under
-- the Roblox top bar and above the jump button. Enabled toggles glow with the
-- accent; actions show a bolt. After a tap a label shows for ~1 s:
-- "Auto farm · ON". The player picks which functions appear in Settings.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Device = import("core/Device")
local Maid = import("util/Maid")

local New = Create.New
local C = Theme.c

local QuickButtons = {}
QuickButtons.__index = QuickButtons

local MAX = 5

function QuickButtons.new(window)
	local self = setmetatable({}, QuickButtons)
	self.Window = window
	self.Maid = Maid.new()
	self.Holder = self.Maid:Add(New("Frame", {
		Name = "QuickButtons",
		AnchorPoint = Vector2.new(1, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		Parent = window.Root.Windows,
	}, { Create.list("Vertical", 8, { align = "Right" }) }))
	self.Maid:Add(window.Store.Changed:Connect(function(flag)
		if type(flag) == "string" and flag:find("^robly:quick:") then
			self:_scheduleRefresh()
		else
			self:_updateStates()
		end
	end))
	self:_scheduleRefresh()
	return self
end

function QuickButtons:_scheduleRefresh()
	if self._pending then
		return
	end
	self._pending = true
	task.defer(function()
		self._pending = false
		if not self.Window.Destroyed then
			self:Refresh()
		end
	end)
end

function QuickButtons:_flagFor(control)
	return control.QuickFlag or ("robly:quick:" .. tostring(control.Flag))
end

function QuickButtons:Refresh()
	local window = self.Window
	if window.SettingsTab and not self._refreshingSettings then
		self._refreshingSettings = true
		window.SettingsTab:RefreshQuick()
		self._refreshingSettings = false
	end
	if self._buttonsMaid then
		self._buttonsMaid:Clean()
	end
	local maid = Maid.new()
	self._buttonsMaid = maid
	self.Buttons = {}
	self.Holder.Position = UDim2.new(1, -12, 0, Device.inset() + 8)
	local count = 0
	for _, control in ipairs(window.Quick) do
		if count >= MAX then
			break
		end
		if not control.Destroyed and window.Store:Get(self:_flagFor(control)) == true then
			count += 1
			self:_button(control, count, maid)
		end
	end
	self.Holder.Visible = Theme.Sizes.touch and count > 0
	self:_updateStates()
end

function QuickButtons:_button(control, order, maid)
	local window = self.Window
	local row = maid:Add(New("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		LayoutOrder = order,
		Parent = self.Holder,
	}, { Create.list("Horizontal", 8, { align = "Right", valign = "Center" }) }))
	local label = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = C("overlay"),
		TextSize = 13,
		Weight = "SemiBold",
		Visible = false,
		LayoutOrder = 1,
		Parent = row,
	}, { Create.corner(8), Create.pad(0, 10), Create.stroke("borderStrong") })
	local button = New("TextButton", {
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C("overlay"),
		LayoutOrder = 2,
		Parent = row,
	}, { Create.corner(12) })
	local stroke = Create.stroke("borderStrong")
	stroke.Parent = button
	local iconName = control.Icon or (control:QuickState() == "action" and "bolt" or "dot")
	if iconName == "dot" then
		iconName = control.Tab.Icon or "bolt"
	end
	local icon = Icons.new(iconName, 20, C("text"), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	icon.Frame.Parent = button
	Motion.pressable(button, nil, 0.9, maid)
	local token = 0
	maid:Add(button.Activated:Connect(function()
		token += 1
		local mine = token
		local text = window.Loc:Get(control.TitleSpec)
		local state = nil
		if not control.Enabled then
			-- locked by EnabledWhen: say so instead of acting
			text ..= " · " .. window.Loc:Lib("locked")
		else
			state = control:QuickActivate()
		end
		if state == true or state == false then
			text ..= " · " .. window.Loc:Lib(state and "on" or "off")
		end
		label.Text = text
		label.Visible = true
		label.TextTransparency = 0
		label.BackgroundTransparency = 0
		task.delay(1, function()
			if token == mine then
				Motion.tween(label, { TextTransparency = 1, BackgroundTransparency = 1 }, "fade")
				task.delay(0.15, function()
					if token == mine then
						label.Visible = false
					end
				end)
			end
		end)
	end))
	table.insert(self.Buttons, { control = control, button = button, icon = icon, stroke = stroke })
end

function QuickButtons:_updateStates()
	for _, entry in ipairs(self.Buttons or {}) do
		local state = entry.control:QuickState()
		local on = state == true
		Theme.set(entry.button, "BackgroundColor3", on and C("accent") or C("overlay"))
		entry.icon:SetColor(on and C("accentInk") or C("text"), true)
		entry.stroke.Transparency = on and 1 or 0
	end
end

function QuickButtons:Destroy()
	if self._buttonsMaid then
		self._buttonsMaid:Clean()
	end
	self.Maid:Clean()
end

return QuickButtons
