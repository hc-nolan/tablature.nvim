-- Handles generating, parsing, and mutating tab staff blocks in the buffer.
--
-- A staff block looks like this (4 measures, 4 beats each):
--
--   e|------------|------------|------------|------------|
--   B|------------|------------|------------|------------|
--   G|------------|------------|------------|------------|
--   D|------------|------------|------------|------------|
--   A|------------|------------|------------|------------|
--   E|------------|------------|------------|------------|
--
-- Column layout per line:
--   <string_label><measure_sep><beats*3 filler chars><measure_sep>...
--
-- Each beat slot is 3 chars: content + overflow + trailing filler
-- e.g. single-digit fret 5: `5--`  double-digit fret 12: `12-`

local config = require("tablature.config")
local state = require("tablature.state")

---@class tablature.staff.position
---@field measure integer  0-indexed measure number
---@field beat integer     0-indexed beat slot within the measure

local M = {}

--- Build a single staff line string for one string.
---@param string_label string  Character used to represent the string, e.g. `e`, `B`
---@param measures integer  How many measures to build
---@param beats integer  How many beat slots per measure
---@param filler string  Character used to fill empty columns
---@param measure_sep string  Character used to separate measures
---@param label_length integer  Number of columns the label should occupy. Padded if string_label is not this length.
---@return string
local function build_line(string_label, measures, beats, filler, measure_sep, label_length)
	local padded = string_label .. string.rep(" ", label_length - #string_label)

	local parts = { padded, measure_sep }
	for _ = 1, measures do
		-- 3 filler chars per beat slot: content + overflow + trailing filler
		parts[#parts + 1] = string.rep(filler, beats * 3)
		parts[#parts + 1] = measure_sep
	end
	return table.concat(parts)
end

--- Generate a full staff block as a list of lines.
---@param opts table|nil  Override config options (measures, beats)
---@return string[]
function M.generate(opts)
	local cfg = config.options
	local measures = (opts and opts.measures) or cfg.default_measures
	local beats = (opts and opts.beats) or cfg.beats
	local filler = cfg.filler
	local measure_sep = cfg.measure_sep
	local label_length = state.label_width

	local strings = state.tuning.strings
	local lines = {}
	for i = #strings, 1, -1 do
		lines[#lines + 1] = build_line(strings[i], measures, beats, filler, measure_sep, label_length)
	end
	return lines
end

--- Insert a new staff block below the current cursor line.
---@param bufnr integer
function M.insert_below_cursor(bufnr)
	local row = vim.api.nvim_win_get_cursor(0)[1] -- 1-indexed
	local cfg = config.options
	local label_width = state.label_width
	local first_col = label_width + cfg.measure_sep:len()
	local lines = M.generate()
	local staff_top = M.find_staff_top(bufnr, row - 1)
	local cursor_position = row + 1
	if staff_top then
		-- Already inside a staff, insert below
		row = staff_top + #state.tuning.strings

		-- Insert 2 blank lines in between staves
		for _ = 1, 2 do
			table.insert(lines, 1, "")
		end
		-- 2 blank lines prepended + 1 for 0->1 index conversion
		cursor_position = row + 3
	end

	vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)
	-- Move cursor to top-left editable position of the new staff
	-- Row becomes (row + 1) in 1-indexed; col is after the string label + beat_sep (col 2, 0-indexed)
	vim.api.nvim_win_set_cursor(0, { cursor_position, first_col })
	local hl = require("tablature.highlights")
	hl.clear_tab_legend(bufnr)
	local new_top = cursor_position - 1
	local pos = M.col_to_position(bufnr, new_top, first_col)
	hl.show_tab_legend(bufnr, new_top)
	hl.show_mode_indicator(bufnr, new_top, pos)
end

---@param tuning tablature.Tuning
---@return integer
function M.compute_label_width(tuning)
	local label_width = 0
	for _, s in ipairs(tuning.strings) do
		if #s > label_width then
			label_width = #s
		end
	end
	return label_width
end

--- Count the number of measures in a staff by scanning its top line.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@return integer
function M.get_measure_count(bufnr, staff_top)
	local cfg = config.options
	local sep = cfg.measure_sep
	local label_width = state.label_width

	local line = vim.api.nvim_buf_get_lines(bufnr, staff_top, staff_top + 1, false)[1]
	if not line then
		return 0
	end

	local count = 0
	local pos = label_width + 1
	while true do
		local sp = line:find(sep, pos, true)
		if not sp then
			break
		end
		count = count + 1
		pos = sp + #sep
	end
	return count
end

--- Find the staff_top of the next staff below the given one.
---@param bufnr integer
---@param current_staff_top integer  0-indexed row of current staff's top line
---@return integer|nil
function M.find_next_staff(bufnr, current_staff_top)
	local num_strings = #state.tuning.strings
	local total_lines = vim.api.nvim_buf_line_count(bufnr)
	local scan = current_staff_top + num_strings
	while scan < total_lines do
		local top = M.find_staff_top(bufnr, scan)
		if top then
			return top
		end
		scan = scan + 1
	end
	return nil
end

--- Find the staff_top of the previous staff above the given one.
---@param bufnr integer
---@param current_staff_top integer  0-indexed row of current staff's top line
---@return integer|nil
function M.find_prev_staff(bufnr, current_staff_top)
	local scan = current_staff_top - 1
	while scan >= 0 do
		local top = M.find_staff_top(bufnr, scan)
		-- Must be strictly above current staff: find_staff_top on a blank line
		-- just above can "look forward" and return current_staff_top itself.
		if top and top < current_staff_top then
			return top
		end
		scan = scan - 1
	end
	return nil
end

--- Rewrite the string labels of an existing staff block to match a new tuning.
--- The number of strings in new_tuning must match the existing block.
---@param bufnr integer
---@param staff_top integer  0-indexed line of top string
---@param old_label_width integer  label width the staff was generated with
---@param new_tuning tablature.Tuning
function M.relabel_staff(bufnr, staff_top, old_label_width, new_tuning)
	local new_label_width = M.compute_label_width(new_tuning)

	local n = #new_tuning.strings
	for i, string_name in ipairs(new_tuning.strings) do
		local row = staff_top + n - i
		local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
		if line then
			local content_after_label = line:sub(old_label_width + 1)
			local new_label = string_name .. string.rep(" ", new_label_width - #string_name)
			vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_label .. content_after_label })
		end
	end
end

--- Detect if the given line number (0-indexed) is part of a staff block.
--- Returns the 0-indexed line of the staff top, or nil.
---@param bufnr integer
---@param row integer  0-indexed line number
---@return integer|nil
function M.find_staff_top(bufnr, row)
	local cfg = config.options
	local num_strings = #state.tuning.strings
	local total_lines = vim.api.nvim_buf_line_count(bufnr)
	local label_width = state.label_width
	local function is_staff_line(r)
		if r < 0 or r >= total_lines then
			return false
		end
		local line = vim.api.nvim_buf_get_lines(bufnr, r, r + 1, false)[1]
		if not line or #line < label_width + 1 then
			return false
		end
		return line:sub(label_width + 1, label_width + 1) == cfg.measure_sep
	end
	-- Walk upward to find the top of the block
	local check = row
	while check >= 0 and is_staff_line(check) do
		check = check - 1
	end
	local top = check + 1
	-- Verify exactly num_strings contiguous staff lines from top
	for offset = 0, num_strings - 1 do
		if not is_staff_line(top + offset) then
			return nil
		end
	end
	-- Verify the line below the block is NOT a staff line (avoids matching mid-block)
	if is_staff_line(top + num_strings) then
		return nil
	end
	return top
end

--- Write a character at (string_idx 0-indexed from top, measure, beat, sub)
--- into the buffer. Ensures all string lines stay consistent.
---@param bufnr integer
---@param staff_top integer   0-indexed line of top string
---@param string_idx integer  0-indexed (0 = top/high-e string)
---@param pos tablature.staff.position
---@param char string  single character to write
function M.write_char(bufnr, staff_top, string_idx, pos, char)
	local row = staff_top + string_idx
	local col = M.position_to_col(bufnr, staff_top, pos)
	if not col then
		vim.notify("tablature: Failed to calculate column", 4)
		return
	end
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if not line then
		return
	end

	-- Replace the single byte at col (assumes ASCII content)
	-- If writing a filler, also clear the overflow slot
	local cfg = config.options
	local new_line
	if char == cfg.filler then
		new_line = line:sub(1, col) .. char .. cfg.filler .. line:sub(col + 3)
	else
		new_line = line:sub(1, col) .. char .. line:sub(col + 2)
	end
	vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_line })
