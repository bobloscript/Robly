--!nocheck
-- Signal: tiny event object used everywhere inside Robly.
-- Handlers run synchronously; an error in one handler is reported and does
-- not stop the others.

local Signal = {}
Signal.__index = Signal

local function report(err)
	warn("[Robly] " .. tostring(err) .. "\n" .. debug.traceback())
end

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self._handlers
	local handler = { fn = fn, connected = true }
	table.insert(handlers, handler)

	local connection = { Connected = true }
	function connection.Disconnect()
		if not handler.connected then
			return
		end
		handler.connected = false
		connection.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, handler in ipairs(table.clone(self._handlers)) do
		if handler.connected then
			xpcall(handler.fn, report, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, handler in ipairs(self._handlers) do
		handler.connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
