-- Root: one ScreenGui per window with fixed layers instead of ZIndex wars
-- (brief, rule 3): 1 Windows · 2 Popups · 3 Notifications · 4 Modal.

local Create = import("core/Create")
local Compat = import("util/Compat")
local Services = import("core/Services")

local New = Create.New
local Root = {}
Root.__index = Root

local LAYERS = { "Windows", "Popups", "Notifications", "Modal" }

function Root.new(name)
	local self = setmetatable({}, Root)
	self.Gui = New("ScreenGui", {
		Name = name or ("Robly_" .. Services.HttpService:GenerateGUID(false):sub(1, 8)),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
	})
	for index, layer in ipairs(LAYERS) do
		self[layer] = New("Frame", {
			Name = layer,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = index,
			Parent = self.Gui,
		})
	end
	self._z = 1
	Compat.mountGui(self.Gui)
	return self
end

-- Next z-order inside the Windows layer: clicking a window raises it.
function Root:NextZ()
	self._z += 1
	return self._z
end

function Root:Destroy()
	self.Gui:Destroy()
end

return Root