end

--- Write a two-digit fret at pos on the given string
---@param bufnr integer
---@param staff_top integer
---@param string_idx integer  0-indexed
---@param pos tablature.staff.position
---@param tens string   first digit character
---@param ones string   second digit character
function M.write_double_digit(bufnr, staff_top, string_idx, pos, tens, ones)
	local col = M.position_to_col(bufnr, staff_top, pos)
	if not col then
		vim.notify("tablature: Failed to calculate column", 4)
		return
	end

	local row = staff_top + string_idx
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if line then
		-- Write both digits into content + overflow slots
		local new_line = line:sub(1, col) .. tens .. ones .. line:sub(col + 3)
		vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_line })
	end
end

--- Write a chord voicing at the given position across all strings.
--- voicing is a list of fret values (low→high string order), one per string.
--- Each value is a string: "x" for muted, "0" for open, or a fret number e.g. "12".
---@param bufnr integer
---@param staff_top integer  0-indexed
---@param pos tablature.staff.position
---@param voicing string[]  low→high order, length must equal #state.tuning.strings
function M.write_chord(bufnr, staff_top, pos, voicing)
	local num_strings = #state.tuning.strings
	for string_idx = 0, num_strings - 1 do
		-- string_idx 0 = top of staff = highest string = last element of voicing
		local v = voicing[num_strings - string_idx]
		if v then
			if v == "x" then
				M.write_char(bufnr, staff_top, string_idx, pos, "x")
			else
				local n = tonumber(v)
				if n and n >= 10 then
					local tens = tostring(math.floor(n / 10))
					local ones = tostring(n % 10)
					M.write_double_digit(bufnr, staff_top, string_idx, pos, tens, ones)
				elseif n then
					M.write_char(bufnr, staff_top, string_idx, pos, tostring(n))
				end
			end
		end
	end
