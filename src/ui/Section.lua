-- Section: collapsible group of controls inside a tab (iOS grouped list).

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Maid = import("util/Maid")
local Util = import("util/Util")
local Registry = import("controls/Registry")

local New = Create.New
local C, S = Theme.c, Theme.s

local Section = {}
Section.__index = Section

function Section.new(tab, opts)
	opts = opts or {}
	if type(opts) ~= "table" then
		opts = { Title = opts }
	end
	local self = setmetatable({}, Section)
	local window = tab.Window
	self.Tab = tab
	self.Window = window
	self.Options = opts
	self.Maid = Maid.new()
	self.Controls = {}
	self.TitleSpec = opts.Title or opts.Name
	self.Collapsed = false
	self._order = 0

	self.Frame = self.Maid:Add(New("Frame", {
		Name = "Section",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = tab:_nextOrder(),
		Parent = tab.Page,
	}, { Create.list("Vertical", Theme.f(function(_, s)
		return UDim.new(0, s.touch and 6 or 8)
	end)) }))

	if self.TitleSpec then
		local header = New("TextButton", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			Parent = self.Frame,
		}, { Create.pad(0, 4), Create.list("Horizontal", 6, { valign = "Center" }) })
		self.Chevron = Icons.new("chevronDown", 14, C("textSubtle"))
		self.Chevron.Frame.Parent = header
		local label = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C("textSubtle"),
			TextSize = S("fontSection"),
			Weight = "SemiBold",
			LayoutOrder = 2,
			Parent = header,
		})
		window.Loc:Bind(label, "Text", function()
			return Util.upper(window.Loc:Get(self.TitleSpec))
		end)
		self.Hint = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C("textSubtle"),
			TextSize = S("fontSection"),
			Weight = "Medium",
			Visible = false,
			LayoutOrder = 3,
			Parent = header,
		})
		window.Loc:Bind(self.Hint, "Text", function()
			return "· " .. window.Loc:Lib("functions", { n = self:Count() })
		end)
		self.Header = header
		if opts.Collapsible ~= false then
			self.Maid:Add(header.Activated:Connect(function()
				self:SetCollapsed(not self.Collapsed)
			end))
		else
			self.Chevron.Frame.Visible = false
		end
	end

	self.Card = New("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C("surface"),
		LayoutOrder = 2,
		Parent = self.Frame,
	}, {
		Create.corner("rSection"),
		Create.stroke("border"),
		Create.list("Vertical", 0),
	})
	self.Card.Visible = false

	if opts.Collapsed then
		self:SetCollapsed(true, true)
	end
	return self
end

function Section:_nextOrder()
	self._order += 1
	return self._order
end

function Section:_add(control)
	table.insert(self.Controls, control)
	self:_updateDividers()
	self.Window:_controlAdded(control)
end

function Section:_remove(control)
	local index = table.find(self.Controls, control)
	if index then
		table.remove(self.Controls, index)
	end
	self:_updateDividers()
end

function Section:Count()
	local n = 0
	for _, control in ipairs(self.Controls) do
		if control.Flag then
			n += 1
		end
	end
	return n
end

-- Dividers between visible rows only (first visible row has none).
function Section:_updateDividers()
	local first = true
	local any = false
	for _, control in ipairs(self.Controls) do
		if control.Visible then
			any = true
			control.Divider.Visible = not first and not control._noDivider
			first = false
		end
	end
	self.Card.Visible = any and not self.Collapsed
	if self.Header then
		self.Header.Visible = any or #self.Controls == 0
	end
end

function Section:SetCollapsed(collapsed, instant)
	self.Collapsed = collapsed
	self:_updateDividers()
	if self.Hint then
		self.Hint.Visible = collapsed
		self.Window.Loc:Refresh()
	end
	if self.Chevron then
		local rotation = collapsed and -90 or 0
		if instant then
			self.Chevron.Frame.Rotation = rotation
		else
			Motion.tween(self.Chevron.Frame, { Rotation = rotation }, "spring")
		end
	end
	return self
end

function Section:SetTitle(spec)
	self.TitleSpec = spec
	self.Window.Loc:Refresh()
	return self
end

function Section:Clear()
	for _, control in ipairs(table.clone(self.Controls)) do
		control:Destroy()
	end
	return self
end

function Section:Destroy()
	self:Clear()
	self.Maid:Clean()
end

for kind, constructor in pairs(Registry) do
	Section[kind] = function(self, opts)
		return constructor(self, opts or {})
	end
end

return Section
