-- Create: declarative instance builder.
--   New("Frame", { Size = ..., BackgroundColor3 = Theme.c("surface") }, { children })
-- Token values are bound through Theme, so they follow theme / size changes.
-- Sensible defaults remove noise: no borders, transparent background unless a
-- colour is given, Builder Sans text, no auto button colours.

local Theme = import("core/Theme")

local Create = {}

local TEXT = { TextLabel = true, TextButton = true, TextBox = true }
local BUTTON = { TextButton = true, ImageButton = true }

local function apply(instance, key, value)
	if Theme.isToken(value) then
		Theme.bind(instance, key, value)
	else
		instance[key] = value
	end
end

function Create.New(className, props, children)
	local instance = Instance.new(className)
	props = props or {}
	local isGui = instance:IsA("GuiObject")

	if isGui then
		instance.BorderSizePixel = 0
		if props.BackgroundColor3 == nil and props.BackgroundTransparency == nil then
			instance.BackgroundTransparency = 1
		end
	end
	if TEXT[className] then
		instance.FontFace = Theme.font(props.Weight or "Regular", props.Mono)
		if props.TextColor3 == nil then
			Theme.bind(instance, "TextColor3", Theme.c("text"))
		end
		if props.TextSize == nil then
			Theme.bind(instance, "TextSize", Theme.s("font"))
		end
		if props.Text == nil then
			instance.Text = ""
		end
		instance.TextXAlignment = Enum.TextXAlignment.Left
	end
	if BUTTON[className] then
		instance.AutoButtonColor = false
	end
	if className == "TextBox" then
		instance.ClearTextOnFocus = false
		if props.PlaceholderColor3 == nil then
			Theme.bind(instance, "PlaceholderColor3", Theme.c("textSubtle"))
		end
	end
	if className == "ScrollingFrame" then
		if props.ScrollBarThickness == nil then
			Theme.bind(instance, "ScrollBarThickness", Theme.s("scrollBar"))
		end
		instance.CanvasSize = UDim2.new()
		instance.AutomaticCanvasSize = Enum.AutomaticSize.Y
		instance.ScrollingDirection = Enum.ScrollingDirection.Y
		instance.ScrollBarImageTransparency = 0.4
		if props.ScrollBarImageColor3 == nil then
			Theme.bind(instance, "ScrollBarImageColor3", Theme.c("textSubtle"))
		end
	end

	local parent = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		elseif key ~= "Weight" and key ~= "Mono" then
			apply(instance, key, value)
		end
	end
	if children then
		for _, child in ipairs(children) do
			if child then
				child.Parent = instance
			end
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Helpers ---------------------------------------------------------------------

local function udim(value)
	if Theme.isToken(value) then
		return value
	end
	if type(value) == "string" then
		return Theme.ud(value)
	end
	if typeof(value) == "UDim" then
		return value
	end
	return UDim.new(0, value or 0)
end

function Create.corner(radius)
	if radius == "full" then
		return Create.New("UICorner", { CornerRadius = UDim.new(1, 0) })
	end
	return Create.New("UICorner", { CornerRadius = udim(radius) })
end

