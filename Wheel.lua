local _, ns = ...

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_SWIPE = "Interface\\Buttons\\WHITE8X8"
local EMPTY_SLOT = "Interface\\Buttons\\UI-EmptySlot-Disabled"
local WEDGE_PATH = "Interface\\AddOns\\RadialBars\\Media\\Wedge"
local SENSOR_SIZE = 4096
local MIN_DEAD_ZONE = 12

local Wheel = {}
ns.Wheel = Wheel

local function CreateCircleMask(parent, texture)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return mask
end

local function SetMasked(texture, mask, masked)
	texture:RemoveMaskTexture(mask)
	if masked then
		texture:AddMaskTexture(mask)
	end
end

-- Slot 1 points up; slots run clockwise. Angles in degrees, 0 = right.
local function SlotAngle(index, count)
	return 90 - (index - 1) * (360 / count)
end

-- Restricted snippet: sets local `index` to the slot in the cursor's direction
-- from the wheel center, or nil inside the dead zone. A large protected
-- "sensor" frame measures the cursor even outside the wheel.
local PICK_DIRECTION = [[
	local index
	local x, y = owner:GetFrameRef("sensor"):GetMousePosition()
	if x then
		local size = owner:GetAttribute("rb-sensor")
		local dx, dy = (x - 0.5) * size, (y - 0.5) * size
		local dead = owner:GetAttribute("rb-dead")
		if dx * dx + dy * dy >= dead * dead then
			local count = owner:GetAttribute("rb-count")
			local step = 360 / count
			local offset = (90 - math.deg(math.atan2(dy, dx))) % 360
			index = math.floor((offset + step / 2) / step) % count + 1
		end
	end
]]

-- Protected header: shown and hidden from secure snippets so it works in combat.
local wheel = CreateFrame("Frame", "RadialBarsWheel", UIParent, "SecureHandlerStateTemplate, SecureHandlerShowHideTemplate")
wheel:SetPoint("CENTER")
wheel:SetFrameStrata("DIALOG")
wheel:SetClampedToScreen(true)
wheel:SetMovable(true)
wheel:Hide()

local sensor = CreateFrame("Frame", "RadialBarsSensor", wheel, "SecureFrameTemplate")
sensor:SetSize(SENSOR_SIZE, SENSOR_SIZE)
sensor:SetPoint("CENTER")
SecureHandlerSetFrameRef(wheel, "sensor", sensor)
wheel:SetAttribute("rb-sensor", SENSOR_SIZE)

local background = wheel:CreateTexture(nil, "BACKGROUND")
background:SetPoint("CENTER")
background:SetColorTexture(0, 0, 0, 1)
CreateCircleMask(wheel, background)

local wedges, wedgeHighlights, dividers = {}, {}, {}
for index = 1, ns.NUM_SLOTS do
	local wedge = wheel:CreateTexture(nil, "BORDER")
	wedge:SetPoint("CENTER")
	wedge:SetVertexColor(0.08, 0.08, 0.1)
	wedges[index] = wedge

	local highlight = wheel:CreateTexture(nil, "ARTWORK", nil, 1)
	highlight:SetPoint("CENTER")
	highlight:SetBlendMode("ADD")
	highlight:SetVertexColor(1, 0.82, 0.3, 0.35)
	highlight:Hide()
	wedgeHighlights[index] = highlight

	local line = wheel:CreateTexture(nil, "ARTWORK", nil, 2)
	line:SetColorTexture(0, 0, 0, 0.9)
	dividers[index] = line
end

local hub = wheel:CreateTexture(nil, "ARTWORK", nil, 3)
hub:SetPoint("CENTER")
hub:SetColorTexture(0.03, 0.03, 0.04, 1)
CreateCircleMask(wheel, hub)

local title = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("CENTER")
title:SetWordWrap(true)

local slots = {}

for index = 1, ns.NUM_SLOTS do
	local button = CreateFrame("Button", "RadialBarsSlot" .. index, wheel, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("type", "action")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.iconMask = CreateCircleMask(button, button.icon)

	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetAtlas("UI-HUD-ActionBar-IconFrame")

	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()

	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)

	button.roundHighlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.roundHighlight:SetAllPoints()
	button.roundHighlight:SetColorTexture(1, 1, 1, 0.25)
	CreateCircleMask(button, button.roundHighlight)

	button.squareHighlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.squareHighlight:SetAllPoints()
	button.squareHighlight:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
	button.squareHighlight:SetBlendMode("ADD")

	-- Shown for the slot picked by direction (hold mode).
	button.selectSquare = button:CreateTexture(nil, "OVERLAY", nil, 2)
	button.selectSquare:SetAllPoints()
	button.selectSquare:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
	button.selectSquare:SetBlendMode("ADD")
	button.selectSquare:Hide()

	button.selectRound = button:CreateTexture(nil, "OVERLAY", nil, 2)
	button.selectRound:SetAllPoints()
	button.selectRound:SetColorTexture(1, 0.82, 0.3, 0.35)
	button.selectRound:SetBlendMode("ADD")
	CreateCircleMask(button, button.selectRound)
	button.selectRound:Hide()

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetAction(self:GetAttribute("action"))
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	SecureHandlerSetFrameRef(wheel, "slot" .. index, button)
	-- Close the wheel after the action runs.
	SecureHandlerWrapScript(button, "OnClick", wheel, [[ return nil, "close" ]], [[ owner:Hide() ]])

	slots[index] = button
