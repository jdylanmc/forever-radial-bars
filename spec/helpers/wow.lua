-- Minimal stand-in for the WoW client API, enough to load the addon files
-- outside the game. Frames accept any method call; attributes, scripts, and
-- secure snippets are recorded for assertions.
local M = {}

local function NewObject(kind, parent)
	local object = { kind = kind, parent = parent, attributes = {}, scripts = {}, hooks = {}, calls = {},
		masks = {}, shown = true, width = 16, height = 16, scale = 1 }
	M.objects[#M.objects + 1] = object
	return setmetatable(object, {
		__index = function(_, method)
			return function(self, ...)
				self.calls[method] = { ... }
				if method == "SetAttribute" then
					local name, value = ...
					self.attributes[name] = value
					if type(value) == "string" and name:sub(1, 1) == "_" then
						M.snippets[#M.snippets + 1] = { source = name, body = value }
					end
				elseif method == "GetAttribute" then
					return self.attributes[(...)]
				elseif method == "SetScript" then
					local script, handler = ...
					self.scripts[script] = handler
				elseif method == "HookScript" then
					local script, handler = ...
					self.hooks[script] = handler
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
				elseif method == "SetScale" then
					self.scale = ...
				elseif method == "GetEffectiveScale" then
					return self.scale * (parent and parent:GetEffectiveScale() or 1)
				elseif method == "GetCenter" then
					return 0, 0
				elseif method == "Show" then
					self.shown = true
				elseif method == "Hide" then
					self.shown = false
				elseif method == "SetShown" then
					self.shown = (...) and true or false
				elseif method == "IsShown" then
					return self.shown and (not parent or parent:IsShown())
				elseif method == "IsMouseOver" then
					return rawget(self, "mouseOver") == true
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

	_G.RadialBarsDB = nil
	_G.CreateFrame = function(kind, name, parent, template)
		local frame = NewObject(kind, parent)
		frame.name = name
		frame.template = template
		M.frames[#M.frames + 1] = frame
		return frame
	end
	_G.UIParent = NewObject("Frame")
	_G.GameTooltip = NewObject("GameTooltip")
	_G.GameTooltip_Hide = function() end
	_G.InCombatLockdown = function()
		return M.inCombat
	end
	_G.SecureHandlerSetFrameRef = function() end
	_G.SecureHandlerWrapScript = function(_, script, _, pre, post)
		M.snippets[#M.snippets + 1] = { source = script .. " pre", body = pre }
		if post then
			M.snippets[#M.snippets + 1] = { source = script .. " post", body = post }
		end
	end
	_G.ClearOverrideBindings = function() end
	_G.SetOverrideBindingClick = function() end
	_G.EMPTY = "Empty"
	_G.CANCEL = "Cancel"
	_G.SlashCmdList = {}
	_G.Settings = Stubbed()
	_G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
	_G.C_ActionBar = {
		HasAction = function() return false end,
		GetActionTexture = function(action) return "ActionTexture" .. action end,
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
		if handler then
			handler(frame, event, ...)
		end
	end
end

return M
