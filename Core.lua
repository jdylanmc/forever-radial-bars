local _, ns = ...

ns.NUM_SLOTS = 12
ns.DEFAULT_BAR = 2

-- Edit Mode "Action Bar N" to action page; slot = (page - 1) * 12 + index.
-- Pages from Blizzard_ActionBar/Shared/MultiActionBars.lua (Forever 1.60.1).
ns.BARS = {
	[2] = { name = "Action Bar 2", page = 6 },
	[3] = { name = "Action Bar 3", page = 5 },
	[4] = { name = "Action Bar 4", page = 3 },
	[5] = { name = "Action Bar 5", page = 4 },
	[6] = { name = "Action Bar 6", page = 13 },
	[7] = { name = "Action Bar 7", page = 14 },
	[8] = { name = "Action Bar 8", page = 15 },
}

ns.MODES = { toggle = true, hold = true }
ns.POSITIONS = { center = true, cursor = true }

function ns.SlotFor(bar, index)
	return (ns.BARS[bar].page - 1) * ns.NUM_SLOTS + index
end

function ns.GetBarConfig(bar)
	local bars = ns.db.bars
	bars[bar] = bars[bar] or {}
	local config = bars[bar]
	if not ns.MODES[config.mode] then
		config.mode = "toggle"
	end
	if not ns.POSITIONS[config.position] then
		config.position = "center"
	end
	return config
end

local function InitDB()
	RadialBarsDB = RadialBarsDB or {}
	local db = RadialBarsDB
	db.version = 1
	db.bars = db.bars or {}
	if not ns.BARS[db.activeBar] then
		db.activeBar = ns.DEFAULT_BAR
	end
	ns.db = db
end

local pendingApply = false

-- Secure attributes and bindings cannot change in combat; defer until it ends.
function ns.ApplyWhenSafe()
	if InCombatLockdown() then
		pendingApply = true
		return false
	end
	pendingApply = false
	ns.Wheel:Apply()
	return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "RadialBars" then
		InitDB()
	elseif event == "PLAYER_LOGIN" then
		ns.ApplyWhenSafe()
	elseif event == "PLAYER_REGEN_ENABLED" and pendingApply then
		ns.ApplyWhenSafe()
	end
end)
