# Robly — UI-библиотека RobScript

Публичная UI-библиотека для Roblox-скриптов (Luau) под брендом [RobScript](https://robscript.com).
Ощущение «как первые айфоны»: тактильно, просто, аккуратно. Работает на всех экзекуторах, включая слабые (Xeno, Solara, мобильные).

Полный справочник API — в [README.md](../README.md) (на английском). Ниже — главное по-русски.

## Подключение

```lua
local Robly = loadstring(game:HttpGet("https://raw.githubusercontent.com/bobloscript/Robly/main/dist/robly.lua"))()

local Window = Robly:CreateWindow({
	Title = "RobScript Hub",
	Subtitle = "Blox Fruits · v2.4",
	Folder = "RobScriptHub",       -- папка конфигов: workspace/Robly/RobScriptHub/
	ToggleKey = "RightShift",
})

local Farm = Window:Tab({ Title = "Фарм", Icon = "leaf", Description = "Уровень, сундуки и мастерство оружия" })
local Auto = Farm:Section({ Title = "Автофарм" })

Auto:Toggle({
	Title = "Авто-фарм уровня",
	Description = "Берёт квест и бьёт ближайших мобов",
	Flag = "autoFarm",
	QuickButton = true,
	Callback = function(on) print(on) end,
})
Auto:Slider({ Title = "Дистанция атаки", Flag = "distance", Min = 4, Max = 30, Default = 12, Suffix = "studs" })
Auto:Segmented({ Title = "Режим", Flag = "mode", Options = { "Ближний", "Дальний", "Авто" } })
```

Полный пример — [`examples/demo.lua`](../examples/demo.lua) (окно из макета).

## Что внутри

- **Навигация.** ПК — боковая панель; телефон (альбомный) — колонка иконок 56 px, шапка 44 px и меню «Ещё»; планшет (портретный) — нижний таб-бар. Один код, разные токены размеров. Зоны нажатия на тач-устройствах ≥ 44×44.
- **Поиск по функциям** на всех платформах: ищет на текущем языке, на языке по умолчанию и по ключу — находится и «farm», и «фарм». Нажатие ведёт к контролу и подсвечивает его.
- **Вкладку можно вынести в отдельное окно** и вернуть: ПК — перетащить из боковой панели / обратно на неё или кнопка «картинка в картинке»; телефон — долгое нажатие (не больше 2 окон). Значения общие, ничего не сбрасывается.
- **Темы** — таблицы семантических токенов: RobScript (по умолчанию), Светлая, Графит, Полночь. Редактор прямо в «Настройках», экспорт/импорт строкой `robly1:…`, смена без пересоздания окна.
- **Конфиги:** профили, автосохранение, автозагрузка. Нет файловой системы — работает в памяти и показывает уведомление.
- **Языки скрипта:** автор задаёт языки и переводы, игрок переключает на лету кнопкой с глобусом в шапке. Тексты самой библиотеки уже переведены на en / ru / es / pt / de / fr.
- **Бинды** с проверкой конфликтов с игрой, панель биндов на ПК, быстрые кнопки на телефоне.
- **Анимации** «Полные / Мягкие / Выкл».
- **Иконки Lucide** (1500+, любое имя с lucide.dev/icons): спрайты загружены в Roblox, грузятся на любом экзекуторе, цвет берётся из темы. Тени — обводка 1 px.

## Языки

```lua
Robly:CreateWindow({
	Title = "My Hub",
	Language = {
		Default = "en",
		Available = { "en", "ru" },
		Strings = {
			en = { ["farm.auto"] = "Auto farm", ["farm.killed"] = "Killed {count} {count|mob|mobs}" },
			ru = { ["farm.auto"] = "Автофарм", ["farm.killed"] = "Убито {count} {count|моб|моба|мобов}" },
		},
	},
})

Section:Toggle({ Title = "farm.auto" })                                  -- ключ
Section:Toggle({ Title = { en = "Chest farm", ru = "Фарм сундуков" } })  -- прямо в контроле
Section:Toggle({ Title = "Server hop" })                                 -- обычная строка, не переводится
```

Нет перевода — показывается язык по умолчанию (с `Dev = true` — ещё и предупреждение в консоли). Если язык один, кнопка и пункт «Язык» не показываются.

## Условия

```lua
Section:Toggle({
	Title = "Фарм боссов",
	EnabledWhen = { Flag = "mode", Equals = "Авто" },
	DisabledText = "Включите «Режим: Авто», чтобы открыть",
})
Section:ColorPicker({ Title = "Цвет ESP", VisibleWhen = { Flag = "esp" } })
```

## Значения

Все значения живут в одном хранилище: `Window.Flags.autoFarm` (чтение и запись), `Window:OnFlagChanged("autoFarm", fn)`. Конфиги, отдельные окна, панель биндов и быстрые кнопки работают с ним же.

## Сборка

Исходники — модули в `src/`, сборка в один файл `dist/robly.lua`:

```sh
python3 tools/build.py
lune run tests/run.luau   # прогон в симуляции Roblox
```

## Лицензия

[The Unlicense](../LICENSE) — общественное достояние: делайте что хотите, даже без указания автора.

Иконки Lucide — © Lucide Contributors (ISC), карта спрайтов для Roblox — latte-soft/lucide-roblox (MIT).
