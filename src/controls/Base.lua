-- Control base: the one row implementation every control extends
-- (brief, rule 5: a small core, new behaviour = extension, no one-off copies).
--
-- Row anatomy (inside a section card):
--   Holder ── Divider (inset like iOS)
--          └─ Row ── Hit (whole-row tap target, optional)
--                 ├─ Inner (padding + layout):  [Left] [Title / Description] [Right]
--                 │                         or  stacked: top line + Body
--                 └─ Overlay (dims + blocks input when EnabledWhen is false)

local Theme = import("core/Theme")
local Create = import("core/Create")
local Motion = import("core/Motion")
local Icons = import("core/Icons")
local Maid = import("util/Maid")
local Util = import("util/Util")
local Signal = import("util/Signal")

local New = Create.New
local C, S = Theme.c, Theme.s

local Control = {}
Control.__index = Control

-- Creates a control subclass table.
function Control.extend(kind)
	local class = setmetatable({}, { __index = Control })
	class.__index = class
	class.Kind = kind
	return class
end

local function evaluate(condition, store)
	if condition == nil then
		return true
	end
	if type(condition) == "function" then
		local ok, result = pcall(condition, function(flag)
			return store:Get(flag)
		end, Theme.Mode)
		return ok and result ~= false and result ~= nil
	end
	if type(condition) == "table" then
		local value = store:Get(condition.Flag)
		if condition.Equals ~= nil then
			return Util.equal(value, condition.Equals)
		elseif condition.NotEquals ~= nil then
			return not Util.equal(value, condition.NotEquals)
		elseif condition.In then
			for _, candidate in ipairs(condition.In) do
				if Util.equal(candidate, value) then
					return true
				end
			end
			return false
		elseif condition.Is then
			local ok, result = pcall(condition.Is, value)
			return ok and result == true
		end
		if type(value) == "table" then
			return next(value) ~= nil
		end
		return value ~= nil and value ~= false and value ~= "" and value ~= 0
	end
	return condition == true
end
Control.evaluate = evaluate