function Create.stroke(color, thickness, transparency)
	return Create.New("UIStroke", {
		Color = Theme.isToken(color) and color or (type(color) == "string" and Theme.c(color) or color),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- pad(all) · pad(y, x) · pad(top, right, bottom, left); numbers or size-token names
function Create.pad(top, right, bottom, left)
	if right == nil then
		right, bottom, left = top, top, top
	elseif bottom == nil then
		bottom, left = top, right
	end
	return Create.New("UIPadding", {
		PaddingTop = udim(top),
		PaddingRight = udim(right),
		PaddingBottom = udim(bottom),
		PaddingLeft = udim(left),
	})
end

-- list("Vertical" | "Horizontal", gap, { align = "Center", valign = "Center", wraps = false })
function Create.list(direction, gap, options)
	options = options or {}
	local layout = Create.New("UIListLayout", {
		FillDirection = direction == "Horizontal" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = udim(gap or 0),
	})
	if options.align then
		layout.HorizontalAlignment = Enum.HorizontalAlignment[options.align]
	end
	if options.valign then
		layout.VerticalAlignment = Enum.VerticalAlignment[options.valign]
	end
	if options.wraps then
		layout.Wraps = true
	end
	return layout
end

function Create.flex(grow)
	return Create.New("UIFlexItem", {
		FlexMode = grow == false and Enum.UIFlexMode.None or Enum.UIFlexMode.Fill,
	})
end

function Create.minSize(x, y)
	return Create.New("UISizeConstraint", { MinSize = Theme.v2(x or 0, y or 0) })
end

function Create.maxSize(x, y)
	return Create.New("UISizeConstraint", { MaxSize = Theme.v2(x or math.huge, y or math.huge) })
end

-- A filled panel with only some corners rounded, built from non-overlapping
-- pieces (3×3 grid; rounded corners are clipped quarter circles). Unlike a
-- rounded frame + square "patches", it stays correct when translucent.
--   Create.panel(parent, { color = token, transparency = token|number,
--                          radius = n, round = { tl, tr, bl, br } })
function Create.panel(parent, opts)
	local r = opts.radius or 12
	local round = opts.round or {}
	local holder = Create.New("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		ZIndex = opts.zindex or 0,
		Parent = parent,
	})
	local function piece(position, size)
		return Create.New("Frame", {
			Position = position,
			Size = size,
			BackgroundColor3 = opts.color,
			BackgroundTransparency = opts.transparency or 0,
			ZIndex = opts.zindex or 0,
			Parent = holder,
		})
	end
	-- centre column and the left/right middle strips
	piece(UDim2.new(0, r, 0, 0), UDim2.new(1, -2 * r, 1, 0))
	piece(UDim2.new(0, 0, 0, r), UDim2.new(0, r, 1, -2 * r))
	piece(UDim2.new(1, -r, 0, r), UDim2.new(0, r, 1, -2 * r))
	local corners = {
		tl = { UDim2.new(0, 0, 0, 0), UDim2.fromOffset(0, 0) },
		tr = { UDim2.new(1, -r, 0, 0), UDim2.fromOffset(-r, 0) },
		bl = { UDim2.new(0, 0, 1, -r), UDim2.fromOffset(0, -r) },
		br = { UDim2.new(1, -r, 1, -r), UDim2.fromOffset(-r, -r) },
	}
	for name, spec in pairs(corners) do
		if round[name] then
			local clip = Create.New("Frame", {
				Position = spec[1],
				Size = UDim2.fromOffset(r, r),
				ClipsDescendants = true,
				ZIndex = opts.zindex or 0,
				Parent = holder,
			})
			local circle = Create.New("Frame", {
				Position = spec[2],
				Size = UDim2.fromOffset(2 * r, 2 * r),
				BackgroundColor3 = opts.color,
				BackgroundTransparency = opts.transparency or 0,
				ZIndex = opts.zindex or 0,
				Parent = clip,
			})
			Create.corner(r).Parent = circle
		else
			piece(spec[1], UDim2.fromOffset(r, r))
		end
	end
	return holder
end

-- Text helper: Create.text(text, { size = "fontDesc", color = "textMuted", weight = "Medium", wrap = true })
function Create.text(text, options)
	options = options or {}
	local label = Create.New("TextLabel", {
		Text = text or "",
		Weight = options.weight,
		Mono = options.mono,
		TextColor3 = Theme.c(options.color or "text"),
		TextSize = Theme.s(options.size or "font"),
		TextWrapped = options.wrap or false,
		TextTruncate = options.truncate and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
		AutomaticSize = options.autoX and Enum.AutomaticSize.XY or (options.wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None),
		Size = options.sizeUDim or (options.autoX and UDim2.new() or UDim2.new(1, 0, 0, 0)),
		LayoutOrder = options.order or 0,
		RichText = options.rich or false,
		Name = options.name or "Text",
	})
	if options.align then
		label.TextXAlignment = Enum.TextXAlignment[options.align]
	end
	if not options.wrap and not options.autoX and not options.sizeUDim then
		Theme.bind(label, "Size", Theme.f(function(_, s)
			return UDim2.new(1, 0, 0, math.ceil((s[options.size or "font"] or 14) * 1.3))
		end))
	end
	return label
end

return Create
