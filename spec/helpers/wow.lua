-- Minimal stand-in for the WoW client API, enough to load the addon files
-- outside the game. Frames accept any method call; attributes, scripts, and
-- secure snippets are recorded and executed by the behavioral model below.
-- This does not model the client's combat authorization or taint system.
local M = {}

local function RunHooks(object, script)
	local depth = M.secureDepth
	M.secureDepth = 0
	if object.scripts[script] then object.scripts[script](object) end
	if object.hooks[script] then object.hooks[script](object) end
	M.secureDepth = depth
end

local function NewObject(kind, parent)
	local object = { kind = kind, parent = parent, attributes = {}, scripts = {}, hooks = {}, calls = {},
		masks = {}, refs = {}, events = {}, wrappers = {}, shown = true, width = 16, height = 16, scale = 1 }
	M.objects[#M.objects + 1] = object
	return setmetatable(object, {
		__index = function(_, method)
			return function(self, ...)
				self.calls[method] = { ... }
				if M.enforceCombat and M.inCombat and M.secureDepth == 0 and rawget(self, "protected")
					and (method == "SetAttribute" or method == "Show" or method == "Hide"
						or method == "SetPoint" or method == "ClearAllPoints" or method == "SetSize"
						or method == "SetAllPoints" or method == "EnableMouse" or method == "EnableMouseMotion"
						or method == "SetPropagateMouseClicks") then
					error("insecure protected mutation: " .. method)
				end
				if method == "SetAttribute" then
					local name, value = ...
					self.attributes[name] = value
					if type(value) == "string" and name:sub(1, 1) == "_" then
						M.snippets[#M.snippets + 1] = { source = name, body = value }
					end
				elseif method == "GetAttribute" then
					return self.attributes[(...)]
				elseif method == "GetFrameRef" then
					return self.refs[(...)]
				elseif method == "GetName" then
					return self.name
				elseif method == "RunAttribute" then
					local name = ...
					return M.Run(self.attributes[name], self, nil, nil, select(2, ...))
				elseif method == "RegisterEvent" then
					self.events[(...)] = true
				elseif method == "RegisterForClicks" then
					self.clicks = {}
					for _, click in ipairs({ ... }) do self.clicks[click] = true end
				elseif method == "ClearBindings" then
					ClearOverrideBindings(self)
				elseif method == "SetBindingClick" then
					SetOverrideBindingClick(self, ...)
				elseif method == "SetScript" then
					local script, handler = ...
					self.scripts[script] = handler
				elseif method == "HookScript" then
					local script, handler = ...
					local previous = self.hooks[script]
					self.hooks[script] = function(...)
						if previous then previous(...) end
						handler(...)
					end
				elseif method == "GetFrameLevel" then
					return 1
				elseif method == "SetSize" then
					self.width, self.height = ...
				elseif method == "SetWidth" then
					self.width = ...
				elseif method == "SetHeight" then
					self.height = ...
				elseif method == "GetWidth" then
					return self.width
				elseif method == "GetHeight" then
					return self.height
				elseif method == "GetStringHeight" then
					local text = self.calls.SetText and tostring(self.calls.SetText[1]) or ""
					return 12 * math.ceil(#text * 5 / math.max(1, self.width))
				elseif method == "GetVerticalScroll" then
					return self.calls.SetVerticalScroll and self.calls.SetVerticalScroll[1] or 0
				elseif method == "GetVerticalScrollRange" then
					local child = self.calls.SetScrollChild and self.calls.SetScrollChild[1]
					return child and math.max(0, child:GetHeight() - self.height) or 0
				elseif method == "SetScale" then
					self.scale = ...
				elseif method == "GetEffectiveScale" then
					return self.scale * (parent and parent:GetEffectiveScale() or 1)
				elseif method == "GetCenter" then
					return 0, 0
				elseif method == "GetMousePosition" then
					return M.mouseX, M.mouseY
				elseif method == "Show" then
					local changed = not self.shown
					self.shown = true
					if changed then
						M.visibility[#M.visibility + 1] = { self.name, true }
						if self.attributes._onshow then M.Run(self.attributes._onshow, self) end
						RunHooks(self, "OnShow")
					end
				elseif method == "Hide" then
					local changed = self.shown
					self.shown = false
					if changed then
						M.visibility[#M.visibility + 1] = { self.name, false }
						if self.attributes._onhide then M.Run(self.attributes._onhide, self) end
						RunHooks(self, "OnHide")
					end
				elseif method == "SetShown" then
					if (...) then self:Show() else self:Hide() end
				elseif method == "IsShown" then
					return self.shown
				elseif method == "IsVisible" then
					return self.shown and (not parent or parent:IsVisible())
				elseif method == "IsMouseOver" then
					return rawget(self, "mouseOver") == true
				elseif method == "EnableMouse" then
					self.mouseClicks, self.mouseMotion = ..., ...
				elseif method == "EnableMouseMotion" then
					self.mouseMotion = ...
				elseif method == "AddMaskTexture" then
					self.masks[(...)] = true
				elseif method == "RemoveMaskTexture" then
					self.masks[(...)] = nil
				elseif method:match("^Create") then
					return NewObject(method, self)
				end
			end
		end,
	})
end

-- Models the documented hover/cursor boundary, not native input dispatch.
local function ViewportMouseFrames()
	local frames = {}
	for _, frame in ipairs(M.frames) do
		local points = frame.calls.SetAllPoints
		if frame:IsVisible() and points and points[1] == UIParent then frames[#frames + 1] = frame end
	end
	return frames
end

function M.MoveCursor(area)
	M.cursorArea, M.cursor, M.cursorHidden = area, nil, false
end

function M.WorldClick(button)
	for _, frame in ipairs(ViewportMouseFrames()) do
		local propagate = frame.calls.SetPropagateMouseClicks
		if rawget(frame, "mouseClicks") and not (propagate and propagate[1]) then return end
	end
	M.worldClicks[#M.worldClicks + 1] = button
end

local function SetModelCursor(cursor)
	if cursor == nil then
		M.cursor, M.cursorHidden = nil, false
		return true
	end
	if M.cursorArea == "world" then
		local owned = false
		for _, frame in ipairs(ViewportMouseFrames()) do
			if rawget(frame, "mouseMotion") then owned = true end
		end
		if not owned then return false end
	end
	local path = cursor:gsub("^Interface\\AddOns\\RadialBars\\", "")
	path = path:gsub("\\", package.config:sub(1, 1))
	if not path:match("%.%w+$") then path = path .. ".blp" end
	local file = io.open(path, "rb")
	local header = file and file:read(12)
	if file then file:close() end
	-- Hardware cursors require an uncompressed BLP, not an ordinary TGA texture.
	local supported = header and header:sub(1, 4) == "BLP2" and header:byte(9) == 3
	M.cursor, M.cursorHidden = supported and cursor or "black-square", supported and true or false
	return supported and true or false
end

function M.Run(body, frame, owner, down, ...)
	local chunk = assert(loadstring(body))
	setfenv(chunk, { self = frame, owner = owner, down = down, math = math })
	-- RestrictedExecution preserves self specially, but scrubs non-scalar varargs.
	local arguments, count = { ... }, select("#", ...)
	for index = 1, count do
		local kind = type(arguments[index])
		if kind ~= "nil" and kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
			arguments[index] = nil
		end
	end
	M.secureDepth = M.secureDepth + 1
	local result = { pcall(chunk, unpack(arguments, 1, count)) }
	M.secureDepth = M.secureDepth - 1
	if not result[1] then error(result[2]) end
	return unpack(result, 2)
end

function M.Click(frame, down)
	local edge = down and "Down" or "Up"
	local clicks = rawget(frame, "clicks") or { LeftButtonUp = true }
	if not clicks["Any" .. edge] and not clicks["LeftButton" .. edge] then return end
	local wrapper = frame.wrappers.OnClick
	local allowed = true
	if wrapper then allowed = M.Run(wrapper.pre, frame, wrapper.owner, down) ~= false end
	if allowed then
		if frame.attributes._onclick then M.Run(frame.attributes._onclick, frame, nil, down) end
		-- SecureActionButton_OnClick: useOnKeyDown=false executes on release.
		local useDown = frame:GetAttribute("useOnKeyDown") == true
		if frame:GetAttribute("type") == "action" and down == useDown then
			M.actions[#M.actions + 1] = frame:GetAttribute("action")
		end
		if wrapper and wrapper.post then M.Run(wrapper.post, frame, wrapper.owner, down) end
	end
end

function M.Key(key, down)
	local binding
	for _, overrides in pairs(M.bindings) do
		if overrides[key] then binding = overrides[key] end
	end
	if binding then M.Click(assert(M.named[binding.target]), down) end
end

function M.Binding(key)
	for _, overrides in pairs(M.bindings) do
		if overrides[key] then return "CLICK " .. overrides[key].target end
	end
	return M.baseBindings[key]
end

local function Stubbed()
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

-- Fresh globals and an empty addon namespace.
function M.Reset()
	M.snippets = {}
	M.frames = {}
	M.objects = {}
	M.inCombat = false
	M.enforceCombat, M.secureDepth = false, 0
	M.bindings, M.baseBindings, M.actions, M.named, M.visibility = {}, {}, {}, {}, {}
	M.mouseX, M.mouseY = 0.5, 0.5
	M.cursorArea, M.cursorHidden, M.worldClicks = "wheel", false, {}

	_G.RadialBarsDB = nil
	_G.CreateFrame = function(kind, name, parent, template)
		local frame = NewObject(kind, parent)
		frame.name = name
		frame.template = template
		frame.protected = (template and template:find("Secure") ~= nil)
			or (parent and rawget(parent, "protected")) or false
		if name then M.named[name] = frame end
		M.frames[#M.frames + 1] = frame
		return frame
	end
	_G.UIParent = NewObject("Frame")
	_G.GameTooltip = NewObject("GameTooltip")
	_G.GameTooltip_Hide = function() end
	_G.InCombatLockdown = function()
		return M.inCombat
	end
	_G.SecureHandlerSetFrameRef = function(frame, name, target) frame.refs[name] = target end
	_G.SecureHandlerWrapScript = function(frame, script, owner, pre, post)
		frame.wrappers[script] = { owner = owner, pre = pre, post = post }
		M.snippets[#M.snippets + 1] = { source = script .. " pre", body = pre }
		if post then
			M.snippets[#M.snippets + 1] = { source = script .. " post", body = post }
		end
	end
	local function CheckBindingWrite()
		if M.enforceCombat and M.inCombat and M.secureDepth == 0 then
			error("insecure binding mutation in combat")
		end
	end
	_G.ClearOverrideBindings = function(frame)
		CheckBindingWrite()
		M.bindings[frame] = {}
	end
	_G.SetOverrideBindingClick = function(frame, _, key, target, button)
		CheckBindingWrite()
		M.bindings[frame] = M.bindings[frame] or {}
		M.bindings[frame][key] = { target = target, button = button }
	end
	local function RejectBaseBindingWrite() error("native bindings must not be mutated") end
	_G.SetBinding, _G.SaveBindings = RejectBaseBindingWrite, RejectBaseBindingWrite
	_G.GetBindingAction = function(key) return M.baseBindings[key] or "" end
	_G.GetBindingText = function(key) return key end
	_G.GetBindingName = function(binding) return binding end
	_G.GetCursorPosition = function() return 0, 0 end
	_G.GetActionInfo = function() end
	_G.GetActionBarPage, _G.GetBonusBarOffset = nil, nil
	_G.IsAltKeyDown = function() return false end
	_G.IsControlKeyDown = function() return false end
	_G.IsShiftKeyDown = function() return false end
	_G.SetCursor = SetModelCursor
	_G.ResetCursor = function()
		M.cursor, M.cursorHidden = nil, false
		M.cursorResets = (M.cursorResets or 0) + 1
	end
	M.cursor, M.cursorResets = nil, 0
	_G.EMPTY = "Empty"
	_G.CANCEL = "Cancel"
	_G.SlashCmdList = {}
	_G.Settings = Stubbed()
	_G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
	_G.C_ActionBar = {
		HasAction = function() return false end,
		GetActionTexture = function(action) return "ActionTexture" .. action end,
		IsUsableAction = function() return true end,
		GetActionCooldown = function() return { startTime = 0, duration = 0, modRate = 1 } end,
		GetActionDisplayCount = function() return "" end,
	}
	_G.MinimalSliderWithSteppersMixin = {
		Label = { Right = 2 },
		Event = { OnValueChanged = "OnValueChanged" },
	}
	M.ns = {}
end

-- Loads addon files (relative to the repository root) into the namespace.
function M.Load(...)
	for _, file in ipairs({ ... }) do
		local chunk = assert(loadfile(file))
		chunk("RadialBars", M.ns)
	end
	return M.ns
end

-- Fires an event at every frame that has an OnEvent script.
function M.Fire(event, ...)
	for _, frame in ipairs(M.frames) do
		local handler = frame.scripts.OnEvent
		if handler and frame.events[event] then
			handler(frame, event, ...)
		end
	end
end

return M