-- spec: { kind, value = bool, default, persist, validate, layout = "row"|"stack"|"custom",
--         rowClick = bool, left = bool, searchable = bool }
function Control.new(section, opts, spec)
	local class = spec.class or Control
	local self = setmetatable({}, class)
	local window = section.Window
	self.Kind = spec.kind
	self.Section = section
	self.Tab = section.Tab
	self.Window = window
	self.Options = opts
	self.Maid = Maid.new()
	self.Loc = window.Loc
	self.Store = window.Store
	self.Changed = Signal.new()
	self.TitleSpec = opts.Title or opts.Name or opts.Text
	self.DescSpec = opts.Description or opts.Desc
	self.Icon = opts.Icon
	self.Visible = true
	self.Enabled = true
	self.Destroyed = false

	if spec.value then
		self.Flag = opts.Flag or window:_autoFlag(self)
		local persist = spec.persist
		if persist == nil then
			persist = "profile"
		end
		if opts.Save == false then
			persist = false
		end
		if opts.Persist ~= nil then
			persist = opts.Persist
		end
		local _, loaded = self.Store:Register(self.Flag, spec.default, {
			persist = persist,
			kind = spec.kind,
			validate = spec.validate,
		})
		self._loaded = loaded
		self.Maid:Add(self.Store:OnChanged(self.Flag, function(value, old, source)
			if self.Destroyed then
				return
			end
			self:_render(value, true, old)
			self.Changed:Fire(value, old, source)
			if opts.Callback and source ~= "silent" then
				task.spawn(opts.Callback, value)
			end
		end))
	end

	-- Holder & divider -------------------------------------------------------
	self.Holder = New("Frame", {
		Name = spec.kind,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = section:_nextOrder(),
		Parent = section.Card,
	}, { Create.list("Vertical", 0, { align = "Right" }) })
	self.Maid:Add(self.Holder)
	self.Divider = New("Frame", {
		Name = "Divider",
		Size = Theme.f(function(_, s)
			return UDim2.new(1, -s.padX, 0, 1)
		end),
		BackgroundColor3 = C("border"),
		LayoutOrder = 1,
		Parent = self.Holder,
	})
	self.Row = New("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C("accent"),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = self.Holder,
	})
	-- hover: accent wash fading to the right
	New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = self.Row,
	})
	self.Maid:Add(self.Row.MouseEnter:Connect(function()
		if self.Enabled then
			Motion.tween(self.Row, { BackgroundTransparency = 0.9 }, "fade")
		end
	end))
	self.Maid:Add(self.Row.MouseLeave:Connect(function()
		Motion.tween(self.Row, { BackgroundTransparency = 1 }, "fade")
	end))
	if spec.rowClick then
		self.Hit = New("TextButton", {
			Name = "Hit",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
			Parent = self.Row,
		})
	end
	-- Nesting: opts.Parent = flag or control → indented under it with a guide
	-- line, and (unless VisibleWhen is given) only shown while the parent is on.
	local parentFlag = opts.Parent
	if type(parentFlag) == "table" then
		parentFlag = parentFlag.Flag
	end
	self.ParentFlag = parentFlag
	local indent = parentFlag and 18 or 0
	self.Inner = New("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 2,
		Parent = self.Row,
	}, { Create.minSize(0, self.DescSpec and "rowDesc" or "row") })
	local padding = New("UIPadding", { Parent = self.Inner })
	Theme.bind(padding, "PaddingTop", Theme.f(function(_, s)
		return UDim.new(0, s.padY)
	end))
	Theme.bind(padding, "PaddingBottom", Theme.f(function(_, s)
		return UDim.new(0, s.padY)
	end))
	Theme.bind(padding, "PaddingRight", Theme.f(function(_, s)
		return UDim.new(0, s.padX)
	end))
	Theme.bind(padding, "PaddingLeft", Theme.f(function(_, s)
		return UDim.new(0, s.padX + indent)
	end))
	if parentFlag then
		New("Frame", {
			Name = "Guide",
			Position = Theme.f(function(_, s)
				return UDim2.new(0, s.padX + 5, 0, 0)
			end),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = C("borderStrong"),
			Parent = self.Row,
		})
		if opts.VisibleWhen == nil then
			opts.VisibleWhen = { Flag = parentFlag }
		end
	end
	-- accent bar on the left edge while the control is "on" (toggles, checkboxes)
	self.ActiveBar = New("Frame", {
		Name = "ActiveBar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 2, 0.6, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = self.Row,
	}, { Create.corner("full"), New("UIGradient", { Color = Theme.gradient(), Rotation = 90 }) })

	local layout = spec.layout or "row"
	self.Layout = layout
	if layout == "row" or layout == "stack" then
		local line = self.Inner
		if layout == "stack" then
			Create.list("Vertical", 10).Parent = self.Inner
			line = New("Frame", {
				Name = "Top",
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 1,
				Parent = self.Inner,
			})
			self.Body = New("Frame", {
				Name = "Body",
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				Parent = self.Inner,
			})
		end
		Create.list("Horizontal", "gap", { valign = "Center" }).Parent = line
		if spec.left then
			self.Left = New("Frame", {
				Name = "Left",
				AutomaticSize = Enum.AutomaticSize.XY,
				LayoutOrder = 0,
				Parent = line,
			})
		end
		self.Texts = New("Frame", {
			Name = "Texts",
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = line,
		}, { Create.list("Vertical", 2), Create.flex() })
		self.TitleLabel = Create.text("", { weight = spec.titleWeight or "Medium", wrap = true, order = 1, name = "Title" })
		self.TitleLabel.Parent = self.Texts
		self.Loc:Bind(self.TitleLabel, "Text", self.TitleSpec or "")
		if self.DescSpec or opts.DisabledText then
			self:_ensureDescription()
		end
		self.Right = New("Frame", {
			Name = "Right",
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = 2,
			Parent = line,
		}, { Create.list("Horizontal", 8, { valign = "Center" }) })
		if opts.Tooltip then
			self:_addTooltip(opts.Tooltip)
		end
	end

	self.Overlay = New("TextButton", {
		Name = "Disabled",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C("surface"),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 10,
		Parent = self.Row,
	})

	-- Conditions (VisibleWhen / EnabledWhen) -----------------------------------
	if opts.VisibleWhen ~= nil or opts.EnabledWhen ~= nil then
		local function update()
			if self.Destroyed then
				return
			end
			if opts.VisibleWhen ~= nil then
				self:_setVisible(evaluate(opts.VisibleWhen, self.Store))
			end
			if opts.EnabledWhen ~= nil then
				self:SetEnabled(evaluate(opts.EnabledWhen, self.Store))
			end
		end
		self.Maid:Add(self.Store.Changed:Connect(update))
		self.Maid:Add(Theme.Changed:Connect(function(what)
			if what == "sizes" then
				update()
			end
		end))
		task.defer(update)
		update()
	end

	if spec.searchable ~= false and self.TitleSpec then
		window.Search:Add(self)
		self.Maid:Add(function()
			window.Search:Remove(self)
		end)
	end
	if opts.QuickButton then
		window:_registerQuick(self)
	end
	section:_add(self)
	return self
end

-- Called by subclasses at the end of construction.
function Control:_finish()
	if self.Flag then
		self:_render(self.Store:Get(self.Flag), false)
		if self._loaded and self.Options.Callback then
			task.spawn(self.Options.Callback, self.Store:Get(self.Flag))
		end
	end
end

function Control:_render() end

