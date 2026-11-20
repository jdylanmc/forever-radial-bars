local wow = require("spec.helpers.wow")

-- Record the rendering boundary, not a replacement implementation of Layout.
local function Track(object, parent)
	object.parent = parent
	object.calls = {}
	object.masks = {}
	object.shown = true
	for _, method in ipairs({
		"SetSize", "SetPoint", "SetTexture", "SetRotation", "SetAlpha",
		"SetTexCoord", "SetVertexColor", "EnableMouse", "SetFrameLevel",
	}) do
		local original = object[method]
		object[method] = function(self, ...)
			self.calls[method] = { ... }
			return original(self, ...)
		end
	end
	object.Show = function(self) self.shown = true end
	object.Hide = function(self) self.shown = false end
	object.SetShown = function(self, shown) self.shown = shown end
	object.IsShown = function(self) return self.shown end
	object.AddMaskTexture = function(self, mask) self.masks[mask] = true end
	object.RemoveMaskTexture = function(self, mask) self.masks[mask] = nil end
	for _, method in ipairs({ "CreateTexture", "CreateMaskTexture" }) do
		local original = object[method]
		object[method] = function(self, ...)
			return Track(original(self, ...), self)
		end
	end
	return object
end

local function Alpha(count, x, y)
	local file = assert(io.open("Media/Wedge" .. count .. ".tga", "rb"))
	local bytes = file:read("*a")
	file:close()
	assert.equal(2, bytes:byte(3)) -- Uncompressed true-color TGA.
	local width = bytes:byte(13) + 256 * bytes:byte(14)
	local height = bytes:byte(15) + 256 * bytes:byte(16)
	local column = math.floor((x + 1) * width / 2)
	local row = math.floor((y + 1) * height / 2)
	return bytes:byte(18 + (row * width + column) * 4 + 4)
end

