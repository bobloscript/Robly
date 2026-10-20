-- Tab: a page of sections. Any tab (except Settings) can be detached into its
-- own window and returned by the same gesture (brief §14).

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Maid = import("util/Maid")
local Signal = import("util/Signal")
local Util = import("util/Util")
local Section = import("ui/Section")
local Registry = import("controls/Registry")

local New = Create.New
local C, S = Theme.c, Theme.s

local Tab = {}
Tab.__index = Tab

function Tab.new(window, opts, internal)
	if type(opts) ~= "table" then
		opts = { Title = opts }
	end
	local self = setmetatable({}, Tab)
	self.Window = window
	self.Options = opts
	self.Maid = Maid.new()
	self.Sections = {}
	self.Internal = internal == true
	self.TitleSpec = opts.Title or opts.Name or "Tab"
	self.DescSpec = opts.Description
	self.Icon = opts.Icon or "dot"
	self.BadgeSpec = opts.Badge
	self.Detachable = opts.Detachable ~= false and not self.Internal
	self.DetachedWindow = nil
	self.DetachChanged = Signal.new()
	self._order = 0

	local idSource = type(self.TitleSpec) == "string" and self.TitleSpec
		or (type(self.TitleSpec) == "table" and (self.TitleSpec.en or self.TitleSpec[window.Loc.Default]))
		or tostring(#window.AllTabs + 1)
	self.Id = opts.Id or Util.sanitizeFileName(tostring(idSource)):gsub("%s", "_")

	self.Page = self.Maid:Add(New("ScrollingFrame", {
		Name = "Page_" .. self.Id,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = window.PageHost,
	}, { Create.list("Vertical", "sectionGap") }))
	self.Page.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar

	-- Page header (PC only: on touch the title lives in the window header)
	local header = New("Frame", {
		Name = "PageHeader",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = S("pageHeader"),
		LayoutOrder = 0,
		Parent = self.Page,
	}, { Create.list("Horizontal", 12) })
	Theme.bind(header, "Visible", S("pageHeader"))
	local texts = New("Frame", {
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = header,
	}, { Create.list("Vertical", 4), Create.flex() })
	local title = Create.text("", { weight = "Bold", size = "fontTitle", wrap = true, order = 1 })
	title.Parent = texts
	window.Loc:Bind(title, "Text", self.TitleSpec)
	self.TitleLabel = title
	if self.DescSpec then
		local desc = Create.text("", { color = "textMuted", wrap = true, order = 2 })
		Theme.bind(desc, "TextSize", Theme.f(function(_, s)
			return s.fontDesc + 1
		end))
		desc.Parent = texts
		window.Loc:Bind(desc, "Text", self.DescSpec)
	end
	if self.Detachable then
		local detach = New("TextButton", {
			Name = "Detach",
			Size = UDim2.fromOffset(32, 32),
			LayoutOrder = 2,
			Parent = header,
		}, { Create.corner(9), Create.stroke("borderStrong") })
		local icon = Icons.new("pip", 16, C("textMuted"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		icon.Frame.Parent = detach
		Motion.pressable(detach, nil, 0.92, self.Maid)
		window.Tooltip:Attach(detach, { __lib = "detach" }, self.Maid)
		self.Maid:Add(detach.Activated:Connect(function()
			self:Detach()
		end))
	end
	self.PageHeader = header
	self.Maid:Add(Create.pad(0, 0, 4, 0)).Parent = self.Page

	window:_addTab(self)
	return self
end

function Tab:_nextOrder()
	self._order += 1
	return self._order
end

function Tab:Section(opts)
	local section = Section.new(self, opts)
	table.insert(self.Sections, section)
	self._default = nil
	return section
end
Tab.AddSection = Tab.Section
Tab.CreateSection = Tab.Section

function Tab:_defaultSection()
	if not self._default then
		self._default = Section.new(self, {})
		table.insert(self.Sections, self._default)
	end
	return self._default
end

for kind in pairs(Registry) do
	Tab[kind] = function(self, opts)
		local section = self:_defaultSection()
		return section[kind](section, opts)
	end
end

function Tab:Select()
	self.Window:SelectTab(self)
	return self
end

function Tab:Title()
	return self.Window.Loc:Get(self.TitleSpec)
end

function Tab:SetTitle(spec)
	self.TitleSpec = spec
	self.Window.Loc:Bind(self.TitleLabel, "Text", spec)
	self.Window:_rebuildNav()
	return self
end

function Tab:SetBadge(spec)
	self.BadgeSpec = spec
	self.Window:_rebuildNav()
	return self
end

function Tab:IsDetached()
	return self.DetachedWindow ~= nil
end

function Tab:Detach(options)
	return self.Window:_detach(self, options)
end

function Tab:Attach()
	if self.DetachedWindow then
		self.DetachedWindow:Attach()
	end
	return self
end

function Tab:Count()
	local n = 0
	for _, section in ipairs(self.Sections) do
		n += section:Count()
	end
	return n
end

function Tab:Destroy()
	if self.DetachedWindow then
		self.DetachedWindow:Destroy(true)
	end
	for _, section in ipairs(self.Sections) do
		section:Destroy()
	end
	self.DetachChanged:DisconnectAll()
	self.Maid:Clean()
end

return Tab