-- Visual "on" state shared by toggles and checkboxes: accent bar + bolder title.
function Control:_setActive(on, animate)
	if self.Options.Highlight == false then
		on = false
	end
	if animate then
		Motion.tween(self.ActiveBar, { BackgroundTransparency = on and 0 or 1 }, "fade")
	else
		self.ActiveBar.BackgroundTransparency = on and 0 or 1
	end
	if self.TitleLabel then
		self.TitleLabel.FontFace = Theme.font(on and "SemiBold" or "Medium")
		Theme.set(self.TitleLabel, "TextColor3", on and C("text") or C("textMuted"))
	end
end

function Control:_ensureDescription()
	if self.DescLabel or not self.Texts then
		return
	end
	self.DescLabel = Create.text("", { size = "fontDesc", color = "textSubtle", wrap = true, order = 2, name = "Description" })
	self.DescLabel.Parent = self.Texts
	self.Loc:Bind(self.DescLabel, "Text", self.DescSpec or "")
	self.DescLabel.Visible = self.DescSpec ~= nil
end

function Control:_addTooltip(spec)
	local button = New("TextButton", {
		Name = "Help",
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = C("segment"),
		Text = "?",
		Weight = "Bold",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = -1,
		Parent = self.Right,
	}, { Create.corner("full") })
	button.TextXAlignment = Enum.TextXAlignment.Center
	self.Maid:Add(button.Activated:Connect(function()
		self.Window.Tooltip:Show(button, spec)
	end))
	self.Window.Tooltip:Attach(button, spec, self.Maid)
end

-- Public API ---------------------------------------------------------------------

function Control:Get()
	if self.Flag then
		return self.Store:Get(self.Flag)
	end
	return nil
end

function Control:Set(value, silent)
	if self.Flag then
		if self._validate then
			value = self:_validate(value)
		end
		self.Store:Set(self.Flag, value, silent and "silent" or "api")
	end
	return self
end

function Control:OnChanged(fn)
	return self.Changed:Connect(fn)
end

function Control:SetTitle(spec)
	self.TitleSpec = spec
	if self.TitleLabel then
		self.Loc:Bind(self.TitleLabel, "Text", spec)
	end
	return self
end

function Control:SetDescription(spec)
	self.DescSpec = spec
	self:_ensureDescription()
	if self.DescLabel then
		self.Loc:Bind(self.DescLabel, "Text", spec or "")
		self.DescLabel.Visible = spec ~= nil
	end
	return self
end

function Control:_setVisible(visible)
	if self.Visible == visible then
		return
	end
	self.Visible = visible
	self.Holder.Visible = visible
	self.Section:_updateDividers()
end

function Control:SetVisible(visible)
	self:_setVisible(visible ~= false)
	return self
end

function Control:SetEnabled(enabled)
	enabled = enabled ~= false
	if self.Enabled == enabled then
		return self
	end
	self.Enabled = enabled
	self.Overlay.Visible = not enabled
	local disabledText = self.Options.DisabledText
	if disabledText and self.DescLabel then
		if enabled then
			self.Loc:Bind(self.DescLabel, "Text", self.DescSpec or "")
			self.DescLabel.Visible = self.DescSpec ~= nil
		else
			self.Loc:Bind(self.DescLabel, "Text", disabledText)
			self.DescLabel.Visible = true
		end
	end
	return self
end

-- Brief highlight used by search navigation.
function Control:Flash()
	self.Row.BackgroundTransparency = 0.8
	Motion.tween(self.Row, { BackgroundTransparency = 1 }, "flash")
end

-- Search support -----------------------------------------------------------------

function Control:SearchTexts()
	return self.Loc:SearchTexts(self.TitleSpec)
end

function Control:StateText()
	return nil
end

-- Quick-button support (toggles and actions)
function Control:QuickState()
	return nil
end

function Control:QuickActivate() end

function Control:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.Changed:DisconnectAll()
	self.Section:_remove(self)
	self.Maid:Clean()
end

-- Shared little builders used by several controls ---------------------------------

-- A pressable pill/rounded button with optional icon; returns button, label.
function Control.chip(props)
	local button = New("TextButton", {
		Name = props.name or "Chip",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = props.size or Theme.sz(0, 0, 0, "control"),
		BackgroundColor3 = props.bg or C("raised"),
		BackgroundTransparency = props.transparent and 1 or 0,
		LayoutOrder = props.order or 0,
	}, {
		Create.corner(props.radius or "rSmall"),
		Create.pad(0, props.padRight or 8, 0, props.padLeft or 12),
		Create.list("Horizontal", 6, { valign = "Center" }),
	})
	local label = New("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = props.color or C("text"),
		TextSize = props.textSize or S("font"),
		Mono = props.mono,
		Weight = props.weight,
		LayoutOrder = 1,
		Parent = button,
	}, { Create.maxSize(props.maxWidth or 180, nil) })
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local icon
	if props.icon then
		icon = Icons.new(props.icon, props.iconSize or 16, props.iconColor or C("textMuted"))
		icon.Frame.LayoutOrder = 2
		icon.Frame.Parent = button
	end
	return button, label, icon
end

return Control
