# Robly

**UI library for Roblox scripts by [RobScript](https://robscript.com).**
Tactile, simple and polished — "like the first iPhones", not skeuomorphic.
Works on every executor, including weak ones (Xeno, Solara, mobile).

[Русская версия →](docs/README.ru.md)

```lua
local Robly = loadstring(game:HttpGet("https://raw.githubusercontent.com/bobloscript/Robly/main/dist/robly.lua"))()

local Window = Robly:CreateWindow({
	Title = "My Hub",
	Subtitle = "Blox Fruits · v1.0",
	Folder = "MyHub",              -- configs: workspace/Robly/MyHub/
})

local Farm = Window:Tab({ Title = "Farm", Icon = "leaf" })
local Auto = Farm:Section({ Title = "Auto farm" })

Auto:Toggle({
	Title = "Auto farm level",
	Description = "Takes a quest and hits the nearest mobs",
	Flag = "autoFarm",
	Callback = function(on)
		print("auto farm", on)
	end,
})
Auto:Slider({ Title = "Attack distance", Flag = "distance", Min = 4, Max = 30, Default = 12, Suffix = "studs" })
Auto:Dropdown({ Title = "Weapon", Flag = "weapon", Options = { "Katana", "Trident", "Bazooka" } })
```

A full showcase lives in [`examples/demo.lua`](examples/demo.lua).

## What you get

- **Navigation first.** PC: sidebar. Phone (landscape): 56 px icon rail, 44 px header, "More" menu. Tablet (portrait): iOS bottom tab bar. One code path, different size tokens. Touch targets ≥ 44×44.
- **Search** across every control, in every language: type "farm", tap a result, Robly jumps to it and highlights it.
- **Detachable tabs.** Drag a tab out of the sidebar (PC) or long-press it (touch) to open it in its own window; drag it back onto the sidebar to return it. Values never reset.
- **Themes** as tables of semantic tokens: RobScript (default), Light, Graphite, Midnight. Live theme editor in Settings, export/import as a short `robly1:…` string, switching without re-creating anything.
- **Configs:** profiles, autosave, autoload on start. Falls back to memory (with a notice) when the executor has no file system.
- **Script localisation:** your script defines its languages and translations; the player switches language live from the header. Library texts ship in en / ru / es / pt / de / fr.
- **Keybinds** with game-conflict checks, a keybind panel on PC, quick buttons on phones.
- **Animations:** Full / Soft / Off for weak devices.
- **Lucide icons** from Roblox-hosted sprite sheets (no external downloads); shadows are 1 px strokes.
- **Clean architecture:** tokens → components, layouts only (no hand-placed coordinates), fixed layers (windows / popups / notifications / modal), one value store, strict cleanup on close.

## Window

```lua
local Window = Robly:CreateWindow({
	Title = "RobScript Hub",          -- text spec (see Localization)
	Subtitle = "Blox Fruits · v2.4",
	Logo = "R",                       -- a letter, an icon name, or "rbxassetid://…"
	Folder = "RobScriptHub",          -- config folder name
	Theme = "RobScript",              -- preset name or colour table (used until the player picks one)
	ToggleKey = "RightShift",         -- PC show/hide key ("Ctrl+B" style combos work)
	Branding = true,                  -- "Robly by RobScript" + robscript.com in the window
	Animations = "Full",              -- "Full" | "Soft" | "Off"
	Size = Vector2.new(860, 560),     -- PC size (clamped to the screen)
	Language = { … },                 -- see Localization
	AutoSave = true, AutoLoad = true, SaveConfig = true,
	MaxDetachedPhone = 2,             -- detached windows allowed on phones
	Device = nil,                     -- force "pc" | "phone" | "tablet"
	Dev = false,                      -- warn about missing translations
	OnClose = function() end,
})
```

| Method | |
| --- | --- |
| `Window:Tab(opts)` | add a tab (`AddTab`, `CreateTab` are aliases) |
| `Window:Notify({ Title, Content, Type, Duration, Icon, Action = { Text, Callback } })` | toast; `Type`: `success`, `warning`, `error`, `info` |
| `Window:Dialog({ Title, Content, Input = { Placeholder, Default }, Buttons = { { Text, Variant, Callback } } })` | modal; a callback returning `false` keeps it open |
| `Window:Minimize()` / `:Restore()` / `:Toggle()` | pill ⇄ window |
| `Window:Close()` / `:Destroy()` | ask & destroy / destroy now — every connection and instance is cleaned |
| `Window:SetTheme(name or colors)` · `:SetLanguage(code)` · `:SetAnimations(mode)` | interface settings (saved) |
| `Window.Flags.autoFarm` | read / write any value: `Window.Flags.autoFarm = true` |
| `Window:OnFlagChanged(flag, fn)` | `fn(value, old, source)` |
| `Window:SaveConfig(name)` / `:LoadConfig(name)` | profiles |
| `Window:SelectTab(tabOrId)` · `Window:Reveal(control)` | navigation |

## Tabs and sections

```lua
local Farm = Window:Tab({
	Title = "Farm",
	Description = "Level, chests and weapon mastery",  -- shown on PC
	Icon = "leaf",            -- built-in icon name or "rbxassetid://…"
	Badge = "12",             -- small counter in the sidebar
	Detachable = true,        -- false: cannot be moved to its own window
})

local Chests = Farm:Section({ Title = "Chests", Collapsed = true })
Farm:Toggle({ … })            -- controls straight on a tab go to an untitled section
Farm:Detach() / Farm:Attach()
Farm.DetachChanged:Connect(function(detached) end)
```

## Controls

Every control accepts:

| Option | |
| --- | --- |
| `Title`, `Description` | text specs |
| `Flag` | key in the value store (also used by configs). Without it a stable flag is derived from the tab and title. |
| `Default`, `Callback` | `Callback(value)` runs on every change, and once on start if a config restored a non-default value |
| `Tooltip` | adds a "?" button |
| `VisibleWhen`, `EnabledWhen` | `{ Flag = "mode", Equals = "auto" }`, `NotEquals`, `In = {…}`, `Is = fn`, `{ Flag = "esp" }` (truthy) or `function(get, deviceMode) … end` |
| `DisabledText` | description shown while disabled ("Switch Mode: Auto on to unlock") |
| `QuickButton = true`, `Icon` | offer the function as a phone quick button |
| `Save = false` | never stored in configs |

Every control has `:Get()`, `:Set(value, silent)`, `:OnChanged(fn)`, `:SetTitle(text)`, `:SetDescription(text)`, `:SetVisible(bool)`, `:SetEnabled(bool)`, `:Destroy()`.

| Control | Extra options |
| --- | --- |
| `Toggle` | — |
| `Checkbox` | — |
| `Button` | `Variant` = `Primary` \| `Secondary` \| `Text` \| `Danger`, `Icon`, `Confirm = true \| { Title, Content }` |
| `Buttons` | `{ {Button opts}, … }` side by side |
| `Slider` | `Min`, `Max`, `Step`, `Suffix`, `Range = true` (value `{min, max}`) |
| `Stepper` | `Min`, `Max`, `Step`, `Suffix` |
| `Segmented` | `Options` (2–4), `Full = true` for a full-width control |
| `Dropdown` | `Options`, `Multi`, `Search`, `AllowNone`, `Placeholder`; `:SetOptions(list)` |
| `Input` | `Placeholder`, `Numeric`, `Min`, `Max`, `Suffix`, `MaxLength`, `Live`, `Finished` |
| `Textarea` | `Placeholder`, `Height` |
| `Keybind` | `Default = "F" \| "Ctrl+X"`, `Mode = "Action" \| "Toggle" \| "Hold"`, `Target = "flag"` (Toggle mode), `Callback`, `Changed(key)`, `Cooldown`, `ShowInHud` |
| `ColorPicker` | `Default` (Color3 or `"#RRGGBB"`), `Swatches` |
| `Label`, `Paragraph` | `Content`, `RichText` |
| `Badge` | `Text`, `Variant` = `accent` \| `neutral` \| `success` \| `warning` \| `danger`; `:SetText()` |
| `ProgressBar` | `Value`, `Max`, `Format(value, max)`; `:SetValue()` |
| `Image` | `Image`, `Height`, `ScaleType` |
| `Code` | `Code`, `Title` — block with a Copy button |
| `Divider` | — |

Options for `Dropdown` / `Segmented` can be plain values or `{ Value = "melee", Text = { en = "Melee", ru = "Ближний" }, Icon = "sword" }`.

## Localization

Your script decides its languages; the player picks one from the header (globe + code) or Settings. On first launch Robly uses the player's Roblox language when you support it.

```lua
Robly:CreateWindow({
	Title = "My Hub",
	Language = {
		Default = "en",
		Available = { "en", "ru", "es" },
		Strings = {                                   -- big scripts: keys
			en = { ["farm.auto"] = "Auto farm", ["farm.killed"] = "Killed {count} {count|mob|mobs}" },
			ru = { ["farm.auto"] = "Автофарм",  ["farm.killed"] = "Убито {count} {count|моб|моба|мобов}" },
		},
		Url = "https://raw.githubusercontent.com/you/hub/main/lang.json", -- optional community translations
		Library = { ru = { cancel = "Отменить" } },  -- override built-in texts
	},
})

Section:Toggle({ Title = "farm.auto" })                          -- key
Section:Toggle({ Title = { en = "Chest farm", ru = "Фарм сундуков" } }) -- inline
Section:Toggle({ Title = "Server hop" })                        -- plain, not translated
```

Missing translations fall back to the default language (with a warning when `Dev = true`). The language button is hidden when only one language is defined. Search matches the current language, the default language and the key.

## Themes

```lua
Robly:SetTheme("Midnight")                    -- "RobScript", "Light", "Graphite", "Midnight"
Robly:AddTheme("Ocean", { accent = "#2EC4B6", bg = "#0B1320" })   -- missing tokens come from RobScript
Window:SetTheme({ accent = Color3.fromRGB(76, 141, 255) })
```

Tokens: `accent, bg, nav, surface, raised, overlay, sunken, selected, segment, border, borderStrong, divider, text, textMuted, textSubtle, accentInk, accentPressed, track, toggleOff, knobOn, knobOff, checkBorder, success, warning, danger, dangerInk, tooltip, tooltipText, backdrop, code, codeText`.

Players can edit themes in Settings and share them as `robly1:…` strings.

## Keybinds, panel and quick buttons

- Binds don't fire while a text box (chat, game, Robly) is focused, and ignore keys the game already processed.
- Assigning a key the game uses shows "G is used by the game" with *Other key* / *Take from game*. Taking it binds through `ContextActionService` at high priority; the choice is saved.
- PC: keybind panel at the screen edge (all / enabled only, left/right, transparency, `Ctrl+B` to hide).
- Phones: quick buttons (44×44) at the right edge for controls with `QuickButton = true`; players choose them in Settings.

## Icons

Robly uses the [Lucide](https://lucide.dev/icons) icon set (1500+ icons, Lucide 0.363), rendered from Roblox-hosted sprite sheets — any Lucide name works:

```lua
Window:Tab({ Title = "Aim", Icon = "crosshair" })
Section:Button({ Title = "Teleport", Icon = "map-pin" })
```

Short aliases are kept too (`pin`, `bolt`, `close`, `farm`, `teleport`, `settings`, …), and any `rbxassetid://` image works. The sprites are regular Roblox assets, so they load on every executor; colours follow the theme.

## Compatibility

Robly checks every executor function before using it: `gethui`/`protect_gui` (falls back to CoreGui, then PlayerGui), `writefile` & co. (falls back to memory + a notice), `setclipboard` (falls back to a dialog with the text selected), `cloneref`, `request`. Fonts are Roblox's built-in Builder Sans and RobotoMono.

## Building and testing

The library is written as modules in `src/` and bundled into `dist/robly.lua`:

```sh
python3 tools/build.py          # build
python3 tools/build.py --check  # CI: fails if dist is outdated
lune run tests/run.luau         # smoke test in a simulated Roblox (needs Lune 0.10+)
```

The smoke test drives the demo through every feature against Roblox's real API database (property names and types are validated) — but it can't render pixels, so check visual changes in game.

## License

[The Unlicense](LICENSE) — public domain. Do anything you want, no attribution required.

Third-party: the Lucide icons are © Lucide Contributors (ISC License); their Roblox sprite map comes from [latte-soft/lucide-roblox](https://github.com/latte-soft/lucide-roblox) (MIT License). Regenerate it with `python3 tools/gen_lucide.py`.
