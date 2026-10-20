-- ColorPicker: swatch in the row; popup with saturation/value square (two
-- UIGradients), hue bar, HEX field and quick swatches.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Device = import("core/Device")
local Services = import("core/Services")
local Util = import("util/Util")
local Control = import("controls/Base")

local New = Create.New
local C, S = Theme.c, Theme.s

local ColorPicker = Control.extend("ColorPicker")

local SWATCHES = { "FF3B7F", "4C8DFF", "34D399", "F5A524", "A78BFA", "F2F2F5" }

local function toColor(value)
	if typeof(value) == "Color3" then
		return value
	end
	return Util.hex(value)
end

local function constructor(section, opts)
	local default = toColor(opts.Default) or Color3.fromRGB(255, 59, 127)
	local self = Control.new(section, opts, {
		class = ColorPicker, kind = "ColorPicker", value = true, default = default,
		validate = function(v)
			return toColor(v)
		end,
	})
	self.HexLabel = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		Mono = true,
		TextColor3 = C("textMuted"),
		TextSize = 12,
		LayoutOrder = 4,
		Parent = self.Right,
	})
	local swatch = New("TextButton", {
		Name = "Swatch",
		Size = Theme.f(function(_, s)
			local size = s.touch and 36 or 28
			return UDim2.fromOffset(size, size)
		end),
		BackgroundColor3 = default,
		LayoutOrder = 5,
		Parent = self.Right,
	}, { Create.corner(8), Create.stroke("borderStrong") })
	self.Swatch = swatch
	Motion.pressable(swatch, nil, 0.92, self.Maid)
	self.Maid:Add(swatch.Activated:Connect(function()
		if self.Enabled then
			self:Open()
		end
	end))
	self:_finish()
	return self
end

function ColorPicker:_validate(value)
	return toColor(value) or self:Get()
end

function ColorPicker:_render(color)
	if typeof(color) ~= "Color3" then
		return
	end
	self.Swatch.BackgroundColor3 = color
	self.HexLabel.Text = "#" .. Util.toHex(color)
	if self._sync then
		self._sync(color)
	end
end

function ColorPicker:StateText()
	return self.HexLabel.Text
end

-- Generic 1D/2D drag area: fn(rx, ry) with ratios 0..1
local function dragArea(area, maid, fn)
	local active = nil
	local function update(input)
		local p = Device.pointer(input)
		local ap, as = area.AbsolutePosition, area.AbsoluteSize
		fn(math.clamp((p.X - ap.X) / math.max(as.X, 1), 0, 1), math.clamp((p.Y - ap.Y) / math.max(as.Y, 1), 0, 1))
	end
	maid:Add(area.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		update(input)
		if active then
			for _, c in ipairs(active) do
				c:Disconnect()
			end
		end
		local uis = Services.UserInputService
		local connections
		connections = {
			uis.InputChanged:Connect(function(changed)
				if changed.UserInputType == Enum.UserInputType.MouseMovement or (changed == input) then
					update(changed)
				end
			end),
			uis.InputEnded:Connect(function(ended)
				if ended == input or ended.UserInputType == Enum.UserInputType.MouseButton1 then
					for _, c in ipairs(connections) do
						c:Disconnect()
					end
					active = nil
				end
			end),
		}
		active = connections
	end))
	maid:Add(function()
		if active then
			for _, c in ipairs(active) do
				c:Disconnect()
			end
		end
	end)
end