end

-- Radial slice shape: one secure button over the whole wheel picks the slice
-- by angle, so the full wedge is clickable. Slot buttons become display only.
local selector = CreateFrame("Button", "RadialBarsSelector", wheel, "SecureActionButtonTemplate")
selector:SetAllPoints()
selector:SetFrameLevel(wheel:GetFrameLevel() + 10)
selector:RegisterForClicks("AnyUp")
selector:SetAttribute("type", "action")
selector:Hide()
SecureHandlerWrapScript(selector, "OnClick", wheel, PICK_DIRECTION .. [[
	if not index then
		return false
	end
	self:SetAttribute("action", owner:GetFrameRef("slot" .. index):GetAttribute("action"))
	return nil, "close"
]], [[ owner:Hide() ]])

local function ActionName(action)
	local ok, name = pcall(function()
		local actionType, id = GetActionInfo(action)
		if actionType == "spell" then
			return C_Spell.GetSpellName(id)
		elseif actionType == "item" then
			return C_Item.GetItemNameByID(id)
		end
		return C_ActionBar.GetActionText(action)
	end)
	return ok and name or nil
end

-- Insecure mirror of PICK_DIRECTION, for highlight and the center label.
local function DirectionIndex()
	local centerX, centerY = wheel:GetCenter()
	if not centerX then
		return nil
	end
	local scale = wheel:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	local dx, dy = cursorX / scale - centerX, cursorY / scale - centerY
	local dead = wheel:GetAttribute("rb-dead")
	if dx * dx + dy * dy < dead * dead then
		return nil
	end
	local count = wheel:GetAttribute("rb-count")
	local step = 360 / count
	local offset = (90 - math.deg(math.atan2(dy, dx))) % 360
	return math.floor((offset + step / 2) / step) % count + 1
end

local selected
local function SetSelected(index)
	if index == selected then
		return
	end
	if selected then
		wedgeHighlights[selected]:Hide()
		slots[selected].selectSquare:Hide()
		slots[selected].selectRound:Hide()
	end
	selected = index
	local shape = wheel:GetAttribute("rb-shape")
	if index then
		if shape == "slice" then
			wedgeHighlights[index]:Show()
		elseif shape == "circle" then
			slots[index].selectRound:Show()
		else
			slots[index].selectSquare:Show()
		end
		local action = slots[index]:GetAttribute("action")
		local name = C_ActionBar.HasAction(action) and ActionName(action)
		title:SetText(name or EMPTY)
		title:SetTextColor(1, 1, 1)
	else
		title:SetText(wheel.barName)
		title:SetTextColor(1, 0.82, 0)
	end
end

wheel:SetScript("OnUpdate", function()
	local index
	if wheel:GetAttribute("rb-mode") == "hold"
		or (wheel:GetAttribute("rb-shape") == "slice" and selector:IsMouseOver()) then
		index = DirectionIndex()
	end
	SetSelected(index)
end)

-- Escape closes the wheel; bound only while the wheel is open.
local close = CreateFrame("Button", "RadialBarsClose", UIParent, "SecureHandlerClickTemplate")
close:RegisterForClicks("AnyUp")
SecureHandlerSetFrameRef(close, "wheel", wheel)
close:SetAttribute("_onclick", [[ self:GetFrameRef("wheel"):Hide() ]])

-- Position on every open, so "cursor" follows the mouse even in combat.
wheel:SetAttribute("_onshow", [[
	self:ClearAllPoints()
	local position = self:GetAttribute("rb-position")
	if position == "cursor" then
		self:SetPoint("CENTER", "$cursor")
	elseif position == "fixed" then
		self:SetPoint("CENTER", "$parent", "CENTER", self:GetAttribute("rb-x"), self:GetAttribute("rb-y"))
	else
		self:SetPoint("CENTER")
	end
	self:SetBindingClick(true, "ESCAPE", "RadialBarsClose")
]])
wheel:SetAttribute("_onhide", [[
	self:ClearBindings()
]])