describe("radial slice rendering and selection", function()
	local ns, frames, secure, config

	before_each(function()
		wow.Reset()
		frames, secure = {}, {}
		local create = CreateFrame
		_G.CreateFrame = function(kind, name, parent, ...)
			local frame = Track(create(kind, name, parent, ...), parent)
			if name then frames[name] = frame end
			return frame
		end
		local wrap = SecureHandlerWrapScript
		_G.SecureHandlerWrapScript = function(frame, script, owner, pre, post)
			secure[frame.name] = pre
			return wrap(frame, script, owner, pre, post)
		end
		_G.C_ActionBar = {
			HasAction = function() return true end,
			GetActionTexture = function(action) return "ActionTexture" .. action end,
			IsUsableAction = function() return true end,
			GetActionCooldown = function() return { startTime = 0, duration = 0, modRate = 1 } end,
			GetActionDisplayCount = function() return "" end,
		}
		ns = wow.Load("Core.lua", "Wheel.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		config = ns.GetBarConfig(2)
		config.shape = "slice"
	end)

	local function Click(frame, dx, dy)
		local wheel, sensor = frames.RadialBarsWheel, frames.RadialBarsSensor
		wheel.GetFrameRef = function(_, name)
			if name == "sensor" then return sensor end
			return frames["RadialBarsSlot" .. name:match("%d+")]
		end
		sensor.GetMousePosition = function()
			return 0.5 + dx / 4096, 0.5 + dy / 4096
		end
		local chunk = assert(loadstring(secure[frame.name]))
		setfenv(chunk, { owner = wheel, self = frame, math = math, down = false })
		wheel:Show()
		return chunk()
	end

	it("fills a pie wedge with upright artwork instead of a circular button", function()
		config.count, config.radius, config.iconSize, config.margin = 4, 100, 40, 0
		config.iconAlpha = 0.65
		ns.Wheel:Apply()
		local button = frames.RadialBarsSlot1
		local icon, mask = button.sliceIcon, button.sliceMask
		assert.equal(icon, button.actionIcon)
		assert.is_false(button.icon:IsShown())
		assert.is_true(icon:IsShown())
		assert.equal(frames.RadialBarsWheel, icon.parent)
		assert.equal("ActionTexture61", icon.calls.SetTexture[1])
		assert.equal(0.65, icon.calls.SetAlpha[1])
		assert.near(120 * math.sqrt(2) * 1.15, icon.calls.SetSize[1], 0.00001)
		assert.near(0, icon.calls.SetPoint[4], 0.00001)
		assert.near((120 + 35 / math.sqrt(2)) / 2, icon.calls.SetPoint[5], 0.00001)
		assert.is_true(icon.masks[mask])
		assert.is_true(icon.masks[button.sliceHubMask])
		assert.same({ 240, 240 }, mask.calls.SetSize)
		assert.same({
			"Interface\\AddOns\\RadialBars\\Media\\Wedge4",
			"CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE",
		}, mask.calls.SetTexture)
	end)

	it("clips artwork out of the round cancel hub at every center size", function()
		for _, hubSize in ipairs({ 0, 0.35, 0.8 }) do
			config.hubSize = hubSize
			ns.Wheel:Apply()
			local mask = frames.RadialBarsSlot1.sliceHubMask
			local coordinates = mask.calls.SetTexCoord
			assert.same({ 288, 288 }, mask.calls.SetSize)
			assert.same({
				"Interface\\AddOns\\RadialBars\\Media\\SliceHubMask", "CLAMP", "CLAMP",
			}, mask.calls.SetTexture)
			local radius = math.max(12, 110 * hubSize)
			local atBoundary = 0.5 + radius / 288 * (coordinates[2] - coordinates[1])
			assert.near(0.75, atBoundary, 0.00001)
			if hubSize == 0.8 then
				assert.is_true(frames.RadialBarsSlot1.sliceIcon.calls.SetPoint[5] > radius)
			end
		end
		local file = assert(io.open("Media/SliceHubMask.tga", "rb"))
		local bytes = file:read("*a")
		file:close()
		assert.equal(0, bytes:byte(18 + (64 * 128 + 64) * 4 + 4))
		assert.equal(255, bytes:byte(22))
	end)

	it("keeps every wedge boundary fixed while zooming only its artwork", function()
		for count = 4, 12 do
			config.count, config.sliceIconZoom = count, 1
			ns.Wheel:Apply()
			local sizes = {}
			for index = 1, count do
				local icon = frames["RadialBarsSlot" .. index].sliceIcon
				sizes[index] = icon.calls.SetSize[1]
				local point = icon.calls.SetPoint
				for _, offset in ipairs({ -0.49, 0, 0.49 }) do
					local angle = math.rad(90 - (index - 1 + offset) * 360 / count)
					assert.is_true(math.abs(144 * math.cos(angle) - point[4]) <= sizes[index] / 2 + 0.001)
					assert.is_true(math.abs(144 * math.sin(angle) - point[5]) <= sizes[index] / 2 + 0.001)
				end
			end
			config.sliceIconZoom = 2
			ns.Wheel:Apply()
			for index = 1, count do
				local button = frames["RadialBarsSlot" .. index]
				assert.near(sizes[index] * 2, button.sliceIcon.calls.SetSize[1], 0.00001)
				assert.same({ 288, 288 }, button.sliceMask.calls.SetSize)
				assert.near(math.rad(-(index - 1) * 360 / count), button.sliceMask.calls.SetRotation[1], 0.00001)
				-- Points along both sector edges and the arc remain covered by artwork.
				local size = button.sliceIcon.calls.SetSize[1]
				local point = button.sliceIcon.calls.SetPoint
				for _, offset in ipairs({ -0.49, 0, 0.49 }) do
					local angle = math.rad(90 - (index - 1 + offset) * 360 / count)
					assert.is_true(math.abs(144 * math.cos(angle) - point[4]) <= size / 2 + 0.001)
					assert.is_true(math.abs(144 * math.sin(angle) - point[5]) <= size / 2 + 0.001)
				end
			end
		end
	end)

	it("uses actual alpha assets that clip sides and the circular outer rim", function()
		for count = 4, 12 do
			assert.equal(255, Alpha(count, 0, 0.75))
			local angle = math.rad(90 - 180 / count - 5)
			assert.equal(0, Alpha(count, 0.75 * math.cos(angle), 0.75 * math.sin(angle)))
			assert.equal(0, Alpha(count, 0.9, 0.9))
		end
	end)

	it("restores unchanged Circle and Square icons after leaving slice mode", function()
		ns.Wheel:Apply()
		for _, shape in ipairs({ "circle", "square" }) do
			config.shape = shape
			ns.Wheel:Apply()
			local button = frames.RadialBarsSlot1
			assert.equal(button.icon, button.actionIcon)
			assert.is_true(button.icon:IsShown())
			assert.is_false(button.sliceIcon:IsShown())
			assert.same({ 44, 44 }, button.calls.SetSize)
			assert.near(110, button.calls.SetPoint[5], 0.00001)
			assert.is_true(button.calls.EnableMouse[1])
			if shape == "circle" then
				assert.is_true(button.icon.masks[button.iconMask])
				assert.same({ 0, 1, 0, 1 }, button.icon.calls.SetTexCoord)
			else
				assert.is_nil(button.icon.masks[button.iconMask])
				assert.same({ 0.07, 0.93, 0.07, 0.93 }, button.icon.calls.SetTexCoord)
			end
		end
	end)

	it("saves zoom per bar and repairs missing, invalid, and out-of-range values", function()
		assert.equal(1.15, config.sliceIconZoom)
		for bar, value in pairs({ [3] = 0, [4] = 8, [5] = "1.35", [6] = "bad" }) do
			ns.db.bars[bar] = { sliceIconZoom = value }
		end
		assert.equal(1, ns.GetBarConfig(3).sliceIconZoom)
		assert.equal(2, ns.GetBarConfig(4).sliceIconZoom)
		assert.equal(1.35, ns.GetBarConfig(5).sliceIconZoom)
		assert.equal(1.15, ns.GetBarConfig(6).sliceIconZoom)
		assert.equal(1.15, ns.GetBarConfig(2).sliceIconZoom)
	end)

	it("clicks the whole wedge, including beyond the small icon and beside the round hub", function()
		config.count = 8
		ns.Wheel:Apply()
		local selector = frames.RadialBarsSelector
		assert.is_true(selector.calls.SetFrameLevel[1] > frames.RadialBarsCancel.calls.SetFrameLevel[1])
		assert.is_not_false(Click(selector, 0, 140))
		assert.equal(61, selector:GetAttribute("action"))
		assert.is_not_false(Click(selector, 30, 30))
		assert.equal(62, selector:GetAttribute("action"))
	end)

	it("matches each painted wedge's direction throughout its full clickable area", function()
		for count = 4, 12 do
			config.count = count
			ns.Wheel:Apply()
			local selector = frames.RadialBarsSelector
			for index = 1, count do
				for _, offset in ipairs({ -0.45, 0, 0.45 }) do
					local angle = math.rad(90 - (index - 1 + offset) * 360 / count)
					for _, radius in ipairs({ 40, 143 }) do
						assert.is_not_false(Click(selector, radius * math.cos(angle), radius * math.sin(angle)))
						assert.equal(60 + index, selector:GetAttribute("action"))
					end
				end
			end
		end
	end)

	it("rejects clicks outside the rim and cancels inside the circular dead zone", function()
		ns.Wheel:Apply()
		local selector, wheel = frames.RadialBarsSelector, frames.RadialBarsWheel
		assert.is_false(Click(selector, 140, 140))
		assert.is_true(wheel:IsShown())
		assert.is_nil(selector:GetAttribute("action"))
		assert.is_false(Click(selector, 0, 0))
		assert.is_false(wheel:IsShown())
		assert.is_nil(selector:GetAttribute("action"))
	end)

	it("preserves Hold selection beyond the wheel", function()
		config.mode = "hold"
		ns.Wheel:Apply()
		local trigger = frames.RadialBarsTrigger
		Click(trigger, 0, 1000)
		assert.equal("action", trigger:GetAttribute("type"))
		assert.equal(61, trigger:GetAttribute("action"))
		assert.is_false(frames.RadialBarsWheel:IsShown())
	end)

	it("refreshes usability and empty-state artwork without losing clipping or opacity", function()
		config.iconAlpha = 0.4
		ns.Wheel:Apply()
		local button = frames.RadialBarsSlot1
		_G.C_ActionBar.IsUsableAction = function() return false, true end
		ns.Wheel:Refresh()
		assert.same({ 0.5, 0.5, 1, 1 }, button.sliceIcon.calls.SetVertexColor)
		_G.C_ActionBar.HasAction = function() return false end
		ns.Wheel:Refresh()
		assert.equal("Interface\\Buttons\\UI-EmptySlot-Disabled", button.sliceIcon.calls.SetTexture[1])
		assert.same({ 1, 1, 1, 0.4 }, button.sliceIcon.calls.SetVertexColor)
		assert.equal(0.4, button.sliceIcon.calls.SetAlpha[1])
		assert.is_true(button.sliceIcon.masks[button.sliceMask])
		assert.is_true(button.sliceIcon.masks[button.sliceHubMask])
	end)
end)
