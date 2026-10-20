-- Services: lazily resolved (and cloneref'd when available) Roblox services.

local Compat = import("util/Compat")

return setmetatable({}, {
	__index = function(self, name)
		local service = Compat.service(name)
		rawset(self, name, service)
		return service
	end,
})
