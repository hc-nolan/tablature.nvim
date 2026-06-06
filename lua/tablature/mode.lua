-- Implements the tab-editing "mode" overlay.
--
--   1. Save any existing buffer-local keymaps that we're about to shadow.
--   2. Install buffer-local keymaps that intercept character input.
--   3. On exit, restore the original keymaps and clean up.

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")
local hl = require("tablature.highlights")
local chord = require("tablature.chord_mode")

local M = {}

-- Active keymap layer for tab mode (nil when not active).
local tab_layer = nil

--- Create a keymap layer that saves and restores displaced buffer-local keymaps.
---@param bufnr integer
---@return tablature.Layer
local function new_keymap_layer(bufnr)
	local installed = {}
	local saved = {}
	local keylist = {}

	---@class tablature.Layer  Keymap layer with helper methods
	local layer = {}

	--- Save existing map and install new one
	---@param keymap tablature.KeyMap
	function layer.set(keymap)
		local existing = vim.fn.maparg(keymap.key, "n", false, true)
		if existing and existing.buffer == 1 then
			saved[keymap.key] = existing
		end
		vim.keymap.set("n", keymap.key, keymap.func, { buffer = bufnr, nowait = true, desc = keymap.desc })
		installed[#installed + 1] = keymap.key
		keylist[#keylist + 1] = { key = keymap.key, desc = keymap.desc }
	end

	-- Remove all installed maps and restore saved ones
	function layer.uninstall()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		for _, key in ipairs(installed) do
			pcall(vim.keymap.del, "n", key, { buffer = bufnr })
		end
		for key, map in pairs(saved) do
			if map.callback then
				vim.keymap.set("n", key, map.callback, { buffer = bufnr, desc = map.desc })
			elseif map.rhs and map.rhs ~= "" then
				vim.keymap.set("n", key, map.rhs, {
					buffer = bufnr,
					desc = map.desc,
					noremap = map.noremap == 1,
					silent = map.silent == 1,
				})
			end
		end
	end

	-- Return list of installed maps
	---@return {key: string, desc: string}
	function layer.get_keylist()
		return keylist
	end

	return layer
end

--- Get the current cursor's grid position and string index.
--- Returns nil if cursor is not on a valid staff cell.
---@return {staff_top: integer, string_idx: integer, pos: tablature.staff.position}|nil
local function get_cursor_context()
	local bufnr = state.bufnr
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local top = staff.find_staff_top(bufnr, row)
	if not top then
		return nil
	end

	local string_idx = row - top -- 0-indexed from top
	local pos = staff.col_to_position(state.bufnr, top, col)
	if not pos then
		vim.notify("tablature: Failed to calculate position", 4)
		return nil
	end

	return { staff_top = top, string_idx = string_idx, pos = pos }
end

--- Move the cursor to a given position within the staff.
--- Clamps to valid range.
---@param ctx table  current context from get_cursor_context()
---@param new_pos {measure: integer, beat: integer}
---@param new_string_idx integer|nil  if nil, keep current string
local function move_to(ctx, new_pos, new_string_idx)
	local cfg = config.options
	local default_measures = cfg.default_measures
	local num_strings = #state.tuning.strings

	-- Clamp beat to the actual beat count of the target measure
	local beats = staff.get_measure_beats(state.bufnr, state.staff_top, new_pos.measure)
	new_pos.beat = math.max(0, math.min(beats - 1, new_pos.beat))

	-- Clamp measure — if it was out of bounds, stay put
	local clamped_measure = math.max(0, math.min(default_measures - 1, new_pos.measure))
	if clamped_measure ~= new_pos.measure then
		new_pos.measure = ctx.pos.measure
		new_pos.beat = ctx.pos.beat
	else
		new_pos.measure = clamped_measure
	end

	-- Clamp string
	local si = new_string_idx or ctx.string_idx
	si = math.max(0, math.min(num_strings - 1, si))

	local new_row = ctx.staff_top + si + 1 -- 1-indexed for nvim_win_set_cursor
	local new_col = staff.position_to_col(state.bufnr, state.staff_top, new_pos)
	if not new_col then
		vim.notify("tablature: Could not calculate new column position", 4)
		return
	end

	vim.api.nvim_win_set_cursor(0, { new_row, new_col })

	-- Update highlights: highlight full measure width
	local measure_start_pos = { measure = new_pos.measure, beat = 0 }
	local measure_col = staff.position_to_col(state.bufnr, state.staff_top, measure_start_pos)
	if not measure_col then
		vim.notify("tablature: Could not calculate measure column position", 4)
		return
	end
	hl.highlight_beat_column(state.bufnr, ctx.staff_top, measure_col, beats * 3)
	hl.show_mode_indicator(state.bufnr, ctx.staff_top, new_pos)
end

--- Write a character at the cursor.
--- If the current cell already contains a digit, treat this as the second digit
--- of a double-digit fret and write into the overflow slot.
---@param char string
local function write_fret(char)
	local ctx = get_cursor_context()
	if not ctx then
		return
	end

	-- Check if the current cell already has a digit (double-digit fret case)
	local col = staff.position_to_col(state.bufnr, state.staff_top, ctx.pos)
	if not col then
		vim.notify("tablature: Column not found", 4)
		return
	end
	local line = vim.api.nvim_buf_get_lines(
		state.bufnr,
		ctx.staff_top + ctx.string_idx,
		ctx.staff_top + ctx.string_idx + 1,
		false
	)[1]
	local existing = line and line:sub(col + 1, col + 1)

	local function write_single_fret()
		-- Default case is a single-digit note
		-- Use write_double_digit with filler char as second 'digit' to overwrite
		-- any existing double-digit notes
		staff.write_double_digit(state.bufnr, ctx.staff_top, ctx.string_idx, ctx.pos, char, config.options.filler)
		state.pending_digit = true
	end

	if existing and existing:match("%d") and char:match("%d") then
		-- Check if pending_digit is true
		if state.pending_digit then
			-- Write double-digit fret: existing is tens digit, char is ones digit
			staff.write_double_digit(state.bufnr, ctx.staff_top, ctx.string_idx, ctx.pos, existing, char)
			state.pending_digit = false
		else
			write_single_fret()
		end
	else
		write_single_fret()
	end

	-- nvim_buf_set_lines on the bottom staff row invalidates the virt_lines
	-- extmark attached there, so re-draw the legend when writing on that row.
	if ctx.string_idx == #state.tuning.strings - 1 and not chord.is_active() then
		hl.show_tab_legend(state.bufnr, state.staff_top)
	end
end

--- Fetch cursor context and run fn(ctx, p) where p is a mutable copy of ctx.pos.
--- Clears pending_digit afterwards. No-op if cursor is not on a valid staff cell.
---@param fn function
local function with_cursor(fn)
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	local p = { measure = ctx.pos.measure, beat = ctx.pos.beat }
	fn(ctx, p)
	state.pending_digit = false
end

function M.move_left()
	with_cursor(function(ctx, p)
		p.beat = p.beat - 1
		if p.beat < 0 then
			-- Wrap into the last beat of the previous measure
			local prev_measure = p.measure - 1
			local prev_beats = prev_measure >= 0 and staff.get_measure_beats(state.bufnr, state.staff_top, prev_measure)
				or config.options.beats
			p.beat = prev_beats - 1
			p.measure = p.measure - 1
		end
		move_to(ctx, p)
	end)
end

function M.move_right()
	with_cursor(function(ctx, p)
		local cur_beats = staff.get_measure_beats(state.bufnr, state.staff_top, p.measure)
		p.beat = p.beat + 1
		if p.beat >= cur_beats then
			p.beat = 0
			p.measure = p.measure + 1
		end
		move_to(ctx, p)
	end)
end

function M.move_previous_measure()
	with_cursor(function(ctx, p)
		p.beat = 0
		p.measure = p.measure - 1
		move_to(ctx, p)
	end)
end

function M.move_next_measure()
	with_cursor(function(ctx, p)
		p.beat = 0
		p.measure = p.measure + 1
		move_to(ctx, p)
	end)
end

function M.move_next_string()
	with_cursor(function(ctx, p)
		move_to(ctx, p, ctx.string_idx + 1)
	end)
end

function M.move_previous_string()
	with_cursor(function(ctx, p)
		move_to(ctx, p, ctx.string_idx - 1)
	end)
end

function M.clear_cell()
	with_cursor(function(ctx, _p)
		staff.write_char(state.bufnr, ctx.staff_top, ctx.string_idx, ctx.pos, config.options.filler)
	end)
end

function M.clear_cell_and_move_left()
	M.clear_cell()
	M.move_left()
end

--- Install all tab-mode keymaps on the buffer.
---@param bufnr integer
local function install_keymaps(bufnr)
	tab_layer = new_keymap_layer(bufnr)

	for _, mapping in pairs(config.options.tabmode_keys) do
		tab_layer.set({ key = mapping.key, func = mapping.func, desc = mapping.desc })
	end

	-- Writing: fret numbers 0-9
	for _, digit in ipairs({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }) do
		local d = digit -- capture for closure
		tab_layer.set({
			key = d,
			func = function()
				write_fret(d)
			end,
			desc = "Tab mode: write fret " .. d,
		})
	end
end

--- Remove all tab-mode keymaps, restoring saved ones.
local function uninstall_keymaps()
	if tab_layer then
		tab_layer.uninstall()
		tab_layer = nil
	end
end

--- Enter tab editing mode on the current buffer.
--- The cursor must already be on a staff line.
function M.enter()
	if state.active then
		vim.notify("tablature: already in tab mode", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed

	local top = staff.find_staff_top(bufnr, row)
	if not top then
		vim.notify("tablature: cursor is not on a tab staff block", vim.log.levels.WARN)
		return
	end

	state.active = true
	state.bufnr = bufnr
	state.staff_top = top

	install_keymaps(bufnr)

	-- Initial highlight + indicator
	local col = cursor[2]
	local pos = staff.col_to_position(bufnr, top, col)
	if not pos then
		vim.notify("tablature: Failed to calculate position", 4)
		return
	end
	local measure_beats = staff.get_measure_beats(bufnr, top, pos.measure)
	local measure_start = { measure = pos.measure, beat = 0 }
	local measure_col = staff.position_to_col(bufnr, top, measure_start)
	if not measure_col then
		vim.notify("tablature: Could not calculate measure column", 4)
		return
	end
	hl.highlight_beat_column(bufnr, top, measure_col, measure_beats * 3)
	hl.show_mode_indicator(bufnr, top, pos)
	hl.show_tab_legend(bufnr, top)

	-- Auto-exit if cursor leaves the buffer
	local aug = vim.api.nvim_create_augroup("TablatureModeExit_" .. bufnr, { clear = true })
	local function auto_exit()
		if state.active and state.bufnr == bufnr then
			M.exit()
		end
	end
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = aug,
		buffer = bufnr,
		once = true,
		callback = auto_exit,
	})

	-- Wipe buffer on bufwipeout
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = aug,
		buffer = bufnr,
		once = true,
		callback = auto_exit,
	})
