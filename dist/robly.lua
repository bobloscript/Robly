--[[
	Robly v1.4.0 — UI library for Roblox scripts by RobScript
	https://robscript.com · https://github.com/bobloscript/Robly

	Built file. Edit the modules in src/ and run `python3 tools/build.py`.
	Public domain (The Unlicense).
]]

local __modules = {}
local __cache = {}
local function import(name)
	local cached = __cache[name]
	if cached ~= nil then
		return cached
	end
	local loader = __modules[name]
	if not loader then
		error("[Robly] missing module: " .. tostring(name), 2)
	end
	local value = loader()
	__cache[name] = value
	return value
end

__modules["controls/Base"] = function()
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
end

__modules["controls/Basic"] = function()
	-- Toggle, Checkbox, Button, Buttons (group), Label, Paragraph, Divider,
	-- Badge, Image, ProgressBar, Code.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Compat = import("util/Compat")
	local Control = import("controls/Base")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Controls = {}

	-- Toggle ----------------------------------------------------------------------------

	local Toggle = Control.extend("Toggle")

	function Controls.Toggle(section, opts)
		local self = Control.new(section, opts, {
			class = Toggle, kind = "Toggle", value = true, default = opts.Default == true,
			rowClick = true,
			validate = function(v)
				return v == true
			end,
		})
		local track = New("TextButton", {
			Name = "Switch",
			Size = Theme.sz(0, "toggleW", 0, "toggleH"),
			BackgroundColor3 = C("toggleOff"),
			LayoutOrder = 5,
			Parent = self.Right,
		}, { Create.corner("full") })
		self.TrackGradient = New("UIGradient", { Color = Theme.gradient(), Enabled = false, Parent = track })
		self.Knob = New("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2, 0.5, 0),
			Size = Theme.sz(0, "knob", 0, "knob"),
			BackgroundColor3 = C("knobOff"),
			Parent = track,
		}, { Create.corner("full") })
		self.Track = track
		Motion.pressable(track, nil, 0.94, self.Maid)
		local function flip()
			self:Set(not self:Get())
		end
		self.Maid:Add(track.Activated:Connect(flip))
		self.Maid:Add(self.Hit.Activated:Connect(flip))
		self:_finish()
		return self
	end

	function Toggle:_validate(v)
		return v == true
	end

	function Toggle:_render(on, animate)
		-- on: white base × accent→accent2 gradient
		self.TrackGradient.Enabled = on == true
		self:_setActive(on == true, animate)
		local trackColor = on and Theme.f(function()
			return Color3.new(1, 1, 1)
		end) or C("toggleOff")
		local knobColor = on and C("knobOn") or C("knobOff")
		local anchor = on and Vector2.new(1, 0.5) or Vector2.new(0, 0.5)
		local position = on and UDim2.new(1, -2, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		if animate then
			Theme.set(self.Track, "BackgroundColor3", trackColor)
			Theme.set(self.Knob, "BackgroundColor3", knobColor)
			Motion.tween(self.Knob, { AnchorPoint = anchor, Position = position }, "spring")
		else
			Theme.bind(self.Track, "BackgroundColor3", trackColor)
			Theme.bind(self.Knob, "BackgroundColor3", knobColor)
			self.Knob.AnchorPoint = anchor
			self.Knob.Position = position
		end
	end

	function Toggle:StateText()
		return self.Loc:Lib(self:Get() and "on_short" or "off_short")
	end

	function Toggle:QuickState()
		return self:Get() == true
	end

	function Toggle:QuickActivate()
		self:Set(not self:Get())
		return self:Get()
	end

	-- Checkbox --------------------------------------------------------------------------

	local Checkbox = Control.extend("Checkbox")

	function Controls.Checkbox(section, opts)
		local self = Control.new(section, opts, {
			class = Checkbox, kind = "Checkbox", value = true, default = opts.Default == true,
			rowClick = true, left = true,
			validate = function(v)
				return v == true
			end,
		})
		local box = New("TextButton", {
			Name = "Box",
			Size = Theme.sz(0, "checkbox", 0, "checkbox"),
			BackgroundColor3 = C("accent"),
			BackgroundTransparency = 1,
			Parent = self.Left,
		}, { Create.corner(6), New("UIGradient", { Color = Theme.gradient(), Rotation = 45 }) })
		box.BackgroundColor3 = Color3.new(1, 1, 1)
		self.Stroke = Create.stroke("checkBorder", 1.5)
		self.Stroke.Parent = box
		self.Check = Icons.new("check", Theme.Sizes.touch and 18 or 14, C("accentInk"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		self.Check.Frame.Parent = box
		self.CheckScale = New("UIScale", { Parent = self.Check.Frame })
		self.Box = box
		Motion.pressable(box, nil, 0.9, self.Maid)
		local function flip()
			self:Set(not self:Get())
		end
		self.Maid:Add(box.Activated:Connect(flip))
		self.Maid:Add(self.Hit.Activated:Connect(flip))
		self:_finish()
		return self
	end

	function Checkbox:_validate(v)
		return v == true
	end

	function Checkbox:_render(on, animate)
		local tween = animate and Motion.tween or function(instance, props)
			for k, v in pairs(props) do
				instance[k] = v
			end
		end
		self:_setActive(on == true, animate)
		tween(self.Box, { BackgroundTransparency = on and 0 or 1 }, "fade")
		tween(self.Stroke, { Transparency = on and 1 or 0 }, "fade")
		self.Check.Frame.Visible = on
		if on and animate then
			self.CheckScale.Scale = 0.6
			Motion.tween(self.CheckScale, { Scale = 1 }, "spring")
		else
			self.CheckScale.Scale = 1
		end
	end

	Checkbox.StateText = Toggle.StateText
	Checkbox.QuickState = Toggle.QuickState
	Checkbox.QuickActivate = Toggle.QuickActivate

	-- Button ------------------------------------------------------------------------------

	local VARIANTS = {
		Primary = { bg = "accent", fg = "accentInk", weight = "SemiBold", gradient = true },
		Secondary = { bg = "raised", fg = "text", pressed = "segment", weight = "Medium" },
		Text = { bg = nil, fg = "accent", weight = "SemiBold" },
		Danger = { bg = "danger", fg = "dangerInk", weight = "SemiBold" },
	}
	Controls.ButtonVariants = VARIANTS

	local function makeButton(control, spec, parent, order)
		local variant = VARIANTS[spec.Variant or "Secondary"] or VARIANTS.Secondary
		local button = New("TextButton", {
			Name = "Button",
			Size = Theme.sz(1, 0, 0, "button"),
			BackgroundColor3 = variant.bg and C(variant.bg) or C("raised"),
			BackgroundTransparency = variant.bg and 0 or 1,
			LayoutOrder = order or 1,
			Parent = parent,
		}, {
			Create.corner("rControl"),
			Create.pad(0, 12),
			Create.list("Horizontal", 8, { align = "Center", valign = "Center" }),
		})
		if variant.gradient then
			button.BackgroundColor3 = Color3.new(1, 1, 1)
			New("UIGradient", { Color = Theme.gradient(), Parent = button })
		end
		if spec.Icon then
			local icon = Icons.new(spec.Icon, "iconSmall", C(variant.fg))
			icon.Frame.LayoutOrder = 1
			icon.Frame.Parent = button
		end
		local label = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C(variant.fg),
			Weight = variant.weight,
			LayoutOrder = 2,
			Parent = button,
		})
		label.TextTruncate = Enum.TextTruncate.AtEnd
		control.Loc:Bind(label, "Text", spec.Title or spec.Text or "")
		Motion.pressable(button, nil, 0.97, control.Maid)
		if variant.pressed then
			control.Maid:Add(button.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					Theme.set(button, "BackgroundColor3", C(variant.pressed), "press")
				end
			end))
			control.Maid:Add(button.InputEnded:Connect(function()
				Theme.set(button, "BackgroundColor3", C(variant.bg), "fade")
			end))
		end
		local function run()
			if not control.Enabled then
				return
			end
			local callback = spec.Callback
			if not callback then
				return
			end
			if spec.Confirm then
				local confirm = type(spec.Confirm) == "table" and spec.Confirm or {}
				control.Window:Dialog({
					Title = confirm.Title or (type(spec.Confirm) ~= "table" and spec.Confirm ~= true and spec.Confirm) or spec.Title or spec.Text,
					Content = confirm.Content,
					Buttons = {
						{ Text = { __lib = "cancel" }, Variant = "Secondary" },
						{ Text = confirm.Confirm or spec.Title or spec.Text or { __lib = "ok" }, Variant = spec.Variant == "Danger" and "Danger" or "Primary", Callback = function()
							task.spawn(callback)
						end },
					},
				})
			else
				task.spawn(callback)
			end
		end
		control.Maid:Add(button.Activated:Connect(run))
		return button, run
	end

	local Button = Control.extend("Button")

	function Controls.Button(section, opts)
		local self = Control.new(section, opts, { class = Button, kind = "Button", layout = "custom" })
		self.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
		Create.list("Vertical", 6).Parent = self.Inner
		local button, run = makeButton(self, opts, self.Inner, 1)
		self.Button = button
		self._run = run
		if self.DescSpec then
			local desc = Create.text("", { size = "fontDesc", color = "textSubtle", wrap = true, order = 2 })
			desc.Parent = self.Inner
			self.Loc:Bind(desc, "Text", self.DescSpec)
		end
		return self
	end

	function Button:QuickActivate()
		self._run()
		return nil
	end

	function Button:QuickState()
		return "action"
	end

	-- Buttons: several buttons in one row ------------------------------------------------

	local Buttons = Control.extend("Buttons")

	function Controls.Buttons(section, opts)
		local list = opts.Buttons or opts
		local self = Control.new(section, { Title = opts.Title }, { class = Buttons, kind = "Buttons", layout = "custom", searchable = false })
		self.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
		Create.list("Horizontal", 8).Parent = self.Inner
		self.Buttons = {}
		for index, spec in ipairs(list) do
			local button = makeButton(self, spec, self.Inner, index)
			button.Size = UDim2.new(0, 0, 0, 0)
			Theme.bind(button, "Size", Theme.sz(0, 0, 0, "button"))
			Create.flex().Parent = button
			table.insert(self.Buttons, button)
		end
		return self
	end

	-- Label & Paragraph ----------------------------------------------------------------

	local Label = Control.extend("Label")

	function Controls.Label(section, opts)
		if type(opts) ~= "table" then
			opts = { Title = opts }
		end
		local self = Control.new(section, opts, { class = Label, kind = "Label", titleWeight = "SemiBold", searchable = false })
		return self
	end

	function Label:SetText(spec)
		return self:SetTitle(spec)
	end

	local Paragraph = Control.extend("Paragraph")

	function Controls.Paragraph(section, opts)
		if type(opts) ~= "table" then
			opts = { Content = opts }
		end
		local self = Control.new(section, { Title = opts.Title, VisibleWhen = opts.VisibleWhen }, {
			class = Paragraph, kind = "Paragraph", layout = "stack", titleWeight = "SemiBold", searchable = false,
		})
		if not opts.Title then
			self.Inner:FindFirstChild("Top").Visible = false
		end
		self.Content = Create.text("", { size = "fontDesc", color = "textMuted", wrap = true })
		self.Content.LineHeight = 1.15
		self.Content.RichText = opts.RichText == true
		self.Content.Parent = self.Body
		self.Loc:Bind(self.Content, "Text", opts.Content or opts.Text or "", opts.Vars)
		return self
	end

	function Paragraph:SetContent(spec, vars)
		self.Loc:Bind(self.Content, "Text", spec, vars)
		return self
	end

	-- Divider ------------------------------------------------------------------------------

	local Divider = Control.extend("Divider")

	function Controls.Divider(section, opts)
		local self = Control.new(section, type(opts) == "table" and opts or {}, { class = Divider, kind = "Divider", layout = "custom", searchable = false })
		self.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
		self.Inner:FindFirstChildOfClass("UIPadding"):Destroy()
		New("Frame", { Size = UDim2.new(1, 0, 0, 6), Parent = self.Inner })
		self.Divider.Visible = false
		self._noDivider = true
		return self
	end

	-- Badge ----------------------------------------------------------------------------------

	local BADGES = {
		accent = { bg = "accent", fg = "accentInk", alpha = 0 },
		neutral = { bg = "raised", fg = "textMuted", alpha = 0 },
		success = { bg = "success", fg = "success", alpha = 0.88 },
		warning = { bg = "warning", fg = "warning", alpha = 0.88 },
		danger = { bg = "danger", fg = "danger", alpha = 0.88 },
	}
	Controls.BadgeStyles = BADGES

	function Controls.makeBadge(loc, text, variant, order)
		local style = BADGES[variant or "neutral"] or BADGES.neutral
		local badge = New("TextLabel", {
			Name = "Badge",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = C(style.bg),
			BackgroundTransparency = style.alpha,
			TextColor3 = C(style.fg),
			Weight = "SemiBold",
			TextSize = S("fontSmall"),
			LayoutOrder = order or 0,
		}, { Create.corner("rBadge"), Create.pad(3, 8) })
		loc:Bind(badge, "Text", text or "")
		return badge
	end

	local Badge = Control.extend("Badge")

	function Controls.Badge(section, opts)
		local self = Control.new(section, opts, { class = Badge, kind = "Badge", searchable = false })
		self.Badge = Controls.makeBadge(self.Loc, opts.Text or opts.Value or "", opts.Variant or "accent", 5)
		self.Badge.Parent = self.Right
		return self
	end

	function Badge:SetText(spec, variant)
		self.Loc:Bind(self.Badge, "Text", spec)
		if variant and BADGES[variant] then
			local style = BADGES[variant]
			Theme.bind(self.Badge, "BackgroundColor3", C(style.bg))
			Theme.bind(self.Badge, "TextColor3", C(style.fg))
			self.Badge.BackgroundTransparency = style.alpha
		end
		return self
	end

	-- Image ----------------------------------------------------------------------------------

	local Image = Control.extend("Image")

	function Controls.Image(section, opts)
		local self = Control.new(section, opts, { class = Image, kind = "Image", layout = "stack", searchable = false })
		if not opts.Title then
			self.Inner:FindFirstChild("Top").Visible = false
		end
		self.Image = New("ImageLabel", {
			Size = UDim2.new(1, 0, 0, opts.Height or 140),
			BackgroundColor3 = C("sunken"),
			Image = opts.Image or "",
			ScaleType = Enum.ScaleType[opts.ScaleType or "Fit"],
			Parent = self.Body,
		}, { Create.corner("rControl") })
		return self
	end

	function Image:SetImage(image)
		self.Image.Image = image
		return self
	end

	-- ProgressBar --------------------------------------------------------------------------

	local Progress = Control.extend("ProgressBar")

	function Controls.ProgressBar(section, opts)
		local self = Control.new(section, opts, { class = Progress, kind = "ProgressBar", layout = "stack", searchable = false })
		self.Max = opts.Max or 100
		self.ValueLabel = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			TextSize = S("fontDesc"),
			LayoutOrder = 5,
			Parent = self.Right,
		})
		local track = New("Frame", {
			Size = Theme.sz(1, 0, 0, "track"),
			BackgroundColor3 = C("track"),
			Parent = self.Body,
		}, { Create.corner("full") })
		self.Fill = New("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = track,
		}, { Create.corner("full"), New("UIGradient", { Color = Theme.gradient() }) })
		self.Value = 0
		self:SetValue(opts.Value or opts.Default or 0, false)
		return self
	end

	function Progress:SetValue(value, animate)
		self.Value = math.clamp(tonumber(value) or 0, 0, self.Max)
		local ratio = self.Max > 0 and self.Value / self.Max or 0
		if animate == false then
			self.Fill.Size = UDim2.fromScale(ratio, 1)
		else
			Motion.tween(self.Fill, { Size = UDim2.fromScale(ratio, 1) }, "window")
		end
		if self.Options.Format then
			self.ValueLabel.Text = self.Options.Format(self.Value, self.Max)
		else
			self.ValueLabel.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
		end
		return self
	end
	Progress.Set = Progress.SetValue

	function Progress:Get()
		return self.Value
	end

	-- Code -------------------------------------------------------------------------------------

	local Code = Control.extend("Code")

	function Controls.Code(section, opts)
		local self = Control.new(section, opts, { class = Code, kind = "Code", layout = "custom", searchable = false })
		self.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
		self.Text = opts.Code or opts.Content or ""
		local block = New("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C("code"),
			Parent = self.Inner,
		}, { Create.corner(12), Create.stroke("border"), Create.list("Vertical", 0) })
		local head = New("Frame", {
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = 1,
			Parent = block,
		}, { Create.pad(0, 6, 0, 12), Create.list("Horizontal", 6, { valign = "Center" }) })
		local lang = New("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C("textSubtle"),
			TextSize = 12,
			LayoutOrder = 1,
			Parent = head,
		}, { Create.flex() })
		self.Loc:Bind(lang, "Text", opts.Title or opts.Language or "Luau")
		local copy, copyLabel, copyIcon = Control.chip({
			icon = "copy", size = UDim2.fromOffset(0, 26), bg = C("overlay"), padLeft = 8, padRight = 8,
			textSize = 12, iconSize = 13, iconColor = C("text"), order = 2,
		})
		copy.Parent = head
		copyIcon.Frame.LayoutOrder = 0
		self.Loc:Bind(copyLabel, "Text", { __lib = "copy" })
		Motion.pressable(copy, nil, nil, self.Maid)
		New("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C("border"), LayoutOrder = 2, Parent = block })
		self.CodeLabel = New("TextLabel", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = self.Text,
			TextColor3 = C("codeText"),
			TextSize = 12,
			Mono = true,
			TextWrapped = true,
			LineHeight = 1.25,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 3,
			Parent = block,
		}, { Create.pad(12) })
		self.Maid:Add(copy.Activated:Connect(function()
			if Compat.clipboard(self.Text) then
				self.Window:Notify({ Title = { __lib = "copied" }, Type = "success", Duration = 2 })
			else
				self.Window:Dialog({
					Title = { __lib = "copy_failed" },
					Input = { Default = self.Text, Mono = true },
					Buttons = { { Text = { __lib = "ok" }, Variant = "Primary" } },
				})
			end
		end))
		return self
	end

	function Code:SetCode(text)
		self.Text = tostring(text)
		self.CodeLabel.Text = self.Text
		return self
	end

	return Controls
end

__modules["controls/ColorPicker"] = function()
	-- ColorPicker: swatch in the row; popup with saturation/value square (two
	-- UIGradients), hue bar, HEX field and quick swatches.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Device = import("core/Device")
	local Services = import("core/Services")
	local Util = import("util/Util")
	local Control = import("controls/Base")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local ColorPicker = Control.extend("ColorPicker")

	local SWATCHES = { "FF3B7F", "4C8DFF", "34D399", "F5A524", "A78BFA", "F2F2F5" }

	local function toColor(value)
		if typeof(value) == "Color3" then
			return value
		end
		return Util.hex(value)
	end

	local function constructor(section, opts)
		local default = toColor(opts.Default) or Color3.fromRGB(255, 59, 127)
		local self = Control.new(section, opts, {
			class = ColorPicker, kind = "ColorPicker", value = true, default = default,
			validate = function(v)
				return toColor(v)
			end,
		})
		self.HexLabel = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			Mono = true,
			TextColor3 = C("textMuted"),
			TextSize = 12,
			LayoutOrder = 4,
			Parent = self.Right,
		})
		local swatch = New("TextButton", {
			Name = "Swatch",
			Size = Theme.f(function(_, s)
				local size = s.touch and 36 or 28
				return UDim2.fromOffset(size, size)
			end),
			BackgroundColor3 = default,
			LayoutOrder = 5,
			Parent = self.Right,
		}, { Create.corner(8), Create.stroke("borderStrong") })
		self.Swatch = swatch
		Motion.pressable(swatch, nil, 0.92, self.Maid)
		self.Maid:Add(swatch.Activated:Connect(function()
			if self.Enabled then
				self:Open()
			end
		end))
		self:_finish()
		return self
	end

	function ColorPicker:_validate(value)
		return toColor(value) or self:Get()
	end

	function ColorPicker:_render(color)
		if typeof(color) ~= "Color3" then
			return
		end
		self.Swatch.BackgroundColor3 = color
		self.HexLabel.Text = "#" .. Util.toHex(color)
		if self._sync then
			self._sync(color)
		end
	end

	function ColorPicker:StateText()
		return self.HexLabel.Text
	end

	-- Generic 1D/2D drag area: fn(rx, ry) with ratios 0..1
	local function dragArea(area, maid, fn)
		local active = nil
		local function update(input)
			local p = Device.pointer(input)
			local ap, as = area.AbsolutePosition, area.AbsoluteSize
			fn(math.clamp((p.X - ap.X) / math.max(as.X, 1), 0, 1), math.clamp((p.Y - ap.Y) / math.max(as.Y, 1), 0, 1))
		end
		maid:Add(area.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			update(input)
			if active then
				for _, c in ipairs(active) do
					c:Disconnect()
				end
			end
			local uis = Services.UserInputService
			local connections
			connections = {
				uis.InputChanged:Connect(function(changed)
					if changed.UserInputType == Enum.UserInputType.MouseMovement or (changed == input) then
						update(changed)
					end
				end),
				uis.InputEnded:Connect(function(ended)
					if ended == input or ended.UserInputType == Enum.UserInputType.MouseButton1 then
						for _, c in ipairs(connections) do
							c:Disconnect()
						end
						active = nil
					end
				end),
			}
			active = connections
		end))
		maid:Add(function()
			if active then
				for _, c in ipairs(active) do
					c:Disconnect()
				end
			end
		end)
	end

	function ColorPicker:Open()
		local window = self.Window
		local h, s, v = self:Get():ToHSV()
		window.Popup:Open({
			anchor = self.Swatch,
			width = 260,
			padding = 12,
			onClose = function()
				self._sync = nil
			end,
			build = function(container, handle)
				container:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 12)
				local square = New("TextButton", {
					Name = "SV",
					Size = UDim2.new(1, 0, 0, 150),
					BackgroundColor3 = Color3.fromHSV(h, 1, 1),
					LayoutOrder = 1,
					Parent = container,
				}, { Create.corner(10) })
				New("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.new(1, 1, 1),
					Parent = square,
				}, {
					Create.corner(10),
					New("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
				})
				New("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.new(0, 0, 0),
					Parent = square,
				}, {
					Create.corner(10),
					New("UIGradient", { Transparency = NumberSequence.new(1, 0), Rotation = 90 }),
				})
				local svKnob = New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(18, 18),
					BackgroundTransparency = 1,
					ZIndex = 3,
					Parent = square,
				}, { Create.corner("full"), Create.stroke(Color3.new(1, 1, 1), 3) })

				local keypoints = {}
				for i = 0, 6 do
					table.insert(keypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)))
				end
				local hue = New("TextButton", {
					Name = "Hue",
					Size = UDim2.new(1, 0, 0, 14),
					BackgroundColor3 = Color3.new(1, 1, 1),
					LayoutOrder = 2,
					Parent = container,
				}, { Create.corner("full"), New("UIGradient", { Color = ColorSequence.new(keypoints) }) })
				local hueKnob = New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(h, 0.5),
					Size = UDim2.fromOffset(18, 18),
					BackgroundTransparency = 1,
					Parent = hue,
				}, { Create.corner("full"), Create.stroke(Color3.new(1, 1, 1), 3) })

				local row = New("Frame", {
					Size = UDim2.new(1, 0, 0, 34),
					LayoutOrder = 3,
					Parent = container,
				}, { Create.list("Horizontal", 8, { valign = "Center" }) })
				local preview = New("Frame", {
					Size = UDim2.fromOffset(34, 34),
					BackgroundColor3 = self:Get(),
					Parent = row,
				}, { Create.corner(9) })
				local hexField = New("Frame", {
					Size = UDim2.fromScale(0, 1),
					BackgroundColor3 = C("bg"),
					LayoutOrder = 2,
					Parent = row,
				}, { Create.corner(9), Create.stroke("borderStrong"), Create.pad(0, 10), Create.flex() })
				local hexBox = New("TextBox", {
					Size = UDim2.fromScale(1, 1),
					Mono = true,
					TextSize = 12.5,
					Text = "#" .. Util.toHex(self:Get()),
					Parent = hexField,
				})

				local swatches = New("Frame", {
					Size = UDim2.new(1, 0, 0, 24),
					LayoutOrder = 4,
					Parent = container,
				}, { Create.list("Horizontal", 8, { valign = "Center" }) })

				local function commit()
					self:Set(Color3.fromHSV(h, s, v))
				end
				local function sync(color)
					local nh, ns, nv = color:ToHSV()
					if ns > 0.001 and nv > 0.001 then
						h = nh
					end
					s, v = ns, nv
					square.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
					svKnob.Position = UDim2.fromScale(s, 1 - v)
					hueKnob.Position = UDim2.fromScale(h, 0.5)
					preview.BackgroundColor3 = color
					if not hexBox:IsFocused() then
						hexBox.Text = "#" .. Util.toHex(color)
					end
				end
				self._sync = sync
				sync(self:Get())

				dragArea(square, handle.maid, function(rx, ry)
					s, v = rx, 1 - ry
					svKnob.Position = UDim2.fromScale(s, 1 - v)
					commit()
				end)
				dragArea(hue, handle.maid, function(rx)
					h = math.min(rx, 0.999)
					hueKnob.Position = UDim2.fromScale(h, 0.5)
					square.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
					commit()
				end)
				handle.maid:Add(hexBox.FocusLost:Connect(function()
					local color = Util.hex(hexBox.Text)
					if color then
						self:Set(color)
					else
						hexBox.Text = "#" .. Util.toHex(self:Get())
					end
				end))

				for index, hex in ipairs(self.Options.Swatches or SWATCHES) do
					local color = toColor(hex)
					local dot = New("TextButton", {
						Size = UDim2.fromOffset(24, 24),
						BackgroundColor3 = color,
						LayoutOrder = index,
						Parent = swatches,
					}, { Create.corner("full"), Create.stroke("borderStrong") })
					Motion.pressable(dot, nil, 0.85, handle.maid)
					handle.maid:Add(dot.Activated:Connect(function()
						self:Set(color)
					end))
				end
			end,
		})
	end

	return constructor
end

__modules["controls/Dropdown"] = function()
	-- Dropdown: single or multiple choice, optional search inside the list.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Util = import("util/Util")
	local Control = import("controls/Base")
	local Value = import("controls/Value")
	local Basic = import("controls/Basic")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Dropdown = Control.extend("Dropdown")

	local function constructor(section, opts)
		local options = Value.normalizeOptions(opts.Options or opts.Values)
		local multi = opts.Multi == true or opts.Multiple == true
		local default = opts.Default
		if multi then
			if type(default) ~= "table" then
				default = default ~= nil and { default } or {}
			end
		elseif default == nil and not opts.AllowNone and options[1] then
			default = options[1].Value
		end
		local self = Control.new(section, opts, {
			class = Dropdown, kind = "Dropdown", value = true, default = default,
		})
		self.Items = options
		self.Multi = multi

		local button = New("TextButton", {
			Name = "Select",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = Theme.sz(0, 0, 0, "control"),
			BackgroundColor3 = C("raised"),
			LayoutOrder = 5,
			Parent = self.Right,
		}, {
			Create.corner("rSmall"),
			Create.list("Horizontal", 6, { valign = "Center" }),
		})
		local padding = Create.pad(0, 8, 0, 12)
		padding.Parent = button
		Theme.bind(button, "BackgroundTransparency", Theme.f(function(_, s)
			return s.dropdownFlat and 1 or 0
		end))
		Theme.bind(padding, "PaddingLeft", Theme.f(function(_, s)
			return UDim.new(0, s.dropdownFlat and 4 or 12)
		end))
		Theme.bind(padding, "PaddingRight", Theme.f(function(_, s)
			return UDim.new(0, s.dropdownFlat and 0 or 8)
		end))
		self.Button = button
		self.ValueLabel = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
			Parent = button,
		}, { Create.maxSize(opts.MaxWidth or 170, nil) })
		Theme.bind(self.ValueLabel, "TextColor3", Theme.f(function(c, s)
			return s.dropdownFlat and c.textMuted or c.text
		end))
		self.CountBadge = Basic.makeBadge(self.Loc, "", "accent", 2)
		self.CountBadge.Parent = button
		self.CountBadge.Visible = false
		local chevron = Icons.new("chevronDown", 16, C("textMuted"))
		chevron.Frame.LayoutOrder = 3
		chevron.Frame.Parent = button
		Motion.pressable(button, nil, 0.97, self.Maid)
		-- long values are cut with "…"; the full text is in a tooltip
		local function truncated()
			return not self.ValueLabel.TextFits
		end
		self.Window.Tooltip:Attach(button, function()
			return self:DisplayText()
		end, self.Maid, nil, truncated)

		self.Maid:Add(button.Activated:Connect(function()
			if self.Enabled then
				self:Open()
			end
		end))
		self.Maid:Add(self.Loc.Changed:Connect(function()
			self:_render(self:Get())
		end))
		self:_finish()
		return self
	end

	function Dropdown:_validate(value)
		if self.Multi then
			local out = {}
			for _, v in ipairs(type(value) == "table" and value or { value }) do
				if self:_find(v) then
					table.insert(out, v)
				end
			end
			return out
		end
		if value == nil and self.Options.AllowNone then
			return nil
		end
		if self:_find(value) then
			return value
		end
		return self:Get()
	end

	function Dropdown:_find(value)
		for _, option in ipairs(self.Items) do
			if option.Value == value then
				return option
			end
		end
		return nil
	end

	function Dropdown:_isSelected(value)
		local current = self:Get()
		if self.Multi then
			return type(current) == "table" and table.find(current, value) ~= nil
		end
		return current == value
	end

	function Dropdown:DisplayText()
		local current = self:Get()
		if self.Multi then
			local names = {}
			for _, option in ipairs(self.Items) do
				if type(current) == "table" and table.find(current, option.Value) then
					table.insert(names, self.Loc:Get(option.Text))
				end
			end
			if #names == 0 then
				return self.Options.Placeholder and self.Loc:Get(self.Options.Placeholder) or self.Loc:Lib("none")
			end
			return table.concat(names, ", ")
		end
		local option = self:_find(current)
		if option then
			return self.Loc:Get(option.Text)
		end
		return self.Options.Placeholder and self.Loc:Get(self.Options.Placeholder) or self.Loc:Lib("none")
	end

	function Dropdown:_render(value)
		self.ValueLabel.Text = self:DisplayText()
		if self.Multi then
			local count = type(value) == "table" and #value or 0
			self.CountBadge.Visible = count > 1
			self.CountBadge.Text = tostring(count)
		end
		if self._refreshList then
			self._refreshList()
		end
	end

	function Dropdown:StateText()
		return self:DisplayText()
	end

	function Dropdown:Open()
		local window = self.Window
		local loc = self.Loc
		local showSearch = self.Options.Search == true or (self.Options.Search ~= false and #self.Items > 8)
		local width = math.max(self.Button.AbsoluteSize.X, Theme.Sizes.touch and 240 or 220)
		window.Popup:Open({
			anchor = self.Button,
			width = width,
			onClose = function()
				self._refreshList = nil
			end,
			build = function(container, handle)
				local query = ""
				if showSearch then
					local field = New("Frame", {
						Size = Theme.sz(1, 0, 0, "item"),
						BackgroundColor3 = C("bg"),
						LayoutOrder = 1,
						Parent = container,
					}, { Create.corner(8), Create.pad(0, 10), Create.list("Horizontal", 8, { valign = "Center" }) })
					local icon = Icons.new("search", 14, C("textSubtle"))
					icon.Frame.Parent = field
					local box = New("TextBox", {
						Size = UDim2.fromScale(0, 1),
						LayoutOrder = 2,
						Parent = field,
					}, { Create.flex() })
					loc:Bind(box, "PlaceholderText", self.Options.SearchPlaceholder or { __lib = "search_list" })
					handle.maid:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
						query = Util.lower(box.Text)
						if handle.refresh then
							handle.refresh()
						end
					end))
					if not Theme.Sizes.touch then
						task.defer(function()
							if box.Parent then
								box:CaptureFocus()
							end
						end)
					end
				end
				local itemHeight = Theme.Sizes.item
				local maxHeight = math.min(#self.Items * (itemHeight + 2), self.Options.MaxHeight or 260)
				local list = New("ScrollingFrame", {
					Size = UDim2.new(1, 0, 0, maxHeight),
					LayoutOrder = 2,
					Parent = container,
				}, { Create.list("Vertical", 2) })
				local rows = {}
				for index, option in ipairs(self.Items) do
					local row = New("TextButton", {
						Size = Theme.sz(1, 0, 0, "item"),
						BackgroundColor3 = C("raised"),
						BackgroundTransparency = 1,
						LayoutOrder = index,
						Parent = list,
					}, { Create.corner(8), Create.pad(0, 10), Create.list("Horizontal", 10, { valign = "Center" }) })
					if option.Icon then
						local icon = Icons.new(option.Icon, "iconSmall", C("textMuted"))
						icon.Frame.Parent = row
					end
					local label = New("TextLabel", {
						Size = UDim2.fromScale(0, 1),
						TextTruncate = Enum.TextTruncate.AtEnd,
						LayoutOrder = 2,
						Parent = row,
					}, { Create.flex() })
					Theme.bind(label, "TextSize", Theme.f(function(_, s)
						return s.font - 1
					end))
					loc:Bind(label, "Text", option.Text)
					local check = Icons.new("check", 16, C("accent"))
					check.Frame.LayoutOrder = 3
					check.Frame.Parent = row
					rows[index] = { row = row, check = check, option = option, label = label }
					handle.maid:Add(row.MouseEnter:Connect(function()
						Motion.tween(row, { BackgroundTransparency = 0 }, "fade")
					end))
					handle.maid:Add(row.MouseLeave:Connect(function()
						Motion.tween(row, { BackgroundTransparency = 1 }, "fade")
					end))
					handle.maid:Add(row.Activated:Connect(function()
						if self.Multi then
							local current = table.clone(self:Get() or {})
							local at = table.find(current, option.Value)
							if at then
								table.remove(current, at)
							else
								table.insert(current, option.Value)
							end
							self:Set(current)
						else
							if self.Options.AllowNone and self:Get() == option.Value then
								self:Set(nil)
							else
								self:Set(option.Value)
							end
							handle.Close()
						end
					end))
				end
				function handle.refresh()
					local visible = 0
					for _, entry in ipairs(rows) do
						local match = query == ""
						if not match then
							local text = Util.lower(entry.label.Text)
							match = text:find(query, 1, true) ~= nil or Util.lower(tostring(entry.option.Value)):find(query, 1, true) ~= nil
						end
						entry.row.Visible = match
						if match then
							visible += 1
						end
						entry.check.Frame.Visible = self:_isSelected(entry.option.Value)
					end
					list.Size = UDim2.new(1, 0, 0, math.max(math.min(visible * (itemHeight + 2), self.Options.MaxHeight or 260), itemHeight))
				end
				self._refreshList = handle.refresh
				handle.refresh()
			end,
		})
	end

	function Dropdown:Close()
		self.Window.Popup:Close()
	end

	-- Replace the option list. Keeps the selection when still valid.
	function Dropdown:SetOptions(list, value)
		self.Items = Value.normalizeOptions(list)
		local current = value
		if current == nil then
			current = self:Get()
		end
		local fixed
		if self.Multi then
			fixed = self:_validate(current)
		elseif self:_find(current) then
			fixed = current
		elseif not self.Options.AllowNone and self.Items[1] then
			fixed = self.Items[1].Value
		end
		if not self.Store:Set(self.Flag, fixed, "api") then
			self:_render(self:Get())
		end
		return self
	end
	Dropdown.Refresh = Dropdown.SetOptions

	return constructor
end

__modules["controls/Keybind"] = function()
	-- Keybind: key chip with capture, conflict checks (game + other binds) and
	-- registration in the bind panel.
	--   section:Keybind({
	--     Title = "Teleport to quest", Default = "Q",            -- "Ctrl+X", Enum.KeyCode.Q
	--     Mode = "Action" | "Toggle" | "Hold",
	--     Target = "autoFarm",       -- Toggle mode: flips this flag (a Toggle's Flag)
	--     Callback = function(state) end,  -- runs on key press
	--     Changed = function(key) end,     -- runs when the player assigns a new key
	--     Cooldown = 3, ShowInHud = true,
	--   })

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Control = import("controls/Base")
	local Binds = import("system/Binds")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Keybind = Control.extend("Keybind")

	local function validate(value)
		if type(value) == "table" then
			return { Key = Binds.normalize(value.Key), Override = value.Override == true }
		end
		return { Key = Binds.normalize(value), Override = false }
	end

	local function constructor(section, opts)
		local baseOpts = table.clone(opts)
		baseOpts.Callback = opts.Changed and function(value)
			opts.Changed(value.Key)
		end or nil
		local self = Control.new(section, baseOpts, {
			class = Keybind, kind = "Keybind", value = true,
			default = validate(opts.Default), persist = opts.System and "ui" or nil,
			validate = validate,
		})
		local chip = New("TextButton", {
			Name = "Key",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = Theme.sz(0, 0, 0, "chip"),
			BackgroundColor3 = C("sunken"),
			LayoutOrder = 5,
			Parent = self.Right,
		}, {
			Create.corner(8),
			Create.pad(0, 10),
			Create.list("Horizontal", 6, { valign = "Center" }),
			Create.minSize(36, 0),
		})
		self.Stroke = Create.stroke("segment", 1)
		self.Stroke.Parent = chip
		self.Warning = Icons.new("warning", 14, C("warning"))
		self.Warning.Frame.LayoutOrder = 0
		self.Warning.Frame.Visible = false
		self.Warning.Frame.Parent = chip
		self.KeyLabel = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			Mono = true,
			TextSize = 12,
			LayoutOrder = 1,
			Parent = chip,
		})
		self.Chip = chip
		Motion.pressable(chip, nil, 0.95, self.Maid)
		self.Maid:Add(chip.Activated:Connect(function()
			if self.Enabled then
				self:StartCapture()
			end
		end))

		self.Entry = self.Window.Binds:Add({
			Flag = self.Flag,
			Title = opts.HudTitle or self.TitleSpec,
			Mode = opts.Mode,
			Target = opts.Target,
			Callback = opts.Callback,
			Cooldown = opts.Cooldown,
			ShowInHud = opts.ShowInHud ~= false,
			System = opts.System == true,
			Control = self,
		})
		self.Maid:Add(function()
			self.Window.Binds:Remove(self.Entry)
		end)
		self.Maid:Add(self.Loc.Changed:Connect(function()
			self:_render(self:Get())
		end))
		self:_finish()
		return self
	end

	function Keybind:_validate(value)
		return validate(value)
	end

	function Keybind:_render(value)
		if self.Capturing then
			return
		end
		local key = type(value) == "table" and value.Key or ""
		self.KeyLabel.FontFace = Theme.font("Regular", true)
		self.KeyLabel.Text = Binds.display(key) or self.Loc:Lib("none")
		Theme.bind(self.KeyLabel, "TextColor3", key ~= "" and C("text") or C("textSubtle"))
		Theme.bind(self.Chip, "BackgroundColor3", C("sunken"))
		Theme.bind(self.Stroke, "Color", C("segment"))
		self.Stroke.Thickness = 1
		self.Warning.Frame.Visible = key ~= "" and not value.Override and self.Window.Binds:GameConflict(key)
	end

	function Keybind:StartCapture()
		local binds = self.Window.Binds
		self.Capturing = true
		self.KeyLabel.FontFace = Theme.font("SemiBold")
		self.KeyLabel.Text = self.Loc:Lib("press_key")
		Theme.set(self.KeyLabel, "TextColor3", C("accent"))
		Theme.set(self.Stroke, "Color", C("accent"))
		self.Stroke.Thickness = 1.5
		self.Chip.BackgroundTransparency = 0
		Theme.set(self.Chip, "BackgroundColor3", Theme.f(function(c)
			return c.accent:Lerp(c.sunken, 0.88)
		end))
		binds:Capture(function(key)
			self.Capturing = false
			if key == nil or self.Destroyed then
				self:_render(self:Get())
				return
			end
			self:_assign(key)
		end)
	end

	function Keybind:_assign(key)
		local binds = self.Window.Binds
		local window = self.Window
		if key == "" then
			self:Set({ Key = "", Override = false })
			self:_render(self:Get())
			return
		end
		local other = binds:BindConflict(key, self.Entry)
		if other then
			window:Dialog({
				Title = { __lib = "key_taken_bind" },
				Vars = { key = Binds.display(key), name = self.Loc:Get(other.Title) },
				Content = { __lib = "key_taken_bind_desc" },
				Buttons = {
					{ Text = { __lib = "other_key" }, Variant = "Secondary", Callback = function()
						task.defer(function()
							self:StartCapture()
						end)
					end },
					{ Text = { __lib = "replace" }, Variant = "Primary", Callback = function()
						self.Store:Set(other.Flag, { Key = "", Override = false }, "api")
						self:_assignGame(key)
					end },
				},
			})
			return
		end
		self:_assignGame(key)
	end

	function Keybind:_assignGame(key)
		local window = self.Window
		if self.Window.Binds:GameConflict(key) then
			local chosen = false
			window:Dialog({
				Title = { __lib = "key_taken_game" },
				Vars = { key = Binds.display(key) },
				Content = { __lib = "key_taken_game_desc" },
				Buttons = {
					{ Text = { __lib = "other_key" }, Variant = "Secondary", Callback = function()
						chosen = true
						task.defer(function()
							self:StartCapture()
						end)
					end },
					{ Text = { __lib = "take_key" }, Variant = "Primary", Callback = function()
						chosen = true
						self:Set({ Key = key, Override = true })
						self:_render(self:Get())
					end },
				},
				OnClose = function()
					if self.Destroyed then
						return
					end
					if not chosen then
						-- Closed without choosing: keep the key; the game keeps priority.
						self:Set({ Key = key, Override = false })
					end
					self:_render(self:Get())
				end,
			})
			return
		end
		self:Set({ Key = key, Override = false })
		self:_render(self:Get())
	end

	function Keybind:GetKey()
		local value = self:Get()
		return value and value.Key or ""
	end

	function Keybind:StateText()
		return Binds.display(self:GetKey())
	end

	function Keybind:QuickState()
		if self.Entry.Target then
			return self.Store:Get(self.Entry.Target) == true
		end
		return "action"
	end

	function Keybind:QuickActivate()
		self.Window.Binds:Trigger(self.Entry, true)
		if self.Entry.Mode == "Hold" then
			self.Window.Binds:Trigger(self.Entry, false)
		end
		return self:QuickState()
	end

	return constructor
end

__modules["controls/Registry"] = function()
	-- Registry of control constructors: Section:<Kind>(opts) for every entry.

	local Basic = import("controls/Basic")
	local Value = import("controls/Value")

	local Registry = {
		Toggle = Basic.Toggle,
		Checkbox = Basic.Checkbox,
		Button = Basic.Button,
		Buttons = Basic.Buttons,
		Label = Basic.Label,
		Paragraph = Basic.Paragraph,
		Divider = Basic.Divider,
		Badge = Basic.Badge,
		Image = Basic.Image,
		ProgressBar = Basic.ProgressBar,
		Code = Basic.Code,
		Slider = Value.Slider,
		Stepper = Value.Stepper,
		Segmented = Value.Segmented,
		Input = Value.Input,
		Textarea = Value.Textarea,
		Dropdown = import("controls/Dropdown"),
		Keybind = import("controls/Keybind"),
		ColorPicker = import("controls/ColorPicker"),
	}

	-- Friendly aliases
	Registry.Switch = Registry.Toggle
	Registry.SegmentedControl = Registry.Segmented
	Registry.TextBox = Registry.Input
	Registry.Progress = Registry.ProgressBar
	Registry.Colorpicker = Registry.ColorPicker
	Registry.Bind = Registry.Keybind

	return Registry
end

__modules["controls/Value"] = function()
	-- Slider (number / range), Stepper, SegmentedControl, Input, Textarea.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Device = import("core/Device")
	local Services = import("core/Services")
	local Util = import("util/Util")
	local Control = import("controls/Base")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Controls = {}

	-- Shared: normalise an options list to { { Value, Text } }.
	function Controls.normalizeOptions(list)
		local out = {}
		for _, option in ipairs(list or {}) do
			if type(option) == "table" and (option.Value ~= nil or option.Text ~= nil or option.Title ~= nil) then
				local value = option.Value
				if value == nil then
					value = option.Text or option.Title
				end
				table.insert(out, { Value = value, Text = option.Text or option.Title or tostring(value), Icon = option.Icon, Description = option.Description })
			else
				table.insert(out, { Value = option, Text = type(option) == "table" and option or tostring(option) })
			end
		end
		return out
	end

	-- Slider ----------------------------------------------------------------------------

	local Slider = Control.extend("Slider")

	function Controls.Slider(section, opts)
		local min, max = opts.Min or 0, opts.Max or 100
		if min > max then
			min, max = max, min
		end
		local step = opts.Step or opts.Increment or 1
		local range = opts.Range == true
		local default = opts.Default
		if range then
			default = type(default) == "table" and default or { min, max }
		else
			default = tonumber(default) or min
		end
		local self = Control.new(section, opts, {
			class = Slider, kind = "Slider", value = true, default = default, layout = "stack",
			validate = function(v)
				if range then
					if type(v) ~= "table" then
						return nil
					end
					return { math.clamp(tonumber(v[1]) or min, min, max), math.clamp(tonumber(v[2]) or max, min, max) }
				end
				return math.clamp(tonumber(v) or min, min, max)
			end,
		})
		self.Min, self.Max, self.Step, self.IsRange = min, max, step, range

		self.ValueLabel = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundColor3 = C("accent"),
			BackgroundTransparency = 0.86,
			TextColor3 = C("accent"),
			Weight = "SemiBold",
			TextSize = S("fontDesc"),
			LayoutOrder = 5,
			Parent = self.Right,
		}, { Create.corner(6), Create.pad(0, 7) })
		self.ValueLabel.TextXAlignment = Enum.TextXAlignment.Center
		Theme.bind(self.ValueLabel, "TextSize", Theme.f(function(_, s)
			return s.font - 1
		end))

		local area = New("TextButton", {
			Name = "Area",
			Size = Theme.sz(1, 0, 0, "sliderHit"),
			BackgroundTransparency = 1,
			Parent = self.Body,
		})
		self.Area = area
		local track = New("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = Theme.sz(1, 0, 0, "track"),
			BackgroundColor3 = C("track"),
			Parent = area,
		}, { Create.corner("full") })
		self.Fill = New("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = track,
		}, { Create.corner("full"), New("UIGradient", { Color = Theme.gradient() }) })

		local function knob()
			local k = New("Frame", {
				Name = "Knob",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = Theme.sz(0, "sliderKnob", 0, "sliderKnob"),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 2,
				Parent = area,
			}, { Create.corner("full") })
			local stroke = Create.stroke("borderStrong", 1)
			Theme.bind(stroke, "Transparency", Theme.f(function(_, s)
				return s.touch and 0 or 1
			end))
			stroke.Parent = k
			New("UIScale", { Parent = k })
			return k
		end
		self.Knobs = { knob() }
		if range then
			table.insert(self.Knobs, knob())
		end

		-- dragging
		local dragging, active = nil, 1
		local function valueAt(x)
			local ap, as = area.AbsolutePosition.X, area.AbsoluteSize.X
			local ratio = as > 0 and math.clamp((x - ap) / as, 0, 1) or 0
			return Util.snap(min + ratio * (max - min), step, min)
		end
		local function apply(x)
			local value = valueAt(x)
			if range then
				local current = self:Get()
				local pair = { current[1], current[2] }
				pair[active] = value
				if pair[1] > pair[2] then
					pair[1], pair[2] = pair[2], pair[1]
					active = 3 - active
				end
				self:Set(pair)
			else
				self:Set(value)
			end
		end
		local function stop()
			if dragging then
				for _, connection in ipairs(dragging) do
					connection:Disconnect()
				end
				dragging = nil
				self.Tab.Page.ScrollingEnabled = true
				for _, k in ipairs(self.Knobs) do
					Motion.tween(k:FindFirstChildOfClass("UIScale"), { Scale = 1 }, "spring")
				end
			end
		end
		self.Maid:Add(stop)
		self.Maid:Add(area.InputBegan:Connect(function(input)
			if not self.Enabled then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			stop()
			local x = Device.pointer(input).X
			if range then
				local current = self:Get()
				local function screenX(v)
					return area.AbsolutePosition.X + (v - min) / math.max(max - min, 1e-9) * area.AbsoluteSize.X
				end
				active = math.abs(x - screenX(current[1])) <= math.abs(x - screenX(current[2])) and 1 or 2
			end
			local scale = self.Knobs[active]:FindFirstChildOfClass("UIScale")
			Motion.tween(scale, { Scale = 1.12 }, "press")
			apply(x)
			-- keep the page from scrolling while the finger drags the knob
			self.Tab.Page.ScrollingEnabled = false
			local uis = Services.UserInputService
			dragging = {
				uis.InputChanged:Connect(function(changed)
					if changed.UserInputType == Enum.UserInputType.MouseMovement or (changed.UserInputType == Enum.UserInputType.Touch and changed == input) then
						apply(Device.pointer(changed).X)
					end
				end),
				uis.InputEnded:Connect(function(ended)
					if ended == input or ended.UserInputType == Enum.UserInputType.MouseButton1 then
						stop()
					end
				end),
			}
		end))
		self:_finish()
		return self
	end

	function Slider:_validate(v)
		if self.IsRange then
			if type(v) ~= "table" then
				return self:Get()
			end
			local a = Util.snap(math.clamp(tonumber(v[1]) or self.Min, self.Min, self.Max), self.Step, self.Min)
			local b = Util.snap(math.clamp(tonumber(v[2]) or self.Max, self.Min, self.Max), self.Step, self.Min)
			return { math.min(a, b), math.max(a, b) }
		end
		return Util.snap(math.clamp(tonumber(v) or self.Min, self.Min, self.Max), self.Step, self.Min)
	end

	function Slider:_format(v)
		local suffix = self.Options.Suffix
		local text = Util.formatNumber(v, self.Step)
		if suffix then
			text ..= " " .. self.Loc:Get(suffix)
		end
		return text
	end

	function Slider:_render(value, animate)
		if value == nil then
			return
		end
		local span = math.max(self.Max - self.Min, 1e-9)
		local a, b
		if self.IsRange then
			a, b = (value[1] - self.Min) / span, (value[2] - self.Min) / span
			self.ValueLabel.Text = Util.formatNumber(value[1], self.Step) .. " – " .. self:_format(value[2])
		else
			a, b = 0, (value - self.Min) / span
			self.ValueLabel.Text = self:_format(value)
		end
		local props = {
			fill = { Position = UDim2.new(a, 0, 0.5, 0), Size = UDim2.fromScale(b - a, 1) },
		}
		local function set(instance, p)
			if animate then
				Motion.tween(instance, p, "press")
			else
				for k, v in pairs(p) do
					instance[k] = v
				end
			end
		end
		set(self.Fill, props.fill)
		if self.IsRange then
			set(self.Knobs[1], { Position = UDim2.fromScale(a, 0.5) })
			set(self.Knobs[2], { Position = UDim2.fromScale(b, 0.5) })
		else
			set(self.Knobs[1], { Position = UDim2.fromScale(b, 0.5) })
		end
	end

	function Slider:StateText()
		return self.ValueLabel.Text
	end

	-- Stepper -----------------------------------------------------------------------------

	local Stepper = Control.extend("Stepper")

	function Controls.Stepper(section, opts)
		local min, max = opts.Min or -math.huge, opts.Max or math.huge
		local step = opts.Step or 1
		local self = Control.new(section, opts, {
			class = Stepper, kind = "Stepper", value = true, default = tonumber(opts.Default) or math.max(0, min),
			validate = function(v)
				return math.clamp(tonumber(v) or 0, min, max)
			end,
		})
		self.Min, self.Max, self.Step = min, max, step
		local box = New("Frame", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = Theme.sz(0, 0, 0, "control"),
			BackgroundColor3 = C("raised"),
			LayoutOrder = 5,
			Parent = self.Right,
		}, { Create.corner("rSmall"), Create.list("Horizontal", 0, { valign = "Center" }) })
		local function stepButton(icon, order, delta)
			local button = New("TextButton", {
				Size = Theme.sz(0, "stepperBtn", 1, 0),
				LayoutOrder = order,
				Parent = box,
			})
			local glyph = Icons.new(icon, 14, C("text"), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			glyph.Frame.Parent = button
			Motion.pressable(button, glyph.Frame, 0.8, self.Maid)
			local holding = 0
			local function bump()
				if self.Enabled then
					self:Set(self:Get() + delta * step)
				end
			end
			self.Maid:Add(button.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				holding += 1
				local mine = holding
				-- stop repeating when this touch/click ends anywhere on screen
				local ended
				ended = Services.UserInputService.InputEnded:Connect(function(other)
					if other == input or other.UserInputType == Enum.UserInputType.MouseButton1 then
						ended:Disconnect()
						if holding == mine then
							holding += 1
						end
					end
				end)
				bump()
				task.delay(0.4, function()
					while holding == mine and not self.Destroyed do
						bump()
						task.wait(0.07)
					end
				end)
			end))
			self.Maid:Add(button.InputEnded:Connect(function()
				holding += 1
			end))
			self.Maid:Add(button.MouseLeave:Connect(function()
				holding += 1
			end))
			return button
		end
		stepButton("minus", 1, -1)
		self.ValueLabel = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			Weight = "SemiBold",
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 2,
			Parent = box,
		}, { Create.minSize(28, 0) })
		self.ValueLabel.TextXAlignment = Enum.TextXAlignment.Center
		stepButton("plus", 3, 1)
		self:_finish()
		return self
	end

	function Stepper:_validate(v)
		local value = math.clamp(tonumber(v) or 0, self.Min, self.Max)
		return Util.snap(value, self.Step, self.Min > -math.huge and self.Min or 0)
	end

	function Stepper:_render(value)
		local text = Util.formatNumber(value, self.Step)
		if self.Options.Suffix then
			text ..= " " .. self.Loc:Get(self.Options.Suffix)
		end
		self.ValueLabel.Text = text
	end

	function Stepper:StateText()
		return self.ValueLabel.Text
	end

	-- SegmentedControl ------------------------------------------------------------------------

	local Segmented = Control.extend("Segmented")

	function Controls.Segmented(section, opts)
		local options = Controls.normalizeOptions(opts.Options or opts.Values)
		local default = opts.Default
		if default == nil and options[1] then
			default = options[1].Value
		end
		local full = opts.Full == true
		local self = Control.new(section, opts, {
			class = Segmented, kind = "Segmented", value = true, default = default,
			layout = full and "stack" or "row",
			validate = function(v)
				for _, option in ipairs(options) do
					if option.Value == v then
						return v
					end
				end
				return default
			end,
		})
		self.Items = options
		local track = New("Frame", {
			Name = "Segments",
			AutomaticSize = full and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
			Size = full and Theme.f(function(_, s)
				return UDim2.new(1, 0, 0, s.segment + 4)
			end) or Theme.f(function(_, s)
				return UDim2.fromOffset(0, s.segment + 4)
			end),
			BackgroundColor3 = C("sunken"),
			LayoutOrder = 5,
			Parent = full and self.Body or self.Right,
		}, { Create.corner("rSmall") })
		self.Thumb = New("Frame", {
			Name = "Thumb",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = C("segment"),
			Parent = track,
		}, { Create.corner(7) })
		local buttons = New("Frame", {
			AutomaticSize = full and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
			Size = full and UDim2.fromScale(1, 1) or UDim2.fromScale(0, 1),
			ZIndex = 2,
			Parent = track,
		}, { Create.pad(2), Create.list("Horizontal", 2, { valign = "Center" }) })
		self.Track = track
		self.Buttons = {}
		for index, option in ipairs(options) do
			local button = New("TextButton", {
				AutomaticSize = full and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
				Size = Theme.sz(0, 0, 0, "segment"),
				TextColor3 = C("textMuted"),
				Weight = "Medium",
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = index,
				ZIndex = 2,
				Parent = buttons,
			}, { Create.pad(0, 12), Create.maxSize(150, nil) })
			button.TextXAlignment = Enum.TextXAlignment.Center
			Theme.bind(button, "TextSize", Theme.f(function(_, s)
				return s.font - 1
			end))
			if full then
				Create.flex().Parent = button
			end
			self.Loc:Bind(button, "Text", option.Text)
			self.Window.Tooltip:Attach(button, option.Text, self.Maid, nil, function()
				return not button.TextFits
			end)
			self.Maid:Add(button.Activated:Connect(function()
				if self.Enabled then
					self:Set(option.Value)
				end
			end))
			self.Maid:Add(button:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				self:_placeThumb(false)
			end))
			self.Maid:Add(button:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				self:_placeThumb(false)
			end))
			self.Buttons[index] = button
		end
		self:_finish()
		return self
	end

	function Segmented:_index(value)
		for index, option in ipairs(self.Items) do
			if option.Value == value then
				return index
			end
		end
		return 1
	end

	function Segmented:_placeThumb(animate)
		local button = self.Buttons[self:_index(self:Get())]
		if not button then
			return
		end
		local offset = button.AbsolutePosition - self.Track.AbsolutePosition
		local props = {
			Position = UDim2.fromOffset(offset.X, offset.Y),
			Size = UDim2.fromOffset(button.AbsoluteSize.X, button.AbsoluteSize.Y),
		}
		if animate then
			Motion.tween(self.Thumb, props, "spring")
		else
			self.Thumb.Position = props.Position
			self.Thumb.Size = props.Size
		end
	end

	function Segmented:_render(value, animate)
		local selected = self:_index(value)
		for index, button in ipairs(self.Buttons) do
			local on = index == selected
			button.FontFace = Theme.font(on and "SemiBold" or "Medium")
			Theme.set(button, "TextColor3", on and C("text") or C("textMuted"), "fade")
		end
		self:_placeThumb(animate)
		task.defer(function()
			if not self.Destroyed then
				self:_placeThumb(false)
			end
		end)
	end

	function Segmented:StateText()
		local option = self.Items[self:_index(self:Get())]
		return option and self.Loc:Get(option.Text) or nil
	end

	-- Input & Textarea ------------------------------------------------------------------------

	local Input = Control.extend("Input")

	local function buildInput(section, opts, multiline)
		local numeric = opts.Numeric == true
		local default = opts.Default
		if default == nil then
			default = numeric and (opts.Min or 0) or ""
		end
		local self = Control.new(section, opts, {
			class = Input, kind = multiline and "Textarea" or "Input", value = true, default = default, layout = "stack",
			validate = function(v)
				if numeric then
					return tonumber(v) or default
				end
				return tostring(v)
			end,
		})
		self.Numeric, self.Multiline = numeric, multiline
		local field = New("Frame", {
			Name = "Field",
			Size = multiline and UDim2.new(1, 0, 0, opts.Height or 76) or Theme.sz(1, 0, 0, "input"),
			BackgroundColor3 = C("bg"),
			Parent = self.Body,
		}, {
			Create.corner("rControl"),
			Create.pad(multiline and 10 or 0, 12),
			Create.list("Horizontal", 8, { valign = multiline and "Top" or "Center" }),
		})
		self.Stroke = Create.stroke("borderStrong", 1)
		self.Stroke.Parent = field
		self.Box = New("TextBox", {
			Size = UDim2.fromScale(0, 1),
			TextWrapped = multiline,
			MultiLine = multiline,
			TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
			TextTruncate = multiline and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
			Parent = field,
		}, { Create.flex() })
		if opts.Placeholder then
			self.Loc:Bind(self.Box, "PlaceholderText", opts.Placeholder)
		end
		if opts.Suffix then
			local suffix = New("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				TextColor3 = C("textSubtle"),
				TextSize = S("fontDesc"),
				LayoutOrder = 2,
				Parent = field,
			})
			self.Loc:Bind(suffix, "Text", opts.Suffix)
		end
		self.Maid:Add(self.Box.Focused:Connect(function()
			Theme.set(self.Stroke, "Color", C("accent"))
			self.Stroke.Thickness = 1.5
		end))
		local function commit()
			local text = self.Box.Text
			if opts.MaxLength and #text > opts.MaxLength then
				text = text:sub(1, opts.MaxLength)
			end
			if numeric then
				local number = tonumber((text:gsub(",", ".")))
				if number == nil then
					self:_render(self:Get())
					return
				end
				if opts.Min or opts.Max then
					number = math.clamp(number, opts.Min or -math.huge, opts.Max or math.huge)
				end
				self:Set(number)
				self:_render(self:Get())
			else
				self:Set(text)
			end
		end
		self.Maid:Add(self.Box.FocusLost:Connect(function()
			Theme.set(self.Stroke, "Color", C("borderStrong"))
			self.Stroke.Thickness = 1
			commit()
			if opts.Finished then
				task.spawn(opts.Finished, self:Get())
			end
		end))
		if opts.Live then
			self.Maid:Add(self.Box:GetPropertyChangedSignal("Text"):Connect(function()
				if self.Box:IsFocused() then
					commit()
				end
			end))
		end
		self:_finish()
		return self
	end

	function Input:_render(value)
		local text = value == nil and "" or tostring(value)
		if self.Box.Text ~= text then
			self.Box.Text = text
		end
	end

	function Input:StateText()
		local value = self:Get()
		if value == nil or value == "" then
			return nil
		end
		local text = tostring(value)
		if #text > 18 then
			text = text:sub(1, 16) .. "…"
		end
		return text
	end

	function Input:Focus()
		self.Box:CaptureFocus()
	end

	function Controls.Input(section, opts)
		return buildInput(section, opts, false)
	end

	function Controls.Textarea(section, opts)
		return buildInput(section, opts, true)
	end

	return Controls
end

__modules["core/Create"] = function()
	-- Create: declarative instance builder.
	--   New("Frame", { Size = ..., BackgroundColor3 = Theme.c("surface") }, { children })
	-- Token values are bound through Theme, so they follow theme / size changes.
	-- Sensible defaults remove noise: no borders, transparent background unless a
	-- colour is given, Builder Sans text, no auto button colours.

	local Theme = import("core/Theme")

	local Create = {}

	local TEXT = { TextLabel = true, TextButton = true, TextBox = true }
	local BUTTON = { TextButton = true, ImageButton = true }

	local function apply(instance, key, value)
		if Theme.isToken(value) then
			Theme.bind(instance, key, value)
		else
			instance[key] = value
		end
	end

	function Create.New(className, props, children)
		local instance = Instance.new(className)
		props = props or {}
		local isGui = instance:IsA("GuiObject")

		if isGui then
			instance.BorderSizePixel = 0
			if props.BackgroundColor3 == nil and props.BackgroundTransparency == nil then
				instance.BackgroundTransparency = 1
			end
		end
		if TEXT[className] then
			instance.FontFace = Theme.font(props.Weight or "Regular", props.Mono)
			if props.TextColor3 == nil then
				Theme.bind(instance, "TextColor3", Theme.c("text"))
			end
			if props.TextSize == nil then
				Theme.bind(instance, "TextSize", Theme.s("font"))
			end
			if props.Text == nil then
				instance.Text = ""
			end
			instance.TextXAlignment = Enum.TextXAlignment.Left
		end
		if BUTTON[className] then
			instance.AutoButtonColor = false
		end
		if className == "TextBox" then
			instance.ClearTextOnFocus = false
			if props.PlaceholderColor3 == nil then
				Theme.bind(instance, "PlaceholderColor3", Theme.c("textSubtle"))
			end
		end
		if className == "ScrollingFrame" then
			if props.ScrollBarThickness == nil then
				Theme.bind(instance, "ScrollBarThickness", Theme.s("scrollBar"))
			end
			instance.CanvasSize = UDim2.new()
			instance.AutomaticCanvasSize = Enum.AutomaticSize.Y
			instance.ScrollingDirection = Enum.ScrollingDirection.Y
			instance.ScrollBarImageTransparency = 0.4
			if props.ScrollBarImageColor3 == nil then
				Theme.bind(instance, "ScrollBarImageColor3", Theme.c("textSubtle"))
			end
		end

		local parent = nil
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			elseif key ~= "Weight" and key ~= "Mono" then
				apply(instance, key, value)
			end
		end
		if children then
			for _, child in ipairs(children) do
				if child then
					child.Parent = instance
				end
			end
		end
		if parent then
			instance.Parent = parent
		end
		return instance
	end

	-- Helpers ---------------------------------------------------------------------

	local function udim(value)
		if Theme.isToken(value) then
			return value
		end
		if type(value) == "string" then
			return Theme.ud(value)
		end
		if typeof(value) == "UDim" then
			return value
		end
		return UDim.new(0, value or 0)
	end

	function Create.corner(radius)
		if radius == "full" then
			return Create.New("UICorner", { CornerRadius = UDim.new(1, 0) })
		end
		return Create.New("UICorner", { CornerRadius = udim(radius) })
	end

	function Create.stroke(color, thickness, transparency)
		return Create.New("UIStroke", {
			Color = Theme.isToken(color) and color or (type(color) == "string" and Theme.c(color) or color),
			Thickness = thickness or 1,
			Transparency = transparency or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end

	-- pad(all) · pad(y, x) · pad(top, right, bottom, left); numbers or size-token names
	function Create.pad(top, right, bottom, left)
		if right == nil then
			right, bottom, left = top, top, top
		elseif bottom == nil then
			bottom, left = top, right
		end
		return Create.New("UIPadding", {
			PaddingTop = udim(top),
			PaddingRight = udim(right),
			PaddingBottom = udim(bottom),
			PaddingLeft = udim(left),
		})
	end

	-- list("Vertical" | "Horizontal", gap, { align = "Center", valign = "Center", wraps = false })
	function Create.list(direction, gap, options)
		options = options or {}
		local layout = Create.New("UIListLayout", {
			FillDirection = direction == "Horizontal" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = udim(gap or 0),
		})
		if options.align then
			layout.HorizontalAlignment = Enum.HorizontalAlignment[options.align]
		end
		if options.valign then
			layout.VerticalAlignment = Enum.VerticalAlignment[options.valign]
		end
		if options.wraps then
			layout.Wraps = true
		end
		return layout
	end

	function Create.flex(grow)
		return Create.New("UIFlexItem", {
			FlexMode = grow == false and Enum.UIFlexMode.None or Enum.UIFlexMode.Fill,
		})
	end

	function Create.minSize(x, y)
		return Create.New("UISizeConstraint", { MinSize = Theme.v2(x or 0, y or 0) })
	end

	function Create.maxSize(x, y)
		return Create.New("UISizeConstraint", { MaxSize = Theme.v2(x or math.huge, y or math.huge) })
	end

	-- A filled panel with only some corners rounded, built from non-overlapping
	-- pieces (3×3 grid; rounded corners are clipped quarter circles). Unlike a
	-- rounded frame + square "patches", it stays correct when translucent.
	--   Create.panel(parent, { color = token, transparency = token|number,
	--                          radius = n, round = { tl, tr, bl, br } })
	function Create.panel(parent, opts)
		local r = opts.radius or 12
		local round = opts.round or {}
		local holder = Create.New("Frame", {
			Name = "Panel",
			Size = UDim2.fromScale(1, 1),
			ZIndex = opts.zindex or 0,
			Parent = parent,
		})
		local function piece(position, size)
			return Create.New("Frame", {
				Position = position,
				Size = size,
				BackgroundColor3 = opts.color,
				BackgroundTransparency = opts.transparency or 0,
				ZIndex = opts.zindex or 0,
				Parent = holder,
			})
		end
		-- centre column and the left/right middle strips
		piece(UDim2.new(0, r, 0, 0), UDim2.new(1, -2 * r, 1, 0))
		piece(UDim2.new(0, 0, 0, r), UDim2.new(0, r, 1, -2 * r))
		piece(UDim2.new(1, -r, 0, r), UDim2.new(0, r, 1, -2 * r))
		local corners = {
			tl = { UDim2.new(0, 0, 0, 0), UDim2.fromOffset(0, 0) },
			tr = { UDim2.new(1, -r, 0, 0), UDim2.fromOffset(-r, 0) },
			bl = { UDim2.new(0, 0, 1, -r), UDim2.fromOffset(0, -r) },
			br = { UDim2.new(1, -r, 1, -r), UDim2.fromOffset(-r, -r) },
		}
		for name, spec in pairs(corners) do
			if round[name] then
				local clip = Create.New("Frame", {
					Position = spec[1],
					Size = UDim2.fromOffset(r, r),
					ClipsDescendants = true,
					ZIndex = opts.zindex or 0,
					Parent = holder,
				})
				local circle = Create.New("Frame", {
					Position = spec[2],
					Size = UDim2.fromOffset(2 * r, 2 * r),
					BackgroundColor3 = opts.color,
					BackgroundTransparency = opts.transparency or 0,
					ZIndex = opts.zindex or 0,
					Parent = clip,
				})
				Create.corner(r).Parent = circle
			else
				piece(spec[1], UDim2.fromOffset(r, r))
			end
		end
		return holder
	end

	-- Text helper: Create.text(text, { size = "fontDesc", color = "textMuted", weight = "Medium", wrap = true })
	function Create.text(text, options)
		options = options or {}
		local label = Create.New("TextLabel", {
			Text = text or "",
			Weight = options.weight,
			Mono = options.mono,
			TextColor3 = Theme.c(options.color or "text"),
			TextSize = Theme.s(options.size or "font"),
			TextWrapped = options.wrap or false,
			TextTruncate = options.truncate and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
			AutomaticSize = options.autoX and Enum.AutomaticSize.XY or (options.wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None),
			Size = options.sizeUDim or (options.autoX and UDim2.new() or UDim2.new(1, 0, 0, 0)),
			LayoutOrder = options.order or 0,
			RichText = options.rich or false,
			Name = options.name or "Text",
		})
		if options.align then
			label.TextXAlignment = Enum.TextXAlignment[options.align]
		end
		if not options.wrap and not options.autoX and not options.sizeUDim then
			Theme.bind(label, "Size", Theme.f(function(_, s)
				return UDim2.new(1, 0, 0, math.ceil((s[options.size or "font"] or 14) * 1.3))
			end))
		end
		return label
	end

	return Create
end

__modules["core/Device"] = function()
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
end

__modules["core/Drag"] = function()
	-- Drag: pointer dragging for mouse and touch with a tap threshold.
	--   Drag.attach(handle, {
	--     onStart(pointer) -> bool?   (return false to cancel)
	--     onMove(pointer, delta)      (only after the threshold)
	--     onEnd(pointer, moved)
	--     threshold = 6,
	--   }, maid)

	local Services = import("core/Services")
	local Device = import("core/Device")

	local Drag = {}

	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end

	local function isMove(input)
		return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
	end

	function Drag.attach(handle, callbacks, maid)
		local threshold = callbacks.threshold or 6
		local active = nil

		local function finish(input)
			if not active then
				return
			end
			local state = active
			active = nil
			for _, connection in ipairs(state.connections) do
				connection:Disconnect()
			end
			if callbacks.onEnd then
				callbacks.onEnd(input and Device.pointer(input) or state.last, state.moved)
			end
		end

		local began = handle.InputBegan:Connect(function(input)
			if active or not isPress(input) then
				return
			end
			local start = Device.pointer(input)
			if callbacks.onStart and callbacks.onStart(start) == false then
				return
			end
			local state = { start = start, last = start, moved = false, input = input, connections = {} }
			active = state
			local uis = Services.UserInputService
			table.insert(state.connections, uis.InputChanged:Connect(function(changed)
				if active ~= state or not isMove(changed) then
					return
				end
				if input.UserInputType == Enum.UserInputType.Touch and changed ~= input then
					return
				end
				local pointer = Device.pointer(changed)
				if not state.moved and (pointer - state.start).Magnitude < threshold then
					return
				end
				state.moved = true
				local delta = pointer - state.last
				state.last = pointer
				if callbacks.onMove then
					callbacks.onMove(pointer, delta, pointer - state.start)
				end
			end))
			table.insert(state.connections, uis.InputEnded:Connect(function(ended)
				if active ~= state then
					return
				end
				if ended == input or (input.UserInputType == Enum.UserInputType.MouseButton1 and ended.UserInputType == Enum.UserInputType.MouseButton1) then
					finish(ended)
				end
			end))
		end)
		if maid then
			maid:Add(began)
			maid:Add(function()
				finish(nil)
			end)
		end
		return began
	end

	-- Long press (touch): fires after `seconds` if the finger did not move.
	function Drag.longPress(handle, seconds, callback, maid)
		local token = 0
		local began = handle.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			token += 1
			local mine = token
			local start = Device.pointer(input)
			local moved = false
			local changed
			changed = Services.UserInputService.InputChanged:Connect(function(c)
				if c == input and (Device.pointer(c) - start).Magnitude > 8 then
					moved = true
				end
			end)
			task.delay(seconds or 0.5, function()
				changed:Disconnect()
				if token == mine and not moved and input.UserInputState ~= Enum.UserInputState.End then
					callback()
				end
			end)
		end)
		local ended = handle.InputEnded:Connect(function()
			token += 1
		end)
		if maid then
			maid:Add(began)
			maid:Add(ended)
		end
	end

	-- Keep a rect inside the screen (below the Roblox top bar).
	function Drag.clamp(position, size, margin)
		margin = margin or 8
		local vp = Device.viewport()
		local top = Device.inset() + margin
		local x = math.clamp(position.X, margin, math.max(margin, vp.X - size.X - margin))
		local y = math.clamp(position.Y, top, math.max(top, vp.Y - size.Y - margin))
		return Vector2.new(x, y)
	end

	return Drag
end

__modules["core/Icons"] = function()
	-- Icons: the Lucide icon set (https://lucide.dev) rendered from Roblox sprite
	-- sheets (ImageLabel + ImageRectOffset), recoloured with the theme.
	--   Icons.new("house"), Icons.new("crosshair", 18, Theme.c("accent"))
	-- Any Lucide name from LucideData works, plus Robly's short names below
	-- (pin, bolt, close, pip…) and any "rbxassetid://…" image.
	-- A few tiny shapes Lucide doesn't have (resize grip, status dots) are drawn
	-- with Frames on a 24×24 grid:
	--   { "l", x1, y1, x2, y2, [w] } line · { "c", cx, cy, r, [w] } ring · { "C", cx, cy, r } dot

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Lucide = import("core/LucideData")

	local New = Create.New
	local Icons = {}

	local D = {}
	Icons.Data = D
	Icons.Lucide = Lucide

	D.grip = { { "l", 21, 9, 9, 21 }, { "l", 21, 15, 15, 21 } }
	D.dot = { { "C", 12, 12, 4 } }
	D.ring = { { "c", 12, 12, 4, 2 } }

	-- Robly's names (used by the library and kept for scripts) -> Lucide names
	Icons.Aliases = {
		home = "home", house = "home", leaf = "leaf", farm = "sprout", sword = "sword", fight = "swords",
		combat = "swords", pin = "map-pin", teleport = "map-pin", eye = "eye", visual = "eye", esp = "eye",
		user = "user", player = "user", sliders = "sliders-horizontal", settings = "settings",
		gear = "settings", close = "x", chevronDown = "chevron-down", chevronUp = "chevron-up",
		chevronLeft = "chevron-left", chevronRight = "chevron-right", pip = "picture-in-picture-2",
		external = "picture-in-picture-2", attach = "minimize-2", ["return"] = "minimize-2",
		more = "more-horizontal", bolt = "zap", lightning = "bolt", warning = "alert-triangle",
		danger = "alert-triangle", success = "check-circle", error = "x-circle", trash = "trash-2",
		box = "package", chest = "package", refresh = "refresh-cw", question = "help-circle",
		stop = "square", speed = "gauge", fly = "plane", money = "coins", ok = "check", fav = "star",
		config = "folder",
	}

	local warned = {}

	-- Resolves a name to ("image", url) | ("sprite", entry) | ("vector", def)
	function Icons.resolve(name)
		if type(name) ~= "string" then
			return "vector", D.dot
		end
		if name:find("^rbxasset") or name:find("^https?://") then
			return "image", name
		end
		if D[name] then
			return "vector", D[name]
		end
		local lucideName = Icons.Aliases[name] or name
		if Icons.Aliases[lucideName] and not Lucide.Icons[lucideName] then
			lucideName = Icons.Aliases[lucideName]
		end
		local entry = Lucide.Icons[lucideName]
		if entry then
			return "sprite", entry
		end
		if not warned[name] then
			warned[name] = true
			warn("[Robly] unknown icon: " .. name .. " (use a Lucide name from lucide.dev/icons)")
		end
		return "sprite", Lucide.Icons["circle"]
	end

	function Icons.has(name)
		if type(name) ~= "string" then
			return false
		end
		if name:find("^rbxasset") or D[name] then
			return true
		end
		local lucideName = Icons.Aliases[name] or name
		return Lucide.Icons[lucideName] ~= nil or Lucide.Icons[Icons.Aliases[lucideName] or ""] ~= nil
	end

	local function px(size)
		return function(width)
			return Theme.f(function(_, s)
				local total = type(size) == "string" and s[size] or size
				return math.max(1, math.floor(width * total / 24 + 0.5))
			end)
		end
	end

	local function sizeToken(size)
		if type(size) == "string" then
			return Theme.f(function(_, s)
				return UDim2.fromOffset(s[size], s[size])
			end)
		end
		return UDim2.fromOffset(size, size)
	end

	-- Icons.new(name, size, colorToken) -> { Frame, SetColor(token, animate), Destroy }
	function Icons.new(name, size, color, props)
		size = size or "icon"
		color = color or Theme.c("text")
		local object = { parts = {} }
		local container = New("Frame", {
			Name = "Icon",
			Size = sizeToken(size),
			BackgroundTransparency = 1,
		})
		if props then
			for key, value in pairs(props) do
				if Theme.isToken(value) then
					Theme.bind(container, key, value)
				else
					container[key] = value
				end
			end
		end
		object.Frame = container

		local function track(instance, prop)
			table.insert(object.parts, { instance, prop })
			Theme.bind(instance, prop, color)
		end

		local kind, value = Icons.resolve(name)
		if kind == "image" or kind == "sprite" then
			local image = New("ImageLabel", {
				Name = "Glyph",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				Parent = container,
			})
			if kind == "image" then
				image.Image = value
			else
				image.Image = "rbxassetid://" .. Lucide.Sheets[value[1]]
				image.ImageRectOffset = Vector2.new(value[2], value[3])
				image.ImageRectSize = Vector2.new(Lucide.Size, Lucide.Size)
			end
			track(image, "ImageColor3")
		else
			local def = value
			local thickness = px(size)

			local function line(x1, y1, x2, y2, w)
				local dx, dy = x2 - x1, y2 - y1
				local length = math.sqrt(dx * dx + dy * dy)
				local bar = New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale((x1 + x2) / 48, (y1 + y2) / 48),
					Size = UDim2.fromScale((length + w) / 24, w / 24),
					Rotation = math.deg(math.atan2(dy, dx)),
					BackgroundColor3 = Color3.new(1, 1, 1),
					Parent = container,
				}, { Create.corner("full") })
				track(bar, "BackgroundColor3")
			end

			local function dot(cx, cy, r)
				local circle = New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(cx / 24, cy / 24),
					Size = UDim2.fromScale(r * 2 / 24, r * 2 / 24),
					BackgroundColor3 = Color3.new(1, 1, 1),
					Parent = container,
				}, { Create.corner("full") })
				track(circle, "BackgroundColor3")
			end

			for _, part in ipairs(def) do
				local kind = part[1]
				if kind == "l" then
					line(part[2], part[3], part[4], part[5], part[6] or 2)
				elseif kind == "p" then
					local w = part.w or 2
					local n = #part
					for i = 2, n - 3, 2 do
						line(part[i], part[i + 1], part[i + 2], part[i + 3], w)
					end
				elseif kind == "c" then
					local ring = New("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(part[2] / 24, part[3] / 24),
						Size = UDim2.fromScale(part[4] * 2 / 24, part[4] * 2 / 24),
						BackgroundTransparency = 1,
						Parent = container,
					}, { Create.corner("full") })
					local stroke = New("UIStroke", {
						Thickness = thickness(part[5] or 2),
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Parent = ring,
					})
					track(stroke, "Color")
				elseif kind == "C" then
					dot(part[2], part[3], part[4])
				elseif kind == "r" or kind == "R" then
					local x, y, w, h, rad = part[2], part[3], part[4], part[5], part[6] or 0
					local box = New("Frame", {
						Position = UDim2.fromScale(x / 24, y / 24),
						Size = UDim2.fromScale(w / 24, h / 24),
						BackgroundTransparency = kind == "R" and 0 or 1,
						BackgroundColor3 = Color3.new(1, 1, 1),
						Parent = container,
					}, { New("UICorner", { CornerRadius = UDim.new(rad / math.min(w, h), 0) }) })
					if kind == "R" then
						track(box, "BackgroundColor3")
					else
						local stroke = New("UIStroke", {
							Thickness = thickness(part[7] or 2),
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
							Parent = box,
						})
						track(stroke, "Color")
					end
				end
			end
		end

		function object.SetColor(_, token, animate)
			color = token
			for _, entry in ipairs(object.parts) do
				if animate then
					Theme.set(entry[1], entry[2], token)
				else
					Theme.bind(entry[1], entry[2], token)
				end
			end
		end

		function object.Destroy()
			container:Destroy()
		end

		return object
	end

	return Icons
end

__modules["core/Localization"] = function()
	-- Localization of the *script's* texts (brief §13).
	--
	-- A text can be:
	--   "Auto farm"                         plain, never translated
	--   "farm.auto"                         key looked up in Language.Strings
	--   { en = "Auto farm", ru = "Автофарм" } inline translations
	--   function() return "…" end           computed
	-- Placeholders: "Killed {count} {count|mob|mobs}" with vars = { count = 3 }.
	-- Plural forms follow each language's rules (ru: моб / моба / мобов).

	local Signal = import("util/Signal")
	local Services = import("core/Services")
	local Compat = import("util/Compat")
	local Strings = import("core/Strings")

	local Localization = {}
	Localization.__index = Localization

	local PLURAL = {}
	function PLURAL.slavic(n)
		local m10, m100 = n % 10, n % 100
		if m10 == 1 and m100 ~= 11 then
			return 1
		elseif m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20) then
			return 2
		end
		return 3
	end
	function PLURAL.polish(n)
		local m10, m100 = n % 10, n % 100
		if n == 1 then
			return 1
		elseif m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20) then
			return 2
		end
		return 3
	end
	function PLURAL.french(n)
		return n < 2 and 1 or 2
	end
	function PLURAL.none()
		return 1
	end
	function PLURAL.default(n)
		return n == 1 and 1 or 2
	end

	local RULES = {
		ru = PLURAL.slavic, uk = PLURAL.slavic, be = PLURAL.slavic, pl = PLURAL.polish,
		fr = PLURAL.french, pt = PLURAL.default, ja = PLURAL.none, zh = PLURAL.none, ko = PLURAL.none,
		th = PLURAL.none, vi = PLURAL.none, id = PLURAL.none, tr = PLURAL.default,
	}

	function Localization.pluralIndex(lang, n)
		local rule = RULES[lang] or PLURAL.default
		return rule(math.abs(math.floor(tonumber(n) or 0)))
	end

	-- Marker for the library's own texts: Localization.L("cancel")
	function Localization.L(key, vars)
		return { __lib = key, vars = vars }
	end

	local function normalizeCode(code)
		code = tostring(code or ""):lower()
		return code:match("^(%a+)") or code
	end

	function Localization.new(options, dev)
		local self = setmetatable({}, Localization)
		options = options or {}
		self.Configured = options.Default ~= nil or options.Available ~= nil
		self.Default = normalizeCode(options.Default or "en")
		self.Available = {}
		for _, code in ipairs(options.Available or { self.Default }) do
			table.insert(self.Available, normalizeCode(code))
		end
		if not table.find(self.Available, self.Default) then
			table.insert(self.Available, 1, self.Default)
		end
		self.Strings = options.Strings or {}
		self.Library = options.Library or {}
		self.Names = options.Names or {}
		self.Dev = dev == true
		self.Current = self.Default
		self.Changed = Signal.new()
		-- strong on purpose (see Theme bindings); cleaned when instances are destroyed
		self._bindings = {}
		self._warned = {}

		-- Script with one language: library texts still follow the player's
		-- Roblox language when Robly has them.
		if not self.Configured then
			local detected = self:DetectRoblox(true)
			self.LibraryLanguage = detected or "en"
		end
		if options.Url then
			self:LoadRemote(options.Url)
		end
		return self
	end

	function Localization:IsMultilingual()
		return #self.Available > 1
	end

	function Localization:NameOf(code)
		return self.Names[code] or Strings.Names[code] or code:upper()
	end

	function Localization:Languages()
		local out = {}
		for _, code in ipairs(self.Available) do
			table.insert(out, { Code = code, Name = self:NameOf(code) })
		end
		return out
	end

	-- Roblox language of the player, if supported (by the script, or by the
	-- library when libraryOnly is true).
	function Localization:DetectRoblox(libraryOnly)
		local ok, locale = pcall(function()
			return Services.LocalizationService.RobloxLocaleId
		end)
		if not ok or type(locale) ~= "string" then
			return nil
		end
		local code = normalizeCode(locale)
		if libraryOnly then
			return Strings[code] and code or nil
		end
		if table.find(self.Available, code) then
			return code
		end
		return nil
	end

	function Localization:_warnOnce(key, lang)
		if not self.Dev then
			return
		end
		local id = key .. "@" .. lang
		if self._warned[id] then
			return
		end
		self._warned[id] = true
		warn("[Robly] " .. self:Lib("missing_translation", { key = key, lang = lang }))
	end

	function Localization:Format(text, vars, lang)
		if not vars or not text:find("{", 1, true) then
			return text
		end
		lang = lang or self.Current
		return (text:gsub("{([%w_]+)([^}]*)}", function(key, forms)
			local value = vars[key]
			if value == nil then
				return nil
			end
			if forms ~= "" and forms:sub(1, 1) == "|" then
				local list = string.split(forms:sub(2), "|")
				local index = Localization.pluralIndex(lang, value)
				return list[math.min(index, #list)] or tostring(value)
			end
			return tostring(value)
		end))
	end

	function Localization:Lib(key, vars)
		local lang = self.LibraryLanguage or self.Current
		local override = self.Library[lang]
		local text = (override and override[key]) or (Strings[lang] and Strings[lang][key])
		if text == nil then
			lang = "en"
			text = (self.Library.en and self.Library.en[key]) or Strings.en[key] or key
		end
		return self:Format(text, vars, lang)
	end

	-- Resolves any text spec to a string in the current language.
	function Localization:Get(spec, vars)
		local kind = type(spec)
		if spec == nil then
			return ""
		elseif kind == "function" then
			local ok, value = pcall(spec, self.Current)
			return ok and tostring(value) or ""
		elseif kind == "table" then
			if spec.__lib then
				return self:Lib(spec.__lib, vars or spec.vars)
			end
			local text = spec[self.Current]
			local lang = self.Current
			if text == nil then
				text = spec[self.Default]
				lang = self.Default
			end
			if text == nil then
				local _, first = next(spec)
				text = first
			end
			return self:Format(tostring(text or ""), vars, lang)
		end
		local text = tostring(spec)
		local current = self.Strings[self.Current]
		if current and current[text] ~= nil then
			return self:Format(current[text], vars)
		end
		local default = self.Strings[self.Default]
		if default and default[text] ~= nil then
			if self.Current ~= self.Default then
				self:_warnOnce(text, self.Current)
			end
			return self:Format(default[text], vars, self.Default)
		end
		if self.Dev and text:match("^[%w_]+%.[%w_.]+$") then
			self:_warnOnce(text, self.Current)
		end
		return self:Format(text, vars)
	end

	-- All strings a search should match for this text: current language,
	-- default language and the key itself (so "farm" finds "Фарм" too).
	function Localization:SearchTexts(spec)
		local out = { self:Get(spec) }
		if type(spec) == "string" then
			table.insert(out, spec)
			local default = self.Strings[self.Default]
			if default and default[spec] then
				table.insert(out, default[spec])
			end
			local en = self.Strings.en
			if en and en[spec] then
				table.insert(out, en[spec])
			end
		elseif type(spec) == "table" and not spec.__lib then
			for _, value in pairs(spec) do
				table.insert(out, tostring(value))
			end
		end
		return out
	end

	-- Binds instance[prop] to a text spec; it re-renders when the language changes.
	function Localization:Bind(instance, prop, spec, vars)
		local entries = self._bindings[instance]
		if not entries then
			entries = {}
			self._bindings[instance] = entries
			pcall(function()
				instance.Destroying:Connect(function()
					self._bindings[instance] = nil
				end)
			end)
		end
		entries[prop] = { spec = spec, vars = vars }
		local v = type(vars) == "function" and vars() or vars
		instance[prop] = self:Get(spec, v)
	end

	function Localization:Unbind(instance, prop)
		local entries = self._bindings[instance]
		if entries then
			entries[prop] = nil
		end
	end

	function Localization:Refresh()
		for instance, entries in pairs(self._bindings) do
			for prop, entry in pairs(entries) do
				local vars = type(entry.vars) == "function" and entry.vars() or entry.vars
				pcall(function()
					instance[prop] = self:Get(entry.spec, vars)
				end)
			end
		end
	end

	function Localization:SetLanguage(code)
		code = normalizeCode(code)
		if not table.find(self.Available, code) then
			return false
		end
		if self.Current == code then
			return true
		end
		self.Current = code
		if self.Configured then
			self.LibraryLanguage = Strings[code] and code or nil
		end
		self:Refresh()
		self.Changed:Fire(code)
		return true
	end

	-- Merge translations fetched from a URL (JSON: { "ru": { "farm.auto": "…" } })
	-- or a table { ru = "https://…/ru.json" }.
	function Localization:LoadRemote(source)
		task.spawn(function()
			local function merge(lang, data)
				if type(data) ~= "table" then
					return
				end
				self.Strings[lang] = self.Strings[lang] or {}
				for key, value in pairs(data) do
					self.Strings[lang][key] = value
				end
			end
			local function fetch(url)
				local body = Compat.httpGet(url)
				if not body then
					return nil
				end
				local ok, data = pcall(function()
					return Services.HttpService:JSONDecode(body)
				end)
				return ok and data or nil
			end
			if type(source) == "string" then
				local data = fetch(source)
				if type(data) == "table" then
					for lang, entries in pairs(data) do
						merge(normalizeCode(lang), entries)
					end
				end
			elseif type(source) == "table" then
				for lang, url in pairs(source) do
					merge(normalizeCode(lang), fetch(url))
				end
			end
			self:Refresh()
			self.Changed:Fire(self.Current)
		end)
	end

	function Localization:Destroy()
		self.Changed:DisconnectAll()
		self._bindings = {}
	end

	return Localization
end

__modules["core/LucideData"] = function()
	-- Lucide icons (https://lucide.dev, ISC License) as Roblox sprite sheets,
	-- from latte-soft/lucide-roblox (MIT License, Copyright (c) 2023 Latte Softworks).
	-- Lucide 0.363.0 · lucide-roblox 0.1.3
	-- Generated by tools/gen_lucide.py — do not edit by hand.
	-- Icons[name] = { sheet index, x offset, y offset }; every icon is 48×48.

	return {
		Version = "0.363.0",
		Size = 48,
		Sheets = { 16898612629, 16898612819, 16898613044, 16898613353, 16898613509, 16898613613, 16898613699, 16898613777, 16898613869 },
		Icons = {
			["a-arrow-down"] = { 1, 771, 0 },
			["a-arrow-up"] = { 1, 0, 771 },
			["a-large-small"] = { 1, 771, 257 },
			["accessibility"] = { 1, 257, 771 },
			["activity"] = { 1, 514, 771 },
			["activity-square"] = { 1, 771, 514 },
			["air-vent"] = { 1, 820, 0 },
			["airplay"] = { 1, 771, 49 },
			["alarm-check"] = { 1, 49, 771 },
			["alarm-clock"] = { 1, 257, 820 },
			["alarm-clock-check"] = { 1, 0, 820 },
			["alarm-clock-minus"] = { 1, 820, 257 },
			["alarm-clock-off"] = { 1, 771, 306 },
			["alarm-clock-plus"] = { 1, 306, 771 },
			["alarm-minus"] = { 1, 820, 514 },
			["alarm-plus"] = { 1, 771, 563 },
			["alarm-smoke"] = { 1, 563, 771 },
			["album"] = { 1, 514, 820 },
			["alert-circle"] = { 1, 869, 0 },
			["alert-octagon"] = { 1, 820, 49 },
			["alert-triangle"] = { 1, 771, 98 },
			["align-center"] = { 1, 0, 869 },
			["align-center-horizontal"] = { 1, 98, 771 },
			["align-center-vertical"] = { 1, 49, 820 },
			["align-end-horizontal"] = { 1, 869, 257 },
			["align-end-vertical"] = { 1, 820, 306 },
			["align-horizontal-distribute-center"] = { 1, 771, 355 },
			["align-horizontal-distribute-end"] = { 1, 355, 771 },
			["align-horizontal-distribute-start"] = { 1, 306, 820 },
			["align-horizontal-justify-center"] = { 1, 257, 869 },
			["align-horizontal-justify-end"] = { 1, 869, 514 },
			["align-horizontal-justify-start"] = { 1, 820, 563 },
			["align-horizontal-space-around"] = { 1, 771, 612 },
			["align-horizontal-space-between"] = { 1, 612, 771 },
			["align-justify"] = { 1, 563, 820 },
			["align-left"] = { 1, 514, 869 },
			["align-right"] = { 1, 918, 0 },
			["align-start-horizontal"] = { 1, 869, 49 },
			["align-start-vertical"] = { 1, 820, 98 },
			["align-vertical-distribute-center"] = { 1, 771, 147 },
			["align-vertical-distribute-end"] = { 1, 147, 771 },
			["align-vertical-distribute-start"] = { 1, 98, 820 },
			["align-vertical-justify-center"] = { 1, 49, 869 },
			["align-vertical-justify-end"] = { 1, 0, 918 },
			["align-vertical-justify-start"] = { 1, 918, 257 },
			["align-vertical-space-around"] = { 1, 869, 306 },
			["align-vertical-space-between"] = { 1, 820, 355 },
			["ambulance"] = { 1, 771, 404 },
			["ampersand"] = { 1, 404, 771 },
			["ampersands"] = { 1, 355, 820 },
			["anchor"] = { 1, 306, 869 },
			["angry"] = { 1, 257, 918 },
			["annoyed"] = { 1, 918, 514 },
			["antenna"] = { 1, 869, 563 },
			["anvil"] = { 1, 820, 612 },
			["aperture"] = { 1, 771, 661 },
			["app-window"] = { 1, 612, 820 },
			["app-window-mac"] = { 1, 661, 771 },
			["apple"] = { 1, 563, 869 },
			["archive"] = { 1, 918, 49 },
			["archive-restore"] = { 1, 514, 918 },
			["archive-x"] = { 1, 967, 0 },
			["area-chart"] = { 1, 869, 98 },
			["armchair"] = { 1, 820, 147 },
			["arrow-big-down"] = { 1, 196, 771 },
			["arrow-big-down-dash"] = { 1, 771, 196 },
			["arrow-big-left"] = { 1, 98, 869 },
			["arrow-big-left-dash"] = { 1, 147, 820 },
			["arrow-big-right"] = { 1, 0, 967 },
			["arrow-big-right-dash"] = { 1, 49, 918 },
			["arrow-big-up"] = { 1, 918, 306 },
			["arrow-big-up-dash"] = { 1, 967, 257 },
			["arrow-down"] = { 1, 967, 49 },
			["arrow-down-0-1"] = { 1, 869, 355 },
			["arrow-down-1-0"] = { 1, 820, 404 },
			["arrow-down-a-z"] = { 1, 771, 453 },
			["arrow-down-circle"] = { 1, 453, 771 },
			["arrow-down-from-line"] = { 1, 404, 820 },
			["arrow-down-left"] = { 1, 257, 967 },
			["arrow-down-left-from-circle"] = { 1, 355, 869 },
			["arrow-down-left-square"] = { 1, 306, 918 },
			["arrow-down-narrow-wide"] = { 1, 967, 514 },
			["arrow-down-right"] = { 1, 820, 661 },
			["arrow-down-right-from-circle"] = { 1, 918, 563 },
			["arrow-down-right-square"] = { 1, 869, 612 },
			["arrow-down-square"] = { 1, 771, 710 },
			["arrow-down-to-dot"] = { 1, 710, 771 },
			["arrow-down-to-line"] = { 1, 661, 820 },
			["arrow-down-up"] = { 1, 612, 869 },
			["arrow-down-wide-narrow"] = { 1, 563, 918 },
			["arrow-down-z-a"] = { 1, 514, 967 },
			["arrow-left"] = { 1, 98, 918 },
			["arrow-left-circle"] = { 1, 918, 98 },
			["arrow-left-from-line"] = { 1, 869, 147 },
			["arrow-left-right"] = { 1, 820, 196 },
			["arrow-left-square"] = { 1, 196, 820 },
			["arrow-left-to-line"] = { 1, 147, 869 },
			["arrow-right"] = { 1, 453, 820 },
			["arrow-right-circle"] = { 1, 49, 967 },
			["arrow-right-from-line"] = { 1, 967, 306 },
			["arrow-right-left"] = { 1, 918, 355 },
			["arrow-right-square"] = { 1, 869, 404 },
			["arrow-right-to-line"] = { 1, 820, 453 },
			["arrow-up"] = { 1, 967, 355 },
			["arrow-up-0-1"] = { 1, 404, 869 },
			["arrow-up-1-0"] = { 1, 355, 918 },
			["arrow-up-a-z"] = { 1, 306, 967 },
			["arrow-up-circle"] = { 1, 967, 563 },
			["arrow-up-down"] = { 1, 918, 612 },
			["arrow-up-from-dot"] = { 1, 869, 661 },
			["arrow-up-from-line"] = { 1, 820, 710 },
			["arrow-up-left"] = { 1, 661, 869 },
			["arrow-up-left-from-circle"] = { 1, 771, 759 },
			["arrow-up-left-square"] = { 1, 710, 820 },
			["arrow-up-narrow-wide"] = { 1, 612, 918 },
			["arrow-up-right"] = { 1, 918, 147 },
			["arrow-up-right-from-circle"] = { 1, 563, 967 },
			["arrow-up-right-square"] = { 1, 967, 98 },
			["arrow-up-square"] = { 1, 869, 196 },
			["arrow-up-to-line"] = { 1, 196, 869 },
			["arrow-up-wide-narrow"] = { 1, 147, 918 },
			["arrow-up-z-a"] = { 1, 98, 967 },
			["arrows-up-from-line"] = { 1, 918, 404 },
			["asterisk"] = { 1, 869, 453 },
			["at-sign"] = { 1, 453, 869 },
			["atom"] = { 1, 404, 918 },
			["audio-lines"] = { 1, 355, 967 },
			["audio-waveform"] = { 1, 967, 612 },
			["award"] = { 1, 918, 661 },
			["axe"] = { 1, 869, 710 },
			["axis-3d"] = { 1, 820, 759 },
			["baby"] = { 1, 771, 808 },
			["backpack"] = { 1, 710, 869 },
			["badge"] = { 1, 661, 967 },
			["badge-alert"] = { 1, 661, 918 },
			["badge-cent"] = { 1, 612, 967 },
			["badge-check"] = { 1, 967, 147 },
			["badge-dollar-sign"] = { 1, 918, 196 },
			["badge-euro"] = { 1, 196, 918 },
			["badge-help"] = { 1, 147, 967 },
			["badge-indian-rupee"] = { 1, 967, 404 },
			["badge-info"] = { 1, 918, 453 },
			["badge-japanese-yen"] = { 1, 453, 918 },
			["badge-minus"] = { 1, 404, 967 },
			["badge-percent"] = { 1, 967, 661 },
			["badge-plus"] = { 1, 918, 710 },
			["badge-pound-sterling"] = { 1, 869, 759 },
			["badge-russian-ruble"] = { 1, 820, 808 },
			["badge-swiss-franc"] = { 1, 771, 857 },
			["badge-x"] = { 1, 710, 918 },
			["baggage-claim"] = { 1, 967, 196 },
			["ban"] = { 1, 196, 967 },
			["banana"] = { 1, 967, 453 },
			["banknote"] = { 1, 453, 967 },
			["bar-chart"] = { 1, 967, 759 },
			["bar-chart-2"] = { 1, 967, 710 },
			["bar-chart-3"] = { 1, 918, 759 },
			["bar-chart-4"] = { 1, 869, 808 },
			["bar-chart-big"] = { 1, 820, 857 },
			["bar-chart-horizontal"] = { 1, 710, 967 },
			["bar-chart-horizontal-big"] = { 1, 771, 906 },
			["barcode"] = { 1, 918, 808 },
			["baseline"] = { 1, 869, 857 },
			["bath"] = { 1, 820, 906 },
			["battery"] = { 1, 967, 857 },
			["battery-charging"] = { 1, 771, 955 },
			["battery-full"] = { 1, 967, 808 },
			["battery-low"] = { 1, 918, 857 },
			["battery-medium"] = { 1, 869, 906 },
			["battery-warning"] = { 1, 820, 955 },
			["beaker"] = { 1, 918, 906 },
			["bean"] = { 1, 967, 906 },
			["bean-off"] = { 1, 869, 955 },
			["bed"] = { 2, 771, 0 },
			["bed-double"] = { 1, 918, 955 },
			["bed-single"] = { 1, 967, 955 },
			["beef"] = { 2, 0, 771 },
			["beer"] = { 2, 257, 771 },
			["beer-off"] = { 2, 771, 257 },
			["bell"] = { 2, 820, 257 },
			["bell-dot"] = { 2, 771, 514 },
			["bell-electric"] = { 2, 514, 771 },
			["bell-minus"] = { 2, 820, 0 },
			["bell-off"] = { 2, 771, 49 },
			["bell-plus"] = { 2, 49, 771 },
			["bell-ring"] = { 2, 0, 820 },
			["between-horizontal-end"] = { 2, 771, 306 },
			["between-horizontal-start"] = { 2, 306, 771 },
			["between-vertical-end"] = { 2, 257, 820 },
			["between-vertical-start"] = { 2, 820, 514 },
			["bike"] = { 2, 771, 563 },
			["binary"] = { 2, 563, 771 },
			["biohazard"] = { 2, 514, 820 },
			["bird"] = { 2, 869, 0 },
			["bitcoin"] = { 2, 820, 49 },
			["blend"] = { 2, 771, 98 },
			["blinds"] = { 2, 98, 771 },
			["blocks"] = { 2, 49, 820 },
			["bluetooth"] = { 2, 771, 355 },
			["bluetooth-connected"] = { 2, 0, 869 },
			["bluetooth-off"] = { 2, 869, 257 },
			["bluetooth-searching"] = { 2, 820, 306 },
			["bold"] = { 2, 355, 771 },
			["bolt"] = { 2, 306, 820 },
			["bomb"] = { 2, 257, 869 },
			["bone"] = { 2, 869, 514 },
			["book"] = { 2, 820, 612 },
			["book-a"] = { 2, 820, 563 },
			["book-audio"] = { 2, 771, 612 },
			["book-check"] = { 2, 612, 771 },
			["book-copy"] = { 2, 563, 820 },
			["book-dashed"] = { 2, 514, 869 },
			["book-down"] = { 2, 918, 0 },
			["book-headphones"] = { 2, 869, 49 },
			["book-heart"] = { 2, 820, 98 },
			["book-image"] = { 2, 771, 147 },
			["book-key"] = { 2, 147, 771 },
			["book-lock"] = { 2, 98, 820 },
			["book-marked"] = { 2, 49, 869 },
			["book-minus"] = { 2, 0, 918 },
			["book-open"] = { 2, 820, 355 },
			["book-open-check"] = { 2, 918, 257 },
			["book-open-text"] = { 2, 869, 306 },
			["book-plus"] = { 2, 771, 404 },
			["book-text"] = { 2, 404, 771 },
			["book-type"] = { 2, 355, 820 },
			["book-up"] = { 2, 257, 918 },
			["book-up-2"] = { 2, 306, 869 },
			["book-user"] = { 2, 918, 514 },
			["book-x"] = { 2, 869, 563 },
			["bookmark"] = { 2, 514, 918 },
			["bookmark-check"] = { 2, 771, 661 },
			["bookmark-minus"] = { 2, 661, 771 },
			["bookmark-plus"] = { 2, 612, 820 },
			["bookmark-x"] = { 2, 563, 869 },
			["boom-box"] = { 2, 967, 0 },
			["bot"] = { 2, 869, 98 },
			["bot-message-square"] = { 2, 918, 49 },
			["box"] = { 2, 771, 196 },
			["box-select"] = { 2, 820, 147 },
			["boxes"] = { 2, 196, 771 },
			["braces"] = { 2, 147, 820 },
			["brackets"] = { 2, 98, 869 },
			["brain"] = { 2, 967, 257 },
			["brain-circuit"] = { 2, 49, 918 },
			["brain-cog"] = { 2, 0, 967 },
			["brick-wall"] = { 2, 918, 306 },
			["briefcase"] = { 2, 771, 453 },
			["briefcase-business"] = { 2, 869, 355 },
			["briefcase-medical"] = { 2, 820, 404 },
			["bring-to-front"] = { 2, 453, 771 },
			["brush"] = { 2, 404, 820 },
			["bug"] = { 2, 257, 967 },
			["bug-off"] = { 2, 355, 869 },
			["bug-play"] = { 2, 306, 918 },
			["building"] = { 2, 918, 563 },
			["building-2"] = { 2, 967, 514 },
			["bus"] = { 2, 820, 661 },
			["bus-front"] = { 2, 869, 612 },
			["cable"] = { 2, 710, 771 },
			["cable-car"] = { 2, 771, 710 },
			["cake"] = { 2, 612, 869 },
			["cake-slice"] = { 2, 661, 820 },
			["calculator"] = { 2, 563, 918 },
			["calendar"] = { 2, 355, 918 },
			["calendar-check"] = { 2, 967, 49 },
			["calendar-check-2"] = { 2, 514, 967 },
			["calendar-clock"] = { 2, 918, 98 },
			["calendar-days"] = { 2, 869, 147 },
			["calendar-fold"] = { 2, 820, 196 },
			["calendar-heart"] = { 2, 196, 820 },
			["calendar-minus"] = { 2, 98, 918 },
			["calendar-minus-2"] = { 2, 147, 869 },
			["calendar-off"] = { 2, 49, 967 },
			["calendar-plus"] = { 2, 918, 355 },
			["calendar-plus-2"] = { 2, 967, 306 },
			["calendar-range"] = { 2, 869, 404 },
			["calendar-search"] = { 2, 820, 453 },
			["calendar-x"] = { 2, 404, 869 },
			["calendar-x-2"] = { 2, 453, 820 },
			["camera"] = { 2, 967, 563 },
			["camera-off"] = { 2, 306, 967 },
			["candlestick-chart"] = { 2, 918, 612 },
			["candy"] = { 2, 771, 759 },
			["candy-cane"] = { 2, 869, 661 },
			["candy-off"] = { 2, 820, 710 },
			["cannabis"] = { 2, 710, 820 },
			["captions"] = { 2, 612, 918 },
			["captions-off"] = { 2, 661, 869 },
			["car"] = { 2, 918, 147 },
			["car-front"] = { 2, 563, 967 },
			["car-taxi-front"] = { 2, 967, 98 },
			["caravan"] = { 2, 869, 196 },
			["carrot"] = { 2, 196, 869 },
			["case-lower"] = { 2, 147, 918 },
			["case-sensitive"] = { 2, 98, 967 },
			["case-upper"] = { 2, 967, 355 },
			["cassette-tape"] = { 2, 918, 404 },
			["cast"] = { 2, 869, 453 },
			["castle"] = { 2, 453, 869 },
			["cat"] = { 2, 404, 918 },
			["cctv"] = { 2, 355, 967 },
			["check"] = { 2, 710, 869 },
			["check-check"] = { 2, 967, 612 },
			["check-circle"] = { 2, 869, 710 },
			["check-circle-2"] = { 2, 918, 661 },
			["check-square"] = { 2, 771, 808 },
			["check-square-2"] = { 2, 820, 759 },
			["chef-hat"] = { 2, 661, 918 },
			["cherry"] = { 2, 612, 967 },
			["chevron-down"] = { 2, 196, 918 },
			["chevron-down-circle"] = { 2, 967, 147 },
			["chevron-down-square"] = { 2, 918, 196 },
			["chevron-first"] = { 2, 147, 967 },
			["chevron-last"] = { 2, 967, 404 },
			["chevron-left"] = { 2, 404, 967 },
			["chevron-left-circle"] = { 2, 918, 453 },
			["chevron-left-square"] = { 2, 453, 918 },
			["chevron-right"] = { 2, 869, 759 },
			["chevron-right-circle"] = { 2, 967, 661 },
			["chevron-right-square"] = { 2, 918, 710 },
			["chevron-up"] = { 2, 710, 918 },
			["chevron-up-circle"] = { 2, 820, 808 },
			["chevron-up-square"] = { 2, 771, 857 },
			["chevrons-down"] = { 2, 967, 196 },
			["chevrons-down-up"] = { 2, 661, 967 },
			["chevrons-left"] = { 2, 967, 453 },
			["chevrons-left-right"] = { 2, 196, 967 },
			["chevrons-right"] = { 2, 967, 710 },
			["chevrons-right-left"] = { 2, 453, 967 },
			["chevrons-up"] = { 2, 869, 808 },
			["chevrons-up-down"] = { 2, 918, 759 },
			["chrome"] = { 2, 820, 857 },
			["church"] = { 2, 771, 906 },
			["cigarette"] = { 2, 967, 759 },
			["cigarette-off"] = { 2, 710, 967 },
			["circle"] = { 3, 771, 355 },
			["circle-alert"] = { 2, 918, 808 },
			["circle-arrow-down"] = { 2, 869, 857 },
			["circle-arrow-left"] = { 2, 820, 906 },
			["circle-arrow-out-down-left"] = { 2, 771, 955 },
			["circle-arrow-out-down-right"] = { 2, 967, 808 },
			["circle-arrow-out-up-left"] = { 2, 918, 857 },
			["circle-arrow-out-up-right"] = { 2, 869, 906 },
			["circle-arrow-right"] = { 2, 820, 955 },
			["circle-arrow-up"] = { 2, 967, 857 },
			["circle-check"] = { 2, 869, 955 },
			["circle-check-big"] = { 2, 918, 906 },
			["circle-chevron-down"] = { 2, 967, 906 },
			["circle-chevron-left"] = { 2, 918, 955 },
			["circle-chevron-right"] = { 2, 967, 955 },
			["circle-chevron-up"] = { 3, 771, 0 },
			["circle-dashed"] = { 3, 0, 771 },
			["circle-divide"] = { 3, 771, 257 },
			["circle-dollar-sign"] = { 3, 257, 771 },
			["circle-dot"] = { 3, 514, 771 },
			["circle-dot-dashed"] = { 3, 771, 514 },
			["circle-ellipsis"] = { 3, 820, 0 },
			["circle-equal"] = { 3, 771, 49 },
			["circle-fading-plus"] = { 3, 49, 771 },
			["circle-gauge"] = { 3, 0, 820 },
			["circle-help"] = { 3, 820, 257 },
			["circle-minus"] = { 3, 771, 306 },
			["circle-off"] = { 3, 306, 771 },
			["circle-parking"] = { 3, 820, 514 },
			["circle-parking-off"] = { 3, 257, 820 },
			["circle-pause"] = { 3, 771, 563 },
			["circle-percent"] = { 3, 563, 771 },
			["circle-play"] = { 3, 514, 820 },
			["circle-plus"] = { 3, 869, 0 },
			["circle-power"] = { 3, 820, 49 },
			["circle-slash"] = { 3, 98, 771 },
			["circle-slash-2"] = { 3, 771, 98 },
			["circle-stop"] = { 3, 49, 820 },
			["circle-user"] = { 3, 869, 257 },
			["circle-user-round"] = { 3, 0, 869 },
			["circle-x"] = { 3, 820, 306 },
			["circuit-board"] = { 3, 355, 771 },
			["citrus"] = { 3, 306, 820 },
			["clapperboard"] = { 3, 257, 869 },
			["clipboard"] = { 3, 49, 869 },
			["clipboard-check"] = { 3, 869, 514 },
			["clipboard-copy"] = { 3, 820, 563 },
			["clipboard-edit"] = { 3, 771, 612 },
			["clipboard-list"] = { 3, 612, 771 },
			["clipboard-minus"] = { 3, 563, 820 },
			["clipboard-paste"] = { 3, 514, 869 },
			["clipboard-pen"] = { 3, 869, 49 },
			["clipboard-pen-line"] = { 3, 918, 0 },
			["clipboard-plus"] = { 3, 820, 98 },
			["clipboard-signature"] = { 3, 771, 147 },
			["clipboard-type"] = { 3, 147, 771 },
			["clipboard-x"] = { 3, 98, 820 },
			["clock"] = { 3, 771, 661 },
			["clock-1"] = { 3, 0, 918 },
			["clock-10"] = { 3, 918, 257 },
			["clock-11"] = { 3, 869, 306 },
			["clock-12"] = { 3, 820, 355 },
			["clock-2"] = { 3, 771, 404 },
			["clock-3"] = { 3, 404, 771 },
			["clock-4"] = { 3, 355, 820 },
			["clock-5"] = { 3, 306, 869 },
			["clock-6"] = { 3, 257, 918 },
			["clock-7"] = { 3, 918, 514 },
			["clock-8"] = { 3, 869, 563 },
			["clock-9"] = { 3, 820, 612 },
			["cloud"] = { 3, 918, 306 },
			["cloud-cog"] = { 3, 661, 771 },
			["cloud-download"] = { 3, 612, 820 },
			["cloud-drizzle"] = { 3, 563, 869 },
			["cloud-fog"] = { 3, 514, 918 },
			["cloud-hail"] = { 3, 967, 0 },
			["cloud-lightning"] = { 3, 918, 49 },
			["cloud-moon"] = { 3, 820, 147 },
			["cloud-moon-rain"] = { 3, 869, 98 },
			["cloud-off"] = { 3, 771, 196 },
			["cloud-rain"] = { 3, 147, 820 },
			["cloud-rain-wind"] = { 3, 196, 771 },
			["cloud-snow"] = { 3, 98, 869 },
			["cloud-sun"] = { 3, 0, 967 },
			["cloud-sun-rain"] = { 3, 49, 918 },
			["cloud-upload"] = { 3, 967, 257 },
			["cloudy"] = { 3, 869, 355 },
			["clover"] = { 3, 820, 404 },
			["club"] = { 3, 771, 453 },
			["code"] = { 3, 355, 869 },
			["code-2"] = { 3, 453, 771 },
			["code-xml"] = { 3, 404, 820 },
			["codepen"] = { 3, 306, 918 },
			["codesandbox"] = { 3, 257, 967 },
			["coffee"] = { 3, 967, 514 },
			["cog"] = { 3, 918, 563 },
			["coins"] = { 3, 869, 612 },
			["columns"] = { 3, 661, 820 },
			["columns-2"] = { 3, 820, 661 },
			["columns-3"] = { 3, 771, 710 },
			["columns-4"] = { 3, 710, 771 },
			["combine"] = { 3, 612, 869 },
			["command"] = { 3, 563, 918 },
			["compass"] = { 3, 514, 967 },
			["component"] = { 3, 967, 49 },
			["computer"] = { 3, 918, 98 },
			["concierge-bell"] = { 3, 869, 147 },
			["cone"] = { 3, 820, 196 },
			["construction"] = { 3, 196, 820 },
			["contact"] = { 3, 49, 967 },
			["contact-2"] = { 3, 147, 869 },
			["contact-round"] = { 3, 98, 918 },
			["container"] = { 3, 967, 306 },
			["contrast"] = { 3, 918, 355 },
			["cookie"] = { 3, 869, 404 },
			["cooking-pot"] = { 3, 820, 453 },
			["copy"] = { 3, 918, 612 },
			["copy-check"] = { 3, 453, 820 },
			["copy-minus"] = { 3, 404, 869 },
			["copy-plus"] = { 3, 355, 918 },
			["copy-slash"] = { 3, 306, 967 },
			["copy-x"] = { 3, 967, 563 },
			["copyleft"] = { 3, 869, 661 },
			["copyright"] = { 3, 820, 710 },
			["corner-down-left"] = { 3, 771, 759 },
			["corner-down-right"] = { 3, 710, 820 },
			["corner-left-down"] = { 3, 661, 869 },
			["corner-left-up"] = { 3, 612, 918 },
			["corner-right-down"] = { 3, 563, 967 },
			["corner-right-up"] = { 3, 967, 98 },
			["corner-up-left"] = { 3, 918, 147 },
			["corner-up-right"] = { 3, 869, 196 },
			["cpu"] = { 3, 196, 869 },
			["creative-commons"] = { 3, 147, 918 },
			["credit-card"] = { 3, 98, 967 },
			["croissant"] = { 3, 967, 355 },
			["crop"] = { 3, 918, 404 },
			["cross"] = { 3, 869, 453 },
			["crosshair"] = { 3, 453, 869 },
			["crown"] = { 3, 404, 918 },
			["cuboid"] = { 3, 355, 967 },
			["cup-soda"] = { 3, 967, 612 },
			["currency"] = { 3, 918, 661 },
			["cylinder"] = { 3, 869, 710 },
			["database"] = { 3, 710, 869 },
			["database-backup"] = { 3, 820, 759 },
			["database-zap"] = { 3, 771, 808 },
			["delete"] = { 3, 661, 918 },
			["dessert"] = { 3, 612, 967 },
			["diameter"] = { 3, 967, 147 },
			["diamond"] = { 3, 196, 918 },
			["diamond-percent"] = { 3, 918, 196 },
			["dice-1"] = { 3, 147, 967 },
			["dice-2"] = { 3, 967, 404 },
			["dice-3"] = { 3, 918, 453 },
			["dice-4"] = { 3, 453, 918 },
			["dice-5"] = { 3, 404, 967 },
			["dice-6"] = { 3, 967, 661 },
			["dices"] = { 3, 918, 710 },
			["diff"] = { 3, 869, 759 },
			["disc"] = { 3, 661, 967 },
			["disc-2"] = { 3, 820, 808 },
			["disc-3"] = { 3, 771, 857 },
			["disc-album"] = { 3, 710, 918 },
			["divide"] = { 3, 967, 453 },
			["divide-circle"] = { 3, 967, 196 },
			["divide-square"] = { 3, 196, 967 },
			["dna"] = { 3, 967, 710 },
			["dna-off"] = { 3, 453, 967 },
			["dock"] = { 3, 918, 759 },
			["dog"] = { 3, 869, 808 },
			["dollar-sign"] = { 3, 820, 857 },
			["donut"] = { 3, 771, 906 },
			["door-closed"] = { 3, 710, 967 },
			["door-open"] = { 3, 967, 759 },
			["dot"] = { 3, 918, 808 },
			["download"] = { 3, 820, 906 },
			["download-cloud"] = { 3, 869, 857 },
			["drafting-compass"] = { 3, 771, 955 },
			["drama"] = { 3, 967, 808 },
			["dribbble"] = { 3, 918, 857 },
			["drill"] = { 3, 869, 906 },
			["droplet"] = { 3, 820, 955 },
			["droplets"] = { 3, 967, 857 },
			["drum"] = { 3, 918, 906 },
			["drumstick"] = { 3, 869, 955 },
			["dumbbell"] = { 3, 967, 906 },
			["ear"] = { 3, 967, 955 },
			["ear-off"] = { 3, 918, 955 },
			["earth"] = { 4, 0, 771 },
			["earth-lock"] = { 4, 771, 0 },
			["eclipse"] = { 4, 771, 257 },
			["egg"] = { 4, 514, 771 },
			["egg-fried"] = { 4, 257, 771 },
			["egg-off"] = { 4, 771, 514 },
			["ellipsis"] = { 4, 771, 49 },
			["ellipsis-vertical"] = { 4, 820, 0 },
			["equal"] = { 4, 0, 820 },
			["equal-not"] = { 4, 49, 771 },
			["eraser"] = { 4, 820, 257 },
			["euro"] = { 4, 771, 306 },
			["expand"] = { 4, 306, 771 },
			["external-link"] = { 4, 257, 820 },
			["eye"] = { 4, 771, 563 },
			["eye-off"] = { 4, 820, 514 },
			["facebook"] = { 4, 563, 771 },
			["factory"] = { 4, 514, 820 },
			["fan"] = { 4, 869, 0 },
			["fast-forward"] = { 4, 820, 49 },
			["feather"] = { 4, 771, 98 },
			["fence"] = { 4, 98, 771 },
			["ferris-wheel"] = { 4, 49, 820 },
			["figma"] = { 4, 0, 869 },
			["file"] = { 4, 820, 661 },
			["file-archive"] = { 4, 869, 257 },
			["file-audio"] = { 4, 771, 355 },
			["file-audio-2"] = { 4, 820, 306 },
			["file-axis-3d"] = { 4, 355, 771 },
			["file-badge"] = { 4, 257, 869 },
			["file-badge-2"] = { 4, 306, 820 },
			["file-bar-chart"] = { 4, 820, 563 },
			["file-bar-chart-2"] = { 4, 869, 514 },
			["file-box"] = { 4, 771, 612 },
			["file-check"] = { 4, 563, 820 },
			["file-check-2"] = { 4, 612, 771 },
			["file-clock"] = { 4, 514, 869 },
			["file-code"] = { 4, 869, 49 },
			["file-code-2"] = { 4, 918, 0 },
			["file-cog"] = { 4, 820, 98 },
			["file-diff"] = { 4, 771, 147 },
			["file-digit"] = { 4, 147, 771 },
			["file-down"] = { 4, 98, 820 },
			["file-edit"] = { 4, 49, 869 },
			["file-heart"] = { 4, 0, 918 },
			["file-image"] = { 4, 918, 257 },
			["file-input"] = { 4, 869, 306 },
			["file-json"] = { 4, 771, 404 },
			["file-json-2"] = { 4, 820, 355 },
			["file-key"] = { 4, 355, 820 },
			["file-key-2"] = { 4, 404, 771 },
			["file-line-chart"] = { 4, 306, 869 },
			["file-lock"] = { 4, 918, 514 },
			["file-lock-2"] = { 4, 257, 918 },
			["file-minus"] = { 4, 820, 612 },
			["file-minus-2"] = { 4, 869, 563 },
			["file-music"] = { 4, 771, 661 },
			["file-output"] = { 4, 661, 771 },
			["file-pen"] = { 4, 563, 869 },
			["file-pen-line"] = { 4, 612, 820 },
			["file-pie-chart"] = { 4, 514, 918 },
			["file-plus"] = { 4, 918, 49 },
			["file-plus-2"] = { 4, 967, 0 },
			["file-question"] = { 4, 869, 98 },
			["file-scan"] = { 4, 820, 147 },
			["file-search"] = { 4, 196, 771 },
			["file-search-2"] = { 4, 771, 196 },
			["file-signature"] = { 4, 147, 820 },
			["file-sliders"] = { 4, 98, 869 },
			["file-spreadsheet"] = { 4, 49, 918 },
			["file-stack"] = { 4, 0, 967 },
			["file-symlink"] = { 4, 967, 257 },
			["file-terminal"] = { 4, 918, 306 },
			["file-text"] = { 4, 869, 355 },
			["file-type"] = { 4, 771, 453 },
			["file-type-2"] = { 4, 820, 404 },
			["file-up"] = { 4, 453, 771 },
			["file-video"] = { 4, 355, 869 },
			["file-video-2"] = { 4, 404, 820 },
			["file-volume"] = { 4, 257, 967 },
			["file-volume-2"] = { 4, 306, 918 },
			["file-warning"] = { 4, 967, 514 },
			["file-x"] = { 4, 869, 612 },
			["file-x-2"] = { 4, 918, 563 },
			["files"] = { 4, 771, 710 },
			["film"] = { 4, 710, 771 },
			["filter"] = { 4, 612, 869 },
			["filter-x"] = { 4, 661, 820 },
			["fingerprint"] = { 4, 563, 918 },
			["fire-extinguisher"] = { 4, 514, 967 },
			["fish"] = { 4, 869, 147 },
			["fish-off"] = { 4, 967, 49 },
			["fish-symbol"] = { 4, 918, 98 },
			["flag"] = { 4, 98, 918 },
			["flag-off"] = { 4, 820, 196 },
			["flag-triangle-left"] = { 4, 196, 820 },
			["flag-triangle-right"] = { 4, 147, 869 },
			["flame"] = { 4, 967, 306 },
			["flame-kindling"] = { 4, 49, 967 },
			["flashlight"] = { 4, 869, 404 },
			["flashlight-off"] = { 4, 918, 355 },
			["flask-conical"] = { 4, 453, 820 },
			["flask-conical-off"] = { 4, 820, 453 },
			["flask-round"] = { 4, 404, 869 },
			["flip-horizontal"] = { 4, 306, 967 },
			["flip-horizontal-2"] = { 4, 355, 918 },
			["flip-vertical"] = { 4, 918, 612 },
			["flip-vertical-2"] = { 4, 967, 563 },
			["flower"] = { 4, 820, 710 },
			["flower-2"] = { 4, 869, 661 },
			["focus"] = { 4, 771, 759 },
			["fold-horizontal"] = { 4, 710, 820 },
			["fold-vertical"] = { 4, 661, 869 },
			["folder"] = { 4, 404, 967 },
			["folder-archive"] = { 4, 612, 918 },
			["folder-check"] = { 4, 563, 967 },
			["folder-clock"] = { 4, 967, 98 },
			["folder-closed"] = { 4, 918, 147 },
			["folder-cog"] = { 4, 869, 196 },
			["folder-dot"] = { 4, 196, 869 },
			["folder-down"] = { 4, 147, 918 },
			["folder-edit"] = { 4, 98, 967 },
			["folder-git"] = { 4, 918, 404 },
			["folder-git-2"] = { 4, 967, 355 },
			["folder-heart"] = { 4, 869, 453 },
			["folder-input"] = { 4, 453, 869 },
			["folder-kanban"] = { 4, 404, 918 },
			["folder-key"] = { 4, 355, 967 },
			["folder-lock"] = { 4, 967, 612 },
			["folder-minus"] = { 4, 918, 661 },
			["folder-open"] = { 4, 820, 759 },
			["folder-open-dot"] = { 4, 869, 710 },
			["folder-output"] = { 4, 771, 808 },
			["folder-pen"] = { 4, 710, 869 },
			["folder-plus"] = { 4, 661, 918 },
			["folder-root"] = { 4, 612, 967 },
			["folder-search"] = { 4, 918, 196 },
			["folder-search-2"] = { 4, 967, 147 },
			["folder-symlink"] = { 4, 196, 918 },
			["folder-sync"] = { 4, 147, 967 },
			["folder-tree"] = { 4, 967, 404 },
			["folder-up"] = { 4, 918, 453 },
			["folder-x"] = { 4, 453, 918 },
			["folders"] = { 4, 967, 661 },
			["footprints"] = { 4, 918, 710 },
			["forklift"] = { 4, 869, 759 },
			["form-input"] = { 4, 820, 808 },
			["forward"] = { 4, 771, 857 },
			["frame"] = { 4, 710, 918 },
			["framer"] = { 4, 661, 967 },
			["frown"] = { 4, 967, 196 },
			["fuel"] = { 4, 196, 967 },
			["fullscreen"] = { 4, 967, 453 },
			["function-square"] = { 4, 453, 967 },
			["gallery-horizontal"] = { 4, 918, 759 },
			["gallery-horizontal-end"] = { 4, 967, 710 },
			["gallery-thumbnails"] = { 4, 869, 808 },
			["gallery-vertical"] = { 4, 771, 906 },
			["gallery-vertical-end"] = { 4, 820, 857 },
			["gamepad"] = { 4, 967, 759 },
			["gamepad-2"] = { 4, 710, 967 },
			["gantt-chart"] = { 4, 869, 857 },
			["gantt-chart-square"] = { 4, 918, 808 },
			["gauge"] = { 4, 771, 955 },
			["gauge-circle"] = { 4, 820, 906 },
			["gavel"] = { 4, 967, 808 },
			["gem"] = { 4, 918, 857 },
			["ghost"] = { 4, 869, 906 },
			["gift"] = { 4, 820, 955 },
			["git-branch"] = { 4, 918, 906 },
			["git-branch-plus"] = { 4, 967, 857 },
			["git-commit-horizontal"] = { 4, 869, 955 },
			["git-commit-vertical"] = { 4, 967, 906 },
			["git-compare"] = { 4, 967, 955 },
			["git-compare-arrows"] = { 4, 918, 955 },
			["git-fork"] = { 5, 771, 0 },
			["git-graph"] = { 5, 0, 771 },
			["git-merge"] = { 5, 771, 257 },
			["git-pull-request"] = { 5, 49, 771 },
			["git-pull-request-arrow"] = { 5, 257, 771 },
			["git-pull-request-closed"] = { 5, 771, 514 },
			["git-pull-request-create"] = { 5, 820, 0 },
			["git-pull-request-create-arrow"] = { 5, 514, 771 },
			["git-pull-request-draft"] = { 5, 771, 49 },
			["github"] = { 5, 0, 820 },
			["gitlab"] = { 5, 820, 257 },
			["glass-water"] = { 5, 771, 306 },
			["glasses"] = { 5, 306, 771 },
			["globe"] = { 5, 771, 563 },
			["globe-2"] = { 5, 257, 820 },
			["globe-lock"] = { 5, 820, 514 },
			["goal"] = { 5, 563, 771 },
			["grab"] = { 5, 514, 820 },
			["graduation-cap"] = { 5, 869, 0 },
			["grape"] = { 5, 820, 49 },
			["grid-2x2"] = { 5, 771, 98 },
			["grid-3x3"] = { 5, 98, 771 },
			["grip"] = { 5, 869, 257 },
			["grip-horizontal"] = { 5, 49, 820 },
			["grip-vertical"] = { 5, 0, 869 },
			["group"] = { 5, 820, 306 },
			["guitar"] = { 5, 771, 355 },
			["ham"] = { 5, 355, 771 },
			["hammer"] = { 5, 306, 820 },
			["hand"] = { 5, 563, 820 },
			["hand-coins"] = { 5, 257, 869 },
			["hand-heart"] = { 5, 869, 514 },
			["hand-helping"] = { 5, 820, 563 },
			["hand-metal"] = { 5, 771, 612 },
			["hand-platter"] = { 5, 612, 771 },
			["handshake"] = { 5, 514, 869 },
			["hard-drive"] = { 5, 820, 98 },
			["hard-drive-download"] = { 5, 918, 0 },
			["hard-drive-upload"] = { 5, 869, 49 },
			["hard-hat"] = { 5, 771, 147 },
			["hash"] = { 5, 147, 771 },
			["haze"] = { 5, 98, 820 },
			["hdmi-port"] = { 5, 49, 869 },
			["heading"] = { 5, 355, 820 },
			["heading-1"] = { 5, 0, 918 },
			["heading-2"] = { 5, 918, 257 },
			["heading-3"] = { 5, 869, 306 },
			["heading-4"] = { 5, 820, 355 },
			["heading-5"] = { 5, 771, 404 },
			["heading-6"] = { 5, 404, 771 },
			["headphones"] = { 5, 306, 869 },
			["headset"] = { 5, 257, 918 },
			["heart"] = { 5, 661, 771 },
			["heart-crack"] = { 5, 918, 514 },
			["heart-handshake"] = { 5, 869, 563 },
			["heart-off"] = { 5, 820, 612 },
			["heart-pulse"] = { 5, 771, 661 },
			["heater"] = { 5, 612, 820 },
			["help-circle"] = { 5, 563, 869 },
			["helping-hand"] = { 5, 514, 918 },
			["hexagon"] = { 5, 967, 0 },
			["highlighter"] = { 5, 918, 49 },
			["history"] = { 5, 869, 98 },
			["home"] = { 5, 820, 147 },
			["hop"] = { 5, 196, 771 },
			["hop-off"] = { 5, 771, 196 },
			["hospital"] = { 5, 147, 820 },
			["hotel"] = { 5, 98, 869 },
			["hourglass"] = { 5, 49, 918 },
			["ice-cream"] = { 5, 869, 355 },
			["ice-cream-2"] = { 5, 0, 967 },
			["ice-cream-bowl"] = { 5, 967, 257 },
			["ice-cream-cone"] = { 5, 918, 306 },
			["image"] = { 5, 306, 918 },
			["image-down"] = { 5, 820, 404 },
			["image-minus"] = { 5, 771, 453 },
			["image-off"] = { 5, 453, 771 },
			["image-plus"] = { 5, 404, 820 },
			["image-up"] = { 5, 355, 869 },
			["images"] = { 5, 257, 967 },
			["import"] = { 5, 967, 514 },
			["inbox"] = { 5, 918, 563 },
			["indent"] = { 5, 771, 710 },
			["indent-decrease"] = { 5, 869, 612 },
			["indent-increase"] = { 5, 820, 661 },
			["indian-rupee"] = { 5, 710, 771 },
			["infinity"] = { 5, 661, 820 },
			["info"] = { 5, 612, 869 },
			["inspection-panel"] = { 5, 563, 918 },
			["instagram"] = { 5, 514, 967 },
			["italic"] = { 5, 967, 49 },
			["iteration-ccw"] = { 5, 918, 98 },
			["iteration-cw"] = { 5, 869, 147 },
			["japanese-yen"] = { 5, 820, 196 },
			["joystick"] = { 5, 196, 820 },
			["kanban"] = { 5, 49, 967 },
			["kanban-square"] = { 5, 98, 918 },
			["kanban-square-dashed"] = { 5, 147, 869 },
			["key"] = { 5, 869, 404 },
			["key-round"] = { 5, 967, 306 },
			["key-square"] = { 5, 918, 355 },
			["keyboard"] = { 5, 453, 820 },
			["keyboard-music"] = { 5, 820, 453 },
			["lamp"] = { 5, 869, 661 },
			["lamp-ceiling"] = { 5, 404, 869 },
			["lamp-desk"] = { 5, 355, 918 },
			["lamp-floor"] = { 5, 306, 967 },
			["lamp-wall-down"] = { 5, 967, 563 },
			["lamp-wall-up"] = { 5, 918, 612 },
			["land-plot"] = { 5, 820, 710 },
			["landmark"] = { 5, 771, 759 },
			["languages"] = { 5, 710, 820 },
			["laptop"] = { 5, 563, 967 },
			["laptop-2"] = { 5, 661, 869 },
			["laptop-minimal"] = { 5, 612, 918 },
			["lasso"] = { 5, 918, 147 },
			["lasso-select"] = { 5, 967, 98 },
			["laugh"] = { 5, 869, 196 },
			["layers"] = { 5, 98, 967 },
			["layers-2"] = { 5, 196, 869 },
			["layers-3"] = { 5, 147, 918 },
			["layout"] = { 5, 967, 612 },
			["layout-dashboard"] = { 5, 967, 355 },
			["layout-grid"] = { 5, 918, 404 },
			["layout-list"] = { 5, 869, 453 },
			["layout-panel-left"] = { 5, 453, 869 },
			["layout-panel-top"] = { 5, 404, 918 },
			["layout-template"] = { 5, 355, 967 },
			["leaf"] = { 5, 918, 661 },
			["leafy-green"] = { 5, 869, 710 },
			["library"] = { 5, 710, 869 },
			["library-big"] = { 5, 820, 759 },
			["library-square"] = { 5, 771, 808 },
			["life-buoy"] = { 5, 661, 918 },
			["ligature"] = { 5, 612, 967 },
			["lightbulb"] = { 5, 918, 196 },
			["lightbulb-off"] = { 5, 967, 147 },
			["line-chart"] = { 5, 196, 918 },
			["link"] = { 5, 918, 453 },
			["link-2"] = { 5, 967, 404 },
			["link-2-off"] = { 5, 147, 967 },
			["linkedin"] = { 5, 453, 918 },
			["list"] = { 5, 869, 808 },
			["list-checks"] = { 5, 404, 967 },
			["list-collapse"] = { 5, 967, 661 },
			["list-end"] = { 5, 918, 710 },
			["list-filter"] = { 5, 869, 759 },
			["list-minus"] = { 5, 820, 808 },
			["list-music"] = { 5, 771, 857 },
			["list-ordered"] = { 5, 710, 918 },
			["list-plus"] = { 5, 661, 967 },
			["list-restart"] = { 5, 967, 196 },
			["list-start"] = { 5, 196, 967 },
			["list-todo"] = { 5, 967, 453 },
			["list-tree"] = { 5, 453, 967 },
			["list-video"] = { 5, 967, 710 },
			["list-x"] = { 5, 918, 759 },
			["loader"] = { 5, 710, 967 },
			["loader-2"] = { 5, 820, 857 },
			["loader-circle"] = { 5, 771, 906 },
			["locate"] = { 5, 869, 857 },
			["locate-fixed"] = { 5, 967, 759 },
			["locate-off"] = { 5, 918, 808 },
			["lock"] = { 5, 918, 857 },
			["lock-keyhole"] = { 5, 771, 955 },
			["lock-keyhole-open"] = { 5, 820, 906 },
			["lock-open"] = { 5, 967, 808 },
			["log-in"] = { 5, 869, 906 },
			["log-out"] = { 5, 820, 955 },
			["lollipop"] = { 5, 967, 857 },
			["luggage"] = { 5, 918, 906 },
			["m-square"] = { 5, 869, 955 },
			["magnet"] = { 5, 967, 906 },
			["mail"] = { 6, 820, 0 },
			["mail-check"] = { 5, 918, 955 },
			["mail-minus"] = { 5, 967, 955 },
			["mail-open"] = { 6, 771, 0 },
			["mail-plus"] = { 6, 0, 771 },
			["mail-question"] = { 6, 771, 257 },
			["mail-search"] = { 6, 257, 771 },
			["mail-warning"] = { 6, 771, 514 },
			["mail-x"] = { 6, 514, 771 },
			["mailbox"] = { 6, 771, 49 },
			["mails"] = { 6, 49, 771 },
			["map"] = { 6, 306, 771 },
			["map-pin"] = { 6, 820, 257 },
			["map-pin-off"] = { 6, 0, 820 },
			["map-pinned"] = { 6, 771, 306 },
			["martini"] = { 6, 257, 820 },
			["maximize"] = { 6, 771, 563 },
			["maximize-2"] = { 6, 820, 514 },
			["medal"] = { 6, 563, 771 },
			["megaphone"] = { 6, 869, 0 },
			["megaphone-off"] = { 6, 514, 820 },
			["meh"] = { 6, 820, 49 },
			["memory-stick"] = { 6, 771, 98 },
			["menu"] = { 6, 49, 820 },
			["menu-square"] = { 6, 98, 771 },
			["merge"] = { 6, 0, 869 },
			["message-circle"] = { 6, 563, 820 },
			["message-circle-code"] = { 6, 869, 257 },
			["message-circle-dashed"] = { 6, 820, 306 },
			["message-circle-heart"] = { 6, 771, 355 },
			["message-circle-more"] = { 6, 355, 771 },
			["message-circle-off"] = { 6, 306, 820 },
			["message-circle-plus"] = { 6, 257, 869 },
			["message-circle-question"] = { 6, 869, 514 },
			["message-circle-reply"] = { 6, 820, 563 },
			["message-circle-warning"] = { 6, 771, 612 },
			["message-circle-x"] = { 6, 612, 771 },
			["message-square"] = { 6, 355, 820 },
			["message-square-code"] = { 6, 514, 869 },
			["message-square-dashed"] = { 6, 918, 0 },
			["message-square-diff"] = { 6, 869, 49 },
			["message-square-dot"] = { 6, 820, 98 },
			["message-square-heart"] = { 6, 771, 147 },
			["message-square-more"] = { 6, 147, 771 },
			["message-square-off"] = { 6, 98, 820 },
			["message-square-plus"] = { 6, 49, 869 },
			["message-square-quote"] = { 6, 0, 918 },
			["message-square-reply"] = { 6, 918, 257 },
			["message-square-share"] = { 6, 869, 306 },
			["message-square-text"] = { 6, 820, 355 },
			["message-square-warning"] = { 6, 771, 404 },
			["message-square-x"] = { 6, 404, 771 },
			["messages-square"] = { 6, 306, 869 },
			["mic"] = { 6, 820, 612 },
			["mic-2"] = { 6, 257, 918 },
			["mic-off"] = { 6, 918, 514 },
			["mic-vocal"] = { 6, 869, 563 },
			["microscope"] = { 6, 771, 661 },
			["microwave"] = { 6, 661, 771 },
			["milestone"] = { 6, 612, 820 },
			["milk"] = { 6, 514, 918 },
			["milk-off"] = { 6, 563, 869 },
			["minimize"] = { 6, 918, 49 },
			["minimize-2"] = { 6, 967, 0 },
			["minus"] = { 6, 771, 196 },
			["minus-circle"] = { 6, 869, 98 },
			["minus-square"] = { 6, 820, 147 },
			["monitor"] = { 6, 404, 820 },
			["monitor-check"] = { 6, 196, 771 },
			["monitor-dot"] = { 6, 147, 820 },
			["monitor-down"] = { 6, 98, 869 },
			["monitor-off"] = { 6, 49, 918 },
			["monitor-pause"] = { 6, 0, 967 },
			["monitor-play"] = { 6, 967, 257 },
			["monitor-smartphone"] = { 6, 918, 306 },
			["monitor-speaker"] = { 6, 869, 355 },
			["monitor-stop"] = { 6, 820, 404 },
			["monitor-up"] = { 6, 771, 453 },
			["monitor-x"] = { 6, 453, 771 },
			["moon"] = { 6, 306, 918 },
			["moon-star"] = { 6, 355, 869 },
			["more-horizontal"] = { 6, 257, 967 },
			["more-vertical"] = { 6, 967, 514 },
			["mountain"] = { 6, 869, 612 },
			["mountain-snow"] = { 6, 918, 563 },
			["mouse"] = { 6, 563, 918 },
			["mouse-pointer"] = { 6, 612, 869 },
			["mouse-pointer-2"] = { 6, 820, 661 },
			["mouse-pointer-click"] = { 6, 771, 710 },
			["mouse-pointer-square"] = { 6, 661, 820 },
			["mouse-pointer-square-dashed"] = { 6, 710, 771 },
			["move"] = { 6, 453, 820 },
			["move-3d"] = { 6, 514, 967 },
			["move-diagonal"] = { 6, 918, 98 },
			["move-diagonal-2"] = { 6, 967, 49 },
			["move-down"] = { 6, 196, 820 },
			["move-down-left"] = { 6, 869, 147 },
			["move-down-right"] = { 6, 820, 196 },
			["move-horizontal"] = { 6, 147, 869 },
			["move-left"] = { 6, 98, 918 },
			["move-right"] = { 6, 49, 967 },
			["move-up"] = { 6, 869, 404 },
			["move-up-left"] = { 6, 967, 306 },
			["move-up-right"] = { 6, 918, 355 },
			["move-vertical"] = { 6, 820, 453 },
			["music"] = { 6, 967, 563 },
			["music-2"] = { 6, 404, 869 },
			["music-3"] = { 6, 355, 918 },
			["music-4"] = { 6, 306, 967 },
			["navigation"] = { 6, 771, 759 },
			["navigation-2"] = { 6, 869, 661 },
			["navigation-2-off"] = { 6, 918, 612 },
			["navigation-off"] = { 6, 820, 710 },
			["network"] = { 6, 710, 820 },
			["newspaper"] = { 6, 661, 869 },
			["nfc"] = { 6, 612, 918 },
			["notebook"] = { 6, 869, 196 },
			["notebook-pen"] = { 6, 563, 967 },
			["notebook-tabs"] = { 6, 967, 98 },
			["notebook-text"] = { 6, 918, 147 },
			["notepad-text"] = { 6, 147, 918 },
			["notepad-text-dashed"] = { 6, 196, 869 },
			["nut"] = { 6, 967, 355 },
			["nut-off"] = { 6, 98, 967 },
			["octagon"] = { 6, 404, 918 },
			["octagon-alert"] = { 6, 918, 404 },
			["octagon-pause"] = { 6, 869, 453 },
			["octagon-x"] = { 6, 453, 869 },
			["option"] = { 6, 355, 967 },
			["orbit"] = { 6, 967, 612 },
			["outdent"] = { 6, 918, 661 },
			["package"] = { 6, 918, 196 },
			["package-2"] = { 6, 869, 710 },
			["package-check"] = { 6, 820, 759 },
			["package-minus"] = { 6, 771, 808 },
			["package-open"] = { 6, 710, 869 },
			["package-plus"] = { 6, 661, 918 },
			["package-search"] = { 6, 612, 967 },
			["package-x"] = { 6, 967, 147 },
			["paint-bucket"] = { 6, 196, 918 },
			["paint-roller"] = { 6, 147, 967 },
			["paintbrush"] = { 6, 918, 453 },
			["paintbrush-2"] = { 6, 967, 404 },
			["palette"] = { 6, 453, 918 },
			["palmtree"] = { 6, 404, 967 },
			["panel-bottom"] = { 6, 771, 857 },
			["panel-bottom-close"] = { 6, 967, 661 },
			["panel-bottom-dashed"] = { 6, 918, 710 },
			["panel-bottom-inactive"] = { 6, 869, 759 },
			["panel-bottom-open"] = { 6, 820, 808 },
			["panel-left"] = { 6, 967, 453 },
			["panel-left-close"] = { 6, 710, 918 },
			["panel-left-dashed"] = { 6, 661, 967 },
			["panel-left-inactive"] = { 6, 967, 196 },
			["panel-left-open"] = { 6, 196, 967 },
			["panel-right"] = { 6, 820, 857 },
			["panel-right-close"] = { 6, 453, 967 },
			["panel-right-dashed"] = { 6, 967, 710 },
			["panel-right-inactive"] = { 6, 918, 759 },
			["panel-right-open"] = { 6, 869, 808 },
			["panel-top"] = { 6, 869, 857 },
			["panel-top-close"] = { 6, 771, 906 },
			["panel-top-dashed"] = { 6, 710, 967 },
			["panel-top-inactive"] = { 6, 967, 759 },
			["panel-top-open"] = { 6, 918, 808 },
			["panels-left-bottom"] = { 6, 820, 906 },
			["panels-right-bottom"] = { 6, 771, 955 },
			["panels-top-left"] = { 6, 967, 808 },
			["paperclip"] = { 6, 918, 857 },
			["parentheses"] = { 6, 869, 906 },
			["parking-circle"] = { 6, 967, 857 },
			["parking-circle-off"] = { 6, 820, 955 },
			["parking-meter"] = { 6, 918, 906 },
			["parking-square"] = { 6, 967, 906 },
			["parking-square-off"] = { 6, 869, 955 },
			["party-popper"] = { 6, 918, 955 },
			["pause"] = { 7, 0, 771 },
			["pause-circle"] = { 6, 967, 955 },
			["pause-octagon"] = { 7, 771, 0 },
			["paw-print"] = { 7, 771, 257 },
			["pc-case"] = { 7, 257, 771 },
			["pen"] = { 7, 771, 49 },
			["pen-line"] = { 7, 771, 514 },
			["pen-square"] = { 7, 514, 771 },
			["pen-tool"] = { 7, 820, 0 },
			["pencil"] = { 7, 820, 257 },
			["pencil-line"] = { 7, 49, 771 },
			["pencil-ruler"] = { 7, 0, 820 },
			["pentagon"] = { 7, 771, 306 },
			["percent"] = { 7, 771, 563 },
			["percent-circle"] = { 7, 306, 771 },
			["percent-diamond"] = { 7, 257, 820 },
			["percent-square"] = { 7, 820, 514 },
			["person-standing"] = { 7, 563, 771 },
			["phone"] = { 7, 0, 869 },
			["phone-call"] = { 7, 514, 820 },
			["phone-forwarded"] = { 7, 869, 0 },
			["phone-incoming"] = { 7, 820, 49 },
			["phone-missed"] = { 7, 771, 98 },
			["phone-off"] = { 7, 98, 771 },
			["phone-outgoing"] = { 7, 49, 820 },
			["pi"] = { 7, 820, 306 },
			["pi-square"] = { 7, 869, 257 },
			["piano"] = { 7, 771, 355 },
			["pickaxe"] = { 7, 355, 771 },
			["picture-in-picture"] = { 7, 257, 869 },
			["picture-in-picture-2"] = { 7, 306, 820 },
			["pie-chart"] = { 7, 869, 514 },
			["piggy-bank"] = { 7, 820, 563 },
			["pilcrow"] = { 7, 612, 771 },
			["pilcrow-square"] = { 7, 771, 612 },
			["pill"] = { 7, 563, 820 },
			["pin"] = { 7, 918, 0 },
			["pin-off"] = { 7, 514, 869 },
			["pipette"] = { 7, 869, 49 },
			["pizza"] = { 7, 820, 98 },
			["plane"] = { 7, 98, 820 },
			["plane-landing"] = { 7, 771, 147 },
			["plane-takeoff"] = { 7, 147, 771 },
			["play"] = { 7, 918, 257 },
			["play-circle"] = { 7, 49, 869 },
			["play-square"] = { 7, 0, 918 },
			["plug"] = { 7, 404, 771 },
			["plug-2"] = { 7, 869, 306 },
			["plug-zap"] = { 7, 771, 404 },
			["plug-zap-2"] = { 7, 820, 355 },
			["plus"] = { 7, 257, 918 },
			["plus-circle"] = { 7, 355, 820 },
			["plus-square"] = { 7, 306, 869 },
			["pocket"] = { 7, 869, 563 },
			["pocket-knife"] = { 7, 918, 514 },
			["podcast"] = { 7, 820, 612 },
			["pointer"] = { 7, 661, 771 },
			["pointer-off"] = { 7, 771, 661 },
			["popcorn"] = { 7, 612, 820 },
			["popsicle"] = { 7, 563, 869 },
			["pound-sterling"] = { 7, 514, 918 },
			["power"] = { 7, 820, 147 },
			["power-circle"] = { 7, 967, 0 },
			["power-off"] = { 7, 918, 49 },
			["power-square"] = { 7, 869, 98 },
			["presentation"] = { 7, 771, 196 },
			["printer"] = { 7, 196, 771 },
			["projector"] = { 7, 147, 820 },
			["proportions"] = { 7, 98, 869 },
			["puzzle"] = { 7, 49, 918 },
			["pyramid"] = { 7, 0, 967 },
			["qr-code"] = { 7, 967, 257 },
			["quote"] = { 7, 918, 306 },
			["rabbit"] = { 7, 869, 355 },
			["radar"] = { 7, 820, 404 },
			["radiation"] = { 7, 771, 453 },
			["radical"] = { 7, 453, 771 },
			["radio"] = { 7, 306, 918 },
			["radio-receiver"] = { 7, 404, 820 },
			["radio-tower"] = { 7, 355, 869 },
			["radius"] = { 7, 257, 967 },
			["rail-symbol"] = { 7, 967, 514 },
			["rainbow"] = { 7, 918, 563 },
			["rat"] = { 7, 869, 612 },
			["ratio"] = { 7, 820, 661 },
			["receipt"] = { 7, 869, 147 },
			["receipt-cent"] = { 7, 771, 710 },
			["receipt-euro"] = { 7, 710, 771 },
			["receipt-indian-rupee"] = { 7, 661, 820 },
			["receipt-japanese-yen"] = { 7, 612, 869 },
			["receipt-pound-sterling"] = { 7, 563, 918 },
			["receipt-russian-ruble"] = { 7, 514, 967 },
			["receipt-swiss-franc"] = { 7, 967, 49 },
			["receipt-text"] = { 7, 918, 98 },
			["rectangle-ellipsis"] = { 7, 820, 196 },
			["rectangle-horizontal"] = { 7, 196, 820 },
			["rectangle-vertical"] = { 7, 147, 869 },
			["recycle"] = { 7, 98, 918 },
			["redo"] = { 7, 918, 355 },
			["redo-2"] = { 7, 49, 967 },
			["redo-dot"] = { 7, 967, 306 },
			["refresh-ccw"] = { 7, 820, 453 },
			["refresh-ccw-dot"] = { 7, 869, 404 },
			["refresh-cw"] = { 7, 404, 869 },
			["refresh-cw-off"] = { 7, 453, 820 },
			["refrigerator"] = { 7, 355, 918 },
			["regex"] = { 7, 306, 967 },
			["remove-formatting"] = { 7, 967, 563 },
			["repeat"] = { 7, 820, 710 },
			["repeat-1"] = { 7, 918, 612 },
			["repeat-2"] = { 7, 869, 661 },
			["replace"] = { 7, 710, 820 },
			["replace-all"] = { 7, 771, 759 },
			["reply"] = { 7, 612, 918 },
			["reply-all"] = { 7, 661, 869 },
			["rewind"] = { 7, 563, 967 },
			["ribbon"] = { 7, 967, 98 },
			["rocket"] = { 7, 918, 147 },
			["rocking-chair"] = { 7, 869, 196 },
			["roller-coaster"] = { 7, 196, 869 },
			["rotate-3d"] = { 7, 147, 918 },
			["rotate-ccw"] = { 7, 967, 355 },
			["rotate-ccw-square"] = { 7, 98, 967 },
			["rotate-cw"] = { 7, 869, 453 },
			["rotate-cw-square"] = { 7, 918, 404 },
			["route"] = { 7, 404, 918 },
			["route-off"] = { 7, 453, 869 },
			["router"] = { 7, 355, 967 },
			["rows"] = { 7, 820, 759 },
			["rows-2"] = { 7, 967, 612 },
			["rows-3"] = { 7, 918, 661 },
			["rows-4"] = { 7, 869, 710 },
			["rss"] = { 7, 771, 808 },
			["ruler"] = { 7, 710, 869 },
			["russian-ruble"] = { 7, 661, 918 },
			["sailboat"] = { 7, 612, 967 },
			["salad"] = { 7, 967, 147 },
			["sandwich"] = { 7, 918, 196 },
			["satellite"] = { 7, 147, 967 },
			["satellite-dish"] = { 7, 196, 918 },
			["save"] = { 7, 918, 453 },
			["save-all"] = { 7, 967, 404 },
			["scale"] = { 7, 404, 967 },
			["scale-3d"] = { 7, 453, 918 },
			["scaling"] = { 7, 967, 661 },
			["scan"] = { 7, 967, 196 },
			["scan-barcode"] = { 7, 918, 710 },
			["scan-eye"] = { 7, 869, 759 },
			["scan-face"] = { 7, 820, 808 },
			["scan-line"] = { 7, 771, 857 },
			["scan-search"] = { 7, 710, 918 },
			["scan-text"] = { 7, 661, 967 },
			["scatter-chart"] = { 7, 196, 967 },
			["school"] = { 7, 453, 967 },
			["school-2"] = { 7, 967, 453 },
			["scissors"] = { 7, 820, 857 },
			["scissors-line-dashed"] = { 7, 967, 710 },
			["scissors-square"] = { 7, 869, 808 },
			["scissors-square-dashed-bottom"] = { 7, 918, 759 },
			["screen-share"] = { 7, 710, 967 },
			["screen-share-off"] = { 7, 771, 906 },
			["scroll"] = { 7, 918, 808 },
			["scroll-text"] = { 7, 967, 759 },
			["search"] = { 7, 918, 857 },
			["search-check"] = { 7, 869, 857 },
			["search-code"] = { 7, 820, 906 },
			["search-slash"] = { 7, 771, 955 },
			["search-x"] = { 7, 967, 808 },
			["send"] = { 7, 967, 857 },
			["send-horizontal"] = { 7, 869, 906 },
			["send-to-back"] = { 7, 820, 955 },
			["separator-horizontal"] = { 7, 918, 906 },
			["separator-vertical"] = { 7, 869, 955 },
			["server"] = { 8, 771, 0 },
			["server-cog"] = { 7, 967, 906 },
			["server-crash"] = { 7, 918, 955 },
			["server-off"] = { 7, 967, 955 },
			["settings"] = { 8, 771, 257 },
			["settings-2"] = { 8, 0, 771 },
			["shapes"] = { 8, 257, 771 },
			["share"] = { 8, 514, 771 },
			["share-2"] = { 8, 771, 514 },
			["sheet"] = { 8, 820, 0 },
			["shell"] = { 8, 771, 49 },
			["shield"] = { 8, 869, 0 },
			["shield-alert"] = { 8, 49, 771 },
			["shield-ban"] = { 8, 0, 820 },
			["shield-check"] = { 8, 820, 257 },
			["shield-ellipsis"] = { 8, 771, 306 },
			["shield-half"] = { 8, 306, 771 },
			["shield-minus"] = { 8, 257, 820 },
			["shield-off"] = { 8, 820, 514 },
			["shield-plus"] = { 8, 771, 563 },
			["shield-question"] = { 8, 563, 771 },
			["shield-x"] = { 8, 514, 820 },
			["ship"] = { 8, 771, 98 },
			["ship-wheel"] = { 8, 820, 49 },
			["shirt"] = { 8, 98, 771 },
			["shopping-bag"] = { 8, 49, 820 },
			["shopping-basket"] = { 8, 0, 869 },
			["shopping-cart"] = { 8, 869, 257 },
			["shovel"] = { 8, 820, 306 },
			["shower-head"] = { 8, 771, 355 },
			["shrink"] = { 8, 355, 771 },
			["shrub"] = { 8, 306, 820 },
			["shuffle"] = { 8, 257, 869 },
			["sigma"] = { 8, 820, 563 },
			["sigma-square"] = { 8, 869, 514 },
			["signal"] = { 8, 918, 0 },
			["signal-high"] = { 8, 771, 612 },
			["signal-low"] = { 8, 612, 771 },
			["signal-medium"] = { 8, 563, 820 },
			["signal-zero"] = { 8, 514, 869 },
			["signpost"] = { 8, 820, 98 },
			["signpost-big"] = { 8, 869, 49 },
			["siren"] = { 8, 771, 147 },
			["skip-back"] = { 8, 147, 771 },
			["skip-forward"] = { 8, 98, 820 },
			["skull"] = { 8, 49, 869 },
			["slack"] = { 8, 0, 918 },
			["slash"] = { 8, 918, 257 },
			["slice"] = { 8, 869, 306 },
			["sliders"] = { 8, 404, 771 },
			["sliders-horizontal"] = { 8, 820, 355 },
			["sliders-vertical"] = { 8, 771, 404 },
			["smartphone"] = { 8, 257, 918 },
			["smartphone-charging"] = { 8, 355, 820 },
			["smartphone-nfc"] = { 8, 306, 869 },
			["smile"] = { 8, 869, 563 },
			["smile-plus"] = { 8, 918, 514 },
			["snail"] = { 8, 820, 612 },
			["snowflake"] = { 8, 771, 661 },
			["sofa"] = { 8, 661, 771 },
			["soup"] = { 8, 612, 820 },
			["space"] = { 8, 563, 869 },
			["spade"] = { 8, 514, 918 },
			["sparkle"] = { 8, 967, 0 },
			["sparkles"] = { 8, 918, 49 },
			["speaker"] = { 8, 869, 98 },
			["speech"] = { 8, 820, 147 },
			["spell-check"] = { 8, 196, 771 },
			["spell-check-2"] = { 8, 771, 196 },
			["spline"] = { 8, 147, 820 },
			["split"] = { 8, 0, 967 },
			["split-square-horizontal"] = { 8, 98, 869 },
			["split-square-vertical"] = { 8, 49, 918 },
			["spray-can"] = { 8, 967, 257 },
			["sprout"] = { 8, 918, 306 },
			["square"] = { 8, 869, 710 },
			["square-activity"] = { 8, 869, 355 },
			["square-arrow-down"] = { 8, 453, 771 },
			["square-arrow-down-left"] = { 8, 820, 404 },
			["square-arrow-down-right"] = { 8, 771, 453 },
			["square-arrow-left"] = { 8, 404, 820 },
			["square-arrow-out-down-left"] = { 8, 355, 869 },
			["square-arrow-out-down-right"] = { 8, 306, 918 },
			["square-arrow-out-up-left"] = { 8, 257, 967 },
			["square-arrow-out-up-right"] = { 8, 967, 514 },
			["square-arrow-right"] = { 8, 918, 563 },
			["square-arrow-up"] = { 8, 771, 710 },
			["square-arrow-up-left"] = { 8, 869, 612 },
			["square-arrow-up-right"] = { 8, 820, 661 },
			["square-asterisk"] = { 8, 710, 771 },
			["square-bottom-dashed-scissors"] = { 8, 661, 820 },
			["square-check"] = { 8, 563, 918 },
			["square-check-big"] = { 8, 612, 869 },
			["square-chevron-down"] = { 8, 514, 967 },
			["square-chevron-left"] = { 8, 967, 49 },
			["square-chevron-right"] = { 8, 918, 98 },
			["square-chevron-up"] = { 8, 869, 147 },
			["square-code"] = { 8, 820, 196 },
			["square-dashed-bottom"] = { 8, 147, 869 },
			["square-dashed-bottom-code"] = { 8, 196, 820 },
			["square-dashed-kanban"] = { 8, 98, 918 },
			["square-dashed-mouse-pointer"] = { 8, 49, 967 },
			["square-divide"] = { 8, 967, 306 },
			["square-dot"] = { 8, 918, 355 },
			["square-equal"] = { 8, 869, 404 },
			["square-function"] = { 8, 820, 453 },
			["square-gantt-chart"] = { 8, 453, 820 },
			["square-kanban"] = { 8, 404, 869 },
			["square-library"] = { 8, 355, 918 },
			["square-m"] = { 8, 306, 967 },
			["square-menu"] = { 8, 967, 563 },
			["square-minus"] = { 8, 918, 612 },
			["square-mouse-pointer"] = { 8, 869, 661 },
			["square-parking"] = { 8, 771, 759 },
			["square-parking-off"] = { 8, 820, 710 },
			["square-pen"] = { 8, 710, 820 },
			["square-percent"] = { 8, 661, 869 },
			["square-pi"] = { 8, 612, 918 },
			["square-pilcrow"] = { 8, 563, 967 },
			["square-play"] = { 8, 967, 98 },
			["square-plus"] = { 8, 918, 147 },
			["square-power"] = { 8, 869, 196 },
			["square-radical"] = { 8, 196, 869 },
			["square-scissors"] = { 8, 147, 918 },
			["square-sigma"] = { 8, 98, 967 },
			["square-slash"] = { 8, 967, 355 },
			["square-split-horizontal"] = { 8, 918, 404 },
			["square-split-vertical"] = { 8, 869, 453 },
			["square-stack"] = { 8, 453, 869 },
			["square-terminal"] = { 8, 404, 918 },
			["square-user"] = { 8, 967, 612 },
			["square-user-round"] = { 8, 355, 967 },
			["square-x"] = { 8, 918, 661 },
			["squircle"] = { 8, 820, 759 },
			["squirrel"] = { 8, 771, 808 },
			["stamp"] = { 8, 710, 869 },
			["star"] = { 8, 967, 147 },
			["star-half"] = { 8, 661, 918 },
			["star-off"] = { 8, 612, 967 },
			["step-back"] = { 8, 918, 196 },
			["step-forward"] = { 8, 196, 918 },
			["stethoscope"] = { 8, 147, 967 },
			["sticker"] = { 8, 967, 404 },
			["sticky-note"] = { 8, 918, 453 },
			["stop-circle"] = { 8, 453, 918 },
			["store"] = { 8, 404, 967 },
			["stretch-horizontal"] = { 8, 967, 661 },
			["stretch-vertical"] = { 8, 918, 710 },
			["strikethrough"] = { 8, 869, 759 },
			["subscript"] = { 8, 820, 808 },
			["subtitles"] = { 8, 771, 857 },
			["sun"] = { 8, 967, 453 },
			["sun-dim"] = { 8, 710, 918 },
			["sun-medium"] = { 8, 661, 967 },
			["sun-moon"] = { 8, 967, 196 },
			["sun-snow"] = { 8, 196, 967 },
			["sunrise"] = { 8, 453, 967 },
			["sunset"] = { 8, 967, 710 },
			["superscript"] = { 8, 918, 759 },
			["swatch-book"] = { 8, 869, 808 },
			["swiss-franc"] = { 8, 820, 857 },
			["switch-camera"] = { 8, 771, 906 },
			["sword"] = { 8, 710, 967 },
			["swords"] = { 8, 967, 759 },
			["syringe"] = { 8, 918, 808 },
			["table"] = { 8, 820, 955 },
			["table-2"] = { 8, 869, 857 },
			["table-cells-merge"] = { 8, 820, 906 },
			["table-cells-split"] = { 8, 771, 955 },
			["table-columns-split"] = { 8, 967, 808 },
			["table-properties"] = { 8, 918, 857 },
			["table-rows-split"] = { 8, 869, 906 },
			["tablet"] = { 8, 918, 906 },
			["tablet-smartphone"] = { 8, 967, 857 },
			["tablets"] = { 8, 869, 955 },
			["tag"] = { 8, 967, 906 },
			["tags"] = { 8, 918, 955 },
			["tally-1"] = { 8, 967, 955 },
			["tally-2"] = { 9, 771, 0 },
			["tally-3"] = { 9, 0, 771 },
			["tally-4"] = { 9, 771, 257 },
			["tally-5"] = { 9, 257, 771 },
			["tangent"] = { 9, 771, 514 },
			["target"] = { 9, 514, 771 },
			["telescope"] = { 9, 820, 0 },
			["tent"] = { 9, 49, 771 },
			["tent-tree"] = { 9, 771, 49 },
			["terminal"] = { 9, 820, 257 },
			["terminal-square"] = { 9, 0, 820 },
			["test-tube"] = { 9, 257, 820 },
			["test-tube-2"] = { 9, 771, 306 },
			["test-tube-diagonal"] = { 9, 306, 771 },
			["test-tubes"] = { 9, 820, 514 },
			["text"] = { 9, 771, 98 },
			["text-cursor"] = { 9, 563, 771 },
			["text-cursor-input"] = { 9, 771, 563 },
			["text-quote"] = { 9, 514, 820 },
			["text-search"] = { 9, 869, 0 },
			["text-select"] = { 9, 820, 49 },
			["theater"] = { 9, 98, 771 },
			["thermometer"] = { 9, 869, 257 },
			["thermometer-snowflake"] = { 9, 49, 820 },
			["thermometer-sun"] = { 9, 0, 869 },
			["thumbs-down"] = { 9, 820, 306 },
			["thumbs-up"] = { 9, 771, 355 },
			["ticket"] = { 9, 612, 771 },
			["ticket-check"] = { 9, 355, 771 },
			["ticket-minus"] = { 9, 306, 820 },
			["ticket-percent"] = { 9, 257, 869 },
			["ticket-plus"] = { 9, 869, 514 },
			["ticket-slash"] = { 9, 820, 563 },
			["ticket-x"] = { 9, 771, 612 },
			["timer"] = { 9, 918, 0 },
			["timer-off"] = { 9, 563, 820 },
			["timer-reset"] = { 9, 514, 869 },
			["toggle-left"] = { 9, 869, 49 },
			["toggle-right"] = { 9, 820, 98 },
			["tornado"] = { 9, 771, 147 },
			["torus"] = { 9, 147, 771 },
			["touchpad"] = { 9, 49, 869 },
			["touchpad-off"] = { 9, 98, 820 },
			["tower-control"] = { 9, 0, 918 },
			["toy-brick"] = { 9, 918, 257 },
			["tractor"] = { 9, 869, 306 },
			["traffic-cone"] = { 9, 820, 355 },
			["train-front"] = { 9, 404, 771 },
			["train-front-tunnel"] = { 9, 771, 404 },
			["train-track"] = { 9, 355, 820 },
			["tram-front"] = { 9, 306, 869 },
			["trash"] = { 9, 918, 514 },
			["trash-2"] = { 9, 257, 918 },
			["tree-deciduous"] = { 9, 869, 563 },
			["tree-palm"] = { 9, 820, 612 },
			["tree-pine"] = { 9, 771, 661 },
			["trees"] = { 9, 661, 771 },
			["trello"] = { 9, 612, 820 },
			["trending-down"] = { 9, 563, 869 },
			["trending-up"] = { 9, 514, 918 },
			["triangle"] = { 9, 869, 98 },
			["triangle-alert"] = { 9, 967, 0 },
			["triangle-right"] = { 9, 918, 49 },
			["trophy"] = { 9, 820, 147 },
			["truck"] = { 9, 771, 196 },
			["turtle"] = { 9, 196, 771 },
			["tv"] = { 9, 98, 869 },
			["tv-2"] = { 9, 147, 820 },
			["twitch"] = { 9, 49, 918 },
			["twitter"] = { 9, 0, 967 },
			["type"] = { 9, 967, 257 },
			["umbrella"] = { 9, 869, 355 },
			["umbrella-off"] = { 9, 918, 306 },
			["underline"] = { 9, 820, 404 },
			["undo"] = { 9, 404, 820 },
			["undo-2"] = { 9, 771, 453 },
			["undo-dot"] = { 9, 453, 771 },
			["unfold-horizontal"] = { 9, 355, 869 },
			["unfold-vertical"] = { 9, 306, 918 },
			["ungroup"] = { 9, 257, 967 },
			["university"] = { 9, 967, 514 },
			["unlink"] = { 9, 869, 612 },
			["unlink-2"] = { 9, 918, 563 },
			["unlock"] = { 9, 771, 710 },
			["unlock-keyhole"] = { 9, 820, 661 },
			["unplug"] = { 9, 710, 771 },
			["upload"] = { 9, 612, 869 },
			["upload-cloud"] = { 9, 661, 820 },
			["usb"] = { 9, 563, 918 },
			["user"] = { 9, 661, 869 },
			["user-2"] = { 9, 514, 967 },
			["user-check"] = { 9, 918, 98 },
			["user-check-2"] = { 9, 967, 49 },
			["user-circle"] = { 9, 820, 196 },
			["user-circle-2"] = { 9, 869, 147 },
			["user-cog"] = { 9, 147, 869 },
			["user-cog-2"] = { 9, 196, 820 },
			["user-minus"] = { 9, 49, 967 },
			["user-minus-2"] = { 9, 98, 918 },
			["user-plus"] = { 9, 918, 355 },
			["user-plus-2"] = { 9, 967, 306 },
			["user-round"] = { 9, 967, 563 },
			["user-round-check"] = { 9, 869, 404 },
			["user-round-cog"] = { 9, 820, 453 },
			["user-round-minus"] = { 9, 453, 820 },
			["user-round-plus"] = { 9, 404, 869 },
			["user-round-search"] = { 9, 355, 918 },
			["user-round-x"] = { 9, 306, 967 },
			["user-search"] = { 9, 918, 612 },
			["user-square"] = { 9, 820, 710 },
			["user-square-2"] = { 9, 869, 661 },
			["user-x"] = { 9, 710, 820 },
			["user-x-2"] = { 9, 771, 759 },
			["users"] = { 9, 967, 98 },
			["users-2"] = { 9, 612, 918 },
			["users-round"] = { 9, 563, 967 },
			["utensils"] = { 9, 869, 196 },
			["utensils-crossed"] = { 9, 918, 147 },
			["utility-pole"] = { 9, 196, 869 },
			["variable"] = { 9, 147, 918 },
			["vault"] = { 9, 98, 967 },
			["vegan"] = { 9, 967, 355 },
			["venetian-mask"] = { 9, 918, 404 },
			["vibrate"] = { 9, 453, 869 },
			["vibrate-off"] = { 9, 869, 453 },
			["video"] = { 9, 355, 967 },
			["video-off"] = { 9, 404, 918 },
			["videotape"] = { 9, 967, 612 },
			["view"] = { 9, 918, 661 },
			["voicemail"] = { 9, 869, 710 },
			["volume"] = { 9, 661, 918 },
			["volume-1"] = { 9, 820, 759 },
			["volume-2"] = { 9, 771, 808 },
			["volume-x"] = { 9, 710, 869 },
			["vote"] = { 9, 612, 967 },
			["wallet"] = { 9, 147, 967 },
			["wallet-2"] = { 9, 967, 147 },
			["wallet-cards"] = { 9, 918, 196 },
			["wallet-minimal"] = { 9, 196, 918 },
			["wallpaper"] = { 9, 967, 404 },
			["wand"] = { 9, 404, 967 },
			["wand-2"] = { 9, 918, 453 },
			["wand-sparkles"] = { 9, 453, 918 },
			["warehouse"] = { 9, 967, 661 },
			["washing-machine"] = { 9, 918, 710 },
			["watch"] = { 9, 869, 759 },
			["waves"] = { 9, 820, 808 },
			["waypoints"] = { 9, 771, 857 },
			["webcam"] = { 9, 710, 918 },
			["webhook"] = { 9, 967, 196 },
			["webhook-off"] = { 9, 661, 967 },
			["weight"] = { 9, 196, 967 },
			["wheat"] = { 9, 453, 967 },
			["wheat-off"] = { 9, 967, 453 },
			["whole-word"] = { 9, 967, 710 },
			["wifi"] = { 9, 869, 808 },
			["wifi-off"] = { 9, 918, 759 },
			["wind"] = { 9, 820, 857 },
			["wine"] = { 9, 710, 967 },
			["wine-off"] = { 9, 771, 906 },
			["workflow"] = { 9, 967, 759 },
			["worm"] = { 9, 918, 808 },
			["wrap-text"] = { 9, 869, 857 },
			["wrench"] = { 9, 820, 906 },
			["x"] = { 9, 869, 906 },
			["x-circle"] = { 9, 771, 955 },
			["x-octagon"] = { 9, 967, 808 },
			["x-square"] = { 9, 918, 857 },
			["youtube"] = { 9, 820, 955 },
			["zap"] = { 9, 918, 906 },
			["zap-off"] = { 9, 967, 857 },
			["zoom-in"] = { 9, 869, 955 },
			["zoom-out"] = { 9, 967, 906 },
		},
	}
end

__modules["core/Motion"] = function()
	-- Motion: every animation goes through here so the "Full / Soft / Off"
	-- setting is respected everywhere.
	--   Full — springs and slides (press 0.97 · 120 ms, Back Out 220 ms, Quint Out 280 ms)
	--   Soft — only fades (120 ms); sizes and positions change instantly
	--   Off  — everything instant

	local Services = import("core/Services")
	local Signal = import("util/Signal")

	local Motion = {
		Mode = "Full",
		Changed = Signal.new(),
	}

	local Style = Enum.EasingStyle
	local Dir = Enum.EasingDirection

	Motion.Presets = {
		press = TweenInfo.new(0.12, Style.Quad, Dir.Out),
		spring = TweenInfo.new(0.22, Style.Back, Dir.Out),
		window = TweenInfo.new(0.28, Style.Quint, Dir.Out),
		fade = TweenInfo.new(0.12, Style.Sine, Dir.Out),
		color = TweenInfo.new(0.16, Style.Quad, Dir.Out),
		flash = TweenInfo.new(0.6, Style.Quad, Dir.Out),
		linear = TweenInfo.new(1, Style.Linear, Dir.InOut),
	}

	local VISUAL = {
		BackgroundColor3 = true,
		BackgroundTransparency = true,
		TextColor3 = true,
		TextTransparency = true,
		TextStrokeTransparency = true,
		ImageColor3 = true,
		ImageTransparency = true,
		Color = true,
		Transparency = true,
		ScrollBarImageColor3 = true,
		PlaceholderColor3 = true,
	}

	function Motion.setMode(mode)
		if mode ~= "Full" and mode ~= "Soft" and mode ~= "Off" then
			mode = "Full"
		end
		if Motion.Mode ~= mode then
			Motion.Mode = mode
			Motion.Changed:Fire(mode)
		end
	end

	local function setAll(instance, props)
		for key, value in pairs(props) do
			instance[key] = value
		end
	end

	-- Tween `props` on `instance` using a named preset (or a TweenInfo).
	function Motion.tween(instance, props, preset)
		if Motion.Mode == "Off" then
			setAll(instance, props)
			return nil
		end
		if Motion.Mode == "Soft" then
			local visual = nil
			for key, value in pairs(props) do
				if VISUAL[key] then
					visual = visual or {}
					visual[key] = value
				else
					instance[key] = value
				end
			end
			if visual then
				local tween = Services.TweenService:Create(instance, Motion.Presets.fade, visual)
				tween:Play()
				return tween
			end
			return nil
		end
		local info = type(preset) == "string" and Motion.Presets[preset] or preset or Motion.Presets.color
		local tween = Services.TweenService:Create(instance, info, props)
		tween:Play()
		return tween
	end

	-- A custom-duration tween that still respects the mode.
	function Motion.tweenFor(instance, props, seconds, style, direction)
		return Motion.tween(instance, props, TweenInfo.new(seconds, style or Style.Quad, direction or Dir.Out))
	end

	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end

	-- Tactile press: shrinks `target` (default: the button) to `scale` while
	-- pressed and springs back on release. Returns the UIScale.
	function Motion.pressable(button, target, scale, maid)
		target = target or button
		local uiScale = target:FindFirstChildOfClass("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Parent = target
		end
		scale = scale or 0.97
		local pressed = false
		local function release()
			if pressed then
				pressed = false
				Motion.tween(uiScale, { Scale = 1 }, "spring")
			end
		end
		local c1 = button.InputBegan:Connect(function(input)
			if isPress(input) and Motion.Mode == "Full" then
				pressed = true
				Motion.tween(uiScale, { Scale = scale }, "press")
				-- a finger that slides off the button never fires its InputEnded
				local ended
				ended = Services.UserInputService.InputEnded:Connect(function(other)
					if other == input or other.UserInputType == Enum.UserInputType.MouseButton1 then
						ended:Disconnect()
						release()
					end
				end)
			end
		end)
		local c2 = button.InputEnded:Connect(function(input)
			if isPress(input) then
				release()
			end
		end)
		local c3 = button.MouseLeave:Connect(release)
		if maid then
			maid:Add(c1)
			maid:Add(c2)
			maid:Add(c3)
		end
		return uiScale
	end

	return Motion
end

__modules["core/Popup"] = function()
	-- Popup: anchored floating panels (dropdown lists, menus, colour picker) in
	-- the "Popups" layer. One popup at a time; tapping outside closes it.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Device = import("core/Device")
	local Icons = import("core/Icons")
	local Maid = import("util/Maid")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Popup = {}
	Popup.__index = Popup

	function Popup.new(window)
		local self = setmetatable({}, Popup)
		self.Window = window
		self.Layer = window.Root.Popups
		self.Current = nil
		return self
	end

	function Popup:Close()
		local current = self.Current
		if not current then
			return
		end
		self.Current = nil
		current.maid:Clean()
		if current.onClose then
			task.spawn(current.onClose)
		end
	end

	-- opts: anchor, width, build(container, handle), align ("left"|"right"|"center"),
	--       placement ("below"|"above"|"center"), onClose, gap
	function Popup:Open(opts)
		self:Close()
		local maid = Maid.new()
		local handle = { maid = maid, onClose = opts.onClose }
		self.Current = handle
		function handle.Close()
			if self.Current == handle then
				self:Close()
			end
		end

		local catcher = maid:Add(New("TextButton", {
			Name = "Catcher",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
			Parent = self.Layer,
		}))
		maid:Add(catcher.Activated:Connect(handle.Close))

		local width = opts.width
		if not width and opts.anchor then
			width = math.max(opts.anchor.AbsoluteSize.X, 200)
		end
		local container = maid:Add(New("Frame", {
			Name = "Popup",
			Size = UDim2.fromOffset(width or 220, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C("overlay"),
			ZIndex = 2,
			Active = true,
			Parent = self.Layer,
		}, {
			Create.corner(12),
			Create.stroke("borderStrong"),
			Create.pad(opts.padding or 6),
			Create.list("Vertical", 2),
		}))
		handle.Frame = container

		local scale = New("UIScale", { Scale = 0.96, Parent = container })

		local function place()
			local vp = Device.viewport()
			local size = container.AbsoluteSize
			local gap = opts.gap or 6
			local x, y
			if opts.anchor and opts.placement ~= "center" then
				local ap, as = Device.toOffset(opts.anchor.AbsolutePosition), opts.anchor.AbsoluteSize
				if opts.align == "left" then
					x = ap.X
				elseif opts.align == "center" then
					x = ap.X + as.X / 2 - size.X / 2
				else
					x = ap.X + as.X - size.X
				end
				y = ap.Y + as.Y + gap
				if opts.placement == "above" or (y + size.Y > vp.Y - 8 and ap.Y - gap - size.Y > Device.inset()) then
					y = ap.Y - gap - size.Y
				end
			else
				x = vp.X / 2 - size.X / 2
				y = vp.Y / 2 - size.Y / 2
			end
			x = math.clamp(x, 8, math.max(8, vp.X - size.X - 8))
			y = math.clamp(y, Device.inset() + 4, math.max(Device.inset() + 4, vp.Y - size.Y - 8))
			container.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
		end
		maid:Add(container:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))

		if opts.build then
			opts.build(container, handle)
		end
		place()
		task.defer(place)
		Motion.tween(scale, { Scale = 1 }, "spring")
		return handle
	end

	-- Simple menu. items: { Text, Icon, Danger, Checked, Disabled, Callback } or "divider"
	function Popup:Menu(anchor, items, opts)
		opts = opts or {}
		local loc = self.Window.Loc
		return self:Open({
			anchor = anchor,
			width = opts.width or 230,
			align = opts.align,
			placement = opts.placement,
			onClose = opts.onClose,
			build = function(container, handle)
				for index, item in ipairs(items) do
					if item == "divider" then
						New("Frame", {
							Size = UDim2.new(1, 0, 0, 1),
							BackgroundColor3 = C("divider"),
							LayoutOrder = index,
							Parent = container,
						})
					else
						local color = item.Danger and C("danger") or C("text")
						local button = New("TextButton", {
							Size = Theme.sz(1, 0, 0, "item"),
							BackgroundColor3 = C("raised"),
							BackgroundTransparency = 1,
							LayoutOrder = index,
							Parent = container,
						}, {
							Create.corner(8),
							Create.pad(0, 10),
							Create.list("Horizontal", 10, { valign = "Center" }),
						})
						if item.Icon then
							local icon = Icons.new(item.Icon, "iconSmall", item.Danger and C("danger") or C("textMuted"))
							icon.Frame.LayoutOrder = 1
							icon.Frame.Parent = button
						end
						local label = New("TextLabel", {
							Size = UDim2.fromScale(0, 1),
							TextColor3 = color,
							TextTruncate = Enum.TextTruncate.AtEnd,
							LayoutOrder = 2,
							Parent = button,
						}, { Create.flex() })
						loc:Bind(label, "Text", item.Text, item.Vars)
						if item.Hint then
							local hint = New("TextLabel", {
								AutomaticSize = Enum.AutomaticSize.X,
								Size = UDim2.fromScale(0, 1),
								TextColor3 = C("textSubtle"),
								TextSize = S("fontDesc"),
								LayoutOrder = 3,
								Parent = button,
							})
							loc:Bind(hint, "Text", item.Hint, item.HintVars)
						end
						if item.Checked then
							local check = Icons.new("check", "iconSmall", C("accent"))
							check.Frame.LayoutOrder = 4
							check.Frame.Parent = button
						end
						if item.Disabled then
							label.TextTransparency = 0.55
						else
							handle.maid:Add(button.MouseEnter:Connect(function()
								Motion.tween(button, { BackgroundTransparency = 0 }, "fade")
							end))
							handle.maid:Add(button.MouseLeave:Connect(function()
								Motion.tween(button, { BackgroundTransparency = 1 }, "fade")
							end))
							handle.maid:Add(button.Activated:Connect(function()
								handle.Close()
								if item.Callback then
									task.spawn(item.Callback)
								end
							end))
						end
					end
				end
			end,
		})
	end

	return Popup
end

__modules["core/Root"] = function()
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
		local Device = import("core/Device")
		Device.OriginLayer = self.Windows
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
end

__modules["core/Services"] = function()
	-- Services: lazily resolved (and cloneref'd when available) Roblox services.

	local Compat = import("util/Compat")

	return setmetatable({}, {
		__index = function(self, name)
			local service = Compat.service(name)
			rawset(self, name, service)
			return service
		end,
	})
end

__modules["core/Store"] = function()
	-- Store: the single source of truth for every control value (brief, rule 4).
	-- Controls only display values; configs, detached windows, the keybind panel
	-- and quick buttons all read and write through the same store.
	--
	-- Persist kinds: "profile" (saved in config profiles), "ui" (Robly's own
	-- interface settings, saved once per script), false (never saved).

	local Signal = import("util/Signal")
	local Util = import("util/Util")

	local Store = {}
	Store.__index = Store

	function Store.new()
		local self = setmetatable({}, Store)
		self.Values = {}
		self.Defaults = {}
		self.Meta = {}
		self.Loaded = {}
		self.LoadedKind = {}
		self.Changed = Signal.new()
		self._signals = {}
		return self
	end

	function Store:_signal(flag)
		local signal = self._signals[flag]
		if not signal then
			signal = Signal.new()
			self._signals[flag] = signal
		end
		return signal
	end

	-- Registers a flag. If a value for it was already loaded (from a config), that
	-- value wins. Returns value, wasLoaded.
	function Store:Register(flag, default, meta)
		meta = meta or {}
		self.Meta[flag] = meta
		self.Defaults[flag] = Util.copy(default)
		if self.Values[flag] == nil then
			self.Values[flag] = Util.copy(default)
			return self.Values[flag], false
		end
		local loaded = self.Values[flag]
		if meta.validate then
			local ok, fixed = pcall(meta.validate, loaded)
			if ok and fixed ~= nil then
				self.Values[flag] = fixed
			else
				self.Values[flag] = Util.copy(default)
			end
		elseif default ~= nil and typeof(loaded) ~= typeof(default) then
			self.Values[flag] = Util.copy(default)
		end
		return self.Values[flag], self.Loaded[flag] == true and not Util.equal(self.Values[flag], default)
	end

	function Store:Has(flag)
		return self.Meta[flag] ~= nil
	end

	function Store:Get(flag)
		return self.Values[flag]
	end

	function Store:Default(flag)
		return Util.copy(self.Defaults[flag])
	end

	function Store:Set(flag, value, source)
		local old = self.Values[flag]
		if Util.equal(old, value) then
			return false
		end
		self.Values[flag] = Util.copy(value)
		local signal = self._signals[flag]
		if signal then
			signal:Fire(value, old, source)
		end
		self.Changed:Fire(flag, value, old, source)
		return true
	end

	function Store:OnChanged(flag, fn)
		return self:_signal(flag):Connect(fn)
	end

	-- Serialisation ----------------------------------------------------------------

	local function encode(value)
		local kind = typeof(value)
		if kind == "Color3" then
			return { __t = "c3", v = Util.toHex(value) }
		elseif kind == "EnumItem" then
			return { __t = "enum", e = tostring(value.EnumType), v = value.Name }
		elseif kind == "table" then
			local out = {}
			for k, v in pairs(value) do
				out[k] = encode(v)
			end
			return out
		end
		return value
	end

	local function decode(value)
		if type(value) ~= "table" then
			return value
		end
		if value.__t == "c3" then
			return Util.hex(value.v)
		elseif value.__t == "enum" then
			local ok, item = pcall(function()
				return Enum[value.e][value.v]
			end)
			return ok and item or nil
		end
		local out = {}
		for k, v in pairs(value) do
			out[k] = decode(v)
		end
		return out
	end

	Store.encode = encode
	Store.decode = decode

	-- Snapshot of every flag with the given persist kind.
	function Store:Snapshot(kind)
		local out = {}
		for flag, meta in pairs(self.Meta) do
			if meta.persist == kind and self.Values[flag] ~= nil then
				out[flag] = encode(self.Values[flag])
			end
		end
		-- Values loaded from a file whose control does not exist (yet) are kept,
		-- so saving never silently drops them.
		for flag, loadedKind in pairs(self.LoadedKind) do
			if loadedKind == kind and not self.Meta[flag] and self.Values[flag] ~= nil then
				out[flag] = encode(self.Values[flag])
			end
		end
		return out
	end

	-- Applies a snapshot. Unknown flags are kept for later registration.
	function Store:Load(snapshot, source, kind)
		local count = 0
		for flag, raw in pairs(snapshot or {}) do
			local value = decode(raw)
			if value ~= nil then
				count += 1
				self.Loaded[flag] = true
				if kind then
					self.LoadedKind[flag] = kind
				end
				if self.Meta[flag] then
					self:Set(flag, value, source or "config")
				else
					self.Values[flag] = value
				end
			end
		end
		return count
	end

	function Store:ResetToDefaults(kind)
		for flag, meta in pairs(self.Meta) do
			if meta.persist == kind then
				self:Set(flag, Util.copy(self.Defaults[flag]), "reset")
			end
		end
	end

	function Store:Destroy()
		self.Changed:DisconnectAll()
		for _, signal in pairs(self._signals) do
			signal:DisconnectAll()
		end
		self._signals = {}
	end

	return Store
end

__modules["core/Strings"] = function()
	-- Built-in texts of the library itself (Cancel, Save, Settings, Theme…).
	-- They switch together with the script's language; authors can override any
	-- key through Language.Library = { ru = { cancel = "…" } }.

	local S = {}

	S.Names = {
		en = "English", ru = "Русский", es = "Español", pt = "Português", de = "Deutsch", fr = "Français",
		it = "Italiano", pl = "Polski", uk = "Українська", tr = "Türkçe", id = "Bahasa Indonesia",
		vi = "Tiếng Việt", th = "ไทย", ja = "日本語", ko = "한국어", zh = "中文", ar = "العربية",
		nl = "Nederlands", ro = "Română", cs = "Čeština", hu = "Magyar", fil = "Filipino",
	}

	S.en = {
		density = "Density", density_compact = "Compact", density_comfortable = "Comfortable",
		sidebar = "Sidebar", cards = "Cards", outline = "Outline", reset_overrides = "Reset hand-picked colours",
		accent2 = "Second accent", effect = "Background effect", effect_desc = "Animated layer behind the window content", glass = "Glass", glass_desc = "Panels let the background effect show through", effect_none = "None", effect_aurora = "Aurora", effect_stars = "Stars", effect_snow = "Snow", effect_grid = "Grid", effect_gradient = "Gradient",
		seconds = "{n}s", paused_short = "Paused", hud_hide_key = "Hide / show panel",
		settings = "Settings", theme = "Theme", configs = "Configs", interface = "Interface", about = "About",
		language = "Language", animations = "Animations", anim_full = "Full", anim_soft = "Soft", anim_off = "Off",
		toggle_key = "Show / hide", search = "Search features", cancel = "Cancel", more = "More",
		nothing_found = "Nothing found", results = "{n} {n|feature|features} · {t} {t|tab|tabs}",
		save = "Save", create = "Create", delete = "Delete", close = "Close", ok = "OK", copy = "Copy",
		export = "Export", import = "Import", load = "Load", overwrite = "Overwrite", rename = "Rename",
		accent = "Accent", background = "Background", surface = "Surface", text = "Text", custom = "Custom",
		more_colors = "All colours", reset_theme = "Reset theme",
		theme_copied = "Theme copied", theme_copied_desc = "Paste it anywhere to share",
		theme_imported = "Theme applied", theme_invalid = "This is not a Robly theme",
		import_theme = "Import theme", paste_theme = "Paste a robly1:… string",
		new_profile = "New profile", profile_name = "Profile name", default_profile = "Main",
		autosave = "Autosave", autosave_desc = "Saves the active profile on every change",
		autoload = "autoload", set_autoload = "Load on start", active = "active",
		delete_profile_q = "Delete profile “{name}”?", delete_profile_desc = "All values of this profile will be lost. This can't be undone.",
		config_saved = "Config saved", config_loaded = "Config loaded",
		profile_values = "Profile “{name}” · {n} {n|value|values}", profile_saved = "Profile “{name}”",
		no_fs = "No file system", no_fs_desc = "This executor has no writefile — settings live until you leave the game.",
		lang_detected = "Language: {lang}", lang_detected_desc = "Picked from your Roblox language", change = "Change",
		just_now = "just now", minutes_ago = "{n} min ago", hours_ago = "{n} h ago", yesterday = "yesterday", days_ago = "{n} {n|day|days} ago",
		detached_title = "“{tab}” is open in a separate window", detached_desc = "Values are shared — toggles work there and after returning.",
		return_to_window = "Return to window", open_in_window = "Open in separate window", detach = "Detach into window",
		detach_limit = "Up to {n} separate windows", detach_count = "{n} of {max}", release_to_return = "Release to return",
		binds = "Keybinds", binds_panel = "Keybind panel", show = "Show", all = "All", enabled_only = "Enabled",
		screen_edge = "Screen edge", left = "Left", right = "Right", bg_opacity = "Background transparency",
		hide_with_window = "Hide with the window", detached_hide = "Hide detached windows with the main one",
		quick_buttons = "Quick buttons", quick_buttons_desc = "Buttons at the screen edge for one-tap actions",
		on = "ON", off = "OFF", on_short = "On", off_short = "Off", paused = "Paused · typing",
		key_taken_game = "{key} is used by the game", key_taken_game_desc = "Pick another key or let Robly take it from the game.",
		key_taken_bind = "{key} is already set for “{name}”", key_taken_bind_desc = "Replace it or pick another key.",
		other_key = "Other key", take_key = "Take from game", replace = "Replace",
		press_key = "Press a key…", none = "None", show_window = "Show window", copied = "Copied", link_copied = "Link copied",
		copy_failed = "Copy it manually", minimize = "Minimize", expand = "Expand",
		close_q = "Close {name}?", close_desc = "The interface will be removed. Features that are already running may keep working.",
		locked = "locked", functions = "{n} {n|feature|features}", search_list = "Search", selected_n = "{n} selected",
		branding = "Robly by RobScript", missing_translation = "No translation for {key} ({lang})",
	}

	S.ru = {
		density = "Плотность", density_compact = "Компактно", density_comfortable = "Просторно",
		sidebar = "Боковая панель", cards = "Карточки", outline = "Обводка", reset_overrides = "Сбросить ручные цвета",
		accent2 = "Второй акцент", effect = "Фоновый эффект", effect_desc = "Анимированный слой за содержимым окна", glass = "Стекло", glass_desc = "Панели пропускают фоновый эффект", effect_none = "Нет", effect_aurora = "Сияние", effect_stars = "Звёзды", effect_snow = "Снег", effect_grid = "Сетка", effect_gradient = "Градиент",
		seconds = "{n} с", paused_short = "Пауза", hud_hide_key = "Скрыть / показать панель",
		settings = "Настройки", theme = "Тема", configs = "Конфиги", interface = "Интерфейс", about = "О библиотеке",
		language = "Язык", animations = "Анимации", anim_full = "Полные", anim_soft = "Мягкие", anim_off = "Выкл",
		toggle_key = "Показать / скрыть", search = "Поиск функций", cancel = "Отмена", more = "Ещё",
		nothing_found = "Ничего не найдено", results = "{n} {n|функция|функции|функций} · {t} {t|вкладка|вкладки|вкладок}",
		save = "Сохранить", create = "Создать", delete = "Удалить", close = "Закрыть", ok = "ОК", copy = "Копировать",
		export = "Экспорт", import = "Импорт", load = "Загрузить", overwrite = "Перезаписать", rename = "Переименовать",
		accent = "Акцент", background = "Фон", surface = "Поверхность", text = "Текст", custom = "Своя",
		more_colors = "Все цвета", reset_theme = "Сбросить тему",
		theme_copied = "Тема скопирована", theme_copied_desc = "Вставьте строку, чтобы поделиться",
		theme_imported = "Тема применена", theme_invalid = "Это не тема Robly",
		import_theme = "Импорт темы", paste_theme = "Вставьте строку robly1:…",
		new_profile = "Новый профиль", profile_name = "Название профиля", default_profile = "Основной",
		autosave = "Автосохранение", autosave_desc = "Сохраняет активный профиль при каждом изменении",
		autoload = "автозагрузка", set_autoload = "Загружать при старте", active = "активный",
		delete_profile_q = "Удалить профиль «{name}»?", delete_profile_desc = "Все значения этого профиля пропадут. Отменить нельзя.",
		config_saved = "Конфиг сохранён", config_loaded = "Конфиг загружен",
		profile_values = "Профиль «{name}» · {n} {n|значение|значения|значений}", profile_saved = "Профиль «{name}»",
		no_fs = "Нет файловой системы", no_fs_desc = "Экзекутор не поддерживает writefile — конфиг живёт до выхода из игры.",
		lang_detected = "Язык: {lang}", lang_detected_desc = "По языку Roblox", change = "Сменить",
		just_now = "только что", minutes_ago = "{n} мин назад", hours_ago = "{n} ч назад", yesterday = "вчера", days_ago = "{n} {n|день|дня|дней} назад",
		detached_title = "«{tab}» открыт в отдельном окне", detached_desc = "Значения общие — переключатели работают и там, и после возврата.",
		return_to_window = "Вернуть в окно", open_in_window = "Открыть в отдельном окне", detach = "Вынести в отдельное окно",
		detach_limit = "Не больше {n} отдельных окон", detach_count = "{n} из {max}", release_to_return = "Отпустите, чтобы вернуть",
		binds = "Бинды", binds_panel = "Панель биндов", show = "Показывать", all = "Все", enabled_only = "Включённые",
		screen_edge = "Край экрана", left = "Слева", right = "Справа", bg_opacity = "Прозрачность фона",
		hide_with_window = "Прятать вместе с окном", detached_hide = "Прятать отдельные окна вместе с главным",
		quick_buttons = "Быстрые кнопки", quick_buttons_desc = "Кнопки у края экрана для действий в одно касание",
		on = "ВКЛ", off = "ВЫКЛ", on_short = "Вкл", off_short = "Выкл", paused = "Пауза · ввод текста",
		key_taken_game = "{key} уже использует игра", key_taken_game_desc = "Выберите другую клавишу или разрешите Robly перехватить её у игры.",
		key_taken_bind = "{key} уже назначена на «{name}»", key_taken_bind_desc = "Заменить назначение или выбрать другую клавишу?",
		other_key = "Другая клавиша", take_key = "Перехватить у игры", replace = "Заменить",
		press_key = "Нажмите клавишу…", none = "Нет", show_window = "Показать окно", copied = "Скопировано", link_copied = "Ссылка скопирована",
		copy_failed = "Скопируйте вручную", minimize = "Свернуть", expand = "Развернуть",
		close_q = "Закрыть {name}?", close_desc = "Интерфейс будет удалён. Уже запущенные функции могут продолжить работу.",
		locked = "заблокировано", functions = "{n} {n|функция|функции|функций}", search_list = "Найти", selected_n = "Выбрано: {n}",
		branding = "Robly by RobScript", missing_translation = "Нет перевода {key} для {lang}",
	}

	S.es = {
		density = "Densidad", density_compact = "Compacta", density_comfortable = "Amplia",
		sidebar = "Barra lateral", cards = "Tarjetas", outline = "Contorno", reset_overrides = "Restablecer colores manuales",
		accent2 = "Segundo acento", effect = "Efecto de fondo", effect_desc = "Capa animada detrás del contenido", glass = "Cristal", glass_desc = "Los paneles dejan ver el efecto de fondo", effect_none = "Ninguno", effect_aurora = "Aurora", effect_stars = "Estrellas", effect_snow = "Nieve", effect_grid = "Cuadrícula", effect_gradient = "Degradado",
		seconds = "{n} s", paused_short = "Pausa", hud_hide_key = "Ocultar / mostrar panel",
		settings = "Ajustes", theme = "Tema", configs = "Configuraciones", interface = "Interfaz", about = "Acerca de",
		language = "Idioma", animations = "Animaciones", anim_full = "Completas", anim_soft = "Suaves", anim_off = "No",
		toggle_key = "Mostrar / ocultar", search = "Buscar funciones", cancel = "Cancelar", more = "Más",
		nothing_found = "Sin resultados", results = "{n} {n|función|funciones} · {t} {t|pestaña|pestañas}",
		save = "Guardar", create = "Crear", delete = "Eliminar", close = "Cerrar", ok = "OK", copy = "Copiar",
		export = "Exportar", import = "Importar", load = "Cargar", overwrite = "Sobrescribir", rename = "Renombrar",
		accent = "Acento", background = "Fondo", surface = "Superficie", text = "Texto", custom = "Propio",
		more_colors = "Todos los colores", reset_theme = "Restablecer tema",
		theme_copied = "Tema copiado", theme_copied_desc = "Pégalo donde quieras para compartirlo",
		theme_imported = "Tema aplicado", theme_invalid = "No es un tema de Robly",
		import_theme = "Importar tema", paste_theme = "Pega una cadena robly1:…",
		new_profile = "Nuevo perfil", profile_name = "Nombre del perfil", default_profile = "Principal",
		autosave = "Autoguardado", autosave_desc = "Guarda el perfil activo en cada cambio",
		autoload = "carga automática", set_autoload = "Cargar al iniciar", active = "activo",
		delete_profile_q = "¿Eliminar el perfil «{name}»?", delete_profile_desc = "Se perderán todos sus valores. No se puede deshacer.",
		config_saved = "Configuración guardada", config_loaded = "Configuración cargada",
		profile_values = "Perfil «{name}» · {n} {n|valor|valores}", profile_saved = "Perfil «{name}»",
		no_fs = "Sin sistema de archivos", no_fs_desc = "El ejecutor no tiene writefile: los ajustes duran hasta salir del juego.",
		lang_detected = "Idioma: {lang}", lang_detected_desc = "Según tu idioma de Roblox", change = "Cambiar",
		just_now = "ahora", minutes_ago = "hace {n} min", hours_ago = "hace {n} h", yesterday = "ayer", days_ago = "hace {n} {n|día|días}",
		detached_title = "«{tab}» está abierta en otra ventana", detached_desc = "Los valores son compartidos: todo sigue funcionando al volver.",
		return_to_window = "Volver a la ventana", open_in_window = "Abrir en otra ventana", detach = "Separar en ventana",
		detach_limit = "Máximo {n} ventanas separadas", detach_count = "{n} de {max}", release_to_return = "Suelta para devolver",
		binds = "Atajos", binds_panel = "Panel de atajos", show = "Mostrar", all = "Todos", enabled_only = "Activos",
		screen_edge = "Borde", left = "Izquierda", right = "Derecha", bg_opacity = "Transparencia del fondo",
		hide_with_window = "Ocultar con la ventana", detached_hide = "Ocultar ventanas separadas con la principal",
		quick_buttons = "Botones rápidos", quick_buttons_desc = "Botones en el borde para acciones de un toque",
		on = "SÍ", off = "NO", on_short = "Sí", off_short = "No", paused = "Pausa · escribiendo",
		key_taken_game = "El juego usa {key}", key_taken_game_desc = "Elige otra tecla o deja que Robly la tome del juego.",
		key_taken_bind = "{key} ya está asignada a «{name}»", key_taken_bind_desc = "¿Reemplazar o elegir otra tecla?",
		other_key = "Otra tecla", take_key = "Tomar del juego", replace = "Reemplazar",
		press_key = "Pulsa una tecla…", none = "Ninguna", show_window = "Mostrar ventana", copied = "Copiado", link_copied = "Enlace copiado",
		copy_failed = "Cópialo manualmente", minimize = "Minimizar", expand = "Expandir",
		close_q = "¿Cerrar {name}?", close_desc = "Se quitará la interfaz. Las funciones activas pueden seguir funcionando.",
		locked = "bloqueado", functions = "{n} {n|función|funciones}", search_list = "Buscar", selected_n = "{n} seleccionados",
		branding = "Robly by RobScript", missing_translation = "Falta traducción de {key} ({lang})",
	}

	S.pt = {
		density = "Densidade", density_compact = "Compacta", density_comfortable = "Espaçosa",
		sidebar = "Barra lateral", cards = "Cartões", outline = "Contorno", reset_overrides = "Redefinir cores manuais",
		accent2 = "Segundo destaque", effect = "Efeito de fundo", effect_desc = "Camada animada atrás do conteúdo", glass = "Vidro", glass_desc = "Os painéis deixam ver o efeito de fundo", effect_none = "Nenhum", effect_aurora = "Aurora", effect_stars = "Estrelas", effect_snow = "Neve", effect_grid = "Grade", effect_gradient = "Gradiente",
		seconds = "{n} s", paused_short = "Pausa", hud_hide_key = "Ocultar / mostrar painel",
		settings = "Configurações", theme = "Tema", configs = "Perfis", interface = "Interface", about = "Sobre",
		language = "Idioma", animations = "Animações", anim_full = "Completas", anim_soft = "Suaves", anim_off = "Desligadas",
		toggle_key = "Mostrar / ocultar", search = "Buscar funções", cancel = "Cancelar", more = "Mais",
		nothing_found = "Nada encontrado", results = "{n} {n|função|funções} · {t} {t|aba|abas}",
		save = "Salvar", create = "Criar", delete = "Excluir", close = "Fechar", ok = "OK", copy = "Copiar",
		export = "Exportar", import = "Importar", load = "Carregar", overwrite = "Sobrescrever", rename = "Renomear",
		accent = "Destaque", background = "Fundo", surface = "Superfície", text = "Texto", custom = "Personalizado",
		more_colors = "Todas as cores", reset_theme = "Redefinir tema",
		theme_copied = "Tema copiado", theme_copied_desc = "Cole onde quiser para compartilhar",
		theme_imported = "Tema aplicado", theme_invalid = "Isto não é um tema Robly",
		import_theme = "Importar tema", paste_theme = "Cole uma string robly1:…",
		new_profile = "Novo perfil", profile_name = "Nome do perfil", default_profile = "Principal",
		autosave = "Salvar automaticamente", autosave_desc = "Salva o perfil ativo a cada mudança",
		autoload = "carregamento automático", set_autoload = "Carregar ao iniciar", active = "ativo",
		delete_profile_q = "Excluir o perfil “{name}”?", delete_profile_desc = "Todos os valores serão perdidos. Não dá para desfazer.",
		config_saved = "Perfil salvo", config_loaded = "Perfil carregado",
		profile_values = "Perfil “{name}” · {n} {n|valor|valores}", profile_saved = "Perfil “{name}”",
		no_fs = "Sem sistema de arquivos", no_fs_desc = "O executor não tem writefile — as configurações duram até sair do jogo.",
		lang_detected = "Idioma: {lang}", lang_detected_desc = "Pelo idioma do Roblox", change = "Mudar",
		just_now = "agora", minutes_ago = "há {n} min", hours_ago = "há {n} h", yesterday = "ontem", days_ago = "há {n} {n|dia|dias}",
		detached_title = "“{tab}” está aberta em outra janela", detached_desc = "Os valores são compartilhados — tudo continua funcionando ao voltar.",
		return_to_window = "Voltar para a janela", open_in_window = "Abrir em janela separada", detach = "Separar em janela",
		detach_limit = "No máximo {n} janelas separadas", detach_count = "{n} de {max}", release_to_return = "Solte para devolver",
		binds = "Atalhos", binds_panel = "Painel de atalhos", show = "Mostrar", all = "Todos", enabled_only = "Ligados",
		screen_edge = "Borda", left = "Esquerda", right = "Direita", bg_opacity = "Transparência do fundo",
		hide_with_window = "Ocultar com a janela", detached_hide = "Ocultar janelas separadas com a principal",
		quick_buttons = "Botões rápidos", quick_buttons_desc = "Botões na borda para ações com um toque",
		on = "LIG", off = "DESL", on_short = "Lig", off_short = "Desl", paused = "Pausa · digitando",
		key_taken_game = "O jogo usa {key}", key_taken_game_desc = "Escolha outra tecla ou deixe o Robly tomá-la do jogo.",
		key_taken_bind = "{key} já está em “{name}”", key_taken_bind_desc = "Substituir ou escolher outra tecla?",
		other_key = "Outra tecla", take_key = "Tomar do jogo", replace = "Substituir",
		press_key = "Pressione uma tecla…", none = "Nenhuma", show_window = "Mostrar janela", copied = "Copiado", link_copied = "Link copiado",
		copy_failed = "Copie manualmente", minimize = "Minimizar", expand = "Expandir",
		close_q = "Fechar {name}?", close_desc = "A interface será removida. Funções já ativas podem continuar.",
		locked = "bloqueado", functions = "{n} {n|função|funções}", search_list = "Buscar", selected_n = "{n} selecionados",
		branding = "Robly by RobScript", missing_translation = "Sem tradução de {key} ({lang})",
	}

	S.de = {
		density = "Dichte", density_compact = "Kompakt", density_comfortable = "Großzügig",
		sidebar = "Seitenleiste", cards = "Karten", outline = "Umriss", reset_overrides = "Eigene Farben zurücksetzen",
		accent2 = "Zweiter Akzent", effect = "Hintergrundeffekt", effect_desc = "Animierte Ebene hinter dem Inhalt", glass = "Glas", glass_desc = "Flächen lassen den Hintergrundeffekt durchscheinen", effect_none = "Keiner", effect_aurora = "Polarlicht", effect_stars = "Sterne", effect_snow = "Schnee", effect_grid = "Raster", effect_gradient = "Verlauf",
		seconds = "{n} s", paused_short = "Pause", hud_hide_key = "Panel aus- / einblenden",
		settings = "Einstellungen", theme = "Design", configs = "Profile", interface = "Oberfläche", about = "Über",
		language = "Sprache", animations = "Animationen", anim_full = "Voll", anim_soft = "Sanft", anim_off = "Aus",
		toggle_key = "Ein- / ausblenden", search = "Funktionen suchen", cancel = "Abbrechen", more = "Mehr",
		nothing_found = "Nichts gefunden", results = "{n} {n|Funktion|Funktionen} · {t} {t|Tab|Tabs}",
		save = "Speichern", create = "Erstellen", delete = "Löschen", close = "Schließen", ok = "OK", copy = "Kopieren",
		export = "Exportieren", import = "Importieren", load = "Laden", overwrite = "Überschreiben", rename = "Umbenennen",
		accent = "Akzent", background = "Hintergrund", surface = "Fläche", text = "Text", custom = "Eigenes",
		more_colors = "Alle Farben", reset_theme = "Design zurücksetzen",
		theme_copied = "Design kopiert", theme_copied_desc = "Zum Teilen irgendwo einfügen",
		theme_imported = "Design angewendet", theme_invalid = "Das ist kein Robly-Design",
		import_theme = "Design importieren", paste_theme = "robly1:…-Text einfügen",
		new_profile = "Neues Profil", profile_name = "Profilname", default_profile = "Haupt",
		autosave = "Automatisch speichern", autosave_desc = "Speichert das aktive Profil bei jeder Änderung",
		autoload = "Autoladen", set_autoload = "Beim Start laden", active = "aktiv",
		delete_profile_q = "Profil „{name}“ löschen?", delete_profile_desc = "Alle Werte dieses Profils gehen verloren. Nicht umkehrbar.",
		config_saved = "Profil gespeichert", config_loaded = "Profil geladen",
		profile_values = "Profil „{name}“ · {n} {n|Wert|Werte}", profile_saved = "Profil „{name}“",
		no_fs = "Kein Dateisystem", no_fs_desc = "Der Executor hat kein writefile — Einstellungen gelten bis zum Verlassen des Spiels.",
		lang_detected = "Sprache: {lang}", lang_detected_desc = "Nach deiner Roblox-Sprache", change = "Ändern",
		just_now = "gerade eben", minutes_ago = "vor {n} Min.", hours_ago = "vor {n} Std.", yesterday = "gestern", days_ago = "vor {n} {n|Tag|Tagen}",
		detached_title = "„{tab}“ ist in einem eigenen Fenster geöffnet", detached_desc = "Werte sind geteilt — alles funktioniert dort und nach der Rückkehr.",
		return_to_window = "Zurück ins Fenster", open_in_window = "In eigenem Fenster öffnen", detach = "In Fenster lösen",
		detach_limit = "Höchstens {n} eigene Fenster", detach_count = "{n} von {max}", release_to_return = "Loslassen zum Zurückgeben",
		binds = "Tasten", binds_panel = "Tastenpanel", show = "Anzeigen", all = "Alle", enabled_only = "Aktive",
		screen_edge = "Bildschirmrand", left = "Links", right = "Rechts", bg_opacity = "Hintergrund-Transparenz",
		hide_with_window = "Mit dem Fenster ausblenden", detached_hide = "Eigene Fenster mit dem Hauptfenster ausblenden",
		quick_buttons = "Schnelltasten", quick_buttons_desc = "Tasten am Rand für Aktionen mit einem Tippen",
		on = "AN", off = "AUS", on_short = "An", off_short = "Aus", paused = "Pause · Texteingabe",
		key_taken_game = "{key} wird vom Spiel benutzt", key_taken_game_desc = "Andere Taste wählen oder Robly die Taste übernehmen lassen.",
		key_taken_bind = "{key} ist schon „{name}“ zugewiesen", key_taken_bind_desc = "Ersetzen oder andere Taste wählen?",
		other_key = "Andere Taste", take_key = "Vom Spiel übernehmen", replace = "Ersetzen",
		press_key = "Taste drücken…", none = "Keine", show_window = "Fenster zeigen", copied = "Kopiert", link_copied = "Link kopiert",
		copy_failed = "Bitte manuell kopieren", minimize = "Minimieren", expand = "Erweitern",
		close_q = "{name} schließen?", close_desc = "Die Oberfläche wird entfernt. Laufende Funktionen können weiterlaufen.",
		locked = "gesperrt", functions = "{n} {n|Funktion|Funktionen}", search_list = "Suchen", selected_n = "{n} ausgewählt",
		branding = "Robly by RobScript", missing_translation = "Keine Übersetzung für {key} ({lang})",
	}

	S.fr = {
		density = "Densité", density_compact = "Compacte", density_comfortable = "Aérée",
		sidebar = "Barre latérale", cards = "Cartes", outline = "Contour", reset_overrides = "Réinitialiser les couleurs perso",
		accent2 = "Second accent", effect = "Effet de fond", effect_desc = "Calque animé derrière le contenu", glass = "Verre", glass_desc = "Les panneaux laissent voir l'effet de fond", effect_none = "Aucun", effect_aurora = "Aurore", effect_stars = "Étoiles", effect_snow = "Neige", effect_grid = "Grille", effect_gradient = "Dégradé",
		seconds = "{n} s", paused_short = "Pause", hud_hide_key = "Masquer / afficher le panneau",
		settings = "Paramètres", theme = "Thème", configs = "Profils", interface = "Interface", about = "À propos",
		language = "Langue", animations = "Animations", anim_full = "Complètes", anim_soft = "Douces", anim_off = "Non",
		toggle_key = "Afficher / masquer", search = "Rechercher", cancel = "Annuler", more = "Plus",
		nothing_found = "Aucun résultat", results = "{n} {n|fonction|fonctions} · {t} {t|onglet|onglets}",
		save = "Enregistrer", create = "Créer", delete = "Supprimer", close = "Fermer", ok = "OK", copy = "Copier",
		export = "Exporter", import = "Importer", load = "Charger", overwrite = "Écraser", rename = "Renommer",
		accent = "Accent", background = "Fond", surface = "Surface", text = "Texte", custom = "Perso",
		more_colors = "Toutes les couleurs", reset_theme = "Réinitialiser le thème",
		theme_copied = "Thème copié", theme_copied_desc = "Collez-le pour le partager",
		theme_imported = "Thème appliqué", theme_invalid = "Ce n'est pas un thème Robly",
		import_theme = "Importer un thème", paste_theme = "Collez une chaîne robly1:…",
		new_profile = "Nouveau profil", profile_name = "Nom du profil", default_profile = "Principal",
		autosave = "Sauvegarde auto", autosave_desc = "Enregistre le profil actif à chaque changement",
		autoload = "chargement auto", set_autoload = "Charger au démarrage", active = "actif",
		delete_profile_q = "Supprimer le profil « {name} » ?", delete_profile_desc = "Toutes ses valeurs seront perdues. Action irréversible.",
		config_saved = "Profil enregistré", config_loaded = "Profil chargé",
		profile_values = "Profil « {name} » · {n} {n|valeur|valeurs}", profile_saved = "Profil « {name} »",
		no_fs = "Pas de système de fichiers", no_fs_desc = "L'exécuteur n'a pas writefile — les réglages durent jusqu'à la sortie du jeu.",
		lang_detected = "Langue : {lang}", lang_detected_desc = "Selon votre langue Roblox", change = "Changer",
		just_now = "à l'instant", minutes_ago = "il y a {n} min", hours_ago = "il y a {n} h", yesterday = "hier", days_ago = "il y a {n} {n|jour|jours}",
		detached_title = "« {tab} » est ouvert dans une fenêtre séparée", detached_desc = "Les valeurs sont partagées — tout marche là-bas et après le retour.",
		return_to_window = "Revenir dans la fenêtre", open_in_window = "Ouvrir dans une fenêtre", detach = "Détacher en fenêtre",
		detach_limit = "{n} fenêtres séparées au maximum", detach_count = "{n} sur {max}", release_to_return = "Relâchez pour rattacher",
		binds = "Raccourcis", binds_panel = "Panneau des raccourcis", show = "Afficher", all = "Tous", enabled_only = "Actifs",
		screen_edge = "Bord de l'écran", left = "Gauche", right = "Droite", bg_opacity = "Transparence du fond",
		hide_with_window = "Masquer avec la fenêtre", detached_hide = "Masquer les fenêtres séparées avec la principale",
		quick_buttons = "Boutons rapides", quick_buttons_desc = "Boutons au bord de l'écran en un geste",
		on = "OUI", off = "NON", on_short = "Oui", off_short = "Non", paused = "Pause · saisie",
		key_taken_game = "{key} est utilisée par le jeu", key_taken_game_desc = "Choisissez une autre touche ou laissez Robly la prendre au jeu.",
		key_taken_bind = "{key} est déjà pour « {name} »", key_taken_bind_desc = "Remplacer ou choisir une autre touche ?",
		other_key = "Autre touche", take_key = "Prendre au jeu", replace = "Remplacer",
		press_key = "Appuyez sur une touche…", none = "Aucune", show_window = "Afficher la fenêtre", copied = "Copié", link_copied = "Lien copié",
		copy_failed = "Copiez-le manuellement", minimize = "Réduire", expand = "Agrandir",
		close_q = "Fermer {name} ?", close_desc = "L'interface sera supprimée. Les fonctions en cours peuvent continuer.",
		locked = "verrouillé", functions = "{n} {n|fonction|fonctions}", search_list = "Rechercher", selected_n = "{n} sélectionnés",
		branding = "Robly by RobScript", missing_translation = "Pas de traduction pour {key} ({lang})",
	}

	return S
end

__modules["core/Theme"] = function()
	-- Theme: a theme is a table of semantic colour tokens; sizes are a second
	-- table chosen by device (one code, two/three sets of size tokens).
	--
	-- Components never hard-code colours or sizes. Instead they bind a property
	-- to a token:
	--     Theme.bind(frame, "BackgroundColor3", Theme.c("surface"))
	--     Theme.bind(frame, "Size", Theme.sz(1, 0, 0, "row"))
	-- When the theme or the device mode changes, every bound property is
	-- re-applied in place — no window re-creation, no restart.

	local Signal = import("util/Signal")
	local Util = import("util/Util")
	local Motion = import("core/Motion")

	local Theme = {}

	Theme.Changed = Signal.new()

	-- Colour tokens ------------------------------------------------------------
	--
	-- A theme is a few BASE colours; every other token is DERIVED from them, so
	-- changing the background (or the accent, or the text) repaints the whole
	-- window: sidebar, cards, outlines, popups, tracks… Any derived token can still
	-- be overridden on its own (theme editor, "All colours"); overrides survive
	-- base changes until the theme is reset.

	Theme.BaseKeys = { "accent", "accent2", "bg", "text", "success", "warning", "danger" }

	-- Editable in the theme editor's main list (base + the most visible derived ones)
	Theme.MainKeys = { "accent", "accent2", "bg", "nav", "surface", "border", "text" }

	-- Every token, in export / "All colours" order.
	Theme.TokenOrder = {
		"accent", "accent2", "bg", "nav", "surface", "border", "text",
		"raised", "overlay", "sunken", "selected", "segment", "borderStrong", "divider",
		"textMuted", "textSubtle", "accentInk", "accentPressed", "track", "toggleOff",
		"knobOn", "knobOff", "checkBorder", "success", "warning", "danger", "dangerInk",
		"tooltip", "tooltipText", "backdrop", "code", "codeText",
	}

	local function isBase(key)
		return table.find(Theme.BaseKeys, key) ~= nil
	end
	Theme.isBase = isBase

	-- Builds the full token table from a spec (base colours + optional overrides).
	function Theme.derive(spec)
		local function get(key, fallback)
			local value = spec[key]
			if typeof(value) == "Color3" then
				return value
			end
			return Util.hex(value) or fallback
		end
		local bg = get("bg", Color3.fromRGB(18, 18, 22))
		local text = get("text", Color3.fromRGB(242, 242, 245))
		local accent = get("accent", Color3.fromRGB(255, 59, 127))
		local dark = Util.luminance(bg) < 0.4
		local black = Color3.new(0, 0, 0)
		local white = Color3.new(1, 1, 1)
		local h, sat, val = accent:ToHSV()
		local c = {
			accent = accent,
			-- second accent for gradients and background effects (default: a
			-- neighbouring hue of the accent)
			accent2 = get("accent2", Color3.fromHSV((h + 0.09) % 1, math.min(1, sat * 0.95), math.min(1, val * 1.02))),
			bg = bg,
			text = text,
			success = get("success", Color3.fromRGB(52, 211, 153)),
			warning = get("warning", Color3.fromRGB(251, 191, 36)),
			danger = get("danger", Color3.fromRGB(255, 90, 90)),
		}
		local function d(key, value)
			c[key] = get(key, nil) or value
		end
		-- surfaces step away from the background towards the text colour
		d("nav", dark and bg:Lerp(black, 0.18) or bg:Lerp(text, 0.045))
		d("surface", bg:Lerp(text, dark and 0.028 or 0.035))
		d("border", bg:Lerp(text, dark and 0.075 or 0.1))
		d("raised", c.surface:Lerp(text, dark and 0.055 or 0.05))
		d("overlay", dark and bg:Lerp(text, 0.045) or bg)
		d("sunken", dark and c.nav or bg:Lerp(text, 0.07))
		d("selected", c.nav:Lerp(text, dark and 0.085 or 0.08))
		d("segment", dark and c.surface:Lerp(text, 0.09) or white)
		d("borderStrong", c.border:Lerp(text, dark and 0.035 or 0.08))
		d("divider", bg:Lerp(c.border, 0.75))
		d("textMuted", text:Lerp(bg, 0.34))
		d("textSubtle", text:Lerp(bg, 0.47))
		d("accentInk", Util.inkFor(accent))
		d("accentPressed", Util.darken(accent, 0.12))
		d("track", c.borderStrong)
		d("toggleOff", c.surface:Lerp(text, dark and 0.15 or 0.16))
		-- a pale accent (Graphite) needs a dark knob to stay visible
		d("knobOn", Util.contrast(accent, white) < 1.6 and bg or white)
		d("knobOff", white)
		d("checkBorder", c.surface:Lerp(text, dark and 0.22 or 0.28))
		d("dangerInk", Util.inkFor(c.danger))
		d("tooltip", text)
		d("tooltipText", bg)
		d("backdrop", bg:Lerp(black, 0.6))
		d("code", dark and c.nav:Lerp(black, 0.2) or c.sunken)
		d("codeText", text:Lerp(bg, 0.12))
		return c
	end

	-- Presets are specs; Theme.Presets holds their derived colours for previews.
	-- Each preset also has a default background effect.
	local PRESETS = {
		{ "RobScript", { accent = "FF3B7F", accent2 = "9B5CFF", bg = "121216", text = "F2F2F5", accentInk = "1A0610" }, "Aurora" },
		{ "Light", { accent = "E0245E", accent2 = "FF7A59", bg = "FFFFFF", text = "16161A", success = "0E9F6E", warning = "B7791F", danger = "E5484D" }, "None" },
		{ "Graphite", { accent = "E6E6E8", accent2 = "9A9AA2", bg = "1B1B1D", text = "EDEDEE" }, "Grid" },
		{ "Midnight", { accent = "4C8DFF", accent2 = "8B5CF6", bg = "0E1320", text = "E8EDF7" }, "Stars" },
		{ "Sakura", { accent = "FF8FB8", accent2 = "FFC2D6", bg = "1A1216", text = "F7EEF2" }, "Snow" },
		{ "Ocean", { accent = "22D3EE", accent2 = "3B82F6", bg = "0A1620", text = "E6F4F8" }, "Aurora" },
		{ "Matcha", { accent = "7BD389", accent2 = "C3E88D", bg = "111712", text = "ECF3EC" }, "Aurora" },
		{ "Sunset", { accent = "FF7A45", accent2 = "FF3D7F", bg = "1A1012", text = "FBEDE7" }, "Gradient" },
		{ "Amber", { accent = "FFB020", accent2 = "FF7A00", bg = "16130C", text = "F7F1E3" }, "Gradient" },
		{ "Crimson", { accent = "FF4D4D", accent2 = "B3123A", bg = "140C0D", text = "F5ECEC" }, "Grid" },
		{ "Cyber", { accent = "00F0FF", accent2 = "FF00C8", bg = "0A0A12", text = "E8F7FF" }, "Grid" },
		{ "Synthwave", { accent = "FF2E97", accent2 = "7B61FF", bg = "140A24", text = "F5E9FF" }, "Stars" },
		{ "Dracula", { accent = "BD93F9", accent2 = "FF79C6", bg = "1E1F29", text = "F8F8F2" }, "Stars" },
		{ "Nord", { accent = "88C0D0", accent2 = "81A1C1", bg = "1F2430", text = "ECEFF4" }, "Snow" },
		{ "Frost", { accent = "7DD3FC", accent2 = "C4B5FD", bg = "0D1117", text = "E6EDF3" }, "Snow" },
		{ "Lavender", { accent = "B794F6", accent2 = "F0ABFC", bg = "15121D", text = "F3EEFB" }, "Aurora" },
		{ "Coffee", { accent = "D4A373", accent2 = "A47148", bg = "16110D", text = "F1E9E1" }, "None" },
		{ "Mono", { accent = "FFFFFF", accent2 = "8A8A8A", bg = "0E0E0E", text = "F2F2F2" }, "None" },
	}
	Theme.PresetSpecs = {}
	Theme.PresetEffects = {}
	Theme.PresetOrder = {}
	for _, entry in ipairs(PRESETS) do
		Theme.PresetSpecs[entry[1]] = entry[2]
		Theme.PresetEffects[entry[1]] = entry[3]
		table.insert(Theme.PresetOrder, entry[1])
	end
	Theme.Presets = {}
	for name, spec in pairs(Theme.PresetSpecs) do
		Theme.Presets[name] = Theme.derive(spec)
	end

	-- Background effect inside the window and "glass" (translucent panels).
	Theme.Effects = { "None", "Aurora", "Stars", "Snow", "Grid", "Gradient" }
	Theme.Effect = "Aurora"
	Theme.Glass = true

	function Theme.setEffect(effect)
		if not table.find(Theme.Effects, effect) then
			effect = "None"
		end
		Theme.Effect = effect
		Theme.refresh()
		Theme.Changed:Fire("effect")
	end

	function Theme.setGlass(enabled)
		Theme.Glass = enabled == true
		Theme.refresh()
		Theme.Changed:Fire("effect")
	end

	-- Transparency for panels that let the background effect show through.
	function Theme.glass(amount)
		return Theme.f(function()
			if Theme.Glass and Theme.Effect ~= "None" then
				return amount or 0.22
			end
			return 0
		end)
	end

	-- Accent → accent2 gradient (UIGradient.Color); the element itself must be white.
	function Theme.gradient()
		return Theme.f(function(c)
			return ColorSequence.new(c.accent, c.accent2)
		end)
	end

	Theme.Name = "RobScript"
	Theme.Spec = table.clone(Theme.PresetSpecs.RobScript)
	Theme.Colors = Theme.derive(Theme.Spec)

	-- Size tokens ------------------------------------------------------------------

	-- PC has two densities: "compact" (default, Obsidian-like dense rows) and
	-- "comfortable" (the roomier original). Touch sizes keep 44 px targets.
	local PC_COMFORTABLE = {
		header = 56, sidebar = 200, navItem = 38, rail = 56, tabbar = 60,
		row = 46, rowDesc = 54, control = 32, button = 34, input = 36,
		toggleW = 44, toggleH = 26, knob = 22, checkbox = 20,
		track = 6, sliderKnob = 18, sliderHit = 24, segment = 28, stepperBtn = 32, chip = 30, hit = 32,
		font = 14, fontDesc = 12, fontSmall = 11, fontSection = 14, fontTitle = 22, fontHeader = 14,
		padX = 14, padY = 7, gap = 14, contentX = 22, contentTop = 18, contentBottom = 20, sectionGap = 12,
		rWindow = 16, rSection = 12, rControl = 9, rSmall = 8, rBadge = 6,
		icon = 18, iconSmall = 16, item = 34, toastWidth = 280, scrollBar = 3,
		groupHeader = 40, groupPad = 4, columnGap = 12, dividers = true,
		touch = false, pageHeader = true, dropdownFlat = false,
	}

	local PC = {
		header = 48, sidebar = 186, navItem = 34, rail = 56, tabbar = 60,
		row = 36, rowDesc = 44, control = 26, button = 30, input = 30,
		toggleW = 34, toggleH = 20, knob = 16, checkbox = 16,
		track = 4, sliderKnob = 14, sliderHit = 18, segment = 24, stepperBtn = 26, chip = 24, hit = 30,
		font = 13, fontDesc = 11, fontSmall = 11, fontSection = 13, fontTitle = 18, fontHeader = 13,
		padX = 12, padY = 5, gap = 12, contentX = 14, contentTop = 12, contentBottom = 14, sectionGap = 10,
		rWindow = 12, rSection = 10, rControl = 7, rSmall = 6, rBadge = 5,
		icon = 16, iconSmall = 14, item = 28, toastWidth = 270, scrollBar = 3,
		groupHeader = 34, groupPad = 3, columnGap = 10, dividers = false,
		touch = false, pageHeader = true, dropdownFlat = false,
	}

	local PHONE = {
		header = 44, sidebar = 56, navItem = 44, rail = 56, tabbar = 60,
		row = 52, rowDesc = 56, control = 44, button = 44, input = 44,
		toggleW = 51, toggleH = 31, knob = 27, checkbox = 24,
		track = 6, sliderKnob = 28, sliderHit = 44, segment = 40, stepperBtn = 44, chip = 36, hit = 44,
		font = 15, fontDesc = 13, fontSmall = 12, fontSection = 14, fontTitle = 16, fontHeader = 16,
		padX = 12, padY = 4, gap = 12, contentX = 12, contentTop = 0, contentBottom = 12, sectionGap = 8,
		rWindow = 18, rSection = 14, rControl = 10, rSmall = 10, rBadge = 6,
		icon = 20, iconSmall = 18, item = 44, toastWidth = 300, scrollBar = 0,
		groupHeader = 44, groupPad = 2, columnGap = 8, dividers = true,
		touch = true, pageHeader = false, dropdownFlat = true,
	}

	local TABLET = Util.merge(PHONE, {
		header = 52, fontTitle = 18, contentX = 16, contentTop = 4, contentBottom = 16,
		rWindow = 22, rSection = 16, padX = 14, sectionGap = 10,
	})

	Theme.Densities = { compact = PC, comfortable = PC_COMFORTABLE }
	Theme.Density = "compact"
	Theme.SizeSets = { pc = PC, phone = PHONE, tablet = TABLET }
	Theme.Mode = "pc"
	Theme.Sizes = PC

	-- Fonts -------------------------------------------------------------------------

	local FONT_UI = "rbxasset://fonts/families/BuilderSans.json"
	local FONT_MONO = "rbxasset://fonts/families/RobotoMono.json"
	local fontCache = {}

	function Theme.font(weight, mono)
		weight = weight or "Regular"
		local key = (mono and "m" or "u") .. weight
		local cached = fontCache[key]
		if cached then
			return cached
		end
		local ok, font = pcall(function()
			return Font.new(mono and FONT_MONO or FONT_UI, Enum.FontWeight[weight] or Enum.FontWeight.Regular)
		end)
		if not ok then
			ok, font = pcall(Font.fromEnum, mono and Enum.Font.RobotoMono or Enum.Font.BuilderSans)
		end
		if ok then
			fontCache[key] = font
			return font
		end
		return nil
	end

	-- Tokens ---------------------------------------------------------------------------

	local Token = {}
	Token.__index = Token

	function Theme.c(name)
		return setmetatable({ kind = "c", name = name }, Token)
	end

	function Theme.s(name)
		return setmetatable({ kind = "s", name = name }, Token)
	end

	function Theme.f(fn)
		return setmetatable({ kind = "f", fn = fn }, Token)
	end

	function Theme.isToken(value)
		return getmetatable(value) == Token
	end

	local MISSING = Color3.fromRGB(255, 0, 255)

	function Theme.resolve(token)
		if token.kind == "c" then
			local color = Theme.Colors[token.name]
			if color == nil then
				warn("[Robly] unknown colour token: " .. tostring(token.name))
				return MISSING
			end
			return color
		elseif token.kind == "s" then
			return Theme.Sizes[token.name]
		end
		return token.fn(Theme.Colors, Theme.Sizes, Theme.Mode)
	end

	-- Helpers that build common computed tokens.
	local function num(value, sizes)
		if type(value) == "string" then
			return sizes[value]
		end
		return value or 0
	end

	function Theme.ud(scale, offset)
		if offset == nil then
			offset, scale = scale, 0
		end
		return Theme.f(function(_, s)
			return UDim.new(scale, num(offset, s))
		end)
	end

	function Theme.sz(xs, xo, ys, yo)
		return Theme.f(function(_, s)
			return UDim2.new(xs, num(xo, s), ys, num(yo, s))
		end)
	end

	function Theme.v2(x, y)
		return Theme.f(function(_, s)
			return Vector2.new(num(x, s), num(y, s))
		end)
	end

	-- Bindings -------------------------------------------------------------------------

	-- Strong tables on purpose: Roblox may garbage-collect the Lua wrapper of an
	-- Instance that is still alive in the game, so a weak-keyed table would
	-- silently lose bindings of labels nobody keeps a reference to. Entries are
	-- removed when the instance is destroyed.
	local bindings = {}
	-- colour tweens started by Theme.set; cancelled on refresh so an old tween
	-- can't finish on a colour from the previous theme
	local tweens = {}
	local watched = {}

	local function watch(instance)
		if watched[instance] then
			return
		end
		watched[instance] = true
		pcall(function()
			instance.Destroying:Connect(function()
				bindings[instance] = nil
				tweens[instance] = nil
				watched[instance] = nil
			end)
		end)
	end
	Theme.watchDestroy = watch

	function Theme.bind(instance, prop, token)
		local props = bindings[instance]
		if not props then
			props = {}
			bindings[instance] = props
			watch(instance)
		end
		props[prop] = token
		instance[prop] = Theme.resolve(token)
	end

	function Theme.unbind(instance, prop)
		local props = bindings[instance]
		if props then
			props[prop] = nil
		end
	end

	-- Re-bind to a new token and animate to its value (state changes such as a
	-- toggle turning on).
	function Theme.set(instance, prop, token, preset)
		local props = bindings[instance]
		if not props then
			props = {}
			bindings[instance] = props
			watch(instance)
		end
		props[prop] = token
		local tween = Motion.tween(instance, { [prop] = Theme.resolve(token) }, preset or "color")
		if tween then
			local running = tweens[instance]
			if not running then
				running = {}
				tweens[instance] = running
			end
			running[prop] = tween
		end
	end

	function Theme.refresh()
		for _, running in pairs(tweens) do
			for _, tween in pairs(running) do
				pcall(tween.Cancel, tween)
			end
		end
		table.clear(tweens)
		for instance, props in pairs(bindings) do
			for prop, token in pairs(props) do
				local ok, value = pcall(Theme.resolve, token)
				if ok and value ~= nil then
					instance[prop] = value
				end
			end
		end
	end

	-- Theme switching ------------------------------------------------------------------

	local function toSpec(colors)
		local spec = {}
		for key, value in pairs(colors) do
			local color = typeof(value) == "Color3" and value or Util.hex(value)
			if color then
				spec[key] = color
			end
		end
		return spec
	end

	local function commit()
		Theme.Colors = Theme.derive(Theme.Spec)
		Theme.refresh()
		Theme.Changed:Fire("colors")
	end

	-- apply("Midnight") · apply({ accent = …, bg = … }) (missing base colours come
	-- from RobScript, everything else is derived)
	function Theme.apply(nameOrColors)
		if type(nameOrColors) == "string" then
			local found = Theme.PresetSpecs[nameOrColors]
			if not found then
				warn("[Robly] unknown theme: " .. nameOrColors)
				return false
			end
			Theme.Name = nameOrColors
			Theme.Spec = toSpec(found)
			Theme.Effect = Theme.PresetEffects[nameOrColors] or Theme.Effect
		elseif type(nameOrColors) == "table" then
			local spec = toSpec(Theme.PresetSpecs.RobScript)
			spec.accentInk = nil
			for key, value in pairs(toSpec(nameOrColors)) do
				spec[key] = value
			end
			Theme.Name = "Custom"
			Theme.Spec = spec
		else
			return false
		end
		commit()
		return true
	end

	-- Change one token (theme editor). A base colour re-derives everything that
	-- isn't overridden; any other token becomes an override.
	function Theme.setToken(name, color)
		Theme.Spec[name] = color
		if name == "accent" then
			Theme.Spec.accentInk = nil
			Theme.Spec.accentPressed = nil
			Theme.Spec.knobOn = nil
		end
		Theme.Name = "Custom"
		commit()
	end

	-- Drop the override of a derived token (back to "follows the base colours").
	function Theme.clearToken(name)
		if not isBase(name) then
			Theme.Spec[name] = nil
			commit()
		end
	end

	function Theme.isOverridden(name)
		return not isBase(name) and Theme.Spec[name] ~= nil
	end

	function Theme.setDensity(density)
		local sizes = Theme.Densities[density]
		if not sizes or Theme.Density == density then
			return
		end
		Theme.Density = density
		Theme.SizeSets.pc = sizes
		if Theme.Mode == "pc" then
			Theme.Sizes = sizes
			Theme.refresh()
			Theme.Changed:Fire("density")
		end
	end

	function Theme.setMode(mode)
		local sizes = Theme.SizeSets[mode]
		if not sizes or Theme.Mode == mode then
			return
		end
		Theme.Mode = mode
		Theme.Sizes = sizes
		Theme.refresh()
		Theme.Changed:Fire("sizes")
	end

	-- Export / import as a short string to share on Discord:
	--   robly2:<base64 of "name;key=RRGGBB;key=RRGGBB…"> — only the spec
	--   robly1:<base64 of "name;hex;hex…">            — old full list, still imported
	function Theme.export(spec, name)
		spec = spec or Theme.Spec
		local parts = { (tostring(name or Theme.Name):gsub("[;=]", "")) }
		for _, key in ipairs(Theme.TokenOrder) do
			local value = spec[key]
			if typeof(value) == "Color3" then
				table.insert(parts, key .. "=" .. Util.toHex(value))
			end
		end
		return "robly2:" .. Util.base64Encode(table.concat(parts, ";"))
	end

	function Theme.import(text)
		text = Util.trim(tostring(text or ""))
		local version, payload = text:match("^robly([12]):(.+)$")
		if not payload then
			return nil, "format"
		end
		local ok, decoded = pcall(Util.base64Decode, payload)
		if not ok then
			return nil, "decode"
		end
		local parts = string.split(decoded, ";")
		local spec = {}
		if version == "2" then
			for index = 2, #parts do
				local key, hex = parts[index]:match("^(%w+)=(%x+)$")
				if key and table.find(Theme.TokenOrder, key) then
					spec[key] = Util.hex(hex)
				end
			end
		else
			local old = {
				"accent", "bg", "nav", "surface", "raised", "overlay", "sunken", "selected", "segment",
				"border", "borderStrong", "divider", "text", "textMuted", "textSubtle",
				"accentInk", "accentPressed", "track", "toggleOff", "knobOn", "knobOff", "checkBorder",
				"success", "warning", "danger", "dangerInk", "tooltip", "tooltipText", "backdrop", "code", "codeText",
			}
			for index, key in ipairs(old) do
				local color = parts[index + 1] and Util.hex(parts[index + 1])
				if color then
					spec[key] = color
				end
			end
		end
		if not (spec.accent and spec.bg and spec.text) then
			return nil, "incomplete"
		end
		return spec, parts[1]
	end

	function Theme.serialize()
		local out = { name = Theme.Name, effect = Theme.Effect, glass = Theme.Glass }
		if Theme.Name == "Custom" then
			out.spec = {}
			for key, color in pairs(Theme.Spec) do
				out.spec[key] = Util.toHex(color)
			end
		end
		return out
	end

	function Theme.deserialize(data)
		if type(data) ~= "table" then
			return
		end
		if type(data.effect) == "string" then
			Theme.Effect = table.find(Theme.Effects, data.effect) and data.effect or Theme.Effect
		end
		if data.glass ~= nil then
			Theme.Glass = data.glass == true
		end
		local raw = data.spec or data.colors -- "colors" = 1.0 full list
		if data.name == "Custom" and type(raw) == "table" then
			local effect = Theme.Effect
			local spec = toSpec(raw)
			if data.colors and not data.spec then
				-- 1.0 saved every token; keep only the base so everything follows
				local base = {}
				for _, key in ipairs(Theme.BaseKeys) do
					base[key] = spec[key]
				end
				spec = base
			end
			Theme.Name = "Custom"
			Theme.Spec = spec
			commit()
		elseif type(data.name) == "string" and Theme.PresetSpecs[data.name] then
			local effect = Theme.Effect
			Theme.apply(data.name)
			if type(data.effect) == "string" then
				Theme.setEffect(effect)
			end
		end
	end

	return Theme
end

__modules["init"] = function()
	-- Robly — UI library for Roblox scripts by RobScript (https://robscript.com)
	-- Public domain (The Unlicense). See README.md for the full API.

	local Theme = import("core/Theme")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Localization = import("core/Localization")
	local Util = import("util/Util")
	local Window = import("ui/Window")

	local Robly = {
		Version = "1.4.0",
		Windows = {},
		Themes = Theme.Presets,
		Effects = Theme.Effects,
		ThemeOrder = Theme.PresetOrder,
		Icons = Icons.Data,
		L = Localization.L,
	}

	-- Robly:CreateWindow({ Title, Subtitle, Logo, Folder, Theme, Language, ToggleKey, Branding, ... })
	function Robly:CreateWindow(options)
		local window = Window.new(self, options)
		table.insert(self.Windows, window)
		return window
	end
	Robly.Window = Robly.CreateWindow
	Robly.New = Robly.CreateWindow

	function Robly:_windowClosed(window)
		local index = table.find(self.Windows, window)
		if index then
			table.remove(self.Windows, index)
		end
	end

	-- Switch theme for every window: a preset name (see Robly.Themes / the 18
	-- built-in presets), a custom registered name, or a colour table.
	function Robly:SetTheme(theme)
		Theme.apply(theme)
	end

	-- Register a theme preset: colours as Color3 or "#RRGGBB"; missing tokens
	-- fall back to RobScript.
	function Robly:AddTheme(name, colors)
		-- a theme is its base colours (accent, bg, text, …); the rest is derived,
		-- and any token given here overrides the derived value
		local spec = {}
		for key, value in pairs(Theme.PresetSpecs.RobScript) do
			if Theme.isBase(key) then
				spec[key] = value
			end
		end
		for key, value in pairs(colors) do
			if key == "Effect" or key == "effect" then
				Theme.PresetEffects[name] = value
			else
				spec[key] = typeof(value) == "Color3" and value or Util.hex(value)
			end
		end
		Theme.PresetSpecs[name] = spec
		local out = Theme.derive(spec)
		Theme.Presets[name] = out
		if not table.find(Theme.PresetOrder, name) then
			table.insert(Theme.PresetOrder, name)
		end
		return out
	end

	-- Background effect inside every window: "None", "Aurora", "Stars", "Snow",
	-- "Grid", "Gradient".
	function Robly:SetEffect(effect)
		Theme.setEffect(effect)
	end

	-- Glass: panels become translucent so the background effect shows through.
	function Robly:SetGlass(enabled)
		Theme.setGlass(enabled)
	end

	function Robly:SetAnimations(mode)
		Motion.setMode(mode)
	end

	function Robly:Notify(options)
		local window = self.Windows[#self.Windows]
		if window then
			return window:Notify(options)
		end
		return nil
	end

	function Robly:Destroy()
		for _, window in ipairs(table.clone(self.Windows)) do
			window:Destroy()
		end
	end

	return Robly
end

__modules["system/Binds"] = function()
	-- Binds: keyboard shortcuts for the whole window.
	--
	-- Rules from the brief (§15):
	--   1. Paused while typing — nothing fires while a TextBox (chat, game input,
	--      Robly field) has focus, and presses the game already processed are
	--      ignored.
	--   2. Game conflicts — a key the game uses is reported when assigned; Robly
	--      only takes it from the game (ContextActionService, high priority, Sink)
	--      if the player agreed. That choice is saved with the bind.
	--   3. Phones have no keyboard — quick buttons replace the panel.
	--
	-- A bind's value lives in the Store as { Key = "Ctrl+X", Override = false }.

	local Services = import("core/Services")
	local Signal = import("util/Signal")

	local Binds = {}
	Binds.__index = Binds

	local MODIFIERS = {
		LeftControl = "Ctrl", RightControl = "Ctrl", LeftShift = "Shift", RightShift = "Shift",
		LeftAlt = "Alt", RightAlt = "Alt", LeftSuper = "Meta", RightSuper = "Meta",
	}

	local DISPLAY = {
		LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
		LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", Backquote = "`", Minus = "-", Equals = "=",
		LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",", Period = ".",
		Slash = "/", BackSlash = "\\", Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
		Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", PageUp = "PgUp", PageDown = "PgDn",
		Escape = "Esc", Delete = "Del", Insert = "Ins", CapsLock = "Caps",
	}

	-- Keys Roblox itself (or most games) use.
	Binds.GameKeys = {
		W = true, A = true, S = true, D = true, Space = true, Tab = true, Slash = true, Backquote = true,
		Escape = true, Up = true, Down = true, Left = true, Right = true, I = true, O = true,
		LeftShift = true, F9 = true, Return = true, Backspace = true,
	}

	local parseCache = {}

	function Binds.parse(text)
		if type(text) ~= "string" or text == "" then
			return nil
		end
		local cached = parseCache[text]
		if cached then
			return cached
		end
		local parts = string.split(text, "+")
		local keyName = parts[#parts]
		local ok, key = pcall(function()
			return Enum.KeyCode[keyName]
		end)
		if not ok or not key then
			return nil
		end
		local parsed = { key = key, Ctrl = false, Shift = false, Alt = false, Meta = false }
		for i = 1, #parts - 1 do
			parsed[parts[i]] = true
		end
		parseCache[text] = parsed
		return parsed
	end

	function Binds.normalize(value)
		if typeof(value) == "EnumItem" then
			return value.Name
		end
		if type(value) == "string" then
			return value
		end
		return ""
	end

	function Binds.display(text)
		if type(text) ~= "string" or text == "" then
			return nil
		end
		local parts = string.split(text, "+")
		for index, part in ipairs(parts) do
			parts[index] = DISPLAY[part] or part
		end
		return table.concat(parts, "+")
	end

	local function held(uis, name, except)
		local keys = {
			Ctrl = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl },
			Shift = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
			Alt = { Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt },
			Meta = { Enum.KeyCode.LeftSuper, Enum.KeyCode.RightSuper },
		}
		for _, key in ipairs(keys[name]) do
			if key ~= except and uis:IsKeyDown(key) then
				return true
			end
		end
		return false
	end

	function Binds.matches(text, keyCode)
		local parsed = Binds.parse(text)
		if not parsed or parsed.key ~= keyCode then
			return false
		end
		local uis = Services.UserInputService
		for _, name in ipairs({ "Ctrl", "Shift", "Alt" }) do
			if parsed[name] ~= held(uis, name, keyCode) then
				return false
			end
		end
		return true
	end

	function Binds.new(window)
		local self = setmetatable({}, Binds)
		self.Window = window
		self.Store = window.Store
		self.Entries = {}
		self.Fired = Signal.new()
		self.Changed = Signal.new()
		self.PausedChanged = Signal.new()
		self.Paused = false
		self.Capturing = nil
		self._connections = {}
		self._counter = 0

		local uis = Services.UserInputService
		local function typing()
			local ok, box = pcall(function()
				return uis:GetFocusedTextBox()
			end)
			return ok and box ~= nil
		end
		local function setPaused(value)
			if self.Paused ~= value then
				self.Paused = value
				self.PausedChanged:Fire(value)
			end
		end
		table.insert(self._connections, uis.TextBoxFocused:Connect(function()
			setPaused(true)
		end))
		table.insert(self._connections, uis.TextBoxFocusReleased:Connect(function()
			task.defer(function()
				setPaused(typing())
			end)
		end))

		table.insert(self._connections, uis.InputBegan:Connect(function(input, processed)
			if input.UserInputType ~= Enum.UserInputType.Keyboard or self.Capturing or typing() then
				return
			end
			for _, entry in ipairs(table.clone(self.Entries)) do
				local value = self.Store:Get(entry.Flag)
				if type(value) == "table" and not value.Override and Binds.matches(value.Key, input.KeyCode) then
					if not processed then
						self:Trigger(entry, true)
					end
				end
			end
		end))
		table.insert(self._connections, uis.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			for _, entry in ipairs(table.clone(self.Entries)) do
				if entry.Mode == "Hold" and entry.Down then
					local value = self.Store:Get(entry.Flag)
					local parsed = type(value) == "table" and Binds.parse(value.Key)
					if parsed and parsed.key == input.KeyCode and not value.Override then
						self:Trigger(entry, false)
					end
				end
			end
		end))
		return self
	end

	function Binds:KeyOf(entry)
		local value = self.Store:Get(entry.Flag)
		return type(value) == "table" and value.Key or ""
	end

	function Binds:Add(entry)
		self._counter += 1
		entry.Id = entry.Id or ("bind" .. self._counter)
		entry.Mode = entry.Mode or (entry.Target and "Toggle" or "Action")
		entry.LastFired = 0
		table.insert(self.Entries, entry)
		entry._watch = self.Store:OnChanged(entry.Flag, function()
			self:_rebind(entry)
			self.Changed:Fire()
		end)
		if entry.Target then
			entry._target = self.Store:OnChanged(entry.Target, function()
				self.Changed:Fire()
			end)
		end
		self:_rebind(entry)
		self.Changed:Fire()
		return entry
	end

	function Binds:Remove(entry)
		local index = table.find(self.Entries, entry)
		if index then
			table.remove(self.Entries, index)
		end
		if entry._watch then
			entry._watch:Disconnect()
		end
		if entry._target then
			entry._target:Disconnect()
		end
		self:_unbindAction(entry)
		self.Changed:Fire()
	end

	function Binds:_unbindAction(entry)
		if entry._action then
			pcall(function()
				Services.ContextActionService:UnbindAction(entry._action)
			end)
			entry._action = nil
		end
	end

	-- Keys the player allowed Robly to take from the game are bound through
	-- ContextActionService at a high priority and sunk.
	function Binds:_rebind(entry)
		self:_unbindAction(entry)
		local value = self.Store:Get(entry.Flag)
		if type(value) ~= "table" or not value.Override then
			return
		end
		local parsed = Binds.parse(value.Key)
		if not parsed then
			return
		end
		local name = "Robly_" .. entry.Id .. "_" .. tostring(self.Window.Id)
		entry._action = name
		pcall(function()
			Services.ContextActionService:BindActionAtPriority(name, function(_, state, input)
				local ok, box = pcall(function()
					return Services.UserInputService:GetFocusedTextBox()
				end)
				if (ok and box) or self.Capturing then
					return Enum.ContextActionResult.Pass
				end
				if state == Enum.UserInputState.Begin then
					if Binds.matches(value.Key, input.KeyCode) then
						self:Trigger(entry, true)
						return Enum.ContextActionResult.Sink
					end
				elseif state == Enum.UserInputState.End and entry.Mode == "Hold" and entry.Down then
					self:Trigger(entry, false)
					return Enum.ContextActionResult.Sink
				end
				return Enum.ContextActionResult.Pass
			end, false, 3000, parsed.key)
		end)
	end

	function Binds:IsOn(entry)
		if entry.Target then
			return self.Store:Get(entry.Target) == true
		end
		return entry.Down == true
	end

	function Binds:CooldownLeft(entry)
		if not entry.Cooldown then
			return 0
		end
		return math.max(0, entry.Cooldown - (os.clock() - entry.LastFired))
	end

	function Binds:Trigger(entry, down)
		local control = entry.Control
		if control and (control.Destroyed or not control.Enabled) and not entry.System then
			return
		end
		local state = nil
		if entry.Mode == "Toggle" and entry.Target then
			if not down then
				return
			end
			state = not (self.Store:Get(entry.Target) == true)
			self.Store:Set(entry.Target, state, "bind")
			if entry.Callback then
				task.spawn(entry.Callback, state)
			end
		elseif entry.Mode == "Hold" then
			entry.Down = down
			state = down
			if entry.Callback then
				task.spawn(entry.Callback, down)
			end
		else
			if not down then
				return
			end
			if self:CooldownLeft(entry) > 0 then
				return
			end
			entry.LastFired = os.clock()
			if entry.Callback then
				task.spawn(entry.Callback)
			end
		end
		self.Fired:Fire(entry, state, down)
	end

	-- Conflicts ---------------------------------------------------------------------------

	function Binds:GameConflict(text)
		local parsed = Binds.parse(text)
		if not parsed then
			return false
		end
		if Binds.GameKeys[parsed.key.Name] and not (parsed.Ctrl or parsed.Alt) then
			return true
		end
		local ok, actions = pcall(function()
			return Services.ContextActionService:GetAllBoundActionInfo()
		end)
		if ok and type(actions) == "table" then
			for name, info in pairs(actions) do
				if type(name) == "string" and not name:find("^Robly_") and type(info) == "table" and type(info.inputTypes) == "table" then
					for _, inputType in ipairs(info.inputTypes) do
						if inputType == parsed.key then
							return true
						end
					end
				end
			end
		end
		return false
	end

	function Binds:BindConflict(text, except)
		if type(text) ~= "string" or text == "" then
			return nil
		end
		for _, entry in ipairs(self.Entries) do
			if entry ~= except and self:KeyOf(entry) == text then
				return entry
			end
		end
		return nil
	end

	-- Capture -----------------------------------------------------------------------------------

	-- Waits for the next key (with modifiers). callback(key) — key is "" when
	-- cleared (Backspace/Delete) and nil when cancelled (Escape / cancel()).
	function Binds:Capture(callback)
		self:CancelCapture()
		local uis = Services.UserInputService
		local capture = {}
		local onlyModifier = nil
		local function finish(result)
			if capture.done then
				return
			end
			capture.done = true
			capture.began:Disconnect()
			capture.ended:Disconnect()
			-- clear after this input event, so the same key press can't fire a bind
			task.defer(function()
				if self.Capturing == capture then
					self.Capturing = nil
				end
			end)
			task.spawn(callback, result)
		end
		capture.finish = finish
		capture.began = uis.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			local name = input.KeyCode.Name
			if input.KeyCode == Enum.KeyCode.Escape then
				finish(nil)
				return
			end
			if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				finish("")
				return
			end
			if MODIFIERS[name] then
				onlyModifier = name
				return
			end
			onlyModifier = nil
			local parts = {}
			for _, mod in ipairs({ "Ctrl", "Shift", "Alt" }) do
				if held(uis, mod, input.KeyCode) then
					table.insert(parts, mod)
				end
			end
			table.insert(parts, name)
			finish(table.concat(parts, "+"))
		end)
		capture.ended = uis.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Keyboard and onlyModifier == input.KeyCode.Name then
				finish(onlyModifier)
			end
		end)
		self.Capturing = capture
		return function()
			finish(nil)
		end
	end

	function Binds:CancelCapture()
		local capture = self.Capturing
		if capture then
			capture.finish(nil)
			if self.Capturing == capture then
				self.Capturing = nil
			end
		end
	end

	function Binds:Destroy()
		self:CancelCapture()
		for _, entry in ipairs(table.clone(self.Entries)) do
			self:Remove(entry)
		end
		for _, connection in ipairs(self._connections) do
			connection:Disconnect()
		end
		self.Fired:DisconnectAll()
		self.Changed:DisconnectAll()
		self.PausedChanged:DisconnectAll()
	end

	return Binds
end

__modules["system/Config"] = function()
	-- Config: profiles, autosave, autoload and Robly's own interface settings.
	--
	--   workspace/Robly/<Folder>/robly.json            interface: theme, language,
	--                                                   animations, window/pill/detached
	--                                                   positions, active & autoload profile
	--   workspace/Robly/<Folder>/profiles/<name>.json  values of every "profile" flag
	--
	-- Without a file system (weak executors) everything keeps working in memory
	-- and the player gets one notice.

	local Compat = import("util/Compat")
	local Util = import("util/Util")
	local Signal = import("util/Signal")
	local Services = import("core/Services")
	local Theme = import("core/Theme")
	local Motion = import("core/Motion")
	local Localization = import("core/Localization")

	local L = Localization.L

	local Config = {}
	Config.__index = Config

	local function encode(data)
		local ok, text = pcall(function()
			return Services.HttpService:JSONEncode(data)
		end)
		return ok and text or nil
	end

	local function decode(text)
		if type(text) ~= "string" or text == "" then
			return nil
		end
		local ok, data = pcall(function()
			return Services.HttpService:JSONDecode(text)
		end)
		return ok and type(data) == "table" and data or nil
	end

	function Config.new(window)
		local self = setmetatable({}, Config)
		local opts = window.Options
		self.Window = window
		self.Store = window.Store
		self.Changed = Signal.new()
		self.FileSystem = Compat.hasFileSystem and opts.SaveConfig ~= false
		local folderName = opts.Folder or (type(window.TitleSpec) == "string" and window.TitleSpec) or "Script"
		self.Folder = "Robly/" .. Util.sanitizeFileName(folderName)
		self.Memory = {}
		self._pending = {}

		if self.FileSystem then
			Compat.ensureFolder(self.Folder .. "/profiles")
			self.Meta = decode(Compat.read(self.Folder .. "/robly.json")) or {}
		else
			self.Meta = {}
		end
		self.FirstRun = next(self.Meta) == nil
		if self.Meta.autosave == nil then
			self.Meta.autosave = opts.AutoSave ~= false
		end
		self.Current = self.Meta.profile or window.Loc:Lib("default_profile")

		-- Interface flags first, then the autoload profile (before any control
		-- exists: controls pick the values up when they register).
		self.Store:Load(self.Meta.ui or {}, "config", "ui")
		local autoload = self.Meta.autoload or self.Current
		local profile = self:_read(autoload)
		if profile and opts.AutoLoad ~= false then
			self.Store:Load(profile.values or {}, "config", "profile")
			self.Current = autoload
		end

		self._storeConnection = self.Store.Changed:Connect(function(flag)
			local meta = self.Store.Meta[flag]
			if not meta then
				return
			end
			if meta.persist == "profile" and self.Meta.autosave then
				self:_schedule("profile")
			elseif meta.persist == "ui" then
				self:_schedule("meta")
			end
		end)
		self._themeConnection = Theme.Changed:Connect(function(what)
			if what == "colors" then
				self:_schedule("meta")
			end
		end)
		self._motionConnection = Motion.Changed:Connect(function()
			self:_schedule("meta")
		end)
		self._densityConnection = Theme.Changed:Connect(function(what)
			if what == "density" then
				self:_schedule("meta")
			end
		end)
		window.Maid:Add(function()
			self._storeConnection:Disconnect()
			self._themeConnection:Disconnect()
			self._motionConnection:Disconnect()
			self._densityConnection:Disconnect()
			self.Changed:DisconnectAll()
		end)
		return self
	end

	-- Interface ----------------------------------------------------------------------------

	function Config:ApplyInterface()
		local window = self.Window
		local opts = window.Options
		local meta = self.Meta
		if meta.theme then
			Theme.deserialize(meta.theme)
		elseif opts.Theme then
			Theme.apply(opts.Theme)
		end
		Motion.setMode(meta.animations or opts.Animations or "Full")
		Theme.setDensity(meta.density or opts.Density or "compact")

		local loc = window.Loc
		if meta.language and table.find(loc.Available, meta.language) then
			loc:SetLanguage(meta.language)
		elseif loc:IsMultilingual() then
			local detected = loc:DetectRoblox(false)
			if detected and detected ~= loc.Current then
				loc:SetLanguage(detected)
				self._detectedLanguage = detected
			elseif detected then
				self._detectedLanguage = detected
			end
		end
	end

	function Config:SaveInterface()
		self:_schedule("meta")
	end

	function Config:GetMeta(key)
		return self.Meta[key]
	end

	function Config:SetMeta(key, value)
		self.Meta[key] = value
		self:_schedule("meta")
	end

	function Config:GetDetached(id)
		local all = self.Meta.detached
		return type(all) == "table" and all[id] or nil
	end

	-- data = nil marks the window as closed but keeps its rect; partial merges.
	function Config:SetDetached(id, data, partial)
		local all = self.Meta.detached
		if type(all) ~= "table" then
			all = {}
			self.Meta.detached = all
		end
		if data == nil then
			if all[id] then
				all[id].open = false
			end
		elseif partial and type(all[id]) == "table" then
			for key, value in pairs(data) do
				all[id][key] = value
			end
		else
			all[id] = data
		end
		self:_schedule("meta")
	end

	-- Saving ---------------------------------------------------------------------------------

	function Config:_schedule(kind)
		if self._pending[kind] then
			return
		end
		self._pending[kind] = true
		task.delay(kind == "profile" and 1 or 0.5, function()
			if not self._pending[kind] then
				return
			end
			self._pending[kind] = nil
			if kind == "profile" then
				self:_write(self.Current)
			else
				self:_writeMeta()
			end
		end)
	end

	function Config:Flush()
		if self._pending.profile then
			self._pending.profile = nil
			self:_write(self.Current)
		end
		self._pending.meta = nil
		self:_writeMeta()
	end

	function Config:_writeMeta()
		local window = self.Window
		local meta = self.Meta
		meta.theme = Theme.serialize()
		meta.animations = Motion.Mode
		meta.density = Theme.Density
		meta.language = window.Loc.Current
		meta.profile = self.Current
		meta.ui = self.Store:Snapshot("ui")
		if self.FileSystem then
			local text = encode(meta)
			if text then
				Compat.write(self.Folder .. "/robly.json", text)
			end
		end
	end

	function Config:_path(name)
		return self.Folder .. "/profiles/" .. Util.sanitizeFileName(name) .. ".json"
	end

	function Config:_read(name)
		if not name then
			return nil
		end
		if self.FileSystem then
			return decode(Compat.read(self:_path(name)))
		end
		return self.Memory[name]
	end

	function Config:_write(name)
		local data = {
			name = name,
			saved = os.time(),
			values = self.Store:Snapshot("profile"),
		}
		if self.FileSystem then
			local text = encode(data)
			if text then
				Compat.write(self:_path(name), text)
			end
		else
			self.Memory[name] = data
		end
		self.Changed:Fire("saved", name)
		return data
	end

	-- Profiles API ----------------------------------------------------------------------------

	function Config:List()
		local names, seen = {}, {}
		local function add(name)
			if name and not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
		if self.FileSystem then
			for _, file in ipairs(Compat.list(self.Folder .. "/profiles")) do
				local name = file:match("^(.+)%.json$")
				if name then
					local data = self:_read(name)
					add(data and data.name or name)
				end
			end
		else
			for name in pairs(self.Memory) do
				add(name)
			end
		end
		add(self.Current)
		table.sort(names, function(a, b)
			if a == self.Current then
				return true
			elseif b == self.Current then
				return false
			end
			return Util.lower(a) < Util.lower(b)
		end)
		return names
	end

	function Config:Info(name)
		local data = self:_read(name)
		return {
			Name = name,
			Saved = data and data.saved or nil,
			Count = data and data.values and (function()
				local n = 0
				for _ in pairs(data.values) do
					n += 1
				end
				return n
			end)() or 0,
			Autoload = (self.Meta.autoload or self.Meta.profile) == name,
			Active = self.Current == name,
		}
	end

	function Config:Save(name)
		name = name and Util.trim(name) or self.Current
		if name == "" then
			return false
		end
		self.Current = name
		self._pending.profile = nil
		local data = self:_write(name)
		self:_writeMeta()
		self.Changed:Fire("list")
		return true, data
	end

	function Config:Load(name)
		local data = self:_read(name)
		if not data then
			return false, 0
		end
		self._pending.profile = nil
		self.Current = name
		local count = self.Store:Load(data.values or {}, "config", "profile")
		self._pending.profile = nil
		self:_writeMeta()
		self.Changed:Fire("list")
		return true, count
	end

	function Config:Delete(name)
		if self.FileSystem then
			Compat.delete(self:_path(name))
		else
			self.Memory[name] = nil
		end
		if self.Meta.autoload == name then
			self.Meta.autoload = nil
		end
		if self.Current == name then
			local rest = self:List()
			for _, other in ipairs(rest) do
				if other ~= name then
					self.Current = other
					break
				end
			end
			if self.Current == name then
				self.Current = self.Window.Loc:Lib("default_profile")
			end
		end
		self:_writeMeta()
		self.Changed:Fire("list")
	end

	function Config:SetAutoload(name)
		self.Meta.autoload = name
		self:_writeMeta()
		self.Changed:Fire("list")
	end

	function Config:SetAutosave(enabled)
		self.Meta.autosave = enabled
		self:_writeMeta()
	end

	-- First-run notices ----------------------------------------------------------------------

	function Config:Notices()
		local window = self.Window
		if not Compat.hasFileSystem and window.Options.SaveConfig ~= false and window.Options.FileSystemNotice ~= false then
			window:Notify({ Title = L("no_fs"), Content = L("no_fs_desc"), Type = "warning", Duration = 6 })
		end
		if self._detectedLanguage and self.FirstRun then
			local loc = window.Loc
			window:Notify({
				Title = L("lang_detected"),
				Vars = { lang = loc:NameOf(loc.Current) },
				Content = L("lang_detected_desc"),
				Type = "info",
				Icon = "globe",
				Duration = 6,
				Action = {
					Text = L("change"),
					Callback = function()
						window:OpenLanguageMenu(window.Header)
					end,
				},
			})
		end
	end

	return Config
end

__modules["system/KeybindHud"] = function()
	-- Keybind panel (PC): a small window at the screen edge — key → function →
	-- state. Works while the main window is minimised. Pauses (dims) while the
	-- player types. Modes: all / only enabled; can fold into a tab at the edge.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Device = import("core/Device")
	local Localization = import("core/Localization")
	local Maid = import("util/Maid")
	local Binds = import("system/Binds")

	local New = Create.New
	local C, S = Theme.c, Theme.s
	local L = Localization.L

	local Hud = {}
	Hud.__index = Hud

	function Hud.new(window)
		local self = setmetatable({}, Hud)
		self.Window = window
		self.Maid = Maid.new()
		self.Hidden = false
		self.Collapsed = window.Config:GetMeta("hudCollapsed") == true
		self.Rows = {}

		self.Frame = self.Maid:Add(New("Frame", {
			Name = "KeybindPanel",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromOffset(230, 0),
			BackgroundColor3 = C("overlay"),
			Visible = false,
			Parent = window.Root.Windows,
		}, {
			Create.corner(14),
			Create.stroke("borderStrong"),
			Create.pad(8),
			Create.list("Vertical", 2),
		}))
		self.Tab = self.Maid:Add(New("TextButton", {
			Name = "KeybindTab",
			Size = UDim2.fromOffset(34, 52),
			BackgroundColor3 = C("overlay"),
			Visible = false,
			Parent = window.Root.Windows,
		}, {
			Create.corner(12),
			Create.stroke("borderStrong"),
			Create.list("Vertical", 2, { align = "Center", valign = "Center" }),
		}))
		Icons.new("keyboard", 16, C("textMuted")).Frame.Parent = self.Tab
		self.TabCount = New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16),
			TextColor3 = C("accent"),
			TextSize = 12,
			Weight = "Bold",
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 2,
			Parent = self.Tab,
		})
		self.TabCount.TextXAlignment = Enum.TextXAlignment.Center
		self.Maid:Add(self.Tab.Activated:Connect(function()
			self:SetCollapsed(false)
		end))

		local store = window.Store
		local function flag(name, default)
			local value = store:Get(name)
			if value == nil then
				return default
			end
			return value
		end
		self.flag = flag

		self.Maid:Add(window.Binds.Changed:Connect(function()
			self:Refresh()
		end))
		self.Maid:Add(window.Binds.Fired:Connect(function(entry, state)
			self:_fired(entry, state)
		end))
		self.Maid:Add(window.Binds.PausedChanged:Connect(function()
			self:_paused()
		end))
		self.Maid:Add(store.Changed:Connect(function(name)
			if type(name) == "string" and name:find("^robly:hud") then
				self:Refresh()
			end
		end))
		self.Maid:Add(window.Loc.Changed:Connect(function()
			self:Refresh()
		end))
		self.Maid:Add(window.VisibilityChanged:Connect(function()
			self:_applyVisibility()
		end))
		self.Maid:Add(Theme.Changed:Connect(function(what)
			if what == "sizes" then
				self:Refresh()
			end
		end))

		-- cooldown ticker
		self.Maid:Add(task.spawn(function()
			while true do
				task.wait(0.25)
				for entry, row in pairs(self.Rows) do
					if entry.Cooldown and row.cooldown then
						local left = window.Binds:CooldownLeft(entry)
						row.cooldown.Visible = left > 0
						row.bolt.Frame.Visible = left <= 0
						if left > 0 then
							row.cooldown.Text = window.Loc:Lib("seconds", { n = math.ceil(left) })
						end
					end
				end
			end
		end))

		task.defer(function()
			self:Refresh()
		end)
		return self
	end

	function Hud:ToggleHidden()
		self.Hidden = not self.Hidden
		self:_applyVisibility()
	end

	function Hud:SetCollapsed(collapsed)
		self.Collapsed = collapsed
		self.Window.Config:SetMeta("hudCollapsed", collapsed)
		self:_applyVisibility()
	end

	function Hud:_entries()
		local binds = self.Window.Binds
		local mode = self.flag("robly:hud.mode", "all")
		local user, system = {}, {}
		for _, entry in ipairs(binds.Entries) do
			local key = binds:KeyOf(entry)
			if entry.ShowInHud and key ~= "" then
				if entry.System then
					if mode == "all" then
						table.insert(system, entry)
					end
				elseif mode == "all" or (entry.Target and binds:IsOn(entry)) then
					table.insert(user, entry)
				end
			end
		end
		return user, system
	end

	function Hud:_applyVisibility()
		local window = self.Window
		local show = Theme.Mode == "pc" and self.flag("robly:hud.show", true) and not self.Hidden and not window.Destroyed
		if show and window.Minimized and self.flag("robly:hud.hideWithWindow", false) then
			show = false
		end
		local user, system = self:_entries()
		local mode = self.flag("robly:hud.mode", "all")
		if #user == 0 and (mode == "enabled" or #system == 0) then
			show = false
		end
		local edge = self.flag("robly:hud.edge", "right")
		local vp = Device.viewport()
		local top = math.floor(math.max(Device.inset() + 120, vp.Y * 0.36))
		if edge == "left" then
			self.Frame.AnchorPoint = Vector2.new(0, 0)
			self.Frame.Position = UDim2.fromOffset(12, top)
			self.Tab.AnchorPoint = Vector2.new(0, 0)
			self.Tab.Position = UDim2.fromOffset(0, top)
		else
			self.Frame.AnchorPoint = Vector2.new(1, 0)
			self.Frame.Position = UDim2.new(1, -12, 0, top)
			self.Tab.AnchorPoint = Vector2.new(1, 0)
			self.Tab.Position = UDim2.new(1, 0, 0, top)
		end
		self.Frame.Visible = show and not self.Collapsed
		self.Tab.Visible = show and self.Collapsed
		local on = 0
		for _, entry in ipairs(window.Binds.Entries) do
			if entry.Target and window.Binds:IsOn(entry) then
				on += 1
			end
		end
		self.TabCount.Text = tostring(on)
		self.Frame.BackgroundTransparency = math.clamp((self.flag("robly:hud.alpha", 8) or 8) / 100, 0, 0.9)
		self:_paused()
	end

	function Hud:_row(entry, order)
		local window = self.Window
		local binds = window.Binds
		local maid = self._rowsMaid
		local row = maid:Add(New("Frame", {
			Name = "Row",
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = C("accent"),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = self.Frame,
		}, { Create.corner(8), Create.pad(0, 6), Create.list("Horizontal", 8, { valign = "Center" }) }))
		local chip = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundColor3 = C("sunken"),
			Text = Binds.display(binds:KeyOf(entry)) or "",
			Mono = true,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = row,
		}, { Create.corner(6), Create.pad(0, 6), Create.minSize(22, 0), Create.stroke("segment") })
		chip.TextXAlignment = Enum.TextXAlignment.Center
		local chipScale = New("UIScale", { Parent = chip })
		local title = New("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			TextSize = 12.5,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = entry.System and C("textMuted") or C("text"),
			LayoutOrder = 2,
			Parent = row,
		}, { Create.flex() })
		window.Loc:Bind(title, "Text", entry.Title or "")
		local value = window.Store:Get(entry.Flag)
		if type(value) == "table" and not value.Override and binds:GameConflict(value.Key) then
			local warning = Icons.new("warning", 13, C("warning"))
			warning.Frame.LayoutOrder = 3
			warning.Frame.Parent = row
		end
		local info = { row = row, chip = chip, chipScale = chipScale }
		if entry.Target then
			local on = binds:IsOn(entry)
			local dot = New("Frame", {
				Size = UDim2.fromOffset(9, 9),
				BackgroundColor3 = C("success"),
				BackgroundTransparency = on and 0 or 1,
				LayoutOrder = 4,
				Parent = row,
			}, { Create.corner("full") })
			local ring = Create.stroke("textSubtle", 1.5)
			ring.Transparency = on and 1 or 0
			ring.Parent = dot
			info.dot, info.ring = dot, ring
		else
			local bolt = Icons.new("bolt", 14, C("textMuted"))
			bolt.Frame.LayoutOrder = 4
			bolt.Frame.Parent = row
			info.bolt = bolt
			if entry.Cooldown then
				local cooldown = New("TextLabel", {
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromScale(0, 1),
					TextColor3 = C("textMuted"),
					TextSize = 11.5,
					Visible = false,
					LayoutOrder = 5,
					Parent = row,
				})
				info.cooldown = cooldown
			end
		end
		self.Rows[entry] = info
	end

	function Hud:Refresh()
		if self._rowsMaid then
			self._rowsMaid:Clean()
		end
		self._rowsMaid = Maid.new()
		self.Rows = {}
		local window = self.Window
		local mode = self.flag("robly:hud.mode", "all")
		local user, system = self:_entries()
		local maid = self._rowsMaid

		if mode == "all" then
			local header = maid:Add(New("Frame", {
				Name = "Header",
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = 0,
				Parent = self.Frame,
			}, { Create.pad(0, 4, 0, 6), Create.list("Horizontal", 6, { valign = "Center" }) }))
			local title = New("TextLabel", {
				Size = UDim2.fromScale(0, 1),
				TextColor3 = C("textSubtle"),
				TextSize = 11.5,
				Weight = "SemiBold",
				Parent = header,
			}, { Create.flex() })
			window.Loc:Bind(title, "Text", function()
				return string.upper(window.Loc:Lib("binds"))
			end)
			self.PauseLabel = New("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				TextColor3 = C("warning"),
				TextSize = 11,
				Visible = false,
				LayoutOrder = 2,
				Parent = header,
			})
			window.Loc:Bind(self.PauseLabel, "Text", L("paused"))
			local fold = New("TextButton", {
				Size = UDim2.fromOffset(22, 22),
				LayoutOrder = 3,
				Parent = header,
			}, { Create.corner(6) })
			local chevron = Icons.new(self.flag("robly:hud.edge", "right") == "left" and "chevronLeft" or "chevronRight", 14, C("textSubtle"), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
			})
			chevron.Frame.Parent = fold
			maid:Add(fold.Activated:Connect(function()
				self:SetCollapsed(true)
			end))
		else
			self.PauseLabel = nil
		end
		for index, entry in ipairs(user) do
			self:_row(entry, index)
		end
		if #system > 0 and #user > 0 then
			maid:Add(New("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = C("divider"),
				LayoutOrder = 500,
				Parent = self.Frame,
			}))
		end
		for index, entry in ipairs(system) do
			self:_row(entry, 600 + index)
		end
		self:_applyVisibility()
	end

	function Hud:_fired(entry, state)
		local row = self.Rows[entry]
		local window = self.Window
		if row then
			row.row.BackgroundTransparency = 0.8
			Motion.tween(row.row, { BackgroundTransparency = 1 }, "flash")
			row.chipScale.Scale = 0.94
			Motion.tween(row.chipScale, { Scale = 1 }, "spring")
			if row.dot then
				local on = state == true
				Motion.tween(row.dot, { BackgroundTransparency = on and 0 or 1 }, "fade")
				Motion.tween(row.ring, { Transparency = on and 1 or 0 }, "fade")
			end
		end
		if self.flag("robly:hud.mode", "all") == "enabled" then
			self:Refresh()
		else
			self:_applyVisibility()
		end
		if not entry.System and Theme.Mode == "pc" then
			local text = window.Loc:Get(entry.Title)
			local content = nil
			if entry.Target then
				content = window.Loc:Lib(state and "on" or "off")
			end
			window:Notify({
				Title = text,
				Content = content,
				Type = "bind",
				Icon = entry.Target and (state and "check" or "minus") or "bolt",
				Duration = 1.6,
			})
		end
	end

	function Hud:_paused()
		local paused = self.Window.Binds.Paused
		if self.PauseLabel then
			self.PauseLabel.Visible = paused
		end
		local base = math.clamp((self.flag("robly:hud.alpha", 8) or 8) / 100, 0, 0.9)
		self.Frame.BackgroundTransparency = paused and math.max(base, 0.35) or base
		for _, child in ipairs(self.Frame:GetDescendants()) do
			if child:IsA("TextLabel") and child ~= self.PauseLabel then
				child.TextTransparency = paused and 0.5 or 0
			end
		end
	end

	function Hud:Destroy()
		if self._rowsMaid then
			self._rowsMaid:Clean()
		end
		self.Maid:Clean()
	end

	return Hud
end

__modules["system/QuickButtons"] = function()
	-- Quick buttons (touch): a column of 44×44 buttons at the screen edge, under
	-- the Roblox top bar and above the jump button. Enabled toggles glow with the
	-- accent; actions show a bolt. After a tap a label shows for ~1 s:
	-- "Auto farm · ON". The player picks which functions appear in Settings.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Device = import("core/Device")
	local Maid = import("util/Maid")

	local New = Create.New
	local C = Theme.c

	local QuickButtons = {}
	QuickButtons.__index = QuickButtons

	local MAX = 5

	function QuickButtons.new(window)
		local self = setmetatable({}, QuickButtons)
		self.Window = window
		self.Maid = Maid.new()
		self.Holder = self.Maid:Add(New("Frame", {
			Name = "QuickButtons",
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Visible = false,
			Parent = window.Root.Windows,
		}, { Create.list("Vertical", 8, { align = "Right" }) }))
		self.Maid:Add(window.Store.Changed:Connect(function(flag)
			if type(flag) == "string" and flag:find("^robly:quick:") then
				self:_scheduleRefresh()
			else
				self:_updateStates()
			end
		end))
		self:_scheduleRefresh()
		return self
	end

	function QuickButtons:_scheduleRefresh()
		if self._pending then
			return
		end
		self._pending = true
		task.defer(function()
			self._pending = false
			if not self.Window.Destroyed then
				self:Refresh()
			end
		end)
	end

	function QuickButtons:_flagFor(control)
		return control.QuickFlag or ("robly:quick:" .. tostring(control.Flag))
	end

	function QuickButtons:Refresh()
		local window = self.Window
		if window.SettingsTab and not self._refreshingSettings then
			self._refreshingSettings = true
			window.SettingsTab:RefreshQuick()
			self._refreshingSettings = false
		end
		if self._buttonsMaid then
			self._buttonsMaid:Clean()
		end
		local maid = Maid.new()
		self._buttonsMaid = maid
		self.Buttons = {}
		self.Holder.Position = UDim2.new(1, -12, 0, Device.inset() + 8)
		local count = 0
		for _, control in ipairs(window.Quick) do
			if count >= MAX then
				break
			end
			if not control.Destroyed and window.Store:Get(self:_flagFor(control)) == true then
				count += 1
				self:_button(control, count, maid)
			end
		end
		self.Holder.Visible = Theme.Sizes.touch and count > 0
		self:_updateStates()
	end

	function QuickButtons:_button(control, order, maid)
		local window = self.Window
		local row = maid:Add(New("Frame", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 44),
			LayoutOrder = order,
			Parent = self.Holder,
		}, { Create.list("Horizontal", 8, { align = "Right", valign = "Center" }) }))
		local label = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 30),
			BackgroundColor3 = C("overlay"),
			TextSize = 13,
			Weight = "SemiBold",
			Visible = false,
			LayoutOrder = 1,
			Parent = row,
		}, { Create.corner(8), Create.pad(0, 10), Create.stroke("borderStrong") })
		local button = New("TextButton", {
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = C("overlay"),
			LayoutOrder = 2,
			Parent = row,
		}, { Create.corner(12) })
		local stroke = Create.stroke("borderStrong")
		stroke.Parent = button
		local iconName = control.Icon or (control:QuickState() == "action" and "bolt" or "dot")
		if iconName == "dot" then
			iconName = control.Tab.Icon or "bolt"
		end
		local icon = Icons.new(iconName, 20, C("text"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		icon.Frame.Parent = button
		Motion.pressable(button, nil, 0.9, maid)
		local token = 0
		maid:Add(button.Activated:Connect(function()
			token += 1
			local mine = token
			local text = window.Loc:Get(control.TitleSpec)
			local state = nil
			if not control.Enabled then
				-- locked by EnabledWhen: say so instead of acting
				text ..= " · " .. window.Loc:Lib("locked")
			else
				state = control:QuickActivate()
			end
			if state == true or state == false then
				text ..= " · " .. window.Loc:Lib(state and "on" or "off")
			end
			label.Text = text
			label.Visible = true
			label.TextTransparency = 0
			label.BackgroundTransparency = 0
			task.delay(1, function()
				if token == mine then
					Motion.tween(label, { TextTransparency = 1, BackgroundTransparency = 1 }, "fade")
					task.delay(0.15, function()
						if token == mine then
							label.Visible = false
						end
					end)
				end
			end)
		end))
		table.insert(self.Buttons, { control = control, button = button, icon = icon, stroke = stroke })
	end

	function QuickButtons:_updateStates()
		for _, entry in ipairs(self.Buttons or {}) do
			local state = entry.control:QuickState()
			local on = state == true
			Theme.set(entry.button, "BackgroundColor3", on and C("accent") or C("overlay"))
			entry.icon:SetColor(on and C("accentInk") or C("text"), true)
			entry.stroke.Transparency = on and 1 or 0
		end
	end

	function QuickButtons:Destroy()
		if self._buttonsMaid then
			self._buttonsMaid:Clean()
		end
		self.Maid:Clean()
	end

	return QuickButtons
end

__modules["system/SettingsTab"] = function()
	-- Built-in "Settings" tab, made with Robly's own controls:
	-- theme (presets + live editor + export/import), configs (profiles,
	-- autosave, autoload), interface (show/hide key, language, animations,
	-- keybind panel on PC, quick buttons on touch), about.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Localization = import("core/Localization")
	local Compat = import("util/Compat")
	local Util = import("util/Util")
	local Control = import("controls/Base")

	local New = Create.New
	local C, S = Theme.c, Theme.s
	local L = Localization.L

	local SettingsTab = {}
	SettingsTab.__index = SettingsTab

	local function pcOnly(_, mode)
		return mode == "pc"
	end

	local function touchOnly(_, mode)
		return mode ~= "pc"
	end

	-- Main editor rows: the base colours plus the most visible derived ones.
	-- Changing Background/Text/Accent re-derives every colour that wasn't set by hand.
	local LABELS = {
		accent = L("accent"),
		accent2 = L("accent2"),
		bg = L("background"),
		nav = L("sidebar"),
		surface = L("cards"),
		border = L("outline"),
		text = L("text"),
	}

	function SettingsTab.new(window)
		local self = setmetatable({}, SettingsTab)
		self.Window = window
		local tab = window:_internalTab({ Title = L("settings"), Icon = "sliders", Id = "robly_settings" })
		self.Tab = tab
		self:_buildTheme()
		self:_buildConfigs()
		self:_buildInterface()
		if window.Branding then
			self:_buildAbout()
		end
		return self
	end

	-- Theme ---------------------------------------------------------------------------------

	local ThemeGrid = Control.extend("ThemeGrid")

	local function miniPreview(colors)
		local card = New("Frame", {
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = colors.bg,
		}, { Create.corner(10), Create.list("Horizontal", 0) })
		New("Frame", {
			Size = UDim2.new(0, 22, 1, 0),
			BackgroundColor3 = colors.nav,
			Parent = card,
		}, { Create.corner(10), Create.pad(8, 5), Create.list("Vertical", 4),
			New("Frame", { Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = colors.raised }, { Create.corner(2) }),
			New("Frame", { Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = colors.surface, LayoutOrder = 2 }, { Create.corner(2) }),
		})
		local body = New("Frame", { Size = UDim2.fromScale(0, 1), LayoutOrder = 2, Parent = card }, {
			Create.flex(), Create.pad(8), Create.list("Vertical", 6),
		})
		New("Frame", { Size = UDim2.new(0.6, 0, 0, 5), BackgroundColor3 = colors.text, Parent = body }, { Create.corner(2) })
		local row = New("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = colors.surface,
			LayoutOrder = 2,
			Parent = body,
		}, { Create.corner(5), Create.pad(0, 5), Create.list("Horizontal", 4, { valign = "Center" }) })
		New("Frame", { Size = UDim2.new(0, 0, 0, 4), BackgroundColor3 = colors.textSubtle, Parent = row }, { Create.corner(2), Create.flex() })
		New("Frame", { Size = UDim2.fromOffset(16, 10), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 2, Parent = row }, {
			Create.corner("full"),
			New("UIGradient", { Color = ColorSequence.new(colors.accent, colors.accent2 or colors.accent) }),
		})
		New("Frame", { Size = UDim2.new(0.85, 0, 0, 3), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 3, Parent = body }, {
			Create.corner(2),
			New("UIGradient", { Color = ColorSequence.new(colors.accent, colors.accent2 or colors.accent) }),
		})
		return card
	end

	function SettingsTab:_buildTheme()
		local window = self.Window
		local section = self.Tab:Section({ Title = L("theme") })
		local grid = Control.new(section, { Title = L("theme") }, { class = ThemeGrid, kind = "ThemeGrid", layout = "custom", searchable = false })
		grid.Inner:FindFirstChildOfClass("UISizeConstraint"):Destroy()
		-- every preset as a card in a responsive grid
		local holder = New("Frame", {
			Name = "Themes",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = grid.Inner,
		})
		local layout = New("UIGridLayout", {
			CellPadding = UDim2.fromOffset(8, 8),
			CellSize = UDim2.fromOffset(110, 92),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = holder,
		})
		local function fit()
			local width = holder.AbsoluteSize.X
			if width <= 0 then
				return
			end
			local columns = math.max(2, math.floor((width + 8) / (104 + 8)))
			layout.CellSize = UDim2.new(1 / columns, -8 + 8 / columns, 0, 92)
		end
		grid.Maid:Add(holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
		fit()
		local cards = {}
		for index, name in ipairs(Theme.PresetOrder) do
			local colors = Theme.Presets[name]
			local button = New("TextButton", {
				Name = name,
				LayoutOrder = index,
				Parent = holder,
			}, { Create.list("Vertical", 5) })
			local preview = miniPreview(colors)
			preview.Parent = button
			local stroke = Create.stroke("accent", 2)
			stroke.Parent = preview
			local label = New("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				Text = name,
				TextSize = 12,
				Weight = "SemiBold",
				LayoutOrder = 2,
				Parent = button,
			})
			label.TextTruncate = Enum.TextTruncate.AtEnd
			Motion.pressable(button, preview, 0.96, grid.Maid)
			grid.Maid:Add(button.Activated:Connect(function()
				window:SetTheme(name)
			end))
			cards[name] = { stroke = stroke, label = label }
		end
		local function refresh()
			for name, card in pairs(cards) do
				local on = Theme.Name == name
				card.stroke.Transparency = on and 0 or 1
				Theme.set(card.label, "TextColor3", on and C("accent") or C("text"))
			end
		end
		refresh()
		grid.Maid:Add(Theme.Changed:Connect(refresh))
		local function relabel()
			for name, card in pairs(cards) do
				card.label.Text = window.Loc:Get(Theme.PresetTitles and Theme.PresetTitles[name] or name)
			end
		end
		relabel()
		grid.Maid:Add(window.Loc.Changed:Connect(relabel))

		-- background effect + glass
		local effectOptions = {}
		for _, effect in ipairs(Theme.Effects) do
			table.insert(effectOptions, { Value = effect, Text = L("effect_" .. string.lower(effect)) })
		end
		local effect = section:Dropdown({
			Title = L("effect"),
			Description = L("effect_desc"),
			Icon = "sparkles",
			Flag = "robly:effect",
			Options = effectOptions,
			Default = Theme.Effect,
			Save = false,
			Callback = function(value)
				if value and value ~= Theme.Effect then
					window:SetEffect(value)
				end
			end,
		})
		local glass = section:Toggle({
			Title = L("glass"),
			Description = L("glass_desc"),
			Flag = "robly:glass",
			Default = Theme.Glass,
			Save = false,
			Highlight = false,
			EnabledWhen = function(get)
				return get("robly:effect") ~= "None"
			end,
			Callback = function(value)
				if value ~= Theme.Glass then
					window:SetGlass(value)
				end
			end,
		})
		grid.Maid:Add(Theme.Changed:Connect(function(what)
			if what == "effect" or what == "colors" then
				window.Store:Set(effect.Flag, Theme.Effect, "silent")
				window.Store:Set(glass.Flag, Theme.Glass, "silent")
			end
		end))

		-- Live editor
		local pickers = {}
		local syncing = false
		local function addPicker(target, key, text)
			local picker = target:ColorPicker({
				Title = text,
				Flag = "robly:color." .. key,
				Default = Theme.Colors[key],
				Save = false,
			})
			picker.Maid:Add(picker.Changed:Connect(function(color, _, source)
				if not syncing and source ~= "silent" and typeof(color) == "Color3" then
					Theme.setToken(key, color)
				end
			end))
			pickers[key] = picker
		end
		for _, key in ipairs(Theme.MainKeys) do
			addPicker(section, key, LABELS[key])
		end
		section:Buttons({
			{ Title = L("export"), Icon = "upload", Callback = function()
				local text = Theme.export()
				if Compat.clipboard(text) then
					window:Notify({ Title = L("theme_copied"), Content = L("theme_copied_desc"), Type = "success", Duration = 3 })
				else
					window:Dialog({ Title = L("copy_failed"), Input = { Default = text, Mono = true }, Buttons = { { Text = L("ok"), Variant = "Primary" } } })
				end
			end },
			{ Title = L("import"), Icon = "download", Callback = function()
				window:Dialog({
					Title = L("import_theme"),
					Input = { Placeholder = L("paste_theme"), Mono = true },
					Buttons = {
						{ Text = L("cancel"), Variant = "Secondary" },
						{ Text = L("import"), Variant = "Primary", Callback = function(text)
							local colors = Theme.import(text)
							if not colors then
								window:Notify({ Title = L("theme_invalid"), Type = "error", Duration = 3 })
								return false
							end
							window:SetTheme(colors)
							window:Notify({ Title = L("theme_imported"), Type = "success", Duration = 2 })
							return true
						end },
					},
				})
			end },
		})

		local more = self.Tab:Section({ Title = L("more_colors"), Collapsed = true })
		for _, key in ipairs(Theme.TokenOrder) do
			if not table.find(Theme.MainKeys, key) then
				addPicker(more, key, key)
			end
		end
		more:Button({ Title = L("reset_overrides"), Variant = "Secondary", Icon = "refresh", Callback = function()
			-- forget hand-picked derived colours: everything follows the base again
			for _, key in ipairs(Theme.TokenOrder) do
				if Theme.isOverridden(key) then
					Theme.Spec[key] = nil
				end
			end
			Theme.setToken("accent", Theme.Spec.accent or Theme.Colors.accent)
			window.Config:SaveInterface()
		end })

		self.Maid = grid.Maid
		grid.Maid:Add(Theme.Changed:Connect(function(what)
			if what ~= "colors" then
				return
			end
			syncing = true
			for key, picker in pairs(pickers) do
				if Theme.Colors[key] then
					window.Store:Set(picker.Flag, Theme.Colors[key], "silent")
				end
			end
			syncing = false
		end))
	end

	-- Configs --------------------------------------------------------------------------------

	local function relativeTime(loc, saved)
		if not saved then
			return nil
		end
		local diff = os.time() - saved
		if diff < 60 then
			return loc:Lib("just_now")
		elseif diff < 3600 then
			return loc:Lib("minutes_ago", { n = math.floor(diff / 60) })
		elseif diff < 86400 then
			return loc:Lib("hours_ago", { n = math.floor(diff / 3600) })
		elseif diff < 172800 then
			return loc:Lib("yesterday")
		end
		return loc:Lib("days_ago", { n = math.floor(diff / 86400) })
	end

	local ProfileRow = Control.extend("Profile")

	function SettingsTab:_buildConfigs()
		local window = self.Window
		local config = window.Config
		local loc = window.Loc
		local section = self.Tab:Section({ Title = L("configs") })
		self.ConfigSection = section
		local list = {}

		local function rebuild()
			for _, row in ipairs(list) do
				row:Destroy()
			end
			table.clear(list)
			for _, name in ipairs(config:List()) do
				local info = config:Info(name)
				local desc = function()
					local parts = {}
					if info.Active then
						table.insert(parts, loc:Lib("active"))
					end
					if info.Autoload then
						table.insert(parts, loc:Lib("autoload"))
					end
					local time = relativeTime(loc, info.Saved)
					if time then
						table.insert(parts, time)
					end
					return table.concat(parts, " · ")
				end
				local row = Control.new(section, { Title = function()
					return name
				end, Description = desc }, { class = ProfileRow, kind = "Profile", rowClick = true, searchable = false })
				row.Holder.LayoutOrder = -100 + #list
				if info.Active then
					local check = Icons.new("check", 18, C("accent"))
					check.Frame.LayoutOrder = 1
					check.Frame.Parent = row.Right
				end
				local more = New("TextButton", {
					Size = Theme.f(function(_, s)
						return UDim2.fromOffset(s.touch and 44 or 32, s.touch and 44 or 32)
					end),
					BackgroundColor3 = C("raised"),
					LayoutOrder = 2,
					Parent = row.Right,
				}, { Create.corner(9) })
				Icons.new("more", 16, C("textMuted"), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }).Frame.Parent = more
				Motion.pressable(more, nil, 0.9, row.Maid)
				local function load()
					local ok, count = config:Load(name)
					if ok then
						window:Notify({ Title = L("config_loaded"), Content = L("profile_values"), ContentVars = { name = name, n = count }, Type = "success", Duration = 3 })
					end
				end
				row.Maid:Add(row.Hit.Activated:Connect(load))
				row.Maid:Add(more.Activated:Connect(function()
					window.Popup:Menu(more, {
						{ Text = L("load"), Icon = "download", Callback = load },
						{ Text = L("overwrite"), Icon = "save", Callback = function()
							config:Save(name)
							window:Notify({ Title = L("config_saved"), Content = L("profile_saved"), ContentVars = { name = name }, Type = "success", Duration = 2 })
						end },
						{ Text = L("set_autoload"), Icon = "star", Checked = info.Autoload, Callback = function()
							config:SetAutoload(name)
						end },
						"divider",
						{ Text = L("delete"), Icon = "trash", Danger = true, Callback = function()
							window:Dialog({
								Title = L("delete_profile_q"),
								Vars = { name = name },
								Content = L("delete_profile_desc"),
								Buttons = {
									{ Text = L("cancel"), Variant = "Secondary" },
									{ Text = L("delete"), Variant = "Danger", Callback = function()
										config:Delete(name)
									end },
								},
							})
						end },
					}, { width = 240 })
				end))
				table.insert(list, row)
			end
		end

		section:Button({ Title = L("new_profile"), Icon = "plus", Variant = "Secondary", Callback = function()
			window:Dialog({
				Title = L("new_profile"),
				Input = { Placeholder = L("profile_name") },
				Buttons = {
					{ Text = L("cancel"), Variant = "Secondary" },
					{ Text = L("create"), Variant = "Primary", Callback = function(text)
						local name = Util.trim(text or "")
						if name == "" then
							return false
						end
						config:Save(name)
						window:Notify({ Title = L("config_saved"), Content = L("profile_saved"), ContentVars = { name = name }, Type = "success", Duration = 2 })
						return true
					end },
				},
			})
		end })
		local autosave = section:Toggle({
			Title = L("autosave"),
			Description = L("autosave_desc"),
			Flag = "robly:autosave",
			Default = config.Meta.autosave ~= false,
			Save = false,
			Callback = function(value)
				config:SetAutosave(value)
			end,
		})
		local _ = autosave
		rebuild()
		window.Maid:Add(config.Changed:Connect(function(kind)
			if kind == "list" then
				rebuild()
			end
		end))
		window.Maid:Add(loc.Changed:Connect(rebuild))
	end

	-- Interface ------------------------------------------------------------------------------

	function SettingsTab:_buildInterface()
		local window = self.Window
		local loc = window.Loc
		local section = self.Tab:Section({ Title = L("interface") })

		section:Keybind({
			Title = L("toggle_key"),
			HudTitle = L("show_window"),
			Flag = "robly:toggleKey",
			Default = window.Options.ToggleKey or "RightShift",
			System = true,
			Mode = "Action",
			VisibleWhen = pcOnly,
			Callback = function()
				window:Toggle()
			end,
		})
		if loc:IsMultilingual() then
			local options = {}
			for _, language in ipairs(loc:Languages()) do
				table.insert(options, { Value = language.Code, Text = language.Name })
			end
			local dropdown = section:Dropdown({
				Title = L("language"),
				Icon = "globe",
				Flag = "robly:language",
				Options = options,
				Default = loc.Current,
				Save = false,
				Callback = function(code)
					if code and code ~= loc.Current then
						window:SetLanguage(code)
					end
				end,
			})
			window.Maid:Add(loc.Changed:Connect(function(code)
				window.Store:Set(dropdown.Flag, code, "silent")
			end))
		end
		local animations = section:Segmented({
			Title = L("animations"),
			Flag = "robly:animations",
			Options = {
				{ Value = "Full", Text = L("anim_full") },
				{ Value = "Soft", Text = L("anim_soft") },
				{ Value = "Off", Text = L("anim_off") },
			},
			Default = Motion.Mode,
			Save = false,
			Callback = function(mode)
				window:SetAnimations(mode)
			end,
		})
		window.Maid:Add(Motion.Changed:Connect(function(mode)
			window.Store:Set(animations.Flag, mode, "silent")
		end))
		local density = section:Segmented({
			Title = L("density"),
			Flag = "robly:density",
			Options = {
				{ Value = "compact", Text = L("density_compact") },
				{ Value = "comfortable", Text = L("density_comfortable") },
			},
			Default = Theme.Density,
			Save = false,
			VisibleWhen = pcOnly,
			Callback = function(value)
				Theme.setDensity(value)
			end,
		})
		window.Maid:Add(Theme.Changed:Connect(function(what)
			if what == "density" then
				window.Store:Set(density.Flag, Theme.Density, "silent")
			end
		end))
		section:Toggle({
			Title = L("detached_hide"),
			Flag = "robly:hideDetached",
			Default = window.Config:GetMeta("hideDetached") == true,
			Save = false,
			Callback = function(value)
				window.Config:SetMeta("hideDetached", value)
			end,
		})

		-- Keybind panel (PC)
		local hud = self.Tab:Section({ Title = L("binds_panel") })
		self.HudSection = hud
		hud:Toggle({ Title = L("binds_panel"), Flag = "robly:hud.show", Default = true, Persist = "ui", VisibleWhen = pcOnly })
		hud:Segmented({
			Title = L("show"),
			Flag = "robly:hud.mode",
			Options = { { Value = "all", Text = L("all") }, { Value = "enabled", Text = L("enabled_only") } },
			Default = "all",
			Persist = "ui",
			VisibleWhen = pcOnly,
		})
		hud:Segmented({
			Title = L("screen_edge"),
			Flag = "robly:hud.edge",
			Options = { { Value = "left", Text = L("left") }, { Value = "right", Text = L("right") } },
			Default = "right",
			Persist = "ui",
			VisibleWhen = pcOnly,
		})
		hud:Slider({ Title = L("bg_opacity"), Flag = "robly:hud.alpha", Min = 0, Max = 60, Step = 2, Default = 8, Suffix = "%", Persist = "ui", VisibleWhen = pcOnly })
		hud:Keybind({
			Title = L("hud_hide_key"),
			Flag = "robly:hud.key",
			Default = "Ctrl+B",
			System = true,
			ShowInHud = false,
			VisibleWhen = pcOnly,
			Callback = function()
				if window.Hud then
					window.Hud:ToggleHidden()
				end
			end,
		})
		hud:Toggle({ Title = L("hide_with_window"), Flag = "robly:hud.hideWithWindow", Default = false, Persist = "ui", VisibleWhen = pcOnly })

		-- Quick buttons (touch)
		self.QuickSection = self.Tab:Section({ Title = L("quick_buttons") })
		self.QuickSection:Paragraph({ Content = L("quick_buttons_desc"), VisibleWhen = touchOnly })
		self._quickRows = {}
	end

	-- Rebuild the list of functions the player can pin as quick buttons.
	function SettingsTab:RefreshQuick()
		local window = self.Window
		local signature = {}
		for _, control in ipairs(window.Quick) do
			table.insert(signature, tostring(control.Flag or control.TitleSpec) .. (control.Destroyed and "x" or ""))
		end
		signature = table.concat(signature, "|")
		if signature == self._quickSignature then
			return
		end
		self._quickSignature = signature
		for _, row in ipairs(self._quickRows) do
			row:Destroy()
		end
		table.clear(self._quickRows)
		for index, control in ipairs(window.Quick) do
			if control.Flag and not control.Destroyed then
				local row = self.QuickSection:Checkbox({
					Title = control.TitleSpec,
					Flag = "robly:quick:" .. control.Flag,
					Default = index <= 4,
					Persist = "ui",
					VisibleWhen = touchOnly,
				})
				table.insert(self._quickRows, row)
			elseif not control.Flag and not control.Destroyed then
				local flag = "robly:quick:" .. (control.TitleSpec and window.Loc:Get(control.TitleSpec) or tostring(index))
				control.QuickFlag = flag
				local row = self.QuickSection:Checkbox({
					Title = control.TitleSpec,
					Flag = flag,
					Default = index <= 4,
					Persist = "ui",
					VisibleWhen = touchOnly,
				})
				table.insert(self._quickRows, row)
			end
		end
		self.QuickSection.Frame.Visible = #window.Quick > 0
	end

	-- About ----------------------------------------------------------------------------------

	function SettingsTab:_buildAbout()
		local window = self.Window
		local section = self.Tab:Section({ Title = L("about") })
		section:Paragraph({ Title = "Robly by RobScript", Content = {
			en = "UI library for Roblox scripts. Open source, free to use.",
			ru = "UI-библиотека для Roblox-скриптов. Открытый код, свободное использование.",
			es = "Biblioteca de interfaz para scripts de Roblox. Código abierto y libre.",
			pt = "Biblioteca de interface para scripts Roblox. Código aberto e livre.",
			de = "UI-Bibliothek für Roblox-Skripte. Open Source, frei nutzbar.",
			fr = "Bibliothèque d'interface pour scripts Roblox. Open source, libre d'usage.",
		} })
		section:Button({ Title = "robscript.com", Icon = "link", Variant = "Text", Callback = function()
			window:_copyLink()
		end })
	end

	return SettingsTab
end

__modules["ui/Body"] = function()
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
end

__modules["ui/Detached"] = function()
	-- DetachedWindow: a tab living in its own small window.
	--   PC   — drag a tab out of the sidebar, or press the "picture in picture"
	--          button. Drag the window by its title back onto the sidebar to
	--          return it (the slot lights up: "Release to return").
	--   Touch — long-press a tab → "Open in separate window" (max 2 on phones).
	-- The page is reparented, never rebuilt: values live in the Store, nothing
	-- resets. Grows out of / folds back into the nav item (Quint Out 280 ms).

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Icons = import("core/Icons")
	local Drag = import("core/Drag")
	local Device = import("core/Device")
	local Maid = import("util/Maid")
	local Util = import("util/Util")
	local Pill = import("ui/Pill")
	local Effects = import("ui/Effects")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Detached = {}
	Detached.__index = Detached

	local function rectOf(gui)
		if gui and gui.Parent and gui.AbsoluteSize.X > 0 then
			return Device.toOffset(gui.AbsolutePosition), gui.AbsoluteSize
		end
		return nil
	end

	function Detached.defaultSize()
		local vp = Device.viewport()
		local mode = Theme.Mode
		if mode == "phone" then
			return Vector2.new(math.clamp(math.floor(vp.X * 0.36), 260, 340), math.max(220, vp.Y - Device.inset() - 16))
		elseif mode == "tablet" then
			return Vector2.new(math.min(360, vp.X - 32), math.min(520, vp.Y - Device.inset() - 32))
		end
		return Vector2.new(360, math.min(460, vp.Y - Device.inset() - 32))
	end

	function Detached.new(tab, options)
		options = options or {}
		local window = tab.Window
		local loc = window.Loc
		local self = setmetatable({}, Detached)
		self.Tab = tab
		self.Window = window
		self.Maid = Maid.new()

		local frame = self.Maid:Add(New("Frame", {
			Name = "Detached_" .. tab.Id,
			BackgroundColor3 = C("bg"),
			ClipsDescendants = true,
			Active = true,
			ZIndex = window.Root:NextZ(),
			Parent = window.Root.Windows,
		}, {
			Create.corner("rWindow"),
			Create.stroke("borderStrong"),
		}))
		self.Frame = frame
		self.Scale = New("UIScale", { Parent = frame })
		self.Effects = self.Maid:Add(Effects.new(frame, 0))
		-- Everything laid out lives in Shell, so free-floating parts (resize grip)
		-- stay out of the list layout.
		local shell = New("Frame", {
			Name = "Shell",
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		}, { Create.list("Vertical", 0) })

		-- Header ---------------------------------------------------------------------
		local headerFrame = New("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = 1,
			Parent = shell,
		})
		-- transparent button under the header content: the drag handle
		local dragHandle = New("TextButton", {
			Name = "DragHandle",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = headerFrame,
		})
		local header = New("Frame", {
			Name = "Row",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = headerFrame,
		}, { Create.pad(0, 4, 0, 14), Create.list("Horizontal", 4, { valign = "Center" }) })
		local title = New("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			RichText = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Weight = "SemiBold",
			Parent = header,
		}, { Create.flex() })
		loc:Bind(title, "Text", function()
			return loc:Get(tab.TitleSpec) .. ' <font color="#' .. Util.toHex(Theme.Colors.textSubtle) .. '">· ' .. loc:Get(window.TitleSpec) .. "</font>"
		end)
		self.Maid:Add(Theme.Changed:Connect(function()
			loc:Bind(title, "Text", function()
				return loc:Get(tab.TitleSpec) .. ' <font color="#' .. Util.toHex(Theme.Colors.textSubtle) .. '">· ' .. loc:Get(window.TitleSpec) .. "</font>"
			end)
		end))

		local function headerButton(icon, order, tip, callback)
			local button = New("TextButton", {
				Size = Theme.sz(0, "hit", 0, "hit"),
				LayoutOrder = order,
				Parent = header,
			}, { Create.corner(9) })
			local glyph = Icons.new(icon, 16, C("textMuted"), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
			})
			glyph.Frame.Parent = button
			Motion.pressable(button, glyph.Frame, 0.85, self.Maid)
			window.Tooltip:Attach(button, tip, self.Maid)
			self.Maid:Add(button.Activated:Connect(callback))
			return button
		end
		headerButton("minus", 2, { __lib = "minimize" }, function()
			self:Minimize()
		end)
		headerButton("attach", 3, { __lib = "return_to_window" }, function()
			self:Attach()
		end)

		New("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = C("divider"),
			LayoutOrder = 2,
			Parent = shell,
		})
		local content = New("Frame", {
			Name = "Content",
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = 3,
			Parent = shell,
		}, { Create.flex(), Create.pad(Theme.f(function(_, s)
			return UDim.new(0, s.touch and 8 or 12)
		end), "contentX", "contentBottom", "contentX") })
		self.Content = content

		-- Move the page in
		tab.Page.Parent = content
		tab.Page.Visible = true
		tab.Page.Position = UDim2.new()
		tab.PageHeader.Visible = false
		Theme.unbind(tab.PageHeader, "Visible")

		-- Geometry -------------------------------------------------------------------
		local saved = window.Config:GetDetached(tab.Id)
		local size = saved and Vector2.new(saved.w, saved.h) or Detached.defaultSize()
		local position
		if options.at then
			position = Device.toOffset(options.at) - Vector2.new(size.X / 2, 20)
		elseif saved then
			position = Vector2.new(saved.x, saved.y)
		else
			local mainPos, mainSize = rectOf(window.Frame)
			if mainPos then
				-- cascade, so a second window never hides exactly behind the first
				local cascade = window:DetachedCount() * 28
				local right = mainPos.X + mainSize.X + 16
				if right + size.X < Device.viewport().X - 8 then
					position = Vector2.new(right, mainPos.Y + cascade)
				else
					position = Vector2.new(mainPos.X - size.X - 16 - cascade, mainPos.Y + cascade)
				end
			else
				position = Vector2.new(24, Device.inset() + 24)
			end
		end
		size = Vector2.new(math.min(size.X, Device.viewport().X - 16), math.min(size.Y, Device.viewport().Y - Device.inset() - 16))
		position = Drag.clamp(position, size)
		self.TargetPosition, self.TargetSize = position, size

		local fromPos, fromSize = options.fromPos, options.fromSize
		if fromPos and Motion.Mode == "Full" then
			frame.Position = UDim2.fromOffset(fromPos.X, fromPos.Y)
			frame.Size = UDim2.fromOffset(fromSize.X, fromSize.Y)
			Motion.tween(frame, {
				Position = UDim2.fromOffset(position.X, position.Y),
				Size = UDim2.fromOffset(size.X, size.Y),
			}, "window")
		else
			frame.Position = UDim2.fromOffset(position.X, position.Y)
			frame.Size = UDim2.fromOffset(size.X, size.Y)
			if Motion.Mode ~= "Off" then
				self.Scale.Scale = 0.96
				Motion.tween(self.Scale, { Scale = 1 }, "spring")
			end
		end

		-- Raise on press
		self.Maid:Add(frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				frame.ZIndex = window.Root:NextZ()
			end
		end))

		-- Drag by header; drop on the main sidebar returns the tab (PC)
		local overNav = false
		local startPosition
		Drag.attach(dragHandle, {
			onStart = function()
				frame.ZIndex = window.Root:NextZ()
				startPosition = Device.offsetOf(frame)
			end,
			onMove = function(pointer, _, total)
				-- keep at least the header on screen
				local p = Drag.clamp(startPosition + total, Vector2.new(frame.AbsoluteSize.X, 44), 0)
				frame.Position = UDim2.fromOffset(p.X, p.Y)
				local over = window:_pointerOverNav(pointer)
				if over ~= overNav then
					overNav = over
					window:_navHighlight(tab, over)
				end
			end,
			onEnd = function(_, moved)
				if not moved then
					return
				end
				if overNav then
					overNav = false
					window:_navHighlight(tab, false)
					self:Attach()
					return
				end
				self:_snap()
				self:_save()
			end,
		}, self.Maid)

		-- Resize (PC)
		local grip = New("TextButton", {
			Name = "Resize",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -2, 1, -2),
			Size = UDim2.fromOffset(16, 16),
			Visible = Theme.f(function(_, s)
				return not s.touch
			end),
			ZIndex = 20,
			Parent = frame,
		})
		local gripIcon = Icons.new("grip", 14, C("textSubtle"))
		gripIcon.Frame.Parent = grip
		local startSize
		Drag.attach(grip, {
			threshold = 1,
			onStart = function()
				startSize = frame.AbsoluteSize
			end,
			onMove = function(_, _, total)
				local vp = Device.viewport()
				local at = Device.offsetOf(frame)
				local w = math.clamp(startSize.X + total.X, 260, math.max(260, vp.X - at.X - 8))
				local h = math.clamp(startSize.Y + total.Y, 200, math.max(200, vp.Y - at.Y - 8))
				frame.Size = UDim2.fromOffset(w, h)
			end,
			onEnd = function()
				self:_save()
			end,
		}, self.Maid)

		-- Pill for minimising
		self.Pill = Pill.new(window, {
			title = tab.TitleSpec,
			logo = function(size)
				local holder = New("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = C("raised") }, { Create.corner("full") })
				local icon = Icons.new(tab.Icon, 16, C("accent"), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
				icon.Frame.Parent = holder
				return holder
			end,
			onRestore = function()
				self:Restore()
			end,
		})
		self.Maid:Add(self.Pill)

		tab.DetachedWindow = self
		return self
	end

	function Detached:_snap()
		local frame = self.Frame
		local vp = Device.viewport()
		local p, size = Device.offsetOf(frame), frame.AbsoluteSize
		local margin, edge = 8, 20
		local x, y = p.X, p.Y
		if x < edge then
			x = margin
		elseif x + size.X > vp.X - edge then
			x = vp.X - size.X - margin
		end
		local top = Device.inset() + margin
		if y < top + edge then
			y = top
		elseif y + size.Y > vp.Y - edge then
			y = vp.Y - size.Y - margin
		end
		local clamped = Drag.clamp(Vector2.new(x, y), size)
		Motion.tween(frame, { Position = UDim2.fromOffset(clamped.X, clamped.Y) }, "window")
	end

	function Detached:_save()
		local p, s = Device.offsetOf(self.Frame), self.Frame.AbsoluteSize
		self.Window.Config:SetDetached(self.Tab.Id, { x = p.X, y = p.Y, w = s.X, h = s.Y, open = true })
	end

	function Detached:Focus()
		self:Restore()
		self.Frame.ZIndex = self.Window.Root:NextZ()
		self.Scale.Scale = 0.97
		Motion.tween(self.Scale, { Scale = 1 }, "spring")
	end

	function Detached:SetHidden(hidden)
		if self.Minimized then
			return
		end
		self.Frame.Visible = not hidden
	end

	function Detached:Minimize()
		self.Minimized = true
		self.Frame.Visible = false
		self.Pill:Show(true)
	end

	function Detached:Restore()
		if not self.Minimized then
			return
		end
		self.Minimized = false
		self.Pill:Hide()
		self.Frame.Visible = true
		self.Frame.ZIndex = self.Window.Root:NextZ()
	end

	-- Return the tab to the main window (folds into its nav item).
	function Detached:Attach()
		if self.Closing then
			return
		end
		self.Closing = true
		local window, tab = self.Window, self.Tab
		self:_save()
		window.Config:SetDetached(tab.Id, nil, true)
		local target = window:_navItemFor(tab)
		local function finish()
			self:Destroy(false)
			window:_attached(tab)
		end
		if target and Motion.Mode == "Full" and not self.Minimized then
			local pos, size = Device.toOffset(target.AbsolutePosition), target.AbsoluteSize
			Motion.tween(self.Frame, {
				Position = UDim2.fromOffset(pos.X, pos.Y),
				Size = UDim2.fromOffset(size.X, size.Y),
			}, "window")
			task.delay(0.28, finish)
		else
			finish()
		end
	end

	function Detached:Destroy(keepPage)
		local tab = self.Tab
		if tab.Page.Parent == self.Content then
			if keepPage then
				tab.Page.Parent = nil
			else
				tab.Page.Parent = self.Window.PageHost
			end
			tab.Page.Visible = false
		end
		Theme.bind(tab.PageHeader, "Visible", S("pageHeader"))
		tab.DetachedWindow = nil
		self.Maid:Clean()
	end

	return Detached
end

__modules["ui/Dialog"] = function()
	-- Dialog: confirmation / input dialogs in the Modal layer.
	--   window:Dialog({
	--     Title = "Delete profile?", Content = "…",
	--     Input = { Placeholder = "…", Default = "", Numeric = false },
	--     Buttons = { { Text = "Cancel" }, { Text = "Delete", Variant = "Danger", Callback = function(text) end } },
	--   })
	-- A callback returning false keeps the dialog open.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Device = import("core/Device")
	local Maid = import("util/Maid")
	local Services = import("core/Services")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Dialog = {}
	Dialog.__index = Dialog

	local VARIANTS = {
		Primary = { bg = "accent", fg = "accentInk", weight = "SemiBold" },
		Secondary = { bg = "segment", fg = "text", weight = "Medium" },
		Danger = { bg = "danger", fg = "dangerInk", weight = "SemiBold" },
	}

	function Dialog.new(window)
		local self = setmetatable({}, Dialog)
		self.Window = window
		self.Layer = window.Root.Modal
		self.Current = nil
		return self
	end

	function Dialog:Close()
		if self.Current then
			local current = self.Current
			self.Current = nil
			current.Close()
		end
	end

	function Dialog:Open(opts)
		self:Close()
		local loc = self.Window.Loc
		local maid = Maid.new()
		local handle = {}

		local backdrop = maid:Add(New("TextButton", {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C("backdrop"),
			BackgroundTransparency = 1,
			Parent = self.Layer,
		}))
		Motion.tween(backdrop, { BackgroundTransparency = 0.45 }, "fade")

		local vp = Device.viewport()
		local card = New("Frame", {
			Name = "Dialog",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(math.min(opts.Width or 340, vp.X - 32), 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C("overlay"),
			Active = true,
			Parent = backdrop,
		}, {
			Create.corner(18),
			Create.stroke("borderStrong"),
			Create.pad(18),
			Create.list("Vertical", 14),
		})
		local scale = New("UIScale", { Scale = 0.94, Parent = card })
		Motion.tween(scale, { Scale = 1 }, "spring")

		local head = New("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = card,
		}, { Create.list("Vertical", 6) })
		local title = Create.text("", { weight = "Bold", size = "fontHeader", wrap = true, order = 1 })
		title.TextSize = 16
		Theme.unbind(title, "TextSize")
		title.Parent = head
		loc:Bind(title, "Text", opts.Title or "", opts.Vars)
		if opts.Content then
			local content = Create.text("", { size = "fontDesc", color = "textMuted", wrap = true, order = 2 })
			content.TextSize = 13.5
			Theme.unbind(content, "TextSize")
			content.LineHeight = 1.1
			content.Parent = head
			loc:Bind(content, "Text", opts.Content, opts.ContentVars or opts.Vars)
		end

		local box
		if opts.Input then
			local holder = New("Frame", {
				Size = Theme.sz(1, 0, 0, "input"),
				BackgroundColor3 = C("bg"),
				LayoutOrder = 2,
				Parent = card,
			}, { Create.corner(10), Create.pad(0, 12) })
			local stroke = Create.stroke("accent", 1.5)
			stroke.Parent = holder
			box = New("TextBox", {
				Size = UDim2.fromScale(1, 1),
				Text = opts.Input.Default or "",
				TextTruncate = Enum.TextTruncate.AtEnd,
				Mono = opts.Input.Mono,
				Parent = holder,
			})
			loc:Bind(box, "PlaceholderText", opts.Input.Placeholder or "")
			task.defer(function()
				if box.Parent then
					box:CaptureFocus()
				end
			end)
		end

		local row = New("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
			Parent = card,
		}, { Create.list("Horizontal", 8) })

		local closed = false
		function handle.Close()
			if closed then
				return
			end
			closed = true
			if self.Current == handle then
				self.Current = nil
			end
			Motion.tween(backdrop, { BackgroundTransparency = 1 }, "fade")
			Motion.tween(scale, { Scale = 0.96 }, "press")
			task.delay(Motion.Mode == "Off" and 0 or 0.12, function()
				maid:Clean()
			end)
			if opts.OnClose then
				task.spawn(opts.OnClose)
			end
		end
		self.Current = handle

		local buttons = opts.Buttons or { { Text = { __lib = "ok" }, Variant = "Primary" } }
		for index, spec in ipairs(buttons) do
			local variant = VARIANTS[spec.Variant or (index == #buttons and "Primary" or "Secondary")] or VARIANTS.Secondary
			local button = New("TextButton", {
				Size = Theme.sz(0, 0, 0, "button"),
				BackgroundColor3 = C(variant.bg),
				TextColor3 = C(variant.fg),
				Weight = variant.weight,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = index,
				Parent = row,
			}, { Create.corner(10), Create.flex(), Create.pad(0, 8) })
			button.TextXAlignment = Enum.TextXAlignment.Center
			button.TextTruncate = Enum.TextTruncate.AtEnd
			loc:Bind(button, "Text", spec.Text or "OK")
			Motion.pressable(button, nil, nil, maid)
			maid:Add(button.Activated:Connect(function()
				local result = nil
				if spec.Callback then
					local ok, value = pcall(spec.Callback, box and box.Text or nil)
					if not ok then
						warn("[Robly] dialog callback: " .. tostring(value))
					end
					result = value
				end
				if result ~= false then
					handle.Close()
				end
			end))
		end

		if box then
			maid:Add(box.FocusLost:Connect(function(enter)
				if enter then
					local last = buttons[#buttons]
					if last and last.Callback then
						local ok, value = pcall(last.Callback, box.Text)
						if ok and value == false then
							return
						end
					end
					handle.Close()
				end
			end))
		end

		maid:Add(Services.UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				handle.Close()
			end
		end))

		return handle
	end

	return Dialog
end

__modules["ui/Effects"] = function()
	-- Effects: decorative background inside a window, behind all content.
	--   Aurora   — large soft colour blobs (accent / accent2) drifting slowly
	--   Stars    — tiny twinkling dots
	--   Snow     — slowly falling dots
	--   Grid     — faint line grid with an accent glow in the corner
	--   Gradient — diagonal accent wash
	--   None
	-- Animated with looping tweens (no per-frame scripts); static when animations
	-- are "Soft" or "Off". Panels become translucent with Theme.Glass.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Services = import("core/Services")
	local Maid = import("util/Maid")

	local New = Create.New
	local C = Theme.c

	local Effects = {}
	Effects.__index = Effects

	-- deterministic pseudo-random so a layout looks the same every time
	local function rng(seed)
		local state = seed
		return function()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	local function loop(instance, props, seconds, style)
		if Motion.Mode ~= "Full" then
			return nil
		end
		local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local tween = Services.TweenService:Create(instance, info, props)
		tween:Play()
		return tween
	end

	function Effects.new(parent, zindex)
		local self = setmetatable({}, Effects)
		self.Parent = parent
		self.Maid = Maid.new()
		self.Holder = self.Maid:Add(New("Frame", {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			ZIndex = zindex or 0,
			ClipsDescendants = true,
			Parent = parent,
		}))
		self.Maid:Add(Theme.Changed:Connect(function(what)
			if what == "effect" or (what == "colors" and self._built ~= Theme.Effect) then
				self:Build()
			end
		end))
		self.Maid:Add(Motion.Changed:Connect(function()
			self:Build()
		end))
		self:Build()
		return self
	end

	function Effects:Build()
		if self._maid then
			self._maid:Clean()
		end
		local maid = Maid.new()
		self._maid = maid
		local holder = self.Holder
		local effect = Theme.Effect
		self._built = effect
		local random = rng(7)

		if effect == "Aurora" then
			local blobs = {
				{ color = "accent", x = 0.05, y = -0.25, size = 0.75, alpha = 0.86 },
				{ color = "accent2", x = 0.55, y = 0.35, size = 0.8, alpha = 0.88 },
				{ color = "accent", x = 0.75, y = -0.35, size = 0.5, alpha = 0.92 },
			}
			for index, spec in ipairs(blobs) do
				local blob = maid:Add(New("Frame", {
					Name = "Blob",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(spec.x + spec.size / 2, spec.y + spec.size / 2),
					Size = UDim2.fromScale(spec.size, spec.size * 1.3),
					BackgroundColor3 = C(spec.color),
					BackgroundTransparency = spec.alpha,
					Parent = holder,
				}, {
					Create.corner("full"),
					New("UIGradient", {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.5, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
						Rotation = index * 40,
					}),
				}))
				maid:Add(loop(blob, {
					Position = UDim2.fromScale(spec.x + spec.size / 2 + (index % 2 == 0 and -0.12 or 0.12), spec.y + spec.size / 2 + 0.1),
					Rotation = index % 2 == 0 and -25 or 25,
				}, 9 + index * 3))
			end
		elseif effect == "Stars" or effect == "Snow" then
			local count = effect == "Stars" and 46 or 34
			for _ = 1, count do
				local size = effect == "Stars" and (random() < 0.8 and 2 or 3) or math.floor(2 + random() * 3)
				local x, y = random(), random()
				local dot = maid:Add(New("Frame", {
					Name = "Dot",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(x, effect == "Snow" and -0.05 + y * 0.2 or y),
					Size = UDim2.fromOffset(size, size),
					BackgroundColor3 = random() < 0.25 and C("accent") or C("text"),
					BackgroundTransparency = 0.35 + random() * 0.45,
					Parent = holder,
				}, { Create.corner("full") }))
				if effect == "Stars" then
					maid:Add(loop(dot, { BackgroundTransparency = 0.92 }, 1.5 + random() * 3))
				else
					dot.Position = UDim2.fromScale(x, y)
					local fall = Motion.Mode == "Full" and TweenInfo.new(9 + random() * 9, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false, random() * 6)
					if fall then
						dot.Position = UDim2.fromScale(x, -0.05)
						local tween = Services.TweenService:Create(dot, fall, { Position = UDim2.fromScale(x + (random() - 0.5) * 0.15, 1.05) })
						tween:Play()
						maid:Add(tween)
					end
				end
			end
		elseif effect == "Grid" then
			local step = 28
			for i = 0, 60 do
				maid:Add(New("Frame", {
					Position = UDim2.fromOffset(i * step, 0),
					Size = UDim2.new(0, 1, 1, 0),
					BackgroundColor3 = C("text"),
					BackgroundTransparency = 0.955,
					Parent = holder,
				}))
			end
			for i = 0, 40 do
				maid:Add(New("Frame", {
					Position = UDim2.fromOffset(0, i * step),
					Size = UDim2.new(1, 0, 0, 1),
					BackgroundColor3 = C("text"),
					BackgroundTransparency = 0.955,
					Parent = holder,
				}))
			end
			local glow = maid:Add(New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.95, 0.05),
				Size = UDim2.fromScale(0.9, 0.9),
				BackgroundColor3 = C("accent"),
				BackgroundTransparency = 0.88,
				Parent = holder,
			}, {
				Create.corner("full"),
				New("UIGradient", {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.5, 0),
						NumberSequenceKeypoint.new(1, 1),
					}),
					Rotation = 45,
				}),
			}))
			maid:Add(loop(glow, { BackgroundTransparency = 0.94 }, 4))
		elseif effect == "Gradient" then
			local wash = maid:Add(New("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.86,
				Parent = holder,
			}, {
				New("UIGradient", {
					Color = Theme.gradient(),
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(0.55, 0.85),
						NumberSequenceKeypoint.new(1, 1),
					}),
					Rotation = 35,
				}),
			}))
			local gradient = wash:FindFirstChildOfClass("UIGradient")
			maid:Add(loop(gradient, { Rotation = 55 }, 8))
		end
	end

	function Effects:Destroy()
		if self._maid then
			self._maid:Clean()
		end
		self.Maid:Clean()
	end

	return Effects
end

__modules["ui/Notifications"] = function()
	-- Notifications (toasts) in their own layer and corner:
	--   PC     — top right, under the Roblox top bar
	--   touch  — top centre, under the top bar (top right belongs to quick buttons)

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Device = import("core/Device")
	local Icons = import("core/Icons")
	local Maid = import("util/Maid")
	local Services = import("core/Services")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Notifications = {}
	Notifications.__index = Notifications

	local KINDS = {
		success = { icon = "check", color = "success" },
		warning = { icon = "warning", color = "warning" },
		error = { icon = "error", color = "danger" },
		info = { icon = "info", color = "text" },
		bind = { icon = "keyboard", color = "accent" },
	}

	function Notifications.new(window)
		local self = setmetatable({}, Notifications)
		self.Window = window
		self.Holder = New("Frame", {
			Name = "Toasts",
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = window.Root.Notifications,
		}, { Create.list("Vertical", 8, { align = "Right" }) })
		Theme.bind(self.Holder, "AnchorPoint", Theme.f(function(_, s)
			return s.touch and Vector2.new(0.5, 0) or Vector2.new(1, 0)
		end))
		Theme.bind(self.Holder, "Size", Theme.f(function(_, s)
			return UDim2.fromOffset(math.min(s.toastWidth, Device.viewport().X - 32), 0)
		end))
		self:Place()
		self._order = 0
		self._live = {}
		return self
	end

	function Notifications:Place()
		local touch = Theme.Sizes.touch
		local top = Device.inset() + (touch and 8 or 16)
		if touch then
			self.Holder.Position = UDim2.new(0.5, 0, 0, top)
		else
			self.Holder.Position = UDim2.new(1, -24, 0, top)
		end
		local vp = Device.viewport()
		self.Holder.Size = UDim2.fromOffset(math.min(Theme.Sizes.toastWidth, vp.X - 32), 0)
	end

	-- opts: Title, Content, Type ("success"|"warning"|"error"|"info"), Icon,
	--       Duration (seconds, default 4; 0 = until closed), Vars,
	--       Action = { Text, Callback }
	function Notifications:Notify(opts)
		opts = opts or {}
		local loc = self.Window.Loc
		local kind = KINDS[opts.Type or "info"] or KINDS.info
		local duration = opts.Duration
		if duration == nil then
			duration = 4
		end
		local maid = Maid.new()
		self._order += 1

		local toast = maid:Add(New("TextButton", {
			Name = "Toast",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C("overlay"),
			LayoutOrder = -self._order,
			ClipsDescendants = true,
			Parent = self.Holder,
		}, {
			Create.corner(14),
			Create.stroke("borderStrong"),
		}))
		local body = New("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = toast,
		}, {
			Create.pad(12, 14),
			Create.list("Horizontal", 12, { valign = "Center" }),
		})

		local badge = New("Frame", {
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = kind.color == "text" and C("raised") or C(kind.color),
			BackgroundTransparency = kind.color == "text" and 0 or 0.86,
			LayoutOrder = 1,
			Parent = body,
		}, { Create.corner(8) })
		local icon = Icons.new(opts.Icon or kind.icon, 16, C(kind.color), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		icon.Frame.Parent = badge

		local texts = New("Frame", {
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = body,
		}, { Create.list("Vertical", 2), Create.flex() })
		local title = Create.text("", { weight = "SemiBold", size = "fontDesc", wrap = true, order = 1 })
		title.TextSize = 13
		Theme.unbind(title, "TextSize")
		title.Parent = texts
		loc:Bind(title, "Text", opts.Title or "", opts.Vars)
		if opts.Content then
			local content = Create.text("", { size = "fontDesc", color = "textMuted", wrap = true, order = 2 })
			content.Parent = texts
			loc:Bind(content, "Text", opts.Content, opts.ContentVars or opts.Vars)
		end

		local handle = {}
		local closed = false
		function handle.Close()
			if closed then
				return
			end
			closed = true
			self._live[handle] = nil
			Motion.tween(toast, { BackgroundTransparency = 1 }, "fade")
			local scale = toast:FindFirstChildOfClass("UIScale") or New("UIScale", { Parent = toast })
			Motion.tween(scale, { Scale = 0.92 }, "press")
			task.delay(Motion.Mode == "Off" and 0 or 0.14, function()
				maid:Clean()
			end)
		end
		self._live[handle] = true

		if opts.Action then
			local action = New("TextButton", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 30),
				BackgroundColor3 = C("segment"),
				Weight = "SemiBold",
				TextSize = 13,
				LayoutOrder = 3,
				Parent = body,
			}, { Create.corner(8), Create.pad(0, 10) })
			loc:Bind(action, "Text", opts.Action.Text or "OK")
			Motion.pressable(action, nil, nil, maid)
			maid:Add(action.Activated:Connect(function()
				handle.Close()
				if opts.Action.Callback then
					task.spawn(opts.Action.Callback)
				end
			end))
		end

		maid:Add(toast.Activated:Connect(handle.Close))

		if duration and duration > 0 then
			local bar = New("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = C("raised"),
				Parent = toast,
			})
			local fill = New("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = C("accent"),
				Parent = bar,
			})
			local info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
			if Motion.Mode ~= "Off" then
				local tween = Services.TweenService:Create(fill, info, { Size = UDim2.fromScale(0, 1) })
				tween:Play()
			end
			task.delay(duration, handle.Close)
		end

		-- entrance
		local scale = New("UIScale", { Scale = 0.94, Parent = toast })
		Motion.tween(scale, { Scale = 1 }, "spring")

		-- keep at most 4 toasts
		local count = 0
		for _ in pairs(self._live) do
			count += 1
		end
		if count > 4 then
			local oldest, oldestOrder = nil, math.huge
			for h in pairs(self._live) do
				if h ~= handle and h.order and h.order < oldestOrder then
					oldest, oldestOrder = h, h.order
				end
			end
			if oldest then
				oldest.Close()
			end
		end
		handle.order = self._order
		return handle
	end

	function Notifications:Destroy()
		self.Holder:Destroy()
	end

	return Notifications
end

__modules["ui/Pill"] = function()
	-- Pill: the minimised window. Drag to move, tap to restore.
	-- Shows a green dot while at least one toggle is on.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Drag = import("core/Drag")
	local Device = import("core/Device")
	local Maid = import("util/Maid")

	local New = Create.New
	local C = Theme.c

	local Pill = {}
	Pill.__index = Pill

	-- opts: layer, root, title (text spec), logo (Frame builder), onRestore, position (Vector2?)
	function Pill.new(window, opts)
		local self = setmetatable({}, Pill)
		self.Window = window
		self.Maid = Maid.new()
		local loc = window.Loc

		local button = self.Maid:Add(New("TextButton", {
			Name = "Pill",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 44),
			BackgroundColor3 = C("overlay"),
			Visible = false,
			Parent = window.Root.Windows,
		}, {
			Create.corner("full"),
			Create.stroke("borderStrong"),
			Create.pad(0, 14, 0, 9),
			Create.list("Horizontal", 10, { valign = "Center" }),
		}))
		self.Button = button

		if opts.logo then
			local logo = opts.logo(26)
			logo.LayoutOrder = 1
			logo.Parent = button
		end
		local label = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 44),
			Weight = "SemiBold",
			TextSize = 13.5,
			LayoutOrder = 2,
			Parent = button,
		}, { Create.maxSize(200, nil) })
		label.TextTruncate = Enum.TextTruncate.AtEnd
		loc:Bind(label, "Text", opts.title)

		self.Dot = New("Frame", {
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = C("success"),
			Visible = false,
			LayoutOrder = 3,
			Parent = button,
		}, { Create.corner("full") })

		local moved = false
		local startPosition
		Drag.attach(button, {
			onStart = function()
				moved = false
				startPosition = Device.offsetOf(button)
				button.ZIndex = window.Root:NextZ()
			end,
			onMove = function(_, _, total)
				moved = true
				local p = Drag.clamp(startPosition + total, button.AbsoluteSize)
				button.Position = UDim2.fromOffset(p.X, p.Y)
			end,
			onEnd = function()
				if moved and opts.onMoved then
					opts.onMoved(Device.offsetOf(button))
				end
			end,
		}, self.Maid)
		self.Maid:Add(button.Activated:Connect(function()
			if not moved and opts.onRestore then
				opts.onRestore()
			end
			moved = false
		end))
		Motion.pressable(button, nil, 0.95, self.Maid)

		self.Position = opts.position
		return self
	end

	function Pill:SetActive(active)
		self.Dot.Visible = active
	end

	function Pill:DefaultPosition()
		local vp = Device.viewport()
		local size = self.Button.AbsoluteSize
		if size.X < 10 then
			size = Vector2.new(180, 44)
		end
		return Vector2.new(math.floor(vp.X / 2 - size.X / 2), Device.inset() + 8)
	end

	function Pill:Show(from)
		local button = self.Button
		local target = self.Position or self:DefaultPosition()
		target = Drag.clamp(target, Vector2.new(math.max(button.AbsoluteSize.X, 160), 44))
		button.Position = UDim2.fromOffset(target.X, target.Y)
		button.ZIndex = self.Window.Root:NextZ()
		button.Visible = true
		local scale = button:FindFirstChildOfClass("UIScale")
		if scale and from then
			scale.Scale = 0.6
			Motion.tween(scale, { Scale = 1 }, "spring")
		end
	end

	function Pill:Hide()
		self.Position = Device.offsetOf(self.Button)
		self.Button.Visible = false
	end

	function Pill:Rect()
		-- offset space (for positioning other top-level frames)
		return Device.offsetOf(self.Button), self.Button.AbsoluteSize
	end

	function Pill:Destroy()
		self.Maid:Clean()
	end

	return Pill
end

__modules["ui/Search"] = function()
	-- Search across every control of the window (all platforms).
	-- Matches the current language, the default language and the text key, so
	-- both "farm" and "фарм" find "Авто-фарм уровня". Tap a result to jump to it.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Icons = import("core/Icons")
	local Util = import("util/Util")
	local Maid = import("util/Maid")

	local New = Create.New
	local C, S = Theme.c, Theme.s

	local Search = {}
	Search.__index = Search

	function Search.new(window)
		local self = setmetatable({}, Search)
		self.Window = window
		self.Entries = {}
		self.Query = ""
		return self
	end

	function Search:Add(control)
		table.insert(self.Entries, control)
	end

	function Search:Remove(control)
		local index = table.find(self.Entries, control)
		if index then
			table.remove(self.Entries, index)
		end
	end

	local function escape(text)
		return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end

	local function highlight(text, query, color)
		if query == "" then
			return escape(text)
		end
		local lower = Util.lower(text)
		local first, last = lower:find(query, 1, true)
		if not first or #lower ~= #text then
			return escape(text)
		end
		return escape(text:sub(1, first - 1))
			.. '<font color="#' .. Util.toHex(color) .. '">' .. escape(text:sub(first, last)) .. "</font>"
			.. escape(text:sub(last + 1))
	end

	function Search:Find(query)
		query = Util.lower(Util.trim(query or ""))
		local results = {}
		if query == "" then
			return results
		end
		for _, control in ipairs(self.Entries) do
			if not control.Destroyed and control.Visible ~= false and not control.Tab.Internal then
				for _, text in ipairs(control:SearchTexts()) do
					if Util.lower(text):find(query, 1, true) then
						table.insert(results, control)
						break
					end
				end
			end
		end
		-- Settings controls come last, still searchable
		for _, control in ipairs(self.Entries) do
			if not control.Destroyed and control.Visible ~= false and control.Tab.Internal then
				for _, text in ipairs(control:SearchTexts()) do
					if Util.lower(text):find(query, 1, true) then
						table.insert(results, control)
						break
					end
				end
			end
		end
		return results
	end

	-- Overlay listing results, placed over the page area.
	function Search:BuildOverlay(parent)
		self.Overlay = New("Frame", {
			Name = "SearchResults",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C("bg"),
			Visible = false,
			ZIndex = 20,
			Parent = parent,
		})
		self.List = New("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			ZIndex = 20,
			Parent = self.Overlay,
		}, { Create.list("Vertical", 8) })
		self.List.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		self._maid = Maid.new()
		return self.Overlay
	end

	function Search:SetQuery(text)
		self.Query = text or ""
		self:Render()
	end

	function Search:Clear()
		self.Query = ""
		if self.Overlay then
			self.Overlay.Visible = false
		end
		self._maid:Clean()
	end

	function Search:Render()
		local window = self.Window
		local loc = window.Loc
		self._maid:Clean()
		local query = Util.trim(self.Query)
		if query == "" then
			self.Overlay.Visible = false
			return
		end
		self.Overlay.Visible = true
		local results = self:Find(query)
		local lowerQuery = Util.lower(query)

		local tabs = {}
		local tabCount = 0
		for _, control in ipairs(results) do
			if not tabs[control.Tab] then
				tabs[control.Tab] = true
				tabCount += 1
			end
		end
		local summary = self._maid:Add(Create.text(loc:Lib(#results > 0 and "results" or "nothing_found", { n = #results, t = tabCount }), {
			size = "fontDesc", color = "textSubtle", order = 0,
		}))
		summary.Parent = self.List
		summary.ZIndex = 20
		if #results == 0 then
			return
		end

		local card = self._maid:Add(New("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C("surface"),
			LayoutOrder = 1,
			ZIndex = 20,
			Parent = self.List,
		}, { Create.corner("rSection"), Create.stroke("border"), Create.list("Vertical", 0, { align = "Right" }) }))

		for index, control in ipairs(results) do
			if index > 1 then
				New("Frame", {
					Size = Theme.f(function(_, s)
						return UDim2.new(1, -s.padX, 0, 1)
					end),
					BackgroundColor3 = C("border"),
					LayoutOrder = index * 2 - 1,
					ZIndex = 20,
					Parent = card,
				})
			end
			local row = New("TextButton", {
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = C("raised"),
				BackgroundTransparency = 1,
				LayoutOrder = index * 2,
				ZIndex = 20,
				Parent = card,
			}, {
				Create.pad("padY", "padX"),
				Create.minSize(0, "rowDesc"),
				Create.list("Horizontal", 12, { valign = "Center" }),
			})
			local texts = New("Frame", {
				Size = UDim2.fromScale(0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				ZIndex = 20,
				Parent = row,
			}, { Create.list("Vertical", 2), Create.flex() })
			local title = Create.text("", { weight = "Medium", wrap = true, rich = true, order = 1 })
			title.ZIndex = 20
			title.Text = highlight(loc:Get(control.TitleSpec), lowerQuery, Theme.Colors.accent)
			title.Parent = texts
			local path = loc:Get(control.Tab.TitleSpec)
			if control.Section.SubTab then
				path ..= " › " .. loc:Get(control.Section.SubTab.TitleSpec)
			end
			if control.Section.TitleSpec then
				path ..= " › " .. loc:Get(control.Section.TitleSpec)
			end
			if not control.Enabled then
				path ..= " · " .. loc:Lib("locked")
			end
			local pathLabel = Create.text(path, { size = "fontDesc", color = "textSubtle", wrap = true, order = 2 })
			pathLabel.ZIndex = 20
			pathLabel.Parent = texts
			local state = control:StateText()
			if state then
				local stateLabel = New("TextLabel", {
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 20),
					Text = state,
					TextColor3 = C("textMuted"),
					TextSize = S("fontDesc"),
					LayoutOrder = 3,
					ZIndex = 20,
					Parent = row,
				}, { Create.maxSize(120, nil) })
				stateLabel.TextTruncate = Enum.TextTruncate.AtEnd
			end
			local chevron = Icons.new("chevronRight", 14, C("textSubtle"))
			chevron.Frame.LayoutOrder = 4
			chevron.Frame.ZIndex = 20
			chevron.Frame.Parent = row
			self._maid:Add(row.MouseEnter:Connect(function()
				row.BackgroundTransparency = 0.6
			end))
			self._maid:Add(row.MouseLeave:Connect(function()
				row.BackgroundTransparency = 1
			end))
			self._maid:Add(row.Activated:Connect(function()
				window:Reveal(control)
			end))
		end
	end

	function Search:Destroy()
		if self._maid then
			self._maid:Clean()
		end
	end

	return Search
end

__modules["ui/Section"] = function()
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
end

__modules["ui/Tab"] = function()
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
		self.CategorySpec = opts.Category
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
		-- icon tile (accent-tinted) gives every page a visual anchor
		local tile = New("Frame", {
			Name = "IconTile",
			Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = C("accent"),
			BackgroundTransparency = 0.84,
			LayoutOrder = 0,
			Parent = header,
		}, { Create.corner(10), Create.stroke("accent", 1, 0.7) })
		Icons.new(self.Icon, 20, C("accent"), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		}).Frame.Parent = tile
		local texts = New("Frame", {
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = header,
		}, { Create.list("Vertical", 2), Create.flex() })
		-- breadcrumb: "Tab › Sub tab" (visible once the tab has sub tabs)
		local crumb = New("TextLabel", {
			Name = "Crumb",
			Size = UDim2.new(1, 0, 0, 14),
			TextColor3 = C("textSubtle"),
			TextSize = 11,
			Weight = "SemiBold",
			Visible = false,
			LayoutOrder = 0,
			Parent = texts,
		})
		self.Crumb = crumb
		local title = Create.text("", { weight = "Bold", size = "fontTitle", wrap = true, order = 1 })
		title.Parent = texts
		self.TitleLabel = title
		self:_updateTitle()
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
		-- PC shows sub tabs as a tree in the sidebar; touch shows the pill row
		Theme.bind(self.SubBar, "Visible", Theme.f(function(_, s)
			return s.touch and #self.SubTabs > 0
		end))
		if self.Window.Selected == self then
			self.Window:_rebuildNav()
		end
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
		self.Main.Frame.Visible = not self.Main:IsEmpty()
		if previous ~= target then
			self:_updateTitle()
			if self.Window.Selected == self and Theme.Mode == "pc" then
				self.Window:_rebuildNav()
			end
		end
	end

	-- Page title shows the current sub tab; the breadcrumb above it names the tab.
	function Tab:_updateTitle()
		local loc = self.Window.Loc
		local sub = self.CurrentSubTab
		if sub then
			self.Crumb.Visible = true
			loc:Bind(self.Crumb, "Text", function()
				return Util.upper(loc:Get(self.TitleSpec)) .. "  ›  " .. Util.upper(loc:Get(sub.TitleSpec))
			end)
			loc:Bind(self.TitleLabel, "Text", sub.TitleSpec)
		else
			self.Crumb.Visible = false
			loc:Bind(self.TitleLabel, "Text", self.TitleSpec)
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
		self:_updateTitle()
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
end

__modules["ui/Tooltip"] = function()
	-- Tooltip: small inverted bubble in the Popups layer.
	-- PC: hover for 0.45 s. Touch: tap the "?" button (or long text) to show.

	local Theme = import("core/Theme")
	local Create = import("core/Create")
	local Motion = import("core/Motion")
	local Device = import("core/Device")

	local New = Create.New
	local C = Theme.c

	local Tooltip = {}
	Tooltip.__index = Tooltip

	function Tooltip.new(window)
		local self = setmetatable({}, Tooltip)
		self.Window = window
		self.Frame = New("Frame", {
			Name = "Tooltip",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = C("tooltip"),
			Visible = false,
			ZIndex = 10,
			Parent = window.Root.Popups,
		}, {
			Create.corner(10),
			Create.pad(8, 10),
			Create.maxSize(240, nil),
		})
		self.Label = New("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.XY,
			TextColor3 = C("tooltipText"),
			TextWrapped = true,
			TextSize = 12.5,
			Parent = self.Frame,
		}, { Create.maxSize(220, nil) })
		self._token = 0
		return self
	end

	function Tooltip:Show(anchor, spec, vars)
		self._token += 1
		local loc = self.Window.Loc
		self.Label.Text = loc:Get(spec, vars)
		local frame = self.Frame
		frame.Visible = true
		task.defer(function()
			local vp = Device.viewport()
			local size = frame.AbsoluteSize
			local ap, as = Device.toOffset(anchor.AbsolutePosition), anchor.AbsoluteSize
			local x = math.clamp(ap.X + as.X / 2 - size.X / 2, 8, math.max(8, vp.X - size.X - 8))
			local y = ap.Y - size.Y - 8
			if y < Device.inset() + 4 then
				y = ap.Y + as.Y + 8
			end
			frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
		end)
		frame.BackgroundTransparency = 1
		self.Label.TextTransparency = 1
		Motion.tween(frame, { BackgroundTransparency = 0 }, "fade")
		Motion.tween(self.Label, { TextTransparency = 0 }, "fade")
		local token = self._token
		task.delay(Theme.Sizes.touch and 2.5 or 6, function()
			if self._token == token then
				self:Hide()
			end
		end)
	end

	function Tooltip:Hide()
		self._token += 1
		self.Frame.Visible = false
	end

	-- Attach hover (PC) / tap-on-anchor (touch) behaviour.
	-- condition (optional): only show when it returns true (e.g. text truncated)
	function Tooltip:Attach(anchor, spec, maid, vars, condition)
		local token = 0
		maid:Add(anchor.MouseEnter:Connect(function()
			if Theme.Sizes.touch or (condition and not condition()) then
				return
			end
			token += 1
			local mine = token
			task.delay(0.45, function()
				if token == mine then
					self:Show(anchor, spec, vars)
				end
			end)
		end))
		maid:Add(anchor.MouseLeave:Connect(function()
			token += 1
			self:Hide()
		end))
	end

	function Tooltip:Destroy()
		self.Frame:Destroy()
	end

	return Tooltip
end

__modules["ui/Window"] = function()
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
			Create.panel(nav, { color = C("nav"), transparency = Theme.glass(0.35), radius = radius, round = round })
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
end

__modules["util/Compat"] = function()
	-- Compat: every executor-specific function goes through here. Each one is
	-- checked before use and has a fallback, so Robly runs on weak executors
	-- (Xeno, Solara, mobile) without file system, clipboard or gethui.

	local Compat = {}

	-- Executor functions are plain globals of the script environment. Reading a
	-- missing global just gives nil, so every lookup is safe.
	local function pick(...)
		for i = 1, select("#", ...) do
			local candidate = select(i, ...)
			if type(candidate) == "function" then
				return candidate
			end
		end
		return nil
	end

	local function member(t, key)
		if type(t) == "table" and type(t[key]) == "function" then
			return t[key]
		end
		return nil
	end

	local syn = syn
	local http = http

	-- Services ---------------------------------------------------------------

	local cloneref = pick(cloneref)

	function Compat.service(name)
		local service = game:GetService(name)
		if cloneref then
			local ok, cloned = pcall(cloneref, service)
			if ok and cloned then
				return cloned
			end
		end
		return service
	end

	-- File system --------------------------------------------------------------

	local writefile = pick(writefile)
	local readfile = pick(readfile)
	local isfile = pick(isfile)
	local isfolder = pick(isfolder)
	local makefolder = pick(makefolder)
	local listfiles = pick(listfiles)
	local delfile = pick(delfile)

	Compat.hasFileSystem = writefile ~= nil and readfile ~= nil and isfile ~= nil and makefolder ~= nil and isfolder ~= nil

	function Compat.ensureFolder(path)
		if not Compat.hasFileSystem then
			return false
		end
		local current = ""
		for part in tostring(path):gmatch("[^/]+") do
			current = current == "" and part or (current .. "/" .. part)
			local ok, exists = pcall(isfolder, current)
			if not (ok and exists) then
				pcall(makefolder, current)
			end
		end
		return true
	end

	function Compat.write(path, content)
		if not Compat.hasFileSystem then
			return false
		end
		return (pcall(writefile, path, content))
	end

	function Compat.read(path)
		if not Compat.hasFileSystem then
			return nil
		end
		local ok, exists = pcall(isfile, path)
		if not (ok and exists) then
			return nil
		end
		local okRead, content = pcall(readfile, path)
		if okRead then
			return content
		end
		return nil
	end

	function Compat.delete(path)
		if not delfile then
			return false
		end
		return (pcall(delfile, path))
	end

	function Compat.list(folder)
		if not listfiles then
			return {}
		end
		local ok, files = pcall(listfiles, folder)
		if not ok or type(files) ~= "table" then
			return {}
		end
		local out = {}
		for _, file in ipairs(files) do
			local name = tostring(file):gsub("\\", "/"):match("([^/]+)$")
			if name then
				table.insert(out, name)
			end
		end
		return out
	end

	-- Clipboard ---------------------------------------------------------------

	local setclipboard = pick(setclipboard, toclipboard, set_clipboard, member(syn, "write_clipboard"), member(Clipboard, "set"))

	Compat.hasClipboard = setclipboard ~= nil

	function Compat.clipboard(text)
		if not setclipboard then
			return false
		end
		return (pcall(setclipboard, tostring(text)))
	end

	-- HTTP ----------------------------------------------------------------------

	local request = pick(request, http_request, member(syn, "request"), member(http, "request"))

	function Compat.httpGet(url)
		local ok, body = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(body) == "string" then
			return body
		end
		if request then
			local okReq, response = pcall(request, { Url = url, Method = "GET" })
			if okReq and type(response) == "table" and type(response.Body) == "string" then
				return response.Body
			end
		end
		return nil
	end

	-- GUI parent ------------------------------------------------------------------

	local gethui = pick(gethui, get_hidden_gui)
	local protect = pick(member(syn, "protect_gui"), protect_gui)

	function Compat.mountGui(gui)
		if protect then
			pcall(protect, gui)
		end
		if gethui then
			local ok, parent = pcall(gethui)
			if ok and typeof(parent) == "Instance" then
				gui.Parent = parent
				return
			end
		end
		local okCore = pcall(function()
			gui.Parent = Compat.service("CoreGui")
		end)
		if okCore and gui.Parent then
			return
		end
		local players = Compat.service("Players")
		local player = players.LocalPlayer
		if player then
			gui.Parent = player:WaitForChild("PlayerGui")
		end
	end

	return Compat
end

__modules["util/Maid"] = function()
	-- Maid: collects connections, instances, objects and functions and cleans
	-- them all at once. Every Robly object owns one, so closing a window leaves
	-- no connections or instances behind (brief, rule 6).

	local Maid = {}
	Maid.__index = Maid

	function Maid.new()
		return setmetatable({ _tasks = {} }, Maid)
	end

	function Maid:Add(item)
		if item ~= nil then
			table.insert(self._tasks, item)
		end
		return item
	end

	local function cleanup(item)
		local kind = typeof(item)
		if kind == "RBXScriptConnection" then
			item:Disconnect()
		elseif kind == "Instance" then
			item:Destroy()
		elseif kind == "function" then
			item()
		elseif kind == "thread" then
			pcall(task.cancel, item)
		elseif kind == "table" then
			if type(item.Destroy) == "function" then
				item:Destroy()
			elseif type(item.Disconnect) == "function" then
				item:Disconnect()
			end
		end
	end

	function Maid:Clean()
		local tasks = self._tasks
		self._tasks = {}
		for index = #tasks, 1, -1 do
			local ok, err = pcall(cleanup, tasks[index])
			if not ok then
				warn("[Robly] cleanup error: " .. tostring(err))
			end
		end
	end

	Maid.Destroy = Maid.Clean

	return Maid
end

__modules["util/Signal"] = function()
	-- Signal: tiny event object used everywhere inside Robly.
	-- Handlers run synchronously; an error in one handler is reported and does
	-- not stop the others.

	local Signal = {}
	Signal.__index = Signal

	local function report(err)
		warn("[Robly] " .. tostring(err) .. "\n" .. debug.traceback())
	end

	function Signal.new()
		return setmetatable({ _handlers = {} }, Signal)
	end

	function Signal:Connect(fn)
		local handlers = self._handlers
		local handler = { fn = fn, connected = true }
		table.insert(handlers, handler)

		local connection = { Connected = true }
		function connection.Disconnect()
			if not handler.connected then
				return
			end
			handler.connected = false
			connection.Connected = false
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end
		return connection
	end

	function Signal:Once(fn)
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end

	function Signal:Fire(...)
		for _, handler in ipairs(table.clone(self._handlers)) do
			if handler.connected then
				xpcall(handler.fn, report, ...)
			end
		end
	end

	function Signal:DisconnectAll()
		for _, handler in ipairs(self._handlers) do
			handler.connected = false
		end
		table.clear(self._handlers)
	end

	Signal.Destroy = Signal.DisconnectAll

	return Signal
end

__modules["util/Util"] = function()
	-- Util: small pure helpers (colors, numbers, tables, UTF-8 case, base64).

	local Util = {}

	-- Colors ---------------------------------------------------------------

	function Util.hex(value)
		if typeof(value) == "Color3" then
			return value
		end
		local s = tostring(value):gsub("#", "")
		if #s == 3 then
			s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
		end
		local r = tonumber(s:sub(1, 2), 16)
		local g = tonumber(s:sub(3, 4), 16)
		local b = tonumber(s:sub(5, 6), 16)
		if not (r and g and b) or #s ~= 6 then
			return nil
		end
		return Color3.fromRGB(r, g, b)
	end

	local function channel(x)
		return math.clamp(math.floor(x * 255 + 0.5), 0, 255)
	end

	function Util.toHex(color)
		return string.format("%02X%02X%02X", channel(color.R), channel(color.G), channel(color.B))
	end

	local function linear(c)
		if c <= 0.03928 then
			return c / 12.92
		end
		return ((c + 0.055) / 1.055) ^ 2.4
	end

	function Util.luminance(color)
		return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
	end

	function Util.contrast(a, b)
		local la, lb = Util.luminance(a), Util.luminance(b)
		if la < lb then
			la, lb = lb, la
		end
		return (la + 0.05) / (lb + 0.05)
	end

	-- Text colour that stays readable on top of an accent colour (brief: dark
	-- accent.ink on bright accents, white on dark ones).
	function Util.inkFor(accent)
		local dark = accent:Lerp(Color3.new(0, 0, 0), 0.9)
		local white = Color3.new(1, 1, 1)
		if Util.contrast(accent, dark) >= Util.contrast(accent, white) then
			return dark
		end
		return white
	end

	function Util.darken(color, amount)
		return color:Lerp(Color3.new(0, 0, 0), amount)
	end

	function Util.lighten(color, amount)
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end

	-- Numbers --------------------------------------------------------------

	function Util.decimals(step)
		if not step or step <= 0 then
			return 0
		end
		local s = string.format("%.6f", step):gsub("0+$", "")
		local dot = s:find("%.")
		if not dot then
			return 0
		end
		return #s - dot
	end

	function Util.snap(value, step, min)
		if not step or step <= 0 then
			return value
		end
		min = min or 0
		local snapped = min + math.floor((value - min) / step + 0.5) * step
		local d = Util.decimals(step)
		return tonumber(string.format("%." .. d .. "f", snapped))
	end

	function Util.formatNumber(value, step)
		if type(value) ~= "number" then
			return tostring(value)
		end
		return string.format("%." .. Util.decimals(step) .. "f", value)
	end

	-- Tables ---------------------------------------------------------------

	function Util.copy(t)
		if type(t) ~= "table" then
			return t
		end
		local out = {}
		for k, v in pairs(t) do
			out[k] = Util.copy(v)
		end
		return out
	end

	function Util.equal(a, b)
		if a == b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for k, v in pairs(a) do
			if not Util.equal(v, b[k]) then
				return false
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	function Util.merge(defaults, options)
		local out = {}
		for k, v in pairs(defaults or {}) do
			out[k] = v
		end
		for k, v in pairs(options or {}) do
			out[k] = v
		end
		return out
	end

	-- UTF-8 case (Latin, Latin-1, Cyrillic) ---------------------------------

	local function mapCase(s, toUpper)
		local ok, result = pcall(function()
			local out = table.create(#s)
			for _, code in utf8.codes(s) do
				if toUpper then
					if (code >= 0x61 and code <= 0x7A) or (code >= 0xE0 and code <= 0xFE and code ~= 0xF7) or (code >= 0x430 and code <= 0x44F) then
						code -= 0x20
					elseif code >= 0x450 and code <= 0x45F then
						code -= 0x50
					end
				else
					if (code >= 0x41 and code <= 0x5A) or (code >= 0xC0 and code <= 0xDE and code ~= 0xD7) or (code >= 0x410 and code <= 0x42F) then
						code += 0x20
					elseif code >= 0x400 and code <= 0x40F then
						code += 0x50
					end
				end
				table.insert(out, utf8.char(code))
			end
			return table.concat(out)
		end)
		if ok then
			return result
		end
		return toUpper and s:upper() or s:lower()
	end

	function Util.upper(s)
		return mapCase(s, true)
	end

	function Util.lower(s)
		return mapCase(s, false)
	end

	function Util.trim(s)
		return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
	end

	function Util.sanitizeFileName(name)
		name = Util.trim(tostring(name or ""))
		name = name:gsub('[\\/:%*%?"<>|]', "_")
		if name == "" then
			name = "default"
		end
		return name:sub(1, 48)
	end

	-- Base64 ---------------------------------------------------------------

	local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local DECODE = {}
	for i = 1, #ALPHABET do
		DECODE[ALPHABET:sub(i, i)] = i - 1
	end

	function Util.base64Encode(data)
		local out = {}
		for i = 1, #data, 3 do
			local a, b, c = data:byte(i, i + 2)
			local n = a * 65536 + (b or 0) * 256 + (c or 0)
			local c1 = bit32.extract(n, 18, 6)
			local c2 = bit32.extract(n, 12, 6)
			local c3 = bit32.extract(n, 6, 6)
			local c4 = bit32.extract(n, 0, 6)
			table.insert(out, ALPHABET:sub(c1 + 1, c1 + 1))
			table.insert(out, ALPHABET:sub(c2 + 1, c2 + 1))
			table.insert(out, b and ALPHABET:sub(c3 + 1, c3 + 1) or "=")
			table.insert(out, c and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
		end
		return table.concat(out)
	end

	function Util.base64Decode(data)
		data = tostring(data):gsub("[^%w%+/=]", "")
		local out = {}
		for i = 1, #data, 4 do
			local chunk = data:sub(i, i + 3)
			local n, pad = 0, 0
			for j = 1, 4 do
				local ch = chunk:sub(j, j)
				local v = DECODE[ch]
				if v == nil then
					v = 0
					pad += 1
				end
				n = n * 64 + v
			end
			local a = bit32.extract(n, 16, 8)
			local b = bit32.extract(n, 8, 8)
			local c = bit32.extract(n, 0, 8)
			table.insert(out, string.char(a))
			if pad < 2 then
				table.insert(out, string.char(b))
			end
			if pad < 1 then
				table.insert(out, string.char(c))
			end
		end
		return table.concat(out)
	end

	return Util
end

return import("init")
