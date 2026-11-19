require("helpers")
local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

-- Default config: 6 strings, label_width = 1, so a staff block is 6 lines.

before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1])
end)

--- Build buffer lines from a list of chunks (each chunk is a list of lines).
local function lines_of(...)
	local lines = {}
	for _, chunk in ipairs({ ... }) do
		for _, line in ipairs(chunk) do
			lines[#lines + 1] = line
		end
	end
	return lines
end

describe("staff.insert_below_cursor", function()
	it("inserts a staff below the cursor line", function()
		local bufnr = make_buffer({ "hello" })
		set_cursor(1, 0)

		staff.insert_below_cursor(bufnr)

		local lines = buf_lines(bufnr)
		assert.are.equal("hello", lines[1])
		for i, staff_line in ipairs(staff.generate()) do
			assert.are.equal(staff_line, lines[i + 1])
		end
		assert.are.equal(1, staff.find_staff_top(bufnr, 1))
		-- The legend belongs under the new block, not the old one
		local legend = buf_extmarks(bufnr)[1]
		assert.are.equal(6, legend.row)
		assert.is_not_nil(legend.opts.virt_lines)
	end)

	it("keeps a blank line before a staff on the following line", function()
		local existing = staff.generate()
		local bufnr = make_buffer(lines_of({ "hello" }, existing))
		set_cursor(1, 0)

		staff.insert_below_cursor(bufnr)

		local lines = buf_lines(bufnr)
		-- New staff parses as its own block...
		assert.are.equal(1, staff.find_staff_top(bufnr, 1))
		-- ...and the existing staff still does, one blank line below it.
		assert.are.equal("", lines[8])
		assert.are.equal(8, staff.find_staff_top(bufnr, 8))
	end)

	it("keeps both staves intact when inserting from inside one", function()
		local bufnr = make_buffer(lines_of(staff.generate(), { "" }, staff.generate()))
		set_cursor(1, 2)

		staff.insert_below_cursor(bufnr)

		local lines = buf_lines(bufnr)
		-- Original staff, two blank lines, new staff, the old blank line, second staff.
		assert.are.equal(0, staff.find_staff_top(bufnr, 0))
		assert.are.equal("", lines[7])
		assert.are.equal("", lines[8])
		assert.are.equal(8, staff.find_staff_top(bufnr, 8))
		assert.are.equal("", lines[15])
		assert.are.equal(15, staff.find_staff_top(bufnr, 15))
	end)
end)
