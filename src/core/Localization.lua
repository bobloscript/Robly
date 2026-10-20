-- Localization of the *script's* texts (brief §13).
--
-- A text can be:
--   "Auto farm"                         plain, never translated
--   "farm.auto"                         key looked up in Language.Strings
--   { en = "Auto farm", ru = "Автофарм" } inline translations
--   function() return "…" end           computed
-- Placeholders: "Killed {count} {count|mob|mobs}" with vars = { count = 3 }.
-- Plural forms follow each language's rules (ru: моб / моба / мобов).

local Signal = import("util/Signal")
local Services = import("core/Services")
local Compat = import("util/Compat")
local Strings = import("core/Strings")

local Localization = {}
Localization.__index = Localization

local PLURAL = {}
function PLURAL.slavic(n)
	local m10, m100 = n % 10, n % 100
	if m10 == 1 and m100 ~= 11 then
		return 1
	elseif m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20) then
		return 2
	end
	return 3
end
function PLURAL.polish(n)
	local m10, m100 = n % 10, n % 100
	if n == 1 then
		return 1
	elseif m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20) then
		return 2
	end
	return 3
end
function PLURAL.french(n)
	return n < 2 and 1 or 2
end
function PLURAL.none()
	return 1
end
function PLURAL.default(n)
	return n == 1 and 1 or 2
end

local RULES = {
	ru = PLURAL.slavic, uk = PLURAL.slavic, be = PLURAL.slavic, pl = PLURAL.polish,
	fr = PLURAL.french, pt = PLURAL.default, ja = PLURAL.none, zh = PLURAL.none, ko = PLURAL.none,
	th = PLURAL.none, vi = PLURAL.none, id = PLURAL.none, tr = PLURAL.default,
}

function Localization.pluralIndex(lang, n)
	local rule = RULES[lang] or PLURAL.default
	return rule(math.abs(math.floor(tonumber(n) or 0)))
end

-- Marker for the library's own texts: Localization.L("cancel")
function Localization.L(key, vars)
	return { __lib = key, vars = vars }
end

local function normalizeCode(code)
	code = tostring(code or ""):lower()
	return code:match("^(%a+)") or code
end

function Localization.new(options, dev)
	local self = setmetatable({}, Localization)
	options = options or {}
	self.Configured = options.Default ~= nil or options.Available ~= nil
	self.Default = normalizeCode(options.Default or "en")
	self.Available = {}
	for _, code in ipairs(options.Available or { self.Default }) do
		table.insert(self.Available, normalizeCode(code))
	end
	if not table.find(self.Available, self.Default) then
		table.insert(self.Available, 1, self.Default)
	end
	self.Strings = options.Strings or {}
	self.Library = options.Library or {}
	self.Names = options.Names or {}
	self.Dev = dev == true
	self.Current = self.Default
	self.Changed = Signal.new()
	self._bindings = setmetatable({}, { __mode = "k" })
	self._warned = {}

	-- Script with one language: library texts still follow the player's
	-- Roblox language when Robly has them.
	if not self.Configured then
		local detected = self:DetectRoblox(true)
		self.LibraryLanguage = detected or "en"
	end
	if options.Url then
		self:LoadRemote(options.Url)
	end
	return self
end

function Localization:IsMultilingual()
	return #self.Available > 1
end

function Localization:NameOf(code)
	return self.Names[code] or Strings.Names[code] or code:upper()
end

function Localization:Languages()
	local out = {}
	for _, code in ipairs(self.Available) do
		table.insert(out, { Code = code, Name = self:NameOf(code) })
	end
	return out
end

-- Roblox language of the player, if supported (by the script, or by the
-- library when libraryOnly is true).
function Localization:DetectRoblox(libraryOnly)
	local ok, locale = pcall(function()
		return Services.LocalizationService.RobloxLocaleId
	end)
	if not ok or type(locale) ~= "string" then
		return nil
	end
	local code = normalizeCode(locale)
	if libraryOnly then
		return Strings[code] and code or nil
	end
	if table.find(self.Available, code) then
		return code
	end
	return nil
end

function Localization:_warnOnce(key, lang)
	if not self.Dev then
		return
	end
	local id = key .. "@" .. lang
	if self._warned[id] then
		return
	end
	self._warned[id] = true
	warn("[Robly] " .. self:Lib("missing_translation", { key = key, lang = lang }))
end

