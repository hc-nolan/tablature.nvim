require("helpers")

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1])
end)

describe("staff.relabel_staff", function()
	it("replaces string labels with the new tuning's strings", function()
		-- Standard staff in buffer
		local lines = {
			"e|--------------|",
			"B|--------------|",
			"G|--------------|",
			"D|--------------|",
			"A|--------------|",
			"E|--------------|",
		}
		local bufnr = make_buffer(lines)
		local drop_d = { name = "Drop D", strings = { "e", "B", "G", "D", "A", "D" } }
		staff.relabel_staff(bufnr, 0, 1, drop_d)
		local result = buf_lines(bufnr)
		-- Only the last line should change (E → D)
		assert.are.equal("e|--------------|", result[1])
		assert.are.equal("B|--------------|", result[2])
		assert.are.equal("D|--------------|", result[6])
	end)

	it("content after the label is preserved", function()
		local lines = {
			"e|5-------------|",
			"B|--------------|",
			"G|--------------|",
			"D|--------------|",
			"A|--------------|",
			"E|--------------|",
		}
		local bufnr = make_buffer(lines)
		local drop_d = { name = "Drop D", strings = { "e", "B", "G", "D", "A", "D" } }
		staff.relabel_staff(bufnr, 0, 1, drop_d)
		local result = buf_lines(bufnr)
		-- First line: label stays "e", content preserved
		assert.are.equal("e|5-------------|", result[1])
	end)

	it("pads labels to new_label_width when new tuning has longer names", function()
		local lines = {
			"e|--------------|",
			"B|--------------|",
			"G|--------------|",
			"D|--------------|",
			"A|--------------|",
			"E|--------------|",
		}
		local bufnr = make_buffer(lines)
		local wide = { name = "Wide", strings = { "e ", "B ", "G ", "D ", "Ab", "Eb" } }
		staff.relabel_staff(bufnr, 0, 1, wide)
		local result = buf_lines(bufnr)
		-- Labels are now 2 chars: "e " etc. Content starts shifted right by 1
		assert.are.equal("e |--------------|", result[1])
		assert.are.equal("Ab|--------------|", result[5])
		assert.are.equal("Eb|--------------|", result[6])
	end)
end)
