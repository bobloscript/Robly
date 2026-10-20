-- Notifications (toasts) in their own layer and corner:
--   PC     — top right, under the Roblox top bar
--   touch  — top centre, under the top bar (top right belongs to quick buttons)

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Device = import("core/Device")
local Icons = import("core/Icons")
local Maid = import("util/Maid")
local Services = import("core/Services")

local New = Create.New
local C, S = Theme.c, Theme.s

local Notifications = {}
Notifications.__index = Notifications

local KINDS = {
	success = { icon = "check", color = "success" },
	warning = { icon = "warning", color = "warning" },
	error = { icon = "error", color = "danger" },
	info = { icon = "info", color = "text" },
	bind = { icon = "keyboard", color = "accent" },
}

function Notifications.new(window)
	local self = setmetatable({}, Notifications)
	self.Window = window
	self.Holder = New("Frame", {
		Name = "Toasts",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = window.Root.Notifications,
	}, { Create.list("Vertical", 8, { align = "Right" }) })
	Theme.bind(self.Holder, "AnchorPoint", Theme.f(function(_, s)
		return s.touch and Vector2.new(0.5, 0) or Vector2.new(1, 0)
	end))
	Theme.bind(self.Holder, "Size", Theme.f(function(_, s)
		return UDim2.fromOffset(math.min(s.toastWidth, Device.viewport().X - 32), 0)
	end))
	self:Place()
	self._order = 0
	self._live = {}
	return self
end

function Notifications:Place()
	local touch = Theme.Sizes.touch
	local top = Device.inset() + (touch and 8 or 16)
	if touch then
		self.Holder.Position = UDim2.new(0.5, 0, 0, top)
	else
		self.Holder.Position = UDim2.new(1, -24, 0, top)
	end
	local vp = Device.viewport()
	self.Holder.Size = UDim2.fromOffset(math.min(Theme.Sizes.toastWidth, vp.X - 32), 0)
end

-- opts: Title, Content, Type ("success"|"warning"|"error"|"info"), Icon,
--       Duration (seconds, default 4; 0 = until closed), Vars,
--       Action = { Text, Callback }
function Notifications:Notify(opts)
	opts = opts or {}
	local loc = self.Window.Loc
	local kind = KINDS[opts.Type or "info"] or KINDS.info
	local duration = opts.Duration
	if duration == nil then
		duration = 4
	end
	local maid = Maid.new()
	self._order += 1

	local toast = maid:Add(New("TextButton", {
		Name = "Toast",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C("overlay"),
		LayoutOrder = -self._order,
		ClipsDescendants = true,
		Parent = self.Holder,
	}, {
		Create.corner(14),
		Create.stroke("borderStrong"),
	}))
	local body = New("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = toast,
	}, {
		Create.pad(12, 14),
		Create.list("Horizontal", 12, { valign = "Center" }),
	})

	local badge = New("Frame", {
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = kind.color == "text" and C("raised") or C(kind.color),
		BackgroundTransparency = kind.color == "text" and 0 or 0.86,
		LayoutOrder = 1,
		Parent = body,
	}, { Create.corner(8) })
	local icon = Icons.new(opts.Icon or kind.icon, 16, C(kind.color), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	icon.Frame.Parent = badge

	local texts = New("Frame", {
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = body,
	}, { Create.list("Vertical", 2), Create.flex() })
	local title = Create.text("", { weight = "SemiBold", size = "fontDesc", wrap = true, order = 1 })
	title.TextSize = 13
	Theme.unbind(title, "TextSize")
	title.Parent = texts
	loc:Bind(title, "Text", opts.Title or "", opts.Vars)
	if opts.Content then
		local content = Create.text("", { size = "fontDesc", color = "textMuted", wrap = true, order = 2 })
		content.Parent = texts
		loc:Bind(content, "Text", opts.Content, opts.ContentVars or opts.Vars)
	end

	local handle = {}
	local closed = false
	function handle.Close()
		if closed then
			return
		end
		closed = true
		self._live[handle] = nil
		Motion.tween(toast, { BackgroundTransparency = 1 }, "fade")
		local scale = toast:FindFirstChildOfClass("UIScale") or New("UIScale", { Parent = toast })
		Motion.tween(scale, { Scale = 0.92 }, "press")
		task.delay(Motion.Mode == "Off" and 0 or 0.14, function()
			maid:Clean()
		end)
	end
	self._live[handle] = true

	if opts.Action then
		local action = New("TextButton", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 30),
			BackgroundColor3 = C("segment"),
			Weight = "SemiBold",
			TextSize = 13,
			LayoutOrder = 3,
			Parent = body,
		}, { Create.corner(8), Create.pad(0, 10) })
		loc:Bind(action, "Text", opts.Action.Text or "OK")
		Motion.pressable(action, nil, nil, maid)
		maid:Add(action.Activated:Connect(function()
			handle.Close()
			if opts.Action.Callback then
				task.spawn(opts.Action.Callback)
			end
		end))
	end

	maid:Add(toast.Activated:Connect(handle.Close))

	if duration and duration > 0 then
		local bar = New("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = C("raised"),
			Parent = toast,
		})
		local fill = New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C("accent"),
			Parent = bar,
		})
		local info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
		if Motion.Mode ~= "Off" then
			local tween = Services.TweenService:Create(fill, info, { Size = UDim2.fromScale(0, 1) })
			tween:Play()
		end
		task.delay(duration, handle.Close)
	end

	-- entrance
	local scale = New("UIScale", { Scale = 0.94, Parent = toast })
	Motion.tween(scale, { Scale = 1 }, "spring")

	-- keep at most 4 toasts
	local count = 0
	for _ in pairs(self._live) do
		count += 1
	end
	if count > 4 then
		local oldest, oldestOrder = nil, math.huge
		for h in pairs(self._live) do
			if h ~= handle and h.order and h.order < oldestOrder then
				oldest, oldestOrder = h, h.order
			end
		end
		if oldest then
			oldest.Close()
		end
	end
	handle.order = self._order
	return handle
end

function Notifications:Destroy()
	self.Holder:Destroy()
end

return Notifications