end

--- Returns 1-indexed start position of measure_idx in line, or nil if out of bounds.
---@return integer|nil
local function find_measure_start(line, measure_idx, label_width, sep, sep_width)
	local pos = label_width + sep_width + 1
	for _ = 1, measure_idx do
		local sp = line:find(sep, pos, true)
		if not sp then
			return nil
		end
		pos = sp + sep_width
	end
	return pos
end

--- Scan the top staff row to get the beat count for a specific measure.
--- Derives the beat count from the actual buffer text, so it is correct even
--- when individual measures have been reformatted to different beat counts.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@param measure_idx integer  0-indexed
---@return integer
function M.get_measure_beats(bufnr, staff_top, measure_idx)
	local cfg = config.options
	local sep = cfg.measure_sep
	local sep_width = #sep
	local label_width = state.label_width

	local line = vim.api.nvim_buf_get_lines(bufnr, staff_top, staff_top + 1, false)[1]
	if not line then
		return cfg.beats
	end

	-- Skip label+sep, then skip measure_idx measures
	local pos = find_measure_start(line, measure_idx, label_width, sep, sep_width)
	if not pos then
		return cfg.beats
	end

	-- Target measure starts at pos; find its trailing sep
	local sp = line:find(sep, pos, true)
	if not sp then
		return cfg.beats
	end
	return math.floor((sp - pos) / 3)
