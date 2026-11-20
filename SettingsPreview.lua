local _, ns = ...

local WEDGE_PATH = "Interface\\AddOns\\RadialBars\\Media\\Wedge"
local EMPTY_SLOT = "Interface\\Buttons\\UI-EmptySlot-Disabled"

-- An ordinary frame, deliberately unrelated to the protected wheel/buttons.
function ns.CreateSettingsPreview(parent, viewport)
	local preview = CreateFrame("Frame", nil, parent)
	preview:EnableMouse(true)
	local surface = CreateFrame("Frame", nil, preview)
	surface:SetPoint("CENTER")
	surface:EnableMouse(false)
	local background = surface:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("CENTER")
	background:SetColorTexture(0, 0, 0, 1)
	ns.Visuals.CircleMask(surface, background)
	local slots, wedges, highlights, dividers = {}, {}, {}, {}
	for index = 1, ns.NUM_SLOTS do
		local wedge = surface:CreateTexture(nil, "BORDER")
		wedge:SetPoint("CENTER")
		wedge:SetVertexColor(0.08, 0.08, 0.1)
		wedges[index] = wedge
		local highlight = surface:CreateTexture(nil, "ARTWORK", nil, 1)
		highlight:SetPoint("CENTER")
		highlight:SetBlendMode("ADD")
		highlight:SetVertexColor(1, 0.82, 0.3, 0.35)
		highlights[index] = highlight
		local line = surface:CreateTexture(nil, "ARTWORK", nil, 2)
		line:SetColorTexture(0, 0, 0, 0.9)
		dividers[index] = line
		local slot = CreateFrame("Frame", nil, surface)
		slot:EnableMouse(false)
		ns.Visuals.CreateSlot(slot, surface)
		slot.highlight = slot:CreateTexture(nil, "OVERLAY", nil, 2)
		slot.highlight:SetAllPoints()
		slot.highlight:SetBlendMode("ADD")
		slots[index] = slot
	end
	local hub = surface:CreateTexture(nil, "ARTWORK", nil, 3)
	hub:SetPoint("CENTER")
	hub:SetColorTexture(0.03, 0.03, 0.04, 1)
	ns.Visuals.CircleMask(surface, hub)
	local cancel = surface:CreateTexture(nil, "ARTWORK", nil, 4)
	cancel:SetPoint("CENTER")
	cancel:SetColorTexture(1, 0.25, 0.2, 0.3)
	ns.Visuals.CircleMask(surface, cancel)
	local title = surface:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetWordWrap(true)
	local description = surface:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOP", title, "BOTTOM", 0, -4)
	description:SetWordWrap(true)
	description:SetMaxLines(5)
	local config, bar, selected, cancelHot, outer, dead

	local function Select(index, hot)
		selected, cancelHot = index, hot
		for i = 1, ns.NUM_SLOTS do
			highlights[i]:SetShown(i == index and config.shape == "slice")
			slots[i].highlight:SetShown(i == index and config.shape ~= "slice")
		end
		cancel:SetShown(hot and true or false)
		description:Hide()
		title:ClearAllPoints()
		title:SetPoint("CENTER", surface, "CENTER")
		if index then
			local action = ns.SlotFor(bar, index)
			local hasAction = C_ActionBar.HasAction(action)
			local name = hasAction and ns.Visuals.ActionName(action)
			title:SetText(name or ((hasAction and "Slot " or "Empty slot ") .. index))
			if hasAction and config.showDescription and math.max(dead * 2 - 8, 60) >= 100 then
				local text = ns.Visuals.ActionDescription(action)
				description:SetText(text or "")
				description:SetShown(text and true or false)
				if text then
					title:ClearAllPoints()
					title:SetPoint("BOTTOM", surface, "CENTER", 0, 6)
				end
			end
		else
			title:SetText(hot and (CANCEL or "Cancel") or "Hover to inspect")
		end
	end

	function preview:Reset()
		if config then Select(nil, false) end
	end

	function preview:Layout(width)
		if not outer then return end
		local size = math.max(1, math.min(width, 320))
		local extent = outer
		if config.shape == "square" then
			local border = config.iconSize * 0.06
			extent = math.max(extent, config.radius + config.iconSize / 2 + border)
		end
		self:SetHeight(size)
		surface:SetScale(size / (extent * 2))
		self:Reset()
	end

	function preview:Refresh()
		if not ns.db then return end
		bar = ns.db.activeBar
		config = ns.GetBarConfig(bar)
		outer = config.radius + config.iconSize / 2 + config.margin
		dead = math.max(config.radius * config.hubSize, 12)
		surface:SetSize(outer * 2, outer * 2)
		background:SetSize(outer * 2, outer * 2)
		background:SetAlpha(config.backdropAlpha)
		background:SetShown(config.shape ~= "slice" and config.backdropAlpha > 0)
		hub:SetSize(dead * 2, dead * 2)
		hub:SetAlpha(math.max(config.backdropAlpha, 0.6))
		cancel:SetSize(dead * 2, dead * 2)
		title:SetWidth(math.max(dead * 2 - 8, 60))
		description:SetWidth(math.max(dead * 2 - 8, 60))
		for index, slot in ipairs(slots) do
			ns.Visuals.LayoutSlot(slot, surface, config, index)
			local action = ns.SlotFor(bar, index)
			local hasAction = C_ActionBar.HasAction(action)
			slot.actionIcon:SetTexture(hasAction and C_ActionBar.GetActionTexture(action) or EMPTY_SLOT)
			slot.actionIcon:SetVertexColor(1, 1, 1, hasAction and 1 or 0.4)
			local slice = config.shape == "slice" and index <= config.count
			local degrees = ns.Visuals.SlotAngle(index, config.count)
			for _, texture in ipairs({ wedges[index], highlights[index] }) do
				texture:SetTexture(WEDGE_PATH .. config.count)
				texture:SetSize(outer * 2, outer * 2)
				texture:SetRotation(math.rad(degrees - 90))
			end
			wedges[index]:SetShown(slice)
			wedges[index]:SetAlpha(config.backdropAlpha)
			local line = dividers[index]
			line:SetShown(slice and config.gap > 0)
			local angle = math.rad(degrees + 180 / config.count)
			local hubRadius = config.radius * config.hubSize
			local length = outer - hubRadius
			local middle = hubRadius + length / 2
			line:ClearAllPoints()
			line:SetPoint("CENTER", surface, "CENTER", middle * math.cos(angle), middle * math.sin(angle))
			line:SetSize(length, config.gap)
			line:SetRotation(angle)
			slot.highlight:RemoveMaskTexture(slot.iconMask)
			if config.shape == "circle" then
				slot.highlight:SetColorTexture(1, 0.82, 0.3, 0.35)
				slot.highlight:AddMaskTexture(slot.iconMask)
			else
				slot.highlight:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
			end
		end
		self:Layout(self:GetWidth())
	end

	preview:SetScript("OnUpdate", function(self)
		if not config then return end
		local index, hot
		if self:IsMouseOver() and viewport:IsMouseOver() then
			local x, y = GetCursorPosition()
			local cx, cy = surface:GetCenter()
			if not cx then self:Reset(); return end
			local scale = surface:GetEffectiveScale()
			local dx, dy = x / scale - cx, y / scale - cy
			local distance = dx * dx + dy * dy
			hot = distance < dead * dead
			if not hot and (config.shape ~= "slice" or distance <= outer * outer) then
				local candidate = ns.DirectionIndex(dx, dy, dead, config.count)
				if config.shape == "slice" then
					index = candidate
				else
					local angle = math.rad(ns.Visuals.SlotAngle(candidate, config.count))
					local sx, sy = dx - config.radius * math.cos(angle), dy - config.radius * math.sin(angle)
					local half = config.iconSize / 2
					if config.shape == "circle" then
						if sx * sx + sy * sy <= half * half then index = candidate end
					elseif math.abs(sx) <= half and math.abs(sy) <= half then
						index = candidate
					end
				end
			end
		end
		hot = hot and true or false
		if index ~= selected or hot ~= cancelHot then Select(index, hot) end
	end)
	preview:SetScript("OnLeave", function(self) self:Reset() end)
	preview:SetScript("OnHide", function(self) self:Reset() end)
	preview:SetScript("OnShow", function(self) self:Refresh() end)
	for _, event in ipairs({
		"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_STATE", "SPELLS_CHANGED", "UPDATE_MACROS",
		"UPDATE_SHAPESHIFT_FORM", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED",
	}) do
		preview:RegisterEvent(event)
	end
	preview:SetScript("OnEvent", function(self)
		if self:IsShown() then self:Refresh() end
	end)
	return preview
end
