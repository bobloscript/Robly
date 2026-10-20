-- Window: the shell. One code path, three layouts chosen by size tokens:
--   pc     — header 56 · sidebar 200 · content          (drag, resize, pill)
--   phone  — 56 px icon rail · header 44 · content       (landscape, "More" menu)
--   tablet — header 52 · content · bottom tab bar 60     (portrait)
-- Layout only through UIListLayout / UIFlexItem / UIPadding (brief, rule 2).

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Device = import("core/Device")
local Drag = import("core/Drag")
local Root = import("core/Root")
local Popup = import("core/Popup")
local Store = import("core/Store")
local Localization = import("core/Localization")
local Services = import("core/Services")
local Maid = import("util/Maid")
local Signal = import("util/Signal")
local Util = import("util/Util")
local Compat = import("util/Compat")
local Notifications = import("ui/Notifications")
local Dialog = import("ui/Dialog")
local Tooltip = import("ui/Tooltip")
local Search = import("ui/Search")
local Pill = import("ui/Pill")
local Tab = import("ui/Tab")
local Detached = import("ui/Detached")
local Effects = import("ui/Effects")
local Binds = import("system/Binds")
local Config = import("system/Config")

local New = Create.New
local C, S = Theme.c, Theme.s
local L = Localization.L

local Window = {}
Window.__index = Window

local counter = 0

function Window.new(library, opts)
	opts = opts or {}
	counter += 1
	local self = setmetatable({}, Window)
	self.Id = counter
	self.Library = library
	self.Options = opts
	self.Maid = Maid.new()
	self.TitleSpec = opts.Title or opts.Name or "Robly"
	self.SubtitleSpec = opts.Subtitle
	self.LogoSpec = opts.Logo
	self.Branding = opts.Branding ~= false
	self.Tabs = {}
	self.AllTabs = {}
	self.Quick = {}
	self._flags = {}
	self.Minimized = false
	self.Destroyed = false
	self.OnDestroy = Signal.new()
	self.VisibilityChanged = Signal.new()
	self.TabChanged = Signal.new()

	Device.Override = opts.Device
	Theme.setMode(Device.mode())
	self.Mode = Theme.Mode

	self.Store = Store.new()
	self.Loc = Localization.new(opts.Language, opts.Dev)
	self.Root = self.Maid:Add(Root.new(opts.GuiName))
	self.Popup = Popup.new(self)
	self.Tooltip = Tooltip.new(self)
	self.Dialogs = Dialog.new(self)
	self.Notifier = Notifications.new(self)
	self.Search = Search.new(self)
	self.Binds = Binds.new(self)
	self.Config = Config.new(self)
	self.Config:ApplyInterface()

	-- Public live view of all values: Window.Flags.autoFarm
	local store = self.Store
	self.Flags = setmetatable({}, {
		__index = function(_, flag)
			return store:Get(flag)
		end,
		__newindex = function(_, flag, value)
			store:Set(flag, value, "api")
		end,
	})

	self:_build()

	local SettingsTab = import("system/SettingsTab")
	local KeybindHud = import("system/KeybindHud")
	local QuickButtons = import("system/QuickButtons")
	self.SettingsTab = SettingsTab.new(self)
	self.Hud = KeybindHud.new(self)
	self.QuickButtons = QuickButtons.new(self)

	Device.watch()
	self.Maid:Add(Device.Changed:Connect(function(mode)
		self:_onDevice(mode)
	end))
	self.Maid:Add(Theme.Changed:Connect(function(what)
		if what == "density" and not self.Destroyed then
			self:_applyLayout()
			self:_fitHeader()
		end
	end))
	self.Maid:Add(self.Loc.Changed:Connect(function()
		self:_rebuildNav()
		self:_buildHeader()
	end))
	self.Maid:Add(store.Changed:Connect(function(_, value)
		if type(value) == "boolean" then
			self:_updatePillDot()
		end
	end))
	self.Maid:Add(Services.UserInputService.InputBegan:Connect(function(input, processed)
		self:_shortcut(input, processed)
	end))

	task.defer(function()
		if not self.Destroyed then
			self:_afterBuild()
		end
	end)
	return self
end

-- Build ------------------------------------------------------------------------------

