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
