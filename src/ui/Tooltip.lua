-- Tooltip: small inverted bubble in the Popups layer.
-- PC: hover for 0.45 s. Touch: tap the "?" button (or long text) to show.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Device = import("core/Device")

local New = Create.New
local C = Theme.c

local Tooltip = {}
Tooltip.__index = Tooltip

function Tooltip.new(window)
	local self = setmetatable({}, Tooltip)
	self.Window = window
	self.Frame = New("Frame", {
		Name = "Tooltip",
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = C("tooltip"),
		Visible = false,
		ZIndex = 10,
		Parent = window.Root.Popups,
	}, {
		Create.corner(10),
		Create.pad(8, 10),
		Create.maxSize(240, nil),
	})
	self.Label = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.XY,
		TextColor3 = C("tooltipText"),
		TextWrapped = true,
		TextSize = 12.5,
		Parent = self.Frame,
	}, { Create.maxSize(220, nil) })
	self._token = 0
	return self
end

function Tooltip:Show(anchor, spec, vars)
	self._token += 1
	local loc = self.Window.Loc
	self.Label.Text = loc:Get(spec, vars)
	local frame = self.Frame
	frame.Visible = true
	task.defer(function()
		local vp = Device.viewport()
		local size = frame.AbsoluteSize
		local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
		local x = math.clamp(ap.X + as.X / 2 - size.X / 2, 8, vp.X - size.X - 8)
		local y = ap.Y - size.Y - 8
		if y < Device.inset() + 4 then
			y = ap.Y + as.Y + 8
		end
		frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	end)
	frame.BackgroundTransparency = 1
	self.Label.TextTransparency = 1
	Motion.tween(frame, { BackgroundTransparency = 0 }, "fade")
	Motion.tween(self.Label, { TextTransparency = 0 }, "fade")
	local token = self._token
	task.delay(Theme.Sizes.touch and 2.5 or 6, function()
		if self._token == token then
			self:Hide()
		end
	end)
end

function Tooltip:Hide()
	self._token += 1
	self.Frame.Visible = false
end

-- Attach hover (PC) / tap-on-anchor (touch) behaviour.
function Tooltip:Attach(anchor, spec, maid, vars)
	local token = 0
	maid:Add(anchor.MouseEnter:Connect(function()
		if Theme.Sizes.touch then
			return
		end
		token += 1
		local mine = token
		task.delay(0.45, function()
			if token == mine then
				self:Show(anchor, spec, vars)
			end
		end)
	end))
	maid:Add(anchor.MouseLeave:Connect(function()
		token += 1
		self:Hide()
	end))
end

function Tooltip:Destroy()
	self.Frame:Destroy()
end

return Tooltip
