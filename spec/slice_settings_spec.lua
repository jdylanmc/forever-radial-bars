local wow = require("spec.helpers.wow")

describe("slice icon zoom settings", function()
	local ns, slider, applied

	before_each(function()
		wow.Reset()
		applied, slider = 0, nil
		local create = CreateFrame
		_G.CreateFrame = function(kind, name, parent, template)
			local frame = create(kind, name, parent, template)
			if template == "MinimalSliderWithSteppersTemplate" then
				frame.Init = function(self, ...)
					self.initial = { ... }
				end
				frame.RegisterCallback = function(self, _, callback)
					self.changed = callback
				end
				frame.SetValue = function(self, value)
					self.value = value
					self.changed(self, value)
				end
				frame.SetEnabled = function(self, enabled)
					self.enabled = enabled
				end
			end
			return frame
		end
		ns = wow.Load("Core.lua", "Visuals.lua", "SettingsPreview.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		ns.Wheel = {
			Apply = function() applied = applied + 1 end,
			IsPreviewing = function() return false end,
			SetPreview = function() end,
		}
		wow.Load("Settings.lua")
		for _, frame in ipairs(wow.frames) do
			if frame.key == "sliceIconZoom" then slider = frame end
		end
	end)

	it("offers the supported zoom range and percentage format", function()
		assert.is_table(slider)
		assert.same({ 1.15, 1, 2, 20 }, {
			slider.initial[1], slider.initial[2], slider.initial[3], slider.initial[4],
		})
		local format = slider.initial[5][MinimalSliderWithSteppersMixin.Label.Right]
		assert.equal("115%", format(1.15))
	end)

	it("enables zoom only for radial slices without applying during refresh", function()
		for _, shape in ipairs({ "square", "slice", "circle", "slice" }) do
			ns.GetBarConfig(2).shape = shape
			ns.OnPreviewChanged()
			assert.equal(shape == "slice", slider.enabled)
		end
		assert.equal(0, applied)
	end)

	it("edits and restores each bar's zoom through the existing callback", function()
		ns.GetBarConfig(2).shape = "slice"
		slider.changed(slider, 1.35)
		assert.near(1.35, ns.GetBarConfig(2).sliceIconZoom, 0.00001)
		assert.equal(1, applied)
		ns.db.activeBar = 3
		local other = ns.GetBarConfig(3)
		other.shape, other.sliceIconZoom = "slice", 1.75
		ns.OnPreviewChanged()
		assert.equal(1.75, slider.value)
		assert.near(1.35, ns.GetBarConfig(2).sliceIconZoom, 0.00001)
		assert.equal(1, applied)
	end)

	it("saves combat edits but defers protected apply until combat ends", function()
		ns.GetBarConfig(2).shape = "slice"
		wow.inCombat = true
		slider.changed(slider, 1.5)
		assert.equal(1.5, ns.GetBarConfig(2).sliceIconZoom)
		assert.equal(0, applied)
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		assert.equal(1, applied)
	end)
end)
