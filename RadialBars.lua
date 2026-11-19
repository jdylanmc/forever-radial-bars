local addonName, RadialBars = ...

local panel = CreateFrame("Frame")

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Radial Bars")

local message = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
message:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
message:SetText("Hello, World!")

local category = Settings.RegisterCanvasLayoutCategory(panel, "Radial Bars")
Settings.RegisterAddOnCategory(category)
RadialBars.settingsCategory = category

SLASH_RADIALBARS1 = "/radialbars"
SlashCmdList.RADIALBARS = function()
	Settings.OpenToCategory(category:GetID())
end
