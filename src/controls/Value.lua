-- Slider (number / range), Stepper, SegmentedControl, Input, Textarea.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Device = import("core/Device")
local Services = import("core/Services")
local Util = import("util/Util")
local Control = import("controls/Base")

local New = Create.New
local C, S = Theme.c, Theme.s

local Controls = {}

-- Shared: normalise an options list to { { Value, Text } }.
function Controls.normalizeOptions(list)
	local out = {}
	for _, option in ipairs(list or {}) do
		if type(option) == "table" and (option.Value ~= nil or option.Text ~= nil or option.Title ~= nil) then
			local value = option.Value
			if value == nil then
				value = option.Text or option.Title
			end
			table.insert(out, { Value = value, Text = option.Text or option.Title or tostring(value), Icon = option.Icon, Description = option.Description })
		else
			table.insert(out, { Value = option, Text = type(option) == "table" and option or tostring(option) })
		end
	end
	return out
end

-- Slider ----------------------------------------------------------------------------

local Slider = Control.extend("Slider")

function Controls.Slider(section, opts)
	local min, max = opts.Min or 0, opts.Max or 100
	if min > max then
		min, max = max, min
	end
	local step = opts.Step or opts.Increment or 1
	local range = opts.Range == true
	local default = opts.Default
	if range then
		default = type(default) == "table" and default or { min, max }
	else
		default = tonumber(default) or min
	end
	local self = Control.new(section, opts, {
		class = Slider, kind = "Slider", value = true, default = default, layout = "stack",
		validate = function(v)
			if range then
				if type(v) ~= "table" then
					return nil
				end
				return { math.clamp(tonumber(v[1]) or min, min, max), math.clamp(tonumber(v[2]) or max, min, max) }
			end
			return math.clamp(tonumber(v) or min, min, max)
		end,
	})
	self.Min, self.Max, self.Step, self.IsRange = min, max, step, range

	self.ValueLabel = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		TextColor3 = C("textMuted"),
		TextSize = S("fontDesc"),
		LayoutOrder = 5,
		Parent = self.Right,
	})
	Theme.bind(self.ValueLabel, "TextSize", Theme.f(function(_, s)
		return s.font - 1
	end))

	local area = New("TextButton", {
		Name = "Area",
		Size = Theme.sz(1, 0, 0, "sliderHit"),
		BackgroundTransparency = 1,
		Parent = self.Body,
	})
	self.Area = area
	local track = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = Theme.sz(1, 0, 0, "track"),
		BackgroundColor3 = C("track"),
		Parent = area,
	}, { Create.corner("full") })
	self.Fill = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C("accent"),
		Parent = track,
	}, { Create.corner("full") })

	local function knob()
		local k = New("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = Theme.sz(0, "sliderKnob", 0, "sliderKnob"),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 2,
			Parent = area,
		}, { Create.corner("full") })
		local stroke = Create.stroke("borderStrong", 1)
		Theme.bind(stroke, "Transparency", Theme.f(function(_, s)
			return s.touch and 0 or 1
		end))
		stroke.Parent = k
		New("UIScale", { Parent = k })
		return k
	end
	self.Knobs = { knob() }
	if range then
		table.insert(self.Knobs, knob())
	end

	-- dragging
	local dragging, active = nil, 1
	local function valueAt(x)
		local ap, as = area.AbsolutePosition.X, area.AbsoluteSize.X
		local ratio = as > 0 and math.clamp((x - ap) / as, 0, 1) or 0
		return Util.snap(min + ratio * (max - min), step, min)
	end
	local function apply(x)
		local value = valueAt(x)
		if range then
			local current = self:Get()
			local pair = { current[1], current[2] }
			pair[active] = value
			if pair[1] > pair[2] then
				pair[1], pair[2] = pair[2], pair[1]
				active = 3 - active
			end
			self:Set(pair)
		else
			self:Set(value)
		end
	end
	local function stop()
		if dragging then
			for _, connection in ipairs(dragging) do
				connection:Disconnect()
			end
			dragging = nil
			self.Tab.Page.ScrollingEnabled = true
			for _, k in ipairs(self.Knobs) do
				Motion.tween(k:FindFirstChildOfClass("UIScale"), { Scale = 1 }, "spring")
			end
		end
	end
	self.Maid:Add(stop)
	self.Maid:Add(area.InputBegan:Connect(function(input)
		if not self.Enabled then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		stop()
		local x = Device.pointer(input).X
		if range then
			local current = self:Get()
			local function screenX(v)
				return area.AbsolutePosition.X + (v - min) / math.max(max - min, 1e-9) * area.AbsoluteSize.X
			end
			active = math.abs(x - screenX(current[1])) <= math.abs(x - screenX(current[2])) and 1 or 2
		end
		local scale = self.Knobs[active]:FindFirstChildOfClass("UIScale")
		Motion.tween(scale, { Scale = 1.12 }, "press")
		apply(x)
		-- keep the page from scrolling while the finger drags the knob
		self.Tab.Page.ScrollingEnabled = false
		local uis = Services.UserInputService
		dragging = {
			uis.InputChanged:Connect(function(changed)
				if changed.UserInputType == Enum.UserInputType.MouseMovement or (changed.UserInputType == Enum.UserInputType.Touch and changed == input) then
					apply(Device.pointer(changed).X)
				end
			end),
			uis.InputEnded:Connect(function(ended)
				if ended == input or ended.UserInputType == Enum.UserInputType.MouseButton1 then
					stop()
				end
			end),
		}
	end))
	self:_finish()
	return self
