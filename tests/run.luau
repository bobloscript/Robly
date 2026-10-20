--!nocheck
-- Smoke test: builds the demo window under a simulated Roblox and drives it
-- through every major feature. Run with Lune:  lune run tests/run.luau
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local M = require("./mock")
local task = require("@lune/task")

local Enum = roblox.Enum
local failures = {}
local passed = 0

local function check(name, condition, detail)
	if condition then
		passed += 1
	else
		table.insert(failures, name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local function step(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		table.insert(failures, "step '" .. name .. "' crashed: " .. tostring(err))
	end
	task.wait(0.05)
end

local dist = fs.readFile("dist/robly.lua")
M.sources["dist/robly.lua"] = dist

local Robly
M.env.loadstring = (function(original)
	return function(source, name)
		local fn = original(source, name)
		if source == dist then
			return function()
				Robly = fn()
				return Robly
			end
		end
		return fn
	end
end)(M.env.loadstring)

-- 1. Demo script ------------------------------------------------------------------------
step("load demo", function()
	M.run(fs.readFile("examples/demo.lua"), "demo")
end)
task.wait(0.3)
check("library loaded", Robly ~= nil)
if not Robly then
	print(table.concat(M.errors, "\n"))
	process.exit(1)
end
local window = Robly.Windows[1]
check("window created", window ~= nil)
check("version set", Robly.Version ~= "__VERSION__", Robly.Version)
check("gui mounted in gethui", window.Root.Gui.Parent == M.hidden)
check("detected Roblox language (ru)", window.Loc.Current == "ru", window.Loc.Current)
check("first tab selected", window.Selected and window.Selected.Id ~= nil)

local function control(flag)
	for _, c in ipairs(window.Search.Entries) do
		if c.Flag == flag then
			return c
		end
	end
	return nil
end

local function textOf(root, text)
	return M.find(root, function(node, d)
		return (d.className == "TextLabel" or d.className == "TextButton") and node.Text == text
	end)
end

step("lucide icons", function()
	local icons = M.findAll(window.Root.Gui, function(node)
		return node.Name == "Glyph"
	end)
	check("icons rendered as Lucide sprites", #icons > 10, #icons)
	local glyph = icons[1]
	check("sprite rect", glyph and glyph.ImageRectSize.X == 48 and tostring(glyph.Image):find("^rbxassetid://") ~= nil)
	local missing = {}
	local Lucide = fs.readFile("src/core/LucideData.lua")
	local iconsSource = fs.readFile("src/core/Icons.lua")
	local aliasBlock = iconsSource:match("Icons.Aliases = (%b{})")
	local aliases = {}
	for alias, target in aliasBlock:gmatch('%[?"?([%w_]+)"?%]? = "([%w%-]+)"') do
		aliases[alias] = target
	end
	for alias, target in pairs(aliases) do
		local name = aliases[target] or target
		if not Lucide:find('["' .. name .. '"]', 1, true) then
			table.insert(missing, alias .. "->" .. name)
		end
	end
	check("every alias points to a Lucide icon", #missing == 0, table.concat(missing, ", "))
end)

-- 2. Controls -----------------------------------------------------------------------------
step("toggle", function()
	local toggle = control("autoFarm")
	check("toggle exists", toggle ~= nil)
	M.fire(toggle.Track, "Activated")
	check("toggle on via switch", window.Flags.autoFarm == true)
	M.fire(toggle.Hit, "Activated")
	check("toggle off via row tap", window.Flags.autoFarm == false)
end)

step("checkbox", function()
	local box = control("ignorePlayers")
	M.fire(box.Box, "Activated")
	check("checkbox on", window.Flags.ignorePlayers == true)
end)

step("slider drag", function()
	local slider = control("distance")
	local area = slider.Area
	local pos, size = area.AbsolutePosition, area.AbsoluteSize
	local input = M.input(Enum.UserInputType.MouseButton1, pos.X + size.X * 0.5, pos.Y - 36)
	M.fire(area, "InputBegan", input)
	M.UIS.InputEnded:Fire(input)
	local v = window.Flags.distance
	check("slider value snapped in range", type(v) == "number" and v >= 4 and v <= 30 and v % 1 == 0, v)
	slider:Set(99)
	check("slider clamps", window.Flags.distance == 30, window.Flags.distance)
	check("slider label", slider.ValueLabel.Text == "30 studs", slider.ValueLabel.Text)
end)

step("range slider", function()
	local range = control("mobLevel")
	range:Set({ 900, 100 })
	local v = window.Flags.mobLevel
	check("range sorted", v[1] == 100 and v[2] == 900, v[1] .. "," .. v[2])
end)

step("segmented + EnabledWhen", function()
	local seg = control("mode")
	local boss = control("bossFarm")
	check("boss locked at start", boss.Enabled == false)
	M.fire(seg.Buttons[3], "Activated")
	check("segmented value", window.Flags.mode == "auto", window.Flags.mode)
	check("boss unlocked", boss.Enabled == true)
end)

step("stepper", function()
	local stepper = control("mobs")
	stepper:Set(stepper:Get() + 1)
	check("stepper +1", window.Flags.mobs == 4, window.Flags.mobs)
	stepper:Set(100)
	check("stepper clamps", window.Flags.mobs == 8)
end)

step("dropdown single", function()
	local dropdown = control("weapon")
	M.fire(dropdown.Button, "Activated")
	check("popup opened", window.Popup.Current ~= nil)
	local option = textOf(window.Root.Popups, "Trident")
	check("option rendered", option ~= nil)
	if option then
		M.fire(option.Parent, "Activated")
	end
	check("dropdown value", window.Flags.weapon == "Trident", window.Flags.weapon)
	check("popup closed after pick", window.Popup.Current == nil)
end)

step("dropdown multi + search", function()
	local dropdown = control("weapons")
	M.fire(dropdown.Button, "Activated")
	local box = M.find(window.Root.Popups, function(_, d)
		return d.className == "TextBox"
	end)
	check("search box in list", box ~= nil)
	box.Text = "baz"
	local option = textOf(window.Root.Popups, "Bazooka")
	M.fire(option.Parent, "Activated")
	local v = window.Flags.weapons
	check("multi added", table.find(v, "Bazooka") ~= nil and #v == 3, #v)
	check("count badge", dropdown.CountBadge.Text == "3" and dropdown.CountBadge.Visible)
	window.Popup:Close()
end)

step("dropdown SetOptions", function()
	local dropdown = control("weapon")
	dropdown:SetOptions({ "A", "B" })
	check("value reset to first valid", window.Flags.weapon == "A", window.Flags.weapon)
end)

step("input numeric", function()
	local input = control("radius")
	input.Box:CaptureFocus()
	input.Box.Text = "abc"
	input.Box:ReleaseFocus()
	check("invalid numeric reverts", window.Flags.radius == 150, window.Flags.radius)
	input.Box:CaptureFocus()
	input.Box.Text = "42,5"
	input.Box:ReleaseFocus()
	check("numeric parsed", window.Flags.radius == 42.5, window.Flags.radius)
end)

step("visible when", function()
	local color = control("espColor")
	check("hidden until esp on", color.Visible == false)
	window.Flags.esp = true
	check("shown when esp on", color.Visible == true)
end)

step("color picker", function()
	local picker = control("espColor")
	picker:Set("#00FF00")
	check("hex parsed", picker.HexLabel.Text == "#00FF00", picker.HexLabel.Text)
	local ok = pcall(function()
		picker:Open()
	end)
	check("color popup opens", ok and window.Popup.Current ~= nil)
	local square = M.find(window.Root.Popups, function(node)
		return node.Name == "SV"
	end)
	if square then
		local p, s = square.AbsolutePosition, square.AbsoluteSize
		local click = M.input(Enum.UserInputType.MouseButton1, p.X + s.X * 0.25, p.Y + s.Y * 0.25)
		M.fire(square, "InputBegan", click)
		M.UIS.InputEnded:Fire(click)
		local knob
		for _, child in ipairs(square:GetChildren()) do
			if child:IsA("GuiObject") and child.ZIndex == 3 then
				knob = child
			end
		end
		local kp = knob.Position
		check("color knob under the cursor", math.abs(kp.X.Scale - 0.25) < 0.01 and math.abs(kp.Y.Scale - 0.25) < 0.01, kp.X.Scale .. "," .. kp.Y.Scale)
	end
	window.Popup:Close()
end)

-- 3. Keybinds ------------------------------------------------------------------------------
step("keybind toggle target", function()
	window.Flags.autoFarm = false
	M.press(Enum.KeyCode.F)
	check("F toggles autoFarm", window.Flags.autoFarm == true)
	M.press(Enum.KeyCode.F)
	check("F toggles back", window.Flags.autoFarm == false)
end)

step("keybind modifiers", function()
	window.Flags.autoFarm = true
	M.press(Enum.KeyCode.X)
	check("X alone does nothing", window.Flags.autoFarm == true)
	M.press(Enum.KeyCode.X, { Enum.KeyCode.LeftControl })
	task.wait(0.05)
	check("Ctrl+X stops", window.Flags.autoFarm == false)
end)

step("bind paused while typing", function()
	local input = control("target")
	input.Box:CaptureFocus()
	M.press(Enum.KeyCode.F)
	check("no bind while typing", window.Flags.autoFarm == false)
	input.Box:ReleaseFocus()
end)

step("keybind capture + game conflict dialog", function()
	local bind = control("questKey")
	M.fire(bind.Chip, "Activated")
	check("capturing", window.Binds.Capturing ~= nil)
	M.press(Enum.KeyCode.W)
	task.wait(0.05)
	check("conflict dialog shown", window.Dialogs.Current ~= nil)
	local take = textOf(window.Root.Modal, window.Loc:Lib("take_key"))
	check("take button", take ~= nil)
	if take then
		M.fire(take, "Activated")
	end
	task.wait(0.05)
	local v = window.Flags.questKey
	check("override saved", v.Key == "W" and v.Override == true, v.Key)
	check("CAS bound", next(M.actions) ~= nil)
end)

step("keybind bind conflict", function()
	local bind = control("questKey")
	local before = window.Flags.autoFarm
	M.fire(bind.Chip, "Activated")
	M.press(Enum.KeyCode.F)
	check("captured key does not fire the existing F bind", window.Flags.autoFarm == before)
	task.wait(0.05)
	check("bind conflict dialog", window.Dialogs.Current ~= nil)
	window.Dialogs:Close()
	task.wait(0.05)
end)

step("window toggle key", function()
	M.press(Enum.KeyCode.RightShift)
	task.wait(0.05)
	check("RightShift minimises", window.Minimized == true)
	M.press(Enum.KeyCode.RightShift)
	task.wait(0.05)
	check("RightShift restores", window.Minimized == false)
end)

step("window drag + layout parts", function()
	check("frame itself has no list layout", window.Frame:FindFirstChildOfClass("UIListLayout") == nil)
	check("resize grip floats in frame", window.Frame:FindFirstChild("Resize") ~= nil)
	local handle = window.DragHandle
	check("drag handle is a button", handle and handle:IsA("GuiButton"))
	local before = window.Frame.Position
	local start = M.input(Enum.UserInputType.MouseButton1, 400, 100)
	M.fire(handle, "InputBegan", start)
	M.UIS.InputChanged:Fire(M.input(Enum.UserInputType.MouseMovement, 440, 140))
	M.UIS.InputChanged:Fire(M.input(Enum.UserInputType.MouseMovement, 460, 160))
	M.UIS.InputEnded:Fire(start)
	check("window moved by header drag", window.Frame.Position ~= before, tostring(window.Frame.Position))
	window.Frame.Position = before
	local src = fs.readFile("src/core/Theme.lua") .. fs.readFile("src/core/Localization.lua")
	check("bindings are not weak tables", src:find('__mode = "k"', 1, true) == nil)
end)

step("drag follows the pointer and reaches the bottom edge", function()
	local frame = window.Frame
	local handle = window.DragHandle
	local before = frame.Position
	local function drag(fromY, toY)
		local start = M.input(Enum.UserInputType.MouseButton1, 500, fromY)
		M.fire(handle, "InputBegan", start)
		M.UIS.InputChanged:Fire(M.input(Enum.UserInputType.MouseMovement, 500, fromY + 10))
		M.UIS.InputChanged:Fire(M.input(Enum.UserInputType.MouseMovement, 500, toY))
		M.UIS.InputEnded:Fire(start)
	end
	local y0 = frame.Position.Y.Offset
	drag(100, 150)
	check("moves exactly with the pointer", frame.Position.Y.Offset == y0 + 50, frame.Position.Y.Offset - y0)
	drag(100, 3000)
	local bottom = 1080 - frame.AbsoluteSize.Y
	check("reaches the bottom edge", frame.Position.Y.Offset == bottom, frame.Position.Y.Offset .. " vs " .. bottom)
	drag(500, -3000)
	check("stops under the top bar", frame.Position.Y.Offset == 36, frame.Position.Y.Offset)
	frame.Position = before
end)

-- 4. Search, tabs, detach -----------------------------------------------------------------
step("search", function()
	window.Search:SetQuery("фарм")
	local results = window.Search:Find("фарм")
	check("search finds Russian", #results >= 3, #results)
	check("search by english text", #window.Search:Find("auto farm") >= 1)
	check("search by key", #window.Search:Find("farm.auto") >= 1)
	window:Reveal(control("chestFarm"))
	task.wait(0.05)
	check("reveal expands section", control("chestFarm").Section.Collapsed == false)
	check("search cleared", window.Search.Overlay.Visible == false)
end)

step("detach and attach", function()
	local farm = control("autoFarm").Tab
	farm:Detach()
	task.wait(0.1)
	check("detached", farm.DetachedWindow ~= nil)
	window:SelectTab(farm)
	check("placeholder shown", window.Placeholder and window.Placeholder.Frame.Visible)
	window.Flags.autoFarm = true
	check("value shared", control("autoFarm").Track.BackgroundColor3 == window.Library.Themes.RobScript.accent)
	local detached = farm.DetachedWindow
	local handle = M.find(detached.Frame, function(node)
		return node.Name == "DragHandle"
	end)
	local start = M.input(Enum.UserInputType.MouseButton1, 900, 300)
	M.fire(handle, "InputBegan", start)
	M.UIS.InputChanged:Fire(M.input(Enum.UserInputType.MouseMovement, 910, 310))
	M.UIS.InputChanged:Fire(M.input(Enum.UserInputType.MouseMovement, 5000, -4000))
	M.UIS.InputEnded:Fire(start)
	local dp = detached.Frame.Position
	check("detached window stays on screen", dp.Y.Offset >= 36 and dp.X.Offset + detached.Frame.AbsoluteSize.X <= 1920, tostring(dp))
	farm:Attach()
	task.wait(0.4)
	check("attached", farm.DetachedWindow == nil and farm.Page.Parent == window.PageHost)
	check("page visible after attach", farm.Page.Visible == true)
end)

-- 5. Theme, language, animations ----------------------------------------------------------
step("theme", function()
	window:SetTheme("Light")
	check("light bg applied", window.Frame.BackgroundColor3 == Robly.Themes.Light.bg)
	local exported = (function()
		local settings = window.SettingsTab
		return settings ~= nil
	end)()
	check("settings tab exists", exported)
	window:SetTheme("RobScript")
end)

step("theme export/import", function()
	local exportButton = textOf(window.SettingsTab.Tab.Page, window.Loc:Lib("export"))
	check("export button", exportButton ~= nil)
	M.fire(exportButton.Parent, "Activated")
	task.wait(0.05)
	check("clipboard has theme", type(M.clipboard) == "string" and M.clipboard:find("^robly1:") ~= nil, M.clipboard)
end)

step("language switch", function()
	window:SetLanguage("en")
	check("en active", window.Loc.Current == "en")
	local farmTitle = control("autoFarm").TitleLabel.Text
	check("control title translated", farmTitle == "Auto farm level", farmTitle)
	local navLabel = textOf(window.Nav, "Farm")
	check("nav translated", navLabel ~= nil)
	window:SetLanguage("ru")
	check("back to ru", control("autoFarm").TitleLabel.Text == "Авто-фарм уровня")
	check("plural ru", window.Loc:Get("farm.killed", { count = 3 }) == "Убито 3 моба", window.Loc:Get("farm.killed", { count = 3 }))
	check("plural ru many", window.Loc:Get("farm.killed", { count = 11 }) == "Убито 11 мобов")
end)

step("minimise during restore keeps the home position", function()
	local home = window.Frame.Position
	window:Minimize()
	window:Restore()
	window:Minimize()
	window:Restore()
	task.wait(0.05)
	check("position unchanged", window.Frame.Position == home, tostring(window.Frame.Position) .. " vs " .. tostring(home))
end)

step("animations off", function()
	window:SetAnimations("Off")
	window:Minimize()
	check("minimised", window.Frame.Visible == false)
	window:Restore()
	check("restored", window.Frame.Visible == true)
	window:SetAnimations("Full")
end)

-- 6. Devices -------------------------------------------------------------------------------
step("phone layout", function()
	M.setViewport(844, 390)
	task.wait(0.25) -- let the real (debounced) device detection fire first
	window:_onDevice("phone")
	task.wait(0.05)
	check("rail built", M.find(window.Nav, function(node)
		return node.Name == "Rail"
	end) ~= nil)
	check("touch sizes", Robly.Themes ~= nil and window.Mode == "phone")
	local more = M.find(window.Nav, function(node)
		return node.Name == "More"
	end)
	M.fire(more, "Activated")
	check("more menu", window.Popup.Current ~= nil)
	window.Popup:Close()
	window:_onDevice("tablet")
	task.wait(0.05)
	check("tab bar built", M.find(window.Nav, function(node)
		return node.Name == "TabBar"
	end) ~= nil)
	M.setViewport(1920, 1080)
	task.wait(0.25)
	window:_onDevice("pc")
	task.wait(0.05)
	check("sidebar back", M.find(window.Nav, function(node)
		return node.Name == "Sidebar"
	end) ~= nil)
end)

-- 7. Configs -------------------------------------------------------------------------------
step("configs", function()
	window.Flags.walkSpeed = 77
	window:SaveConfig("PvP")
	local path = "Robly/RobScriptHub/profiles/PvP.json"
	check("profile written", M.files[path] ~= nil)
	window.Flags.walkSpeed = 20
	window:LoadConfig("PvP")
	check("profile loaded", window.Flags.walkSpeed == 77, window.Flags.walkSpeed)
	window.Config:Flush()
	check("meta written", M.files["Robly/RobScriptHub/robly.json"] ~= nil)
	local meta = M.files["Robly/RobScriptHub/robly.json"]
	check("meta has theme + language", meta:find('"language"') ~= nil and meta:find('"theme"') ~= nil)
end)

step("unknown saved values survive a save", function()
	local path = "Robly/RobScriptHub/profiles/PvP.json"
	local data = require("@lune/serde").decode("json", M.files[path])
	data.values["later:flag"] = 5
	M.files[path] = require("@lune/serde").encode("json", data)
	window:LoadConfig("PvP")
	window:SaveConfig("PvP")
	local again = require("@lune/serde").decode("json", M.files[path])
	check("unregistered flag kept", again.values["later:flag"] == 5)
end)

step("notifications + dialog", function()
	local toast = window:Notify({ Title = "Hi", Content = "There", Type = "success", Duration = 0.1 })
	check("toast handle", toast ~= nil)
	local dialog = window:Dialog({ Title = "Q", Input = { Default = "x" }, Buttons = { { Text = "OK" } } })
	check("dialog handle", dialog ~= nil)
	dialog.Close()
end)

step("code copy", function()
	local code = M.find(window.PageHost, function(node, d)
		return d.className == "TextLabel" and node.Text:find("loadstring") ~= nil
	end)
	check("code rendered", code ~= nil)
end)

-- 8. Reload: values restored from disk ------------------------------------------------------
step("destroy", function()
	window:Destroy()
	task.wait(0.1)
	check("gui removed", window.Root.Gui.Parent == nil)
	check("window list empty", #Robly.Windows == 0)
end)

step("reload restores config", function()
	M.run(fs.readFile("examples/demo.lua"), "demo2")
	task.wait(0.3)
	local second = Robly.Windows[1]
	check("second window", second ~= nil)
	check("walkSpeed restored", second and second.Flags.walkSpeed == 77, second and second.Flags.walkSpeed)
	check("keybind restored", second and second.Flags.questKey and second.Flags.questKey.Key == "W")
	if second then
		second:Destroy()
	end
end)

-- 9. Phone from scratch ----------------------------------------------------------------------
step("phone window", function()
	M.setTouch(true)
	M.setViewport(844, 390)
	M.run(fs.readFile("examples/demo.lua"), "demo-phone")
	task.wait(0.3)
	local phone = Robly.Windows[1]
	check("phone mode", phone and phone.Mode == "phone", phone and phone.Mode)
	check("rail", M.find(phone.Nav, function(node)
		return node.Name == "Rail"
	end) ~= nil)
	check("window under top bar", phone.Frame.Position.Y.Offset >= 36)
	local quick = phone.QuickButtons
	check("quick buttons visible", quick.Holder.Visible == true)
	check("quick buttons count", #quick.Buttons >= 2, #quick.Buttons)
	local first = quick.Buttons[1]
	local before = first.control:QuickState()
	M.fire(first.button, "Activated")
	check("quick button acts", first.control:QuickState() ~= before or before == "action")
	-- long press a rail tab → menu → detach (max 2 on phones)
	local farmButton = M.find(phone.Nav, function(node)
		return node.Name == phone.Tabs[2].Id
	end)
	check("rail tab button", farmButton ~= nil)
	if farmButton then
		M.fire(farmButton, "InputBegan", M.input(roblox.Enum.UserInputType.Touch, 10, 10))
		task.wait(0.6)
		check("long-press menu", phone.Popup.Current ~= nil)
		phone.Popup:Close()
	end
	for _, tab in ipairs(phone.Tabs) do
		tab:Detach()
	end
	task.wait(0.1)
	check("phone detach limit 2", phone:DetachedCount() == 2, phone:DetachedCount())
	phone:Destroy()
	M.setTouch(false)
	M.setViewport(1920, 1080)
end)

-- 10. Load: 150 controls ---------------------------------------------------------------------
step("150 controls", function()
	local start = os.clock()
	local big = Robly:CreateWindow({ Title = "Stress", Folder = "Stress" })
	for t = 1, 5 do
		local tab = big:Tab({ Title = "Tab " .. t, Icon = "star" })
		for s2 = 1, 3 do
			local section = tab:Section({ Title = "Section " .. s2 })
			for i = 1, 10 do
				if i % 3 == 0 then
					section:Slider({ Title = "Slider " .. t .. s2 .. i, Min = 0, Max = 100 })
				elseif i % 3 == 1 then
					section:Toggle({ Title = "Toggle " .. t .. s2 .. i })
				else
					section:Dropdown({ Title = "Drop " .. t .. s2 .. i, Options = { "a", "b", "c" } })
				end
			end
		end
	end
	local elapsed = os.clock() - start
	local extra = big.Tabs[1]:Section({ Title = "Edge cases" })
	local inverted = extra:Slider({ Title = "Inverted", Min = 10, Max = 0, Default = 5 })
	check("inverted slider range", inverted:Get() == 5)
	local fired = false
	extra:Keybind({ Title = "Locked bind", Default = "J", EnabledWhen = function()
		return false
	end, Callback = function()
		fired = true
	end })
	M.press(Enum.KeyCode.J)
	task.wait(0.05)
	check("disabled bind does not fire", fired == false)
	check("150 controls built", #big.Search.Entries >= 150, #big.Search.Entries)
	print(string.format("150 controls built in %.2fs (mock)", elapsed))
	local themeStart = os.clock()
	big:SetTheme("Midnight")
	print(string.format("theme switch over all bindings: %.3fs (mock)", os.clock() - themeStart))
	big:Destroy()
end)

task.wait(0.5)

-- Report ---------------------------------------------------------------------------------------
local robWarnings = {}
for _, w in ipairs(M.warnings) do
	table.insert(robWarnings, w)
end
print(string.format("checks passed: %d, failed: %d, runtime errors: %d, warnings: %d, instances: %d", passed, #failures, #M.errors, #robWarnings, M.instances))
for _, f in ipairs(failures) do
	print("FAIL  " .. f)
end
for _, e in ipairs(M.errors) do
	print("ERROR " .. e)
end
for _, w in ipairs(robWarnings) do
	print("WARN  " .. w:sub(1, 300))
end
if #failures > 0 or #M.errors > 0 then
	process.exit(1)
end

process.exit(0)
