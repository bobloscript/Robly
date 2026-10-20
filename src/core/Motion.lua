-- Motion: every animation goes through here so the "Full / Soft / Off"
-- setting is respected everywhere.
--   Full — springs and slides (press 0.97 · 120 ms, Back Out 220 ms, Quint Out 280 ms)
--   Soft — only fades (120 ms); sizes and positions change instantly
--   Off  — everything instant

local Services = import("core/Services")
local Signal = import("util/Signal")

local Motion = {
	Mode = "Full",
	Changed = Signal.new(),
}

local Style = Enum.EasingStyle
local Dir = Enum.EasingDirection

Motion.Presets = {
	press = TweenInfo.new(0.12, Style.Quad, Dir.Out),
	spring = TweenInfo.new(0.22, Style.Back, Dir.Out),
	window = TweenInfo.new(0.28, Style.Quint, Dir.Out),
	fade = TweenInfo.new(0.12, Style.Sine, Dir.Out),
	color = TweenInfo.new(0.16, Style.Quad, Dir.Out),
	flash = TweenInfo.new(0.6, Style.Quad, Dir.Out),
	linear = TweenInfo.new(1, Style.Linear, Dir.InOut),
}

local VISUAL = {
	BackgroundColor3 = true,
	BackgroundTransparency = true,
	TextColor3 = true,
	TextTransparency = true,
	TextStrokeTransparency = true,
	ImageColor3 = true,
	ImageTransparency = true,
	Color = true,
	Transparency = true,
	ScrollBarImageColor3 = true,
	PlaceholderColor3 = true,
}

function Motion.setMode(mode)
	if mode ~= "Full" and mode ~= "Soft" and mode ~= "Off" then
		mode = "Full"
	end
	if Motion.Mode ~= mode then
		Motion.Mode = mode
		Motion.Changed:Fire(mode)
	end
end

local function setAll(instance, props)
	for key, value in pairs(props) do
		instance[key] = value
	end
end

-- Tween `props` on `instance` using a named preset (or a TweenInfo).
function Motion.tween(instance, props, preset)
	if Motion.Mode == "Off" then
		setAll(instance, props)
		return nil
	end
	if Motion.Mode == "Soft" then
		local visual = nil
		for key, value in pairs(props) do
			if VISUAL[key] then
				visual = visual or {}
				visual[key] = value
			else
				instance[key] = value
			end
		end
		if visual then
			local tween = Services.TweenService:Create(instance, Motion.Presets.fade, visual)
			tween:Play()
			return tween
		end
		return nil
	end
	local info = type(preset) == "string" and Motion.Presets[preset] or preset or Motion.Presets.color
	local tween = Services.TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- A custom-duration tween that still respects the mode.
function Motion.tweenFor(instance, props, seconds, style, direction)
	return Motion.tween(instance, props, TweenInfo.new(seconds, style or Style.Quad, direction or Dir.Out))
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Tactile press: shrinks `target` (default: the button) to `scale` while
-- pressed and springs back on release. Returns the UIScale.
function Motion.pressable(button, target, scale, maid)
	target = target or button
	local uiScale = target:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = target
	end
	scale = scale or 0.97
	local pressed = false
	local function release()
		if pressed then
			pressed = false
			Motion.tween(uiScale, { Scale = 1 }, "spring")
		end
	end
	local c1 = button.InputBegan:Connect(function(input)
		if isPress(input) and Motion.Mode == "Full" then
			pressed = true
			Motion.tween(uiScale, { Scale = scale }, "press")
			-- a finger that slides off the button never fires its InputEnded
			local ended
			ended = Services.UserInputService.InputEnded:Connect(function(other)
				if other == input or other.UserInputType == Enum.UserInputType.MouseButton1 then
					ended:Disconnect()
					release()
				end
			end)
		end
	end)
	local c2 = button.InputEnded:Connect(function(input)
		if isPress(input) then
			release()
		end
	end)
	local c3 = button.MouseLeave:Connect(release)
	if maid then
		maid:Add(c1)
		maid:Add(c2)
		maid:Add(c3)
	end
	return uiScale
end

return Motion
