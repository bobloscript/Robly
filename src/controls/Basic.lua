-- Toggle, Checkbox, Button, Buttons (group), Label, Paragraph, Divider,
-- Badge, Image, ProgressBar, Code.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Compat = import("util/Compat")
local Control = import("controls/Base")

local New = Create.New
local C, S = Theme.c, Theme.s

local Controls = {}

-- Toggle ----------------------------------------------------------------------------

local Toggle = Control.extend("Toggle")

function Controls.Toggle(section, opts)
	local self = Control.new(section, opts, {
		class = Toggle, kind = "Toggle", value = true, default = opts.Default == true,
		rowClick = true,
		validate = function(v)
			return v == true
		end,
	})
	local track = New("TextButton", {
		Name = "Switch",
		Size = Theme.sz(0, "toggleW", 0, "toggleH"),
		BackgroundColor3 = C("toggleOff"),
		LayoutOrder = 5,
		Parent = self.Right,
	}, { Create.corner("full") })
	self.TrackGradient = New("UIGradient", { Color = Theme.gradient(), Enabled = false, Parent = track })
	-- glow ring around the switch while it is on
	self.Glow = New("UIStroke", {
		Color = C("accent"),
		Thickness = 3,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = track,
	})
	self.Knob = New("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = Theme.sz(0, "knob", 0, "knob"),
		BackgroundColor3 = C("knobOff"),
		Parent = track,
	}, { Create.corner("full") })
	self.Track = track
	Motion.pressable(track, nil, 0.94, self.Maid)
	local function flip()
		self:Set(not self:Get())
	end
	self.Maid:Add(track.Activated:Connect(flip))
	self.Maid:Add(self.Hit.Activated:Connect(flip))
	self:_finish()
	return self
end

function Toggle:_validate(v)
	return v == true
end

