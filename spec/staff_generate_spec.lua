require("helpers")

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1])
end)

-- Default config:
--   strings = { "e","B","G","D","A","E" }  label_width = 1
--   measure_sep = "|"
--   divisions = 4, beats_per_measure = 4, default_measures = 2
--
-- Expected line structure:
--   <label(1)><sep(1)> then for each beat: <div*3 fillers><sep>
--   total = 1 + 1 + measures * bpm * (div*3 + 1)
--            = 2 + 2 * 4 * 13 = 2 + 104 = 106

describe("staff.generate", function()
	it("returns one line per string", function()
		local lines = staff.generate()
		assert.are.equal(6, #lines)
	end)

	it("each line starts with the string label followed by the measure separator", function()
		local lines = staff.generate()
		local strings = state.tuning.strings
		-- generate() outputs strings high→low (reversed from low→high config order)
		for i, line in ipairs(lines) do
			local s = strings[#strings - i + 1]
			assert.are.equal(s .. config.options.measure_sep, line:sub(1, #s + 1))
		end
	end)

	it("each line has the correct total length", function()
		local cfg = config.options
		-- label(1) + sep(1) + measures * bpm * (div*3 + sep_width)
		local expected_len = state.label_width
			+ #cfg.measure_sep
			+ cfg.default_measures * cfg.beats_per_measure * (cfg.divisions * 3 + #cfg.measure_sep)
		local lines = staff.generate()
		for _, line in ipairs(lines) do
			assert.are.equal(expected_len, #line)
		end
	end)

	it("empty cells are filled with the filler character", function()
		local lines = staff.generate()
		local cfg = config.options
		-- Strip label+sep prefix and check that remaining chars are only filler or measure_sep
		for _, line in ipairs(lines) do
			local content = line:sub(state.label_width + #cfg.measure_sep + 1)
			assert.truthy(content:match("^[" .. cfg.filler .. "%" .. cfg.measure_sep .. "]+$"))
		end
	end)

	it("respects custom measures opt", function()
		local lines = staff.generate({ measures = 4 })
		local cfg = config.options
		local expected_len = state.label_width
			+ #cfg.measure_sep
			+ 4 * cfg.beats_per_measure * (cfg.divisions * 3 + #cfg.measure_sep)
		for _, line in ipairs(lines) do
			assert.are.equal(expected_len, #line)
		end
	end)

	it("respects custom beats_per_measure opt", function()
		local lines = staff.generate({ measures = 1, beats_per_measure = 3 })
		local cfg = config.options
		local expected_len = state.label_width + #cfg.measure_sep + 1 * 3 * (cfg.divisions * 3 + #cfg.measure_sep)
		for _, line in ipairs(lines) do
			assert.are.equal(expected_len, #line)
		end
	end)

	it("respects custom divisions opt", function()
		local lines = staff.generate({ measures = 1, divisions = 2 })
		local cfg = config.options
		local expected_len = state.label_width
			+ #cfg.measure_sep
			+ 1 * cfg.beats_per_measure * (2 * 3 + #cfg.measure_sep)
		for _, line in ipairs(lines) do
			assert.are.equal(expected_len, #line)
		end
	end)

	it("all lines have the same length", function()
		local lines = staff.generate()
		local len = #lines[1]
		for _, line in ipairs(lines) do
			assert.are.equal(len, #line)
		end
	end)
end)
