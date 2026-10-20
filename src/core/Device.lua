-- Device: decides the layout mode and reports screen geometry.
--   "pc"     — mouse/keyboard: sidebar on the left
--   "phone"  — touch, landscape (the usual Roblox phone case): 56 px icon rail
--   "tablet" — touch, portrait: iOS-style bottom tab bar

local Services = import("core/Services")
local Signal = import("util/Signal")

local Device = {
	Changed = Signal.new(),
	Override = nil,
}

function Device.viewport()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

function Device.isTouch()
	local uis = Services.UserInputService
	return uis.TouchEnabled and not uis.KeyboardEnabled and not uis.MouseEnabled
end

function Device.mode()
	if Device.Override then
		return Device.Override
	end
	if not Device.isTouch() then
		return "pc"
	end
	local vp = Device.viewport()
	if vp.X >= vp.Y then
		return "phone"
	end
	return "tablet"
end

-- Height of Roblox's top bar (GuiInset). Windows never go under it.
function Device.inset()
	local ok, topLeft = pcall(function()
		return Services.GuiService:GetGuiInset()
	end)
	if ok and typeof(topLeft) == "Vector2" then
		return math.max(topLeft.Y, 36)
	end
	return 36
end

-- Two coordinate spaces exist in a ScreenGui with IgnoreGuiInset = true:
--   "absolute" — AbsolutePosition and InputObject.Position (they agree)
--   "offset"   — UDim2 Position offsets of our top-level frames (0,0 = screen corner)
-- They can differ by the top-bar height, so never mix them: read the pointer
-- and AbsolutePosition in absolute space, and convert with toOffset() before
-- assigning a Position.
function Device.pointer(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

-- A full-screen layer frame at Position (0, 0); its AbsolutePosition is where
-- the screen's top-left corner is in absolute space.
Device.OriginLayer = nil

function Device.origin()
	local layer = Device.OriginLayer
	if layer and layer.Parent then
		local ok, position = pcall(function()
			return layer.AbsolutePosition
		end)
		if ok and typeof(position) == "Vector2" then
			return position
		end
	end
	return Vector2.zero
end

function Device.toOffset(absolute)
	return absolute - Device.origin()
end

function Device.toAbsolute(offset)
	return offset + Device.origin()
end

-- Position offsets of a top-level frame as a Vector2.
function Device.offsetOf(gui)
	return Vector2.new(gui.Position.X.Offset, gui.Position.Y.Offset)
end

local watching = false
function Device.watch()
	if watching then
		return
	end
	watching = true
	local last = Device.viewport()
	local pending = false
	local function check()
		local vp = Device.viewport()
		if vp ~= last then
			last = vp
			if not pending then
				pending = true
				task.delay(0.15, function()
					pending = false
					Device.Changed:Fire(Device.mode(), Device.viewport())
				end)
			end
		end
	end
	local function hook()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(check)
		end
	end
	hook()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
end

return Device