function Toggle:_render(on, animate)
	-- on: white base × accent→accent2 gradient
	self.TrackGradient.Enabled = on == true
	if animate then
		Motion.tween(self.Glow, { Transparency = on and 0.75 or 1 }, "fade")
	else
		self.Glow.Transparency = on and 0.75 or 1
	end
	self:_setActive(on == true, animate)
	local trackColor = on and Theme.f(function()
		return Color3.new(1, 1, 1)
	end) or C("toggleOff")
	local knobColor = on and C("knobOn") or C("knobOff")
	local anchor = on and Vector2.new(1, 0.5) or Vector2.new(0, 0.5)
	local position = on and UDim2.new(1, -2, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	if animate then
		Theme.set(self.Track, "BackgroundColor3", trackColor)
		Theme.set(self.Knob, "BackgroundColor3", knobColor)
		Motion.tween(self.Knob, { AnchorPoint = anchor, Position = position }, "spring")
	else
		Theme.bind(self.Track, "BackgroundColor3", trackColor)
		Theme.bind(self.Knob, "BackgroundColor3", knobColor)
		self.Knob.AnchorPoint = anchor
		self.Knob.Position = position
	end
end

function Toggle:StateText()
	return self.Loc:Lib(self:Get() and "on_short" or "off_short")
end

function Toggle:QuickState()
	return self:Get() == true
end

function Toggle:QuickActivate()
	self:Set(not self:Get())
	return self:Get()
end

-- Checkbox --------------------------------------------------------------------------

local Checkbox = Control.extend("Checkbox")

function Controls.Checkbox(section, opts)
	local self = Control.new(section, opts, {
		class = Checkbox, kind = "Checkbox", value = true, default = opts.Default == true,
		rowClick = true, left = true,
		validate = function(v)
			return v == true
		end,
	})
	local box = New("TextButton", {
		Name = "Box",
		Size = Theme.sz(0, "checkbox", 0, "checkbox"),
		BackgroundColor3 = C("accent"),
		BackgroundTransparency = 1,
		Parent = self.Left,
	}, { Create.corner(6), New("UIGradient", { Color = Theme.gradient(), Rotation = 45 }) })
	box.BackgroundColor3 = Color3.new(1, 1, 1)
	self.Stroke = Create.stroke("checkBorder", 1.5)
	self.Stroke.Parent = box
	self.Check = Icons.new("check", Theme.Sizes.touch and 18 or 14, C("accentInk"), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	self.Check.Frame.Parent = box
	self.CheckScale = New("UIScale", { Parent = self.Check.Frame })
	self.Box = box
	Motion.pressable(box, nil, 0.9, self.Maid)
	local function flip()
		self:Set(not self:Get())
	end
	self.Maid:Add(box.Activated:Connect(flip))
	self.Maid:Add(self.Hit.Activated:Connect(flip))
	self:_finish()
	return self
end

function Checkbox:_validate(v)
	return v == true
end

function Checkbox:_render(on, animate)
	local tween = animate and Motion.tween or function(instance, props)
		for k, v in pairs(props) do
			instance[k] = v
		end
	end
	self:_setActive(on == true, animate)
	tween(self.Box, { BackgroundTransparency = on and 0 or 1 }, "fade")
	tween(self.Stroke, { Transparency = on and 1 or 0 }, "fade")
	self.Check.Frame.Visible = on
	if on and animate then
		self.CheckScale.Scale = 0.6
		Motion.tween(self.CheckScale, { Scale = 1 }, "spring")
	else
		self.CheckScale.Scale = 1
	end
end

Checkbox.StateText = Toggle.StateText
Checkbox.QuickState = Toggle.QuickState
Checkbox.QuickActivate = Toggle.QuickActivate

-- Button ------------------------------------------------------------------------------

local VARIANTS = {
	Primary = { bg = "accent", fg = "accentInk", weight = "SemiBold", gradient = true },
	Secondary = { bg = "raised", fg = "text", pressed = "segment", weight = "Medium" },
	Text = { bg = nil, fg = "accent", weight = "SemiBold" },
	Danger = { bg = "danger", fg = "dangerInk", weight = "SemiBold" },
}
Controls.ButtonVariants = VARIANTS

local function makeButton(control, spec, parent, order)
	local variant = VARIANTS[spec.Variant or "Secondary"] or VARIANTS.Secondary
	local button = New("TextButton", {
		Name = "Button",
		Size = Theme.sz(1, 0, 0, "button"),
		BackgroundColor3 = variant.bg and C(variant.bg) or C("raised"),
		BackgroundTransparency = variant.bg and 0 or 1,
		LayoutOrder = order or 1,
		Parent = parent,
	}, {
		Create.corner("rControl"),
		Create.pad(0, 12),
		Create.list("Horizontal", 8, { align = "Center", valign = "Center" }),
	})
	if variant.gradient then
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		New("UIGradient", { Color = Theme.gradient(), Parent = button })
	end
	if spec.Icon then
		local icon = Icons.new(spec.Icon, "iconSmall", C(variant.fg))
		icon.Frame.LayoutOrder = 1
		icon.Frame.Parent = button
	end
	local label = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C(variant.fg),
		Weight = variant.weight,
		LayoutOrder = 2,
		Parent = button,
	})
	label.TextTruncate = Enum.TextTruncate.AtEnd
	control.Loc:Bind(label, "Text", spec.Title or spec.Text or "")
	Motion.pressable(button, nil, 0.97, control.Maid)
	if variant.pressed then
		control.Maid:Add(button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				Theme.set(button, "BackgroundColor3", C(variant.pressed), "press")
			end
		end))
		control.Maid:Add(button.InputEnded:Connect(function()
			Theme.set(button, "BackgroundColor3", C(variant.bg), "fade")
		end))
	end
	local function run()
		if not control.Enabled then
			return
		end
		local callback = spec.Callback
		if not callback then
			return
		end
		if spec.Confirm then
			local confirm = type(spec.Confirm) == "table" and spec.Confirm or {}
			control.Window:Dialog({
				Title = confirm.Title or (type(spec.Confirm) ~= "table" and spec.Confirm ~= true and spec.Confirm) or spec.Title or spec.Text,
				Content = confirm.Content,
				Buttons = {
					{ Text = { __lib = "cancel" }, Variant = "Secondary" },
					{ Text = confirm.Confirm or spec.Title or spec.Text or { __lib = "ok" }, Variant = spec.Variant == "Danger" and "Danger" or "Primary", Callback = function()
						task.spawn(callback)
					end },
				},
			})
		else
			task.spawn(callback)
		end
	end
	control.Maid:Add(button.Activated:Connect(run))
	return button, run
end

local Button = Control.extend("Button")

function Controls.Button(section, opts)
	local self = Control.new(section, opts, { class = Button, kind = "Button", layout = "custom" })
	self.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
	Create.list("Vertical", 6).Parent = self.Inner
	local button, run = makeButton(self, opts, self.Inner, 1)
	self.Button = button
	self._run = run
	if self.DescSpec then
		local desc = Create.text("", { size = "fontDesc", color = "textSubtle", wrap = true, order = 2 })
		desc.Parent = self.Inner
		self.Loc:Bind(desc, "Text", self.DescSpec)
	end
	return self
end