function Window:_logo(size, round)
	local spec = self.LogoSpec
	local frame = New("Frame", {
		Name = "Logo",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C("accent"),
	}, { round and Create.corner("full") or Create.corner(math.floor(size * 0.29)) })
	if type(spec) == "string" and (Icons.has(spec) and #spec > 1) then
		local icon = Icons.new(spec, math.floor(size * 0.6), C("accentInk"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		icon.Frame.Parent = frame
	else
		local letter = type(spec) == "string" and spec or Util.upper(self.Loc:Get(self.TitleSpec)):sub(1, 1)
		New("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			Text = letter,
			TextColor3 = C("accentInk"),
			TextSize = math.floor(size * 0.54),
			Weight = "Bold",
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = frame,
		}).TextXAlignment = Enum.TextXAlignment.Center
	end
	return frame
end

function Window:_build()
	local root = self.Root
	self.Frame = self.Maid:Add(New("Frame", {
		Name = "Window",
		BackgroundColor3 = C("bg"),
		ClipsDescendants = true,
		Active = true,
		ZIndex = root:NextZ(),
		Parent = root.Windows,
	}, {
		Create.corner("rWindow"),
		Create.stroke("border"),
	}))
	self.Scale = New("UIScale", { Parent = self.Frame })
	-- Everything laid out lives in Shell; the resize grip floats in Frame and
	-- must not be part of the list layout.
	self.Effects = self.Maid:Add(Effects.new(self.Frame, 0))
	self.Shell = New("Frame", { Name = "Shell", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = self.Frame })
	self.Header = New("Frame", { Name = "Header", Parent = self.Shell })
	-- transparent button under the header content: the drag handle (Frames
	-- don't receive input reliably, buttons do)
	self.DragHandle = New("TextButton", { Name = "DragHandle", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = self.Header })
	self.Nav = New("Frame", { Name = "Nav", Parent = self.Shell })
	self.Main = New("Frame", { Name = "Main", Parent = self.Shell }, {
		Create.pad("contentTop", "contentX", "contentBottom", "contentX"),
	})
	self.PageHost = New("Frame", { Name = "Pages", Size = UDim2.fromScale(1, 1), Parent = self.Main })
	self.Search:BuildOverlay(self.Main)

	self.Maid:Add(self.Frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.Frame.ZIndex = root:NextZ()
		end
	end))

	-- Move by header (not when pressing inside the search field)
	Drag.attach(self.DragHandle, {
		onStart = function(pointer)
			self.Frame.ZIndex = root:NextZ()
			self._dragStart = Device.offsetOf(self.Frame)
			local field = self.SearchField
			if field and field.Parent and Theme.Mode == "pc" then
				local p, s = field.AbsolutePosition, field.AbsoluteSize
				if pointer.X >= p.X and pointer.X <= p.X + s.X and pointer.Y >= p.Y and pointer.Y <= p.Y + s.Y then
					return false
				end
			end
			return true
		end,
		onMove = function(_, _, total)
			-- move from where the drag started: no drift, no lost movement
			local p = Drag.clamp(self._dragStart + total, self.Frame.AbsoluteSize, 0)
			self.Frame.Position = UDim2.fromOffset(p.X, p.Y)
		end,
		onEnd = function(_, moved)
			if moved then
				self:_saveRect()
			end
		end,
	}, self.Maid)

	-- Resize grip (PC)
	local grip = New("TextButton", {
		Name = "Resize",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -3, 1, -3),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 30,
		Parent = self.Frame,
	})
	Theme.bind(grip, "Visible", Theme.f(function(_, s)
		return not s.touch
	end))
	Icons.new("grip", 14, C("textSubtle")).Frame.Parent = grip
	local startSize
	Drag.attach(grip, {
		threshold = 1,
		onStart = function()
			startSize = self.Frame.AbsoluteSize
		end,
		onMove = function(_, _, total)
			local vp = Device.viewport()
			local pos = Device.offsetOf(self.Frame)
			local w = math.clamp(startSize.X + total.X, 520, math.max(520, vp.X - pos.X - 4))
			local h = math.clamp(startSize.Y + total.Y, 340, math.max(340, vp.Y - pos.Y - 4))
			self.Frame.Size = UDim2.fromOffset(w, h)
			self:_fitHeader()
		end,
		onEnd = function()
			self:_saveRect()
		end,
	}, self.Maid)

	self.Pill = self.Maid:Add(Pill.new(self, {
		title = self.TitleSpec,
		logo = function(size)
			return self:_logo(size, true)
		end,
		onRestore = function()
			self:Restore()
		end,
		onMoved = function(position)
			self.Config:SetMeta("pill", { x = position.X, y = position.Y })
		end,
		position = self.Config:GetMeta("pill") and Vector2.new(self.Config:GetMeta("pill").x, self.Config:GetMeta("pill").y) or nil,
	}))

	self:_applyLayout()
	self:_placeWindow(true)
end

-- Arrange header / nav / main for the current mode.
function Window:_applyLayout()
	local mode = Theme.Mode
	local frame = self.Shell
	local header, nav, main = self.Header, self.Nav, self.Main
	-- move the persistent parts out before the old containers are destroyed
	for _, part in ipairs({ header, nav, main }) do
		part.Parent = frame
	end
	if self._layoutMaid then
		self._layoutMaid:Clean()
	end
	local maid = Maid.new()
	self._layoutMaid = maid
	for _, child in ipairs(nav:GetChildren()) do
		child:Destroy()
	end

	local radius = Theme.Sizes.rWindow
	-- sidebar background: only its outer corners are round; translucent with Glass
	local function navPanel(round)
		Create.panel(nav, { color = C("nav"), transparency = Theme.glass(0.45), radius = radius, round = round })
	end
	if mode == "pc" then
		maid:Add(Create.list("Vertical", 0)).Parent = frame
		header.LayoutOrder = 1
		header.Size = Theme.resolve(Theme.sz(1, 0, 0, "header"))
		local body = maid:Add(New("Frame", { Name = "Body", Size = UDim2.fromScale(1, 0), LayoutOrder = 2, Parent = frame }, {
			Create.flex(),
			Create.list("Horizontal", 0),
		}))
		nav.Parent = body
		nav.Size = UDim2.new(0, Theme.Sizes.sidebar, 1, 0)
		nav.LayoutOrder = 1
		main.Parent = body
		main.Size = UDim2.fromScale(0, 1)
		main.LayoutOrder = 2
		Create.flex().Parent = main
		navPanel({ bl = true })
		New("Frame", { Name = "Edge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = C("divider"), ZIndex = 3, Parent = nav })
		New("Frame", { Name = "Edge", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C("divider"), ZIndex = 3, Parent = header })
	elseif mode == "phone" then
		maid:Add(Create.list("Horizontal", 0)).Parent = frame
		nav.LayoutOrder = 1
		nav.Size = UDim2.new(0, Theme.Sizes.rail, 1, 0)
		local column = maid:Add(New("Frame", { Name = "Column", Size = UDim2.fromScale(0, 1), LayoutOrder = 2, Parent = frame }, {
			Create.flex(),
			Create.list("Vertical", 0),
		}))
		header.Parent = column
		header.LayoutOrder = 1
		header.Size = UDim2.new(1, 0, 0, Theme.Sizes.header)
		main.Parent = column
		main.LayoutOrder = 2
		main.Size = UDim2.fromScale(1, 0)
		Create.flex().Parent = main
		navPanel({ tl = true, bl = true })
		New("Frame", { Name = "Edge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = C("divider"), ZIndex = 3, Parent = nav })
	else
		maid:Add(Create.list("Vertical", 0)).Parent = frame
		header.LayoutOrder = 1
		header.Size = UDim2.new(1, 0, 0, Theme.Sizes.header)
		main.LayoutOrder = 2
		main.Size = UDim2.fromScale(1, 0)
		Create.flex().Parent = main
		nav.LayoutOrder = 3
		nav.Size = UDim2.new(1, 0, 0, Theme.Sizes.tabbar)
		navPanel({ bl = true, br = true })
		New("Frame", { Name = "Edge", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C("divider"), ZIndex = 3, Parent = nav })
	end
	maid:Add(function()
		for _, item in ipairs(main:GetChildren()) do
			if item:IsA("UIFlexItem") then
				item:Destroy()
			end
		end
		for _, item in ipairs(header:GetChildren()) do
			if item.Name == "Edge" then
				item:Destroy()
			end
		end
	end)
	self:_buildHeader()
	self:_rebuildNav()
end

-- Header -------------------------------------------------------------------------------

local function iconButton(window, maid, icon, order, tip, callback, size)
	local button = New("TextButton", {
		Size = Theme.f(function(_, s)
			local n = size or s.hit
			return UDim2.fromOffset(n, n)
		end),
		BackgroundColor3 = C("raised"),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, { Create.corner(9) })
	local glyph = Icons.new(icon, Theme.Sizes.touch and 20 or 18, Theme.Sizes.touch and C("text") or C("textMuted"), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	glyph.Frame.Parent = button
	Motion.pressable(button, glyph.Frame, 0.85, maid)
	maid:Add(button.MouseEnter:Connect(function()
		Motion.tween(button, { BackgroundTransparency = 0 }, "fade")
	end))
	maid:Add(button.MouseLeave:Connect(function()
		Motion.tween(button, { BackgroundTransparency = 1 }, "fade")
	end))
	if tip then
		window.Tooltip:Attach(button, tip, maid)
	end
	maid:Add(button.Activated:Connect(callback))
	return button, glyph
end

function Window:_languageButton(maid, order)
	local loc = self.Loc
	local touch = Theme.Sizes.touch
	local button = New("TextButton", {
		Name = "Language",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, touch and 44 or 34),
		BackgroundColor3 = C("overlay"),
		BackgroundTransparency = touch and 1 or 0,
		LayoutOrder = order,
	}, {
		Create.corner(10),
		Create.pad(0, touch and 8 or 7, 0, touch and 8 or 9),
		Create.list("Horizontal", 6, { valign = "Center" }),
	})
	if not touch then
		Create.stroke("borderStrong").Parent = button
	end
	Icons.new("globe", 16, C("textMuted")).Frame.Parent = button
	New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Text = loc.Current:upper(),
		Weight = "SemiBold",
		TextSize = touch and 13 or 12.5,
		LayoutOrder = 2,
		Parent = button,
	})
	if not touch then
		local chevron = Icons.new("chevronDown", 14, C("textMuted"))
		chevron.Frame.LayoutOrder = 3
		chevron.Frame.Parent = button
	end
	Motion.pressable(button, nil, 0.95, maid)
	maid:Add(button.Activated:Connect(function()
		self:OpenLanguageMenu(button)
	end))
	return button
end

function Window:OpenLanguageMenu(anchor)
	local items = {}
	for _, language in ipairs(self.Loc:Languages()) do
		table.insert(items, {
			Text = language.Name,
			Checked = language.Code == self.Loc.Current,
			Callback = function()
				self:SetLanguage(language.Code)
			end,
		})
	end
	self.Popup:Menu(anchor or self.Header, items, { width = 200 })
end

function Window:_buildHeader()
	if self._headerMaid then
		self._headerMaid:Clean()
	end
	local maid = Maid.new()
	self._headerMaid = maid
	local header = self.Header
	local mode = Theme.Mode
	local loc = self.Loc

	local row = maid:Add(New("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = header,
	}, {
		Create.list("Horizontal", mode == "pc" and 12 or 4, { valign = "Center" }),
	}))
	local pad = Create.pad(0, mode == "pc" and 10 or 4, 0, mode == "phone" and 14 or 16)
	pad.Parent = row
	self.HeaderRow = row

	if mode ~= "phone" then
		local logo = self:_logo(28)
		logo.LayoutOrder = 1
		logo.Parent = row
	end

	self.HeaderTitle = nil
	if mode == "pc" then
		local texts = New("Frame", {
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 2,
			Parent = row,
		}, { Create.list("Vertical", 1, { valign = "Center" }), Create.flex() })
		local title = New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			Weight = "SemiBold",
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = texts,
		})
		loc:Bind(title, "Text", self.TitleSpec)
		if self.SubtitleSpec then
			local subtitle = New("TextLabel", {
				Size = UDim2.new(1, 0, 0, 15),
				TextColor3 = C("textSubtle"),
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
				Parent = texts,
			})
			loc:Bind(subtitle, "Text", self.SubtitleSpec)
		end
	else
		local title = New("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			Weight = "Bold",
			TextSize = S("fontTitle"),
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 2,
			Parent = row,
		}, { Create.flex() })
		self.HeaderTitle = title
		if self.Selected then
			loc:Bind(title, "Text", self.Selected.TitleSpec)
		end
	end

	if loc:IsMultilingual() and mode ~= "phone" or (mode == "phone" and loc:IsMultilingual()) then
		self:_languageButton(maid, 3).Parent = row
	end

	if mode == "pc" then
		local search = New("Frame", {
			Name = "Search",
			Size = UDim2.fromOffset(280, 32),
			BackgroundColor3 = C("overlay"),
			LayoutOrder = 4,
			Parent = row,
		}, {
			Create.corner(10),
			Create.stroke("borderStrong"),
			Create.pad(0, 6, 0, 10),
			Create.list("Horizontal", 8, { valign = "Center" }),
		})
		self.SearchField = search
		Icons.new("search", 16, C("textSubtle")).Frame.Parent = search
		local box = New("TextBox", {
			Size = UDim2.fromScale(0, 1),
			TextSize = 13,
			LayoutOrder = 2,
			Parent = search,
		}, { Create.flex() })
		loc:Bind(box, "PlaceholderText", L("search"))
		self.SearchBox = box
		New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = C("raised"),
			Text = "Ctrl K",
			TextColor3 = C("textMuted"),
			TextSize = 11,
			Weight = "Medium",
			LayoutOrder = 3,
			Parent = search,
		}, { Create.corner(6), Create.pad(3, 6) })
		maid:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
			-- Ctrl+K focuses the box; drop the "k" that the shortcut itself types
			if self._swallowKey and os.clock() - self._swallowKey < 0.3 and box.Text:lower() == "k" then
				self._swallowKey = nil
				box.Text = ""
				return
			end
			self.Search:SetQuery(box.Text)
		end))
		maid:Add(box.FocusLost:Connect(function(enter)
			if enter then
				local first = self.Search:Find(box.Text)[1]
				if first then
					self:Reveal(first)
				end
			end
		end))
		local buttons = New("Frame", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 5,
			Parent = row,
		}, { Create.list("Horizontal", 2, { valign = "Center" }) })
		iconButton(self, maid, "minus", 1, L("minimize"), function()
			self:Minimize()
		end).Parent = buttons
		iconButton(self, maid, "close", 2, L("close"), function()
			self:Close()
		end).Parent = buttons
		self:_fitHeader()
	else
		iconButton(self, maid, "search", 4, nil, function()
			self:_openTouchSearch()
		end).Parent = row
		if self.Selected and self.Selected.Detachable then
			iconButton(self, maid, "pip", 5, nil, function()
				if self.Selected then
					self.Selected:Detach()
				end
			end).Parent = row
		end
		iconButton(self, maid, "minus", 6, nil, function()
			self:Minimize()
		end).Parent = row
	end

	-- Touch search bar (covers the header row while searching)
	if mode ~= "pc" then
		local bar = maid:Add(New("Frame", {
			Name = "SearchBar",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C("bg"),
			Visible = false,
			ZIndex = 5,
			Parent = header,
		}, {
			Create.pad(0, 4, 0, 12),
			Create.list("Horizontal", 8, { valign = "Center" }),
		}))
		local field = New("Frame", {
			Size = UDim2.new(0, 0, 0, 36),
			BackgroundColor3 = C("overlay"),
			ZIndex = 5,
			Parent = bar,
		}, { Create.corner(10), Create.pad(0, 10), Create.list("Horizontal", 8, { valign = "Center" }), Create.flex() })
		Icons.new("search", 16, C("textSubtle")).Frame.Parent = field
		local box = New("TextBox", {
			Size = UDim2.fromScale(0, 1),
			ZIndex = 5,
			LayoutOrder = 2,
			Parent = field,
		}, { Create.flex() })
		loc:Bind(box, "PlaceholderText", L("search"))
		local cancel = New("TextButton", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C("accent"),
			Weight = "SemiBold",
			ZIndex = 5,
			LayoutOrder = 3,
			Parent = bar,
		}, { Create.pad(0, 8) })
		loc:Bind(cancel, "Text", L("cancel"))
		maid:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
			self.Search:SetQuery(box.Text)
		end))
		maid:Add(cancel.Activated:Connect(function()
			self:_closeTouchSearch()
		end))
		self.SearchBar = bar
		self.SearchBox = box
	else
		self.SearchBar = nil
	end
