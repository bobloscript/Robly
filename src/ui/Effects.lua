-- Effects: decorative background inside a window, behind all content.
--   Aurora   — large soft colour blobs (accent / accent2) drifting slowly
--   Stars    — tiny twinkling dots
--   Snow     — slowly falling dots
--   Grid     — faint line grid with an accent glow in the corner
--   Gradient — diagonal accent wash
--   None
-- Animated with looping tweens (no per-frame scripts); static when animations
-- are "Soft" or "Off". Panels become translucent with Theme.Glass.

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Services = import("core/Services")
local Maid = import("util/Maid")

local New = Create.New
local C = Theme.c

local Effects = {}
Effects.__index = Effects

-- deterministic pseudo-random so a layout looks the same every time
local function rng(seed)
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function loop(instance, props, seconds, style)
	if Motion.Mode ~= "Full" then
		return nil
	end
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = Services.TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

function Effects.new(parent, zindex)
	local self = setmetatable({}, Effects)
	self.Parent = parent
	self.Maid = Maid.new()
	self.Holder = self.Maid:Add(New("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		ZIndex = zindex or 0,
		ClipsDescendants = true,
		Parent = parent,
	}))
	self.Maid:Add(Theme.Changed:Connect(function(what)
		if what == "effect" or (what == "colors" and self._built ~= Theme.Effect) then
			self:Build()
		end
	end))
	self.Maid:Add(Motion.Changed:Connect(function()
		self:Build()
	end))
	self:Build()
	return self
end

-- transparency for an opacity, scaled by the user's effect strength
local function alpha(opacity)
	return 1 - math.clamp(opacity * Theme.EffectStrength, 0, 0.95)
end

-- Soft radial glow: concentric circles, each faint; they add up in the middle.
local function glow(parent, color, position, size, opacity, maid)
	local holder = maid:Add(New("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		Parent = parent,
	}, { New("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }) }))
	local rings = 9
	local each = 1 - (1 - math.clamp(opacity * Theme.EffectStrength, 0, 0.9)) ^ (1 / rings)
	for i = 1, rings do
		local scale = 1 - (i - 1) / rings * 0.85
		New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(scale, scale),
			BackgroundColor3 = C(color),
			BackgroundTransparency = 1 - each,
			Parent = holder,
		}, { Create.corner("full") })
	end
	return holder
end

function Effects:Build()
	if self._maid then
		self._maid:Clean()
	end
	local maid = Maid.new()
	self._maid = maid
	local holder = self.Holder
	local effect = Theme.Effect
	self._built = effect
	local random = rng(7)

	if effect == "Aurora" then
		local blobs = {
			{ color = "accent", x = 0.2, y = 0.1, size = 0.75, opacity = 0.5, dx = 0.18, dy = 0.12 },
			{ color = "accent2", x = 0.8, y = 0.75, size = 0.85, opacity = 0.45, dx = -0.2, dy = -0.1 },
			{ color = "accent2", x = 0.85, y = 0.05, size = 0.5, opacity = 0.35, dx = -0.12, dy = 0.15 },
			{ color = "accent", x = 0.15, y = 0.95, size = 0.55, opacity = 0.3, dx = 0.15, dy = -0.12 },
		}
		for index, spec in ipairs(blobs) do
			local blob = glow(holder, spec.color, UDim2.fromScale(spec.x, spec.y), UDim2.fromScale(spec.size, spec.size), spec.opacity, maid)
			maid:Add(loop(blob, {
				Position = UDim2.fromScale(spec.x + spec.dx, spec.y + spec.dy),
				Size = UDim2.fromScale(spec.size * 1.15, spec.size * 1.15),
			}, 7 + index * 2.5))
		end
	elseif effect == "Stars" then
		glow(holder, "accent2", UDim2.fromScale(0.85, 0.15), UDim2.fromScale(0.6, 0.6), 0.22, maid)
		glow(holder, "accent", UDim2.fromScale(0.1, 0.9), UDim2.fromScale(0.5, 0.5), 0.18, maid)
		for _ = 1, 80 do
			local big = random() < 0.15
			local size = big and 4 or (random() < 0.6 and 2 or 3)
			local dot = maid:Add(New("Frame", {
				Name = "Star",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(random(), random()),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = big and C("accent") or C("text"),
				BackgroundTransparency = alpha(0.45 + random() * 0.5),
				Parent = holder,
			}, { Create.corner("full") }))
			maid:Add(loop(dot, { BackgroundTransparency = alpha(0.08) }, 1.2 + random() * 2.5))
		end
	elseif effect == "Snow" then
		glow(holder, "accent", UDim2.fromScale(0.5, 1.05), UDim2.fromScale(1.1, 1.1), 0.2, maid)
		for _ = 1, 60 do
			local size = math.floor(2 + random() * 4)
			local x, y = random(), random()
			local dot = maid:Add(New("Frame", {
				Name = "Flake",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, y),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = random() < 0.2 and C("accent") or C("text"),
				BackgroundTransparency = alpha(0.4 + random() * 0.45),
				Parent = holder,
			}, { Create.corner("full") }))
			if Motion.Mode == "Full" then
				local seconds = 8 + random() * 10
				local fall = TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false, 0)
				-- start each flake somewhere along its path so the sky is never empty
				dot.Position = UDim2.fromScale(x, -0.05)
				local tween = Services.TweenService:Create(dot, fall, { Position = UDim2.fromScale(x + (random() - 0.5) * 0.2, 1.05) })
				tween:Play()
				pcall(function()
					tween.TimePosition = y * seconds
				end)
				maid:Add(tween)
			end
		end
	elseif effect == "Grid" then
		local step = 28
		local line = alpha(0.09)
		for i = 0, 70 do
			maid:Add(New("Frame", {
				Position = UDim2.fromOffset(i * step, 0),
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = C("text"),
				BackgroundTransparency = line,
				Parent = holder,
			}))
		end
		for i = 0, 45 do
			maid:Add(New("Frame", {
				Position = UDim2.fromOffset(0, i * step),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = C("text"),
				BackgroundTransparency = line,
				Parent = holder,
			}))
		end
		local a = glow(holder, "accent", UDim2.fromScale(0.9, 0.1), UDim2.fromScale(0.8, 0.8), 0.4, maid)
		local b = glow(holder, "accent2", UDim2.fromScale(0.1, 0.95), UDim2.fromScale(0.6, 0.6), 0.3, maid)
		maid:Add(loop(a, { Position = UDim2.fromScale(0.7, 0.3) }, 9))
		maid:Add(loop(b, { Position = UDim2.fromScale(0.3, 0.75) }, 11))
	elseif effect == "Gradient" then
		local wash = maid:Add(New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = alpha(0.42),
			Parent = holder,
		}, {
			New("UIGradient", {
				Color = Theme.gradient(),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.6, 0.75),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 35,
			}),
		}))
		local gradient = wash:FindFirstChildOfClass("UIGradient")
		maid:Add(loop(gradient, { Rotation = 75 }, 7))
		local spot = glow(holder, "accent2", UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.7, 0.7), 0.3, maid)
		maid:Add(loop(spot, { Position = UDim2.fromScale(0.6, 0.6) }, 8))
	end
end

function Effects:Destroy()
	if self._maid then
		self._maid:Clean()
	end
	self.Maid:Clean()
end

return Effects
