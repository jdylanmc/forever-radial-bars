local _, ns = ...

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_SWIPE = "Interface\\Buttons\\WHITE8X8"
local EMPTY_SLOT = "Interface\\Buttons\\UI-EmptySlot-Disabled"
local WEDGE_PATH = "Interface\\AddOns\\RadialBars\\Media\\Wedge"
local BLANK_CURSOR = "Interface\\AddOns\\RadialBars\\Media\\Blank"
local POINTER = "Interface\\AddOns\\RadialBars\\Media\\Pointer"
local SENSOR_SIZE = 4096
local MIN_DEAD_ZONE = 12

local Wheels = { instances = {} }
ns.Wheel = Wheels
local coordinator = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
coordinator:SetAttribute("open", [[
	local bar = ...
	local wheel = self:GetFrameRef("wheel" .. bar)
	local previous = self:GetAttribute("current")
	if previous and previous ~= wheel then previous:Hide() end
	if not wheel:IsShown() then wheel:Show() end
]])

local close = CreateFrame("Button", "RadialBarsClose", UIParent, "SecureHandlerClickTemplate")
close:RegisterForClicks("AnyUp")
SecureHandlerSetFrameRef(close, "coordinator", coordinator)
close:SetAttribute("_onclick", [[
	local wheel = self:GetFrameRef("coordinator"):GetAttribute("current")
	if wheel then wheel:Hide() end
]])

local open = CreateFrame("Button", "RadialBarsOpen", UIParent, "SecureHandlerClickTemplate")
open:RegisterForClicks("AnyUp")
SecureHandlerSetFrameRef(open, "coordinator", coordinator)
open:SetAttribute("_onclick", [[
	self:GetFrameRef("coordinator"):RunAttribute("open", self:GetAttribute("rb-bar"))
]])

local CreateCircleMask = ns.Visuals.CircleMask
local SlotAngle = ns.Visuals.SlotAngle

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

ns.PICK_DIRECTION = PICK_DIRECTION

local function CreateWheel(bar)
local Wheel = {}
local function Name(part)
	return "RadialBars" .. part .. (bar == ns.DEFAULT_BAR and "" or "Bar" .. bar)
end

-- Protected header: shown and hidden from secure snippets so it works in combat.
local wheel = CreateFrame("Frame", Name("Wheel"), UIParent, "SecureHandlerStateTemplate, SecureHandlerShowHideTemplate")
wheel:SetPoint("CENTER")
wheel:SetFrameStrata("DIALOG")
wheel:SetClampedToScreen(true)
wheel:SetMovable(true)
wheel:Hide()
SecureHandlerSetFrameRef(wheel, "coordinator", coordinator)
wheel:SetAttribute("rb-bar", bar)

local sensor = CreateFrame("Frame", Name("Sensor"), wheel, "SecureFrameTemplate")
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

local cancelHighlight = wheel:CreateTexture(nil, "ARTWORK", nil, 4)
cancelHighlight:SetPoint("CENTER")
cancelHighlight:SetColorTexture(1, 0.25, 0.2, 0.3)
cancelHighlight:SetBlendMode("ADD")
CreateCircleMask(wheel, cancelHighlight)
cancelHighlight:Hide()

-- Shows the pointing direction, since Hold mode can hide the cursor.
local pointer = wheel:CreateTexture(nil, "OVERLAY", nil, 1)
pointer:SetTexture(POINTER)
pointer:SetSize(16, 16)
pointer:SetVertexColor(1, 0.82, 0.3, 0.9)
pointer:Hide()

local title = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("CENTER")
title:SetWordWrap(true)

local description = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
description:SetPoint("TOP", title, "BOTTOM", 0, -4)
description:SetWordWrap(true)
description:SetMaxLines(5)
description:Hide()

-- Room the center needs before a description fits.
local MIN_DESCRIPTION_WIDTH = 100

local slots = {}

