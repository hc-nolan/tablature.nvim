require("helpers")

local config = require("tablature.config")

-- Backported from tablature-obsidian: a shape whose length doesn't match the
-- staff would be written onto the wrong strings, so it is never offered.

before_each(function()
	config.set()
end)

describe("config.chord_shapes_for", function()
	it("merges default shapes with the tuning's own shapes", function()
		local shapes = config.chord_shapes_for("Standard", 6)
		assert.are.same({ "0", "2", "2", "x", "x", "x" }, shapes["Power 5th (E root)"])
		assert.are.same({ "0", "2", "2", "1", "0", "0" }, shapes["Major (E shape)"])
	end)

	it("drops shapes that do not match the string count", function()
		config.set({
			chords = {
				default = { ["Six string"] = { "0", "2", "2", "1", "0", "0" } },
				Bass = { ["Four string"] = { "0", "2", "2", "0" } },
			},
		})

		local shapes = config.chord_shapes_for("Bass", 4)
		assert.is_nil(shapes["Six string"])
		assert.are.same({ "0", "2", "2", "0" }, shapes["Four string"])

		local guitar = config.chord_shapes_for("Bass", 6)
		assert.are.same({ "0", "2", "2", "1", "0", "0" }, guitar["Six string"])
		assert.is_nil(guitar["Four string"])
	end)

	it("prefers the tuning's shape when a default shape has the same name", function()
		config.set({
			chords = {
				default = { ["Power"] = { "0", "2", "2", "x", "x", "x" } },
				Bass = { ["Power"] = { "0", "0", "0", "x" } },
			},
		})

		assert.are.same({ "0", "0", "0", "x" }, config.chord_shapes_for("Bass", 4)["Power"])
		assert.are.same({ "0", "2", "2", "x", "x", "x" }, config.chord_shapes_for("Bass", 6)["Power"])
	end)

	it("falls back to the default shapes for an unknown tuning name", function()
		local shapes = config.chord_shapes_for("Nope", 6)
		assert.are.same({ "0", "2", "2", "x", "x", "x" }, shapes["Power 5th (E root)"])
		assert.is_nil(shapes["Major (E shape)"])
	end)

	it("returns nothing when no shape matches the string count", function()
		assert.are.same({}, config.chord_shapes_for("Standard", 7))
	end)
end)