end

--- Exit tab editing mode.
function M.exit()
	if not state.active then
		return
	end

	local bufnr = state.bufnr

	chord.exit() -- no-op if not in chord mode
	uninstall_keymaps()
	hl.clear(bufnr)

	-- Clean up the auto-exit augroup
	pcall(vim.api.nvim_del_augroup_by_name, "TablatureModeExit_" .. bufnr)

	state.reset()
end

--- Restore cursor position and re-enter tab mode if a picker (e.g. Snacks)
--- opened a new window and triggered our BufLeave/WinLeave auto-exit.
---@param win integer
---@param cursor integer[]
local function restore_tab_mode(win, cursor)
	vim.schedule(function()
		vim.api.nvim_win_set_cursor(win, cursor)
		if not state.active then
			M.enter()
		end
	end)
end

--- Open a shape picker and enter chord mode with the selection.
--- Safe to call from tab mode; also re-entered by C in chord mode.
function M.insert_chord()
	local win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(win)
	local bufnr = state.bufnr

	if not get_cursor_context() then
		vim.notify("tablature: cursor is not on a valid staff cell", vim.log.levels.WARN)
		return
	end

	-- Merge default shapes with active tuning's shapes (tuning takes precedence).
	local chords = config.options.chords
	local merged = {}
	for k, v in pairs(chords.default or {}) do
		merged[k] = v
	end
	for k, v in pairs(chords[state.tuning.name] or {}) do
		merged[k] = v
	end

	local shape_names = vim.tbl_keys(merged)
	table.sort(shape_names)

	if #shape_names == 0 then
		vim.notify("tablature: no chord shapes defined for tuning " .. state.tuning.name, vim.log.levels.WARN)
		restore_tab_mode(win, cursor)
		return
	end

	vim.ui.select(shape_names, { prompt = "Select chord shape" }, function(shape_name)
		if not shape_name then
			restore_tab_mode(win, cursor)
			return
		end
		vim.schedule(function()
			vim.api.nvim_win_set_cursor(win, cursor)
			if not state.active then
				M.enter()
			end
			chord.enter(bufnr, shape_name, merged, {
				new_layer = new_keymap_layer,
				get_context = get_cursor_context,
				movement = {
					left = M.move_left,
					right = M.move_right,
					previous_measure = M.move_previous_measure,
					next_measure = M.move_next_measure,
				},
				reenter = M.insert_chord,
			})
		end)
	end)