end

function Window:_fitHeader()
	if Theme.Mode ~= "pc" or not self.SearchField then
		return
	end
	local width = self.Frame.AbsoluteSize.X
	if width <= 0 then
		width = self._targetSize and self._targetSize.X or 860
	end
	self.SearchField.Size = UDim2.fromOffset(width < 640 and 150 or (width < 760 and 210 or 260), Theme.Sizes.hit)
end

function Window:_openTouchSearch()
	if not self.SearchBar then
		return
	end
	self.SearchBar.Visible = true
	self.SearchBox.Text = ""
	self.SearchBox:CaptureFocus()
end

function Window:_closeTouchSearch()
	if self.SearchBar then
		self.SearchBar.Visible = false
		self.SearchBox.Text = ""
		self.SearchBox:ReleaseFocus()
	end
	self.Search:Clear()
end

function Window:FocusSearch()
	if Theme.Mode == "pc" and self.SearchBox then
		if self.Minimized then
			self:Restore()
		end
		self._swallowKey = os.clock()
		self.SearchBox:CaptureFocus()
	else
		self:_openTouchSearch()
	end
end

-- Navigation ----------------------------------------------------------------------------

function Window:_navTabs()
	local list = {}
	for _, tab in ipairs(self.Tabs) do
		table.insert(list, tab)
	end
	return list
end