function Button:QuickActivate()
	self._run()
	return nil
end

function Button:QuickState()
	return "action"
end

-- Buttons: several buttons in one row ------------------------------------------------

local Buttons = Control.extend("Buttons")

function Controls.Buttons(section, opts)
	local list = opts.Buttons or opts
	local self = Control.new(section, { Title = opts.Title }, { class = Buttons, kind = "Buttons", layout = "custom", searchable = false })
	self.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
	Create.list("Horizontal", 8).Parent = self.Inner
	self.Buttons = {}
	for index, spec in ipairs(list) do
		local button = makeButton(self, spec, self.Inner, index)
		button.Size = UDim2.new(0, 0, 0, 0)
		Theme.bind(button, "Size", Theme.sz(0, 0, 0, "button"))
		Create.flex().Parent = button
		table.insert(self.Buttons, button)
	end
	return self
end

-- Label & Paragraph ----------------------------------------------------------------

local Label = Control.extend("Label")

function Controls.Label(section, opts)
	if type(opts) ~= "table" then
		opts = { Title = opts }
	end
	local self = Control.new(section, opts, { class = Label, kind = "Label", titleWeight = "SemiBold", searchable = false })
	return self
end

function Label:SetText(spec)
	return self:SetTitle(spec)
end

local Paragraph = Control.extend("Paragraph")

function Controls.Paragraph(section, opts)
	if type(opts) ~= "table" then
		opts = { Content = opts }
	end
	local self = Control.new(section, { Title = opts.Title, VisibleWhen = opts.VisibleWhen }, {
		class = Paragraph, kind = "Paragraph", layout = "stack", titleWeight = "SemiBold", searchable = false,
	})
	if not opts.Title then
		self.Inner:FindFirstChild("Top").Visible = false
	end
	self.Content = Create.text("", { size = "fontDesc", color = "textMuted", wrap = true })
	self.Content.LineHeight = 1.15
	self.Content.RichText = opts.RichText == true
	self.Content.Parent = self.Body
	self.Loc:Bind(self.Content, "Text", opts.Content or opts.Text or "", opts.Vars)
	return self
end

function Paragraph:SetContent(spec, vars)
	self.Loc:Bind(self.Content, "Text", spec, vars)
	return self
end

-- Divider ------------------------------------------------------------------------------

local Divider = Control.extend("Divider")

function Controls.Divider(section, opts)
	local self = Control.new(section, type(opts) == "table" and opts or {}, { class = Divider, kind = "Divider", layout = "custom", searchable = false })
	self.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
	self.Inner:FindFirstChildOfClass("UIPadding"):Destroy()
	New("Frame", { Size = UDim2.new(1, 0, 0, 6), Parent = self.Inner })
	self.Divider.Visible = false
	self._noDivider = true
	return self
end

-- Badge ----------------------------------------------------------------------------------

local BADGES = {
	accent = { bg = "accent", fg = "accentInk", alpha = 0 },
	neutral = { bg = "raised", fg = "textMuted", alpha = 0 },
	success = { bg = "success", fg = "success", alpha = 0.88 },
	warning = { bg = "warning", fg = "warning", alpha = 0.88 },
	danger = { bg = "danger", fg = "danger", alpha = 0.88 },
}
Controls.BadgeStyles = BADGES

function Controls.makeBadge(loc, text, variant, order)
	local style = BADGES[variant or "neutral"] or BADGES.neutral
	local badge = New("TextLabel", {
		Name = "Badge",
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = C(style.bg),
		BackgroundTransparency = style.alpha,
		TextColor3 = C(style.fg),
		Weight = "SemiBold",
		TextSize = S("fontSmall"),
		LayoutOrder = order or 0,
	}, { Create.corner("rBadge"), Create.pad(3, 8) })
	loc:Bind(badge, "Text", text or "")
	return badge
end

local Badge = Control.extend("Badge")

function Controls.Badge(section, opts)
	local self = Control.new(section, opts, { class = Badge, kind = "Badge", searchable = false })
	self.Badge = Controls.makeBadge(self.Loc, opts.Text or opts.Value or "", opts.Variant or "accent", 5)
	self.Badge.Parent = self.Right
	return self
end

function Badge:SetText(spec, variant)
	self.Loc:Bind(self.Badge, "Text", spec)
	if variant and BADGES[variant] then
		local style = BADGES[variant]
		Theme.bind(self.Badge, "BackgroundColor3", C(style.bg))
		Theme.bind(self.Badge, "TextColor3", C(style.fg))
		self.Badge.BackgroundTransparency = style.alpha
	end
	return self
end

