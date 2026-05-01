require("helpers")

local config = require("tablature.config")
local state = require("tablature.state")

describe("config.set", function()
	it("applies defaults when called with no arguments", function()
		config.set()
		assert.are.equal(true, config.options.default_mappings)
		assert.are.equal(4, config.options.divisions)
		assert.are.equal(4, config.options.beats_per_measure)
		assert.are.equal(2, config.options.default_measures)
		assert.are.equal("-", config.options.filler)
		assert.are.equal("|", config.options.measure_sep)
		assert.are.same({ "E", "A", "D", "G", "B", "e" }, config.options.tunings[1].strings)
	end)

	it("user values override defaults", function()
		config.set({ divisions = 2, beats_per_measure = 3 })
		assert.are.equal(2, config.options.divisions)
		assert.are.equal(3, config.options.beats_per_measure)
		-- non-overridden values stay at defaults
		assert.are.equal(2, config.options.default_measures)
	end)

	it("derives label_width from active tuning via state.set_tuning", function()
		config.set()
		state.set_tuning(config.options.tunings[1])
		-- default strings are all 1 char ("e","B","G","D","A","E")
		assert.are.equal(1, state.label_width)
	end)

	it("recomputes label_width for multi-char string names", function()
		state.set_tuning({ name = "Test", strings = { "e", "B", "G", "D", "Ab", "Eb" } })
		assert.are.equal(2, state.label_width)
	end)

	it("is safe to call multiple times — last call wins", function()
		config.set({ divisions = 8 })
		config.set({ divisions = 2 })
		assert.are.equal(2, config.options.divisions)
	end)

	it("chords is nested: default key plus per-tuning keys", function()
		config.set()
		local chords = config.options.chords
		assert.is_table(chords)
		assert.is_table(chords.default, "chords.default should exist")
		assert.is_table(chords.Standard, "chords.Standard should exist")
		assert.is_table(chords["Drop D"], "chords['Drop D'] should exist")
	end)

	it("default chords include tuning-agnostic power chord shapes", function()
		config.set()
		assert.is_table(config.options.chords.default["Power 5th (E root)"])
		assert.is_table(config.options.chords.default["Power 5th (A root)"])
	end)

	it("Standard chords include E-shape and A-shape movable barre shapes", function()
		config.set()
		local std = config.options.chords.Standard
		assert.is_table(std["Major (E shape)"])
		assert.is_table(std["Minor (E shape)"])
		assert.is_table(std["Major (A shape)"])
		assert.is_table(std["Minor (A shape)"])
	end)

	it("all shape values are 'x' or numeric strings", function()
		config.set()
		local chords = config.options.chords
		for _, group in pairs(chords) do
			for shape_name, shape in pairs(group) do
				for _, fret in ipairs(shape) do
					assert.is_true(fret == "x" or tonumber(fret) ~= nil,
						("shape %q has non-numeric, non-x value %q"):format(shape_name, fret))
				end
			end
		end
	end)

	it("user can add shapes to a tuning without losing defaults", function()
		config.set({ chords = { Standard = { ["My shape"] = { "0", "2", "2", "1", "0", "0" } } } })
		assert.is_table(config.options.chords.Standard["My shape"])
		assert.is_table(config.options.chords.Standard["Major (E shape)"])
		assert.is_table(config.options.chords.default["Power 5th (E root)"])
	end)
end)
