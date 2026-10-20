-- Section / Groupbox: a titled, collapsible card of compact rows.
-- Titled sections sit in the body's columns; the untitled default section
-- (controls added straight to a tab) is a full-width card on top.

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

function Section.new(body, opts)
	opts = opts or {}
	if type(opts) ~= "table" then
		opts = { Title = opts }
	end
	local self = setmetatable({}, Section)
	local window = body.Window
	self.Body = body
	self.Tab = body.Tab
	self.SubTab = body.SubTab
	self.Window = window
	self.Options = opts
	self.Maid = Maid.new()
	self.Controls = {}
	self.TitleSpec = opts.Title or opts.Name
	self.Full = opts.Full == true or (self.TitleSpec == nil and opts.Side == nil)
	self.Collapsed = false
	self.Destroyed = false
	self._order = 0

	local parent = body:_place(self, opts.Side)
	self.Frame = self.Maid:Add(New("Frame", {
		Name = self.TitleSpec and "Groupbox" or "Section",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C("surface"),
		BackgroundTransparency = Theme.glass(),
		LayoutOrder = body:_nextOrder(),
		Parent = parent,
	}, {
		Create.corner("rSection"),
		Create.stroke("border"),
		Create.list("Vertical", 0),
	}))

	if self.TitleSpec then
		local header = New("TextButton", {
			Name = "Header",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = self.Frame,
		}, {
			Create.pad(6, "padX"),
			Create.minSize(0, "groupHeader"),
			Create.list("Horizontal", 9, { valign = "Center" }),
		})
		if opts.Icon then
			-- icon in an accent-tinted tile
			local tile = New("Frame", {
				Name = "IconTile",
				Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = C("accent"),
				BackgroundTransparency = 0.85,
				LayoutOrder = 0,
				Parent = header,
			}, { Create.corner(7) })
			Icons.new(opts.Icon, 14, C("accent"), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
			}).Frame.Parent = tile
		end
		local texts = New("Frame", {
			Name = "Texts",
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = header,
		}, { Create.list("Vertical", 1), Create.flex() })
		local label = New("TextLabel", {
			Size = Theme.f(function(_, s)
				return UDim2.new(1, 0, 0, s.fontSection + 4)
			end),
			Weight = "Bold",
			TextSize = S("fontSection"),
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
			Parent = texts,
		})
		self.TitleLabel = label
		window.Loc:Bind(label, "Text", self.TitleSpec)
		if opts.Description then
			local desc = Create.text("", { size = "fontDesc", color = "textSubtle", wrap = true, order = 2, name = "Description" })
			desc.Parent = texts
			window.Loc:Bind(desc, "Text", opts.Description)
			self.DescLabel = desc
		end
		self.Hint = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			BackgroundColor3 = C("raised"),
			TextColor3 = C("textSubtle"),
			TextSize = S("fontDesc"),
			Visible = false,
			LayoutOrder = 2,
			Parent = header,
		}, { Create.corner("full"), Create.pad(0, 7) })
		self:_refreshHint()
		self.Chevron = Icons.new("chevronDown", 14, C("textSubtle"))
		self.Chevron.Frame.LayoutOrder = 3
		self.Chevron.Frame.Parent = header
		self.HeaderButton = header
		-- accent line under the header, fading out to the right
		self.HeaderLine = New("Frame", {
			Name = "HeaderLine",
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			LayoutOrder = 2,
			Parent = self.Frame,
		}, {
			New("UIGradient", {
				Color = Theme.gradient(),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.35),
					NumberSequenceKeypoint.new(0.6, 0.85),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		if opts.Collapsible ~= false then
			self.Maid:Add(header.Activated:Connect(function()
				self:SetCollapsed(not self.Collapsed)
			end))
		else
			self.Chevron.Frame.Visible = false
		end
	end

	-- rows
	self.Card = New("Frame", {
		Name = "Rows",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = self.Frame,
	}, {
		Create.list("Vertical", 0),
		Create.pad("groupPad", 0),
	})

	self:_updateDividers()
	if opts.Collapsed then
		self:SetCollapsed(true, true)
	end
	return self
end

function Section:_refreshHint()
	if self.Hint then
		self.Window.Loc:Bind(self.Hint, "Text", function()
			return self.Window.Loc:Lib("functions", { n = self:Count() })
		end)
	end
end

function Section:_nextOrder()
	self._order += 1
	return self._order
end

function Section:_add(control)
	table.insert(self.Controls, control)
	self:_updateDividers()
	self:_refreshHint()
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

-- Row dividers (only in the comfortable / touch density), and the whole card
-- hides when none of its rows are visible.
function Section:_updateDividers()
	local first = true
	local any = false
	local dividers = Theme.Sizes.dividers
	for _, control in ipairs(self.Controls) do
		if control.Visible then
			any = true
			control.Divider.Visible = dividers and not first and not control._noDivider
			first = false
		end
	end
	self.Card.Visible = any and not self.Collapsed
	if self.HeaderLine then
		self.HeaderLine.Visible = any and not self.Collapsed
	end
	self.Frame.Visible = any or (#self.Controls == 0 and self.TitleSpec ~= nil)
end

function Section:SetCollapsed(collapsed, instant)
	self.Collapsed = collapsed
	self:_updateDividers()
	if self.Hint then
		self.Hint.Visible = collapsed
		self:_refreshHint()
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
Section.Collapse = function(self)
	return self:SetCollapsed(true)
end
Section.Expand = function(self)
	return self:SetCollapsed(false)
end

function Section:IsCollapsed()
	return self.Collapsed
end

function Section:SetTitle(spec)
	self.TitleSpec = spec
	if self.TitleLabel then
		self.Window.Loc:Bind(self.TitleLabel, "Text", spec)
	end
	return self
end

-- Sub heading inside a groupbox: small caps caption that splits rows into groups.
function Section:Header(spec)
	local holder = New("Frame", {
		Name = "SubHeader",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self:_nextOrder(),
		Parent = self.Card,
	}, { Create.pad(8, "padX", 2, "padX"), Create.list("Horizontal", 8, { valign = "Center" }) })
	local label = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 14),
		TextColor3 = C("accent"),
		TextSize = 11,
		Weight = "Bold",
		LayoutOrder = 1,
		Parent = holder,
	})
	self.Window.Loc:Bind(label, "Text", function()
		return Util.upper(self.Window.Loc:Get(spec))
	end)
	New("Frame", {
		Size = UDim2.new(0, 0, 0, 1),
		BackgroundColor3 = C("divider"),
		LayoutOrder = 2,
		Parent = holder,
	}, { Create.flex() })
	self.Maid:Add(holder)
	return holder
end
Section.AddHeader = Section.Header
Section.CreateHeader = Section.Header
Section.SubHeader = Section.Header

function Section:SetVisible(visible)
	self.Frame.Visible = visible ~= false
	return self
end

function Section:Clear()
	for _, control in ipairs(table.clone(self.Controls)) do
		control:Destroy()
	end
	return self
end

function Section:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self:Clear()
	if self.Side and self.Body._sides[self.Side] then
		self.Body._sides[self.Side] -= 1
		self.Body:_layout()
	end
	self.Maid:Clean()
end

for kind, constructor in pairs(Registry) do
	local function add(self, opts)
		return constructor(self, opts or {})
	end
	Section[kind] = add
	Section["Create" .. kind] = add
	Section["Add" .. kind] = add
end

return Section