function Window:_rebuildNav()
	if not self.Nav then
		return
	end
	if self._navMaid then
		self._navMaid:Clean()
	end
	local maid = Maid.new()
	self._navMaid = maid
	self._navItems = {}
	self._moreButton = nil
	local mode = Theme.Mode
	if mode == "pc" then
		self:_buildSidebar(maid)
	elseif mode == "phone" then
		self:_buildRail(maid)
	else
		self:_buildTabbar(maid)
	end
	self:_updateNavSelection(true)
end

function Window:_navVisual(tab, item)
	local selected = self.Selected == tab
	local highlighted = self._highlightTab == tab
	local mode = Theme.Mode
	if mode == "pc" then
		Theme.set(item.button, "BackgroundColor3", highlighted and C("accent") or C("selected"))
		Motion.tween(item.button, { BackgroundTransparency = highlighted and 0.82 or (selected and 0.35 or 1) }, "fade")
		item.icon:SetColor(selected and C("accent") or C("textMuted"), true)
		Theme.set(item.label, "TextColor3", selected and C("text") or C("textMuted"))
		item.label.FontFace = Theme.font(selected and "SemiBold" or "Medium")
		if item.tile then
			Motion.tween(item.tile, { BackgroundTransparency = selected and 0.84 or 1 }, "fade")
		end
		if item.bar then
			item.bar.Visible = selected
			if selected then
				item.bar.Size = UDim2.fromOffset(3, 4)
				Motion.tween(item.bar, { Size = UDim2.fromOffset(3, 18) }, "spring")
			end
		end
	elseif mode == "phone" then
		Theme.set(item.button, "BackgroundColor3", C("accent"))
		Motion.tween(item.button, { BackgroundTransparency = (selected or highlighted) and 0.84 or 1 }, "fade")
		item.icon:SetColor(selected and C("accent") or C("textSubtle"), true)
	else
		item.icon:SetColor(selected and C("accent") or C("textSubtle"), true)
		Theme.set(item.label, "TextColor3", selected and C("accent") or C("textSubtle"))
		item.label.FontFace = Theme.font(selected and "SemiBold" or "Medium")
	end
	if item.pip then
		item.pip.Frame.Visible = tab.DetachedWindow ~= nil
	end
end

function Window:_updateNavSelection()
	for tab, item in pairs(self._navItems or {}) do
		self:_navVisual(tab, item)
	end
	if self._moreButton then
		local inMore = self.Selected and not self._navItems[self.Selected]
		self._moreButton.icon:SetColor(inMore and C("accent") or C("textSubtle"), true)
		if self._moreButton.label then
			Theme.set(self._moreButton.label, "TextColor3", inMore and C("accent") or C("textSubtle"))
		end
	end
end

function Window:_attachNavGestures(tab, button, maid)
	if not tab.Detachable then
		return
	end
	if Theme.Mode == "pc" then
		-- drag a tab out of the sidebar to detach it
		local ghost
		Drag.attach(button, {
			threshold = 10,
			onMove = function(pointer)
				if not ghost then
					ghost = New("Frame", {
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, 36),
						BackgroundColor3 = C("overlay"),
						ZIndex = 50,
						Parent = self.Root.Popups,
					}, { Create.corner(10), Create.stroke("accent"), Create.pad(0, 12), Create.list("Horizontal", 8, { valign = "Center" }) })
					Icons.new(tab.Icon, 16, C("accent")).Frame.Parent = ghost
					local label = New("TextLabel", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Weight = "SemiBold", TextSize = 13, LayoutOrder = 2, Parent = ghost })
					self.Loc:Bind(label, "Text", tab.TitleSpec)
				end
				local at = Device.toOffset(pointer)
				ghost.Position = UDim2.fromOffset(at.X + 12, at.Y - 18)
			end,
			onEnd = function(pointer, moved)
				if ghost then
					ghost:Destroy()
					ghost = nil
				end
				if moved and not self:_pointerOverWindow(pointer) then
					tab:Detach({ at = pointer })
				end
			end,
		}, maid)
	else
		Drag.longPress(button, 0.5, function()
			self:_tabMenu(tab, button)
		end, maid)
	end
end

function Window:_tabMenu(tab, anchor)
	local limit = self:DetachLimit()
	local count = self:DetachedCount()
	local items = {}
	if tab.DetachedWindow then
		table.insert(items, { Text = L("return_to_window"), Icon = "attach", Callback = function()
			tab:Attach()
		end })
	else
		table.insert(items, {
			Text = L("open_in_window"),
			Icon = "pip",
			Hint = limit < math.huge and L("detach_count") or nil,
			HintVars = { n = count, max = limit },
			Disabled = count >= limit,
			Callback = function()
				tab:Detach()
			end,
		})
	end
	self.Popup:Menu(anchor, items, { align = "left", width = 260 })
end

