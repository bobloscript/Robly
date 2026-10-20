-- Binds: keyboard shortcuts for the whole window.
--
-- Rules from the brief (§15):
--   1. Paused while typing — nothing fires while a TextBox (chat, game input,
--      Robly field) has focus, and presses the game already processed are
--      ignored.
--   2. Game conflicts — a key the game uses is reported when assigned; Robly
--      only takes it from the game (ContextActionService, high priority, Sink)
--      if the player agreed. That choice is saved with the bind.
--   3. Phones have no keyboard — quick buttons replace the panel.
--
-- A bind's value lives in the Store as { Key = "Ctrl+X", Override = false }.

local Services = import("core/Services")
local Signal = import("util/Signal")

local Binds = {}
Binds.__index = Binds

local MODIFIERS = {
	LeftControl = "Ctrl", RightControl = "Ctrl", LeftShift = "Shift", RightShift = "Shift",
	LeftAlt = "Alt", RightAlt = "Alt", LeftSuper = "Meta", RightSuper = "Meta",
}

local DISPLAY = {
	LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
	LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", Backquote = "`", Minus = "-", Equals = "=",
	LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",", Period = ".",
	Slash = "/", BackSlash = "\\", Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
	Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", PageUp = "PgUp", PageDown = "PgDn",
	Escape = "Esc", Delete = "Del", Insert = "Ins", CapsLock = "Caps",
}

-- Keys Roblox itself (or most games) use.
Binds.GameKeys = {
	W = true, A = true, S = true, D = true, Space = true, Tab = true, Slash = true, Backquote = true,
	Escape = true, Up = true, Down = true, Left = true, Right = true, I = true, O = true,
	LeftShift = true, F9 = true, Return = true, Backspace = true,
}

local parseCache = {}

function Binds.parse(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local cached = parseCache[text]
	if cached then
		return cached
	end
	local parts = string.split(text, "+")
	local keyName = parts[#parts]
	local ok, key = pcall(function()
		return Enum.KeyCode[keyName]
	end)
	if not ok or not key then
		return nil
	end
	local parsed = { key = key, Ctrl = false, Shift = false, Alt = false, Meta = false }
	for i = 1, #parts - 1 do
		parsed[parts[i]] = true
	end
	parseCache[text] = parsed
	return parsed
end

function Binds.normalize(value)
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	if type(value) == "string" then
		return value
	end
	return ""
end

function Binds.display(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local parts = string.split(text, "+")
	for index, part in ipairs(parts) do
		parts[index] = DISPLAY[part] or part
	end
	return table.concat(parts, "+")
end

local function held(uis, name, except)
	local keys = {
		Ctrl = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl },
		Shift = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
		Alt = { Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt },
		Meta = { Enum.KeyCode.LeftSuper, Enum.KeyCode.RightSuper },
	}
	for _, key in ipairs(keys[name]) do
		if key ~= except and uis:IsKeyDown(key) then
			return true
		end
	end
	return false
end

function Binds.matches(text, keyCode)
	local parsed = Binds.parse(text)
	if not parsed or parsed.key ~= keyCode then
		return false
	end
	local uis = Services.UserInputService
	for _, name in ipairs({ "Ctrl", "Shift", "Alt" }) do
		if parsed[name] ~= held(uis, name, keyCode) then
			return false
		end
	end
	return true
end

function Binds.new(window)
	local self = setmetatable({}, Binds)
	self.Window = window
	self.Store = window.Store
	self.Entries = {}
	self.Fired = Signal.new()
	self.Changed = Signal.new()
	self.PausedChanged = Signal.new()
	self.Paused = false
	self.Capturing = nil
	self._connections = {}
	self._counter = 0

	local uis = Services.UserInputService
	local function typing()
		local ok, box = pcall(function()
			return uis:GetFocusedTextBox()
		end)
		return ok and box ~= nil
	end
	local function setPaused(value)
		if self.Paused ~= value then
			self.Paused = value
			self.PausedChanged:Fire(value)
		end
	end
	table.insert(self._connections, uis.TextBoxFocused:Connect(function()
		setPaused(true)
	end))
	table.insert(self._connections, uis.TextBoxFocusReleased:Connect(function()
		task.defer(function()
			setPaused(typing())
		end)
	end))

	table.insert(self._connections, uis.InputBegan:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard or self.Capturing or typing() then
			return
		end
		for _, entry in ipairs(table.clone(self.Entries)) do
			local value = self.Store:Get(entry.Flag)
			if type(value) == "table" and not value.Override and Binds.matches(value.Key, input.KeyCode) then
				if not processed then
					self:Trigger(entry, true)
				end
			end
		end
	end))
	table.insert(self._connections, uis.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		for _, entry in ipairs(table.clone(self.Entries)) do
			if entry.Mode == "Hold" and entry.Down then
				local value = self.Store:Get(entry.Flag)
				local parsed = type(value) == "table" and Binds.parse(value.Key)
				if parsed and parsed.key == input.KeyCode and not value.Override then
					self:Trigger(entry, false)
				end
			end
		end
	end))
	return self
end

function Binds:KeyOf(entry)
	local value = self.Store:Get(entry.Flag)
	return type(value) == "table" and value.Key or ""
end

function Binds:Add(entry)
	self._counter += 1
	entry.Id = entry.Id or ("bind" .. self._counter)
	entry.Mode = entry.Mode or (entry.Target and "Toggle" or "Action")
	entry.LastFired = 0
	table.insert(self.Entries, entry)
	entry._watch = self.Store:OnChanged(entry.Flag, function()
		self:_rebind(entry)
		self.Changed:Fire()
	end)
	if entry.Target then
		entry._target = self.Store:OnChanged(entry.Target, function()
			self.Changed:Fire()
		end)
	end
	self:_rebind(entry)
	self.Changed:Fire()
	return entry
end

function Binds:Remove(entry)
	local index = table.find(self.Entries, entry)
	if index then
		table.remove(self.Entries, index)
	end
	if entry._watch then
		entry._watch:Disconnect()
	end
	if entry._target then
		entry._target:Disconnect()
	end
	self:_unbindAction(entry)
	self.Changed:Fire()
end

function Binds:_unbindAction(entry)
	if entry._action then
		pcall(function()
			Services.ContextActionService:UnbindAction(entry._action)
		end)
		entry._action = nil
	end
end

-- Keys the player allowed Robly to take from the game are bound through
-- ContextActionService at a high priority and sunk.
function Binds:_rebind(entry)
	self:_unbindAction(entry)
	local value = self.Store:Get(entry.Flag)
	if type(value) ~= "table" or not value.Override then
		return
	end
	local parsed = Binds.parse(value.Key)
	if not parsed then
		return
	end
	local name = "Robly_" .. entry.Id .. "_" .. tostring(self.Window.Id)
	entry._action = name
	pcall(function()
		Services.ContextActionService:BindActionAtPriority(name, function(_, state, input)
			local ok, box = pcall(function()
				return Services.UserInputService:GetFocusedTextBox()
			end)
			if (ok and box) or self.Capturing then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				if Binds.matches(value.Key, input.KeyCode) then
					self:Trigger(entry, true)
					return Enum.ContextActionResult.Sink
				end
			elseif state == Enum.UserInputState.End and entry.Mode == "Hold" and entry.Down then
				self:Trigger(entry, false)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, 3000, parsed.key)
	end)
end

function Binds:IsOn(entry)
	if entry.Target then
		return self.Store:Get(entry.Target) == true
	end
	return entry.Down == true
end

function Binds:CooldownLeft(entry)
	if not entry.Cooldown then
		return 0
	end
	return math.max(0, entry.Cooldown - (os.clock() - entry.LastFired))
end

function Binds:Trigger(entry, down)
	local state = nil
	if entry.Mode == "Toggle" and entry.Target then
		if not down then
			return
		end
		state = not (self.Store:Get(entry.Target) == true)
		self.Store:Set(entry.Target, state, "bind")
		if entry.Callback then
			task.spawn(entry.Callback, state)
		end
	elseif entry.Mode == "Hold" then
		entry.Down = down
		state = down
		if entry.Callback then
			task.spawn(entry.Callback, down)
		end
	else
		if not down then
			return
		end
		if self:CooldownLeft(entry) > 0 then
			return
		end
		entry.LastFired = os.clock()
		if entry.Callback then
			task.spawn(entry.Callback)
		end
	end
	self.Fired:Fire(entry, state, down)
end

-- Conflicts ---------------------------------------------------------------------------

function Binds:GameConflict(text)
	local parsed = Binds.parse(text)
	if not parsed then
		return false
	end
	if Binds.GameKeys[parsed.key.Name] and not (parsed.Ctrl or parsed.Alt) then
		return true
	end
	local ok, actions = pcall(function()
		return Services.ContextActionService:GetAllBoundActionInfo()
	end)
	if ok and type(actions) == "table" then
		for name, info in pairs(actions) do
			if type(name) == "string" and not name:find("^Robly_") and type(info) == "table" and type(info.inputTypes) == "table" then
				for _, inputType in ipairs(info.inputTypes) do
					if inputType == parsed.key then
						return true
					end
				end
			end
		end
	end
	return false
end

function Binds:BindConflict(text, except)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	for _, entry in ipairs(self.Entries) do
		if entry ~= except and self:KeyOf(entry) == text then
			return entry
		end
	end
	return nil
end

-- Capture -----------------------------------------------------------------------------------

-- Waits for the next key (with modifiers). callback(key) — key is "" when
-- cleared (Backspace/Delete) and nil when cancelled (Escape / cancel()).
function Binds:Capture(callback)
	self:CancelCapture()
	local uis = Services.UserInputService
	local capture = {}
	local onlyModifier = nil
	local function finish(result)
		if self.Capturing ~= capture then
			return
		end
		self.Capturing = nil
		capture.began:Disconnect()
		capture.ended:Disconnect()
		task.spawn(callback, result)
	end
	capture.finish = finish
	capture.began = uis.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local name = input.KeyCode.Name
		if input.KeyCode == Enum.KeyCode.Escape then
			finish(nil)
			return
		end
		if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
			finish("")
			return
		end
		if MODIFIERS[name] then
			onlyModifier = name
			return
		end
		onlyModifier = nil
		local parts = {}
		for _, mod in ipairs({ "Ctrl", "Shift", "Alt" }) do
			if held(uis, mod, input.KeyCode) then
				table.insert(parts, mod)
			end
		end
		table.insert(parts, name)
		finish(table.concat(parts, "+"))
	end)
	capture.ended = uis.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard and onlyModifier == input.KeyCode.Name then
			finish(onlyModifier)
		end
	end)
	self.Capturing = capture
	return function()
		finish(nil)
	end
end

function Binds:CancelCapture()
	if self.Capturing then
		self.Capturing.finish(nil)
	end
end

function Binds:Destroy()
	self:CancelCapture()
	for _, entry in ipairs(table.clone(self.Entries)) do
		self:Remove(entry)
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self.Fired:DisconnectAll()
	self.Changed:DisconnectAll()
	self.PausedChanged:DisconnectAll()
end

return Binds
