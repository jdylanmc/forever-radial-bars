local wow = require("spec.helpers.wow")

describe("copy bar settings", function()
	local ns, source, expected, applied, refreshed

	before_each(function()
		wow.Reset()
		ns = wow.Load("Core.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		source = ns.GetBarConfig(8)
		local values = {
			key = "SOURCE", mode = "hold", position = "fixed", shape = "slice", x = 123, y = -456,
			count = 5, radius = 235, iconSize = 66, margin = 44, hubSize = 0.75, gap = 7,
			sliceIconZoom = 1.95, backdropAlpha = 0.15, iconAlpha = 0.25,
			showDescription = false, hideCursor = false,
		}
		for key, value in pairs(values) do source[key] = value end
		expected = values
		applied, refreshed = 0, 0
		ns.Wheel = { Apply = function() applied = applied + 1 end }
		ns.OnSettingsChanged = function() refreshed = refreshed + 1 end
	end)

	for _, key in ipairs({ "DESTINATION", false }) do
		it("copies every supported value while preserving destination identity and " .. tostring(key) .. " key", function()
			local destination = ns.GetBarConfig(1)
			destination.key = key or nil
			local contents = { [1] = "untouched" }
			destination.actions, destination.barId = contents, 1
			assert.is_true(ns.CopyBarSettings(8, 1))
			assert.equal(destination, ns.db.bars[1])
			assert.is_false(destination == source)
			assert.equal(key or nil, destination.key)
			assert.equal(contents, destination.actions)
			assert.equal(1, destination.barId)
			for setting, value in pairs(expected) do
				if setting ~= "key" then assert.equal(value, destination[setting], setting) end
			end
			assert.same(expected, source)
			assert.equal(1, applied)
			assert.equal(1, refreshed)
		end)
	end

	it("allows each of the eight bars as either endpoint without moving key ownership", function()
		for bar = 1, 8 do
			local config = ns.GetBarConfig(bar)
			config.key, config.radius = "KEY" .. bar, 60 + bar * 10
		end
		for bar = 1, 8 do
			local destination = bar % 8 + 1
			local radius = ns.GetBarConfig(bar).radius
			assert.is_true(ns.CopyBarSettings(bar, destination))
			assert.equal(radius, ns.GetBarConfig(destination).radius)
			assert.equal("KEY" .. destination, ns.GetBarConfig(destination).key)
			assert.equal("KEY" .. bar, ns.GetBarConfig(bar).key)
		end
	end)

	it("deep copies supported values if they grow nested data", function()
		-- A supported setting represented as structured data must not acquire aliases.
		source.showDescription = { style = { color = "gold" } }
		ns.CopyBarSettings(8, 1)
		ns.GetBarConfig(1).showDescription.style.color = "red"
		assert.equal("gold", source.showDescription.style.color)
	end)

	it("ignores self-copy and invalid endpoints without applying or refreshing", function()
		assert.is_false(ns.CopyBarSettings(8, 8))
		assert.is_false(ns.CopyBarSettings(0, 1))
		assert.is_false(ns.CopyBarSettings(1, 9))
		assert.equal(0, applied)
		assert.equal(0, refreshed)
		assert.same(expected, source)
	end)

	it("saves and refreshes immediately but defers protected changes during combat", function()
		wow.inCombat = true
		assert.is_true(ns.CopyBarSettings(8, 1))
		assert.equal(235, ns.GetBarConfig(1).radius)
		assert.equal(0, applied)
		assert.equal(1, refreshed)
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		assert.equal(1, applied)
	end)
end)
