-- Handles generating, parsing, and mutating tab staff blocks in the buffer.
--
-- A staff block looks like this (4 beats, 2 divisions each):
--
--   e|------|------|------|------|
--   B|------|------|------|------|
--   G|------|------|------|------|
--   D|------|------|------|------|
--   A|------|------|------|------|
--   E|------|------|------|------|
--
-- Column layout per line:
--   <string_label> | <beat_sep> <div*(filler*3)> ... <beat_sep> ... |
--
-- Each division is 3 chars: content + overflow + separator filler
-- e.g. single-digit fret 5: `5--`  double-digit fret 12: `12-`
-- Each beat is:  beat_sep + (3 * divisions) filler chars
-- Final char  :  beat_sep (closing bar)

local config = require("tablature.config")
local state = require("tablature.state")

---@class tablature.staff.position
---@field measure integer
---@field beat integer
---@field sub integer
---

local M = {}

--- Build a single staff line string for one string.
---@param string_label string  Character used to represent the string, e.g. `e`, `B`
---@param measures integer  How many measures to build
---@param beats_per_measure integer  Beats per measure
---@param divisions integer  How many columns per beat, e.g. `4` for quarter notes
---@param filler string  Character used to fill empty columns
---@param measure_sep string  Character used to separate measures
---@param label_length integer  Number of columns the label should occupy. Padded if string_label is not this length.
---@return string
local function build_line(string_label, measures, beats_per_measure, divisions, filler, measure_sep, label_length)
	local padded = string_label .. string.rep(" ", label_length - #string_label)

	local parts = { padded, measure_sep }
	for _ = 1, measures * beats_per_measure do
		-- 3 filler chars per division: content + overflow + separator
		parts[#parts + 1] = string.rep(filler, divisions * 3)
		parts[#parts + 1] = measure_sep
	end
	return table.concat(parts)
end

--- Generate a full staff block as a list of lines.
---@param opts table|nil  Override config options (measures, beats_per_measure, divisions)
---@return string[]
function M.generate(opts)
	local cfg = config.options
	local measures = (opts and opts.measures) or cfg.default_measures
	local bpm = (opts and opts.beats_per_measure) or cfg.beats_per_measure
	local div = (opts and opts.divisions) or cfg.divisions
	local filler = cfg.filler
	local beat_sep = cfg.measure_sep
	local label_length = state.label_width

	local strings = state.tuning.strings
	local lines = {}
	for i = #strings, 1, -1 do
		lines[#lines + 1] = build_line(strings[i], measures, bpm, div, filler, beat_sep, label_length)
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
		-- Account for the new lines in cursor row
		-- find_staff_top returns 0-indexed row, we need 1-indexed, so account for
		-- that too
		cursor_position = row + 3
	end

	vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)
	-- Move cursor to top-left editable position of the new staff
	-- Row becomes (row + 1) in 1-indexed; col is after the string label + beat_sep (col 2, 0-indexed)
	vim.api.nvim_win_set_cursor(0, { cursor_position, first_col })
end

--- Rewrite the string labels of an existing staff block to match a new tuning.
--- The number of strings in new_tuning must match the existing block.
---@param bufnr integer
---@param staff_top integer  0-indexed line of top string
---@param old_label_width integer  label width the staff was generated with
---@param new_tuning tablature.Tuning
function M.relabel_staff(bufnr, staff_top, old_label_width, new_tuning)
	local new_label_width = 0
	for _, s in ipairs(new_tuning.strings) do
		if #s > new_label_width then
			new_label_width = #s
		end
	end

	for i, string_name in ipairs(new_tuning.strings) do
		local row = staff_top + i - 1
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

--- Given a cursor column, compute which beat and sub-column the cursor is in.
--- Returns { measure, beat, sub } all 0-indexed, or nil if not in a grid cell.
---@param col integer   0-indexed column
---@return tablature.staff.position|nil
function M.col_to_position(col)
	local cfg = config.options
	local div = cfg.divisions
	local bpm = cfg.beats_per_measure
	local sep_width = cfg.measure_sep:len()

	local label_width = state.label_width

	local content_start = label_width + sep_width

	if col < content_start then
		return nil
	end

	local offset = col - content_start
	local cell_width = div * 3 + sep_width -- each beat: (div * 3) filler chars + trailing sep

	local total_beat = math.floor(offset / cell_width)
	if total_beat > cfg.default_measures * bpm then
		-- Cursor out of bounds
		return nil
	end
	local char_pos = offset % cell_width
	local sub_beat = math.floor(char_pos / 3)

	-- If cursor is on or past the beat separator, clamp or bail
	if char_pos >= div * 3 then
		return nil
	end

	local measure = math.floor(total_beat / bpm)
	local beat = total_beat % bpm

	return { measure = measure, beat = beat, sub = sub_beat }
end

--- Given a position {measure, beat, sub}, return the 0-indexed column.
---@param pos tablature.staff.position
---@return integer
function M.position_to_col(pos)
	local cfg = config.options
	local div = cfg.divisions
	local bpm = cfg.beats_per_measure
	local label_width = state.label_width
	local sep_width = cfg.measure_sep:len()
	local cell_width = div * 3 + sep_width

	local total_beat = pos.measure * bpm + pos.beat
	return label_width + sep_width + total_beat * cell_width + pos.sub * 3
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
	local col = M.position_to_col(pos)
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
	local col = M.position_to_col(pos)

	local row = staff_top + string_idx
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if line then
		local new_line
		-- Write both digits into content + overflow slots
		new_line = line:sub(1, col) .. tens .. ones .. line:sub(col + 3)
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
		if not v then
			-- no value for this string, leave as-is
		elseif v == "x" then
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

--- Scan the top staff row to get the division count for a specific measure.
--- Derives divisions from the actual buffer text, so it is correct even when
--- individual measures have been reformatted to different division counts.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@param measure_idx integer  0-indexed
---@return integer
function M.get_measure_divisions(bufnr, staff_top, measure_idx)
	local cfg = config.options
	local bpm = cfg.beats_per_measure
	local sep = cfg.measure_sep
	local sep_width = #sep
	local label_width = state.label_width

	local line = vim.api.nvim_buf_get_lines(bufnr, staff_top, staff_top + 1, false)[1]
	if not line then
		return cfg.divisions
	end

	-- Skip label+sep, then skip measure_idx * bpm beats
	local pos = label_width + sep_width + 1 -- 1-indexed Lua string position
	for _ = 1, measure_idx * bpm do
		local sp = line:find(sep, pos, true)
		if not sp then
			return cfg.divisions
		end
		pos = sp + sep_width
	end

	-- Measure's first beat starts at pos; find its trailing sep
	local sp = line:find(sep, pos, true)
	if not sp then
		return cfg.divisions
	end
	return math.floor((sp - pos) / 3)
end

--- Convert a position to a 0-indexed column by scanning the actual buffer content.
--- Unlike position_to_col, this handles measures with different division counts.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@param pos tablature.staff.position
---@return integer
function M.buf_position_to_col(bufnr, staff_top, pos)
	local cfg = config.options
	local bpm = cfg.beats_per_measure
	local sep = cfg.measure_sep
	local sep_width = #sep
	local label_width = state.label_width

	local line = vim.api.nvim_buf_get_lines(bufnr, staff_top, staff_top + 1, false)[1]
	if not line then
		return M.position_to_col(pos)
	end

	local total_beats = pos.measure * bpm + pos.beat
	local scan = label_width + sep_width + 1 -- 1-indexed

	for _ = 1, total_beats do
		local sp = line:find(sep, scan, true)
		if not sp then
			return M.position_to_col(pos)
		end
		scan = sp + sep_width
	end

	-- scan is the 1-indexed start of the target beat; convert to 0-indexed col
	return (scan - 1) + pos.sub * 3
end

--- Convert a 0-indexed column to a position by scanning the actual buffer content.
--- Unlike col_to_position, this handles measures with different division counts.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@param col integer  0-indexed column
---@return tablature.staff.position|nil
function M.buf_col_to_position(bufnr, staff_top, col)
	local cfg = config.options
	local bpm = cfg.beats_per_measure
	local sep = cfg.measure_sep
	local sep_width = #sep
	local label_width = state.label_width

	local line = vim.api.nvim_buf_get_lines(bufnr, staff_top, staff_top + 1, false)[1]
	if not line then
		return M.col_to_position(col)
	end

	local content_start = label_width + sep_width -- 0-indexed
	if col < content_start then
		return nil
	end

	local scan = content_start + 1 -- 1-indexed
	local total_beat = 0

	while scan <= #line do
		local sp = line:find(sep, scan, true)
		if not sp then
			break
		end

		local beat_col_start = scan - 1 -- 0-indexed
		local beat_content_len = sp - scan -- = div * 3

		if col >= beat_col_start and col < beat_col_start + beat_content_len then
			local offset_in_beat = col - beat_col_start
			local sub = math.floor(offset_in_beat / 3)
			return {
				measure = math.floor(total_beat / bpm),
				beat = total_beat % bpm,
				sub = sub,
			}
		end

		-- col is on the sep itself → not a valid cell
		if col == beat_col_start + beat_content_len then
			return nil
		end

		total_beat = total_beat + 1
		scan = sp + sep_width
	end

	return nil
end

--- Reformat a single measure to use a new division count.
--- Inserts filler columns when expanding, trims trailing columns when shrinking.
--- All string rows in the staff are updated.
---@param bufnr integer
---@param staff_top integer  0-indexed row of top staff line
---@param measure_idx integer  0-indexed
---@param new_div integer
function M.set_measure_divisions(bufnr, staff_top, measure_idx, new_div)
	local cfg = config.options
	local bpm = cfg.beats_per_measure
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
			local pos = label_width + sep_width + 1 -- 1-indexed
			for _ = 1, measure_idx * bpm do
				local sp = line:find(sep, pos, true)
				pos = sp + sep_width
			end
			local measure_start = pos

			-- Rebuild each beat with new_div width
			local new_beats = {}
			local beat_pos = measure_start
			for _ = 1, bpm do
				local sp = line:find(sep, beat_pos, true)
				local beat_content = line:sub(beat_pos, sp - 1)
				local old_div = math.floor(#beat_content / 3)

				if new_div > old_div then
					beat_content = beat_content .. string.rep(filler, (new_div - old_div) * 3)
				elseif new_div < old_div then
					beat_content = beat_content:sub(1, new_div * 3)
				end

				new_beats[#new_beats + 1] = beat_content .. sep
				beat_pos = sp + sep_width
			end

			local new_measure_str = table.concat(new_beats)
			local before = line:sub(1, measure_start - 1)
			local after = line:sub(beat_pos)
			vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { before .. new_measure_str .. after })
		end
	end
end

return M
