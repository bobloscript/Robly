# Changelog

## 1.2.0 — 2026-10-20

- Linked colours. A theme is now a few base colours (accent, background, text, status colours); every other colour — sidebar, cards, outlines, popups, tracks, muted text… — is derived from them. Changing the background or text in the editor repaints the whole window, sidebar included (Obsidian/Airflow-style model).
- Theme editor: Accent, Background, Sidebar, Cards, Outline and Text in the main list; every other token in "All colours". A colour picked by hand overrides its derived value and survives base changes; "Reset hand-picked colours" makes everything follow the base again.
- Theme strings are now `robly2:` (base + overrides only); `robly1:` strings still import. Saved 1.x custom themes load as their base colours.
- `Robly:AddTheme(name, { accent, bg, text, … })` needs only the base colours.

## 1.1.0 — 2026-10-20

- Icons are now [Lucide](https://lucide.dev/icons): 1573 icons rendered from Roblox-hosted sprite sheets (ImageLabel + ImageRectOffset), recoloured by the theme. Any Lucide name works (`Icon = "crosshair"`); the old short names (`pin`, `bolt`, `close`, …) map to Lucide icons. Fewer instances per icon (one image instead of many frames), so windows are lighter.
- `tools/gen_lucide.py` regenerates `src/core/LucideData.lua` from the latte-soft/lucide-roblox release.

## 1.0.3 — 2026-10-20

- Dragging: windows followed the pointer with a drift equal to the Roblox top-bar height, so the main window couldn't reach the bottom of the screen and detached windows flew off it. In a ScreenGui with IgnoreGuiInset, AbsolutePosition/InputObject.Position and UDim2 Position offsets differ by the top bar; the code mixed them. Pointer and AbsolutePosition now stay in one space and are converted (Device.toOffset) before setting a Position; drags move from the start position by the total pointer delta.
- Detached windows and the pill are clamped to the screen while dragging (a detached window keeps its header visible).
- Colour picker: the circle in the saturation/brightness square sits exactly under the cursor.
- Popups, tooltips, the drag ghost and detach/return animations use the same conversion, so they line up with their anchors.
- Tests: the Lune mock now reproduces the top-bar offset, with checks for pointer-following drags, reaching the bottom edge and the colour cursor.

## 1.0.2 — 2026-10-20

Fixes from the first in-game test.

- Theme and language bindings were kept in weak tables. Roblox collects the Lua wrapper of a live Instance, so labels, strokes and corner patches nobody referenced stopped updating: after switching to Light/Graphite/Midnight parts of the window kept the old colours (title, Export/Import, "New profile", search field border, sidebar patches), and language switching had the same problem. Bindings are now strong and removed when the instance is destroyed.
- Window and detached windows can be dragged again: the header drag uses a transparent button under the header content (Frames don't receive input reliably).
- The resize grip sat inside the window's list layout: it showed up as "//" in the top-left corner and pushed the whole window down by 16 px. Layout now lives in an inner Shell frame.
- A second detached window no longer opens exactly behind the first (cascades by 28 px).
- Collapsed sections show the right number of functions ("All colours · 27 features" instead of "0").
- Pressing a window's header raises it above other windows.

## 1.0.1 — 2026-10-20

Bug hunt fixes.

- Configs: saving no longer drops values loaded for controls that weren't created yet (lazy tabs, older script versions).
- Keybinds: the key pressed while assigning a new bind no longer also fires an existing bind on that key.
- Keybinds and quick buttons do nothing while their control is locked by `EnabledWhen` (quick buttons say "locked").
- Minimise → restore → minimise quickly no longer moves the window to a wrong spot.
- Ctrl+K no longer types "k" into the search field.
- Switching theme during a colour animation no longer leaves a colour from the old theme.
- Touch: a finger sliding off a button no longer leaves it pressed, and no longer makes the stepper count to its limit.
- Truncated dropdown values and segments show the full text in a tooltip (PC).
- The Settings "Animations" control follows `Robly:SetAnimations()`.
- Search jumps to a control reliably after expanding its section.
- No crash when a slider is given Min > Max or a window/tooltip doesn't fit the screen.

## 1.0.0 — 2026-10-20

First release, built from the Robly brief and the "Robly UI" mockup.

- Window with three layouts: PC sidebar, phone icon rail, tablet bottom tab bar; drag, resize (PC), minimise to a pill, show/hide key.
- Search across all controls in every language.
- Detachable tabs (drag out / long press) with return by the same gesture.
- Controls: Toggle, Checkbox, Button, Buttons, Slider (number/range), Stepper, Segmented, Dropdown (single/multi, search), Input, Textarea, Keybind, ColorPicker, Label, Paragraph, Badge, Image, ProgressBar, Code, Divider.
- Feedback: notifications, dialogs, tooltips — each in its own layer.
- Themes: RobScript, Light, Graphite, Midnight; live editor; robly1: export/import.
- Configs: profiles, autosave, autoload; in-memory fallback without a file system.
- Script localisation with plurals and remote translations; built-in texts in en/ru/es/pt/de/fr.
- Keybinds with game-conflict handling, PC keybind panel, phone quick buttons.
- Animations Full / Soft / Off. Vector icon set without images.