function Window:_buildSidebar(maid)
	local nav = self.Nav
	local loc = self.Loc
	local holder = maid:Add(New("Frame", {
		Name = "Sidebar",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = nav,
	}, { Create.pad(12, 10), Create.list("Vertical", 2) }))
	local list = New("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.fromScale(1, 0),
		ScrollBarThickness = 0,
		ZIndex = 2,
		LayoutOrder = 1,
		Parent = holder,
	}, { Create.flex(), Create.list("Vertical", 2) })
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	-- keep the scroll position when the tree is rebuilt (sub tabs unfold)
	if self._navScroll then
		list.CanvasPosition = self._navScroll
	end
	maid:Add(list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self._navScroll = list.CanvasPosition
	end))

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local function item(tab, parent)
		local selected = self.Selected == tab
		local button = New("TextButton", {
			Name = tab.Id,
			Size = Theme.sz(1, 0, 0, "navItem"),
			BackgroundColor3 = C("selected"),
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
			ZIndex = 2,
			Parent = parent,
		}, { Create.corner(8), Create.pad(0, 8, 0, 6), Create.list("Horizontal", 9, { valign = "Center" }) })
		-- accent bar on the left edge of the selected tab (gradient accent → accent2)
		local bar = New("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -6, 0.5, 0),
			Size = UDim2.fromOffset(3, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = button,
		}, { Create.corner("full"), New("UIGradient", { Color = Theme.gradient(), Rotation = 90 }) })
		New("UIFlexItem", { FlexMode = Enum.UIFlexMode.None, Parent = bar })
		bar.Visible = false
		-- icon in a tile: accent-tinted when selected
		local tile = New("Frame", {
			Name = "Tile",
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = C("accent"),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = button,
		}, { Create.corner(7) })
		local icon = Icons.new(tab.Icon, 16, C("textMuted"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		icon.Frame.Parent = tile
		local label = New("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C("textMuted"),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Weight = "Medium",
			LayoutOrder = 2,
			ZIndex = 2,
			Parent = button,
		}, { Create.flex() })
		loc:Bind(label, "Text", tab.TitleSpec)
		if tab.BadgeSpec then
			local badge = New("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 18),
				BackgroundColor3 = C("raised"),
				TextColor3 = C("textMuted"),
				TextSize = 11,
				Weight = "SemiBold",
				LayoutOrder = 3,
				Parent = button,
			}, { Create.corner("full"), Create.pad(0, 6) })
			badge.TextXAlignment = Enum.TextXAlignment.Center
			loc:Bind(badge, "Text", tab.BadgeSpec)
		end
		local pip = Icons.new("pip", 14, C("textSubtle"))
		pip.Frame.LayoutOrder = 4
		pip.Frame.Parent = button
		local chevron
		if #tab.SubTabs > 0 then
			chevron = Icons.new("chevronDown", 14, C("textSubtle"))
			chevron.Frame.LayoutOrder = 5
			chevron.Frame.Rotation = selected and 0 or -90
			chevron.Frame.Parent = button
		end
		maid:Add(button.MouseEnter:Connect(function()
			if self.Selected ~= tab then
				Motion.tween(button, { BackgroundTransparency = 0.6 }, "fade")
			end
		end))
		maid:Add(button.MouseLeave:Connect(function()
			if self.Selected ~= tab and self._highlightTab ~= tab then
				Motion.tween(button, { BackgroundTransparency = 1 }, "fade")
			end
		end))
		maid:Add(button.Activated:Connect(function()
			self:SelectTab(tab)
		end))
		self:_attachNavGestures(tab, button, maid)
		self._navItems[tab] = { button = button, icon = icon, label = label, pip = pip, bar = bar, tile = tile }

		-- sub tabs of the open tab unfold underneath, as a tree (quick-nav style)
		if selected and #tab.SubTabs > 0 then
			local tree = New("Frame", {
				Name = "SubTree",
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = nextOrder(),
				ZIndex = 2,
				Parent = parent,
			}, { Create.pad(2, 0, 4, 22), Create.list("Vertical", 1) })
			New("Frame", {
				Name = "Guide",
				Position = UDim2.new(0, -3, 0, 4),
				Size = UDim2.new(0, 1, 1, -8),
				BackgroundColor3 = C("border"),
				Parent = tree,
			})
			for index, sub in ipairs(tab.SubTabs) do
				local current = tab.CurrentSubTab == sub
				local subButton = New("TextButton", {
					Name = "Sub",
					Size = Theme.f(function(_, s)
						return UDim2.new(1, 0, 0, s.navItem - 6)
					end),
					BackgroundColor3 = C("selected"),
					BackgroundTransparency = current and 0.5 or 1,
					LayoutOrder = index,
					ZIndex = 2,
					Parent = tree,
				}, { Create.corner(6), Create.pad(0, 8, 0, 10), Create.list("Horizontal", 8, { valign = "Center" }) })
				-- dot on the guide line marks the current sub tab
				New("Frame", {
					Name = "Dot",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, -3, 0.5, 0),
					Size = UDim2.fromOffset(current and 7 or 5, current and 7 or 5),
					BackgroundColor3 = current and C("accent") or C("border"),
					ZIndex = 3,
					Parent = subButton,
				}, { Create.corner("full"), New("UIFlexItem", { FlexMode = Enum.UIFlexMode.None }) })
				if sub.Icon then
					Icons.new(sub.Icon, 14, current and C("accent") or C("textSubtle")).Frame.Parent = subButton
				end
				local subLabel = New("TextLabel", {
					Size = UDim2.fromScale(0, 1),
					TextColor3 = current and C("text") or C("textMuted"),
					Weight = current and "SemiBold" or "Regular",
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = 2,
					Parent = subButton,
				}, { Create.flex() })
				Theme.bind(subLabel, "TextSize", Theme.f(function(_, s)
					return s.font - 1
				end))
				loc:Bind(subLabel, "Text", sub.TitleSpec)
				maid:Add(subButton.Activated:Connect(function()
					tab:SelectSubTab(sub)
				end))
			end
		end
	end

	-- tabs, grouped by Category (a small caption before each new category)
	local lastCategory = nil
	for _, tab in ipairs(self:_navTabs()) do
		local category = tab.CategorySpec
		if category and category ~= lastCategory then
			local caption = New("TextLabel", {
				Name = "Category",
				Size = UDim2.new(1, 0, 0, 26),
				TextColor3 = C("textSubtle"),
				TextSize = 11,
				Weight = "SemiBold",
				TextYAlignment = Enum.TextYAlignment.Bottom,
				LayoutOrder = nextOrder(),
				Parent = list,
			}, { Create.pad(0, 0, 4, 10) })
			loc:Bind(caption, "Text", function()
				return Util.upper(loc:Get(category))
			end)
		end
		lastCategory = category
		item(tab, list)
	end
	if self.SettingsTab then
		item(self.SettingsTab.Tab, holder)
		self._navItems[self.SettingsTab.Tab].button.LayoutOrder = 2
	end
	if self.Branding then
		New("Frame", {
			Size = UDim2.new(1, -8, 0, 1),
			BackgroundColor3 = C("divider"),
			LayoutOrder = 3,
			Parent = holder,
		})
		local brand = New("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 4,
			ZIndex = 2,
			Parent = holder,
		}, { Create.pad(6, 10, 2, 10), Create.list("Vertical", 2) })
		New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 15),
			Text = "Robly by RobScript",
			TextColor3 = C("textSubtle"),
			TextSize = 11.5,
			Parent = brand,
		})
		local link = New("TextButton", {
			Size = UDim2.new(1, 0, 0, 15),
			Text = "robscript.com",
			TextColor3 = C("textMuted"),
			TextSize = 11.5,
			LayoutOrder = 2,
			Parent = brand,
		})
		maid:Add(link.Activated:Connect(function()
			self:_copyLink()
		end))
	end
end

function Window:_copyLink()
	if Compat.clipboard("https://robscript.com") then
		self:Notify({ Title = L("link_copied"), Content = "robscript.com", Type = "success", Duration = 2 })
	else
		self:Notify({ Title = "robscript.com", Type = "info", Duration = 3 })
	end
end

function Window:_moreItems(overflow, includeLanguage)
	local items = {}
	for _, tab in ipairs(overflow) do
		table.insert(items, {
			Text = tab.TitleSpec,
			Icon = tab.Icon,
			Checked = self.Selected == tab,
			Callback = function()
				self:SelectTab(tab)
			end,
		})
	end
	if #items > 0 then
		table.insert(items, "divider")
	end
	if self.SettingsTab then
		local settings = self.SettingsTab.Tab
		table.insert(items, {
			Text = settings.TitleSpec,
			Icon = settings.Icon,
			Checked = self.Selected == settings,
			Callback = function()
				self:SelectTab(settings)
			end,
		})
	end
	if includeLanguage and self.Loc:IsMultilingual() then
		table.insert(items, {
			Text = L("language"),
			Icon = "globe",
			Hint = self.Loc.Current:upper(),
			Callback = function()
				task.defer(function()
					self:OpenLanguageMenu(self._moreButton and self._moreButton.button)
				end)
			end,
		})
	end
	table.insert(items, "divider")
	table.insert(items, {
		Text = L("close"),
		Icon = "close",
		Danger = true,
		Callback = function()
			self:Close()
		end,
	})
	return items
end

