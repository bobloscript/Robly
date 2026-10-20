--!nocheck
-- A small Roblox environment for running Robly under Lune (no Roblox needed).
-- Instances are proxies over Lune's real Instance objects, so every property
-- name and value type is validated against the Roblox API database, while
-- events, focus, services and executor functions are simulated here.

local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local task = require("@lune/task")

local M = {}
M.errors = {}
M.warnings = {}
M.files = {}
M.clipboard = nil
M.instances = 0

local Vector2, Vector3 = roblox.Vector2, roblox.Vector3
local Enum = roblox.Enum

-- Signals ------------------------------------------------------------------------

local function Signal(name)
	local s = { handlers = {}, name = name }
	function s:Connect(fn)
		local h = { fn = fn, on = true }
		table.insert(self.handlers, h)
		local c = { Connected = true }
		function c:Disconnect()
			h.on = false
			c.Connected = false
		end
		return c
	end
	function s:Once(fn)
		local c
		c = self:Connect(function(...)
			c:Disconnect()
			fn(...)
		end)
		return c
	end
	function s:Fire(...)
		for _, h in ipairs(table.clone(self.handlers)) do
			if h.on then
				local ok, err = pcall(h.fn, ...)
				if not ok then
					table.insert(M.errors, self.name .. ": " .. tostring(err))
				end
			end
		end
	end
	return s
end
M.Signal = Signal

-- Instances ------------------------------------------------------------------------

local data = setmetatable({}, { __mode = "k" })
M.data = data
local Meta = {}
local Methods = {}

local EVENTS = {
	InputBegan = true, InputEnded = true, InputChanged = true, MouseEnter = true, MouseLeave = true,
	Activated = true, MouseButton1Click = true, FocusLost = true, Focused = true, Destroying = true,
	Changed = true, ChildAdded = true, ChildRemoved = true,
}

local viewport = Vector2.new(1920, 1080)

local function new(className)
	local real = roblox.Instance.new(className)
	local p = setmetatable({}, Meta)
	data[p] = { real = real, className = className, children = {}, parent = nil, events = {}, props = {}, destroyed = false }
	M.instances += 1
	return p
end
M.new = new

local function setParent(p, parent)
	local d = data[p]
	if d.parent == parent then
		return
	end
	if parent ~= nil and not data[parent] then
		error("Parent must be an Instance proxy, got " .. typeof(parent))
	end
	if d.parent then
		local siblings = data[d.parent].children
		local i = table.find(siblings, p)
		if i then
			table.remove(siblings, i)
		end
	end
	d.parent = parent
	if parent then
		table.insert(data[parent].children, p)
	end
end

local function absSize(p)
	local d = data[p]
	if d.className == "ScreenGui" or d.className == "Folder" then
		return viewport
	end
	local parentSize = d.parent and absSize(d.parent) or viewport
	local ok, size = pcall(function()
		return d.real.Size
	end)
	if not ok or typeof(size) ~= "UDim2" then
		return parentSize
	end
	return Vector2.new(parentSize.X * size.X.Scale + size.X.Offset, parentSize.Y * size.Y.Scale + size.Y.Offset)
end

local function absPos(p)
	local d = data[p]
	-- Like Roblox: in a ScreenGui with IgnoreGuiInset, AbsolutePosition is still
	-- measured from below the 36 px top bar, so the screen corner is at y = -36.
	if d.className == "ScreenGui" then
		return Vector2.new(0, d.real.IgnoreGuiInset and -36 or 0)
	end
	if d.className == "Folder" or not d.parent then
		return Vector2.new(0, 0)
	end
	local parentPos, parentSize = absPos(d.parent), absSize(d.parent)
	local ok, pos = pcall(function()
		return d.real.Position
	end)
	if not ok or typeof(pos) ~= "UDim2" then
		return parentPos
	end
	local size = absSize(p)
	local anchor = d.real.AnchorPoint
	return Vector2.new(
		parentPos.X + parentSize.X * pos.X.Scale + pos.X.Offset - anchor.X * size.X,
		parentPos.Y + parentSize.Y * pos.Y.Scale + pos.Y.Offset - anchor.Y * size.Y
	)
