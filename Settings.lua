local _, ns = ...

local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true,
	LCTRL = true, RCTRL = true,
	LALT = true, RALT = true,
	LMETA = true, RMETA = true,
	UNKNOWN = true,
}

local panel = CreateFrame("Frame")
local widgets = {}

local function Label(text, template, anchor, x, y)
	local label = panel:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -16)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function RadioGroup(anchor, options, onSelect)
	local group = {}
	local previous
	for i, option in ipairs(options) do
		local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
		if previous then
			radio:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)
		else
			radio:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
		end
		local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", radio, "RIGHT", 4, 0)
		text:SetText(option.label)
		radio.value = option.value
		radio:SetScript("OnClick", function()
			onSelect(option.value)
		end)
		group[i] = radio
		previous = radio
	end
	function group:Select(value)
		for _, radio in ipairs(self) do
			radio:SetChecked(radio.value == value)
		end
	end
	group.last = previous
	return group
end

local function ApplyAndRefresh()
	if not ns.ApplyWhenSafe() then
		widgets.status:SetText("In combat: changes apply when combat ends.")
	end
	widgets.Refresh()
end

local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 16, -16)
header:SetText("Radial Bars")

local intro = Label("Turns one action bar into a radial wheel opened by a hotkey. The original bar stays visible.", "GameFontHighlightSmall", header, 0, -8)

local barLabel = Label("Action bar", nil, intro)
local barOptions = {}
for bar = 2, 8 do
	barOptions[#barOptions + 1] = { value = bar, label = ns.BARS[bar].name }
end
widgets.bar = RadioGroup(barLabel, barOptions, function(bar)
	ns.db.activeBar = bar
	ApplyAndRefresh()
end)

local barNote = Label("Action Bar 1 is not supported.", "GameFontDisableSmall", widgets.bar.last, 0, -6)

local modeLabel = Label("Hotkey behavior", nil, barNote)
widgets.mode = RadioGroup(modeLabel, {
	{ value = "toggle", label = "Toggle: press to open, click a slot to use it" },
	{ value = "hold", label = "Hold: hold to open, release over a slot to use it" },
}, function(mode)
	ns.GetBarConfig(ns.db.activeBar).mode = mode
	ApplyAndRefresh()
end)

local keyLabel = Label("Hotkey", nil, widgets.mode.last)

local keyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
keyButton:SetSize(180, 24)
keyButton:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", 0, -8)
widgets.key = keyButton

local clearButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
clearButton:SetSize(80, 24)
clearButton:SetPoint("LEFT", keyButton, "RIGHT", 8, 0)
clearButton:SetText("Clear")

local keyNote = Label("", "GameFontHighlightSmall", keyButton, 0, -6)
widgets.keyNote = keyNote

widgets.status = Label("", "GameFontRedSmall", keyNote, 0, -12)

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
		local binding = (IsAltKeyDown() and "ALT-" or "")
			.. (IsControlKeyDown() and "CTRL-" or "")
			.. (IsShiftKeyDown() and "SHIFT-" or "")
			.. key
		ns.GetBarConfig(ns.db.activeBar).key = binding
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
	ns.GetBarConfig(ns.db.activeBar).key = nil
	ApplyAndRefresh()
end)

function widgets.Refresh()
	if not ns.db then
		return
	end
	local bar = ns.db.activeBar
	local config = ns.GetBarConfig(bar)
	widgets.bar:Select(bar)
	widgets.mode:Select(config.mode)
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

panel:SetScript("OnShow", widgets.Refresh)

local category = Settings.RegisterCanvasLayoutCategory(panel, "Radial Bars")
Settings.RegisterAddOnCategory(category)
ns.settingsCategory = category

SLASH_RADIALBARS1 = "/radialbars"
SlashCmdList.RADIALBARS = function()
	Settings.OpenToCategory(category:GetID())
end
