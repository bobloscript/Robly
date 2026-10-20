-- Config: profiles, autosave, autoload and Robly's own interface settings.
--
--   workspace/Robly/<Folder>/robly.json            interface: theme, language,
--                                                   animations, window/pill/detached
--                                                   positions, active & autoload profile
--   workspace/Robly/<Folder>/profiles/<name>.json  values of every "profile" flag
--
-- Without a file system (weak executors) everything keeps working in memory
-- and the player gets one notice.

local Compat = import("util/Compat")
local Util = import("util/Util")
local Signal = import("util/Signal")
local Services = import("core/Services")
local Theme = import("core/Theme")
local Motion = import("core/Motion")
local Localization = import("core/Localization")

local L = Localization.L

local Config = {}
Config.__index = Config

local function encode(data)
	local ok, text = pcall(function()
		return Services.HttpService:JSONEncode(data)
	end)
	return ok and text or nil
end

local function decode(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local ok, data = pcall(function()
		return Services.HttpService:JSONDecode(text)
	end)
	return ok and type(data) == "table" and data or nil
end

function Config.new(window)
	local self = setmetatable({}, Config)
	local opts = window.Options
	self.Window = window
	self.Store = window.Store
	self.Changed = Signal.new()
	self.FileSystem = Compat.hasFileSystem and opts.SaveConfig ~= false
	local folderName = opts.Folder or (type(window.TitleSpec) == "string" and window.TitleSpec) or "Script"
	self.Folder = "Robly/" .. Util.sanitizeFileName(folderName)
	self.Memory = {}
	self._pending = {}

	if self.FileSystem then
		Compat.ensureFolder(self.Folder .. "/profiles")
		self.Meta = decode(Compat.read(self.Folder .. "/robly.json")) or {}
	else
		self.Meta = {}
	end
	self.FirstRun = next(self.Meta) == nil
	if self.Meta.autosave == nil then
		self.Meta.autosave = opts.AutoSave ~= false
	end
	self.Current = self.Meta.profile or window.Loc:Lib("default_profile")

	-- Interface flags first, then the autoload profile (before any control
	-- exists: controls pick the values up when they register).
	self.Store:Load(self.Meta.ui or {}, "config")
	local autoload = self.Meta.autoload or self.Current
	local profile = self:_read(autoload)
	if profile and opts.AutoLoad ~= false then
		self.Store:Load(profile.values or {}, "config")
		self.Current = autoload
	end

	self._storeConnection = self.Store.Changed:Connect(function(flag)
		local meta = self.Store.Meta[flag]
		if not meta then
			return
		end
		if meta.persist == "profile" and self.Meta.autosave then
			self:_schedule("profile")
		elseif meta.persist == "ui" then
			self:_schedule("meta")
		end
	end)
	self._themeConnection = Theme.Changed:Connect(function(what)
		if what == "colors" then
			self:_schedule("meta")
		end
	end)
	self._motionConnection = Motion.Changed:Connect(function()
		self:_schedule("meta")
	end)
	window.Maid:Add(function()
		self._storeConnection:Disconnect()
		self._themeConnection:Disconnect()
		self._motionConnection:Disconnect()
		self.Changed:DisconnectAll()
	end)
	return self
end

-- Interface ----------------------------------------------------------------------------

function Config:ApplyInterface()
	local window = self.Window
	local opts = window.Options
	local meta = self.Meta
	if meta.theme then
		Theme.deserialize(meta.theme)
	elseif opts.Theme then
		Theme.apply(opts.Theme)
	end
	Motion.setMode(meta.animations or opts.Animations or "Full")

	local loc = window.Loc
	if meta.language and table.find(loc.Available, meta.language) then
		loc:SetLanguage(meta.language)
	elseif loc:IsMultilingual() then
		local detected = loc:DetectRoblox(false)
		if detected and detected ~= loc.Current then
			loc:SetLanguage(detected)
			self._detectedLanguage = detected
		elseif detected then
			self._detectedLanguage = detected
		end
	end
end

function Config:SaveInterface()
	self:_schedule("meta")
end

function Config:GetMeta(key)
	return self.Meta[key]
end

function Config:SetMeta(key, value)
	self.Meta[key] = value
	self:_schedule("meta")
end

function Config:GetDetached(id)
	local all = self.Meta.detached
	return type(all) == "table" and all[id] or nil
end

-- data = nil marks the window as closed but keeps its rect; partial merges.
function Config:SetDetached(id, data, partial)
	local all = self.Meta.detached
	if type(all) ~= "table" then
		all = {}
		self.Meta.detached = all
	end
	if data == nil then
		if all[id] then
			all[id].open = false
		end
	elseif partial and type(all[id]) == "table" then
		for key, value in pairs(data) do
			all[id][key] = value
		end
	else
		all[id] = data
	end
	self:_schedule("meta")
end

-- Saving ---------------------------------------------------------------------------------

function Config:_schedule(kind)
	if self._pending[kind] then
		return
	end
	self._pending[kind] = true
	task.delay(kind == "profile" and 1 or 0.5, function()
		if not self._pending[kind] then
			return
		end
		self._pending[kind] = nil
		if kind == "profile" then
			self:_write(self.Current)
		else
			self:_writeMeta()
		end
	end)
end

function Config:Flush()
	if self._pending.profile then
		self._pending.profile = nil
		self:_write(self.Current)
	end
	self._pending.meta = nil
	self:_writeMeta()
end

function Config:_writeMeta()
	local window = self.Window
	local meta = self.Meta
	meta.theme = Theme.serialize()
	meta.animations = Motion.Mode
	meta.language = window.Loc.Current
	meta.profile = self.Current
	meta.ui = self.Store:Snapshot("ui")
	if self.FileSystem then
		local text = encode(meta)
		if text then
			Compat.write(self.Folder .. "/robly.json", text)
		end
	end
end

function Config:_path(name)
	return self.Folder .. "/profiles/" .. Util.sanitizeFileName(name) .. ".json"
end

function Config:_read(name)
	if not name then
		return nil
	end
	if self.FileSystem then
		return decode(Compat.read(self:_path(name)))
	end
	return self.Memory[name]
end

function Config:_write(name)
	local data = {
		name = name,
		saved = os.time(),
		values = self.Store:Snapshot("profile"),
	}
	if self.FileSystem then
		local text = encode(data)
		if text then
			Compat.write(self:_path(name), text)
		end
	else
		self.Memory[name] = data
	end
	self.Changed:Fire("saved", name)
	return data
end

-- Profiles API ----------------------------------------------------------------------------

function Config:List()
	local names, seen = {}, {}
	local function add(name)
		if name and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	if self.FileSystem then
		for _, file in ipairs(Compat.list(self.Folder .. "/profiles")) do
			local name = file:match("^(.+)%.json$")
			if name then
				local data = self:_read(name)
				add(data and data.name or name)
			end
		end
	else
		for name in pairs(self.Memory) do
			add(name)
		end
	end
	add(self.Current)
	table.sort(names, function(a, b)
		if a == self.Current then
			return true
		elseif b == self.Current then
			return false
		end
		return Util.lower(a) < Util.lower(b)
	end)
	return names
end

function Config:Info(name)
	local data = self:_read(name)
	return {
		Name = name,
		Saved = data and data.saved or nil,
		Count = data and data.values and (function()
			local n = 0
			for _ in pairs(data.values) do
				n += 1
			end
			return n
		end)() or 0,
		Autoload = (self.Meta.autoload or self.Meta.profile) == name,
		Active = self.Current == name,
	}
end

function Config:Save(name)
	name = name and Util.trim(name) or self.Current
	if name == "" then
		return false
	end
	self.Current = name
	self._pending.profile = nil
	local data = self:_write(name)
	self:_writeMeta()
	self.Changed:Fire("list")
	return true, data
end

function Config:Load(name)
	local data = self:_read(name)
	if not data then
		return false, 0
	end
	self._pending.profile = nil
	self.Current = name
	local count = self.Store:Load(data.values or {}, "config")
	self._pending.profile = nil
	self:_writeMeta()
	self.Changed:Fire("list")
	return true, count
end

function Config:Delete(name)
	if self.FileSystem then
		Compat.delete(self:_path(name))
	else
		self.Memory[name] = nil
	end
	if self.Meta.autoload == name then
		self.Meta.autoload = nil
	end
	if self.Current == name then
		local rest = self:List()
		for _, other in ipairs(rest) do
			if other ~= name then
				self.Current = other
				break
			end
		end
		if self.Current == name then
			self.Current = self.Window.Loc:Lib("default_profile")
		end
	end
	self:_writeMeta()
	self.Changed:Fire("list")
end

function Config:SetAutoload(name)
	self.Meta.autoload = name
	self:_writeMeta()
	self.Changed:Fire("list")
end

function Config:SetAutosave(enabled)
	self.Meta.autosave = enabled
	self:_writeMeta()
end

-- First-run notices ----------------------------------------------------------------------

function Config:Notices()
	local window = self.Window
	if not Compat.hasFileSystem and window.Options.SaveConfig ~= false and window.Options.FileSystemNotice ~= false then
		window:Notify({ Title = L("no_fs"), Content = L("no_fs_desc"), Type = "warning", Duration = 6 })
	end
	if self._detectedLanguage and self.FirstRun then
		local loc = window.Loc
		window:Notify({
			Title = L("lang_detected"),
			Vars = { lang = loc:NameOf(loc.Current) },
			Content = L("lang_detected_desc"),
			Type = "info",
			Icon = "globe",
			Duration = 6,
			Action = {
				Text = L("change"),
				Callback = function()
					window:OpenLanguageMenu(window.Header)
				end,
			},
		})
	end
end

return Config
