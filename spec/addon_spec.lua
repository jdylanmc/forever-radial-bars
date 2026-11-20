local wow = require("spec.helpers.wow")

describe("addon files", function()
	local ns

	setup(function()
		wow.Reset()
		ns = wow.Load("Core.lua", "Changelog.lua", "Visuals.lua", "Wheel.lua", "SettingsPreview.lua", "Settings.lua")
	end)

	it("load in TOC order", function()
		local toc = assert(io.open("RadialBars.toc")):read("*a")
		local files = {}
		for line in toc:gmatch("[^\r\n]+") do
			if not line:match("^#") and line:match("%.lua$") then
				files[#files + 1] = line
			end
		end
		assert.same({ "Core.lua", "Changelog.lua", "Visuals.lua", "Wheel.lua", "SettingsPreview.lua", "Settings.lua" }, files)
		assert.is_table(ns.Wheel)
		assert.is_function(SlashCmdList.RADIALBARS)
	end)

	it("build secure snippets that compile", function()
		assert.is_true(#wow.snippets > 10)
		for _, snippet in ipairs(wow.snippets) do
			local chunk, err = loadstring(snippet.body)
			assert(chunk, snippet.source .. ": " .. tostring(err))
		end
	end)

	it("ship a changelog with the current version first", function()
		assert.is_true(#ns.CHANGELOG > 0)
		local package = assert(io.open("package.json")):read("*a")
		local version = package:match('"version"%s*:%s*"([^"]+)"')
		assert.equal(version, ns.CHANGELOG[1].version)
		for _, release in ipairs(ns.CHANGELOG) do
			assert.is_string(release.version)
			for _, section in ipairs(release.sections) do
				assert.is_true(#section.entries > 0, release.version .. " " .. section.title)
			end
		end
	end)
end)
