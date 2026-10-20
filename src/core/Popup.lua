-- Popup: anchored floating panels (dropdown lists, menus, colour picker) in
-- the "Popups" layer. One popup at a time; tapping outside closes it.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Device = import("core/Device")
local Icons = import("core/Icons")
local Maid = import("util/Maid")

local New = Create.New
local C, S = Theme.c, Theme.s

local Popup = {}
Popup.__index = Popup

function Popup.new(window)
	local self = setmetatable({}, Popup)
	self.Window = window
	self.Layer = window.Root.Popups
	self.Current = nil
	return self
end

function Popup:Close()
	local current = self.Current
	if not current then
		return
	end
	self.Current = nil
	current.maid:Clean()
	if current.onClose then
		task.spawn(current.onClose)
	end
end

-- opts: anchor, width, build(container, handle), align ("left"|"right"|"center"),
--       placement ("below"|"above"|"center"), onClose, gap
function Popup:Open(opts)
	self:Close()
	local maid = Maid.new()
	local handle = { maid = maid, onClose = opts.onClose }
	self.Current = handle
	function handle.Close()
		if self.Current == handle then
			self:Close()
		end
	end

	local catcher = maid:Add(New("TextButton", {
		Name = "Catcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = self.Layer,
	}))
	maid:Add(catcher.Activated:Connect(handle.Close))

	local width = opts.width
	if not width and opts.anchor then
		width = math.max(opts.anchor.AbsoluteSize.X, 200)
	end
	local container = maid:Add(New("Frame", {
		Name = "Popup",
		Size = UDim2.fromOffset(width or 220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C("overlay"),
		ZIndex = 2,
		Active = true,
		Parent = self.Layer,
	}, {
		Create.corner(12),
		Create.stroke("borderStrong"),
		Create.pad(opts.padding or 6),
		Create.list("Vertical", 2),
	}))
	handle.Frame = container

	local scale = New("UIScale", { Scale = 0.96, Parent = container })

	local function place()
		local vp = Device.viewport()
		local size = container.AbsoluteSize
		local gap = opts.gap or 6
		local x, y
		if opts.anchor and opts.placement ~= "center" then
			local ap, as = Device.toOffset(opts.anchor.AbsolutePosition), opts.anchor.AbsoluteSize
			if opts.align == "left" then
				x = ap.X
			elseif opts.align == "center" then
				x = ap.X + as.X / 2 - size.X / 2
			else
				x = ap.X + as.X - size.X
			end
			y = ap.Y + as.Y + gap
			if opts.placement == "above" or (y + size.Y > vp.Y - 8 and ap.Y - gap - size.Y > Device.inset()) then
				y = ap.Y - gap - size.Y
			end
		else
			x = vp.X / 2 - size.X / 2
			y = vp.Y / 2 - size.Y / 2
		end
		x = math.clamp(x, 8, math.max(8, vp.X - size.X - 8))
		y = math.clamp(y, Device.inset() + 4, math.max(Device.inset() + 4, vp.Y - size.Y - 8))
		container.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	end
	maid:Add(container:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))

	if opts.build then
		opts.build(container, handle)
	end
	place()
	task.defer(place)
	Motion.tween(scale, { Scale = 1 }, "spring")
	return handle
end

-- Simple menu. items: { Text, Icon, Danger, Checked, Disabled, Callback } or "divider"
function Popup:Menu(anchor, items, opts)
	opts = opts or {}
	local loc = self.Window.Loc
	return self:Open({
		anchor = anchor,
		width = opts.width or 230,
		align = opts.align,
		placement = opts.placement,
		onClose = opts.onClose,
		build = function(container, handle)
			for index, item in ipairs(items) do
				if item == "divider" then
					New("Frame", {
						Size = UDim2.new(1, 0, 0, 1),
						BackgroundColor3 = C("divider"),
						LayoutOrder = index,
						Parent = container,
					})
				else
					local color = item.Danger and C("danger") or C("text")
					local button = New("TextButton", {
						Size = Theme.sz(1, 0, 0, "item"),
						BackgroundColor3 = C("raised"),
						BackgroundTransparency = 1,
						LayoutOrder = index,
						Parent = container,
					}, {
						Create.corner(8),
						Create.pad(0, 10),
						Create.list("Horizontal", 10, { valign = "Center" }),
					})
					if item.Icon then
						local icon = Icons.new(item.Icon, "iconSmall", item.Danger and C("danger") or C("textMuted"))
						icon.Frame.LayoutOrder = 1
						icon.Frame.Parent = button
					end
					local label = New("TextLabel", {
						Size = UDim2.fromScale(0, 1),
						TextColor3 = color,
						TextTruncate = Enum.TextTruncate.AtEnd,
						LayoutOrder = 2,
						Parent = button,
					}, { Create.flex() })
					loc:Bind(label, "Text", item.Text, item.Vars)
					if item.Hint then
						local hint = New("TextLabel", {
							AutomaticSize = Enum.AutomaticSize.X,
							Size = UDim2.fromScale(0, 1),
							TextColor3 = C("textSubtle"),
							TextSize = S("fontDesc"),
							LayoutOrder = 3,
							Parent = button,
						})
						loc:Bind(hint, "Text", item.Hint, item.HintVars)
					end
					if item.Checked then
						local check = Icons.new("check", "iconSmall", C("accent"))
						check.Frame.LayoutOrder = 4
						check.Frame.Parent = button
					end
					if item.Disabled then
						label.TextTransparency = 0.55
					else
						handle.maid:Add(button.MouseEnter:Connect(function()
							Motion.tween(button, { BackgroundTransparency = 0 }, "fade")
						end))
						handle.maid:Add(button.MouseLeave:Connect(function()
							Motion.tween(button, { BackgroundTransparency = 1 }, "fade")
						end))
						handle.maid:Add(button.Activated:Connect(function()
							handle.Close()
							if item.Callback then
								task.spawn(item.Callback)
							end
						end))
					end
				end
			end
		end,
	})
end

return Popup