end

function Slider:_validate(v)
	if self.IsRange then
		if type(v) ~= "table" then
			return self:Get()
		end
		local a = Util.snap(math.clamp(tonumber(v[1]) or self.Min, self.Min, self.Max), self.Step, self.Min)
		local b = Util.snap(math.clamp(tonumber(v[2]) or self.Max, self.Min, self.Max), self.Step, self.Min)
		return { math.min(a, b), math.max(a, b) }
	end
	return Util.snap(math.clamp(tonumber(v) or self.Min, self.Min, self.Max), self.Step, self.Min)
end

function Slider:_format(v)
	local suffix = self.Options.Suffix
	local text = Util.formatNumber(v, self.Step)
	if suffix then
		text ..= " " .. self.Loc:Get(suffix)
	end
	return text
end

function Slider:_render(value, animate)
	if value == nil then
		return
	end
	local span = math.max(self.Max - self.Min, 1e-9)
	local a, b
	if self.IsRange then
		a, b = (value[1] - self.Min) / span, (value[2] - self.Min) / span
		self.ValueLabel.Text = Util.formatNumber(value[1], self.Step) .. " – " .. self:_format(value[2])
	else
		a, b = 0, (value - self.Min) / span
		self.ValueLabel.Text = self:_format(value)
	end
	local props = {
		fill = { Position = UDim2.new(a, 0, 0.5, 0), Size = UDim2.fromScale(b - a, 1) },
	}
	local function set(instance, p)
		if animate then
			Motion.tween(instance, p, "press")
		else
			for k, v in pairs(p) do
				instance[k] = v
			end
		end
	end
	set(self.Fill, props.fill)
	if self.IsRange then
		set(self.Knobs[1], { Position = UDim2.fromScale(a, 0.5) })
		set(self.Knobs[2], { Position = UDim2.fromScale(b, 0.5) })
	else
		set(self.Knobs[1], { Position = UDim2.fromScale(b, 0.5) })
	end
end

function Slider:StateText()
	return self.ValueLabel.Text
end

-- Stepper -----------------------------------------------------------------------------

local Stepper = Control.extend("Stepper")

function Controls.Stepper(section, opts)
	local min, max = opts.Min or -math.huge, opts.Max or math.huge
	local step = opts.Step or 1
	local self = Control.new(section, opts, {
		class = Stepper, kind = "Stepper", value = true, default = tonumber(opts.Default) or math.max(0, min),
		validate = function(v)
			return math.clamp(tonumber(v) or 0, min, max)
		end,
	})
	self.Min, self.Max, self.Step = min, max, step
	local box = New("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = Theme.sz(0, 0, 0, "control"),
		BackgroundColor3 = C("raised"),
		LayoutOrder = 5,
		Parent = self.Right,
	}, { Create.corner("rSmall"), Create.list("Horizontal", 0, { valign = "Center" }) })
	local function stepButton(icon, order, delta)
		local button = New("TextButton", {
			Size = Theme.sz(0, "stepperBtn", 1, 0),
			LayoutOrder = order,
			Parent = box,
		})
		local glyph = Icons.new(icon, 14, C("text"), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		glyph.Frame.Parent = button
		Motion.pressable(button, glyph.Frame, 0.8, self.Maid)
		local holding = 0
		local function bump()
			if self.Enabled then
				self:Set(self:Get() + delta * step)
			end
		end
		self.Maid:Add(button.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			holding += 1
			local mine = holding
			-- stop repeating when this touch/click ends anywhere on screen
			local ended
			ended = Services.UserInputService.InputEnded:Connect(function(other)
				if other == input or other.UserInputType == Enum.UserInputType.MouseButton1 then
					ended:Disconnect()
					if holding == mine then
						holding += 1
					end
				end
			end)
			bump()
			task.delay(0.4, function()
				while holding == mine and not self.Destroyed do
					bump()
					task.wait(0.07)
				end
			end)
		end))
		self.Maid:Add(button.InputEnded:Connect(function()
			holding += 1
		end))
		self.Maid:Add(button.MouseLeave:Connect(function()
			holding += 1
		end))
		return button
	end
	stepButton("minus", 1, -1)
	self.ValueLabel = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Weight = "SemiBold",
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = box,
	}, { Create.minSize(28, 0) })
	self.ValueLabel.TextXAlignment = Enum.TextXAlignment.Center
	stepButton("plus", 3, 1)
	self:_finish()
	return self
