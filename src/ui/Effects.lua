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
			{ color = "accent", x = 0.05, y = -0.25, size = 0.75, alpha = 0.86 },
			{ color = "accent2", x = 0.55, y = 0.35, size = 0.8, alpha = 0.88 },
			{ color = "accent", x = 0.75, y = -0.35, size = 0.5, alpha = 0.92 },
		}
		for index, spec in ipairs(blobs) do
			local blob = maid:Add(New("Frame", {
				Name = "Blob",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spec.x + spec.size / 2, spec.y + spec.size / 2),
				Size = UDim2.fromScale(spec.size, spec.size * 1.3),
				BackgroundColor3 = C(spec.color),
				BackgroundTransparency = spec.alpha,
				Parent = holder,
			}, {
				Create.corner("full"),
				New("UIGradient", {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.5, 0),
						NumberSequenceKeypoint.new(1, 1),
					}),
					Rotation = index * 40,
				}),
			}))
			maid:Add(loop(blob, {
				Position = UDim2.fromScale(spec.x + spec.size / 2 + (index % 2 == 0 and -0.12 or 0.12), spec.y + spec.size / 2 + 0.1),
				Rotation = index % 2 == 0 and -25 or 25,
			}, 9 + index * 3))
		end
	elseif effect == "Stars" or effect == "Snow" then
		local count = effect == "Stars" and 46 or 34
		for _ = 1, count do
			local size = effect == "Stars" and (random() < 0.8 and 2 or 3) or math.floor(2 + random() * 3)
			local x, y = random(), random()
			local dot = maid:Add(New("Frame", {
				Name = "Dot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, effect == "Snow" and -0.05 + y * 0.2 or y),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = random() < 0.25 and C("accent") or C("text"),
				BackgroundTransparency = 0.35 + random() * 0.45,
				Parent = holder,
			}, { Create.corner("full") }))
			if effect == "Stars" then
				maid:Add(loop(dot, { BackgroundTransparency = 0.92 }, 1.5 + random() * 3))
			else
				dot.Position = UDim2.fromScale(x, y)
				local fall = Motion.Mode == "Full" and TweenInfo.new(9 + random() * 9, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false, random() * 6)
				if fall then
					dot.Position = UDim2.fromScale(x, -0.05)
					local tween = Services.TweenService:Create(dot, fall, { Position = UDim2.fromScale(x + (random() - 0.5) * 0.15, 1.05) })
					tween:Play()
					maid:Add(tween)
				end
			end
		end
	elseif effect == "Grid" then
		local step = 28
		for i = 0, 60 do
			maid:Add(New("Frame", {
				Position = UDim2.fromOffset(i * step, 0),
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = C("text"),
				BackgroundTransparency = 0.955,
				Parent = holder,
			}))
		end
		for i = 0, 40 do
			maid:Add(New("Frame", {
				Position = UDim2.fromOffset(0, i * step),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = C("text"),
				BackgroundTransparency = 0.955,
				Parent = holder,
			}))
		end
		local glow = maid:Add(New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.95, 0.05),
			Size = UDim2.fromScale(0.9, 0.9),
			BackgroundColor3 = C("accent"),
			BackgroundTransparency = 0.88,
			Parent = holder,
		}, {
			Create.corner("full"),
			New("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 45,
			}),
		}))
		maid:Add(loop(glow, { BackgroundTransparency = 0.94 }, 4))
	elseif effect == "Gradient" then
		local wash = maid:Add(New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.86,
			Parent = holder,
		}, {
			New("UIGradient", {
				Color = Theme.gradient(),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.55, 0.85),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 35,
			}),
		}))
		local gradient = wash:FindFirstChildOfClass("UIGradient")
		maid:Add(loop(gradient, { Rotation = 55 }, 8))
	end
end

function Effects:Destroy()
	if self._maid then
		self._maid:Clean()
	end
	self.Maid:Clean()
end

return Effects
