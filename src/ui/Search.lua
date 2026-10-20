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