end

function Stepper:_validate(v)
	local value = math.clamp(tonumber(v) or 0, self.Min, self.Max)
	return Util.snap(value, self.Step, self.Min > -math.huge and self.Min or 0)
end

function Stepper:_render(value)
	local text = Util.formatNumber(value, self.Step)
	if self.Options.Suffix then
		text ..= " " .. self.Loc:Get(self.Options.Suffix)
	end
	self.ValueLabel.Text = text
end

function Stepper:StateText()
	return self.ValueLabel.Text
end

-- SegmentedControl ------------------------------------------------------------------------

local Segmented = Control.extend("Segmented")

function Controls.Segmented(section, opts)
	local options = Controls.normalizeOptions(opts.Options or opts.Values)
	local default = opts.Default
	if default == nil and options[1] then
		default = options[1].Value
	end
	local full = opts.Full == true
	local self = Control.new(section, opts, {
		class = Segmented, kind = "Segmented", value = true, default = default,
		layout = full and "stack" or "row",
		validate = function(v)
			for _, option in ipairs(options) do
				if option.Value == v then
					return v
				end
			end
			return default
		end,
	})
	self.Items = options
	local track = New("Frame", {
		Name = "Segments",
		AutomaticSize = full and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		Size = full and Theme.f(function(_, s)
			return UDim2.new(1, 0, 0, s.segment + 4)
		end) or Theme.f(function(_, s)
			return UDim2.fromOffset(0, s.segment + 4)
		end),
		BackgroundColor3 = C("sunken"),
		LayoutOrder = 5,
		Parent = full and self.Body or self.Right,
	}, { Create.corner("rSmall") })
	self.Thumb = New("Frame", {
		Name = "Thumb",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = C("segment"),
		Parent = track,
	}, { Create.corner(7) })
	local buttons = New("Frame", {
		AutomaticSize = full and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		Size = full and UDim2.fromScale(1, 1) or UDim2.fromScale(0, 1),
		ZIndex = 2,
		Parent = track,
	}, { Create.pad(2), Create.list("Horizontal", 2, { valign = "Center" }) })
	self.Track = track
	self.Buttons = {}
	for index, option in ipairs(options) do
		local button = New("TextButton", {
			AutomaticSize = full and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
			Size = Theme.sz(0, 0, 0, "segment"),
			TextColor3 = C("textMuted"),
			Weight = "Medium",
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = index,
			ZIndex = 2,
			Parent = buttons,
		}, { Create.pad(0, 12), Create.maxSize(150, nil) })
		button.TextXAlignment = Enum.TextXAlignment.Center
		Theme.bind(button, "TextSize", Theme.f(function(_, s)
			return s.font - 1
		end))
		if full then
			Create.flex().Parent = button
		end
		self.Loc:Bind(button, "Text", option.Text)
		self.Window.Tooltip:Attach(button, option.Text, self.Maid, nil, function()
			return not button.TextFits
		end)
		self.Maid:Add(button.Activated:Connect(function()
			if self.Enabled then
				self:Set(option.Value)
			end
		end))
		self.Maid:Add(button:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_placeThumb(false)
		end))
		self.Maid:Add(button:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			self:_placeThumb(false)
		end))
		self.Buttons[index] = button
	end
	self:_finish()
	return self
end

function Segmented:_index(value)
	for index, option in ipairs(self.Items) do
		if option.Value == value then
			return index
		end
	end
	return 1
end

