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
