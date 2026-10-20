-- Drag: pointer dragging for mouse and touch with a tap threshold.
--   Drag.attach(handle, {
--     onStart(pointer) -> bool?   (return false to cancel)
--     onMove(pointer, delta)      (only after the threshold)
--     onEnd(pointer, moved)
--     threshold = 6,
--   }, maid)

local Services = import("core/Services")
local Device = import("core/Device")

local Drag = {}

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

function Drag.attach(handle, callbacks, maid)
	local threshold = callbacks.threshold or 6
	local active = nil

	local function finish(input)
		if not active then
			return
		end
		local state = active
		active = nil
		for _, connection in ipairs(state.connections) do
			connection:Disconnect()
		end
		if callbacks.onEnd then
			callbacks.onEnd(input and Device.pointer(input) or state.last, state.moved)
		end
	end

	local began = handle.InputBegan:Connect(function(input)
		if active or not isPress(input) then
			return
		end
		local start = Device.pointer(input)
		if callbacks.onStart and callbacks.onStart(start) == false then
			return
		end
		local state = { start = start, last = start, moved = false, input = input, connections = {} }
		active = state
		local uis = Services.UserInputService
		table.insert(state.connections, uis.InputChanged:Connect(function(changed)
			if active ~= state or not isMove(changed) then
				return
			end
			if input.UserInputType == Enum.UserInputType.Touch and changed ~= input then
				return
			end
			local pointer = Device.pointer(changed)
			if not state.moved and (pointer - state.start).Magnitude < threshold then
				return
			end
			state.moved = true
			local delta = pointer - state.last
			state.last = pointer
			if callbacks.onMove then
				callbacks.onMove(pointer, delta, pointer - state.start)
			end
		end))
		table.insert(state.connections, uis.InputEnded:Connect(function(ended)
			if active ~= state then
				return
			end
			if ended == input or (input.UserInputType == Enum.UserInputType.MouseButton1 and ended.UserInputType == Enum.UserInputType.MouseButton1) then
				finish(ended)
			end
		end))
	end)
	if maid then
		maid:Add(began)
		maid:Add(function()
			finish(nil)
		end)
	end
	return began
end

-- Long press (touch): fires after `seconds` if the finger did not move.
function Drag.longPress(handle, seconds, callback, maid)
	local token = 0
	local began = handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		token += 1
		local mine = token
		local start = Device.pointer(input)
		local moved = false
		local changed
		changed = Services.UserInputService.InputChanged:Connect(function(c)
			if c == input and (Device.pointer(c) - start).Magnitude > 8 then
				moved = true
			end
		end)
		task.delay(seconds or 0.5, function()
			changed:Disconnect()
			if token == mine and not moved and input.UserInputState ~= Enum.UserInputState.End then
				callback()
			end
		end)
	end)
	local ended = handle.InputEnded:Connect(function()
		token += 1
	end)
	if maid then
		maid:Add(began)
		maid:Add(ended)
	end
end

-- Keep a rect inside the screen (below the Roblox top bar).
function Drag.clamp(position, size, margin)
	margin = margin or 8
	local vp = Device.viewport()
	local top = Device.inset() + margin
	local x = math.clamp(position.X, margin, math.max(margin, vp.X - size.X - margin))
	local y = math.clamp(position.Y, top, math.max(top, vp.Y - size.Y - margin))
	return Vector2.new(x, y)
end

return Drag
