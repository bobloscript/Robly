-- Store: the single source of truth for every control value (brief, rule 4).
-- Controls only display values; configs, detached windows, the keybind panel
-- and quick buttons all read and write through the same store.
--
-- Persist kinds: "profile" (saved in config profiles), "ui" (Robly's own
-- interface settings, saved once per script), false (never saved).

local Signal = import("util/Signal")
local Util = import("util/Util")

local Store = {}
Store.__index = Store

function Store.new()
	local self = setmetatable({}, Store)
	self.Values = {}
	self.Defaults = {}
	self.Meta = {}
	self.Loaded = {}
	self.LoadedKind = {}
	self.Changed = Signal.new()
	self._signals = {}
	return self
end

function Store:_signal(flag)
	local signal = self._signals[flag]
	if not signal then
		signal = Signal.new()
		self._signals[flag] = signal
	end
	return signal
end

-- Registers a flag. If a value for it was already loaded (from a config), that
-- value wins. Returns value, wasLoaded.
function Store:Register(flag, default, meta)
	meta = meta or {}
	self.Meta[flag] = meta
	self.Defaults[flag] = Util.copy(default)
	if self.Values[flag] == nil then
		self.Values[flag] = Util.copy(default)
		return self.Values[flag], false
	end
	local loaded = self.Values[flag]
	if meta.validate then
		local ok, fixed = pcall(meta.validate, loaded)
		if ok and fixed ~= nil then
			self.Values[flag] = fixed
		else
			self.Values[flag] = Util.copy(default)
		end
	elseif default ~= nil and typeof(loaded) ~= typeof(default) then
		self.Values[flag] = Util.copy(default)
	end
	return self.Values[flag], self.Loaded[flag] == true and not Util.equal(self.Values[flag], default)
end

function Store:Has(flag)
	return self.Meta[flag] ~= nil
end

function Store:Get(flag)
	return self.Values[flag]
end

function Store:Default(flag)
	return Util.copy(self.Defaults[flag])
end

function Store:Set(flag, value, source)
	local old = self.Values[flag]
	if Util.equal(old, value) then
		return false
	end
	self.Values[flag] = Util.copy(value)
	local signal = self._signals[flag]
	if signal then
		signal:Fire(value, old, source)
	end
	self.Changed:Fire(flag, value, old, source)
	return true
end

function Store:OnChanged(flag, fn)
	return self:_signal(flag):Connect(fn)
end

-- Serialisation ----------------------------------------------------------------

local function encode(value)
	local kind = typeof(value)
	if kind == "Color3" then
		return { __t = "c3", v = Util.toHex(value) }
	elseif kind == "EnumItem" then
		return { __t = "enum", e = tostring(value.EnumType), v = value.Name }
	elseif kind == "table" then
		local out = {}
		for k, v in pairs(value) do
			out[k] = encode(v)
		end
		return out
	end
	return value
end

local function decode(value)
	if type(value) ~= "table" then
		return value
	end
	if value.__t == "c3" then
		return Util.hex(value.v)
	elseif value.__t == "enum" then
		local ok, item = pcall(function()
			return Enum[value.e][value.v]
		end)
		return ok and item or nil
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = decode(v)
	end
	return out
end

Store.encode = encode
Store.decode = decode

-- Snapshot of every flag with the given persist kind.
function Store:Snapshot(kind)
	local out = {}
	for flag, meta in pairs(self.Meta) do
		if meta.persist == kind and self.Values[flag] ~= nil then
			out[flag] = encode(self.Values[flag])
		end
	end
	-- Values loaded from a file whose control does not exist (yet) are kept,
	-- so saving never silently drops them.
	for flag, loadedKind in pairs(self.LoadedKind) do
		if loadedKind == kind and not self.Meta[flag] and self.Values[flag] ~= nil then
			out[flag] = encode(self.Values[flag])
		end
	end
	return out
end

-- Applies a snapshot. Unknown flags are kept for later registration.
function Store:Load(snapshot, source, kind)
	local count = 0
	for flag, raw in pairs(snapshot or {}) do
		local value = decode(raw)
		if value ~= nil then
			count += 1
			self.Loaded[flag] = true
			if kind then
				self.LoadedKind[flag] = kind
			end
			if self.Meta[flag] then
				self:Set(flag, value, source or "config")
			else
				self.Values[flag] = value
			end
		end
	end
	return count
end

function Store:ResetToDefaults(kind)
	for flag, meta in pairs(self.Meta) do
		if meta.persist == kind then
			self:Set(flag, Util.copy(self.Defaults[flag]), "reset")
		end
	end
end

function Store:Destroy()
	self.Changed:DisconnectAll()
	for _, signal in pairs(self._signals) do
		signal:DisconnectAll()
	end
	self._signals = {}
end

return Store
