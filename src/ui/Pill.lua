-- Pill: the minimised window. Drag to move, tap to restore.
-- Shows a green dot while at least one toggle is on.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Drag = import("core/Drag")
local Device = import("core/Device")
local Maid = import("util/Maid")

local New = Create.New
local C = Theme.c

local Pill = {}
Pill.__index = Pill

-- opts: layer, root, title (text spec), logo (Frame builder), onRestore, position (Vector2?)
function Pill.new(window, opts)
	local self = setmetatable({}, Pill)
	self.Window = window
	self.Maid = Maid.new()
	local loc = window.Loc

	local button = self.Maid:Add(New("TextButton", {
		Name = "Pill",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		BackgroundColor3 = C("overlay"),
		Visible = false,
		Parent = window.Root.Windows,
	}, {
		Create.corner("full"),
		Create.stroke("borderStrong"),
		Create.pad(0, 14, 0, 9),
		Create.list("Horizontal", 10, { valign = "Center" }),
	}))
	self.Button = button

	if opts.logo then
		local logo = opts.logo(26)
		logo.LayoutOrder = 1
		logo.Parent = button
	end
	local label = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		Weight = "SemiBold",
		TextSize = 13.5,
		LayoutOrder = 2,
		Parent = button,
	}, { Create.maxSize(200, nil) })
	label.TextTruncate = Enum.TextTruncate.AtEnd
	loc:Bind(label, "Text", opts.title)

	self.Dot = New("Frame", {
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = C("success"),
		Visible = false,
		LayoutOrder = 3,
		Parent = button,
	}, { Create.corner("full") })

	local moved = false
	Drag.attach(button, {
		onStart = function()
			moved = false
			button.ZIndex = window.Root:NextZ()
		end,
		onMove = function(_, delta)
			moved = true
			local p = button.AbsolutePosition + delta
			p = Drag.clamp(p, button.AbsoluteSize)
			button.Position = UDim2.fromOffset(p.X, p.Y)
		end,
		onEnd = function()
			if moved and opts.onMoved then
				opts.onMoved(button.AbsolutePosition)
			end
		end,
	}, self.Maid)
	self.Maid:Add(button.Activated:Connect(function()
		if not moved and opts.onRestore then
			opts.onRestore()
		end
		moved = false
	end))
	Motion.pressable(button, nil, 0.95, self.Maid)

	self.Position = opts.position
	return self
end

function Pill:SetActive(active)
	self.Dot.Visible = active
end

function Pill:DefaultPosition()
	local vp = Device.viewport()
	local size = self.Button.AbsoluteSize
	if size.X < 10 then
		size = Vector2.new(180, 44)
	end
	return Vector2.new(math.floor(vp.X / 2 - size.X / 2), Device.inset() + 8)
end

function Pill:Show(from)
	local button = self.Button
	local target = self.Position or self:DefaultPosition()
	target = Drag.clamp(target, Vector2.new(math.max(button.AbsoluteSize.X, 160), 44))
	button.Position = UDim2.fromOffset(target.X, target.Y)
	button.ZIndex = self.Window.Root:NextZ()
	button.Visible = true
	local scale = button:FindFirstChildOfClass("UIScale")
	if scale and from then
		scale.Scale = 0.6
		Motion.tween(scale, { Scale = 1 }, "spring")
	end
end

function Pill:Hide()
	self.Position = self.Button.AbsolutePosition
	self.Button.Visible = false
end

function Pill:Rect()
	return self.Button.AbsolutePosition, self.Button.AbsoluteSize
end

function Pill:Destroy()
	self.Maid:Clean()
end

return Pill
