require("helpers")

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

-- Default config: beats=4, default_measures=8, measure_sep="|"
-- Line structure: <label(1)><sep(1)> then for each measure: <beats*3 filler chars><sep>
-- With beats=4: each measure is 12 filler chars + "|" = 13 chars

before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1])
end)

--- Build a buffer from a generated staff using the current config.
--- Returns bufnr and staff_top (always 0 since we put staff at top).
local function make_staff(opts)
	local lines = staff.generate(opts)
	local bufnr = make_buffer(lines)
	return bufnr, 0
end

describe("staff.get_measure_beats", function()
	it("returns config beats for a freshly generated staff", function()
		local bufnr, top = make_staff()
		assert.are.equal(4, staff.get_measure_beats(bufnr, top, 0))
		assert.are.equal(4, staff.get_measure_beats(bufnr, top, 1))
	end)

	it("reflects a custom beat count passed to generate", function()
		local bufnr, top = make_staff({ beats = 8 })
		assert.are.equal(8, staff.get_measure_beats(bufnr, top, 0))
		assert.are.equal(8, staff.get_measure_beats(bufnr, top, 1))
	end)

	it("reads the correct measure when measures have different beat counts", function()
		local bufnr, top = make_staff()
		-- Reformat measure 1 to 8 beats; measure 0 stays at 4
		staff.set_measure_beats(bufnr, top, 1, 8)
		assert.are.equal(4, staff.get_measure_beats(bufnr, top, 0))
		assert.are.equal(8, staff.get_measure_beats(bufnr, top, 1))
	end)
end)

describe("staff.set_measure_beats", function()
	it("expands a measure by inserting filler columns", function()
		local bufnr, top = make_staff()
		staff.set_measure_beats(bufnr, top, 0, 8)
		-- Measure 0 should now have 8 beats
		assert.are.equal(8, staff.get_measure_beats(bufnr, top, 0))
	end)

	it("shrinks a measure by removing trailing columns", function()
		local bufnr, top = make_staff()
		staff.set_measure_beats(bufnr, top, 0, 2)
		assert.are.equal(2, staff.get_measure_beats(bufnr, top, 0))
	end)

	it("updates all string rows consistently", function()
		local bufnr, top = make_staff()
		staff.set_measure_beats(bufnr, top, 0, 8)
		local div0 = staff.get_measure_beats(bufnr, top, 0)
		-- Verify every string row has the same measure 0 beat count
		-- (get_measure_beats reads row 0; check row 1 manually)
		local lines = buf_lines(bufnr)
		local sep = config.options.measure_sep
		local lw = state.label_width
		-- Find the first beat sep position in row 2 (index 2, 1-indexed)
		local row2 = lines[2]
		local sp = row2:find(sep, lw + 2, true) -- skip label+sep, find first measure sep
		local measure_content_len = sp - (lw + 2)
		assert.are.equal(div0 * 3, measure_content_len)
	end)

	it("does not affect other measures", function()
		local bufnr, top = make_staff()
		staff.set_measure_beats(bufnr, top, 0, 8)
		-- Measure 1 should still be 4
		assert.are.equal(4, staff.get_measure_beats(bufnr, top, 1))
	end)

	it("preserves existing notes in expanding measures", function()
		local bufnr, top = make_staff()
		-- Write a note at measure 0, beat 0 on string 0
		local pos = { measure = 0, beat = 0 }
		staff.write_char(bufnr, top, 0, pos, "5")
		-- Expand measure 0 from 4 to 8 beats
		staff.set_measure_beats(bufnr, top, 0, 8)
		-- The note should still be at the same position
		local col = staff.position_to_col(bufnr, top, pos)
		local line = buf_lines(bufnr)[1]
		assert.are.equal("5", line:sub(col + 1, col + 1))
	end)
end)

describe("staff.position_to_col", function()
	it("accounts for a wider measure 0 when computing measure 1 column", function()
		local bufnr, top = make_staff()
		staff.set_measure_beats(bufnr, top, 0, 8)
		-- With uniform beats=4: measure 1, beat 0 column would be
		-- label(1) + sep(1) + 1 measure * (4*3+1) = 2 + 13 = 15
		local uniform_col = staff.position_to_col({ measure = 1, beat = 0 })
		-- With beats=8 for measure 0: col should be larger
		local buf_col = staff.position_to_col(bufnr, top, { measure = 1, beat = 0 })
		assert.is_true(buf_col > uniform_col)
	end)
end)

describe("staff.col_to_position", function()
	it("round-trips with position_to_col", function()
		local bufnr, top = make_staff()
		local pos = { measure = 1, beat = 3 }
		local col = staff.position_to_col(bufnr, top, pos)
		local back = staff.col_to_position(bufnr, top, col)
		assert.are.equal(pos.measure, back.measure)
		assert.are.equal(pos.beat, back.beat)
	end)

	it("round-trips correctly after measure 0 is resized", function()
		local bufnr, top = make_staff()
		staff.set_measure_beats(bufnr, top, 0, 8)
		local pos = { measure = 1, beat = 1 }
		local col = staff.position_to_col(bufnr, top, pos)
		local back = staff.col_to_position(bufnr, top, col)
		assert.are.equal(pos.measure, back.measure)
		assert.are.equal(pos.beat, back.beat)
	end)

	it("returns nil for a column on a separator", function()
		local bufnr, top = make_staff()
		-- The separator after the label is at column label_width (0-indexed)
		local sep_col = state.label_width
		assert.is_nil(staff.col_to_position(bufnr, top, sep_col))
	end)
end)