function Window:_buildRail(maid)
	local nav = self.Nav
	local holder = maid:Add(New("Frame", {
		Name = "Rail",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = nav,
	}, { Create.pad(0, 6, 6, 6), Create.list("Vertical", 2, { align = "Center" }) }))
	local logoSlot = New("Frame", { Size = UDim2.new(1, 0, 0, 44), Parent = holder })
	local logo = self:_logo(28)
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.5)
	logo.Parent = logoSlot

	local height = (self._targetSize and self._targetSize.Y) or self.Frame.AbsoluteSize.Y
	local fit = math.max(1, math.floor((height - 44 - 46 - 8) / 46))
	local tabs = self:_navTabs()
	local overflow = {}
	for index, tab in ipairs(tabs) do
		if index <= fit then
			local button = New("TextButton", {
				Name = tab.Id,
				Size = UDim2.fromOffset(44, 44),
				BackgroundColor3 = C("raised"),
				BackgroundTransparency = 1,
				LayoutOrder = index + 1,
				ZIndex = 2,
				Parent = holder,
			}, { Create.corner(12) })
			local icon = Icons.new(tab.Icon, 20, C("textSubtle"), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
			})
			icon.Frame.Parent = button
			local pip = Icons.new("pip", 11, C("accent"), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -3, 0, 3),
			})
			pip.Frame.Parent = button
			Motion.pressable(button, nil, 0.92, maid)
			maid:Add(button.Activated:Connect(function()
				self:SelectTab(tab)
			end))
			self:_attachNavGestures(tab, button, maid)
			self._navItems[tab] = { button = button, icon = icon, pip = pip }
		else
			table.insert(overflow, tab)
		end
	end
	New("Frame", { Size = UDim2.fromScale(1, 0), LayoutOrder = 900, Parent = holder }, { Create.flex() })
	local more = New("TextButton", {
		Name = "More",
		Size = UDim2.fromOffset(44, 44),
		LayoutOrder = 1000,
		ZIndex = 2,
		Parent = holder,
	}, { Create.corner(12) })
	local moreIcon = Icons.new("more", 20, C("textSubtle"), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	moreIcon.Frame.Parent = more
	Motion.pressable(more, nil, 0.92, maid)
	self._moreButton = { button = more, icon = moreIcon }
	maid:Add(more.Activated:Connect(function()
		self.Popup:Menu(more, self:_moreItems(overflow, true), { align = "left", placement = "above", width = 240 })
	end))
end

function Window:_buildTabbar(maid)
	local nav = self.Nav
	local holder = maid:Add(New("Frame", {
		Name = "TabBar",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = nav,
	}, { Create.pad(0, 8), Create.list("Horizontal", 0, { valign = "Center" }) }))
	local tabs = self:_navTabs()
	local visible = math.min(#tabs, 4)
	local overflow = {}
	local function cell(name, iconName, order)
		local button = New("TextButton", {
			Name = name,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = order,
			ZIndex = 2,
			Parent = holder,
		}, { Create.flex(), Create.list("Vertical", 3, { align = "Center", valign = "Center" }) })
		local icon = Icons.new(iconName, 22, C("textSubtle"))
		icon.Frame.Parent = button
		local label = New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			TextColor3 = C("textSubtle"),
			TextSize = 11,
			Weight = "Medium",
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 2,
			Parent = button,
		})
		label.TextXAlignment = Enum.TextXAlignment.Center
		Motion.pressable(button, icon.Frame, 0.88, maid)
		return button, icon, label
	end
	for index, tab in ipairs(tabs) do
		if index <= visible then
			local button, icon, label = cell(tab.Id, tab.Icon, index)
			self.Loc:Bind(label, "Text", tab.TitleSpec)
			maid:Add(button.Activated:Connect(function()
				self:SelectTab(tab)
			end))
			self:_attachNavGestures(tab, button, maid)
			self._navItems[tab] = { button = button, icon = icon, label = label }
		else
			table.insert(overflow, tab)
		end
	end
	local more, moreIcon, moreLabel = cell("More", "more", 100)
	self.Loc:Bind(moreLabel, "Text", L("more"))
	self._moreButton = { button = more, icon = moreIcon, label = moreLabel }
	maid:Add(more.Activated:Connect(function()
		self.Popup:Menu(more, self:_moreItems(overflow, false), { align = "right", placement = "above", width = 240 })
	end))
end

function Window:_navItemFor(tab)
	local item = self._navItems and self._navItems[tab]
	if item then
		return item.button
	end
	return self._moreButton and self._moreButton.button or self.Frame
end

function Window:_pointerOverWindow(pointer)
	if self.Minimized then
		return false
	end
	local p, s = self.Frame.AbsolutePosition, self.Frame.AbsoluteSize
	return pointer.X >= p.X and pointer.X <= p.X + s.X and pointer.Y >= p.Y and pointer.Y <= p.Y + s.Y
end

function Window:_pointerOverNav(pointer)
	if self.Minimized then
		return false
	end
	local p, s = self.Nav.AbsolutePosition, self.Nav.AbsoluteSize
	return pointer.X >= p.X and pointer.X <= p.X + s.X and pointer.Y >= p.Y and pointer.Y <= p.Y + s.Y
end

function Window:_navHighlight(tab, on)
	self._highlightTab = on and tab or nil
	local item = self._navItems and self._navItems[tab]
	if item then
		self:_navVisual(tab, item)
		if on then
			self.Tooltip:Show(item.button, L("release_to_return"))
		else
			self.Tooltip:Hide()
		end
	end
end

-- Tabs ------------------------------------------------------------------------------------

function Window:Tab(opts)
	return Tab.new(self, opts)
end
Window.AddTab = Window.Tab
Window.CreateTab = Window.Tab

function Window:_internalTab(opts)
	return Tab.new(self, opts, true)
end

function Window:_addTab(tab)
	table.insert(self.AllTabs, tab)
	if not tab.Internal then
		table.insert(self.Tabs, tab)
	end
	self:_rebuildNav()
	if not tab.Internal and (not self.Selected or self.Selected.Internal) then
		self:SelectTab(tab)
	end
	local saved = self.Config:GetDetached(tab.Id)
	if saved and saved.open and tab.Detachable then
		task.defer(function()
			if not self.Destroyed and not tab.DetachedWindow then
				self:_detach(tab, { restoring = true })
			end
		end)
	end
end

function Window:_controlAdded() end

function Window:SelectTab(tab)
	if type(tab) == "string" or type(tab) == "number" then
		for index, candidate in ipairs(self.AllTabs) do
			if candidate.Id == tab or index == tab then
				tab = candidate
				break
			end
		end
	end
	if type(tab) ~= "table" then
		return
	end
	self.Search:Clear()
	if self.SearchBox and Theme.Mode == "pc" then
		self.SearchBox.Text = ""
	end
	self:_closeTouchSearch()
	local previous = self.Selected
	if previous and previous ~= tab and not previous.DetachedWindow then
		previous.Page.Visible = false
	end
	self.Selected = tab
	if tab.DetachedWindow then
		tab.Page.Visible = true
		self:_showPlaceholder(tab)
	else
		self:_hidePlaceholder()
		tab.Page.Visible = true
		if previous ~= tab and Motion.Mode == "Full" then
			tab.Page.Position = UDim2.fromOffset(0, 8)
			Motion.tween(tab.Page, { Position = UDim2.new() }, "window")
		end
	end
	if self.HeaderTitle then
		self.Loc:Bind(self.HeaderTitle, "Text", tab.TitleSpec)
	end
	if Theme.Mode ~= "pc" and previous ~= tab then
		self:_buildHeader()
	end
	if Theme.Mode == "pc" and previous ~= tab and ((previous and #previous.SubTabs > 0) or #tab.SubTabs > 0) then
		self:_rebuildNav() -- the sub tab tree follows the open tab
	else
		self:_updateNavSelection()
	end
	self.TabChanged:Fire(tab)
end

function Window:_showPlaceholder(tab)
	if not self.Placeholder then
		local holder = New("Frame", {
			Name = "Detached",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = self.PageHost,
		}, { Create.list("Vertical", 12, { align = "Center", valign = "Center" }) })
		local circle = New("Frame", {
			Size = UDim2.fromOffset(56, 56),
			BackgroundColor3 = C("surface"),
			Parent = holder,
		}, { Create.corner("full"), Create.stroke("border") })
		Icons.new("pip", 24, C("accent"), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }).Frame.Parent = circle
		local title = Create.text("", { weight = "SemiBold", wrap = true, order = 2, align = "Center" })
		title.Size = UDim2.new(0.8, 0, 0, 0)
		title.Parent = holder
		local desc = Create.text("", { size = "fontDesc", color = "textMuted", wrap = true, order = 3, align = "Center" })
		desc.Size = UDim2.new(0.8, 0, 0, 0)
		desc.Parent = holder
		self.Loc:Bind(desc, "Text", L("detached_desc"))
		local button = New("TextButton", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = Theme.sz(0, 0, 0, "button"),
			BackgroundColor3 = C("accent"),
			TextColor3 = C("accentInk"),
			Weight = "SemiBold",
			LayoutOrder = 4,
			Parent = holder,
		}, { Create.corner("rControl"), Create.pad(0, 16) })
		self.Loc:Bind(button, "Text", L("return_to_window"))
		Motion.pressable(button, nil, nil, self.Maid)
		self.Maid:Add(button.Activated:Connect(function()
			if self.Selected and self.Selected.DetachedWindow then
				self.Selected:Attach()
			end
		end))
		self.Placeholder = { Frame = holder, Title = title }
	end
	for _, other in ipairs(self.AllTabs) do
		if not other.DetachedWindow then
			other.Page.Visible = false
		end
	end
	self.Loc:Bind(self.Placeholder.Title, "Text", L("detached_title"), function()
		return { tab = self.Loc:Get(tab.TitleSpec) }
	end)
	self.Placeholder.Frame.Visible = true