function Localization:Format(text, vars, lang)
	if not vars or not text:find("{", 1, true) then
		return text
	end
	lang = lang or self.Current
	return (text:gsub("{([%w_]+)([^}]*)}", function(key, forms)
		local value = vars[key]
		if value == nil then
			return nil
		end
		if forms ~= "" and forms:sub(1, 1) == "|" then
			local list = string.split(forms:sub(2), "|")
			local index = Localization.pluralIndex(lang, value)
			return list[math.min(index, #list)] or tostring(value)
		end
		return tostring(value)
	end))
end

function Localization:Lib(key, vars)
	local lang = self.LibraryLanguage or self.Current
	local override = self.Library[lang]
	local text = (override and override[key]) or (Strings[lang] and Strings[lang][key])
	if text == nil then
		lang = "en"
		text = (self.Library.en and self.Library.en[key]) or Strings.en[key] or key
	end
	return self:Format(text, vars, lang)
end

-- Resolves any text spec to a string in the current language.
function Localization:Get(spec, vars)
	local kind = type(spec)
	if spec == nil then
		return ""
	elseif kind == "function" then
		local ok, value = pcall(spec, self.Current)
		return ok and tostring(value) or ""
	elseif kind == "table" then
		if spec.__lib then
			return self:Lib(spec.__lib, vars or spec.vars)
		end
		local text = spec[self.Current]
		local lang = self.Current
		if text == nil then
			text = spec[self.Default]
			lang = self.Default
		end
		if text == nil then
			local _, first = next(spec)
			text = first
		end
		return self:Format(tostring(text or ""), vars, lang)
	end
	local text = tostring(spec)
	local current = self.Strings[self.Current]
	if current and current[text] ~= nil then
		return self:Format(current[text], vars)
	end
	local default = self.Strings[self.Default]
	if default and default[text] ~= nil then
		if self.Current ~= self.Default then
			self:_warnOnce(text, self.Current)
		end
		return self:Format(default[text], vars, self.Default)
	end
	if self.Dev and text:match("^[%w_]+%.[%w_.]+$") then
		self:_warnOnce(text, self.Current)
	end
	return self:Format(text, vars)
end

-- All strings a search should match for this text: current language,
-- default language and the key itself (so "farm" finds "Фарм" too).
function Localization:SearchTexts(spec)
	local out = { self:Get(spec) }
	if type(spec) == "string" then
		table.insert(out, spec)
		local default = self.Strings[self.Default]
		if default and default[spec] then
			table.insert(out, default[spec])
		end
		local en = self.Strings.en
		if en and en[spec] then
			table.insert(out, en[spec])
		end
	elseif type(spec) == "table" and not spec.__lib then
		for _, value in pairs(spec) do
			table.insert(out, tostring(value))
		end
	end
	return out
end

-- Binds instance[prop] to a text spec; it re-renders when the language changes.
function Localization:Bind(instance, prop, spec, vars)
	local entries = self._bindings[instance]
	if not entries then
		entries = {}
		self._bindings[instance] = entries
	end
	entries[prop] = { spec = spec, vars = vars }
	local v = type(vars) == "function" and vars() or vars
	instance[prop] = self:Get(spec, v)
end

function Localization:Unbind(instance, prop)
	local entries = self._bindings[instance]
	if entries then
		entries[prop] = nil
	end
end

function Localization:Refresh()
	for instance, entries in pairs(self._bindings) do
		for prop, entry in pairs(entries) do
			local vars = type(entry.vars) == "function" and entry.vars() or entry.vars
			pcall(function()
				instance[prop] = self:Get(entry.spec, vars)
			end)
		end
	end
end

function Localization:SetLanguage(code)
	code = normalizeCode(code)
	if not table.find(self.Available, code) then
		return false
	end
	if self.Current == code then
		return true
	end
	self.Current = code
	if self.Configured then
		self.LibraryLanguage = Strings[code] and code or nil
	end
	self:Refresh()
	self.Changed:Fire(code)
	return true
end

-- Merge translations fetched from a URL (JSON: { "ru": { "farm.auto": "…" } })
-- or a table { ru = "https://…/ru.json" }.
function Localization:LoadRemote(source)
	task.spawn(function()
		local function merge(lang, data)
			if type(data) ~= "table" then
				return
			end
			self.Strings[lang] = self.Strings[lang] or {}
			for key, value in pairs(data) do
				self.Strings[lang][key] = value
			end
		end
		local function fetch(url)
			local body = Compat.httpGet(url)
			if not body then
				return nil
			end
			local ok, data = pcall(function()
				return Services.HttpService:JSONDecode(body)
			end)
			return ok and data or nil
		end
		if type(source) == "string" then
			local data = fetch(source)
			if type(data) == "table" then
				for lang, entries in pairs(data) do
					merge(normalizeCode(lang), entries)
				end
			end
		elseif type(source) == "table" then
			for lang, url in pairs(source) do
				merge(normalizeCode(lang), fetch(url))
			end
		end
		self:Refresh()
		self.Changed:Fire(self.Current)
	end)
end

function Localization:Destroy()
	self.Changed:DisconnectAll()
	self._bindings = {}
end

return Localization
