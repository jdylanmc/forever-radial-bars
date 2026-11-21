local wow = require("spec.helpers.wow")

describe("Hold cursor ownership", function()
	local ns, wheel

	local function Tick(area)
		wow.MoveCursor(area)
		wheel.scripts.OnUpdate()
	end

	local function Configure(mode, hidden)
		local config = ns.GetBarConfig(2)
		config.key, config.mode, config.hideCursor = "H", mode or "hold", hidden ~= false
		ns.ApplyWhenSafe()
		wheel = ns.Wheel.instances[2].frame
	end

	local function Combat()
		wow.inCombat, wow.enforceCombat = true, true
	end

	before_each(function()
		wow.Reset()
		ns = wow.Load("Core.lua", "Visuals.lua", "Wheel.lua", "SettingsPreview.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		Configure()
	end)

	it("uses a supported transparent hardware cursor over the wheel", function()
		Combat()
		wow.Key("H", true)
		Tick("wheel")
		assert.is_true(wow.cursorHidden)
		assert.not_equal("black-square", wow.cursor)
	end)

	it("owns hover across an ultrawide viewport without intercepting world clicks or changing the direction sensor", function()
		UIParent:SetSize(7680, 2160)
		Combat()
		wow.Key("H", true)
		Tick("world")
		assert.is_true(wow.cursorHidden)
		wow.WorldClick("LeftButton")
		wow.WorldClick("RightButton")
		assert.same({ "LeftButton", "RightButton" }, wow.worldClicks)
		assert.equal(4096, wheel:GetAttribute("rb-sensor"))
		assert.same({ 4096, 4096 }, wheel.refs.sensor.calls.SetSize)
		assert.same({}, wow.actions)
	end)

	for _, mode in ipairs({ "toggle", "hold-visible", "preview" }) do
		it("does not own world hover or hide the cursor for " .. mode, function()
			Configure(mode == "toggle" and "toggle" or "hold", mode ~= "hold-visible")
			if mode == "preview" then ns.Wheel:SetPreview(true) else wow.Key("H", true) end
			Tick("world")
			assert.is_false(wow.cursorHidden)
			assert.is_nil(wow.cursor)
			wow.WorldClick("RightButton")
			assert.same({ "RightButton" }, wow.worldClicks)
		end)
	end

	for _, closing in ipairs({ "release", "escape", "cancel", "slot", "switch" }) do
		it("restores the cursor and world ownership on " .. closing, function()
			ns.GetBarConfig(3).key = "T"
			ns.ApplyWhenSafe()
			Combat()
			wow.Key("H", true)
			Tick("world")
			assert.is_true(wow.cursorHidden)
			if closing == "release" then wow.Key("H", false)
			elseif closing == "escape" then wow.Key("ESCAPE", false)
			elseif closing == "cancel" then wow.Click(wow.named.RadialBarsCancel, false)
			elseif closing == "slot" then wow.Click(wheel.refs.slot1, false)
			else wow.Key("T", true) end
			assert.is_nil(wow.cursor)
			assert.is_false(wow.cursorHidden)
			SetCursor("Interface\\AddOns\\RadialBars\\Media\\Blank.blp")
			assert.is_nil(wow.cursor, "no fullscreen hover owner may survive closing")
		end)
	end

	it("retains cursor ownership during deferred edits and updates it only after combat", function()
		Combat()
		wow.Key("H", true)
		Tick("world")
		assert.is_true(wow.cursorHidden)
		ns.GetBarConfig(2).hideCursor = false
		assert.is_false(ns.ApplyWhenSafe())
		Tick("world")
		assert.is_true(wow.cursorHidden)
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		assert.is_nil(wow.cursor)
		wow.Click(wow.named.RadialBarsOpen, false)
		Tick("world")
		assert.is_false(wow.cursorHidden)
	end)

	it("transfers hidden-cursor ownership between Hold wheels without letting a stale release reset it", function()
		local other = ns.GetBarConfig(3)
		other.key, other.mode, other.hideCursor = "B", "hold", true
		ns.ApplyWhenSafe()
		Combat()
		wow.MoveCursor("world")
		wow.Key("H", true)
		assert.is_true(wow.cursorHidden, "hide immediately on open, not only after OnUpdate")
		wow.Key("B", true)
		assert.is_true(wow.cursorHidden)
		assert.equal(1, wow.cursorResets)
		wow.Key("H", false)
		assert.is_true(wow.cursorHidden)
		assert.same({}, wow.actions)
		wow.Key("B", false)
		assert.is_false(wow.cursorHidden)
		assert.equal(2, wow.cursorResets)
	end)

	it("leaves the inline preview cursor and input alone", function()
		local preview = ns.CreateSettingsPreview(UIParent, UIParent)
		preview:Refresh()
		wow.MoveCursor("world")
		preview.scripts.OnUpdate(preview)
		assert.is_nil(wow.cursor)
		assert.is_false(wow.cursorHidden)
		assert.same({}, wow.actions)
	end)
end)
