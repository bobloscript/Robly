-- Splash: loading screen shown over the window while the script starts.
--   CreateWindow({ Loading = true })                       -- 1.6 s, automatic
--   CreateWindow({ Loading = { Title, Subtitle, Duration } })
--   Window.Splash:Set(0.4, "Loading modules…")  · Window.Splash:Done()
-- With Duration = false the bar waits for Set/Done calls from the script.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Maid = import("util/Maid")

local New = Create.New
local C = Theme.c

local Splash = {}
Splash.__index = Splash

function Splash.new(window, opts)
	if opts == true then
		opts = {}
	end
	local self = setmetatable({}, Splash)
	self.Window = window
	self.Maid = Maid.new()
	self.Progress = 0
	self.Finished = false
	local loc = window.Loc

	local group = self.Maid:Add(New("CanvasGroup", {
		Name = "Splash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C("bg"),
		ZIndex = 50,
		Parent = window.Frame,
	}))
	self.Group = group
	-- its own background effect, so the splash already looks like the brand
	local Effects = import("ui/Effects")
	self.Effects = self.Maid:Add(Effects.new(group, 50))

	local center = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 51,
		Parent = group,
	}, { Create.list("Vertical", 10, { align = "Center" }) })
	local logo = window:_logo(64)
	logo.LayoutOrder = 1
	logo.Parent = center
	local logoScale = New("UIScale", { Scale = 0.7, Parent = logo })
	New("UIGradient", { Color = Theme.gradient(), Rotation = 45, Parent = logo })
	logo.BackgroundColor3 = Color3.new(1, 1, 1)
	Motion.tween(logoScale, { Scale = 1 }, "spring")

	local title = New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		TextSize = 22,
		Weight = "Bold",
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = center,
	})
	title.TextXAlignment = Enum.TextXAlignment.Center
	loc:Bind(title, "Text", opts.Title or window.TitleSpec or "")
	local subtitle = New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		TextColor3 = C("textMuted"),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 3,
		Parent = center,
	})
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	loc:Bind(subtitle, "Text", opts.Subtitle or window.SubtitleSpec or "")

	local track = New("Frame", {
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = C("track"),
		LayoutOrder = 4,
		Parent = center,
	}, { Create.corner("full") })
	self.Fill = New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	}, { Create.corner("full"), New("UIGradient", { Color = Theme.gradient() }) })
	self.Status = New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		TextColor3 = C("textSubtle"),
		TextSize = 11,
		Weight = "Medium",
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 5,
		Parent = center,
	})
	self.Status.TextXAlignment = Enum.TextXAlignment.Center
	loc:Bind(self.Status, "Text", opts.Status or { __lib = "loading" })

	local duration = opts.Duration
	if duration == nil then
		duration = 1.6
	end
	if duration then
		task.spawn(function()
			local steps = 20
			for i = 1, steps do
				task.wait(duration / steps)
				if self.Finished then
					return
				end
				self:Set(math.max(self.Progress, i / steps))
			end
			self:Done()
		end)
	end
	return self
end

-- ratio 0…1, optional status text (string or localized spec)
function Splash:Set(ratio, status)
	if self.Finished then
		return self
	end
	self.Progress = math.clamp(tonumber(ratio) or 0, 0, 1)
	Motion.tween(self.Fill, { Size = UDim2.fromScale(self.Progress, 1) }, "window")
	if status then
		self.Window.Loc:Bind(self.Status, "Text", status)
	end
	return self
end

function Splash:Done()
	if self.Finished then
		return
	end
	self.Finished = true
	self.Fill.Size = UDim2.fromScale(1, 1)
	if Motion.Mode == "Off" then
		self:Destroy()
		return
	end
	task.delay(0.15, function()
		Motion.tween(self.Group, { GroupTransparency = 1 }, "window")
		task.wait(0.35)
		self:Destroy()
	end)
end

function Splash:Destroy()
	self.Finished = true
	self.Maid:Clean()
	if self.Window.Splash == self then
		self.Window.Splash = nil
	end
end

return Splash