end

Meta.__index = function(p, key)
	local d = data[p]
	if Methods[key] then
		return Methods[key]
	end
	if EVENTS[key] then
		d.events[key] = d.events[key] or Signal(d.className .. "." .. key)
		return d.events[key]
	end
	if key == "Parent" then
		return d.parent
	elseif key == "ClassName" then
		return d.className
	elseif key == "AbsoluteSize" or key == "AbsoluteWindowSize" then
		return absSize(p)
	elseif key == "AbsolutePosition" then
		return absPos(p)
	elseif key == "AbsoluteCanvasSize" then
		return absSize(p)
	elseif key == "AbsoluteRotation" then
		return 0
	elseif key == "TextFits" then
		return true
	elseif key == "UserInputState" then
		return Enum.UserInputState.End
	end
	local ok, value = pcall(function()
		return d.real[key]
	end)
	if ok then
		return value
	end
	if d.props[key] ~= nil then
		return d.props[key]
	end
	error(string.format("%s is not a valid member of %s", tostring(key), d.className), 2)
end

Meta.__newindex = function(p, key, value)
	local d = data[p]
	if key == "Parent" then
		setParent(p, value)
		return
	end
	if data[value] then
		error("cannot assign Instance to property " .. key)
	end
	local ok, err = pcall(function()
		d.real[key] = value
	end)
	if not ok then
		error(string.format("set %s.%s = %s failed: %s", d.className, tostring(key), tostring(value), tostring(err)), 2)
	end
	d.props[key] = value
	local signal = d.events["prop:" .. key]
	if signal then
		signal:Fire()
	end
end

Meta.__tostring = function(p)
	return data[p].real.Name
end

function Methods.Destroy(p)
	local d = data[p]
	if d.destroyed then
		return
	end
	d.destroyed = true
	if d.events.Destroying then
		d.events.Destroying:Fire()
	end
	for _, child in ipairs(table.clone(d.children)) do
		Methods.Destroy(child)
	end
	setParent(p, nil)
end

function Methods.ClearAllChildren(p)
	for _, child in ipairs(table.clone(data[p].children)) do
		Methods.Destroy(child)
	end
end

function Methods.GetChildren(p)
	return table.clone(data[p].children)
end

function Methods.GetDescendants(p)
	local out = {}
	local function walk(node)
		for _, child in ipairs(data[node].children) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(p)
	return out
end

function Methods.FindFirstChild(p, name)
	for _, child in ipairs(data[p].children) do
		if data[child].real.Name == name then
			return child
		end
	end
	return nil
end

function Methods.WaitForChild(p, name)
	return Methods.FindFirstChild(p, name)
end

function Methods.FindFirstChildOfClass(p, className)
	for _, child in ipairs(data[p].children) do
		if data[child].className == className then
			return child
		end
	end
	return nil
end

function Methods.FindFirstChildWhichIsA(p, className)
	for _, child in ipairs(data[p].children) do
		if data[child].real:IsA(className) then
			return child
		end
	end
	return nil
end

function Methods.IsA(p, className)
	return data[p].real:IsA(className)
end

function Methods.IsDescendantOf(p, ancestor)
	local node = data[p].parent
	while node do
		if node == ancestor then
			return true
		end
		node = data[node].parent
	end
	return false
end

function Methods.GetPropertyChangedSignal(p, prop)
	local d = data[p]
	local key = "prop:" .. prop
	d.events[key] = d.events[key] or Signal(d.className .. ":" .. prop)
	return d.events[key]
end

M.focused = nil
function Methods.CaptureFocus(p)
	M.focused = p
	Methods.GetPropertyChangedSignal(p, "x")
	local d = data[p]
	d.events.Focused = d.events.Focused or Signal("Focused")
	d.events.Focused:Fire()
