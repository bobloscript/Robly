-- Tab: a page of sections. Any tab (except Settings) can be detached into its
-- own window and returned by the same gesture (brief §14).

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Maid = import("util/Maid")
local Signal = import("util/Signal")
local Util = import("util/Util")
local Body = import("ui/Body")

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
	self.SubTabs = {}
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

	-- Sub tab pills (hidden until the first sub tab)
	self.SubBar = New("ScrollingFrame", {
		Name = "SubTabs",
		Size = Theme.f(function(_, s)
			return UDim2.new(1, 0, 0, s.segment + 6)
		end),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 0,
		Visible = false,
		LayoutOrder = 1,
		Parent = self.Page,
	})
	self.SubTrack = New("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C("sunken"),
		Parent = self.SubBar,
	}, { Create.corner("rSmall"), Create.pad(3), Create.list("Horizontal", 3, { valign = "Center" }) })

	self.Main = Body.new(self, self.Page, 2)

	window:_addTab(self)
	return self
end

function Tab:_body()
	return self.Main
end
Body.installApi(Tab)

function Tab:_bodies()
	local list = { self.Main }
	for _, sub in ipairs(self.SubTabs) do
		table.insert(list, sub.Body)
	end
	return list
end

-- Sub tabs ------------------------------------------------------------------------

local SubTab = {}
SubTab.__index = SubTab

function SubTab:_body()
	return self.Body
end
Body.installApi(SubTab)

function SubTab:Select()
	self.Tab:SelectSubTab(self)
	return self
end

function SubTab:SetTitle(spec)
	self.TitleSpec = spec
	self.Tab.Window.Loc:Bind(self.Label, "Text", spec)
	return self
end

-- tab:SubTab({ Title, Icon }) · tab:SubTab("PvP", "shield")
function Tab:SubTab(opts, icon)
	if type(opts) ~= "table" then
		opts = { Title = opts, Icon = icon }
	end
	local window = self.Window
	local sub = setmetatable({}, SubTab)
	sub.Tab = self
	sub.Window = window
	sub.TitleSpec = opts.Title or opts.Name or ("Page " .. (#self.SubTabs + 1))
	sub.Icon = opts.Icon
	sub.Body = Body.new(self, self.Page, 10 + #self.SubTabs, sub)
	sub.Body.Frame.Visible = false
	table.insert(self.SubTabs, sub)

	local button = New("TextButton", {
		Name = "SubTab",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = Theme.sz(0, 0, 0, "segment"),
		BackgroundColor3 = C("segment"),
		BackgroundTransparency = 1,
		LayoutOrder = #self.SubTabs,
		Parent = self.SubTrack,
	}, { Create.corner(Theme.f(function(_, s)
		return UDim.new(0, s.rSmall - 2)
	end)), Create.pad(0, 12), Create.list("Horizontal", 6, { valign = "Center" }) })
	if sub.Icon then
		sub.IconObject = Icons.new(sub.Icon, "iconSmall", C("textMuted"))
		sub.IconObject.Frame.Parent = button
	end
	local label = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C("textMuted"),
		Weight = "Medium",
		LayoutOrder = 2,
		Parent = button,
	})
	Theme.bind(label, "TextSize", Theme.f(function(_, s)
		return s.font - 1
	end))
	window.Loc:Bind(label, "Text", sub.TitleSpec)
	sub.Button, sub.Label = button, label
	Motion.pressable(button, nil, 0.96, self.Maid)
	self.Maid:Add(button.Activated:Connect(function()
		self:SelectSubTab(sub)
	end))
	self.SubBar.Visible = true
	-- tab-level controls stay on top; an empty main body takes no space
	self.Main.Frame.Visible = not self.Main:IsEmpty()
	if not self.CurrentSubTab then
		self:SelectSubTab(sub)
	end
	return sub
end
Tab.AddSubTab = Tab.SubTab
Tab.CreateSubTab = Tab.SubTab

function Tab:SelectSubTab(which)
	local target = which
	if type(which) ~= "table" then
		for index, sub in ipairs(self.SubTabs) do
			if index == which or sub.TitleSpec == which or self.Window.Loc:Get(sub.TitleSpec) == which then
				target = sub
			end
		end
	end
	if type(target) ~= "table" then
		return
	end
	local previous = self.CurrentSubTab
	self.CurrentSubTab = target
	for _, sub in ipairs(self.SubTabs) do
		local on = sub == target
		sub.Body.Frame.Visible = on
		Motion.tween(sub.Button, { BackgroundTransparency = on and 0 or 1 }, "fade")
		Theme.set(sub.Label, "TextColor3", on and C("text") or C("textMuted"))
		sub.Label.FontFace = Theme.font(on and "SemiBold" or "Medium")
		if sub.IconObject then
			sub.IconObject:SetColor(on and C("accent") or C("textMuted"), true)
		end
	end
	local _ = previous
	self.Main.Frame.Visible = not self.Main:IsEmpty()
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
	for _, body in ipairs(self:_bodies()) do
		n += body:Count()
	end
	return n
end

function Tab:Destroy()
	if self.DetachedWindow then
		self.DetachedWindow:Destroy(true)
	end
	for _, body in ipairs(self:_bodies()) do
		body:Destroy()
	end
	self.DetachChanged:DisconnectAll()
	self.Maid:Clean()
end

return Tab
