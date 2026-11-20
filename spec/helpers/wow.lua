-- Minimal stand-in for the WoW client API, enough to load the addon files
-- outside the game. Frames accept any method call; attributes, scripts, and
-- secure snippets are recorded for assertions.
local M = {}

local function NewObject(kind)
	local object = { kind = kind, attributes = {}, scripts = {}, hooks = {} }
	return setmetatable(object, {
		__index = function(_, method)
			return function(self, ...)
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
				elseif method:match("^Create") then
					return NewObject(method)
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
	M.inCombat = false

	_G.RadialBarsDB = nil
	_G.CreateFrame = function(kind, name)
		local frame = NewObject(kind)
		frame.name = name
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
