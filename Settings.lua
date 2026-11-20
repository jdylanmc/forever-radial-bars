local _, ns = ...

local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true,
	LCTRL = true, RCTRL = true,
	LALT = true, RALT = true,
	LMETA = true, RMETA = true,
	UNKNOWN = true,
}

local RIGHT_LABEL = MinimalSliderWithSteppersMixin.Label.Right
local COLUMN_WIDTH = 300

local panel = CreateFrame("Frame")
local widgets = { sliders = {} }
local refreshing = false

local function Config()
	return ns.GetBarConfig(ns.db.activeBar)
end

local function Label(text, template, anchor, x, y, point)
	local label = panel:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
	label:SetPoint("TOPLEFT", anchor, point or "BOTTOMLEFT", x or 0, y or -16)
	label:SetJustifyH("LEFT")
	label:SetWidth(COLUMN_WIDTH)
	label:SetText(text)
	return label
end

local function ApplyAndRefresh()
	if not ns.ApplyWhenSafe() then
		widgets.status:SetText("In combat: changes apply when combat ends.")
	end
	widgets.Refresh()
end

-- Radio buttons in rows of `columns`.
local function RadioGroup(anchor, options, onSelect, columns, columnWidth)
	columns = columns or 1
	columnWidth = columnWidth or COLUMN_WIDTH
	local group = {}
	for i, option in ipairs(options) do
		local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
		local row, column = math.floor((i - 1) / columns), (i - 1) % columns
		radio:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", column * columnWidth, -8 - row * 22)
		local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", radio, "RIGHT", 4, 0)
		text:SetText(option.label)
		radio.value = option.value
		radio:SetScript("OnClick", function()
			onSelect(option.value)
		end)
		group[i] = radio
		if column == 0 then
			group.last = radio
		end
	end
	function group:Select(value)
		for _, radio in ipairs(self) do
			radio:SetChecked(radio.value == value)
		end
	end
	return group
end

local function Percent(value)
	return math.floor(value * 100 + 0.5) .. "%"
end

local function Whole(value)
	return tostring(math.floor(value + 0.5))
end