end

function Methods.ReleaseFocus(p, enter)
	if M.focused == p then
		M.focused = nil
		local d = data[p]
		d.events.FocusLost = d.events.FocusLost or Signal("FocusLost")
		d.events.FocusLost:Fire(enter == true)
	end
end

function Methods.IsFocused(p)
	return M.focused == p
end

function Methods.GetFullName(p)
	local names = {}
	local node = p
	while node do
		table.insert(names, 1, data[node].real.Name)
		node = data[node].parent
	end
	return table.concat(names, ".")
end

-- Helpers for tests -----------------------------------------------------------------------

function M.fire(instance, event, ...)
	local d = data[instance]
	d.events[event] = d.events[event] or Signal(d.className .. "." .. event)
	d.events[event]:Fire(...)
end

function M.input(kind, x, y, keyCode)
	return {
		UserInputType = kind or Enum.UserInputType.MouseButton1,
		KeyCode = keyCode or Enum.KeyCode.Unknown,
		Position = Vector3.new(x or 0, y or 0, 0),
		UserInputState = Enum.UserInputState.Begin,
	}
end

function M.find(root, predicate)
	for _, node in ipairs(Methods.GetDescendants(root)) do
		if predicate(node, data[node]) then
			return node
		end
	end
	return nil
end

function M.findAll(root, predicate)
	local out = {}
	for _, node in ipairs(Methods.GetDescendants(root)) do
		if predicate(node, data[node]) then
			table.insert(out, node)
		end
	end
	return out
end

function M.isProxy(value)
	return data[value] ~= nil
end

-- Services ---------------------------------------------------------------------------------

local UIS = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	MouseEnabled = true,
	InputBegan = Signal("UIS.InputBegan"),
	InputChanged = Signal("UIS.InputChanged"),
	InputEnded = Signal("UIS.InputEnded"),
	TextBoxFocused = Signal("UIS.TextBoxFocused"),
	TextBoxFocusReleased = Signal("UIS.TextBoxFocusReleased"),
	keysDown = {},
}
function UIS:GetFocusedTextBox()
	return M.focused
end
function UIS:IsKeyDown(key)
	return self.keysDown[key.Name] == true
end
function UIS:GetMouseLocation()
	return Vector2.new(0, 0)
end
M.UIS = UIS

function M.press(keyCode, mods)
	for _, mod in ipairs(mods or {}) do
		UIS.keysDown[mod.Name] = true
	end
	local input = M.input(Enum.UserInputType.Keyboard, 0, 0, keyCode)
	UIS.InputBegan:Fire(input, false)
	UIS.InputEnded:Fire(input, false)
	for _, mod in ipairs(mods or {}) do
		UIS.keysDown[mod.Name] = nil
	end
end

local camera = { ViewportSize = viewport, _signals = {} }
function camera:GetPropertyChangedSignal(prop)
	self._signals[prop] = self._signals[prop] or Signal("Camera." .. prop)
	return self._signals[prop]
end
function M.setViewport(x, y)
	viewport = Vector2.new(x, y)
	camera.ViewportSize = viewport
	local s = camera._signals.ViewportSize
	if s then
		s:Fire()
	end
end

local workspace = { CurrentCamera = camera }
function workspace:GetPropertyChangedSignal()
	return Signal("workspace.prop")
end