for index = 1, ns.NUM_SLOTS do
	local button = CreateFrame("Button", Name("Slot" .. index), wheel, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("type", "action")

	ns.Visuals.CreateSlot(button, wheel)

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
local selector = CreateFrame("Button", Name("Selector"), wheel, "SecureActionButtonTemplate")
selector:SetAllPoints()
selector:SetFrameLevel(wheel:GetFrameLevel() + 16)
selector:RegisterForClicks("AnyUp")
selector:SetAttribute("type", "action")
selector:Hide()
SecureHandlerWrapScript(selector, "OnClick", wheel, [[
	local x, y = owner:GetFrameRef("sensor"):GetMousePosition()
	if not x then
		return false
	end
	local size = owner:GetAttribute("rb-sensor")
	local dx, dy = (x - 0.5) * size, (y - 0.5) * size
	local outer = owner:GetAttribute("rb-outer")
	if dx * dx + dy * dy > outer * outer then
		return false
	end
]] .. PICK_DIRECTION .. [[
	if not index then
		owner:Hide()
		return false
	end
	self:SetAttribute("action", owner:GetFrameRef("slot" .. index):GetAttribute("action"))
	return nil, "close"
]], [[ owner:Hide() ]])

local ActionName = ns.Visuals.ActionName
local ActionDescription = ns.Visuals.ActionDescription

-- Insecure mirror of PICK_DIRECTION, for highlight and the center label.
-- Returns the slot index (nil in the dead zone) and the pointing angle.
local function DirectionIndex(bounded)
	local centerX, centerY = wheel:GetCenter()
	if not centerX then
		return nil
	end
	local scale = wheel:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	local dx, dy = cursorX / scale - centerX, cursorY / scale - centerY
	local dead = wheel:GetAttribute("rb-dead")
	if dx * dx + dy * dy < dead * dead then
		return nil, nil, true
	end
	local outer = wheel:GetAttribute("rb-outer")
	if bounded and dx * dx + dy * dy > outer * outer then
		return nil
	end
	local index = ns.DirectionIndex(dx, dy, dead, wheel:GetAttribute("rb-count"))
	if index then
		return index, math.atan2(dy, dx)
	end
end

local CANCEL_TEXT = CANCEL or "Cancel"

local selected, cancelHot
local function SetSelected(index, hot)
	hot = (not index and hot) and true or false
	if index == selected and hot == cancelHot then
		return
	end
	cancelHot = hot
	cancelHighlight:SetShown(hot)
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
		local hasAction = C_ActionBar.HasAction(action)
		title:SetText(hasAction and ActionName(action) or EMPTY)
		title:SetTextColor(1, 1, 1)
		local text = hasAction and wheel.showDescription and ActionDescription(action)
		description:SetText(text or "")
		description:SetShown(text and true or false)
	else
		title:SetText(CANCEL_TEXT)
		if hot then
			title:SetTextColor(1, 0.45, 0.4)
		else
			title:SetTextColor(0.6, 0.6, 0.6)
		end
		description:Hide()
	end
	title:ClearAllPoints()
	if description:IsShown() then
		title:SetPoint("BOTTOM", wheel, "CENTER", 0, 6)
	else
		title:SetPoint("CENTER")
	end
end

local function HoveredSlot()
	for index, button in ipairs(slots) do
		if button:IsShown() and button:IsMouseOver() then
			return index
		end
	end
end

local cursorHidden = false

wheel:SetScript("OnUpdate", function()
	local hold = wheel:GetAttribute("rb-mode") == "hold"
	local slice = wheel:GetAttribute("rb-shape") == "slice"
	local index, angle, inDeadZone, _
	if hold then
		index, angle = DirectionIndex()
	elseif slice then
		if selector:IsMouseOver() then
			index, _, inDeadZone = DirectionIndex(true)
		end
	else
		index = HoveredSlot()
	end
	SetSelected(index, hold or inDeadZone or (not slice and Wheel.cancelButton:IsMouseOver()))

	if angle then
		local distance = wheel:GetAttribute("rb-dead") + 10
		pointer:ClearAllPoints()
		pointer:SetPoint("CENTER", wheel, "CENTER", distance * math.cos(angle), distance * math.sin(angle))
		pointer:SetRotation(angle - math.pi / 2)
		pointer:Show()
	else
		pointer:Hide()
	end

	-- The game restores its cursor as the mouse moves, so reapply each frame.
	if hold and wheel.hideCursor and not Wheel:IsPreviewing() then
		SetCursor(BLANK_CURSOR)
		cursorHidden = true
	end
end)

-- Center "Cancel": clicking it closes the wheel. In Hold mode, releasing with
-- the cursor in the center does the same (PICK_DIRECTION returns nil there).
local cancelButton = CreateFrame("Button", Name("Cancel"), wheel, "SecureHandlerClickTemplate")
cancelButton:SetPoint("CENTER")
cancelButton:SetFrameLevel(wheel:GetFrameLevel() + 15)
cancelButton:RegisterForClicks("AnyUp")
SecureHandlerSetFrameRef(cancelButton, "wheel", wheel)
cancelButton:SetAttribute("_onclick", [[ self:GetFrameRef("wheel"):Hide() ]])
Wheel.cancelButton = cancelButton

-- Position on every open, so "cursor" follows the mouse even in combat.
wheel:SetAttribute("_onshow", [[
	local coordinator = self:GetFrameRef("coordinator")
	coordinator:SetAttribute("current", self)
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
	self:GetFrameRef("trigger"):SetAttribute("rb-armed", false)
	local coordinator = self:GetFrameRef("coordinator")
	if coordinator:GetAttribute("current") == self then
		coordinator:SetAttribute("current", nil)
	end
]])

-- The hotkey clicks this button. Toggle mode opens and closes the wheel on key
-- down. Hold mode opens on key down and, on key up, runs the slot in the
-- cursor's direction through this button's own secure action.
local trigger = CreateFrame("Button", Name("Trigger"), UIParent, "SecureActionButtonTemplate")
trigger:RegisterForClicks("AnyDown", "AnyUp")
trigger:SetAttribute("useOnKeyDown", false)
SecureHandlerSetFrameRef(wheel, "trigger", trigger)
SecureHandlerWrapScript(trigger, "OnClick", wheel, [[
	local mode = owner:GetAttribute("rb-mode")
	if down then
		if self:GetAttribute("rb-down") then return false end
		self:SetAttribute("rb-down", true)
	else
		self:SetAttribute("rb-down", false)
	end
	if owner:GetAttribute("rb-preview") then return false end
	if mode ~= "hold" then
		if down then
			if owner:IsShown() then
				owner:Hide()
			else
				owner:GetFrameRef("coordinator"):RunAttribute("open", owner:GetAttribute("rb-bar"))
			end
		end
		return false
	end
	if down then
		owner:GetFrameRef("coordinator"):RunAttribute("open", owner:GetAttribute("rb-bar"))
		self:SetAttribute("rb-armed", true)
		return false
	end
	if not self:GetAttribute("rb-armed") or not owner:IsShown() then
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
	if ns.GetBarConfig(bar).position == "fixed" and not InCombatLockdown() then
		wheel:StartMoving()
	end
end)
overlay:SetScript("OnMouseUp", function()
	wheel:StopMovingOrSizing()
	local config = ns.GetBarConfig(bar)
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
	local icon = button.actionIcon
	local action = button:GetAttribute("action")
	if not action or not C_ActionBar.HasAction(action) then
		icon:SetTexture(EMPTY_SLOT)
		icon:SetVertexColor(1, 1, 1, 0.4)
		button.cooldown:Clear()
		button.count:SetText("")
		return
	end

	icon:SetTexture(C_ActionBar.GetActionTexture(action))
	local usable, lackingResources = C_ActionBar.IsUsableAction(action)
	if usable then
		icon:SetVertexColor(1, 1, 1, 1)
	elseif lackingResources then
		icon:SetVertexColor(0.5, 0.5, 1, 1)
	else
		icon:SetVertexColor(0.4, 0.4, 0.4, 1)
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

	hub:SetSize(deadZone * 2, deadZone * 2)
	hub:SetAlpha(math.max(config.backdropAlpha, 0.6))
	cancelHighlight:SetSize(deadZone * 2, deadZone * 2)
	cancelButton:SetSize(deadZone * 2, deadZone * 2)

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
		ns.Visuals.LayoutSlot(button, wheel, config, index)
		local shown = index <= count
		if shown then
			button:EnableMouse(not slice)
			if round then
				button.cooldown:SetSwipeTexture(CIRCLE_MASK)
			else
				button.cooldown:SetSwipeTexture(SQUARE_SWIPE)
			end
			button.roundHighlight:SetShown(shape == "circle")
			button.squareHighlight:SetShown(not round)
		end
	end

	selector:SetShown(slice)

	wheel:SetAttribute("rb-count", count)
	wheel:SetAttribute("rb-shape", shape)
	wheel:SetAttribute("rb-dead", deadZone)
	wheel:SetAttribute("rb-outer", outer)
	local centerWidth = math.max(deadZone * 2 - 8, 60)
	title:SetWidth(centerWidth)
	description:SetWidth(centerWidth)
	wheel.showDescription = config.showDescription and centerWidth >= MIN_DESCRIPTION_WIDTH
	wheel.hideCursor = config.hideCursor
end

-- Out of combat only (see ns.ApplyWhenSafe).
local applying, boundKey = false, nil
function Wheel:Apply()
	local config = ns.GetBarConfig(bar)

	applying = true
	wheel:Hide()
	trigger:SetAttribute("rb-armed", false)
	if config.key ~= boundKey then
		trigger:SetAttribute("rb-down", false)
		boundKey = config.key
	end
	for index, button in ipairs(slots) do
		button:SetAttribute("action", ns.SlotFor(bar, index))
	end
	Layout(config)
	wheel:SetAttribute("rb-mode", config.mode)
	wheel:SetAttribute("rb-position", config.position)
	wheel:SetAttribute("rb-x", config.x)
	wheel:SetAttribute("rb-y", config.y)
	SetSelected(nil, false)

	ClearOverrideBindings(trigger)
	if config.key then
		SetOverrideBindingClick(trigger, true, config.key, Name("Trigger"), "LeftButton")
	end

	if previewing then
		overlayText:SetText(config.position == "fixed" and "Preview: drag to place" or "Preview")
		wheel:Show()
	end
	self:Refresh()
	applying = false
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
	wheel:SetAttribute("rb-preview", previewing)
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
	SetSelected(nil, false)
	pointer:Hide()
	if cursorHidden then
		cursorHidden = false
		ResetCursor()
	end
end)

wheel:HookScript("OnHide", function()
	if previewing and not applying and not InCombatLockdown() then
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
Wheel.frame = wheel
return Wheel
end

for bar = 1, 8 do
	Wheels.instances[bar] = CreateWheel(bar)
	SecureHandlerSetFrameRef(coordinator, "wheel" .. bar, Wheels.instances[bar].frame)
end

function Wheels:Apply()
	local preview = self:IsPreviewing()
	for bar = 1, 8 do self.instances[bar].frame:Hide() end
	if self.previewBar and self.previewBar ~= ns.db.activeBar then
		self.instances[self.previewBar]:SetPreview(false)
		self.previewBar = nil
	end
	for bar = 1, 8 do
		self.instances[bar]:Apply()
	end
	open:SetAttribute("rb-bar", ns.db.activeBar)
	if preview then self:SetPreview(true) end
end

function Wheels:IsPreviewing()
	return self.previewBar ~= nil and self.instances[self.previewBar]:IsPreviewing()
end

function Wheels:SetPreview(enabled)
	if InCombatLockdown() then return end
	if self.previewBar and (not enabled or self.previewBar ~= ns.db.activeBar) then
		self.instances[self.previewBar]:SetPreview(false)
		self.previewBar = nil
	end
	if enabled then
		for bar = 1, 8 do
			if bar ~= ns.db.activeBar then self.instances[bar].frame:Hide() end
		end
		self.previewBar = ns.db.activeBar
		self.instances[self.previewBar]:SetPreview(true)
	end
end
