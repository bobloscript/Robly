-- Body: the content of a tab or a sub tab.
--   Top      — full-width cards: controls added straight to the tab/sub tab
--   Columns  — groupboxes in two columns (Left / Right / balanced); they stack
--              into one column on narrow windows and on touch devices
-- (Airflow / Obsidian-style layout.)

local Theme = import("core/Theme")
local Create = import("core/Create")
local Maid = import("util/Maid")
local Registry = import("controls/Registry")

local New = Create.New

local Body = {}
Body.__index = Body

-- Single column below this content width (px).
local TWO_COLUMNS_MIN = 560

function Body.new(tab, parent, order, subTab)
	local self = setmetatable({}, Body)
	self.Tab = tab
	self.Window = tab.Window
	self.SubTab = subTab
	self.Maid = Maid.new()
	self.Sections = {}
	self._order = 0
	self._sides = { Left = 0, Right = 0 }

	self.Frame = self.Maid:Add(New("Frame", {
		Name = subTab and "SubBody" or "Body",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	}, { Create.list("Vertical", "sectionGap") }))
	self.Top = New("Frame", {
		Name = "Top",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = self.Frame,
	}, { Create.list("Vertical", "sectionGap") })
	self.Columns = New("Frame", {
		Name = "Columns",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = self.Frame,
	})
	self.ColumnLayout = Create.list("Horizontal", "columnGap", { valign = "Top" })
	self.ColumnLayout.Parent = self.Columns
	local function column(name, order2)
		return New("Frame", {
			Name = name,
			Size = UDim2.fromScale(0.5, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order2,
			Parent = self.Columns,
		}, { Create.list("Vertical", "sectionGap") })
	end
	self.Left = column("Left", 1)
	self.Right = column("Right", 2)
	self.Maid:Add(self.Columns:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
	end))
	self.Maid:Add(Theme.Changed:Connect(function(what)
		if what ~= "colors" then
			self:_layout()
			for _, section in ipairs(self.Sections) do
				if not section.Destroyed then
					section:_updateDividers()
				end
			end
		end
	end))
	self:_layout()
	return self
end

function Body:_nextOrder()
	self._order += 1
	return self._order
end

-- Where a section goes: untitled "default" sections are full width on top,
-- groupboxes go to a column (explicit Side, else the one with fewer boxes).
function Body:_place(section, side)
	if section.Full then
		return self.Top
	end
	if side == 1 or side == "Left" or side == "left" then
		side = "Left"
	elseif side == 2 or side == "Right" or side == "right" then
		side = "Right"
	else
		side = self._sides.Left <= self._sides.Right and "Left" or "Right"
	end
	self._sides[side] += 1
	section.Side = side
	task.defer(function()
		self:_layout()
	end)
	return self[side]
end

function Body:_layout()
	local width = self.Columns.AbsoluteSize.X
	local gap = Theme.Sizes.columnGap or 10
	local hasLeft = self._sides.Left > 0
	local hasRight = self._sides.Right > 0
	local two = hasLeft and hasRight and not Theme.Sizes.touch and (width <= 0 or width >= TWO_COLUMNS_MIN)
	self.Columns.Visible = hasLeft or hasRight
	if two then
		self.ColumnLayout.FillDirection = Enum.FillDirection.Horizontal
		self.Left.Size = UDim2.new(0.5, -math.floor(gap / 2), 0, 0)
		self.Right.Size = UDim2.new(0.5, -math.ceil(gap / 2), 0, 0)
	else
		self.ColumnLayout.FillDirection = Enum.FillDirection.Vertical
		self.Left.Size = UDim2.fromScale(1, 0)
		self.Right.Size = UDim2.fromScale(1, 0)
	end
	self.Left.Visible = hasLeft
	self.Right.Visible = hasRight
end

function Body:_newSection(opts)
	local Section = import("ui/Section")
	if type(opts) ~= "table" then
		opts = { Title = opts }
	end
	local section = Section.new(self, opts)
	table.insert(self.Sections, section)
	if not self.SubTab then
		self.Frame.Visible = true
	end
	return section
end

function Body:_defaultSection()
	if not self._default or self._default.Destroyed then
		local Section = import("ui/Section")
		self._default = Section.new(self, { Full = true })
		table.insert(self.Sections, self._default)
		if not self.SubTab then
			self.Frame.Visible = true
		end
	end
	return self._default
end

function Body:Count()
	local n = 0
	for _, section in ipairs(self.Sections) do
		n += section:Count()
	end
	return n
end

function Body:IsEmpty()
	return #self.Sections == 0
end

function Body:Destroy()
	for _, section in ipairs(self.Sections) do
		section:Destroy()
	end
	self.Maid:Clean()
end

-- Shared API for Tab, SubTab and Body: sections, groupboxes and controls ------

local function sectionWith(side)
	return function(self, opts, icon)
		if type(opts) ~= "table" then
			opts = { Title = opts, Icon = icon }
		end
		if side then
			opts = table.clone(opts)
			opts.Side = side
		end
		return self:_body():_newSection(opts)
	end
end

function Body.installApi(class)
	class.Section = sectionWith(nil)
	class.AddSection = class.Section
	class.CreateSection = class.Section
	class.Groupbox = class.Section
	class.AddGroupbox = class.Section
	class.CreateGroupbox = class.Section
	class.AddLeftGroupbox = sectionWith("Left")
	class.AddRightGroupbox = sectionWith("Right")
	for kind in pairs(Registry) do
		local function add(self, opts)
			local section = self:_body():_defaultSection()
			return section[kind](section, opts)
		end
		class[kind] = add
		class["Create" .. kind] = add
		class["Add" .. kind] = add
	end
end

function Body:_body()
	return self
end
Body.installApi(Body)

return Body
