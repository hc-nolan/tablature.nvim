require("helpers")
local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

-- Initialise config and default tuning before each test
before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1])
end)

-- Default config: label_width=1, measure_sep="|" (1 char), divisions=4, beats_per_measure=4
-- content_start = label_width(1) + sep_width(1) = 2
-- cell_width    = divisions(4) * 3 + sep_width(1) = 13

describe("staff.position_to_col", function()
	it("returns content_start for the very first position", function()
		-- measure=0, beat=0, sub=0  =>  col = 1 + 1 + 0 = 2
		assert.are.equal(2, staff.position_to_col({ measure = 0, beat = 0, sub = 0 }))
	end)

	it("advances by 3 for each sub-column", function()
		assert.are.equal(5, staff.position_to_col({ measure = 0, beat = 0, sub = 1 }))
		assert.are.equal(8, staff.position_to_col({ measure = 0, beat = 0, sub = 2 }))
	end)

	it("advances by cell_width (13) for each beat", function()
		assert.are.equal(15, staff.position_to_col({ measure = 0, beat = 1, sub = 0 }))
	end)

	it("advances by beats_per_measure * cell_width for each measure", function()
		-- measure 1, beat 0, sub 0  =>  2 + 1*4*13 = 54
		assert.are.equal(54, staff.position_to_col({ measure = 1, beat = 0, sub = 0 }))
	end)
end)

describe("staff.col_to_position", function()
	it("returns nil for columns inside the label/sep area", function()
		assert.is_nil(staff.col_to_position(0))
		assert.is_nil(staff.col_to_position(1))
	end)

	it("round-trips with position_to_col", function()
		local positions = {
			{ measure = 0, beat = 0, sub = 0 },
			{ measure = 0, beat = 0, sub = 3 },
			{ measure = 0, beat = 2, sub = 1 },
			{ measure = 1, beat = 3, sub = 0 },
		}
		for _, pos in ipairs(positions) do
			local col = staff.position_to_col(pos)
			local result = staff.col_to_position(col)
			assert.are.equal(pos.measure, result.measure)
			assert.are.equal(pos.beat, result.beat)
			assert.are.equal(pos.sub, result.sub)
		end
	end)

	it("returns nil when the cursor lands on a beat separator", function()
		-- Beat separator is at col = content_start + cell_width - 1 = 2 + 12 = 14
		assert.is_nil(staff.col_to_position(14))
	end)
end)
