require("helpers")

local state = require("tablature.state")

describe("state.set_tuning", function()
	it("sets M.tuning to the given tuning", function()
		local t = { name = "Standard", strings = { "e", "B", "G", "D", "A", "E" } }
		state.set_tuning(t)
		assert.are.equal(t, state.tuning)
	end)

	it("computes label_width as 1 for single-char string names", function()
		state.set_tuning({ name = "Standard", strings = { "e", "B", "G", "D", "A", "E" } })
		assert.are.equal(1, state.label_width)
	end)

	it("computes label_width as the longest string name", function()
		state.set_tuning({ name = "Test", strings = { "e", "B", "G", "D", "Ab", "Eb" } })
		assert.are.equal(2, state.label_width)
	end)

	it("updating the tuning recalculates label_width", function()
		state.set_tuning({ name = "Standard", strings = { "e", "B", "G", "D", "A", "E" } })
		assert.are.equal(1, state.label_width)
		state.set_tuning({ name = "Test", strings = { "e", "B", "G", "D", "Ab", "Eb" } })
		assert.are.equal(2, state.label_width)
	end)
end)

describe("state.reset", function()
	it("clears active, bufnr, and staff_top", function()
		state.active = true
		state.bufnr = 1
		state.staff_top = 5
		state.reset()
		assert.is_false(state.active)
		assert.is_nil(state.bufnr)
		assert.is_nil(state.staff_top)
	end)

	it("preserves tuning and label_width across reset", function()
		local t = { name = "Standard", strings = { "e", "B", "G", "D", "A", "E" } }
		state.set_tuning(t)
		state.reset()
		assert.are.equal(t, state.tuning)
		assert.are.equal(1, state.label_width)
	end)
end)
