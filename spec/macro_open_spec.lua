local wow = require("spec.helpers.wow")

describe("macro opening", function()
	local ns, open, wheel

	before_each(function()
		wow.Reset()
		ns = wow.Load("Core.lua", "Changelog.lua", "Visuals.lua", "Wheel.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		open, wheel = wow.named.RadialBarsOpen, wow.named.RadialBarsWheel
	end)

	for _, mode in ipairs({ "toggle", "hold" }) do
		it("opens the edited " .. mode .. " wheel without acting on macro release or repeat", function()
			local config = ns.GetBarConfig(2)
			config.mode, config.position, config.key = mode, "cursor", "K"
			ns.ApplyWhenSafe()
			wow.inCombat, wow.enforceCombat = true, true
			wow.Click(open, false)
			local point = wheel.calls.SetPoint
			wow.Click(open, false)
			wow.Key("K", false)
			assert.is_true(wheel:IsShown())
			assert.same(point, wheel.calls.SetPoint)
			assert.same({}, wow.actions)
			assert.is_false(wow.named.RadialBarsTrigger:GetAttribute("rb-armed"))
			assert.equal("SecureHandlerClickTemplate", open.template)
			assert.is_nil(open.scripts.OnClick)
		end)
	end

	it("targets the selected edit bar after deferred settings apply", function()
		ns.ApplyWhenSafe()
		wow.inCombat = true
		ns.db.activeBar = 8
		assert.is_false(ns.ApplyWhenSafe())
		wow.Click(open, false)
		assert.is_true(wheel:IsShown())
		assert.is_false(ns.Wheel.instances[8].frame:IsShown())
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		wow.Click(open, false)
		assert.is_false(wheel:IsShown())
		assert.is_true(ns.Wheel.instances[8].frame:IsShown())
		assert.same({}, wow.actions)
	end)
end)
