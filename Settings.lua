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

local canvas = CreateFrame("Frame")
local scroll = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -8)
scroll:SetPoint("BOTTOMRIGHT", -26, 8)

local panel = CreateFrame("Frame", nil, scroll)
panel:SetSize(COLUMN_WIDTH * 2 + 36, 1)
scroll:SetScrollChild(panel)
local widgets = { sliders = {} }
local refreshing = false

local function Config()
	return ns.GetBarConfig(ns.db.activeBar)
end

local sectionOrder = {}

local function AddRow(section, region, gap, layout)
	section.rows[#section.rows + 1] = { region = region, gap = gap or 8, layout = layout }
	section.finalContent = region
	return region
end

local function Label(section, text, template, gap)
	local label = section:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return AddRow(section, label, gap)
end

local function Section(title)
	local section = CreateFrame("Frame", nil, panel)
	section.rows = {}
	section.heading = Label(section, title, "GameFontNormalLarge", 0)
	sectionOrder[#sectionOrder + 1] = section
	return section
end

local function ApplyAndRefresh()
	if not ns.ApplyWhenSafe() then
		widgets.status:SetText("In combat: changes apply when combat ends.")
	end
	widgets.Refresh()
end

-- Radio buttons in rows of `columns`.
local function RadioGroup(section, options, onSelect, columns, columnWidth)
	columns = columns or 1
	columnWidth = columnWidth or COLUMN_WIDTH
	local container = CreateFrame("Frame", nil, section)
	local group = {}
	for i, option in ipairs(options) do
		local radio = CreateFrame("CheckButton", nil, container, "UIRadioButtonTemplate")
		local text = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("TOPLEFT", radio, "TOPRIGHT", 4, -2)
		text:SetJustifyH("LEFT")
		text:SetText(option.label)
		radio.label = text
		radio.value = option.value
		radio:SetScript("OnClick", function()
			onSelect(option.value)
		end)
		group[i] = radio
	end
	AddRow(section, container, 8, function(width)
		local count = math.max(1, math.min(columns, math.floor(width / columnWidth)))
		local cellWidth = width / count
		local offset, rowHeight = 0, 0
		for i, radio in ipairs(group) do
			local column = (i - 1) % count
			if column == 0 then
				offset, rowHeight = offset + rowHeight, 22
			end
			radio:ClearAllPoints()
			radio:SetPoint("TOPLEFT", container, "TOPLEFT", column * cellWidth, -offset)
			radio.label:SetWidth(math.max(1, cellWidth - 24))
			rowHeight = math.max(rowHeight, radio.label:GetStringHeight() + 4)
		end
		container:SetHeight(offset + rowHeight)
	end)
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

local function Slider(section, text, key, step, formatter)
	local limit = ns.LIMITS[key]
	Label(section, text, nil, 12)
	local slider = CreateFrame("Frame", nil, section, "MinimalSliderWithSteppersTemplate")
	slider:SetWidth(COLUMN_WIDTH - 60)
	AddRow(section, slider, 2, function(width)
		slider:SetWidth(math.min(COLUMN_WIDTH - 60, width))
	end)
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

local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 16, -16)
header:SetText("Radial Bars")

local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
intro:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
intro:SetJustifyH("LEFT")
intro:SetText("Turns one action bar into a radial wheel opened by a hotkey. The original bar stays visible. Action Bar 1 is not supported.")

local actionBar = Section("Action bar")
local barOptions = {}
for bar = 2, 8 do
	barOptions[#barOptions + 1] = { value = bar, label = "Bar " .. bar }
end
widgets.bar = RadioGroup(actionBar, barOptions, function(bar)
	ns.db.activeBar = bar
	ApplyAndRefresh()
end, 4, 72)

local activation = Section("Activation")
Label(activation, "Hotkey")
local keyRow = CreateFrame("Frame", nil, activation)
local keyButton = CreateFrame("Button", nil, keyRow, "UIPanelButtonTemplate")
keyButton:SetPoint("TOPLEFT")

local clearButton = CreateFrame("Button", nil, keyRow, "UIPanelButtonTemplate")
clearButton:SetSize(80, 24)
clearButton:SetText("Clear")
AddRow(activation, keyRow, 8, function(width)
	keyButton:SetSize(math.min(180, width), 24)
	clearButton:ClearAllPoints()
	if width >= 268 then
		clearButton:SetPoint("LEFT", keyButton, "RIGHT", 8, 0)
		keyRow:SetHeight(24)
	else
		clearButton:SetPoint("TOPLEFT", keyButton, "BOTTOMLEFT", 0, -6)
		keyRow:SetHeight(54)
	end
end)

local keyNote = Label(activation, "", "GameFontHighlightSmall", 6)
widgets.status = Label(activation, "", "GameFontRedSmall", 8)

Label(activation, "Hotkey behavior", nil, 12)
widgets.mode = RadioGroup(activation, {
	{ value = "toggle", label = "Toggle: press to open, click a slot" },
	{ value = "hold", label = "Hold: point toward a slot, release to use" },
}, function(mode)
	Config().mode = mode
	ApplyAndRefresh()
end)

local function Checkbox(section, text, note, key)
	local container = CreateFrame("Frame", nil, section)
	local check = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("TOPLEFT")
	local label = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", check, "TOPRIGHT", 4, -4)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	check.note = container:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	check.note:SetJustifyH("LEFT")
	check.note:SetText(note)
	AddRow(section, container, 10, function(width)
		label:SetWidth(math.max(1, width - 28))
		local height = math.max(24, label:GetStringHeight() + 4)
		check.note:ClearAllPoints()
		check.note:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -height - 2)
		check.note:SetWidth(math.max(1, width - 4))
		container:SetHeight(height + 2 + check.note:GetStringHeight())
	end)
	check.key = key
	check:SetScript("OnClick", function(self)
		Config()[key] = self:GetChecked() and true or false
		ApplyAndRefresh()
	end)
	widgets.checks[#widgets.checks + 1] = check
	return check
end

widgets.checks = {}
Checkbox(activation, "Hide cursor in Hold mode",
	"A pointer shows the direction instead.", "hideCursor")

local placement = Section("Placement")
Label(placement, "Open at")
widgets.position = RadioGroup(placement, {
	{ value = "center", label = "Screen center" },
	{ value = "cursor", label = "Mouse cursor" },
	{ value = "fixed", label = "Fixed position (drag in preview)" },
}, function(position)
	Config().position = position
	ApplyAndRefresh()
end)

local previewButton = CreateFrame("Button", nil, placement, "UIPanelButtonTemplate")
previewButton:SetSize(140, 24)
AddRow(placement, previewButton, 10, function(width)
	previewButton:SetWidth(math.min(140, width))
end)
previewButton:SetScript("OnClick", function()
	if InCombatLockdown() then
		widgets.status:SetText("Leave combat to preview.")
		widgets.Refresh()
		return
	end
	ns.Wheel:SetPreview(not ns.Wheel:IsPreviewing())
end)
widgets.preview = previewButton

local wheelLayout = Section("Wheel layout")
Label(wheelLayout, "Icon shape")
widgets.shape = RadioGroup(wheelLayout, {
	{ value = "square", label = "Square" },
	{ value = "circle", label = "Circle" },
	{ value = "slice", label = "Radial slice" },
}, function(shape)
	Config().shape = shape
	ApplyAndRefresh()
end, 3, 95)

for _, spec in ipairs({
	{ "Buttons", "count", 1 },
	{ "Icon size", "iconSize", 2 },
	{ "Spacing (distance from center)", "radius", 5 },
	{ "Margin (backdrop around icons)", "margin", 2 },
	{ "Center size (dead zone)", "hubSize", 0.05, Percent },
	{ "Slice gap", "gap", 1 },
	{ "Slice icon zoom", "sliceIconZoom", 0.05, Percent },
}) do
	Slider(wheelLayout, spec[1], spec[2], spec[3], spec[4])
end

local visibility = Section("Visibility")
Slider(visibility, "Backdrop opacity", "backdropAlpha", 0.05, Percent)
Slider(visibility, "Icon opacity", "iconAlpha", 0.05, Percent)
Checkbox(visibility, "Show description in center",
	"Needs a center size large enough to fit text.", "showDescription")

local function UpdateLayout()
	panel:SetWidth(scroll:GetWidth())
	local top = panel:GetTop()
	if not top then
		return
	end
	local width = math.max(1, panel:GetWidth() - 32)
	intro:SetWidth(width)
	local previous = intro
	for _, section in ipairs(sectionOrder) do
		section:ClearAllPoints()
		section:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -24)
		section:SetWidth(width)
		local last
		for _, row in ipairs(section.rows) do
			local region = row.region
			region:ClearAllPoints()
			region:SetWidth(width)
			region:SetPoint("TOPLEFT", last or section, last and "BOTTOMLEFT" or "TOPLEFT", 0, -row.gap)
			if row.layout then row.layout(width) end
			last = region
		end
		local bottom = section.finalContent:GetBottom()
		if not bottom then return end
		section:SetHeight(section:GetTop() - bottom)
		previous = section
	end
	panel:SetHeight(top - previous:GetBottom() + 16)
	scroll:UpdateScrollChildRect()
	scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
end

scroll:HookScript("OnSizeChanged", UpdateLayout)

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
		widgets.Refresh()
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
		if slider.key == "sliceIconZoom" then
			slider:SetEnabled(config.shape == "slice")
		end
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
	UpdateLayout()
end

ns.OnPreviewChanged = widgets.Refresh

canvas:SetScript("OnShow", function()
	widgets.Refresh()
	UpdateLayout()
end)
canvas:SetScript("OnHide", function()
	ns.Wheel:SetPreview(false)
end)

local category = Settings.RegisterCanvasLayoutCategory(canvas, "Radial Bars")
Settings.RegisterAddOnCategory(category)
ns.settingsCategory = category

-- Changelog subpage.

local changelogPanel = CreateFrame("Frame")

local changelogHeader = changelogPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
changelogHeader:SetPoint("TOPLEFT", 16, -16)
changelogHeader:SetText("Radial Bars Changelog")

local installed = changelogPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
installed:SetPoint("TOPLEFT", changelogHeader, "BOTTOMLEFT", 0, -6)
installed:SetText("Installed version: " .. (C_AddOns.GetAddOnMetadata("RadialBars", "Version") or "unknown"))

local changelogScroll = CreateFrame("ScrollFrame", nil, changelogPanel, "UIPanelScrollFrameTemplate")
changelogScroll:SetPoint("TOPLEFT", installed, "BOTTOMLEFT", 0, -12)
changelogScroll:SetPoint("BOTTOMRIGHT", -36, 16)

local content = CreateFrame("Frame", nil, changelogScroll)
content:SetSize(1, 1)
changelogScroll:SetScrollChild(content)

local changelogText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
changelogText:SetPoint("TOPLEFT")
changelogText:SetJustifyH("LEFT")
changelogText:SetSpacing(3)
changelogText:SetText(ns.FormatChangelog(ns.CHANGELOG))

changelogScroll:SetScript("OnSizeChanged", function(_, width)
	content:SetWidth(width)
	changelogText:SetWidth(width - 8)
	content:SetHeight(changelogText:GetStringHeight() + 8)
end)

Settings.RegisterCanvasLayoutSubcategory(category, changelogPanel, "Changelog")

SLASH_RADIALBARS1 = "/radialbars"
SlashCmdList.RADIALBARS = function()
	Settings.OpenToCategory(category:GetID())
end
