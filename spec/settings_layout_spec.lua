local wow = require("spec.helpers.wow")

-- Only vertical anchors and scroll extents are modeled, not client rendering or font metrics.
local function TrackLayout()
	local regions, geometry = {}, {}
	local function Edge(point)
		return point:find("TOP") and 0 or (point:find("BOTTOM") and 1 or 0.5)
	end
	local function Track(object, kind, parent, template)
		local rect = { parent = parent, points = {}, width = 16, height = 16, offset = 0, kind = kind }
		if kind == "FontString" then
			rect.width = nil
			rect.height = template == "GameFontNormalLarge" and 16 or 12
		elseif template == "MinimalSliderWithSteppersTemplate" then
			rect.height = 32
		end
		geometry[object] = rect
		regions[#regions + 1] = object
		function object:SetPoint(point, relative, relativePoint, _x, y)
			if type(relative) == "number" then
				y, relative, relativePoint = relativePoint, parent, point
			end
			rect.points[#rect.points + 1] = {
				point = point, relative = relative or parent, relativePoint = relativePoint or point, y = y or 0,
			}
		end
		function object:SetSize(width, height) rect.width, rect.height = width, height end
		function object:SetWidth(width) rect.width = width end
		function object:SetHeight(height) rect.height = height end
		function object:SetText(text) rect.text = text end
		function object:GetWidth() return rect.width end
		function object:GetHeight()
			local first, last = rect.points[1], rect.points[2]
			if first and last then
				return first.relative:GetTop() - first.relative:GetHeight() * Edge(first.relativePoint) + first.y
					- (last.relative:GetTop() - last.relative:GetHeight() * Edge(last.relativePoint) + last.y)
			end
			if rect.text and rect.width then
				return rect.height * math.max(1, math.ceil(#rect.text * 5 / rect.width))
			end
			return rect.height
		end
		function object:GetTop()
			if rect.top then return rect.top end
			local point = rect.points[1]
			if not point then return parent and parent:GetTop() or 1000 end
			local top = point.relative:GetTop() - point.relative:GetHeight() * Edge(point.relativePoint)
				+ point.y + self:GetHeight() * Edge(point.point)
			local owner = geometry[parent]
			return top + (owner and owner.child == self and owner.offset or 0)
		end
		function object:GetBottom() return self:GetTop() - self:GetHeight() end
		function object:SetScrollChild(child)
			rect.child = child
			child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		end
		function object:SetVerticalScroll(offset) rect.offset = offset end
		function object:GetVerticalScroll() return rect.offset end
		function object:GetVerticalScrollRange()
			return math.max(0, rect.child:GetHeight() - self:GetHeight())
		end
		local createFontString = object.CreateFontString
		function object:CreateFontString(name, layer, font)
			return Track(createFontString(self, name, layer, font), "FontString", self, font)
		end
		return object
	end
	local createFrame = _G.CreateFrame
	_G.CreateFrame = function(kind, name, parent, template)
		return Track(createFrame(kind, name, parent, template), kind, parent, template)
	end
	return regions, geometry
end

describe("settings layout", function()
	local canvas, scroll, finalNote, regions, geometry

	local function DescendsFrom(region, ancestor)
		while region do
			if region == ancestor then return true end
			region = geometry[region].parent
		end
		return false
	end

	local function Resize(height)
		canvas:SetSize(680, height)
		if scroll then
			scroll:SetWidth(654)
			local resized = scroll.hooks.OnSizeChanged
			if resized then resized(scroll, 654, height) end
		end
		canvas.scripts.OnShow(canvas)
	end

	before_each(function()
		wow.Reset()
		regions, geometry = TrackLayout()
		local ns = wow.Load("Core.lua", "Changelog.lua")
		ns.Wheel = { Apply = function() end, IsPreviewing = function() return false end, SetPreview = function() end }
		wow.Fire("ADDON_LOADED", "RadialBars")
		_G.Settings.RegisterCanvasLayoutCategory = function(panel)
			canvas = panel
			return { GetID = function() return 1 end }
		end
		wow.Load("Settings.lua")
		scroll, finalNote = nil, nil
		for _, region in ipairs(regions) do
			local rect = geometry[region]
			if rect.kind == "ScrollFrame" and DescendsFrom(region, canvas) then scroll = region end
			if rect.text == "A pointer shows the direction instead." then finalNote = region end
		end
		geometry[canvas].top = 1000
		assert.is_not_nil(finalNote)
	end)

	it("contains every setting inside a viewport that leaves the footer clear", function()
		assert.is_not_nil(scroll, "settings need a clipping scroll viewport")
		Resize(610)
		assert.is_true(scroll:GetTop() <= canvas:GetTop())
		assert.is_true(scroll:GetBottom() >= canvas:GetBottom())
		assert.is_true(finalNote:GetBottom() < scroll:GetBottom(), "fixture must need scrolling")
		for _, region in ipairs(regions) do
			if region ~= canvas and DescendsFrom(region, canvas) then
				assert.is_true(DescendsFrom(region, scroll), "a setting bypasses scroll clipping")
			end
		end
	end)

	it("makes the final setting reachable at each short viewport height", function()
		assert.is_not_nil(scroll)
		for _, height in ipairs({ 610, 460, 310 }) do
			Resize(height)
			assert.is_true(scroll:GetVerticalScrollRange() > 0)
			scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
			assert.is_true(finalNote:GetBottom() >= scroll:GetBottom(), "final note is below the viewport")
			assert.is_true(finalNote:GetTop() <= scroll:GetTop(), "final note is above the viewport")
		end
	end)

	it("clears the old scroll offset when a larger viewport fits all settings", function()
		assert.is_not_nil(scroll)
		Resize(310)
		scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
		Resize(900)
		assert.equal(0, scroll:GetVerticalScrollRange())
		assert.equal(0, scroll:GetVerticalScroll())
		assert.is_true(finalNote:GetBottom() >= scroll:GetBottom())
		assert.is_true(finalNote:GetTop() <= scroll:GetTop())
	end)
end)
