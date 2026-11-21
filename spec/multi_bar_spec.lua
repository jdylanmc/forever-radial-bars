local wow = require("spec.helpers.wow")

describe("independent radial bars", function()
	local ns

	local function Config(bar, mode)
		local config = ns.GetBarConfig(bar)
		config.key, config.mode = "F" .. bar, mode or "toggle"
		return config
	end

	local function Wheel(bar)
		return ns.Wheel.instances[bar].frame
	end

	local function VisibleOnly(bar)
		for candidate = 1, 8 do
			assert.equal(candidate == bar, Wheel(candidate):IsShown(), "bar " .. candidate)
		end
	end

	local function Combat()
		ns.ApplyWhenSafe()
		wow.inCombat, wow.enforceCombat = true, true
	end

	local function PointUp()
		wow.mouseX, wow.mouseY = 0.5, 0.5 + 110 / 4096
	end

	before_each(function()
		wow.Reset()
		ns = wow.Load("Core.lua", "Visuals.lua", "Wheel.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
	end)

	it("installs all eight independent keys and keeps each bar's geometry and fixed action page", function()
		local pages = { 1, 6, 5, 3, 4, 13, 14, 15 }
		for bar = 1, 8 do
			local config = Config(bar)
			config.count, config.radius, config.iconSize = bar + 4, 60 + bar * 10, 24 + bar * 2
			config.position, config.x, config.y = "fixed", bar * 20, -bar * 10
		end
		Combat()
		for bar = 1, 8 do
			assert.matches("^CLICK RadialBarsTrigger", wow.Binding("F" .. bar))
			wow.Key("F" .. bar, true)
			wow.Key("F" .. bar, false)
			VisibleOnly(bar)
			local wheel = Wheel(bar)
			assert.same({ "CENTER", "$parent", "CENTER", bar * 20, -bar * 10 }, wheel.calls.SetPoint)
			assert.equal(bar + 4, wheel:GetAttribute("rb-count"))
			for index = 1, 12 do
				assert.equal((pages[bar] - 1) * 12 + index, wheel.refs["slot" .. index]:GetAttribute("action"))
			end
		end
		assert.same({}, wow.actions)
	end)

	it("executes every Hold key through the scrubbed coordinator boundary without selecting its edit bar", function()
		local firstSlots = { 1, 61, 49, 25, 37, 145, 157, 169 }
		for bar = 1, 8 do Config(bar, "hold") end
		Combat()
		PointUp()
		for bar = 1, 8 do
			wow.Key("F" .. bar, true)
			VisibleOnly(bar)
			wow.Key("F" .. bar, false)
			VisibleOnly(nil)
			assert.equal(firstSlots[bar], wow.actions[bar])
		end
		assert.equal(8, #wow.actions)
	end)

	it("changes the edit target without losing other configurations or bindings", function()
		local first, last = Config(1, "hold"), Config(8)
		first.radius, last.radius, last.shape = 80, 210, "slice"
		ns.ApplyWhenSafe()
		ns.db.activeBar = 8
		ns.ApplyWhenSafe()
		assert.equal(80, ns.GetBarConfig(1).radius)
		assert.equal(210, ns.GetBarConfig(8).radius)
		assert.equal("slice", Wheel(8):GetAttribute("rb-shape"))
		wow.Key("F1", true)
		VisibleOnly(1)
		wow.Key("F8", true)
		VisibleOnly(8)
		assert.same({}, wow.actions)
	end)

	it("restores the original binding on clear and moves only duplicate radial key ownership", function()
		local first, second = Config(2), Config(7, "hold")
		first.radius, second.position, second.x = 225, "fixed", 73
		wow.baseBindings.F2, wow.baseBindings.F7 = "JUMP", "TOGGLEBAG"
		ns.ApplyWhenSafe()
		ns.AssignBarKey(7, "F2")
		ns.ApplyWhenSafe()
		assert.is_nil(first.key)
		assert.equal("F2", second.key)
		assert.equal(225, first.radius)
		assert.equal("hold", second.mode)
		assert.equal(73, second.x)
		assert.equal("TOGGLEBAG", wow.Binding("F7"))
		wow.Key("F2", true)
		VisibleOnly(7)
		ns.AssignBarKey(7, nil)
		ns.ApplyWhenSafe()
		assert.equal("JUMP", wow.Binding("F2"))
		assert.same({ F2 = "JUMP", F7 = "TOGGLEBAG" }, wow.baseBindings)
	end)

	for _, mode in ipairs({ "hold", "toggle" }) do
		it("closes a held wheel before opening another " .. mode .. " wheel and rejects the old release", function()
			Config(1, "hold")
			Config(8, mode)
			Combat()
			PointUp()
			wow.Key("F1", true)
			wow.visibility = {}
			wow.Key("F8", true)
			assert.same({
				{ "RadialBarsWheelBar1", false }, { "RadialBarsWheelBar8", true },
			}, wow.visibility)
			wow.Key("F1", true) -- An old key's auto-repeat must not steal the new wheel.
			VisibleOnly(8)
			wow.Key("F1", false)
			VisibleOnly(8)
			assert.same({}, wow.actions)
			wow.Key("F8", false)
			if mode == "hold" then
				VisibleOnly(nil)
				assert.same({ 169 }, wow.actions)
			else
				VisibleOnly(8)
				assert.same({}, wow.actions)
			end
		end)
	end

	for _, cancel in ipairs({ "escape", "center", "slot" }) do
		it("invalidates a held release after " .. cancel .. " and macro reopen", function()
			Config(2, "hold")
			Combat()
			PointUp()
			wow.Key("F2", true)
			if cancel == "escape" then
				wow.Key("ESCAPE", false)
			elseif cancel == "center" then
				wow.Click(wow.named.RadialBarsCancel, false)
			else
				wow.Click(Wheel(2).refs.slot1, false)
			end
			VisibleOnly(nil)
			local executed = #wow.actions
			wow.Click(wow.named.RadialBarsOpen, false)
			wow.Key("F2", true) -- Auto-repeat from the still-held, cancelled press.
			wow.Key("F2", false)
			VisibleOnly(2)
			assert.equal(executed, #wow.actions)
			wow.Key("F2", true) -- A fresh press may arm and execute normally.
			wow.Key("F2", false)
			VisibleOnly(nil)
			assert.equal(executed + 1, #wow.actions)
			assert.equal(61, wow.actions[#wow.actions])
		end)
	end

	it("ignores autorepeat, cancels in the center, and restores a hidden cursor on switching", function()
		Config(2, "hold")
		Config(3)
		Combat()
		wow.Key("F2", true)
		Wheel(2).scripts.OnUpdate()
		assert.is_true(wow.cursorHidden)
		wow.Key("F2", true)
		wow.Key("F3", true)
		assert.is_nil(wow.cursor)
		assert.equal(1, wow.cursorResets)
		wow.Key("F2", false)
		wow.Key("F3", false)
		wow.Key("F2", true)
		wow.Key("F2", false)
		VisibleOnly(nil)
		assert.same({}, wow.actions)
	end)

	it("keeps toggle autorepeat open until a fresh press", function()
		Config(4)
		Combat()
		wow.Key("F4", true)
		wow.Key("F4", true)
		VisibleOnly(4)
		wow.Key("F4", false)
		wow.Key("F4", true)
		VisibleOnly(nil)
		assert.same({}, wow.actions)
	end)

	it("allows a rebound trigger after its old key can no longer deliver a release", function()
		Config(6, "hold")
		ns.ApplyWhenSafe()
		wow.Key("F6", true)
		ns.AssignBarKey(6, "NEW")
		ns.ApplyWhenSafe()
		wow.Key("F6", false)
		wow.Key("NEW", true)
		PointUp()
		wow.Key("NEW", false)
		VisibleOnly(nil)
		assert.same({ 145 }, wow.actions)
	end)

	it("does not rearm an unchanged held key after settings apply and macro reopen", function()
		Config(2, "hold")
		ns.ApplyWhenSafe()
		wow.Key("F2", true)
		ns.GetBarConfig(2).radius = 180
		ns.ApplyWhenSafe()
		wow.Click(wow.named.RadialBarsOpen, false)
		wow.Key("F2", true)
		PointUp()
		wow.Key("F2", false)
		VisibleOnly(2)
		assert.same({}, wow.actions)
	end)

	it("uses each instance's cursor or center placement in combat", function()
		Config(1).position = "cursor"
		Config(7).position = "center"
		Combat()
		wow.Key("F1", true)
		assert.same({ "CENTER", "$cursor" }, Wheel(1).calls.SetPoint)
		wow.Key("F7", true)
		assert.same({ "CENTER" }, Wheel(7).calls.SetPoint)
		VisibleOnly(7)
	end)

	it("does not page bar 1 when stance, form, or action-page events arrive", function()
		Config(1)
		Combat()
		wow.Key("F1", true)
		_G.GetActionBarPage = function() return 9 end
		_G.GetBonusBarOffset = function() return 5 end
		for _, event in ipairs({ "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR" }) do
			wow.Fire(event)
		end
		for index = 1, 12 do assert.equal(index, Wheel(1).refs["slot" .. index]:GetAttribute("action")) end
		VisibleOnly(1)
	end)

	it("keeps floating preview on the edit bar, refreshes copied geometry, and never arms hold actions", function()
		Config(2, "hold")
		local source = Config(8)
		source.radius, source.position, source.x, source.y = 230, "fixed", 320, -150
		ns.ApplyWhenSafe()
		ns.Wheel:SetPreview(true)
		VisibleOnly(2)
		PointUp()
		wow.Key("F2", true)
		wow.Key("F2", false)
		assert.same({}, wow.actions)
		ns.CopyBarSettings(8, 2)
		VisibleOnly(2)
		assert.is_true(ns.Wheel:IsPreviewing())
		assert.equal(528, Wheel(2):GetWidth())
		assert.same({ "CENTER", "$parent", "CENTER", 320, -150 }, Wheel(2).calls.SetPoint)
		ns.db.activeBar = 1
		ns.ApplyWhenSafe()
		VisibleOnly(1)
		assert.is_true(ns.Wheel:IsPreviewing())
		ns.Wheel:SetPreview(false)
		VisibleOnly(nil)
		assert.same({}, wow.actions)
	end)

	it("closes floating preview before combat lockdown", function()
		ns.ApplyWhenSafe()
		ns.Wheel:SetPreview(true)
		VisibleOnly(2)
		wow.Fire("PLAYER_REGEN_DISABLED")
		assert.is_false(ns.Wheel:IsPreviewing())
		VisibleOnly(nil)
		wow.inCombat, wow.enforceCombat = true, true
		ns.db.activeBar = 1
		assert.is_false(ns.ApplyWhenSafe())
		assert.same({}, wow.actions)
	end)

	it("defers all protected geometry and key changes in combat while retaining saved edits", function()
		Config(2)
		Combat()
		local oldSize = Wheel(2):GetWidth()
		ns.GetBarConfig(2).radius = 250
		ns.AssignBarKey(2, "X")
		assert.is_false(ns.ApplyWhenSafe())
		assert.equal(oldSize, Wheel(2):GetWidth())
		assert.matches("^CLICK", wow.Binding("F2"))
		assert.is_nil(wow.Binding("X"))
		wow.inCombat = false
		wow.Fire("PLAYER_REGEN_ENABLED")
		assert.is_true(Wheel(2):GetWidth() > oldSize)
		assert.matches("^CLICK", wow.Binding("X"))
		assert.is_nil(wow.Binding("F2"))
	end)
end)

describe("saved multi-bar migration", function()
	before_each(function() wow.Reset() end)

	it("retains every existing bar 2-8 value and unbound bar 1 through version 1 migration", function()
		local bars, expected = {}, {}
		for bar = 2, 8 do
			bars[bar] = {
				key = "F" .. bar, mode = "hold", position = "fixed", shape = "slice",
				x = bar * 23, y = -bar * 17, count = 4 + bar, radius = 150 + bar,
				iconSize = 42, margin = 14, hubSize = 0.5, gap = 3, sliceIconZoom = 1.65,
				backdropAlpha = 0.4, iconAlpha = 0.8, hideCursor = false, showDescription = false,
			}
			expected[bar] = {}
			for key, value in pairs(bars[bar]) do expected[bar][key] = value end
		end
		_G.RadialBarsDB = { version = 1, activeBar = 7, bars = bars }
		local ns = wow.Load("Core.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		for bar = 2, 8 do assert.same(expected[bar], ns.GetBarConfig(bar)) end
		assert.is_nil(ns.GetBarConfig(1).key)
		assert.equal(7, ns.db.activeBar)
		assert.equal(2, ns.db.version)
	end)

	it("gives the legacy operational selection its duplicate key, otherwise the lowest bar", function()
		_G.RadialBarsDB = {
			version = 1, activeBar = 7,
			bars = {
				[2] = { key = "K", radius = 80 }, [7] = { key = "K", radius = 190 },
				[3] = { key = "J" }, [8] = { key = "J" },
			},
		}
		local ns = wow.Load("Core.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		assert.equal("K", ns.GetBarConfig(7).key)
		assert.is_nil(ns.GetBarConfig(2).key)
		assert.equal("J", ns.GetBarConfig(3).key)
		assert.is_nil(ns.GetBarConfig(8).key)
		assert.equal(80, ns.GetBarConfig(2).radius)
		assert.equal(190, ns.GetBarConfig(7).radius)
		wow.Fire("ADDON_LOADED", "RadialBars")
		assert.equal("K", ns.GetBarConfig(7).key)
		assert.equal("J", ns.GetBarConfig(3).key)
	end)

	it("persists an explicit key move across a fresh load independently of the edit target", function()
		local ns = wow.Load("Core.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		ns.GetBarConfig(2).key, ns.GetBarConfig(2).radius = "K", 220
		ns.GetBarConfig(8).key, ns.GetBarConfig(8).mode = "J", "hold"
		ns.AssignBarKey(8, "K")
		local saved = { version = ns.db.version, activeBar = 2, bars = {} }
		for bar = 1, 8 do
			saved.bars[bar] = {}
			for key, value in pairs(ns.GetBarConfig(bar)) do saved.bars[bar][key] = value end
		end
		wow.Reset()
		_G.RadialBarsDB = saved
		ns = wow.Load("Core.lua", "Visuals.lua", "Wheel.lua")
		wow.Fire("ADDON_LOADED", "RadialBars")
		wow.Fire("PLAYER_LOGIN")
		assert.is_nil(ns.GetBarConfig(2).key)
		assert.equal(220, ns.GetBarConfig(2).radius)
		assert.equal("hold", ns.GetBarConfig(8).mode)
		assert.equal("K", ns.GetBarConfig(8).key)
		assert.is_nil(wow.Binding("J"))
		wow.Key("K", true)
		assert.is_true(ns.Wheel.instances[8].frame:IsShown())
		assert.is_false(ns.Wheel.instances[2].frame:IsShown())
	end)
end)
