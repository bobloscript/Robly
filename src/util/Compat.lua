-- Compat: every executor-specific function goes through here. Each one is
-- checked before use and has a fallback, so Robly runs on weak executors
-- (Xeno, Solara, mobile) without file system, clipboard or gethui.

local Compat = {}

-- Executor functions are plain globals of the script environment. Reading a
-- missing global just gives nil, so every lookup is safe.
local function pick(...)
	for i = 1, select("#", ...) do
		local candidate = select(i, ...)
		if type(candidate) == "function" then
			return candidate
		end
	end
	return nil
end

local function member(t, key)
	if type(t) == "table" and type(t[key]) == "function" then
		return t[key]
	end
	return nil
end

local syn = syn
local http = http

-- Services ---------------------------------------------------------------

local cloneref = pick(cloneref)

function Compat.service(name)
	local service = game:GetService(name)
	if cloneref then
		local ok, cloned = pcall(cloneref, service)
		if ok and cloned then
			return cloned
		end
	end
	return service
end

-- File system --------------------------------------------------------------

local writefile = pick(writefile)
local readfile = pick(readfile)
local isfile = pick(isfile)
local isfolder = pick(isfolder)
local makefolder = pick(makefolder)
local listfiles = pick(listfiles)
local delfile = pick(delfile)

Compat.hasFileSystem = writefile ~= nil and readfile ~= nil and isfile ~= nil and makefolder ~= nil and isfolder ~= nil

function Compat.ensureFolder(path)
	if not Compat.hasFileSystem then
		return false
	end
	local current = ""
	for part in tostring(path):gmatch("[^/]+") do
		current = current == "" and part or (current .. "/" .. part)
		local ok, exists = pcall(isfolder, current)
		if not (ok and exists) then
			pcall(makefolder, current)
		end
	end
	return true
end

function Compat.write(path, content)
	if not Compat.hasFileSystem then
		return false
	end
	return (pcall(writefile, path, content))
end

function Compat.read(path)
	if not Compat.hasFileSystem then
		return nil
	end
	local ok, exists = pcall(isfile, path)
	if not (ok and exists) then
		return nil
	end
	local okRead, content = pcall(readfile, path)
	if okRead then
		return content
	end
	return nil
end

function Compat.delete(path)
	if not delfile then
		return false
	end
	return (pcall(delfile, path))
end

function Compat.list(folder)
	if not listfiles then
		return {}
	end
	local ok, files = pcall(listfiles, folder)
	if not ok or type(files) ~= "table" then
		return {}
	end
	local out = {}
	for _, file in ipairs(files) do
		local name = tostring(file):gsub("\\", "/"):match("([^/]+)$")
		if name then
			table.insert(out, name)
		end
	end
	return out
end

-- Clipboard ---------------------------------------------------------------

local setclipboard = pick(setclipboard, toclipboard, set_clipboard, member(syn, "write_clipboard"), member(Clipboard, "set"))

Compat.hasClipboard = setclipboard ~= nil

function Compat.clipboard(text)
	if not setclipboard then
		return false
	end
	return (pcall(setclipboard, tostring(text)))
end

-- HTTP ----------------------------------------------------------------------

local request = pick(request, http_request, member(syn, "request"), member(http, "request"))

function Compat.httpGet(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" then
		return body
	end
	if request then
		local okReq, response = pcall(request, { Url = url, Method = "GET" })
		if okReq and type(response) == "table" and type(response.Body) == "string" then
			return response.Body
		end
	end
	return nil
end

-- GUI parent ------------------------------------------------------------------

local gethui = pick(gethui, get_hidden_gui)
local protect = pick(member(syn, "protect_gui"), protect_gui)

function Compat.mountGui(gui)
	if protect then
		pcall(protect, gui)
	end
	if gethui then
		local ok, parent = pcall(gethui)
		if ok and typeof(parent) == "Instance" then
			gui.Parent = parent
			return
		end
	end
	local okCore = pcall(function()
		gui.Parent = Compat.service("CoreGui")
	end)
	if okCore and gui.Parent then
		return
	end
	local players = Compat.service("Players")
	local player = players.LocalPlayer
	if player then
		gui.Parent = player:WaitForChild("PlayerGui")
	end
end

return Compat
