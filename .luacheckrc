std = "lua51"
max_line_length = false
codes = true
self = false
exclude_files = { "node_modules/", ".luarocks/" }

-- Globals the addon defines.
globals = {
	"RadialBarsDB",
	"SLASH_RADIALBARS1",
	"SlashCmdList",
}

-- WoW: Forever client API used by the addon.
read_globals = {
	"C_ActionBar", "C_AddOns", "C_Item", "C_Spell", "C_TooltipInfo",
	"CANCEL", "EMPTY",
	"ClearOverrideBindings", "CreateFrame", "GameTooltip", "GameTooltip_Hide",
	"GetActionInfo", "GetBindingAction", "GetBindingName", "GetBindingText",
	"GetCursorPosition", "InCombatLockdown", "IsAltKeyDown", "IsControlKeyDown",
	"IsShiftKeyDown", "MinimalSliderWithSteppersMixin", "ResetCursor",
	"SecureHandlerSetFrameRef", "SecureHandlerWrapScript", "SetCursor",
	"SetOverrideBindingClick", "Settings", "UIParent",
}

files["spec/"] = {
	std = "+busted",
	globals = { "_G", "RadialBarsDB" },
}
