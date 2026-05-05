require("helpers")
local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

-- Initialise config and default tuning before each test
before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1])
end)

-- Default config: label_width=1, measure_sep="|" (1 char), beats=4
-- content_start = label_width(1) + sep_width(1) = 2
-- cell_width    = beats(4) * 3 + sep_width(1) = 13  (one measure)

describe("staff.position_to_col", function()
	it("returns content_start for the very first position", function()
		-- measure=0, beat=0  =>  col = 1 + 1 + 0 = 2
		assert.are.equal(2, staff.position_to_col({ measure = 0, beat = 0 }))
	end)

	it("advances by 3 for each beat slot", function()
		assert.are.equal(5, staff.position_to_col({ measure = 0, beat = 1 }))
		assert.are.equal(8, staff.position_to_col({ measure = 0, beat = 2 }))
	end)

	it("advances by cell_width (13) for each measure", function()
		assert.are.equal(15, staff.position_to_col({ measure = 1, beat = 0 }))
	end)

	it("advances by 2 * cell_width for measure 2", function()
		-- measure 2, beat 0  =>  2 + 2*13 = 28
		assert.are.equal(28, staff.position_to_col({ measure = 2, beat = 0 }))
	end)
end)

describe("staff.col_to_position", function()
	it("returns nil for columns inside the label/sep area", function()
		assert.is_nil(staff.col_to_position(0))
		assert.is_nil(staff.col_to_position(1))
	end)

	it("round-trips with position_to_col", function()
		local positions = {
			{ measure = 0, beat = 0 },
			{ measure = 0, beat = 3 },
			{ measure = 0, beat = 2 },
			{ measure = 1, beat = 3 },
		}
		for _, pos in ipairs(positions) do
			local col = staff.position_to_col(pos)
			local result = staff.col_to_position(col)
			assert.are.equal(pos.measure, result.measure)
			assert.are.equal(pos.beat, result.beat)
		end
	end)

	it("returns nil when the cursor lands on a measure separator", function()
		-- Separator is at col = content_start + beats*3 = 2 + 12 = 14
		assert.is_nil(staff.col_to_position(14))
	end)
end)
