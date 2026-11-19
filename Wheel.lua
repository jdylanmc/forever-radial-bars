local _, ns = ...

local RADIUS = 110
local BUTTON_SIZE = 44
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local EMPTY_SLOT = "Interface\\Buttons\\UI-EmptySlot-Disabled"

local Wheel = {}
ns.Wheel = Wheel

local function AddCircleMask(parent, texture)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
end

-- Protected header: shown and hidden from secure snippets so it works in combat.
local wheel = CreateFrame("Frame", "RadialBarsWheel", UIParent, "SecureHandlerStateTemplate, SecureHandlerShowHideTemplate")
wheel:SetSize((RADIUS + BUTTON_SIZE) * 2, (RADIUS + BUTTON_SIZE) * 2)
wheel:SetPoint("CENTER")
wheel:SetFrameStrata("DIALOG")
wheel:Hide()

local background = wheel:CreateTexture(nil, "BACKGROUND")
background:SetPoint("CENTER")
background:SetSize((RADIUS + BUTTON_SIZE) * 2 - 8, (RADIUS + BUTTON_SIZE) * 2 - 8)
background:SetColorTexture(0, 0, 0, 0.55)
AddCircleMask(wheel, background)

local title = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("CENTER")

local slots = {}

for index = 1, ns.NUM_SLOTS do
	local button = CreateFrame("Button", "RadialBarsSlot" .. index, wheel, "SecureActionButtonTemplate")
	local angle = math.rad(90 - (index - 1) * (360 / ns.NUM_SLOTS))
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetPoint("CENTER", wheel, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("type", "action")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	AddCircleMask(button, button.icon)

	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button.cooldown:SetSwipeTexture(CIRCLE_MASK)

	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.25)
	AddCircleMask(button, highlight)

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

-- Escape closes the wheel; bound only while the wheel is open.
local close = CreateFrame("Button", "RadialBarsClose", UIParent, "SecureHandlerClickTemplate")
close:RegisterForClicks("AnyUp")
SecureHandlerSetFrameRef(close, "wheel", wheel)
close:SetAttribute("_onclick", [[ self:GetFrameRef("wheel"):Hide() ]])

wheel:SetAttribute("_onshow", [[
	self:SetBindingClick(true, "ESCAPE", "RadialBarsClose")
]])
wheel:SetAttribute("_onhide", [[
	self:ClearBindings()
]])

-- The hotkey clicks this button. Toggle mode opens and closes the wheel on key
-- down. Hold mode opens on key down and, on key up, runs the slot under the
-- cursor through this button's own secure action.
local trigger = CreateFrame("Button", "RadialBarsTrigger", UIParent, "SecureActionButtonTemplate")
trigger:RegisterForClicks("AnyDown", "AnyUp")
trigger:SetAttribute("useOnKeyDown", false)
SecureHandlerWrapScript(trigger, "OnClick", wheel, [[
	local mode = owner:GetAttribute("rb-mode")
	if mode == "hold" then
		if down then
			owner:Show()
			return false
		end
		local action
		if owner:IsShown() then
			for index = 1, 12 do
				local slot = owner:GetFrameRef("slot" .. index)
				if slot:IsUnderMouse() then
					action = slot:GetAttribute("action")
					break
				end
			end
			owner:Hide()
		end
		if not action then
			return false
		end
		self:SetAttribute("type", "action")
		self:SetAttribute("action", action)
		return
	end
	if down then
		if owner:IsShown() then
			owner:Hide()
		else
			owner:Show()
		end
	end
	return false
]])

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
		UpdateSlot(button)
	end
end

-- Out of combat only (see ns.ApplyWhenSafe).
function Wheel:Apply()
	local bar = ns.db.activeBar
	local config = ns.GetBarConfig(bar)

	wheel:Hide()
	for index, button in ipairs(slots) do
		button:SetAttribute("action", ns.SlotFor(bar, index))
	end
	wheel:SetAttribute("rb-mode", config.mode)
	title:SetText(ns.BARS[bar].name)

	ClearOverrideBindings(trigger)
	if config.key then
		SetOverrideBindingClick(trigger, true, config.key, "RadialBarsTrigger", "LeftButton")
	end

	self:Refresh()
end

wheel:HookScript("OnShow", function()
	Wheel:Refresh()
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
