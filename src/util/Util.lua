-- Util: small pure helpers (colors, numbers, tables, UTF-8 case, base64).

local Util = {}

-- Colors ---------------------------------------------------------------

function Util.hex(value)
	if typeof(value) == "Color3" then
		return value
	end
	local s = tostring(value):gsub("#", "")
	if #s == 3 then
		s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
	end
	local r = tonumber(s:sub(1, 2), 16)
	local g = tonumber(s:sub(3, 4), 16)
	local b = tonumber(s:sub(5, 6), 16)
	if not (r and g and b) or #s ~= 6 then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

local function channel(x)
	return math.clamp(math.floor(x * 255 + 0.5), 0, 255)
end

function Util.toHex(color)
	return string.format("%02X%02X%02X", channel(color.R), channel(color.G), channel(color.B))
end

local function linear(c)
	if c <= 0.03928 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

function Util.luminance(color)
	return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
end

function Util.contrast(a, b)
	local la, lb = Util.luminance(a), Util.luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

-- Text colour that stays readable on top of an accent colour (brief: dark
-- accent.ink on bright accents, white on dark ones).
function Util.inkFor(accent)
	local dark = accent:Lerp(Color3.new(0, 0, 0), 0.9)
	local white = Color3.new(1, 1, 1)
	if Util.contrast(accent, dark) >= Util.contrast(accent, white) then
		return dark
	end
	return white
end

function Util.darken(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function Util.lighten(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

-- Numbers --------------------------------------------------------------

function Util.decimals(step)
	if not step or step <= 0 then
		return 0
	end
	local s = string.format("%.6f", step):gsub("0+$", "")
	local dot = s:find("%.")
	if not dot then
		return 0
	end
	return #s - dot
end

function Util.snap(value, step, min)
	if not step or step <= 0 then
		return value
	end
	min = min or 0
	local snapped = min + math.floor((value - min) / step + 0.5) * step
	local d = Util.decimals(step)
	return tonumber(string.format("%." .. d .. "f", snapped))
end

function Util.formatNumber(value, step)
	if type(value) ~= "number" then
		return tostring(value)
	end
	return string.format("%." .. Util.decimals(step) .. "f", value)
end

-- Tables ---------------------------------------------------------------

function Util.copy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = Util.copy(v)
	end
	return out
end

function Util.equal(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not Util.equal(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function Util.merge(defaults, options)
	local out = {}
	for k, v in pairs(defaults or {}) do
		out[k] = v
	end
	for k, v in pairs(options or {}) do
		out[k] = v
	end
	return out
end

-- UTF-8 case (Latin, Latin-1, Cyrillic) ---------------------------------

local function mapCase(s, toUpper)
	local ok, result = pcall(function()
		local out = table.create(#s)
		for _, code in utf8.codes(s) do
			if toUpper then
				if (code >= 0x61 and code <= 0x7A) or (code >= 0xE0 and code <= 0xFE and code ~= 0xF7) or (code >= 0x430 and code <= 0x44F) then
					code -= 0x20
				elseif code >= 0x450 and code <= 0x45F then
					code -= 0x50
				end
			else
				if (code >= 0x41 and code <= 0x5A) or (code >= 0xC0 and code <= 0xDE and code ~= 0xD7) or (code >= 0x410 and code <= 0x42F) then
					code += 0x20
				elseif code >= 0x400 and code <= 0x40F then
					code += 0x50
				end
			end
			table.insert(out, utf8.char(code))
		end
		return table.concat(out)
	end)
	if ok then
		return result
	end
	return toUpper and s:upper() or s:lower()
end

function Util.upper(s)
	return mapCase(s, true)
end

function Util.lower(s)
	return mapCase(s, false)
end

function Util.trim(s)
	return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.sanitizeFileName(name)
	name = Util.trim(tostring(name or ""))
	name = name:gsub('[\\/:%*%?"<>|]', "_")
	if name == "" then
		name = "default"
	end
	return name:sub(1, 48)
end

-- Base64 ---------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for i = 1, #ALPHABET do
	DECODE[ALPHABET:sub(i, i)] = i - 1
end

function Util.base64Encode(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = bit32.extract(n, 18, 6)
		local c2 = bit32.extract(n, 12, 6)
		local c3 = bit32.extract(n, 6, 6)
		local c4 = bit32.extract(n, 0, 6)
		table.insert(out, ALPHABET:sub(c1 + 1, c1 + 1))
		table.insert(out, ALPHABET:sub(c2 + 1, c2 + 1))
		table.insert(out, b and ALPHABET:sub(c3 + 1, c3 + 1) or "=")
		table.insert(out, c and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

function Util.base64Decode(data)
	data = tostring(data):gsub("[^%w%+/=]", "")
	local out = {}
	for i = 1, #data, 4 do
		local chunk = data:sub(i, i + 3)
		local n, pad = 0, 0
		for j = 1, 4 do
			local ch = chunk:sub(j, j)
			local v = DECODE[ch]
			if v == nil then
				v = 0
				pad += 1
			end
			n = n * 64 + v
		end
		local a = bit32.extract(n, 16, 8)
		local b = bit32.extract(n, 8, 8)
		local c = bit32.extract(n, 0, 8)
		table.insert(out, string.char(a))
		if pad < 2 then
			table.insert(out, string.char(b))
		end
		if pad < 1 then
			table.insert(out, string.char(c))
		end
	end
	return table.concat(out)
end

return Util