end

--- Open a beat picker.
--- Prompt the user for a new beat count and reformat the current measure.
function M.set_beats()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	local bufnr = state.bufnr
	local staff_top = state.staff_top
	local measure_idx = ctx.pos.measure
	local current_beats = staff.get_measure_beats(bufnr, staff_top, measure_idx)

	vim.ui.input({
		prompt = "Beats for measure " .. (measure_idx + 1) .. " (current: " .. current_beats .. "): ",
		default = tostring(current_beats),
	}, function(input)
		if not input or input == "" then
			return
		end
		local new_beats = tonumber(input)
		if not new_beats or new_beats < 1 or math.floor(new_beats) ~= new_beats then
			vim.notify("tablature: beats must be a positive integer", vim.log.levels.WARN)
			return
		end
		vim.schedule(function()
			staff.set_measure_beats(bufnr, staff_top, measure_idx, new_beats)
			-- Clamp cursor beat in case measure shrank
			local clamped_beat = math.min(ctx.pos.beat, new_beats - 1)
			local new_pos = { measure = measure_idx, beat = clamped_beat }
			local new_col = staff.position_to_col(bufnr, staff_top, new_pos)
			if not new_col then
				vim.notify("tablature: Failed to calculate new column", 4)
				return
			end
			vim.api.nvim_win_set_cursor(0, { ctx.staff_top + ctx.string_idx + 1, new_col })
		end)
	end)
