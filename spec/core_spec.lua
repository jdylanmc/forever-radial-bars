local wow = require("spec.helpers.wow")

describe("Core", function()
	local ns

	before_each(function()
		wow.Reset()
		ns = wow.Load("Core.lua")
		ns.Wheel = { Apply = spy.new(function() end), SetPreview = function() end }
		wow.Fire("ADDON_LOADED", "RadialBars")
	end)

	describe("SlotFor", function()
		it("maps Edit Mode bars to their action pages", function()
			assert.equal(61, ns.SlotFor(2, 1))
			assert.equal(72, ns.SlotFor(2, 12))
			assert.equal(25, ns.SlotFor(4, 1))
			assert.equal(156, ns.SlotFor(6, 12))
			assert.equal(180, ns.SlotFor(8, 12))
		end)
	end)

	describe("saved settings", function()
		it("creates defaults on first load", function()
			assert.is_table(RadialBarsDB)
			assert.equal(2, ns.db.activeBar)
			local config = ns.GetBarConfig(2)
			assert.same({ "toggle", "center", "square" }, { config.mode, config.position, config.shape })
			assert.equal(12, config.count)
			assert.is_true(config.showDescription)
			assert.is_true(config.hideCursor)
		end)

		it("never selects Action Bar 1", function()
			wow.Reset()
			_G.RadialBarsDB = { activeBar = 1 }
			ns = wow.Load("Core.lua")
			wow.Fire("ADDON_LOADED", "RadialBars")
			assert.equal(2, ns.db.activeBar)
		end)

		it("clamps numbers and repairs invalid choices", function()
			ns.db.bars[3] = { count = 40, iconSize = 1, mode = "bogus", shape = "hexagon", position = 7, radius = "x" }
			local config = ns.GetBarConfig(3)
			assert.equal(12, config.count)
			assert.equal(ns.LIMITS.iconSize[2], config.iconSize)
			assert.equal(ns.LIMITS.radius[1], config.radius)
			assert.same({ "toggle", "square", "center" }, { config.mode, config.shape, config.position })
		end)

		it("keeps valid choices", function()
			ns.db.bars[5] = { count = 6, mode = "hold", shape = "slice", position = "cursor", showDescription = false }
			local config = ns.GetBarConfig(5)
			assert.same({ 6, "hold", "slice", "cursor", false },
				{ config.count, config.mode, config.shape, config.position, config.showDescription })
		end)
	end)

	describe("ApplyWhenSafe", function()
		it("applies immediately out of combat", function()
			assert.is_true(ns.ApplyWhenSafe())
			assert.spy(ns.Wheel.Apply).was.called(1)
		end)

		it("defers until combat ends", function()
			wow.inCombat = true
			assert.is_false(ns.ApplyWhenSafe())
			assert.spy(ns.Wheel.Apply).was.called(0)
			wow.inCombat = false
			wow.Fire("PLAYER_REGEN_ENABLED")
			assert.spy(ns.Wheel.Apply).was.called(1)
		end)
	end)

	describe("FormatChangelog", function()
		it("lists releases, sections, and entries", function()
			local text = ns.FormatChangelog({
				{ version = "0.0.2", sections = { { title = "Patch Changes", entries = { "Fix A", "Fix B" } } } },
				{ version = "0.0.1", sections = { { title = "Initial release", entries = { "Wheel" } } } },
			})
			assert.truthy(text:find("0.0.2", 1, true))
			assert.truthy(text:find("  - Fix B", 1, true))
			assert.truthy(text:find("0.0.2") < text:find("0.0.1"))
		end)

		it("handles an empty changelog", function()
			assert.equal("No changes recorded.", ns.FormatChangelog({}))
		end)
	end)
end)
