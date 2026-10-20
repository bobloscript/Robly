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
