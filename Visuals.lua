local _, ns = ...

local Visuals = {}
ns.Visuals = Visuals

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WEDGE_PATH = "Interface\\AddOns\\RadialBars\\Media\\Wedge"
local SLICE_HUB_MASK = "Interface\\AddOns\\RadialBars\\Media\\SliceHubMask"

function Visuals.CircleMask(parent, texture)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return mask
end

function Visuals.SlotAngle(index, count)
	return 90 - (index - 1) * (360 / count)
end

function Visuals.CreateSlot(button, parent)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.iconMask = Visuals.CircleMask(button, button.icon)
	button.sliceIcon = parent:CreateTexture(nil, "ARTWORK")
	button.sliceIcon:Hide()
	button.sliceMask = parent:CreateMaskTexture()
	button.sliceMask:SetPoint("CENTER")
	button.sliceIcon:AddMaskTexture(button.sliceMask)
	button.sliceHubMask = parent:CreateMaskTexture()
	button.sliceHubMask:SetPoint("CENTER")
	button.sliceHubMask:SetTexture(SLICE_HUB_MASK, "CLAMP", "CLAMP")
	button.sliceIcon:AddMaskTexture(button.sliceHubMask)
	button.actionIcon = button.icon
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetAtlas("UI-HUD-ActionBar-IconFrame")
end

-- Fit upright artwork to the sector's bounding square, not to an action button.
local function SliceBounds(angle, halfStep, inner, outer)
	local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
	local function Include(degrees, radius)
		local radians = math.rad(degrees)
		local x, y = radius * math.cos(radians), radius * math.sin(radians)
		left, right = math.min(left, x), math.max(right, x)
		bottom, top = math.min(bottom, y), math.max(top, y)
	end
	Include(angle - halfStep, inner)
	Include(angle + halfStep, inner)
	Include(angle - halfStep, outer)
	Include(angle + halfStep, outer)
	for cardinal = 0, 270, 90 do
		if math.abs((cardinal - angle + 180) % 360 - 180) <= halfStep then
			Include(cardinal, outer)
		end
	end
	return (left + right) / 2, (bottom + top) / 2, math.max(right - left, top - bottom)
end

-- Visual mutations only; callers retain all secure attributes and interaction.
function Visuals.LayoutSlot(button, parent, config, index)
	local slice, round = config.shape == "slice", config.shape ~= "square"
	local shown = index <= config.count
	button:SetShown(shown)
	button.sliceIcon:SetShown(shown and slice)
	button.icon:SetShown(not slice)
	button.actionIcon = slice and button.sliceIcon or button.icon
	if not shown then return end
	local degrees = Visuals.SlotAngle(index, config.count)
	local angle = math.rad(degrees)
	button:ClearAllPoints()
	button:SetPoint("CENTER", parent, "CENTER", config.radius * math.cos(angle), config.radius * math.sin(angle))
	button:SetSize(config.iconSize, config.iconSize)
	button:SetAlpha(config.iconAlpha)
	if slice then
		local outer = config.radius + config.iconSize / 2 + config.margin
		local dead = math.max(config.radius * config.hubSize, 12)
		local x, y, size = SliceBounds(degrees, 180 / config.count, dead, outer)
		button.sliceIcon:ClearAllPoints()
		button.sliceIcon:SetPoint("CENTER", parent, "CENTER", x, y)
		button.sliceIcon:SetSize(size * config.sliceIconZoom, size * config.sliceIconZoom)
		button.sliceIcon:SetAlpha(config.iconAlpha)
		-- Zoom never moves or resizes either native mask.
		button.sliceMask:SetTexture(WEDGE_PATH .. config.count, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		button.sliceMask:SetSize(outer * 2, outer * 2)
		button.sliceMask:SetRotation(math.rad(degrees - 90))
		-- The inverse disk's UV radius is 1/4; clamped white edges keep the hole round.
		local span = outer / (2 * dead)
		button.sliceHubMask:SetSize(outer * 2, outer * 2)
		button.sliceHubMask:SetTexCoord(0.5 - span / 2, 0.5 + span / 2, 0.5 - span / 2, 0.5 + span / 2)
	end
	button.icon:RemoveMaskTexture(button.iconMask)
	if round then button.icon:AddMaskTexture(button.iconMask) end
	if round then
		button.icon:SetTexCoord(0, 1, 0, 1)
	else
		button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
	local outset = config.iconSize * 0.06
	button.border:SetShown(not round)
	button.border:ClearAllPoints()
	button.border:SetPoint("TOPLEFT", -outset, outset)
	button.border:SetPoint("BOTTOMRIGHT", outset, -outset)
end

function Visuals.ActionName(action)
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

-- Tooltip text can be secret; omit it if the read or inspection fails.
function Visuals.ActionDescription(action)
	local ok, text = pcall(function()
		local data = C_TooltipInfo.GetAction(action)
		local lines = data and data.lines
		if not lines then return nil end
		for i = #lines, 2, -1 do
			local line = lines[i].leftText
			if line and line ~= "" then return line end
		end
	end)
	return ok and text or nil
end
