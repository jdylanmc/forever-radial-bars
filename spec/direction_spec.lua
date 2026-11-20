local wow = require("spec.helpers.wow")

-- Runs the restricted PICK_DIRECTION snippet against a fake wheel whose sensor
-- reports the cursor at (dx, dy) from the center.
local function SecurePick(snippet, dx, dy, dead, count)
	local size = 4096
	local attributes = { ["rb-sensor"] = size, ["rb-dead"] = dead, ["rb-count"] = count }
	local sensor = {
		GetMousePosition = function()
			return 0.5 + dx / size, 0.5 + dy / size
		end,
	}
	local owner = {
		GetAttribute = function(_, name)
			return attributes[name]
		end,
		GetFrameRef = function()
			return sensor
		end,
	}
	local chunk = assert(loadstring(snippet .. "\nreturn index"))
	setfenv(chunk, { owner = owner, math = math })
	return chunk()
end

describe("direction selection", function()
	local ns

	setup(function()
		wow.Reset()
		ns = wow.Load("Core.lua", "Changelog.lua", "Visuals.lua", "Wheel.lua")
	end)

	it("puts slot 1 at the top and runs clockwise", function()
		assert.equal(1, ns.DirectionIndex(0, 100, 10, 4))
		assert.equal(2, ns.DirectionIndex(100, 0, 10, 4))
		assert.equal(3, ns.DirectionIndex(0, -100, 10, 4))
		assert.equal(4, ns.DirectionIndex(-100, 0, 10, 4))
	end)

	it("picks the nearest slot between neighbors", function()
		local angle = math.rad(90 - 25)
		assert.equal(2, ns.DirectionIndex(100 * math.cos(angle), 100 * math.sin(angle), 10, 12))
	end)

	it("returns nothing inside the dead zone", function()
		assert.is_nil(ns.DirectionIndex(5, 5, 10, 8))
		assert.is_nil(ns.DirectionIndex(0, 0, 0.5, 8))
	end)

	it("matches the secure snippet for every bar size and direction", function()
		for count = 4, 12 do
			local step = 360 / count
			for degrees = 0, 359, 0.5 do
				-- Exactly on a border either neighbor is correct; float noise decides.
				local fromBorder = math.abs(((90 - degrees) % step) - step / 2)
				if fromBorder > 0.01 then
					local angle = math.rad(degrees)
					local dx, dy = 150 * math.cos(angle), 150 * math.sin(angle)
					local expected = ns.DirectionIndex(dx, dy, 30, count)
					local actual = SecurePick(ns.PICK_DIRECTION, dx, dy, 30, count)
					assert.equal(expected, actual, ("count %d at %.1f degrees"):format(count, degrees))
				end
			end
		end
		assert.is_nil(SecurePick(ns.PICK_DIRECTION, 3, 4, 30, 8))
	end)
end)