end

--- Convert a position to a 0-indexed column by scanning the buffer content.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@param pos tablature.staff.position
---@return integer|nil
function M.position_to_col(bufnr, staff_top, pos)
	local cfg = config.options
	local sep = cfg.measure_sep
	local sep_width = #sep
	local label_width = state.label_width

	local line = vim.api.nvim_buf_get_lines(bufnr, staff_top, staff_top + 1, false)[1]
	if not line then
		vim.notify("tablature: Staff lines were not found in buffer " .. bufnr, 4)
		return nil
	end

	-- Walk pos.measure measures to find the start of the target measure
	local scan = find_measure_start(line, pos.measure, label_width, sep, sep_width)
	if not scan then
		vim.notify("tablature: Could not find measure start at line " .. line, 4)
		return nil
	end
	-- scan is the 1-indexed start of the target measure; add beat offset
	return (scan - 1) + pos.beat * 3
end

--- Convert a 0-indexed column to a position by scanning the buffer content.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@param col integer|nil  0-indexed column
---@return tablature.staff.position|nil
function M.col_to_position(bufnr, staff_top, col)
	local cfg = config.options
	local sep = cfg.measure_sep
	local sep_width = #sep
	local label_width = state.label_width

	local line = vim.api.nvim_buf_get_lines(bufnr, staff_top, staff_top + 1, false)[1]
	if not line then
		vim.notify("tablature: Staff lines were not found in buffer " .. bufnr, 4)
		return nil
	end

	local content_start = label_width + sep_width -- 0-indexed
	if col < content_start then
		return nil
	end

	local scan = content_start + 1 -- 1-indexed
	local measure = 0

	while scan <= #line do
		local sp = line:find(sep, scan, true)
		if not sp then
			break
		end

		local measure_col_start = scan - 1 -- 0-indexed
		local measure_content_len = sp - scan -- = beats * 3

		if col >= measure_col_start and col < measure_col_start + measure_content_len then
			local beat = math.floor((col - measure_col_start) / 3)
			return { measure = measure, beat = beat }
		end

		-- col is on the sep itself → not a valid cell
		if col == measure_col_start + measure_content_len then
			return nil
		end

		measure = measure + 1
		scan = sp + sep_width
	end

	return nil
end

--- Reformat a single measure to use a new beat count.
--- Inserts filler beat slots when expanding, trims trailing slots when shrinking.
--- All string rows in the staff are updated.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@param measure_idx integer  0-indexed
---@param new_beats integer
function M.set_measure_beats(bufnr, staff_top, measure_idx, new_beats)
	local cfg = config.options
	local sep = cfg.measure_sep
	local sep_width = #sep
	local label_width = state.label_width
	local filler = cfg.filler
	local num_strings = #state.tuning.strings

	for s = 0, num_strings - 1 do
		local row = staff_top + s
		local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
		if line then
			-- Walk to the start of the target measure
			local measure_start = find_measure_start(line, measure_idx, label_width, sep, sep_width)

			-- Find the measure's trailing sep
			local sp = line:find(sep, measure_start, true)
			local measure_content = line:sub(measure_start, sp - 1)
			local old_beats = math.floor(#measure_content / 3)

			local new_content
			if new_beats > old_beats then
				new_content = measure_content .. string.rep(filler, (new_beats - old_beats) * 3)
			elseif new_beats < old_beats then
				new_content = measure_content:sub(1, new_beats * 3)
			else
				new_content = measure_content
			end

			local before = line:sub(1, measure_start - 1)
			local after = line:sub(sp) -- includes the trailing sep and everything after
			vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { before .. new_content .. after })
		end
	end
end

--- Apply a root-fret offset to a chord shape, producing an absolute voicing.
--- "x" entries are passed through unchanged; numeric string values have the
--- offset added.
---@param shape tablature.ChordShape
---@param offset integer  root fret to add to every non-muted string
---@return string[]
function M.apply_offset(shape, offset)
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

return M
