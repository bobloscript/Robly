-- Robly demo: the "RobScript Hub" window from the design mockup.
-- Run in any executor:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/bobloscript/Robly/main/examples/demo.lua"))()

local Robly = loadstring(game:HttpGet("https://raw.githubusercontent.com/bobloscript/Robly/main/dist/robly.lua"))()

local Window = Robly:CreateWindow({
	Title = "RobScript Hub",
	Subtitle = "Blox Fruits · v2.4",
	Logo = "R",
	Folder = "RobScriptHub",
	ToggleKey = "RightShift",
	Language = {
		Default = "en",
		Available = { "en", "ru" },
		Strings = {
			en = {
				["tab.home"] = "Home", ["tab.farm"] = "Farm", ["tab.combat"] = "Combat",
				["tab.teleport"] = "Teleports", ["tab.visual"] = "Visuals", ["tab.player"] = "Player",
				["farm.desc"] = "Level, chests and weapon mastery",
				["farm.auto"] = "Auto farm level", ["farm.auto.desc"] = "Takes a quest and hits the nearest mobs",
				["farm.weapon"] = "Weapon", ["farm.distance"] = "Attack distance", ["farm.mode"] = "Mode",
				["farm.mobs"] = "Mobs at once", ["farm.killed"] = "Killed {count} {count|mob|mobs}",
			},
			ru = {
				["tab.home"] = "Главная", ["tab.farm"] = "Фарм", ["tab.combat"] = "Бой",
				["tab.teleport"] = "Телепорты", ["tab.visual"] = "Визуал", ["tab.player"] = "Игрок",
				["farm.desc"] = "Уровень, сундуки и мастерство оружия",
				["farm.auto"] = "Авто-фарм уровня", ["farm.auto.desc"] = "Берёт квест и бьёт ближайших мобов",
				["farm.weapon"] = "Оружие", ["farm.distance"] = "Дистанция атаки", ["farm.mode"] = "Режим",
				["farm.mobs"] = "Мобов за раз", ["farm.killed"] = "Убито {count} {count|моб|моба|мобов}",
			},
		},
	},
})

