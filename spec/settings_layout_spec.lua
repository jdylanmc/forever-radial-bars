local wow = require("spec.helpers.wow")

-- Approximate wrapped text and anchors, not client rendering or actual font metrics.
local function TrackLayout()
	local regions, geometry = {}, {}
	local function Edge(point)
		return point:find("TOP") and 0 or (point:find("BOTTOM") and 1 or 0.5)
	end
	local function Track(object, kind, parent, template)
		local size = (kind == "Frame" or kind == "ScrollFrame") and 0 or 16
		local rect = { parent = parent, points = {}, width = size, height = size, offset = 0, kind = kind, template = template }
		if kind == "FontString" then
			rect.width = nil
			rect.fontHeight = template == "GameFontNormalLarge" and 16 or 12
			rect.height = nil
		elseif template == "MinimalSliderWithSteppersTemplate" then
			-- Pinned Forever MinimalSlider.xml gives this template a 250 x 40 size.
			rect.width, rect.height = 250, 40
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
			return rect.fontHeight * math.max(1, math.ceil(#(rect.text or "") * 5 / (rect.width or 300)))
		end
		function object:GetHeight()
			local first, last = rect.points[1], rect.points[2]
			if first and last then
				assert(first.relative == last.relative, "fixture only supports opposing anchors to the same parent")
				return first.relative:GetHeight() * (Edge(last.relativePoint) - Edge(first.relativePoint))
					+ first.y - last.y
			end
			if rect.text and rect.width then
				return rect.height or self:GetStringHeight()
			end
			return rect.height
		end
		function object:GetTop()
			if self:GetHeight() <= 0 then return end
			if rect.top then return rect.top end
			local point = rect.points[1]
			if not point or (geometry[parent] and not parent:GetTop()) then return end
			local relativeTop = point.relative:GetTop()
			if not relativeTop then return end
			local top = relativeTop - point.relative:GetHeight() * Edge(point.relativePoint)
				+ point.y + self:GetHeight() * Edge(point.point)
			local owner = geometry[parent]
			return top + (owner and owner.child == self and owner.offset or 0)
		end
		function object:GetBottom()
			local top = self:GetTop()
			return top and top - self:GetHeight()
		end
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
		ns = wow.Load("Core.lua", "Changelog.lua", "Visuals.lua", "SettingsPreview.lua")
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

	it("sizes every initially zero-height section on the first show in a resolved viewport", function()
		Resize(601, 665)
		local count = 0
		for _, region in ipairs(regions) do
			if geometry[region].parent == geometry[scroll].child and geometry[region].kind == "Frame" then
				count = count + 1
				assert.is_true(region:GetHeight() > 0, "section must not wait on its zero-height rectangle")
				assert.is_number(region:GetTop())
			end
		end
		assert.equal(5, count)
		assert.is_true(scroll:GetVerticalScrollRange() > 0)
		scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
		assert.is_true(finalNote:GetBottom() >= scroll:GetBottom())
	end)

	it("measures initially zero-height sections before absolute coordinates resolve and on reopening", function()
		local sections = {}
		for _, region in ipairs(regions) do
			if geometry[region].template == "GameFontNormalLarge" and geometry[region].parent ~= scroll then
				local section = geometry[region].parent
				if geometry[section].parent == geometry[scroll].child then
					sections[#sections + 1] = section
					assert.equal(0, section:GetHeight())
					assert.is_nil(section:GetTop())
				end
			end
		end
		assert.equal(5, #sections)
		geometry[canvas].top = nil
		Resize(601, 665)
		for _, section in ipairs(sections) do
			assert.is_true(section:GetHeight() > 0, "section must measure without an absolute rectangle")
		end
		local content = geometry[scroll].child
		assert.is_true(content:GetHeight() > scroll:GetHeight())
		geometry[canvas].top = 1008
		for _, section in ipairs(sections) do assert.is_number(section:GetTop()) end
		scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
		assert.is_true(finalNote:GetBottom() >= scroll:GetBottom())
		canvas.scripts.OnHide()
		Resize(601, 665)
		assert.is_true(finalNote:GetBottom() >= scroll:GetBottom())
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
					if region ~= scroll and DescendsFrom(region, scroll) and region:GetEffectiveScale() == 1 then
						assert.is_true(region:GetLeft() >= scroll:GetLeft(), "content escapes the left edge")
						assert.is_true(region:GetRight() <= scroll:GetRight(), "content escapes the right edge")
					end
				end
			end
		end
	end)

	it("lays out the embedded preview in Placement and preserves scroll reachability after it grows", function()
		Resize(310, 320)
		local preview, placement, layout
		for _, region in ipairs(regions) do
			local text = geometry[region].text
			if text == "Placement" then placement = geometry[region].parent end
			if text == "Wheel layout" then layout = geometry[region].parent end
			if rawget(region, "Refresh") and rawget(region, "Layout") then preview = region end
		end
		assert.is_not_nil(preview)
		assert.equal(placement, geometry[preview].parent)
		assert.near(scroll:GetWidth() - 32, preview:GetWidth(), 0.001)
		assert.near(preview:GetWidth(), preview:GetHeight(), 0.001)
		assert.is_true(layout:GetTop() < preview:GetBottom())
		for _, width in ipairs({ 320, 960, 400 }) do
			Resize(310, width)
			assert.near(math.min(320, scroll:GetWidth() - 32), preview:GetHeight(), 0.001)
			scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
			assert.is_true(finalNote:GetBottom() >= scroll:GetBottom())
		end
	end)

	it("clears the old scroll offset when a larger viewport fits all settings", function()
		assert.is_not_nil(scroll)
		Resize(310)
		scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
		Resize(3000)
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
			["Action bar"] = {
				1, 2, 3, 4, 5, 6, 7, 8, "copySource1", "copySource2", "copySource3", "copySource4",
				"copySource5", "copySource6", "copySource7", "copySource8", "Copy settings",
			},
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

	it("refreshes embedded artwork through real bar and slider handlers while protected apply is deferred", function()
		Resize(310, 320)
		_G.C_ActionBar.HasAction = function() return true end
		local controls, slot = {}, nil
		for _, region in ipairs(regions) do
			local key = rawget(region, "key") or rawget(region, "value")
			if key then controls[key] = region end
			if rawget(region, "sliceIcon") and not slot then slot = region end
		end
		wow.inCombat = true
		controls[3].scripts.OnClick()
		controls.slice.scripts.OnClick()
		assert.equal("ActionTexture49", slot.sliceIcon.calls.SetTexture[1])
		local size = slot.sliceIcon.calls.SetSize[1]
		geometry[controls.sliceIconZoom].callback(controls.sliceIconZoom, 2)
		assert.near(size * 2 / 1.15, slot.sliceIcon.calls.SetSize[1], 0.00001)
		assert.same({ 288, 288 }, slot.sliceMask.calls.SetSize)
		assert.equal(0, applied)
		assert.equal(2, ns.GetBarConfig(3).sliceIconZoom)
		assert.equal(1.15, ns.GetBarConfig(2).sliceIconZoom)
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		assert.equal(1, applied)
	end)

	it("copies from an explicit source to the edit target and refreshes controls and inline artwork in combat", function()
		Resize(610)
		_G.C_ActionBar.HasAction = function() return true end
		local controls, copy, slot = {}, nil, nil
		for _, region in ipairs(regions) do
			local key = rawget(region, "key") or rawget(region, "value")
			if key then controls[key] = region end
			if geometry[region].text == "Copy settings" then copy = region end
			if rawget(region, "sliceIcon") and not slot then slot = region end
		end
		local source = ns.GetBarConfig(8)
		source.shape, source.radius, source.sliceIconZoom, source.key = "slice", 170, 1.8, "S"
		ns.GetBarConfig(1).key = "D"
		controls[1].scripts.OnClick()
		controls.copySource1.scripts.OnClick()
		assert.is_false(geometry[copy].enabled)
		controls.copySource8.scripts.OnClick()
		assert.is_true(geometry[copy].enabled)
		wow.inCombat = true
		local count = applied
		copy.scripts.OnClick()
		assert.equal(count, applied)
		assert.equal(170, geometry[controls.radius].value)
		assert.equal(1.8, geometry[controls.sliceIconZoom].value)
		assert.is_true(geometry[controls.slice].checked)
		assert.equal("ActionTexture1", slot.sliceIcon.calls.SetTexture[1])
		assert.equal("D", ns.GetBarConfig(1).key)
		assert.equal("S", source.key)
		assert.equal(2, ns.GetBarConfig(2).gap)
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		assert.equal(count + 1, applied)
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
		ns.GetBarConfig(8).key, ns.GetBarConfig(8).radius = "SHIFT-K", 225
		_G.IsShiftKeyDown = function() return true end
		key.scripts.OnKeyDown(key, "K")
		assert.equal("SHIFT-K", ns.GetBarConfig(2).key)
		assert.is_nil(ns.GetBarConfig(8).key)
		assert.equal(225, ns.GetBarConfig(8).radius)
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