end

function Window:_hidePlaceholder()
	if self.Placeholder then
		self.Placeholder.Frame.Visible = false
	end
end

function Window:DetachLimit()
	if Theme.Mode == "phone" then
		return self.Options.MaxDetachedPhone or 2
	end
	return self.Options.MaxDetached or math.huge
end

function Window:DetachedCount()
	local n = 0
	for _, tab in ipairs(self.AllTabs) do
		if tab.DetachedWindow then
			n += 1
		end
	end
	return n
end

function Window:_detach(tab, options)
	options = options or {}
	if not tab.Detachable or tab.DetachedWindow then
		return nil
	end
	local limit = self:DetachLimit()
	if self:DetachedCount() >= limit then
		self:Notify({ Title = L("detach_limit"), Vars = { n = limit }, Type = "warning", Duration = 3 })
		return nil
	end
	local item = self:_navItemFor(tab)
	if item and not options.restoring and not self.Minimized then
		options.fromPos, options.fromSize = Device.toOffset(item.AbsolutePosition), item.AbsoluteSize
	end
	local detached = Detached.new(tab, options)
	self.Config:SetDetached(tab.Id, { open = true }, true)
	if self.Selected == tab then
		self:_showPlaceholder(tab)
	end
	if self.Minimized and self.Config:GetMeta("hideDetached") then
		detached:SetHidden(true)
	end
	self:_rebuildNav()
	if Theme.Mode ~= "pc" then
		self:_buildHeader()
	end
	tab.DetachChanged:Fire(true)
	return detached
end

function Window:_attached(tab)
	if self.Selected == tab then
		self:_hidePlaceholder()
		tab.Page.Visible = true
	else
		tab.Page.Visible = false
	end
	self:_rebuildNav()
	if Theme.Mode ~= "pc" then
		self:_buildHeader()
	end
	tab.DetachChanged:Fire(false)
end

-- Jump to a control (search results, API).
function Window:Reveal(control)
	if self.Minimized then
		self:Restore()
	end
	self:_closeTouchSearch()
	if self.SearchBox and Theme.Mode == "pc" then
		self.SearchBox.Text = ""
	end
	self.Search:Clear()
	local tab = control.Tab
	if tab.DetachedWindow then
		tab.DetachedWindow:Focus()
	else
		self:SelectTab(tab)
	end
	if control.Section.SubTab then
		tab:SelectSubTab(control.Section.SubTab)
	end
	if control.Section.Collapsed then
		control.Section:SetCollapsed(false)
	end
	task.delay(0.05, function()
		if self.Destroyed or control.Destroyed then
			return
		end
		local page = tab.Page
		local y = control.Holder.AbsolutePosition.Y - page.AbsolutePosition.Y + page.CanvasPosition.Y - 24
		local maxY = math.max(0, page.AbsoluteCanvasSize.Y - page.AbsoluteWindowSize.Y)
		Motion.tween(page, { CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY)) }, "window")
		task.delay(Motion.Mode == "Full" and 0.2 or 0, function()
			control:Flash()
		end)
	end)
end

-- Geometry ------------------------------------------------------------------------------

function Window:_defaultRect()
	local vp = Device.viewport()
	local inset = Device.inset()
	local mode = Theme.Mode
	local size = self.Options.Size
	local w, h, x, y
	if mode == "pc" then
		w = math.min(size and size.X or 860, vp.X - 32)
		h = math.min(size and size.Y or 560, vp.Y - inset - 32)
		x = math.min((vp.X - w) / 2, vp.X - w - (Theme.Sizes.toastWidth + 48))
		x = math.max(16, x)
		y = math.max(inset + 16, (vp.Y - h) / 2)
	elseif mode == "phone" then
		w = math.clamp(math.floor(vp.X * 0.57), math.min(360, vp.X - 24), math.min(560, vp.X - 24))
		h = vp.Y - inset - 16
		x = (vp.X - w) / 2
		y = inset + 8
	else
		w = math.min(math.floor(vp.X * 0.72), 560, vp.X - 32)
		h = math.min(math.floor(vp.Y * 0.7), 820, vp.Y - inset - 32)
		x = (vp.X - w) / 2
		y = inset + 24
	end
	return Vector2.new(math.floor(x), math.floor(y)), Vector2.new(math.floor(w), math.floor(h))
end

function Window:_placeWindow(useSaved)
	local position, size = self:_defaultRect()
	if useSaved and Theme.Mode == "pc" then
		local saved = self.Config:GetMeta("window")
		if type(saved) == "table" and saved.w and saved.h then
			local vp = Device.viewport()
			size = Vector2.new(math.clamp(saved.w, 520, math.max(520, vp.X - 16)), math.clamp(saved.h, 340, math.max(340, vp.Y - Device.inset() - 16)))
			position = Drag.clamp(Vector2.new(saved.x or position.X, saved.y or position.Y), size)
		end
	end
	self._targetSize = size
	self.Frame.Position = UDim2.fromOffset(position.X, position.Y)
	self.Frame.Size = UDim2.fromOffset(size.X, size.Y)
	self:_fitHeader()
end

function Window:_saveRect()
	if Theme.Mode ~= "pc" then
		return
	end
	local p, s = Device.offsetOf(self.Frame), self.Frame.AbsoluteSize
	self._targetSize = s
	self.Config:SetMeta("window", { x = p.X, y = p.Y, w = s.X, h = s.Y })
end

function Window:_onDevice(mode)
	if self.Destroyed then
		return
	end
	if mode ~= self.Mode then
		self.Mode = mode
		Theme.setMode(mode)
		self.Popup:Close()
		self:_applyLayout()
		self:_placeWindow(true)
		self:_rebuildNav()
	else
		local p, s = Device.offsetOf(self.Frame), self.Frame.AbsoluteSize
		local vp = Device.viewport()
		if s.X > vp.X - 16 or s.Y > vp.Y - Device.inset() - 16 or Theme.Mode ~= "pc" then
			self:_placeWindow(false)
			self:_rebuildNav()
		else
			local clamped = Drag.clamp(p, s)
			self.Frame.Position = UDim2.fromOffset(clamped.X, clamped.Y)
		end
	end
	self.Notifier:Place()
	if self.Hud then
		self.Hud:Refresh()
	end
	if self.QuickButtons then
		self.QuickButtons:Refresh()
	end
