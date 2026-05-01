require("helpers")

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

-- Build a minimal staff block: each line is "<label>|..." where label is padded to label_width
local function make_staff_lines(strings, label_width)
	local lines = {}
	for _, s in ipairs(strings) do
		local padded = s .. string.rep(" ", label_width - #s)
		lines[#lines + 1] = padded .. "|--------------|"
	end
	return lines
end

before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1]) -- Standard: e B G D A E
end)

describe("staff.find_staff_top", function()
	it("returns the top row when cursor is on the top string", function()
		local lines = make_staff_lines({ "e", "B", "G", "D", "A", "E" }, 1)
		local bufnr = make_buffer(lines)
		assert.are.equal(0, staff.find_staff_top(bufnr, 0))
	end)

	it("returns the top row when cursor is on a middle string", function()
		local lines = make_staff_lines({ "e", "B", "G", "D", "A", "E" }, 1)
		local bufnr = make_buffer(lines)
		assert.are.equal(0, staff.find_staff_top(bufnr, 3))
	end)

	it("returns the top row when cursor is on the bottom string", function()
		local lines = make_staff_lines({ "e", "B", "G", "D", "A", "E" }, 1)
		local bufnr = make_buffer(lines)
		assert.are.equal(0, staff.find_staff_top(bufnr, 5))
	end)

	it("returns nil when the cursor is not on a staff line", function()
		local lines = { "not a staff line", "e|--------------|" }
		local bufnr = make_buffer(lines)
		assert.is_nil(staff.find_staff_top(bufnr, 0))
	end)

	it("returns nil when the block has fewer lines than num_strings", function()
		-- Only 3 lines but tuning expects 6
		local lines = make_staff_lines({ "e", "B", "G" }, 1)
		local bufnr = make_buffer(lines)
		assert.is_nil(staff.find_staff_top(bufnr, 0))
	end)

	it("works correctly with duplicate string names (Drop D)", function()
		state.set_tuning({ name = "Drop D", strings = { "e", "B", "G", "D", "A", "D" } })
		local lines = make_staff_lines({ "e", "B", "G", "D", "A", "D" }, 1)
		local bufnr = make_buffer(lines)
		-- Cursor on last line (low D) should still find top
		assert.are.equal(0, staff.find_staff_top(bufnr, 5))
	end)

	it("handles staff with blank lines above and below", function()
		local staff_lines = make_staff_lines({ "e", "B", "G", "D", "A", "E" }, 1)
		local lines = { "" }
		for _, l in ipairs(staff_lines) do lines[#lines + 1] = l end
		lines[#lines + 1] = ""
		local bufnr = make_buffer(lines)
		-- staff starts at row 1 (0-indexed)
		assert.are.equal(1, staff.find_staff_top(bufnr, 3))
	end)
end)
