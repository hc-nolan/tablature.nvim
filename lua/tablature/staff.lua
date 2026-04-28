-- Handles generating, parsing, and mutating tab staff blocks in the buffer.
--
-- A staff block looks like this (4 beats, 4 divisions each):
--
--   e|----|----|----|----|
--   B|----|----|----|----|
--   G|----|----|----|----|
--   D|----|----|----|----|
--   A|----|----|----|----|
--   E|----|----|----|----|
--
-- Column layout per line:
--   <string_label> | <beat_sep> <div*filler> ... <beat_sep> ... |
--
-- Each beat is:  beat_sep + (filler * divisions)
-- Final char  :  beat_sep (closing bar)

local config = require("tablature.config")

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
		parts[#parts + 1] = string.rep(filler, divisions)
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
	local label_length = cfg.label_width

	local lines = {}
	for _, s in ipairs(cfg.strings) do
		lines[#lines + 1] = build_line(s, measures, bpm, div, filler, beat_sep, label_length)
	end
	return lines
end

--- Insert a new staff block below the current cursor line.
---@param bufnr integer
function M.insert_below_cursor(bufnr)
	local row = vim.api.nvim_win_get_cursor(0)[1] -- 1-indexed
	local cfg = config.options
	local label_width = cfg.label_width
	local first_col = label_width + cfg.measure_sep:len()
	local lines = M.generate()
	local staff_top = M.find_staff_top(bufnr, row - 1)
	local cursor_position = row + 1
	if staff_top then
		-- Already inside a staff, insert below
		row = staff_top + #cfg.strings

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

--- Detect if the given line number (0-indexed) is part of a staff block.
--- Returns the 0-indexed line of the staff top, or nil.
---@param bufnr integer
---@param row integer  0-indexed line number
---@return integer|nil
function M.find_staff_top(bufnr, row)
	local cfg = config.options
	local num_strings = #cfg.strings
	local total_lines = vim.api.nvim_buf_line_count(bufnr)
	local label_width = cfg.label_width

	-- Search upward from row to find the first line of the staff block
	-- A staff line starts with one of the string labels followed by the beat_sep
	local function is_staff_line(r)
		if r < 0 or r >= total_lines then
			return false, nil
		end
		local line = vim.api.nvim_buf_get_lines(bufnr, r, r + 1, false)[1]
		if not line then
			return false, nil
		end
		for i, s in ipairs(cfg.strings) do
			local padded = s .. string.rep(" ", label_width - #s)
			if vim.startswith(line, padded .. cfg.measure_sep) then
				return true, i -- 1-indexed string position
			end
		end
		return false, nil
	end

	-- Walk upward to find top of block
	local check = row
	while check >= 0 do
		local ok, str_idx = is_staff_line(check)
		if not ok then
			break
		end
		-- If this is string 1 (top string), we found the top
		if str_idx == 1 then
			-- Verify all num_strings lines form a contiguous block
			local valid = true
			for offset = 0, num_strings - 1 do
				local ok2, idx2 = is_staff_line(check + offset)
				if not ok2 or idx2 ~= offset + 1 then
					valid = false
					break
				end
			end
			if valid then
				return check
			end
			break
		end
		check = check - 1
	end
	return nil
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

	local label_width = cfg.label_width

	local content_start = label_width + sep_width

	if col < content_start then
		return nil
	end

	local offset = col - content_start
	local cell_width = div + sep_width -- each beat: div filler chars + trailing sep

	local total_beat = math.floor(offset / cell_width)
	if total_beat > cfg.default_measures * bpm then
		-- Cursor out of bounds
		return nil
	end
	local sub = offset % cell_width

	-- If cursor is ON the separator at end of beat, treat as last sub of that beat
	if sub == div then
		-- cursor is on the separator itself — clamp to last valid sub
		sub = div - 1
	elseif sub >= div then
		return nil -- shouldn't happen
	end

	local measure = math.floor(total_beat / bpm)
	local beat = total_beat % bpm

	return { measure = measure, beat = beat, sub = sub }
end

--- Given a position {measure, beat, sub}, return the 0-indexed column.
---@param pos tablature.staff.position
---@return integer
function M.position_to_col(pos)
	local cfg = config.options
	local div = cfg.divisions
	local bpm = cfg.beats_per_measure
	local label_width = cfg.label_width
	local sep_width = cfg.measure_sep:len()
	local cell_width = div + sep_width

	local total_beat = pos.measure * bpm + pos.beat
	return label_width + sep_width + total_beat * cell_width + pos.sub
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
	local new_line = line:sub(1, col) .. char .. line:sub(col + 2)
	vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_line })
end

return M
