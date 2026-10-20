-- Icons: the Lucide icon set (https://lucide.dev) rendered from Roblox sprite
-- sheets (ImageLabel + ImageRectOffset), recoloured with the theme.
--   Icons.new("house"), Icons.new("crosshair", 18, Theme.c("accent"))
-- Any Lucide name from LucideData works, plus Robly's short names below
-- (pin, bolt, close, pip…) and any "rbxassetid://…" image.
-- A few tiny shapes Lucide doesn't have (resize grip, status dots) are drawn
-- with Frames on a 24×24 grid:
--   { "l", x1, y1, x2, y2, [w] } line · { "c", cx, cy, r, [w] } ring · { "C", cx, cy, r } dot

local Theme = import("core/Theme")
local Create = import("core/Create")
local Lucide = import("core/LucideData")

local New = Create.New
local Icons = {}

local D = {}
Icons.Data = D
Icons.Lucide = Lucide

D.grip = { { "l", 21, 9, 9, 21 }, { "l", 21, 15, 15, 21 } }
D.dot = { { "C", 12, 12, 4 } }
D.ring = { { "c", 12, 12, 4, 2 } }

-- Robly's names (used by the library and kept for scripts) -> Lucide names
Icons.Aliases = {
	home = "home", house = "home", leaf = "leaf", farm = "sprout", sword = "sword", fight = "swords",
	combat = "swords", pin = "map-pin", teleport = "map-pin", eye = "eye", visual = "eye", esp = "eye",
	user = "user", player = "user", sliders = "sliders-horizontal", settings = "settings",
	gear = "settings", close = "x", chevronDown = "chevron-down", chevronUp = "chevron-up",
	chevronLeft = "chevron-left", chevronRight = "chevron-right", pip = "picture-in-picture-2",
	external = "picture-in-picture-2", attach = "minimize-2", ["return"] = "minimize-2",
	more = "more-horizontal", bolt = "zap", lightning = "bolt", warning = "alert-triangle",
	danger = "alert-triangle", success = "check-circle", error = "x-circle", trash = "trash-2",
	box = "package", chest = "package", refresh = "refresh-cw", question = "help-circle",
	stop = "square", speed = "gauge", fly = "plane", money = "coins", ok = "check", fav = "star",
	config = "folder",
}

local warned = {}

-- Resolves a name to ("image", url) | ("sprite", entry) | ("vector", def)
function Icons.resolve(name)
	if type(name) ~= "string" then
		return "vector", D.dot
	end
	if name:find("^rbxasset") or name:find("^https?://") then
		return "image", name
	end
	if D[name] then
		return "vector", D[name]
	end
	local lucideName = Icons.Aliases[name] or name
	if Icons.Aliases[lucideName] and not Lucide.Icons[lucideName] then
		lucideName = Icons.Aliases[lucideName]
	end
	local entry = Lucide.Icons[lucideName]
	if entry then
		return "sprite", entry
	end
	if not warned[name] then
		warned[name] = true
		warn("[Robly] unknown icon: " .. name .. " (use a Lucide name from lucide.dev/icons)")
	end
	return "sprite", Lucide.Icons["circle"]
end

function Icons.has(name)
	if type(name) ~= "string" then
		return false
	end
	if name:find("^rbxasset") or D[name] then
		return true
	end
	local lucideName = Icons.Aliases[name] or name
	return Lucide.Icons[lucideName] ~= nil or Lucide.Icons[Icons.Aliases[lucideName] or ""] ~= nil
end

local function px(size)
	return function(width)
		return Theme.f(function(_, s)
			local total = type(size) == "string" and s[size] or size
			return math.max(1, math.floor(width * total / 24 + 0.5))
		end)
	end
end

local function sizeToken(size)
	if type(size) == "string" then
		return Theme.f(function(_, s)
			return UDim2.fromOffset(s[size], s[size])
		end)
	end
	return UDim2.fromOffset(size, size)
end

-- Icons.new(name, size, colorToken) -> { Frame, SetColor(token, animate), Destroy }
function Icons.new(name, size, color, props)
	size = size or "icon"
	color = color or Theme.c("text")
	local object = { parts = {} }
	local container = New("Frame", {
		Name = "Icon",
		Size = sizeToken(size),
		BackgroundTransparency = 1,
	})
	if props then
		for key, value in pairs(props) do
			if Theme.isToken(value) then
				Theme.bind(container, key, value)
			else
				container[key] = value
			end
		end
	end
	object.Frame = container

	local function track(instance, prop)
		table.insert(object.parts, { instance, prop })
		Theme.bind(instance, prop, color)
	end

	local kind, value = Icons.resolve(name)
	if kind == "image" or kind == "sprite" then
		local image = New("ImageLabel", {
			Name = "Glyph",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Parent = container,
		})
		if kind == "image" then
			image.Image = value
		else
			image.Image = "rbxassetid://" .. Lucide.Sheets[value[1]]
			image.ImageRectOffset = Vector2.new(value[2], value[3])
			image.ImageRectSize = Vector2.new(Lucide.Size, Lucide.Size)
		end
		track(image, "ImageColor3")
	else
		local def = value
		local thickness = px(size)

		local function line(x1, y1, x2, y2, w)
			local dx, dy = x2 - x1, y2 - y1
			local length = math.sqrt(dx * dx + dy * dy)
			local bar = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((x1 + x2) / 48, (y1 + y2) / 48),
				Size = UDim2.fromScale((length + w) / 24, w / 24),
				Rotation = math.deg(math.atan2(dy, dx)),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = container,
			}, { Create.corner("full") })
			track(bar, "BackgroundColor3")
		end

		local function dot(cx, cy, r)
			local circle = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(cx / 24, cy / 24),
				Size = UDim2.fromScale(r * 2 / 24, r * 2 / 24),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = container,
			}, { Create.corner("full") })
			track(circle, "BackgroundColor3")
		end

		for _, part in ipairs(def) do
			local kind = part[1]
			if kind == "l" then
				line(part[2], part[3], part[4], part[5], part[6] or 2)
			elseif kind == "p" then
				local w = part.w or 2
				local n = #part
				for i = 2, n - 3, 2 do
					line(part[i], part[i + 1], part[i + 2], part[i + 3], w)
				end
			elseif kind == "c" then
				local ring = New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(part[2] / 24, part[3] / 24),
					Size = UDim2.fromScale(part[4] * 2 / 24, part[4] * 2 / 24),
					BackgroundTransparency = 1,
					Parent = container,
				}, { Create.corner("full") })
				local stroke = New("UIStroke", {
					Thickness = thickness(part[5] or 2),
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Parent = ring,
				})
				track(stroke, "Color")
			elseif kind == "C" then
				dot(part[2], part[3], part[4])
			elseif kind == "r" or kind == "R" then
				local x, y, w, h, rad = part[2], part[3], part[4], part[5], part[6] or 0
				local box = New("Frame", {
					Position = UDim2.fromScale(x / 24, y / 24),
					Size = UDim2.fromScale(w / 24, h / 24),
					BackgroundTransparency = kind == "R" and 0 or 1,
					BackgroundColor3 = Color3.new(1, 1, 1),
					Parent = container,
				}, { New("UICorner", { CornerRadius = UDim.new(rad / math.min(w, h), 0) }) })
				if kind == "R" then
					track(box, "BackgroundColor3")
				else
					local stroke = New("UIStroke", {
						Thickness = thickness(part[7] or 2),
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Parent = box,
					})
					track(stroke, "Color")
				end
			end
		end
	end

	function object.SetColor(_, token, animate)
		color = token
		for _, entry in ipairs(object.parts) do
			if animate then
				Theme.set(entry[1], entry[2], token)
			else
				Theme.bind(entry[1], entry[2], token)
			end
		end
	end

	function object.Destroy()
		container:Destroy()
	end

	return object
end

return Icons
