local _, ns = ...

ns.NUM_SLOTS = 12
ns.DEFAULT_BAR = 2

-- Edit Mode "Action Bar N" to action page; slot = (page - 1) * 12 + index.
-- Pages from Blizzard_ActionBar/Shared/MultiActionBars.lua (Forever 1.60.1).
ns.BARS = {
	[1] = { name = "Action Bar 1 (fixed slots 1-12)", page = 1 },
	[2] = { name = "Action Bar 2", page = 6 },
	[3] = { name = "Action Bar 3", page = 5 },
	[4] = { name = "Action Bar 4", page = 3 },
	[5] = { name = "Action Bar 5", page = 4 },
	[6] = { name = "Action Bar 6", page = 13 },
	[7] = { name = "Action Bar 7", page = 14 },
	[8] = { name = "Action Bar 8", page = 15 },
}

ns.MODES = { toggle = true, hold = true }
ns.POSITIONS = { center = true, cursor = true, fixed = true }
ns.SHAPES = { square = true, circle = true, slice = true }

-- Numeric per-bar settings: default, min, max.
ns.LIMITS = {
	count = { 12, 4, 12 },
	radius = { 110, 60, 250 },
	iconSize = { 44, 24, 72 },
	margin = { 12, 0, 48 },
	hubSize = { 0.35, 0, 0.8 },
	gap = { 2, 0, 8 },
	backdropAlpha = { 0.55, 0, 1 },
	iconAlpha = { 1, 0.1, 1 },
	sliceIconZoom = { 1.15, 1, 2 },
}

-- Slot index (1 = up, clockwise) for an offset from the wheel center, or nil
-- inside the dead zone. Must match PICK_DIRECTION in Wheel.lua, which runs in
-- the restricted environment and cannot call this.
function ns.DirectionIndex(dx, dy, dead, count)
	if dx * dx + dy * dy < dead * dead then
		return nil
	end
	local step = 360 / count
	local offset = (90 - math.deg(math.atan2(dy, dx))) % 360
	return math.floor((offset + step / 2) / step) % count + 1
end

function ns.AssignBarKey(bar, key)
	local config = ns.GetBarConfig(bar)
	if key then
		for other = 1, 8 do
			local previous = ns.db.bars[other]
			if other ~= bar and previous and previous.key == key then
				previous.key = nil
			end
		end
	end
	config.key = key
end

local function DeepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = DeepCopy(child)
	end
	return copy
end

function ns.CopyBarSettings(source, destination)
	if source == destination or not ns.BARS[source] or not ns.BARS[destination] then
		return false
	end
	local from, to = ns.GetBarConfig(source), ns.GetBarConfig(destination)
	local keys = {
		"mode", "position", "shape", "x", "y", "showDescription", "hideCursor",
	}
	for key in pairs(ns.LIMITS) do keys[#keys + 1] = key end
	for _, key in ipairs(keys) do
		to[key] = DeepCopy(from[key])
	end
	ns.ApplyWhenSafe()
	if ns.OnSettingsChanged then ns.OnSettingsChanged() end
	return true
end

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
	if not ns.SHAPES[config.shape] then
		config.shape = "square"
	end
	for key, limit in pairs(ns.LIMITS) do
		local value = tonumber(config[key]) or limit[1]
		config[key] = math.min(limit[3], math.max(limit[2], value))
	end
	if config.showDescription == nil then
		config.showDescription = true
	end
	if config.hideCursor == nil then
		config.hideCursor = true
	end
	config.x = tonumber(config.x) or 0
	config.y = tonumber(config.y) or 0
	return config
end

local GOLD = "|cffffd100"
local GREY = "|cffa0a0a0"
local RESET = "|r"

-- Display text for the settings Changelog page, newest release first.
function ns.FormatChangelog(changelog)
	local lines = {}
	for _, release in ipairs(changelog or {}) do
		lines[#lines + 1] = GOLD .. release.version .. RESET
		for _, section in ipairs(release.sections) do
			lines[#lines + 1] = GREY .. section.title .. RESET
			for _, entry in ipairs(section.entries) do
				lines[#lines + 1] = "  - " .. entry
			end
		end
		lines[#lines + 1] = ""
	end
	if #lines == 0 then
		return "No changes recorded."
	end
	return table.concat(lines, "\n")
end

local function InitDB()
	RadialBarsDB = RadialBarsDB or {}
	local db = RadialBarsDB
	db.bars = db.bars or {}
	if not ns.BARS[db.activeBar] then
		db.activeBar = ns.DEFAULT_BAR
	end
	ns.db = db
	-- The old selected bar was the only operational binding. Keep its ownership
	-- when upgrading duplicate keys; otherwise the lowest bar wins.
	local owners = {}
	local selected = db.activeBar
	local selectedKey = ns.GetBarConfig(selected).key
	if selectedKey then owners[selectedKey] = selected end
	for bar = 1, 8 do
		local config = ns.GetBarConfig(bar)
		if config.key then
			if owners[config.key] and owners[config.key] ~= bar then
				config.key = nil
			else
				owners[config.key] = bar
			end
		end
	end
	db.version = 2
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
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "RadialBars" then
		InitDB()
	elseif event == "PLAYER_LOGIN" then
		ns.ApplyWhenSafe()
	elseif event == "PLAYER_REGEN_ENABLED" and pendingApply then
		ns.ApplyWhenSafe()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Fires just before lockdown, while the preview can still be hidden.
		ns.Wheel:SetPreview(false)
	end
end)
