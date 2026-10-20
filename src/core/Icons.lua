-- Icons: Robly's own vector icon set, drawn with plain Frames (rotated bars,
-- rings, rounded rects) on a 24×24 grid. No images, so icons render on every
-- executor, scale cleanly and recolour with the theme.
--
-- Primitive codes (24-unit grid):
--   { "l", x1, y1, x2, y2, [w] }    line with round caps
--   { "p", x1, y1, x2, y2, ..., w=} polyline with round joints
--   { "c", cx, cy, r, [w] }         ring        { "C", cx, cy, r }      dot
--   { "r", x, y, w, h, rad, [sw] }  outline box { "R", x, y, w, h, rad } filled box
-- Any "rbxassetid://…" string works as an icon too (ImageLabel).

local Theme = import("core/Theme")
local Create = import("core/Create")

local New = Create.New
local Icons = {}

local D = {}
Icons.Data = D

D.home = { { "p", 3, 11, 12, 3.5, 21, 11 }, { "l", 5.5, 9.5, 5.5, 20 }, { "l", 18.5, 9.5, 18.5, 20 }, { "l", 5.5, 20, 18.5, 20 }, { "p", 10, 20, 10, 14.5, 14, 14.5, 14, 20 } }
D.leaf = { { "l", 12, 21, 12, 11 }, { "p", 12, 12, 13.5, 8, 16.5, 5.5, 20, 4.5, 19.5, 8, 17, 10.5, 12, 12 }, { "p", 12, 15, 10.5, 12, 8, 10.3, 5, 9.5, 5.5, 12.5, 8, 14.3, 12, 15 } }
D.sword = { { "p", 14.5, 17.5, 4, 7, 4, 4, 7, 4, 17.5, 14.5 }, { "l", 13, 19, 19, 13 }, { "l", 16, 16, 20, 20 } }
D.pin = { { "p", 12, 21, 7.2, 15, 5.4, 11.5, 5.4, 9, 6.6, 6, 9, 3.8, 12, 3, 15, 3.8, 17.4, 6, 18.6, 9, 18.6, 11.5, 16.8, 15, 12, 21 }, { "c", 12, 9.5, 2.5 } }
D.eye = { { "p", 2, 12, 4.5, 8.5, 8, 6, 12, 5, 16, 6, 19.5, 8.5, 22, 12, 19.5, 15.5, 16, 18, 12, 19, 8, 18, 4.5, 15.5, 2, 12 }, { "c", 12, 12, 3 } }
D.user = { { "c", 12, 8, 4 }, { "p", 4, 21, 4.6, 18, 6.5, 15.8, 9, 14.5, 12, 14, 15, 14.5, 17.5, 15.8, 19.4, 18, 20, 21 } }
D.sliders = { { "l", 4, 6, 13, 6 }, { "l", 17, 6, 20, 6 }, { "c", 15, 6, 2 }, { "l", 4, 12, 7, 12 }, { "l", 11, 12, 20, 12 }, { "c", 9, 12, 2 }, { "l", 4, 18, 15, 18 }, { "l", 19, 18, 20, 18 }, { "c", 17, 18, 2 } }
D.search = { { "c", 11, 11, 7 }, { "l", 16.5, 16.5, 20, 20 } }
D.globe = { { "c", 12, 12, 9 }, { "l", 3, 12, 21, 12 }, { "p", 12, 3, 14.3, 6, 15.6, 9, 15.8, 12, 15.6, 15, 14.3, 18, 12, 21, 9.7, 18, 8.4, 15, 8.2, 12, 8.4, 9, 9.7, 6, 12, 3 } }
D.minus = { { "l", 6, 12, 18, 12 } }
D.plus = { { "l", 5, 12, 19, 12 }, { "l", 12, 5, 12, 19 } }
D.close = { { "l", 7, 7, 17, 17 }, { "l", 17, 7, 7, 17 } }
D.check = { { "p", 5, 12.5, 9.5, 17, 19, 7.5, w = 2.4 } }
D.chevronDown = { { "p", 7, 10, 12, 15, 17, 10 } }
D.chevronUp = { { "p", 7, 14, 12, 9, 17, 14 } }
D.chevronRight = { { "p", 9, 6, 15, 12, 9, 18 } }
D.chevronLeft = { { "p", 15, 6, 9, 12, 15, 18 } }
D.pip = { { "r", 3, 5, 18, 14, 2.5 }, { "R", 12, 11, 6, 5, 1 } }
D.attach = { { "r", 3, 5, 18, 14, 2.5 }, { "p", 9, 10, 9, 15, 14, 15 }, { "l", 9, 15, 16, 8.5 } }
D.more = { { "C", 5, 12, 1.8 }, { "C", 12, 12, 1.8 }, { "C", 19, 12, 1.8 } }
D.bolt = { { "p", 13, 2.5, 4.5, 13.5, 11.5, 13.5, 10.5, 21.5, 19.5, 10.5, 12.5, 10.5, 13, 2.5 } }
D.warning = { { "p", 12, 3.5, 21.5, 20, 2.5, 20, 12, 3.5 }, { "l", 12, 9.5, 12, 13.5 }, { "C", 12, 16.6, 1.2 } }
D.info = { { "c", 12, 12, 9 }, { "l", 12, 11, 12, 16.5 }, { "C", 12, 7.8, 1.2 } }
D.success = { { "p", 5, 12.5, 9.5, 17, 19, 7.5, w = 2.4 } }
D.error = { { "c", 12, 12, 9 }, { "l", 9, 9, 15, 15 }, { "l", 15, 9, 9, 15 } }
D.copy = { { "r", 8, 8, 12, 12, 2.5 }, { "p", 16, 8, 16, 6, 14.5, 4, 6, 4, 4, 6, 4, 14.5, 6, 16, 8, 16 } }
D.keyboard = { { "r", 2.5, 6, 19, 12, 2.5 }, { "C", 6.5, 10, 0.9 }, { "C", 10, 10, 0.9 }, { "C", 13.5, 10, 0.9 }, { "C", 17, 10, 0.9 }, { "l", 8, 14.2, 16, 14.2 } }
D.palette = { { "c", 12, 12, 9 }, { "C", 8, 10, 1.4 }, { "C", 12, 7.5, 1.4 }, { "C", 16, 10, 1.4 }, { "C", 14.5, 15, 1.4 } }
D.folder = { { "p", 3, 6, 9.5, 6, 11.5, 8.5, 21, 8.5, 21, 19, 3, 19, 3, 6 } }
D.trash = { { "l", 4, 6.5, 20, 6.5 }, { "p", 9, 6.5, 9, 4, 15, 4, 15, 6.5 }, { "p", 6, 6.5, 7, 20, 17, 20, 18, 6.5 } }
D.star = { { "p", 12, 3, 14.6, 8.8, 21, 9.4, 16.2, 13.6, 17.6, 20, 12, 16.7, 6.4, 20, 7.8, 13.6, 3, 9.4, 9.4, 8.8, 12, 3 } }
D.target = { { "c", 12, 12, 8 }, { "c", 12, 12, 3.5 } }
D.crosshair = { { "c", 12, 12, 7.5 }, { "l", 12, 2, 12, 6 }, { "l", 12, 18, 12, 22 }, { "l", 2, 12, 6, 12 }, { "l", 18, 12, 22, 12 } }
D.shield = { { "p", 12, 3, 19, 6, 19, 12, 16.5, 17, 12, 21, 7.5, 17, 5, 12, 5, 6, 12, 3 } }
D.gear = { { "c", 12, 12, 3 }, { "c", 12, 12, 7 }, { "l", 12, 2, 12, 5 }, { "l", 12, 19, 12, 22 }, { "l", 2, 12, 5, 12 }, { "l", 19, 12, 22, 12 }, { "l", 4.9, 4.9, 7, 7 }, { "l", 17, 17, 19.1, 19.1 }, { "l", 4.9, 19.1, 7, 17 }, { "l", 17, 7, 19.1, 4.9 } }
D.map = { { "p", 3, 6, 9, 3.5, 15, 6, 21, 3.5, 21, 18, 15, 20.5, 9, 18, 3, 20.5, 3, 6 }, { "l", 9, 3.5, 9, 18 }, { "l", 15, 6, 15, 20.5 } }
D.box = { { "r", 3, 9, 18, 11, 2 }, { "p", 4.5, 9, 6.5, 4.5, 17.5, 4.5, 19.5, 9 }, { "l", 3, 13, 21, 13 }, { "R", 10.5, 12, 3, 3, 0.8 } }
D.plane = { { "p", 2.5, 12.5, 21.5, 4, 14.5, 21, 11, 14, 2.5, 12.5 }, { "l", 11, 14, 21.5, 4 } }
D.heart = { { "p", 12, 20, 4.5, 13, 3, 9.5, 4, 6.5, 6.5, 5, 9.5, 5.3, 12, 8, 14.5, 5.3, 17.5, 5, 20, 6.5, 21, 9.5, 19.5, 13, 12, 20 } }
D.download = { { "l", 12, 4, 12, 15 }, { "p", 7, 10.5, 12, 15.5, 17, 10.5 }, { "l", 4, 20, 20, 20 } }
D.upload = { { "l", 12, 15.5, 12, 4.5 }, { "p", 7, 9, 12, 4, 17, 9 }, { "l", 4, 20, 20, 20 } }
D.save = { { "p", 4, 4, 16, 4, 20, 8, 20, 20, 4, 20, 4, 4 }, { "p", 8, 20, 8, 14, 16, 14, 16, 20 }, { "p", 8, 4, 8, 8, 14, 8 } }
D.link = { { "p", 10, 14, 8, 16, 5.5, 16, 4, 14.5, 4, 12, 7, 9 }, { "p", 14, 10, 16, 8, 18.5, 8, 20, 9.5, 20, 12, 17, 15 }, { "l", 9.5, 14.5, 14.5, 9.5 } }
D.refresh = { { "p", 19.5, 12, 18.6, 15.8, 16, 18.6, 12, 19.5, 8, 18.6, 5.4, 15.8, 4.5, 12, 5.4, 8.2, 8, 5.4, 12, 4.5, 16, 5.4, 18.5, 7.5 }, { "p", 19, 3.5, 19, 8, 14.5, 8 } }
D.grip = { { "l", 21, 9, 9, 21 }, { "l", 21, 15, 15, 21 } }
D.dot = { { "C", 12, 12, 4 } }
D.ring = { { "c", 12, 12, 4, 2 } }
D.question = { { "p", 9, 9, 9.6, 6.8, 12, 5.5, 14.4, 6.4, 15.2, 8.6, 14.2, 10.6, 12, 12, 12, 14 }, { "C", 12, 17.8, 1.3 } }
D.play = { { "p", 7, 4.5, 19, 12, 7, 19.5, 7, 4.5 } }
D.stop = { { "r", 6, 6, 12, 12, 2 } }
D.list = { { "l", 9, 6, 20, 6 }, { "l", 9, 12, 20, 12 }, { "l", 9, 18, 20, 18 }, { "C", 4.5, 6, 1.2 }, { "C", 4.5, 12, 1.2 }, { "C", 4.5, 18, 1.2 } }
D.coins = { { "c", 9, 9, 5.5 }, { "p", 9.5, 19.5, 12, 20.5, 15, 20.5, 18, 19, 20, 16, 20, 13, 18.5, 10.5 } }
D.skull = { { "p", 7, 20, 7, 16.5, 4.5, 14, 4, 10.5, 5.5, 6.5, 9, 4, 12, 3.5, 15, 4, 18.5, 6.5, 20, 10.5, 19.5, 14, 17, 16.5, 17, 20, 7, 20 }, { "C", 9, 11.5, 1.8 }, { "C", 15, 11.5, 1.8 } }
D.lock = { { "r", 5, 10.5, 14, 10, 2.5 }, { "p", 8, 10.5, 8, 7.5, 9.2, 4.8, 12, 3.8, 14.8, 4.8, 16, 7.5, 16, 10.5 } }
D.speed = { { "p", 4, 17, 3.5, 13, 5, 8.5, 8.5, 5.5, 12, 4.5, 15.5, 5.5, 19, 8.5, 20.5, 13, 20, 17 }, { "l", 12, 14, 16, 9 } }

Icons.Aliases = {
	farm = "leaf", fight = "sword", combat = "sword", teleport = "pin", visual = "eye", esp = "eye",
	player = "user", settings = "sliders", x = "close", lightning = "bolt", zap = "bolt",
	["external"] = "pip", ["return"] = "attach", fly = "plane", chest = "box", money = "coins",
	ok = "check", danger = "warning", fav = "star", config = "folder",
}

function Icons.has(name)
	if type(name) ~= "string" then
		return false
	end
	return D[name] ~= nil or Icons.Aliases[name] ~= nil or name:find("^rbxasset") ~= nil
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

	if type(name) == "string" and name:find("^rbxasset") then
		local image = New("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = name,
			Parent = container,
		})
		track(image, "ImageColor3")
	else
		local def = D[name] or D[Icons.Aliases[name] or ""] or D.dot
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