-- Image ----------------------------------------------------------------------------------

local Image = Control.extend("Image")

function Controls.Image(section, opts)
	local self = Control.new(section, opts, { class = Image, kind = "Image", layout = "stack", searchable = false })
	if not opts.Title then
		self.Inner:FindFirstChild("Top").Visible = false
	end
	self.Image = New("ImageLabel", {
		Size = UDim2.new(1, 0, 0, opts.Height or 140),
		BackgroundColor3 = C("sunken"),
		Image = opts.Image or "",
		ScaleType = Enum.ScaleType[opts.ScaleType or "Fit"],
		Parent = self.Body,
	}, { Create.corner("rControl") })
	return self
end

function Image:SetImage(image)
	self.Image.Image = image
	return self
end

-- ProgressBar --------------------------------------------------------------------------

local Progress = Control.extend("ProgressBar")

function Controls.ProgressBar(section, opts)
	local self = Control.new(section, opts, { class = Progress, kind = "ProgressBar", layout = "stack", searchable = false })
	self.Max = opts.Max or 100
	self.ValueLabel = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		TextSize = S("fontDesc"),
		LayoutOrder = 5,
		Parent = self.Right,
	})
	local track = New("Frame", {
		Size = Theme.sz(1, 0, 0, "track"),
		BackgroundColor3 = C("track"),
		Parent = self.Body,
	}, { Create.corner("full") })
	self.Fill = New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	}, { Create.corner("full"), New("UIGradient", { Color = Theme.gradient() }) })
	self.Value = 0
	self:SetValue(opts.Value or opts.Default or 0, false)
	return self
end

function Progress:SetValue(value, animate)
	self.Value = math.clamp(tonumber(value) or 0, 0, self.Max)
	local ratio = self.Max > 0 and self.Value / self.Max or 0
	if animate == false then
		self.Fill.Size = UDim2.fromScale(ratio, 1)
	else
		Motion.tween(self.Fill, { Size = UDim2.fromScale(ratio, 1) }, "window")
	end
	if self.Options.Format then
		self.ValueLabel.Text = self.Options.Format(self.Value, self.Max)
	else
		self.ValueLabel.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
	end
	return self
end
Progress.Set = Progress.SetValue

function Progress:Get()
	return self.Value
end

-- Code -------------------------------------------------------------------------------------

local Code = Control.extend("Code")

function Controls.Code(section, opts)
	local self = Control.new(section, opts, { class = Code, kind = "Code", layout = "custom", searchable = false })
	self.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
	self.Text = opts.Code or opts.Content or ""
	local block = New("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C("code"),
		Parent = self.Inner,
	}, { Create.corner(12), Create.stroke("border"), Create.list("Vertical", 0) })
	local head = New("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 1,
		Parent = block,
	}, { Create.pad(0, 6, 0, 12), Create.list("Horizontal", 6, { valign = "Center" }) })
	local lang = New("TextLabel", {
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C("textSubtle"),
		TextSize = 12,
		LayoutOrder = 1,
		Parent = head,
	}, { Create.flex() })
	self.Loc:Bind(lang, "Text", opts.Title or opts.Language or "Luau")
	local copy, copyLabel, copyIcon = Control.chip({
		icon = "copy", size = UDim2.fromOffset(0, 26), bg = C("overlay"), padLeft = 8, padRight = 8,
		textSize = 12, iconSize = 13, iconColor = C("text"), order = 2,
	})
	copy.Parent = head
	copyIcon.Frame.LayoutOrder = 0
	self.Loc:Bind(copyLabel, "Text", { __lib = "copy" })
	Motion.pressable(copy, nil, nil, self.Maid)
	New("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C("border"), LayoutOrder = 2, Parent = block })
	self.CodeLabel = New("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = self.Text,
		TextColor3 = C("codeText"),
		TextSize = 12,
		Mono = true,
		TextWrapped = true,
		LineHeight = 1.25,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 3,
		Parent = block,
	}, { Create.pad(12) })
	self.Maid:Add(copy.Activated:Connect(function()
		if Compat.clipboard(self.Text) then
			self.Window:Notify({ Title = { __lib = "copied" }, Type = "success", Duration = 2 })
		else
			self.Window:Dialog({
				Title = { __lib = "copy_failed" },
				Input = { Default = self.Text, Mono = true },
				Buttons = { { Text = { __lib = "ok" }, Variant = "Primary" } },
			})
		end
	end))
	return self
end

function Code:SetCode(text)
	self.Text = tostring(text)
	self.CodeLabel.Text = self.Text
	return self
end

return Controls