-- The hotkey clicks this button. Toggle mode opens and closes the wheel on key
-- down. Hold mode opens on key down and, on key up, runs the slot in the
-- cursor's direction through this button's own secure action.
local trigger = CreateFrame("Button", "RadialBarsTrigger", UIParent, "SecureActionButtonTemplate")
trigger:RegisterForClicks("AnyDown", "AnyUp")
trigger:SetAttribute("useOnKeyDown", false)
SecureHandlerWrapScript(trigger, "OnClick", wheel, [[
	local mode = owner:GetAttribute("rb-mode")
	if mode ~= "hold" then
		if down then
			if owner:IsShown() then
				owner:Hide()
			else
				owner:Show()
			end
		end
		return false
	end
	if down then
		owner:Show()
		return false
	end
	if not owner:IsShown() then
		return false
	end
	]] .. PICK_DIRECTION .. [[
	local slot = index and owner:GetFrameRef("slot" .. index)
	owner:Hide()
	if not slot then
		return false
	end
	self:SetAttribute("type", "action")
	self:SetAttribute("action", slot:GetAttribute("action"))
]])

-- Preview overlay: blocks clicks and lets a fixed-position wheel be dragged
-- into place. Insecure, so only used out of combat.
local overlay = CreateFrame("Frame", nil, wheel)
overlay:SetAllPoints()
overlay:SetFrameLevel(wheel:GetFrameLevel() + 20)
overlay:EnableMouse(true)
overlay:Hide()

local overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
overlayText:SetPoint("TOP", title, "BOTTOM", 0, -4)

overlay:SetScript("OnMouseDown", function()
	if ns.GetBarConfig(ns.db.activeBar).position == "fixed" and not InCombatLockdown() then
		wheel:StartMoving()
	end
end)
overlay:SetScript("OnMouseUp", function()
	wheel:StopMovingOrSizing()
	local config = ns.GetBarConfig(ns.db.activeBar)
	if config.position ~= "fixed" then
		return
	end
	local x, y = wheel:GetCenter()
	local parentX, parentY = UIParent:GetCenter()
	config.x = math.floor(x - parentX + 0.5)
	config.y = math.floor(y - parentY + 0.5)
	ns.ApplyWhenSafe()
end)

local previewing = false

local function UpdateSlot(button)
	local action = button:GetAttribute("action")
	if not action or not C_ActionBar.HasAction(action) then
		button.icon:SetTexture(EMPTY_SLOT)
		button.icon:SetVertexColor(1, 1, 1, 0.4)
		button.cooldown:Clear()
		button.count:SetText("")
		return
	end

	button.icon:SetTexture(C_ActionBar.GetActionTexture(action))
	local usable, lackingResources = C_ActionBar.IsUsableAction(action)
	if usable then
		button.icon:SetVertexColor(1, 1, 1, 1)
	elseif lackingResources then
		button.icon:SetVertexColor(0.5, 0.5, 1, 1)
	else
		button.icon:SetVertexColor(0.4, 0.4, 0.4, 1)
	end

	-- Cooldown and count can be secret values in restricted content; pass them
	-- straight to widgets and never compare them. Skip on failure.
	pcall(function()
		local info = C_ActionBar.GetActionCooldown(action)
		button.cooldown:SetCooldown(info.startTime, info.duration, info.modRate)
	end)
	pcall(function()
		button.count:SetText(C_ActionBar.GetActionDisplayCount(action))
	end)
end

function Wheel:Refresh()
	for _, button in ipairs(slots) do
		if button:IsShown() then
			UpdateSlot(button)
		end
	end
end

