-- DetachedWindow: a tab living in its own small window.
--   PC   — drag a tab out of the sidebar, or press the "picture in picture"
--          button. Drag the window by its title back onto the sidebar to
--          return it (the slot lights up: "Release to return").
--   Touch — long-press a tab → "Open in separate window" (max 2 on phones).
-- The page is reparented, never rebuilt: values live in the Store, nothing
-- resets. Grows out of / folds back into the nav item (Quint Out 280 ms).

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Drag = import("core/Drag")
local Device = import("core/Device")
local Maid = import("util/Maid")
local Util = import("util/Util")
local Pill = import("ui/Pill")

local New = Create.New
local C, S = Theme.c, Theme.s

local Detached = {}
Detached.__index = Detached

local function rectOf(gui)
	if gui and gui.Parent and gui.AbsoluteSize.X > 0 then
		return gui.AbsolutePosition, gui.AbsoluteSize
	end
	return nil
end

function Detached.defaultSize()
	local vp = Device.viewport()
	local mode = Theme.Mode
	if mode == "phone" then
		return Vector2.new(math.clamp(math.floor(vp.X * 0.36), 260, 340), math.max(220, vp.Y - Device.inset() - 16))
	elseif mode == "tablet" then
		return Vector2.new(math.min(360, vp.X - 32), math.min(520, vp.Y - Device.inset() - 32))
	end
	return Vector2.new(360, math.min(460, vp.Y - Device.inset() - 32))
end

