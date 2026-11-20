local wow = require("spec.helpers.wow")

describe("macro opening", function()
	local frames, refs, templates

	before_each(function()
		wow.Reset()
		frames, refs, templates = {}, {}, {}
		local createFrame = CreateFrame
		_G.CreateFrame = function(kind, name, parent, template)
			local frame = createFrame(kind, name, parent, template)
			if name then
				frames[name] = frame
				templates[name] = template
			end
			return frame
		end
		_G.SecureHandlerSetFrameRef = function(frame, name, target)
			refs[frame] = refs[frame] or {}
			refs[frame][name] = target
		end
		wow.Load("Core.lua", "Changelog.lua", "Wheel.lua")
	end)

	local function RunOpen(mode, shown)
		local open = assert(frames.RadialBarsOpen, "missing public macro endpoint")
		local wheel = assert(frames.RadialBarsWheel)
		local trigger = assert(frames.RadialBarsTrigger)
		assert.equal("SecureHandlerClickTemplate", templates.RadialBarsOpen)
		assert.equal(wheel, refs[open].wheel)
		assert.is_nil(open.scripts.OnClick)

		wheel.attributes["rb-mode"] = mode
		wheel.attributes["rb-count"] = 8
		wheel.attributes["rb-position"] = "cursor"
		local wheelAttributes, triggerAttributes = {}, {}
		for key, value in pairs(wheel.attributes) do
			wheelAttributes[key] = value
		end
		for key, value in pairs(trigger.attributes) do
			triggerAttributes[key] = value
		end

		local calls = { show = 0 }
		local secureWheel = {
			IsShown = function()
				return shown
			end,
			Show = function()
				shown = true
				calls.show = calls.show + 1
			end,
		}
		setmetatable(secureWheel, {
			__index = function(_, method)
				error("unexpected wheel operation: " .. method)
			end,
		})
		local secureOpen = {
			GetFrameRef = function(_, name)
				assert.equal(wheel, refs[open][name])
				return secureWheel
			end,
		}
		local chunk = assert(loadstring(open.attributes._onclick))
		-- This models the restricted handler, not client combat authorization.
		setfenv(chunk, setmetatable({ self = secureOpen }, {
			__index = function(_, name)
				error("unexpected insecure global: " .. name)
			end,
		}))
		chunk()
		chunk()

		assert.is_true(shown)
		assert.same(wheelAttributes, wheel.attributes)
		assert.same(triggerAttributes, trigger.attributes)
		return calls
	end

	for _, mode in ipairs({ "toggle", "hold" }) do
		it("opens the configured " .. mode .. " wheel without an action", function()
			assert.equal(1, RunOpen(mode, false).show)
		end)

		it("leaves an open " .. mode .. " wheel untouched", function()
			assert.equal(0, RunOpen(mode, true).show)
		end)
	end
end)