function ColorPicker:Open()
	local window = self.Window
	local h, s, v = self:Get():ToHSV()
	window.Popup:Open({
		anchor = self.Swatch,
		width = 260,
		padding = 12,
		onClose = function()
			self._sync = nil
		end,
		build = function(container, handle)
			container:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 12)
			local square = New("TextButton", {
				Name = "SV",
				Size = UDim2.new(1, 0, 0, 150),
				BackgroundColor3 = Color3.fromHSV(h, 1, 1),
				LayoutOrder = 1,
				Parent = container,
			}, { Create.corner(10) })
			New("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = square,
			}, {
				Create.corner(10),
				New("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
			})
			New("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(0, 0, 0),
				Parent = square,
			}, {
				Create.corner(10),
				New("UIGradient", { Transparency = NumberSequence.new(1, 0), Rotation = 90 }),
			})
			local svKnob = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(18, 18),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Parent = square,
			}, { Create.corner("full"), Create.stroke(Color3.new(1, 1, 1), 3) })

			local keypoints = {}
			for i = 0, 6 do
				table.insert(keypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)))
			end
			local hue = New("TextButton", {
				Name = "Hue",
				Size = UDim2.new(1, 0, 0, 14),
				BackgroundColor3 = Color3.new(1, 1, 1),
				LayoutOrder = 2,
				Parent = container,
			}, { Create.corner("full"), New("UIGradient", { Color = ColorSequence.new(keypoints) }) })
			local hueKnob = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(h, 0.5),
				Size = UDim2.fromOffset(18, 18),
				BackgroundTransparency = 1,
				Parent = hue,
			}, { Create.corner("full"), Create.stroke(Color3.new(1, 1, 1), 3) })

			local row = New("Frame", {
				Size = UDim2.new(1, 0, 0, 34),
				LayoutOrder = 3,
				Parent = container,
			}, { Create.list("Horizontal", 8, { valign = "Center" }) })
			local preview = New("Frame", {
				Size = UDim2.fromOffset(34, 34),
				BackgroundColor3 = self:Get(),
				Parent = row,
			}, { Create.corner(9) })
			local hexField = New("Frame", {
				Size = UDim2.fromScale(0, 1),
				BackgroundColor3 = C("bg"),
				LayoutOrder = 2,
				Parent = row,
			}, { Create.corner(9), Create.stroke("borderStrong"), Create.pad(0, 10), Create.flex() })
			local hexBox = New("TextBox", {
				Size = UDim2.fromScale(1, 1),
				Mono = true,
				TextSize = 12.5,
				Text = "#" .. Util.toHex(self:Get()),
				Parent = hexField,
			})

			local swatches = New("Frame", {
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 4,
				Parent = container,
			}, { Create.list("Horizontal", 8, { valign = "Center" }) })

			local function commit()
				self:Set(Color3.fromHSV(h, s, v))
			end
			local function sync(color)
				local nh, ns, nv = color:ToHSV()
				if ns > 0.001 and nv > 0.001 then
					h = nh
				end
				s, v = ns, nv
				square.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				svKnob.Position = UDim2.fromScale(s, 1 - v)
				hueKnob.Position = UDim2.fromScale(h, 0.5)
				preview.BackgroundColor3 = color
				if not hexBox:IsFocused() then
					hexBox.Text = "#" .. Util.toHex(color)
				end
			end
			self._sync = sync
			sync(self:Get())

			dragArea(square, handle.maid, function(rx, ry)
				s, v = rx, 1 - ry
				svKnob.Position = UDim2.fromScale(s, 1 - v)
				commit()
			end)
			dragArea(hue, handle.maid, function(rx)
				h = math.min(rx, 0.999)
				hueKnob.Position = UDim2.fromScale(h, 0.5)
				square.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				commit()
			end)
			handle.maid:Add(hexBox.FocusLost:Connect(function()
				local color = Util.hex(hexBox.Text)
				if color then
					self:Set(color)
				else
					hexBox.Text = "#" .. Util.toHex(self:Get())
				end
			end))

			for index, hex in ipairs(self.Options.Swatches or SWATCHES) do
				local color = toColor(hex)
				local dot = New("TextButton", {
					Size = UDim2.fromOffset(24, 24),
					BackgroundColor3 = color,
					LayoutOrder = index,
					Parent = swatches,
				}, { Create.corner("full"), Create.stroke("borderStrong") })
				Motion.pressable(dot, nil, 0.85, handle.maid)
				handle.maid:Add(dot.Activated:Connect(function()
					self:Set(color)
				end))
			end
		end,
	})
end

return constructor