function Segmented:_placeThumb(animate)
	local button = self.Buttons[self:_index(self:Get())]
	if not button then
		return
	end
	local offset = button.AbsolutePosition - self.Track.AbsolutePosition
	local props = {
		Position = UDim2.fromOffset(offset.X, offset.Y),
		Size = UDim2.fromOffset(button.AbsoluteSize.X, button.AbsoluteSize.Y),
	}
	if animate then
		Motion.tween(self.Thumb, props, "spring")
	else
		self.Thumb.Position = props.Position
		self.Thumb.Size = props.Size
	end
end

function Segmented:_render(value, animate)
	local selected = self:_index(value)
	for index, button in ipairs(self.Buttons) do
		local on = index == selected
		button.FontFace = Theme.font(on and "SemiBold" or "Medium")
		Theme.set(button, "TextColor3", on and C("text") or C("textMuted"), "fade")
	end
	self:_placeThumb(animate)
	task.defer(function()
		if not self.Destroyed then
			self:_placeThumb(false)
		end
	end)
end

function Segmented:StateText()
	local option = self.Items[self:_index(self:Get())]
	return option and self.Loc:Get(option.Text) or nil
end

-- Input & Textarea ------------------------------------------------------------------------

local Input = Control.extend("Input")

local function buildInput(section, opts, multiline)
	local numeric = opts.Numeric == true
	local default = opts.Default
	if default == nil then
		default = numeric and (opts.Min or 0) or ""
	end
	local self = Control.new(section, opts, {
		class = Input, kind = multiline and "Textarea" or "Input", value = true, default = default, layout = "stack",
		validate = function(v)
			if numeric then
				return tonumber(v) or default
			end
			return tostring(v)
		end,
	})
	self.Numeric, self.Multiline = numeric, multiline
	local field = New("Frame", {
		Name = "Field",
		Size = multiline and UDim2.new(1, 0, 0, opts.Height or 76) or Theme.sz(1, 0, 0, "input"),
		BackgroundColor3 = C("bg"),
		Parent = self.Body,
	}, {
		Create.corner("rControl"),
		Create.pad(multiline and 10 or 0, 12),
		Create.list("Horizontal", 8, { valign = multiline and "Top" or "Center" }),
	})
	self.Stroke = Create.stroke("borderStrong", 1)
	self.Stroke.Parent = field
	self.Box = New("TextBox", {
		Size = UDim2.fromScale(0, 1),
		TextWrapped = multiline,
		MultiLine = multiline,
		TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		TextTruncate = multiline and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
		Parent = field,
	}, { Create.flex() })
	if opts.Placeholder then
		self.Loc:Bind(self.Box, "PlaceholderText", opts.Placeholder)
	end
	if opts.Suffix then
		local suffix = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C("textSubtle"),
			TextSize = S("fontDesc"),
			LayoutOrder = 2,
			Parent = field,
		})
		self.Loc:Bind(suffix, "Text", opts.Suffix)
	end
	self.Maid:Add(self.Box.Focused:Connect(function()
		Theme.set(self.Stroke, "Color", C("accent"))
		self.Stroke.Thickness = 1.5
	end))
	local function commit()
		local text = self.Box.Text
		if opts.MaxLength and #text > opts.MaxLength then
			text = text:sub(1, opts.MaxLength)
		end
		if numeric then
			local number = tonumber((text:gsub(",", ".")))
			if number == nil then
				self:_render(self:Get())
				return
			end
			if opts.Min or opts.Max then
				number = math.clamp(number, opts.Min or -math.huge, opts.Max or math.huge)
			end
			self:Set(number)
			self:_render(self:Get())
		else
			self:Set(text)
		end
	end
	self.Maid:Add(self.Box.FocusLost:Connect(function()
		Theme.set(self.Stroke, "Color", C("borderStrong"))
		self.Stroke.Thickness = 1
		commit()
		if opts.Finished then
			task.spawn(opts.Finished, self:Get())
		end
	end))
	if opts.Live then
		self.Maid:Add(self.Box:GetPropertyChangedSignal("Text"):Connect(function()
			if self.Box:IsFocused() then
				commit()
			end
		end))
	end
	self:_finish()
	return self
end

function Input:_render(value)
	local text = value == nil and "" or tostring(value)
	if self.Box.Text ~= text then
		self.Box.Text = text
	end
end

function Input:StateText()
	local value = self:Get()
	if value == nil or value == "" then
		return nil
	end
	local text = tostring(value)
	if #text > 18 then
		text = text:sub(1, 16) .. "…"
	end
	return text
end

function Input:Focus()
	self.Box:CaptureFocus()
end

function Controls.Input(section, opts)
	return buildInput(section, opts, false)
end

function Controls.Textarea(section, opts)
	return buildInput(section, opts, true)
end

return Controls