-- Home ---------------------------------------------------------------------------
local Home = Window:Tab({ Title = "tab.home", Icon = "home", Category = { en = "Main", ru = "Главное" } })
local status = Home:Section({ Title = { en = "Status", ru = "Статус" }, Icon = "activity" })
status:Paragraph({
	Title = { en = "Farm status", ru = "Статус фарма" },
	Content = {
		en = "The script takes a quest for your level and changes island when mobs run out.",
		ru = "Скрипт берёт квест под ваш уровень и меняет остров, когда мобы заканчиваются.",
	},
})
status:Badge({ Title = { en = "Build", ru = "Сборка" }, Text = { en = "Works", ru = "Работает" }, Variant = "success" })
local progress = status:ProgressBar({ Title = { en = "Up to level 1500", ru = "До 1500 уровня" }, Value = 68 })
status:Code({ Title = "Luau", Code = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/bobloscript/Robly/main/dist/robly.lua"))()' })

-- Farm -----------------------------------------------------------------------------
local Farm = Window:Tab({ Title = "tab.farm", Description = "farm.desc", Icon = "leaf", Badge = "12", Category = { en = "Game", ru = "Игра" } })

local auto = Farm:Section({
	Title = { en = "Auto farm", ru = "Автофарм" },
	Icon = "leaf",
	Description = { en = "Quests, mobs and islands", ru = "Квесты, мобы и острова" },
})
auto:Toggle({
	Title = "farm.auto",
	Description = "farm.auto.desc",
	Flag = "autoFarm",
	Default = false,
	QuickButton = true,
	Icon = "leaf",
	Callback = function(on)
		print("Auto farm:", on)
	end,
})
auto:Dropdown({
	Title = "farm.weapon",
	Flag = "weapon",
	Options = { "Katana", "Trident", "Dual blade", "Bazooka", "Fists" },
	Default = "Katana",
})
auto:Slider({ Title = "farm.distance", Flag = "distance", Min = 4, Max = 30, Step = 1, Default = 12, Suffix = "studs" })
auto:Segmented({
	Title = "farm.mode",
	Flag = "mode",
	Options = {
		{ Value = "melee", Text = { en = "Melee", ru = "Ближний" } },
		{ Value = "ranged", Text = { en = "Ranged", ru = "Дальний" } },
		{ Value = "auto", Text = { en = "Auto", ru = "Авто" } },
	},
	Default = "melee",
})
auto:Stepper({ Title = "farm.mobs", Flag = "mobs", Min = 1, Max = 8, Default = 3 })
auto:Header({ en = "Attack", ru = "Атака" })
auto:Toggle({ Title = { en = "Fast attack", ru = "Быстрая атака" }, Flag = "fastAttack", Icon = "zap" })
-- Parent: indented under "Fast attack" and shown only while it is on
auto:Slider({ Title = { en = "Attack speed", ru = "Скорость атаки" }, Flag = "attackSpeed", Parent = "fastAttack", Min = 1, Max = 10, Default = 5 })
auto:Checkbox({ Title = { en = "Skip animations", ru = "Пропускать анимации" }, Flag = "skipAnims", Parent = "fastAttack" })

local chests = Farm:Section({ Title = { en = "Chests", ru = "Сундуки" }, Icon = "box", Collapsed = true })
chests:Toggle({ Title = { en = "Chest farm", ru = "Фарм сундуков" }, Flag = "chestFarm", QuickButton = true, Icon = "box" })
chests:Toggle({ Title = { en = "Server hop when empty", ru = "Сервер-хоп, если пусто" }, Flag = "serverHop", Default = true })
chests:Checkbox({ Title = { en = "Collect fruits", ru = "Собирать фрукты" }, Flag = "collectFruits", Default = true })
chests:Checkbox({ Title = { en = "Ignore players", ru = "Игнорировать игроков" }, Flag = "ignorePlayers" })

local bosses = Farm:Section({ Title = { en = "Bosses", ru = "Боссы" }, Icon = "skull" })
bosses:Toggle({
	Title = { en = "Boss farm", ru = "Фарм боссов" },
	Flag = "bossFarm",
	EnabledWhen = { Flag = "mode", Equals = "auto" },
	DisabledText = { en = "Switch “Mode: Auto” on to unlock", ru = "Включите «Режим: Авто», чтобы открыть" },
})
bosses:Slider({ Title = { en = "Mob level", ru = "Уровень мобов" }, Flag = "mobLevel", Range = true, Min = 0, Max = 1000, Step = 50, Default = { 200, 750 } })

-- Combat ---------------------------------------------------------------------------
local Combat = Window:Tab({ Title = "tab.combat", Icon = "swords", Category = { en = "Game", ru = "Игра" } })
local PvE = Combat:SubTab({ Title = "PvE", Icon = "skull" })
local PvP = Combat:SubTab({ Title = "PvP", Icon = "crosshair" })
local aim = PvP:AddLeftGroupbox({ Title = { en = "Aim", ru = "Прицел" }, Icon = "crosshair" })
aim:CreateToggle({ Title = "Silent Aim", Flag = "silentAim" })
aim:CreateSlider({ Title = "FOV", Flag = "fov", Min = 30, Max = 360, Default = 180 })
local pvpVisual = PvP:AddRightGroupbox({ Title = "ESP", Icon = "eye" })
pvpVisual:CreateToggle({ Title = { en = "Boxes", ru = "Боксы" }, Flag = "pvpBoxes" })
pvpVisual:CreateColorPicker({ Title = { en = "Colour", ru = "Цвет" }, Flag = "pvpColor", Default = "#4C8DFF" })
local weapons = PvE:Section({ Title = { en = "Weapons", ru = "Оружие" }, Icon = "sword" })
weapons:Dropdown({
	Title = { en = "Weapons", ru = "Оружие" },
	Flag = "weapons",
	Multi = true,
	Search = true,
	Options = { "Katana", "Trident", "Dual blade", "Bazooka", "Fists" },
	Default = { "Katana", "Dual blade" },
})
weapons:Toggle({ Title = { en = "Mastery farm", ru = "Фарм мастерства" }, Flag = "masteryFarm" })
weapons:Keybind({
	Title = { en = "Auto farm key", ru = "Клавиша автофарма" },
	Flag = "autoFarmKey",
	Default = "F",
	Mode = "Toggle",
	Target = "autoFarm",
})
weapons:Keybind({
	Title = { en = "Teleport to quest", ru = "Телепорт к квесту" },
	Flag = "questKey",
	Default = "Q",
	Cooldown = 3,
	QuickButton = true,
	Icon = "pin",
	Callback = function()
		Window:Notify({ Title = { en = "Teleporting…", ru = "Телепорт…" }, Type = "info", Duration = 2 })
	end,
})
weapons:Keybind({
	Title = { en = "Stop everything", ru = "Остановить всё" },
	Flag = "stopKey",
	Default = "Ctrl+X",
	Callback = function()
		Window.Flags.autoFarm = false
		Window.Flags.chestFarm = false
	end,
})

-- Teleports --------------------------------------------------------------------------
local Teleports = Window:Tab({ Title = "tab.teleport", Icon = "pin", Category = { en = "World", ru = "Мир" } })
local islands = Teleports:Section({ Title = { en = "Islands", ru = "Острова" }, Icon = "map" })
for _, island in ipairs({ "Starter Island", "Jungle", "Desert", "Snow Mountain", "Sky Island" }) do
	islands:Button({
		Title = island,
		Icon = "pin",
		Callback = function()
			Window:Notify({
				Title = { en = "Teleport to island", ru = "Телепорт на остров" },
				Content = island,
				Action = { Text = { en = "Undo", ru = "Отменить" }, Callback = function() end },
			})
		end,
	})
end

-- Visuals ------------------------------------------------------------------------------
local Visual = Window:Tab({ Title = "tab.visual", Icon = "eye", Category = { en = "World", ru = "Мир" } })
local esp = Visual:Section({ Title = "ESP", Icon = "eye" })
esp:Toggle({ Title = { en = "Player ESP", ru = "ESP игроков" }, Flag = "esp" })
esp:ColorPicker({ Title = { en = "ESP colour", ru = "Цвет ESP" }, Flag = "espColor", Default = "#FF3B7F", VisibleWhen = { Flag = "esp" } })
esp:Slider({ Title = { en = "Max distance", ru = "Макс. дистанция" }, Flag = "espDistance", Min = 100, Max = 5000, Step = 100, Default = 1500, VisibleWhen = { Flag = "esp" } })

-- Player -------------------------------------------------------------------------------
local Player = Window:Tab({ Title = "tab.player", Icon = "user", Category = { en = "World", ru = "Мир" } })
local movement = Player:Section({ Title = { en = "Movement", ru = "Движение" }, Icon = "footprints" })
movement:Slider({ Title = { en = "Walk speed", ru = "Скорость" }, Flag = "walkSpeed", Min = 16, Max = 120, Default = 48 })
movement:Input({ Title = { en = "Player name", ru = "Ник игрока" }, Flag = "target", Placeholder = { en = "For example, Builderman", ru = "Например, Builderman" } })
movement:Input({ Title = { en = "Radius", ru = "Радиус" }, Flag = "radius", Numeric = true, Default = 150, Suffix = "studs" })
movement:Textarea({ Title = { en = "Chat message", ru = "Сообщение в чат" }, Flag = "chatMessage", Placeholder = { en = "Text sent after a raid", ru = "Текст, который скрипт отправит после рейда" } })
movement:Buttons({
	{ Title = { en = "Reset", ru = "Сбросить" }, Variant = "Secondary", Callback = function() Window.Flags.walkSpeed = 16 end },
	{ Title = { en = "Rejoin", ru = "Перезайти" }, Variant = "Danger", Confirm = { Title = { en = "Rejoin the server?", ru = "Перезайти на сервер?" } }, Callback = function() end },
})

-- Show off: progress grows over time
task.spawn(function()
	local value = 68
	while progress and not Window.Destroyed do
		task.wait(3)
		value = (value + 1) % 101
		progress:SetValue(value)
	end
end)
