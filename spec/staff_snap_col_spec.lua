require("helpers")

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

-- Default config: label_width = 1, measure_sep = "|", beats = 4, so a staff line
-- is "e|" followed by 4 beats of 3 chars (12) plus the closing "|" per measure:
--   col 0 = label, col 1 = sep, col 2..13 = measure 0 content, col 14 = sep, ...
-- A cursor parked on a separator has no cell; entering tab mode there used to
-- leave the mode on with no position.

before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1])
end)

local function make_staff()
	return make_buffer(staff.generate()), 0
end

describe("staff.snap_col_to_position", function()
	it("keeps a column that is already on a cell", function()
		local bufnr, top = make_staff()
		local pos = staff.snap_col_to_position(bufnr, top, 5)
		assert.are.equal(0, pos.measure)
		assert.are.equal(1, pos.beat)
	end)

	it("moves forward off the separator before a measure", function()
		local bufnr, top = make_staff()
		local pos = staff.snap_col_to_position(bufnr, top, 14) -- sep closing measure 0
		assert.are.equal(1, pos.measure)
		assert.are.equal(0, pos.beat)
	end)

	it("moves forward off the separator before the first measure", function()
		local bufnr, top = make_staff()
		local pos = staff.snap_col_to_position(bufnr, top, 1) -- sep after the label
		assert.are.equal(0, pos.measure)
		assert.are.equal(0, pos.beat)
	end)

	it("moves backward when there is no cell after the separator", function()
		local bufnr, top = make_staff()
		local line = buf_lines(bufnr)[1]
		local pos = staff.snap_col_to_position(bufnr, top, #line - 1) -- trailing sep
		assert.are.equal(7, pos.measure) -- default_measures - 1
		assert.are.equal(3, pos.beat)
	end)

	it("snaps the string label onto the first cell", function()
		local bufnr, top = make_staff()
		local pos = staff.snap_col_to_position(bufnr, top, 0)
		assert.are.equal(0, pos.measure)
		assert.are.equal(0, pos.beat)
	end)

	it("returns nil for a line that is not a staff", function()
		local bufnr = make_buffer({ "plain text" })
		assert.is_nil(staff.snap_col_to_position(bufnr, 0, 3))
	end)
end)
