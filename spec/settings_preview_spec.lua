local wow = require("spec.helpers.wow")

describe("embedded settings preview", function()
	local ns, preview, viewport, surface, slots, title, description, config, cursorX, cursorY, replacedGlobals

	local function Hover(x, y)
		cursorX, cursorY = x * surface:GetEffectiveScale(), y * surface:GetEffectiveScale()
		preview.mouseOver, viewport.mouseOver = true, true
		preview.scripts.OnUpdate(preview, 0)
	end

	before_each(function()
		wow.Reset()
		ns = wow.Load("Core.lua", "Visuals.lua", "SettingsPreview.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		_G.GetCursorPosition = function() return cursorX, cursorY end
		_G.C_ActionBar.HasAction = function(action) return action ~= 62 end
		_G.GetActionInfo = function(action) return "spell", action + 100 end
		_G.C_Spell = { GetSpellName = function(id) return "Spell " .. id end }
		_G.C_TooltipInfo = { GetAction = function(action)
			return { lines = { { leftText = "Name" }, { leftText = "Description " .. action } } }
		end }
		viewport = CreateFrame("ScrollFrame", nil, UIParent)
		preview = ns.CreateSettingsPreview(viewport, viewport)
		preview:SetWidth(300)
		config = ns.GetBarConfig(2)
		preview:Refresh()
		slots = {}
		for _, object in ipairs(wow.objects) do
			if object.parent == preview and object.kind == "Frame" then surface = object end
			if rawget(object, "icon") then slots[#slots + 1] = object end
		end
		for _, object in ipairs(wow.objects) do
			if object.parent == surface and object.kind == "CreateFontString" then
				if not title then title = object else description = object end
			end
		end
	end)

	after_each(function()
		title, description, surface = nil, nil, nil
		for name, saved in pairs(replacedGlobals or {}) do _G[name] = saved.value end
		replacedGlobals = nil
	end)

	it("only inspects real selected-bar actions and meaningful empty slots on hover", function()
		Hover(0, 110)
		assert.equal("Spell 161", title.calls.SetText[1])
		assert.equal("ActionTexture61", slots[1].icon.calls.SetTexture[1])
		local angle = math.rad(60)
		Hover(110 * math.cos(angle), 110 * math.sin(angle))
		assert.equal("Empty slot 2", title.calls.SetText[1])
		assert.equal("Interface\\Buttons\\UI-EmptySlot-Disabled", slots[2].icon.calls.SetTexture[1])
		Hover(0, 0)
		assert.equal("Cancel", title.calls.SetText[1])
		preview.scripts.OnLeave(preview)
		assert.equal("Hover to inspect", title.calls.SetText[1])
		assert.is_false(slots[1].highlight:IsShown())
	end)

	it("never executes, binds, moves, hides the cursor, or forwards mouse events", function()
		local function Forbidden() error("preview crossed the execution boundary") end
		local function Replace(name)
			replacedGlobals[name] = { value = rawget(_G, name) }
		end
		replacedGlobals = {}
		for _, name in ipairs({
			"SecureHandlerSetFrameRef", "SecureHandlerWrapScript", "ClearOverrideBindings", "SetOverrideBindingClick",
			"SetCursor", "ResetCursor", "UseAction", "CastSpellByID", "RunMacro", "RunMacroText",
		}) do Replace(name); _G[name] = Forbidden end
		ns.Wheel = setmetatable({}, { __index = function() return Forbidden end })
		for _, name in ipairs({ "RadialBarsOpen", "RadialBarsTrigger", "RadialBarsSelector" }) do
			Replace(name)
			_G[name] = setmetatable({}, { __index = function() return Forbidden end })
		end
		for _, shape in ipairs({ "square", "circle", "slice" }) do
			config.shape = shape
			preview:Refresh()
			Hover(0, 110)
			for _, frame in ipairs(wow.frames) do
				assert.is_nil(rawget(frame, "template"))
				assert.same({}, frame.attributes)
				for _, event in ipairs({ "OnEnter", "OnMouseDown", "OnMouseUp", "OnClick", "OnLeave", "OnHide" }) do
					local handler = frame.scripts[event]
					if handler then handler(frame, "LeftButton") end
				end
				for _, method in ipairs({ "SetFrameRef", "Click", "StartMoving", "SetBindingClick", "SetAttribute" }) do
					assert.is_nil(frame.calls[method])
				end
			end
		end
		assert.same({}, wow.snippets)
	end)

	it("reads item and macro names without running them and skips unavailable descriptions", function()
		_G.GetActionInfo = function() return "item", 900 end
		_G.C_Item = { GetItemNameByID = function(id) return "Item " .. id end }
		_G.C_TooltipInfo.GetAction = function() error("restricted tooltip") end
		config.radius, config.hubSize = 200, 0.8
		preview:Refresh()
		Hover(0, 200)
		assert.equal("Item 900", title.calls.SetText[1])
		assert.is_false(description:IsShown())
		_G.GetActionInfo = function() return "macro", 7 end
		_G.C_ActionBar.GetActionText = function(action) return "Macro label " .. action end
		preview.scripts.OnEvent(preview, "UPDATE_MACROS")
		Hover(0, 200)
		assert.equal("Macro label 61", title.calls.SetText[1])
		_G.GetActionInfo = function() error("restricted action name") end
		preview:Refresh()
		Hover(0, 200)
		assert.equal("Slot 1", title.calls.SetText[1])
	end)

	it("refreshes the saved edit bar in combat without touching deferred protected state", function()
		local applied = 0
		ns.Wheel = { Apply = function() applied = applied + 1 end }
		wow.inCombat = true
		ns.db.activeBar = 3
		local other = ns.GetBarConfig(3)
		other.shape, other.count, other.iconAlpha = "slice", 4, 0.35
		assert.is_false(ns.ApplyWhenSafe())
		preview:Refresh()
		assert.equal("ActionTexture49", slots[1].sliceIcon.calls.SetTexture[1])
		assert.equal(0.35, slots[1].sliceIcon.calls.SetAlpha[1])
		assert.is_false(slots[5]:IsShown())
		Hover(0, 110)
		assert.equal("Spell 149", title.calls.SetText[1])
		assert.equal(0, applied)
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		assert.equal(1, applied)
		assert.equal("Hover to inspect", title.calls.SetText[1])
	end)

	it("keeps all native slice masks stationary for counts 4-12 and zoom 100-200%", function()
		config.shape, config.radius, config.iconSize, config.margin, config.hubSize = "slice", 100, 40, 0, 0.5
		for count = 4, 12 do
			config.count, config.sliceIconZoom = count, 1
			preview:Refresh()
			local sizes, points, hubs = {}, {}, {}
			for index = 1, count do
				local slot = slots[index]
				sizes[index] = slot.sliceIcon.calls.SetSize[1]
				points[index] = slot.sliceIcon.calls.SetPoint
				hubs[index] = slot.sliceHubMask.calls.SetTexCoord
			end
			config.sliceIconZoom = 2
			preview:Refresh()
			for index = 1, count do
				local slot = slots[index]
				assert.near(sizes[index] * 2, slot.sliceIcon.calls.SetSize[1], 0.00001)
				assert.same(points[index], slot.sliceIcon.calls.SetPoint)
				assert.same({ 240, 240 }, slot.sliceMask.calls.SetSize)
				assert.same({ 240, 240 }, slot.sliceHubMask.calls.SetSize)
				assert.same(hubs[index], slot.sliceHubMask.calls.SetTexCoord)
				assert.equal("Interface\\AddOns\\RadialBars\\Media\\Wedge" .. count, slot.sliceMask.calls.SetTexture[1])
				assert.near(math.rad(-(index - 1) * 360 / count), slot.sliceMask.calls.SetRotation[1], 0.00001)
				assert.is_true(slot.sliceIcon.masks[slot.sliceMask])
				assert.is_true(slot.sliceIcon.masks[slot.sliceHubMask])
				local angle = math.rad(90 - (index - 1) * 360 / count)
				Hover(115 * math.cos(angle), 115 * math.sin(angle))
				assert.equal(index == 2 and "Empty slot 2" or ("Spell " .. (160 + index)), title.calls.SetText[1])
			end
			Hover(119, 119)
			assert.equal("Hover to inspect", title.calls.SetText[1])
		end
	end)

	it("restores square and circle artwork and uses shape-accurate hover targets", function()
		config.count, config.radius, config.iconSize, config.margin = 4, 100, 40, 0
		for _, shape in ipairs({ "slice", "square", "circle" }) do
			config.shape = shape
			preview:Refresh()
			if shape ~= "slice" then
				assert.is_false(slots[1].sliceIcon:IsShown())
				assert.is_true(slots[1].icon:IsShown())
				assert.same({ 40, 40 }, slots[1].calls.SetSize)
				assert.near(100, slots[1].calls.SetPoint[5], 0.00001)
				assert.equal(shape == "circle" and true or nil, slots[1].icon.masks[slots[1].iconMask])
				Hover(19, 119)
				assert.equal(shape == "square" and "Spell 161" or "Hover to inspect", title.calls.SetText[1])
				local extent = shape == "square" and 122.4 or 120
				assert.near(300, extent * 2 * surface.scale, 0.00001)
			end
		end
	end)

	it("hits a visible square corner even when a different angular sector is nearer", function()
		config.shape, config.count, config.radius, config.iconSize = "square", 8, 110, 72
		preview:Refresh()
		Hover(-33, 76)
		assert.equal("Spell 161", title.calls.SetText[1])
		assert.is_true(slots[1].highlight:IsShown())
		assert.is_false(slots[8].highlight:IsShown())
	end)

	it("uses slot order consistently where square or circle icons overlap", function()
		config.count, config.radius, config.iconSize = 12, 60, 72
		for _, shape in ipairs({ "square", "circle" }) do
			config.shape = shape
			preview:Refresh()
			Hover(-20, 60)
			assert.equal("Spell 161", title.calls.SetText[1])
			assert.is_true(slots[1].highlight:IsShown())
			assert.is_false(slots[12].highlight:IsShown())
		end
	end)

	it("skips event and hover work while only an ancestor is hidden, then refreshes on reopen", function()
		local artwork, geometry, scale = slots[1].icon.calls.SetTexture, surface.calls.SetSize, surface.calls.SetScale
		viewport:Hide()
		assert.is_true(preview:IsShown())
		assert.is_false(preview:IsVisible())
		ns.db.activeBar = 3
		_G.C_ActionBar.GetActionTexture = function(action) return "ChangedTexture" .. action end
		for _, event in ipairs({
			"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_STATE", "SPELLS_CHANGED", "UPDATE_MACROS",
			"UPDATE_SHAPESHIFT_FORM", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED",
		}) do wow.Fire(event) end
		Hover(0, 110)
		assert.equal(artwork, slots[1].icon.calls.SetTexture)
		assert.equal(geometry, surface.calls.SetSize)
		assert.equal(scale, surface.calls.SetScale)
		assert.equal("Hover to inspect", title.calls.SetText[1])
		viewport:Show()
		preview.scripts.OnShow(preview)
		assert.is_true(preview:IsVisible())
		assert.equal("ChangedTexture49", slots[1].icon.calls.SetTexture[1])
		Hover(0, 110)
		assert.equal("Spell 149", title.calls.SetText[1])
	end)

	it("reflects appearance, description, action events and clears hover on lifecycle and viewport changes", function()
		config.radius, config.iconSize, config.margin, config.hubSize = 200, 60, 30, 0.8
		config.backdropAlpha, config.iconAlpha, config.gap = 0.25, 0.5, 7
		preview:Refresh()
		assert.same({ 520, 520 }, surface.calls.SetSize)
		assert.equal(0.5, slots[1].calls.SetAlpha[1])
		Hover(0, 200)
		assert.equal("Spell 161", title.calls.SetText[1])
		assert.equal("Description 61", description.calls.SetText[1])
		assert.is_true(description:IsShown())
		config.showDescription = false
		preview:Refresh()
		Hover(0, 200)
		assert.is_false(description:IsShown())
		for _, size in ipairs({ 180, 640, 250 }) do
			preview:Layout(size)
			assert.equal(math.min(size, 320), preview:GetHeight())
			assert.near(math.min(size, 320), surface.width * surface.scale, 0.00001)
			assert.equal("Hover to inspect", title.calls.SetText[1])
		end
		Hover(0, 200)
		viewport.mouseOver = false
		preview.scripts.OnUpdate(preview, 0)
		assert.equal("Hover to inspect", title.calls.SetText[1])
		for _, event in ipairs({ "OnHide", "OnShow" }) do
			Hover(0, 200)
			preview.scripts[event](preview)
			assert.equal("Hover to inspect", title.calls.SetText[1])
		end
		Hover(0, 200)
		wow.Fire("ACTIONBAR_SLOT_CHANGED", 61)
		assert.equal("Hover to inspect", title.calls.SetText[1])
	end)
end)