end

function M.pick_tuning()
	local was_active = state.active
	local win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(win)
	local bufnr = vim.api.nvim_get_current_buf()
	local row = cursor[1] - 1 -- 0-indexed
	local staff_top = state.tuning and staff.find_staff_top(bufnr, row)
	local old_label_width = state.label_width

	vim.ui.select(config.options.tunings, {
		prompt = "Select tuning",
		format_item = function(t)
			if state.tuning and state.tuning.name == t.name then
				return t.name .. " (active)"
			end
			return t.name
		end,
	}, function(choice)
		if not choice then
			if was_active then
				restore_tab_mode(win, cursor)
			end
			return
		end
		if staff_top then
			if #choice.strings == #state.tuning.strings then
				staff.relabel_staff(bufnr, staff_top, old_label_width, choice)
			else
				vim.notify("tablature: cannot relabel staff — string count mismatch", vim.log.levels.WARN)
			end
		end
		state.set_tuning(choice)
		if staff_top then
			vim.notify("tablature: tuning changed to " .. choice.name .. " (staff relabeled)", vim.log.levels.INFO)
		else
			vim.notify("tablature: tuning changed to " .. choice.name, vim.log.levels.INFO)
		end
		if was_active then
			restore_tab_mode(win, cursor)
		end
	end)
end

return M