local function Layout(config)
	local shape, count = config.shape, config.count
	local radius, iconSize = config.radius, config.iconSize
	local slice, round = shape == "slice", shape ~= "square"
	local outer = radius + iconSize / 2 + config.margin
	local hubRadius = radius * config.hubSize
	local deadZone = math.max(hubRadius, MIN_DEAD_ZONE)
	local step = 360 / count

	wheel:SetSize(outer * 2, outer * 2)

	background:SetSize(outer * 2, outer * 2)
	background:SetAlpha(config.backdropAlpha)
	background:SetShown(not slice and config.backdropAlpha > 0)

	hub:SetSize(hubRadius * 2, hubRadius * 2)
	hub:SetAlpha(math.max(config.backdropAlpha, 0.6))
	hub:SetShown(slice and hubRadius > 0)

	for index = 1, ns.NUM_SLOTS do
		local shown = slice and index <= count
		local rotation = math.rad(SlotAngle(index, count) - 90)
		for _, texture in ipairs({ wedges[index], wedgeHighlights[index] }) do
			texture:SetShown(shown and texture == wedges[index])
			texture:SetTexture(WEDGE_PATH .. count)
			texture:SetSize(outer * 2, outer * 2)
			texture:SetRotation(rotation)
		end
		wedges[index]:SetAlpha(config.backdropAlpha)

		local line = dividers[index]
		line:SetShown(shown and config.gap > 0)
		if shown then
			local angle = math.rad(SlotAngle(index, count) + step / 2)
			local length = outer - hubRadius
			local middle = hubRadius + length / 2
			line:ClearAllPoints()
			line:SetPoint("CENTER", wheel, "CENTER", middle * math.cos(angle), middle * math.sin(angle))
			line:SetSize(length, config.gap)
			line:SetRotation(angle)
		end
	end

	for index, button in ipairs(slots) do
		local shown = index <= count
		button:SetShown(shown)
		if shown then
			local angle = math.rad(SlotAngle(index, count))
			button:ClearAllPoints()
			button:SetPoint("CENTER", wheel, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
			button:SetSize(iconSize, iconSize)
			button:SetAlpha(config.iconAlpha)
			button:EnableMouse(not slice)

			SetMasked(button.icon, button.iconMask, round)
			if round then
				button.icon:SetTexCoord(0, 1, 0, 1)
				button.cooldown:SetSwipeTexture(CIRCLE_MASK)
			else
				button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				button.cooldown:SetSwipeTexture(SQUARE_SWIPE)
			end
			local outset = iconSize * 0.06
			button.border:SetShown(not round)
			button.border:ClearAllPoints()
			button.border:SetPoint("TOPLEFT", -outset, outset)
			button.border:SetPoint("BOTTOMRIGHT", outset, -outset)
			button.roundHighlight:SetShown(shape == "circle")
			button.squareHighlight:SetShown(not round)
		end
	end

	selector:SetShown(slice)

	wheel:SetAttribute("rb-count", count)
	wheel:SetAttribute("rb-shape", shape)
	wheel:SetAttribute("rb-dead", deadZone)
	title:SetWidth(math.max(deadZone * 2 - 8, 60))
end

-- Out of combat only (see ns.ApplyWhenSafe).
function Wheel:Apply()
	local bar = ns.db.activeBar
	local config = ns.GetBarConfig(bar)

	wheel:Hide()
	for index, button in ipairs(slots) do
		button:SetAttribute("action", ns.SlotFor(bar, index))
	end
	Layout(config)
	wheel:SetAttribute("rb-mode", config.mode)
	wheel:SetAttribute("rb-position", config.position)
	wheel:SetAttribute("rb-x", config.x)
	wheel:SetAttribute("rb-y", config.y)
	wheel.barName = ns.BARS[bar].name
	selected = nil
	title:SetText(wheel.barName)
	title:SetTextColor(1, 0.82, 0)

	ClearOverrideBindings(trigger)
	if config.key then
		SetOverrideBindingClick(trigger, true, config.key, "RadialBarsTrigger", "LeftButton")
	end

	if previewing then
		overlayText:SetText(config.position == "fixed" and "Preview: drag to place" or "Preview")
		wheel:Show()
	end
	self:Refresh()
end

function Wheel:IsPreviewing()
	return previewing
end

-- Out of combat only.
function Wheel:SetPreview(enabled)
	if InCombatLockdown() then
		return
	end
	enabled = enabled and true or false
	if enabled == previewing then
		return
	end
	previewing = enabled
	overlay:SetShown(previewing)
	if previewing then
		self:Apply()
	else
		wheel:StopMovingOrSizing()
		wheel:Hide()
	end
	if ns.OnPreviewChanged then
		ns.OnPreviewChanged()
	end
end

wheel:HookScript("OnShow", function()
	Wheel:Refresh()
end)

wheel:HookScript("OnHide", function()
	SetSelected(nil)
end)

wheel:HookScript("OnHide", function()
	if previewing and not InCombatLockdown() then
		Wheel:SetPreview(false)
	end
end)

local updates = CreateFrame("Frame")
for _, event in ipairs({
	"ACTIONBAR_SLOT_CHANGED",
	"ACTIONBAR_UPDATE_COOLDOWN",
	"ACTIONBAR_UPDATE_USABLE",
	"ACTIONBAR_UPDATE_STATE",
	"SPELL_UPDATE_COOLDOWN",
	"SPELL_UPDATE_CHARGES",
	"BAG_UPDATE_DELAYED",
	"UPDATE_SHAPESHIFT_FORM",
}) do
	updates:RegisterEvent(event)
end
updates:SetScript("OnEvent", function()
	if wheel:IsShown() then
		Wheel:Refresh()
	end
end)
