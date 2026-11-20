local wow = require("spec.helpers.wow")

-- Approximate wrapped text and anchors, not client rendering or actual font metrics.
local function TrackLayout()
	local regions, geometry = {}, {}
	local function Edge(point)
		return point:find("TOP") and 0 or (point:find("BOTTOM") and 1 or 0.5)
	end
	local function Track(object, kind, parent, template)
		local rect = { parent = parent, points = {}, width = 16, height = 16, offset = 0, kind = kind, template = template }
		if kind == "FontString" then
			rect.width = nil
			rect.height = template == "GameFontNormalLarge" and 16 or 12
		elseif template == "MinimalSliderWithSteppersTemplate" then
			rect.height = 32
		end
		geometry[object] = rect
		regions[#regions + 1] = object
		function object:SetPoint(point, relative, relativePoint, x, y)
			if type(relative) == "number" then
				x, y, relative, relativePoint = relative, relativePoint, parent, point
			end
			rect.points[#rect.points + 1] = {
				point = point, relative = relative or parent, relativePoint = relativePoint or point, x = x or 0, y = y or 0,
			}
		end
		function object:ClearAllPoints() rect.points = {} end
		function object:SetSize(width, height) rect.width, rect.height = width, height end
		function object:SetWidth(width) rect.width = width end
		function object:SetHeight(height) rect.height = height end
		function object:SetText(text) rect.text = text end
		function object:SetChecked(checked) rect.checked = checked end
		function object:GetChecked() return rect.checked end
		function object:EnableKeyboard(enabled) rect.keyboard = enabled end
		function object:SetPropagateKeyboardInput(propagate) rect.propagate = propagate end
		function object:RegisterCallback(_, callback) rect.callback = callback end
		function object:SetValue(value)
			rect.value = value
			rect.callback(self, value)
		end
		function object:SetEnabled(enabled) rect.enabled = enabled end
		function object:GetWidth() return rect.width or #(rect.text or "") * 5 end
		function object:GetStringHeight()
			if rect.text == "" then return 0 end
			return rect.height * math.max(1, math.ceil(#(rect.text or "") * 5 / (rect.width or 300)))
		end
		function object:GetHeight()
			local first, last = rect.points[1], rect.points[2]
			if first and last then
				return first.relative:GetTop() - first.relative:GetHeight() * Edge(first.relativePoint) + first.y
					- (last.relative:GetTop() - last.relative:GetHeight() * Edge(last.relativePoint) + last.y)
			end
			if rect.text and rect.width then
				return self:GetStringHeight()
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
		local function HorizontalEdge(point)
			return point:find("LEFT") and 0 or (point:find("RIGHT") and 1 or 0.5)
		end
		function object:GetLeft()
			local point = rect.points[1]
			if not point then return parent and parent:GetLeft() or 0 end
			return point.relative:GetLeft() + point.relative:GetWidth() * HorizontalEdge(point.relativePoint)
				+ point.x - self:GetWidth() * HorizontalEdge(point.point)
		end
		function object:GetRight() return self:GetLeft() + self:GetWidth() end
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
	local canvas, scroll, finalNote, regions, geometry, ns, applied, previewing

	local function DescendsFrom(region, ancestor)
		while region do
			if region == ancestor then return true end
			region = geometry[region].parent
		end
		return false
	end

	local function Resize(height, width)
		width = width or 680
		canvas:SetSize(width, height)
		if scroll then
			scroll:SetWidth(width - 26)
			local resized = scroll.hooks.OnSizeChanged
			if resized then resized(scroll, width - 26, height) end
		end
		canvas.scripts.OnShow(canvas)
	end

	before_each(function()
		wow.Reset()
		regions, geometry = TrackLayout()
		ns = wow.Load("Core.lua", "Changelog.lua")
		applied, previewing = 0, false
		ns.Wheel = {
			Apply = function() applied = applied + 1 end,
			IsPreviewing = function() return previewing end,
			SetPreview = function(_, value) previewing = value; ns.OnPreviewChanged() end,
		}
		_G.GetBindingText = function(key) return key end
		_G.GetBindingAction = function() return "" end
		_G.IsAltKeyDown = function() return false end
		_G.IsControlKeyDown = function() return false end
		_G.IsShiftKeyDown = function() return false end
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
			if rect.text == "Needs a center size large enough to fit text." then finalNote = region end
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
		for _, width in ipairs({ 320, 680, 960 }) do
			for _, height in ipairs({ 610, 460, 310 }) do
				Resize(height, width)
				assert.is_true(scroll:GetVerticalScrollRange() > 0)
				scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
				assert.is_true(finalNote:GetBottom() >= scroll:GetBottom(), "final note is below the viewport")
				assert.is_true(finalNote:GetTop() <= scroll:GetTop(), "final note is above the viewport")
				for _, region in ipairs(regions) do
					if region ~= scroll and DescendsFrom(region, scroll) then
						assert.is_true(region:GetLeft() >= scroll:GetLeft(), "content escapes the left edge")
						assert.is_true(region:GetRight() <= scroll:GetRight(), "content escapes the right edge")
					end
				end
			end
		end
	end)

	it("clears the old scroll offset when a larger viewport fits all settings", function()
		assert.is_not_nil(scroll)
		Resize(310)
		scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
		Resize(2400)
		assert.equal(0, scroll:GetVerticalScrollRange())
		assert.equal(0, scroll:GetVerticalScroll())
		assert.is_true(finalNote:GetBottom() >= scroll:GetBottom())
		assert.is_true(finalNote:GetTop() <= scroll:GetTop())
	end)

	it("groups every existing control exactly once under five ordered native headings", function()
		Resize(610)
		local titles = { "Action bar", "Activation", "Placement", "Wheel layout", "Visibility" }
		local sections, previous = {}, nil
		for _, title in ipairs(titles) do
			local found = {}
			for _, region in ipairs(regions) do
				if geometry[region].text == title then found[#found + 1] = region end
			end
			assert.equal(1, #found, title)
			local heading = found[1]
			assert.equal("GameFontNormalLarge", geometry[heading].template)
			sections[title] = geometry[heading].parent
			if previous then assert.is_true(heading:GetTop() < previous:GetBottom()) end
			previous = sections[title]
		end
		local expected = {
			["Action bar"] = { 2, 3, 4, 5, 6, 7, 8 },
			Activation = { "toggle", "hold", "hideCursor", "Not bound", "Clear" },
			Placement = { "center", "cursor", "fixed", "Preview wheel" },
			["Wheel layout"] = { "square", "circle", "slice", "count", "iconSize", "radius", "margin", "hubSize", "gap", "sliceIconZoom" },
			Visibility = { "backdropAlpha", "iconAlpha", "showDescription" },
		}
		local seen = {}
		for _, region in ipairs(regions) do
			local rect = geometry[region]
			local interactive = rect.kind == "Button" or rect.kind == "CheckButton"
				or rect.template == "MinimalSliderWithSteppersTemplate"
			if interactive and DescendsFrom(region, canvas) then
				local key = rawget(region, "key") or rawget(region, "value") or rect.text
				assert.is_not_nil(key, "unidentified control")
				assert.is_nil(seen[key], "duplicate control: " .. tostring(key))
				seen[key] = region
			end
		end
		for title, controls in pairs(expected) do
			for _, key in ipairs(controls) do
				assert.is_not_nil(seen[key], "missing control: " .. tostring(key))
				assert.is_true(DescendsFrom(seen[key], sections[title]), "wrong section: " .. tostring(key))
				seen[key] = nil
			end
		end
		assert.same({}, seen)
	end)

	it("keeps wrapped binding and combat notes above later sections after resize and refresh", function()
		ns.GetBarConfig(2).key = "K"
		_G.GetBindingAction = function() return "LONG_BINDING" end
		_G.GetBindingName = function() return string.rep("Long binding name ", 14) end
		Resize(310, 320)
		local note, status, placement
		for _, region in ipairs(regions) do
			local text = geometry[region].text or ""
			if text:find("Overrides the game binding:", 1, true) then note = region end
			if geometry[region].template == "GameFontRedSmall" then status = region end
			if text == "Placement" then placement = region end
		end
		local narrowHeight = note:GetHeight()
		wow.inCombat = true
		status:SetText(string.rep("Changes apply when combat ends. ", 12))
		ns.OnPreviewChanged()
		assert.is_true(status:GetTop() < note:GetBottom())
		assert.is_true(placement:GetTop() < status:GetBottom())
		scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
		assert.is_true(finalNote:GetBottom() >= scroll:GetBottom())
		Resize(610, 960)
		assert.is_true(note:GetHeight() < narrowHeight)
		assert.is_true(placement:GetTop() < status:GetBottom())
		assert.is_true(scroll:GetVerticalScroll() <= scroll:GetVerticalScrollRange())
	end)

	it("preserves grouped callbacks, per-bar values, and combat-deferred apply", function()
		Resize(610)
		local controls = {}
		for _, region in ipairs(regions) do
			local key = rawget(region, "key") or rawget(region, "value")
			if key then controls[key] = region end
		end
		controls.hold.scripts.OnClick()
		controls.fixed.scripts.OnClick()
		controls.hideCursor:SetChecked(false)
		controls.hideCursor.scripts.OnClick(controls.hideCursor)
		geometry[controls.count].callback(controls.count, 6)
		assert.same({ "hold", "fixed", false, 6 }, {
			ns.GetBarConfig(2).mode, ns.GetBarConfig(2).position,
			ns.GetBarConfig(2).hideCursor, ns.GetBarConfig(2).count,
		})
		assert.equal(4, applied)
		controls[3].scripts.OnClick()
		assert.same({ "toggle", "center", true, 12 }, {
			ns.GetBarConfig(3).mode, ns.GetBarConfig(3).position,
			geometry[controls.hideCursor].checked, geometry[controls.count].value,
		})
		wow.inCombat = true
		geometry[controls.iconAlpha].callback(controls.iconAlpha, 0.5)
		assert.equal(0.5, ns.GetBarConfig(3).iconAlpha)
		assert.equal(5, applied)
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		assert.equal(6, applied)
		controls[2].scripts.OnClick()
		assert.equal(6, geometry[controls.count].value)
		assert.is_false(geometry[controls.hideCursor].checked)
	end)

	it("retains keyboard capture, Clear, and the floating preview lifecycle", function()
		Resize(610, 320)
		local key, clear, preview
		for _, region in ipairs(regions) do
			local text = geometry[region].text
			if text == "Not bound" then key = region end
			if text == "Clear" then clear = region end
			if text == "Preview wheel" then preview = region end
		end
		assert.is_true(clear:GetTop() <= key:GetBottom(), "narrow hotkey row should wrap")
		key.scripts.OnClick()
		assert.is_true(geometry[key].keyboard)
		key.scripts.OnKeyDown(key, "LSHIFT")
		assert.is_nil(ns.GetBarConfig(2).key)
		_G.IsShiftKeyDown = function() return true end
		key.scripts.OnKeyDown(key, "K")
		assert.equal("SHIFT-K", ns.GetBarConfig(2).key)
		assert.is_false(geometry[key].keyboard)
		assert.is_false(geometry[key].propagate)
		key.scripts.OnClick()
		key.scripts.OnKeyDown(key, "ESCAPE")
		assert.equal("SHIFT-K", ns.GetBarConfig(2).key)
		clear.scripts.OnClick()
		assert.is_nil(ns.GetBarConfig(2).key)
		preview.scripts.OnClick()
		assert.is_true(previewing)
		assert.equal("Hide preview", geometry[preview].text)
		canvas.scripts.OnHide()
		assert.is_false(previewing)
		wow.inCombat = true
		preview.scripts.OnClick()
		key.scripts.OnClick()
		assert.is_false(previewing)
		assert.is_false(geometry[key].keyboard)
		local status, activation, placement, cursorNote
		for _, region in ipairs(regions) do
			local rect = geometry[region]
			if rect.template == "GameFontRedSmall" then status = region end
			if rect.text == "Activation" then activation = geometry[region].parent end
			if rect.text == "Placement" then placement = region end
			if rect.text == "A pointer shows the direction instead." then cursorNote = region end
		end
		assert.equal("Leave combat to change the hotkey.", geometry[status].text)
		assert.is_true(status:GetBottom() > activation:GetBottom(), "status grew outside its section")
		assert.is_true(cursorNote:GetBottom() >= activation:GetBottom(), "status growth overflowed its section")
		assert.is_true(placement:GetTop() < activation:GetBottom(), "status update overlaps the next section")
	end)
end)