end

-- Minimise / restore ------------------------------------------------------------------

function Window:_updatePillDot()
	local any = false
	for flag, meta in pairs(self.Store.Meta) do
		if meta.persist == "profile" and meta.kind == "Toggle" and self.Store:Get(flag) == true then
			any = true
			break
		end
	end
	self.Pill:SetActive(any)
end

function Window:Minimize()
	if self.Minimized or self.Destroyed then
		return
	end
	self.Minimized = true
	self.Popup:Close()
	self.Tooltip:Hide()
	self:_updatePillDot()
	local frame = self.Frame
	if not (self._animatingUntil and os.clock() < self._animatingUntil and self._restorePosition) then
		self._restorePosition = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
	end
	self._animatingUntil = os.clock() + 0.3
	self.Pill:Show(true)
	if Motion.Mode == "Full" then
		local pillPos, pillSize = self.Pill:Rect()
		local center = pillPos + pillSize / 2
		local scale = 0.12
		local fullSize = Vector2.new(frame.Size.X.Offset, frame.Size.Y.Offset)
		local target = center - fullSize * scale / 2
		Motion.tween(self.Scale, { Scale = scale }, "window")
		Motion.tween(frame, { Position = UDim2.fromOffset(target.X, target.Y) }, "window")
		task.delay(0.26, function()
			if self.Minimized then
				frame.Visible = false
			end
		end)
	else
		frame.Visible = false
	end
	for _, tab in ipairs(self.AllTabs) do
		if tab.DetachedWindow and self.Config:GetMeta("hideDetached") then
			tab.DetachedWindow:SetHidden(true)
		end
	end
	self.VisibilityChanged:Fire(false)
end

function Window:Restore()
	if not self.Minimized or self.Destroyed then
		return
	end
	self.Minimized = false
	local frame = self.Frame
	local target = self._restorePosition or Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
	self._animatingUntil = os.clock() + 0.3
	self.Pill:Hide()
	frame.Visible = true
	frame.ZIndex = self.Root:NextZ()
	if Motion.Mode == "Full" then
		Motion.tween(self.Scale, { Scale = 1 }, "window")
		Motion.tween(frame, { Position = UDim2.fromOffset(target.X, target.Y) }, "window")
	else
		self.Scale.Scale = 1
		frame.Position = UDim2.fromOffset(target.X, target.Y)
	end
	for _, tab in ipairs(self.AllTabs) do
		if tab.DetachedWindow then
			tab.DetachedWindow:SetHidden(false)
		end
	end
	self.VisibilityChanged:Fire(true)
end

function Window:Toggle()
	if self.Minimized then
		self:Restore()
	else
		self:Minimize()
	end
end

function Window:IsVisible()
	return not self.Minimized
end

-- Keyboard shortcuts (PC): Ctrl+K search, Escape closes search / popups.
function Window:_shortcut(input, processed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local uis = Services.UserInputService
	if input.KeyCode == Enum.KeyCode.K and (uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl)) then
		if not self.Binds.Capturing then
			self:FocusSearch()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape and not processed then
		self.Popup:Close()
		self.Search:Clear()
	end
end

-- Public helpers -----------------------------------------------------------------------

function Window:Notify(opts)
	if type(opts) == "string" then
		opts = { Title = opts }
	end
	return self.Notifier:Notify(opts)
end

function Window:Dialog(opts)
	return self.Dialogs:Open(opts)
end

function Window:SetTheme(nameOrColors)
	Theme.apply(nameOrColors)
	self.Config:SaveInterface()
end

function Window:SetEffect(effect)
	Theme.setEffect(effect)
	self.Config:SaveInterface()
end

-- 0.25 … 2 (1 = default)
function Window:SetEffectStrength(value)
	Theme.setEffectStrength(value)
	self.Config:SaveInterface()
end

function Window:SetGlass(enabled)
	Theme.setGlass(enabled)
	self.Config:SaveInterface()
end

function Window:SetLanguage(code)
	if self.Loc:SetLanguage(code) then
		self.Config:SaveInterface()
	end
end

function Window:SetAnimations(mode)
	Motion.setMode(mode)
	self.Config:SaveInterface()
end

function Window:GetFlag(flag)
	return self.Store:Get(flag)
end

function Window:SetFlag(flag, value)
	return self.Store:Set(flag, value, "api")
end

function Window:OnFlagChanged(flag, fn)
	return self.Store:OnChanged(flag, fn)
end

function Window:SaveConfig(name)
	return self.Config:Save(name)
end

function Window:LoadConfig(name)
	return self.Config:Load(name)
end

function Window:_autoFlag(control)
	local spec = control.TitleSpec
	local text
	if type(spec) == "string" then
		text = spec
	elseif type(spec) == "table" and not spec.__lib then
		text = spec.en or spec[self.Loc.Default]
		if not text then
			local _, first = next(spec)
			text = first
		end
	elseif type(spec) == "table" then
		text = spec.__lib
	end
	local base = control.Tab.Id .. "/" .. tostring(text or control.Kind):gsub("[^%w_%-%.]", "_")
	local flag = base
	local n = 1
	while self._flags[flag] do
		n += 1
		flag = base .. "#" .. n
	end
	self._flags[flag] = true
	return flag
end

function Window:_registerQuick(control)
	table.insert(self.Quick, control)
	if self.QuickButtons then
		self.QuickButtons:_scheduleRefresh()
	end
	control.Maid:Add(function()
		local index = table.find(self.Quick, control)
		if index then
			table.remove(self.Quick, index)
		end
		if self.QuickButtons and not self.Destroyed then
			self.QuickButtons:_scheduleRefresh()
		end
	end)
end

function Window:_afterBuild()
	if not self.Selected then
		local first = self.Tabs[1] or (self.SettingsTab and self.SettingsTab.Tab)
		if first then
			self:SelectTab(first)
		end
	end
	self.Config:Notices()
	self:_updatePillDot()
end

function Window:Close()
	self:Dialog({
		Title = L("close_q"),
		Vars = { name = self.Loc:Get(self.TitleSpec) },
		Content = L("close_desc"),
		Buttons = {
			{ Text = L("cancel"), Variant = "Secondary" },
			{ Text = L("close"), Variant = "Danger", Callback = function()
				task.defer(function()
					self:Destroy()
				end)
			end },
		},
	})
end

function Window:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.OnDestroy:Fire()
	if self.Options.OnClose then
		task.spawn(self.Options.OnClose)
	end
	self.Config:Flush()
	for _, tab in ipairs(table.clone(self.AllTabs)) do
		tab:Destroy()
	end
	if self.Hud then
		self.Hud:Destroy()
	end
	if self.QuickButtons then
		self.QuickButtons:Destroy()
	end
	self.Binds:Destroy()
	self.Search:Destroy()
	if self._navMaid then
		self._navMaid:Clean()
	end
	if self._headerMaid then
		self._headerMaid:Clean()
	end
	if self._layoutMaid then
		self._layoutMaid:Clean()
	end
	self.Maid:Clean()
	self.Store:Destroy()
	self.Loc:Destroy()
	self.OnDestroy:DisconnectAll()
	self.VisibilityChanged:DisconnectAll()
	self.TabChanged:DisconnectAll()
	if self.Library and self.Library._windowClosed then
		self.Library:_windowClosed(self)
	end
end

return Window