function Detached.new(tab, options)
	options = options or {}
	local window = tab.Window
	local loc = window.Loc
	local self = setmetatable({}, Detached)
	self.Tab = tab
	self.Window = window
	self.Maid = Maid.new()

	local frame = self.Maid:Add(New("Frame", {
		Name = "Detached_" .. tab.Id,
		BackgroundColor3 = C("bg"),
		ClipsDescendants = true,
		Active = true,
		ZIndex = window.Root:NextZ(),
		Parent = window.Root.Windows,
	}, {
		Create.corner("rWindow"),
		Create.stroke("borderStrong"),
		Create.list("Vertical", 0),
	}))
	self.Frame = frame
	self.Scale = New("UIScale", { Parent = frame })

	-- Header ---------------------------------------------------------------------
	local header = New("Frame", {
		Name = "Header",
		Size = Theme.f(function(_, s)
			return UDim2.new(1, 0, 0, s.touch and 44 or 44)
		end),
		LayoutOrder = 1,
		Active = true,
		Parent = frame,
	}, { Create.pad(0, 4, 0, 14), Create.list("Horizontal", 4, { valign = "Center" }) })
	local title = New("TextLabel", {
		Size = UDim2.fromScale(0, 1),
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Weight = "SemiBold",
		Parent = header,
	}, { Create.flex() })
	loc:Bind(title, "Text", function()
		return loc:Get(tab.TitleSpec) .. ' <font color="#' .. Util.toHex(Theme.Colors.textSubtle) .. '">· ' .. loc:Get(window.TitleSpec) .. "</font>"
	end)
	self.Maid:Add(Theme.Changed:Connect(function()
		loc:Bind(title, "Text", function()
			return loc:Get(tab.TitleSpec) .. ' <font color="#' .. Util.toHex(Theme.Colors.textSubtle) .. '">· ' .. loc:Get(window.TitleSpec) .. "</font>"
		end)
	end))

	local function headerButton(icon, order, tip, callback)
		local button = New("TextButton", {
			Size = Theme.sz(0, "hit", 0, "hit"),
			LayoutOrder = order,
			Parent = header,
		}, { Create.corner(9) })
		local glyph = Icons.new(icon, 16, C("textMuted"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		glyph.Frame.Parent = button
		Motion.pressable(button, glyph.Frame, 0.85, self.Maid)
		window.Tooltip:Attach(button, tip, self.Maid)
		self.Maid:Add(button.Activated:Connect(callback))
		return button
	end
	headerButton("minus", 2, { __lib = "minimize" }, function()
		self:Minimize()
	end)
	headerButton("attach", 3, { __lib = "return_to_window" }, function()
		self:Attach()
	end)

	New("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C("divider"),
		LayoutOrder = 2,
		Parent = frame,
	})
	local content = New("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 3,
		Parent = frame,
	}, { Create.flex(), Create.pad(Theme.f(function(_, s)
		return UDim.new(0, s.touch and 8 or 12)
	end), "contentX", "contentBottom", "contentX") })
	self.Content = content

	-- Move the page in
	tab.Page.Parent = content
	tab.Page.Visible = true
	tab.Page.Position = UDim2.new()
	tab.PageHeader.Visible = false
	Theme.unbind(tab.PageHeader, "Visible")

	-- Geometry -------------------------------------------------------------------
	local saved = window.Config:GetDetached(tab.Id)
	local size = saved and Vector2.new(saved.w, saved.h) or Detached.defaultSize()
	local position
	if options.at then
		position = options.at - Vector2.new(size.X / 2, 20)
	elseif saved then
		position = Vector2.new(saved.x, saved.y)
	else
		local mainPos, mainSize = rectOf(window.Frame)
		if mainPos then
			local right = mainPos.X + mainSize.X + 16
			if right + size.X < Device.viewport().X - 8 then
				position = Vector2.new(right, mainPos.Y)
			else
				position = Vector2.new(mainPos.X - size.X - 16, mainPos.Y)
			end
		else
			position = Vector2.new(24, Device.inset() + 24)
		end
	end
	size = Vector2.new(math.min(size.X, Device.viewport().X - 16), math.min(size.Y, Device.viewport().Y - Device.inset() - 16))
	position = Drag.clamp(position, size)
	self.TargetPosition, self.TargetSize = position, size

	local fromPos, fromSize = options.fromPos, options.fromSize
	if fromPos and Motion.Mode == "Full" then
		frame.Position = UDim2.fromOffset(fromPos.X, fromPos.Y)
		frame.Size = UDim2.fromOffset(fromSize.X, fromSize.Y)
		Motion.tween(frame, {
			Position = UDim2.fromOffset(position.X, position.Y),
			Size = UDim2.fromOffset(size.X, size.Y),
		}, "window")
	else
		frame.Position = UDim2.fromOffset(position.X, position.Y)
		frame.Size = UDim2.fromOffset(size.X, size.Y)
		if Motion.Mode ~= "Off" then
			self.Scale.Scale = 0.96
			Motion.tween(self.Scale, { Scale = 1 }, "spring")
		end
	end

	-- Raise on press
	self.Maid:Add(frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			frame.ZIndex = window.Root:NextZ()
		end
	end))

	-- Drag by header; drop on the main sidebar returns the tab (PC)
	local overNav = false
	Drag.attach(header, {
		onMove = function(pointer, delta)
			local p = frame.AbsolutePosition + delta
			frame.Position = UDim2.fromOffset(p.X, p.Y)
			local over = window:_pointerOverNav(pointer)
			if over ~= overNav then
				overNav = over
				window:_navHighlight(tab, over)
			end
		end,
		onEnd = function(_, moved)
			if not moved then
				return
			end
			if overNav then
				overNav = false
				window:_navHighlight(tab, false)
				self:Attach()
				return
			end
			self:_snap()
			self:_save()
		end,
	}, self.Maid)

	-- Resize (PC)
	local grip = New("TextButton", {
		Name = "Resize",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -2, 1, -2),
		Size = UDim2.fromOffset(16, 16),
		Visible = Theme.f(function(_, s)
			return not s.touch
		end),
		ZIndex = 20,
		Parent = frame,
	})
	local gripIcon = Icons.new("grip", 14, C("textSubtle"))
	gripIcon.Frame.Parent = grip
	local startSize
	Drag.attach(grip, {
		threshold = 1,
		onStart = function()
			startSize = frame.AbsoluteSize
		end,
		onMove = function(_, _, total)
			local vp = Device.viewport()
			local w = math.clamp(startSize.X + total.X, 260, math.max(260, vp.X - frame.AbsolutePosition.X - 8))
			local h = math.clamp(startSize.Y + total.Y, 200, math.max(200, vp.Y - frame.AbsolutePosition.Y - 8))
			frame.Size = UDim2.fromOffset(w, h)
		end,
		onEnd = function()
			self:_save()
		end,
	}, self.Maid)

	-- Pill for minimising
	self.Pill = Pill.new(window, {
		title = tab.TitleSpec,
		logo = function(size)
			local holder = New("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = C("raised") }, { Create.corner("full") })
			local icon = Icons.new(tab.Icon, 16, C("accent"), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			icon.Frame.Parent = holder
			return holder
		end,
		onRestore = function()
			self:Restore()
		end,
	})
	self.Maid:Add(self.Pill)

	tab.DetachedWindow = self
	return self
end

function Detached:_snap()
	local frame = self.Frame
	local vp = Device.viewport()
	local p, size = frame.AbsolutePosition, frame.AbsoluteSize
	local margin, edge = 8, 20
	local x, y = p.X, p.Y
	if x < edge then
		x = margin
	elseif x + size.X > vp.X - edge then
		x = vp.X - size.X - margin
	end
	local top = Device.inset() + margin
	if y < top + edge then
		y = top
	elseif y + size.Y > vp.Y - edge then
		y = vp.Y - size.Y - margin
	end
	local clamped = Drag.clamp(Vector2.new(x, y), size)
	Motion.tween(frame, { Position = UDim2.fromOffset(clamped.X, clamped.Y) }, "window")
end

function Detached:_save()
	local p, s = self.Frame.AbsolutePosition, self.Frame.AbsoluteSize
	self.Window.Config:SetDetached(self.Tab.Id, { x = p.X, y = p.Y, w = s.X, h = s.Y, open = true })
end

function Detached:Focus()
	self:Restore()
	self.Frame.ZIndex = self.Window.Root:NextZ()
	self.Scale.Scale = 0.97
	Motion.tween(self.Scale, { Scale = 1 }, "spring")
end

function Detached:SetHidden(hidden)
	if self.Minimized then
		return
	end
	self.Frame.Visible = not hidden
end

function Detached:Minimize()
	self.Minimized = true
	self.Frame.Visible = false
	self.Pill:Show(true)
end

function Detached:Restore()
	if not self.Minimized then
		return
	end
	self.Minimized = false
	self.Pill:Hide()
	self.Frame.Visible = true
	self.Frame.ZIndex = self.Window.Root:NextZ()
end

-- Return the tab to the main window (folds into its nav item).
function Detached:Attach()
	if self.Closing then
		return
	end
	self.Closing = true
	local window, tab = self.Window, self.Tab
	self:_save()
	window.Config:SetDetached(tab.Id, nil, true)
	local target = window:_navItemFor(tab)
	local function finish()
		self:Destroy(false)
		window:_attached(tab)
	end
	if target and Motion.Mode == "Full" and not self.Minimized then
		local pos, size = target.AbsolutePosition, target.AbsoluteSize
		Motion.tween(self.Frame, {
			Position = UDim2.fromOffset(pos.X, pos.Y),
			Size = UDim2.fromOffset(size.X, size.Y),
		}, "window")
		task.delay(0.28, finish)
	else
		finish()
	end
end

function Detached:Destroy(keepPage)
	local tab = self.Tab
	if tab.Page.Parent == self.Content then
		if keepPage then
			tab.Page.Parent = nil
		else
			tab.Page.Parent = self.Window.PageHost
		end
		tab.Page.Visible = false
	end
	Theme.bind(tab.PageHeader, "Visible", S("pageHeader"))
	tab.DetachedWindow = nil
	self.Maid:Clean()
end

return Detached