local function Slider(anchor, text, key, step, formatter)
	local limit = ns.LIMITS[key]
	local label = Label(text, "GameFontHighlight", anchor, 0, -12)
	local slider = CreateFrame("Frame", nil, panel, "MinimalSliderWithSteppersTemplate")
	slider:SetWidth(COLUMN_WIDTH - 60)
	slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
	slider:Init(limit[1], limit[2], limit[3], math.floor((limit[3] - limit[2]) / step + 0.5), {
		[RIGHT_LABEL] = formatter or Whole,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if refreshing then
			return
		end
		Config()[key] = math.floor(value / step + 0.5) * step
		ApplyAndRefresh()
	end, slider)
	slider.key = key
	widgets.sliders[#widgets.sliders + 1] = slider
	return slider
end

-- Left column: behavior.

local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 16, -16)
header:SetText("Radial Bars")

local intro = Label("Turns one action bar into a radial wheel opened by a hotkey. The original bar stays visible. Action Bar 1 is not supported.", "GameFontHighlightSmall", header, 0, -8)
intro:SetWidth(COLUMN_WIDTH * 2)

local barLabel = Label("Action bar", nil, intro)
local barOptions = {}
for bar = 2, 8 do
	barOptions[#barOptions + 1] = { value = bar, label = "Bar " .. bar }
end
widgets.bar = RadioGroup(barLabel, barOptions, function(bar)
	ns.db.activeBar = bar
	ApplyAndRefresh()
end, 4, 72)

local modeLabel = Label("Hotkey behavior", nil, widgets.bar.last, 0, -14)
widgets.mode = RadioGroup(modeLabel, {
	{ value = "toggle", label = "Toggle: press to open, click a slot" },
	{ value = "hold", label = "Hold: point toward a slot, release to use" },
}, function(mode)
	Config().mode = mode
	ApplyAndRefresh()
end)

local positionLabel = Label("Open at", nil, widgets.mode.last, 0, -14)
widgets.position = RadioGroup(positionLabel, {
	{ value = "center", label = "Screen center" },
	{ value = "cursor", label = "Mouse cursor" },
	{ value = "fixed", label = "Fixed position (drag in preview)" },
}, function(position)
	Config().position = position
	ApplyAndRefresh()
end)

local previewButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
previewButton:SetSize(140, 24)
previewButton:SetPoint("TOPLEFT", widgets.position.last, "BOTTOMLEFT", 0, -10)
previewButton:SetScript("OnClick", function()
	if InCombatLockdown() then
		widgets.status:SetText("Leave combat to preview.")
		return
	end
	ns.Wheel:SetPreview(not ns.Wheel:IsPreviewing())
end)
widgets.preview = previewButton

local keyLabel = Label("Hotkey", nil, previewButton, 0, -14)

local keyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
keyButton:SetSize(180, 24)
keyButton:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", 0, -8)

local clearButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
clearButton:SetSize(80, 24)
clearButton:SetPoint("LEFT", keyButton, "RIGHT", 8, 0)
clearButton:SetText("Clear")

local keyNote = Label("", "GameFontHighlightSmall", keyButton, 0, -6)
widgets.status = Label("", "GameFontRedSmall", keyNote, 0, -8)

-- Right column: appearance.

local appearance = Label("Appearance", nil, intro, COLUMN_WIDTH + 20, -16)

widgets.shape = RadioGroup(appearance, {
	{ value = "square", label = "Square" },
	{ value = "circle", label = "Circle" },
	{ value = "slice", label = "Radial slice" },
}, function(shape)
	Config().shape = shape
	ApplyAndRefresh()
end, 3, 95)

local previous = widgets.shape.last
for _, spec in ipairs({
	{ "Buttons", "count", 1 },
	{ "Icon size", "iconSize", 2 },
	{ "Spacing (distance from center)", "radius", 5 },
	{ "Margin (backdrop around icons)", "margin", 2 },
	{ "Center size (dead zone)", "hubSize", 0.05, Percent },
	{ "Slice gap", "gap", 1 },
	{ "Backdrop opacity", "backdropAlpha", 0.05, Percent },
	{ "Icon opacity", "iconAlpha", 0.05, Percent },
}) do
	previous = Slider(previous, spec[1], spec[2], spec[3], spec[4])
end

local function Checkbox(anchor, x, y, text, note, key)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
	local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	label:SetText(text)
	check.note = Label(note, "GameFontDisableSmall", check, 4, -2)
	check.key = key
	check:SetScript("OnClick", function(self)
		Config()[key] = self:GetChecked() and true or false
		ApplyAndRefresh()
	end)
	widgets.checks[#widgets.checks + 1] = check
	return check
end

widgets.checks = {}
local describe = Checkbox(previous, -4, -10, "Show description in center",
	"Needs a center size large enough to fit text.", "showDescription")
Checkbox(describe.note, -4, -6, "Hide cursor in Hold mode",
	"A pointer shows the direction instead.", "hideCursor")

-- Key capture.

local capturing = false

local function StopCapture()
	capturing = false
	keyButton:EnableKeyboard(false)
	widgets.Refresh()
end

keyButton:SetScript("OnClick", function()
	if InCombatLockdown() then
		widgets.status:SetText("Leave combat to change the hotkey.")
		return
	end
	capturing = true
	keyButton:EnableKeyboard(true)
	keyButton:SetText("Press a key (Esc cancels)")
end)

keyButton:SetScript("OnKeyDown", function(self, key)
	if not capturing then
		self:SetPropagateKeyboardInput(true)
		return
	end
	self:SetPropagateKeyboardInput(false)
	if MODIFIER_KEYS[key] then
		return
	end
	if key ~= "ESCAPE" then
		Config().key = (IsAltKeyDown() and "ALT-" or "")
			.. (IsControlKeyDown() and "CTRL-" or "")
			.. (IsShiftKeyDown() and "SHIFT-" or "")
			.. key
		ns.ApplyWhenSafe()
	end
	StopCapture()
end)

keyButton:SetScript("OnHide", function()
	if capturing then
		StopCapture()
	end
end)

clearButton:SetScript("OnClick", function()
	Config().key = nil
	ApplyAndRefresh()
end)

function widgets.Refresh()
	if not ns.db then
		return
	end
	refreshing = true
	local config = Config()
	widgets.bar:Select(ns.db.activeBar)
	widgets.mode:Select(config.mode)
	widgets.position:Select(config.position)
	widgets.shape:Select(config.shape)
	for _, check in ipairs(widgets.checks) do
		check:SetChecked(config[check.key])
	end
	for _, slider in ipairs(widgets.sliders) do
		slider:SetValue(config[slider.key])
	end
	refreshing = false

	previewButton:SetText(ns.Wheel:IsPreviewing() and "Hide preview" or "Preview wheel")
	if not capturing then
		keyButton:SetText(config.key and GetBindingText(config.key) or "Not bound")
	end
	local note = ""
	if config.key then
		local existing = GetBindingAction(config.key)
		if existing and existing ~= "" then
			note = "Overrides the game binding: " .. (GetBindingName(existing) or existing)
		end
	end
	keyNote:SetText(note)
	if not InCombatLockdown() then
		widgets.status:SetText("")
	end
end

ns.OnPreviewChanged = widgets.Refresh

panel:SetScript("OnShow", widgets.Refresh)
panel:SetScript("OnHide", function()
	ns.Wheel:SetPreview(false)
end)

local category = Settings.RegisterCanvasLayoutCategory(panel, "Radial Bars")
Settings.RegisterAddOnCategory(category)
ns.settingsCategory = category

SLASH_RADIALBARS1 = "/radialbars"
SlashCmdList.RADIALBARS = function()
	Settings.OpenToCategory(category:GetID())
end
