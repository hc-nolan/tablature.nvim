require("helpers")

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")

-- 6-string standard tuning, label_width = 1
-- beats_per_measure = 4, divisions = 2 → each beat is |------
-- position_to_col for {measure=0, beat=0, sub=0} → label_width + 1 (past the opening |)
-- col = 1 + 1 = 2  (0-indexed: label "e" at 0, "|" at 1, first content at 2)

before_each(function()
	config.set()
	state.set_tuning(config.options.tunings[1]) -- Standard: E A D G B e (low→high)
end)

-- Build a minimal 6-string staff at staff_top=0 with one measure.
-- Line format: <label>|<beat*divisions*3>|  e.g. "e|------|------| ..."
local function make_staff()
	local cfg = config.options
	local strings_display = {} -- high→low for display (reverse of storage)
	local ns = #state.tuning.strings
	for i = ns, 1, -1 do
		strings_display[#strings_display + 1] = state.tuning.strings[i]
	end
	local lines = {}
	for _, lbl in ipairs(strings_display) do
		local content = "|"
		for _ = 1, cfg.beats_per_measure do
			content = content .. string.rep(cfg.filler, cfg.divisions * 3) .. "|"
		end
		lines[#lines + 1] = lbl .. content
	end
	return make_buffer(lines)
end

local pos0 = { measure = 0, beat = 0, sub = 0 } -- first playable column
local pos1 = { measure = 0, beat = 0, sub = 1 } -- second sub-division

describe("staff.write_char", function()
	it("writes a single digit into the correct column on the correct string", function()
		local bufnr = make_staff()
		-- string_idx=0 is the top row (high e string)
		staff.write_char(bufnr, 0, 0, pos0, "5")
		local lines = buf_lines(bufnr)
		-- label_width=1, measure_sep="|" → col 2 in 0-indexed → char at position 3 in 1-indexed
		assert.is_truthy(lines[1]:find("5", 1, true))
		assert.are.equal("5", lines[1]:sub(3, 3))
	end)

	it("clears overflow slot when writing a filler", function()
		local bufnr = make_staff()
		-- First write a double-digit so overflow is filled, then clear with filler
		staff.write_double_digit(bufnr, 0, 0, pos0, "1", "2")
		local before = buf_lines(bufnr)[1]
		assert.are.equal("12", before:sub(3, 4))
		-- Now clear it
		staff.write_char(bufnr, 0, 0, pos0, config.options.filler)
		local after = buf_lines(bufnr)[1]
		assert.are.equal("--", after:sub(3, 4))
	end)

	it("does not affect other strings", function()
		local bufnr = make_staff()
		staff.write_char(bufnr, 0, 0, pos0, "7")
		local lines = buf_lines(bufnr)
		-- Rows 2-6 (1-indexed) should be unchanged (all dashes at col 3)
		for i = 2, 6 do
			assert.are.equal("-", lines[i]:sub(3, 3))
		end
	end)
end)

describe("staff.write_double_digit", function()
	it("writes tens+ones on the target string", function()
		local bufnr = make_staff()
		staff.write_double_digit(bufnr, 0, 2, pos0, "1", "2") -- string_idx=2, G string
		local lines = buf_lines(bufnr)
		assert.are.equal("12", lines[3]:sub(3, 4)) -- row 3 (1-indexed)
	end)

	it("clears content+overflow on all other strings", function()
		local bufnr = make_staff()
		-- Write something on another string first
		staff.write_char(bufnr, 0, 0, pos0, "5")
		-- Now write double-digit on string_idx=2; should clear string_idx=0
		staff.write_double_digit(bufnr, 0, 2, pos0, "1", "0")
		local lines = buf_lines(bufnr)
		-- string_idx=0 (row 1) should have filler in both content and overflow slots
		assert.are.equal("--", lines[1]:sub(3, 4))
	end)
end)

-- Helper: apply a root offset to a shape the same way mode.lua does.
local function apply_offset(shape, offset)
	local voicing = {}
	for i, v in ipairs(shape) do
		if v == "x" then
			voicing[i] = "x"
		else
			local n = tonumber(v)
			voicing[i] = n and tostring(n + offset) or v
		end
	end
	return voicing
end

describe("apply_offset (chord shape helper)", function()
	it("leaves muted strings unchanged", function()
		local shape = { "x", "0", "2", "2", "2", "0" }
		local result = apply_offset(shape, 3)
		assert.are.equal("x", result[1])
	end)

	it("adds offset to all numeric values", function()
		local shape = { "0", "2", "2", "1", "0", "0" } -- E-shape major
		local result = apply_offset(shape, 1) -- → F barre
		assert.are.same({ "1", "3", "3", "2", "1", "1" }, result)
	end)

	it("offset 0 is identity", function()
		local shape = { "x", "0", "2", "2", "1", "0" }
		assert.are.same(shape, apply_offset(shape, 0))
	end)

	it("handles double-digit results", function()
		local shape = { "0", "2", "2", "1", "0", "0" }
		local result = apply_offset(shape, 10)
		assert.are.equal("10", result[1])
		assert.are.equal("12", result[2])
	end)
end)

describe("staff.write_chord", function()
	it("writes single-digit frets across all strings", function()
		-- Standard A chord: E=0 A=0 D=2 G=2 B=2 e=0 (low→high voicing)
		local voicing = { "0", "0", "2", "2", "2", "0" }
		local bufnr = make_staff()
		staff.write_chord(bufnr, 0, pos0, voicing)
		local lines = buf_lines(bufnr)
		-- Display order is high→low: e B G D A E
		-- voicing[6]=0 → e (row 1, string_idx=0)
		assert.are.equal("0", lines[1]:sub(3, 3)) -- e string
		-- voicing[5]=2 → B (row 2, string_idx=1)
		assert.are.equal("2", lines[2]:sub(3, 3)) -- B string
		-- voicing[4]=2 → G (row 3, string_idx=2)
		assert.are.equal("2", lines[3]:sub(3, 3)) -- G string
		-- voicing[3]=2 → D (row 4, string_idx=3)
		assert.are.equal("2", lines[4]:sub(3, 3)) -- D string
		-- voicing[2]=0 → A (row 5, string_idx=4)
		assert.are.equal("0", lines[5]:sub(3, 3)) -- A string
		-- voicing[1]=0 → E (row 6, string_idx=5)
		assert.are.equal("0", lines[6]:sub(3, 3)) -- E string
	end)

	it("writes x for muted strings", function()
		local voicing = { "x", "0", "2", "2", "0", "x" }
		local bufnr = make_staff()
		staff.write_chord(bufnr, 0, pos0, voicing)
		local lines = buf_lines(bufnr)
		assert.are.equal("x", lines[1]:sub(3, 3)) -- e string (voicing[6]="x")
		assert.are.equal("x", lines[6]:sub(3, 3)) -- E string (voicing[1]="x")
	end)

	it("writes double-digit frets (>=10) correctly", function()
		local voicing = { "0", "0", "0", "0", "0", "12" }
		local bufnr = make_staff()
		staff.write_chord(bufnr, 0, pos0, voicing)
		local lines = buf_lines(bufnr)
		-- e string (string_idx=0, row 1) gets fret 12
		assert.are.equal("12", lines[1]:sub(3, 4))
	end)

	it("writes at the correct position when sub > 0", function()
		local voicing = { "5", "5", "5", "5", "5", "5" }
		local bufnr = make_staff()
		staff.write_chord(bufnr, 0, pos1, voicing)
		local lines = buf_lines(bufnr)
		-- pos1 = sub=1 → col = label_width + 1 + 1*3 = 1+1+3 = 5 (0-indexed) → sub(6,6) in 1-indexed
		-- position_to_col({measure=0,beat=0,sub=1}): label_width + 1(sep) + sub*3 = 1+1+3 = 5
		assert.are.equal("5", lines[1]:sub(6, 6))
		-- sub=0 position should be untouched (still filler)
		assert.are.equal("-", lines[1]:sub(3, 3))
	end)
end)
