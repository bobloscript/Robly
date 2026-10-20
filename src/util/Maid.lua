--!nocheck
-- Maid: collects connections, instances, objects and functions and cleans
-- them all at once. Every Robly object owns one, so closing a window leaves
-- no connections or instances behind (brief, rule 6).

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Add(item)
	if item ~= nil then
		table.insert(self._tasks, item)
	end
	return item
end

local function cleanup(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for index = #tasks, 1, -1 do
		local ok, err = pcall(cleanup, tasks[index])
		if not ok then
			warn("[Robly] cleanup error: " .. tostring(err))
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