local actions = {}
M.actions = actions
local services = {
	TweenService = {
		Create = function(_, instance, _, props)
			local tween = { Completed = Signal("Tween.Completed") }
			function tween:Play()
				for key, value in pairs(props) do
					instance[key] = value
				end
				tween.Completed:Fire(Enum.PlaybackState.Completed)
			end
			function tween:Cancel() end
			function tween:Pause() end
			return tween
		end,
	},
	UserInputService = UIS,
	GuiService = {
		GetGuiInset = function()
			return Vector2.new(0, 36), Vector2.new(0, 0)
		end,
	},
	HttpService = {
		JSONEncode = function(_, value)
			return serde.encode("json", value)
		end,
		JSONDecode = function(_, text)
			return serde.decode("json", text)
		end,
		GenerateGUID = function()
			return string.format("%08x-%04x", math.random(0, 0x7fffffff), math.random(0, 0xffff))
		end,
	},
	ContextActionService = {
		BindActionAtPriority = function(_, name, fn, _, _, ...)
			actions[name] = { fn = fn, inputs = { ... } }
		end,
		UnbindAction = function(_, name)
			actions[name] = nil
		end,
		GetAllBoundActionInfo = function()
			return {}
		end,
	},
	LocalizationService = { RobloxLocaleId = "ru-ru" },
	RunService = { Heartbeat = Signal("Heartbeat"), RenderStepped = Signal("RenderStepped") },
}
local hidden = new("Folder")
hidden.Name = "HiddenUI"
M.hidden = hidden
local playerGui = new("Folder")
services.Players = { LocalPlayer = { WaitForChild = function()
	return playerGui
end } }
services.CoreGui = new("Folder")

local sources = {}
M.sources = sources

local game = setmetatable({}, {
	__index = {
		GetService = function(_, name)
			local service = services[name]
			if not service then
				error("mock: unknown service " .. name)
			end
			return service
		end,
		HttpGet = function(_, url)
			for pattern, text in pairs(sources) do
				if url:find(pattern, 1, true) then
					return text
				end
			end
			error("mock: no source for " .. url)
		end,
	},
})

-- Environment -------------------------------------------------------------------------------

local env
local function typeofProxy(value)
	if data[value] then
		return "Instance"
	end
	return typeof(value)
end

local Instance = {
	new = function(className, parent)
		local p = new(className)
		if parent then
			p.Parent = parent
		end
		return p
	end,
}

local TweenInfo = {
	new = function(time, style, direction)
		return { Time = time or 1, EasingStyle = style, EasingDirection = direction }
	end,
}

env = {
	game = game,
	workspace = workspace,
	Instance = Instance,
	Enum = Enum,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = Vector2,
	Vector3 = Vector3,
	Color3 = roblox.Color3,
	Font = roblox.Font,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	TweenInfo = TweenInfo,
	typeof = typeofProxy,
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		table.insert(M.warnings, table.concat(parts, " "))
	end,
	print = function() end,
	task = task,
	-- executor API
	writefile = function(path, content)
		M.files[path] = content
	end,
	readfile = function(path)
		return M.files[path] or error("no file " .. path)
	end,
	isfile = function(path)
		return M.files[path] ~= nil
	end,
	isfolder = function(path)
		return M.files[path .. "/"] ~= nil
	end,
	makefolder = function(path)
		M.files[path .. "/"] = ""
	end,
	listfiles = function(folder)
		local out = {}
		for path, content in pairs(M.files) do
			if content ~= "" and path:sub(1, #folder + 1) == folder .. "/" and not path:sub(#folder + 2):find("/") then
				table.insert(out, path)
			end
		end
		return out
	end,
	delfile = function(path)
		M.files[path] = nil
	end,
	setclipboard = function(text)
		M.clipboard = text
	end,
	gethui = function()
		return hidden
	end,
}
env.getgenv = function()
	return env
end
env.loadstring = function(source, name)
	return luau.load(source, { debugName = name or "chunk", environment = env })
end
setmetatable(env, { __index = function(_, key)
	return (getfenv and getfenv(0) or _G)[key]
end })
M.env = env

function M.run(source, name)
	local fn = luau.load(source, { debugName = name or "chunk", environment = env })
	return fn()
end

function M.setTouch(touch)
	UIS.TouchEnabled = touch
	UIS.KeyboardEnabled = not touch
	UIS.MouseEnabled = not touch
end

return M
