-- Implements the tab-editing "mode" overlay.
--
--   1. Save any existing buffer-local keymaps that we're about to shadow.
--   2. Install buffer-local keymaps that intercept character input.
--   3. On exit, restore the original keymaps and clean up.

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")
local hl = require("tablature.highlights")

local M = {}

-- Keymaps we install in tab mode. Stored so we can remove them on exit.
local TAB_MODE_KEYS = {}

-- Track which buffer-local keymaps existed before we installed ours,
-- so we can restore them on exit.
local saved_keymaps = {}

--- Get the current cursor's grid position and string index.
--- Returns nil if cursor is not on a valid staff cell.
---@return {staff_top: integer, string_idx: integer, pos: table}|nil
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
	local pos = staff.col_to_position(col)
	if not pos then
		return nil
	end

	return { staff_top = top, string_idx = string_idx, pos = pos }
end

--- Move the cursor to a given position within the staff.
--- Clamps to valid range.
---@param ctx table  current context from get_cursor_context()
---@param new_pos {measure: integer, beat: integer, sub: integer}
---@param new_string_idx integer|nil  if nil, keep current string
local function move_to(ctx, new_pos, new_string_idx)
	local cfg = config.options
	local div = cfg.divisions
	local bpm = cfg.beats_per_measure
	local default_measures = cfg.default_measures
	local num_strings = #state.tuning.strings

	-- Clamp sub
	new_pos.sub = math.max(0, math.min(div - 1, new_pos.sub))

	-- Handle beat overflow/underflow → carry into measure
	if new_pos.beat >= bpm then
		new_pos.measure = new_pos.measure + math.floor(new_pos.beat / bpm)
		new_pos.beat = new_pos.beat % bpm
	elseif new_pos.beat < 0 then
		local underflow = -new_pos.beat
		new_pos.measure = new_pos.measure - math.ceil(underflow / bpm)
		new_pos.beat = (bpm - (underflow % bpm)) % bpm
	end

	-- Clamp measure — if it was out of bounds, pin to the boundary position
	local clamped_measure = math.max(0, math.min(default_measures - 1, new_pos.measure))
	if clamped_measure ~= new_pos.measure then
		-- Would have gone past the edge — stay put
		new_pos.measure = ctx.pos.measure
		new_pos.beat = ctx.pos.beat
		new_pos.sub = ctx.pos.sub
	else
		new_pos.measure = clamped_measure
		new_pos.beat = math.max(0, math.min(bpm - 1, new_pos.beat))
	end

	-- Clamp string
	local si = new_string_idx or ctx.string_idx
	si = math.max(0, math.min(num_strings - 1, si))

	local new_row = ctx.staff_top + si + 1 -- 1-indexed for nvim_win_set_cursor
	local new_col = staff.position_to_col(new_pos)

	vim.api.nvim_win_set_cursor(0, { new_row, new_col })

	-- Update highlights
	local beat_start_pos = { measure = new_pos.measure, beat = new_pos.beat, sub = 0 }
	hl.highlight_beat_column(state.bufnr, ctx.staff_top, staff.position_to_col(beat_start_pos), div * 3)
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
	local col = staff.position_to_col(ctx.pos)
	local line = vim.api.nvim_buf_get_lines(
		state.bufnr,
		ctx.staff_top + ctx.string_idx,
		ctx.staff_top + ctx.string_idx + 1,
		false
	)[1]
	local existing = line and line:sub(col + 1, col + 1)

	if existing and existing:match("%d") and char:match("%d") then
		-- Write double-digit fret: existing is tens digit, char is ones digit
		staff.write_double_digit(state.bufnr, ctx.staff_top, ctx.string_idx, ctx.pos, existing, char)
	else
		staff.write_char(state.bufnr, ctx.staff_top, ctx.string_idx, ctx.pos, char)
	end
end

--- Save existing buffer-local keymap for a key (if any), then set our override.
---@param bufnr integer
---@param key string
---@param callback function
---@param desc string
local function set_tab_keymap(bufnr, key, callback, desc)
	-- Check for existing buffer-local keymap to save
	local existing = vim.fn.maparg(key, "n", false, true)
	if existing and existing.buffer == 1 then
		saved_keymaps[key] = existing
	end

	vim.keymap.set("n", key, callback, {
		buffer = bufnr,
		nowait = true,
		desc = desc,
	})
	TAB_MODE_KEYS[#TAB_MODE_KEYS + 1] = key
end

function M.move_left()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	local p = vim.deepcopy(ctx.pos)
	p.sub = p.sub - 1
	if p.sub < 0 then
		p.sub = config.options.divisions - 1
		p.beat = p.beat - 1
	end
	move_to(ctx, p)
end

function M.move_right()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	local p = vim.deepcopy(ctx.pos)
	p.sub = p.sub + 1
	if p.sub >= config.options.divisions then
		p.sub = 0
		p.beat = p.beat + 1
	end
	move_to(ctx, p)
end

function M.move_previous_beat()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	local p = vim.deepcopy(ctx.pos)
	p.sub = 0
	p.beat = p.beat - 1
	move_to(ctx, p)
end

function M.move_next_beat()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	local p = vim.deepcopy(ctx.pos)
	p.sub = 0
	p.beat = p.beat + 1
	move_to(ctx, p)
end

function M.move_previous_measure()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	local p = vim.deepcopy(ctx.pos)
	p.sub = 0
	p.beat = 0
	p.measure = p.measure - 1
	move_to(ctx, p)
end

function M.move_next_measure()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	local p = vim.deepcopy(ctx.pos)
	p.sub = 0
	p.beat = 0
	p.measure = p.measure + 1
	move_to(ctx, p)
end

function M.move_next_string()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	move_to(ctx, ctx.pos, ctx.string_idx + 1)
end

function M.move_previous_string()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	move_to(ctx, ctx.pos, ctx.string_idx - 1)
end

function M.clear_cell()
	local ctx = get_cursor_context()
	if not ctx then
		return
	end
	staff.write_char(state.bufnr, ctx.staff_top, ctx.string_idx, ctx.pos, config.options.filler)
end

function M.clear_cell_and_move_left()
	M.clear_cell()
	M.move_left()
end

--- Install all tab-mode keymaps on the buffer.
---@param bufnr integer
local function install_keymaps(bufnr)
	TAB_MODE_KEYS = {}
	saved_keymaps = {}

	local keys = config.options.tabmode_keys
	for _, mapping in pairs(keys) do
		set_tab_keymap(bufnr, mapping.key, mapping.func, mapping.desc)
	end

	-- Writing: fret numbers 0-9
	for _, digit in ipairs({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }) do
		local d = digit -- capture for closure
		set_tab_keymap(bufnr, d, function()
			write_fret(d)
		end, "Tab mode: write fret " .. d)
	end
end

--- Remove all tab-mode keymaps, restoring saved ones.
---@param bufnr integer
local function uninstall_keymaps(bufnr)
	-- Only delete if buffer is still valid
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	for _, key in ipairs(TAB_MODE_KEYS) do
		pcall(vim.keymap.del, "n", key, { buffer = bufnr })
	end

	-- Restore any previously existing keymaps
	for key, map in pairs(saved_keymaps) do
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

	TAB_MODE_KEYS = {}
	saved_keymaps = {}
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
	local pos = staff.col_to_position(col)
	if pos then
		local beat_start = { measure = pos.measure, beat = pos.beat, sub = 0 }
		hl.highlight_beat_column(bufnr, top, staff.position_to_col(beat_start), config.options.divisions * 3)
		hl.show_mode_indicator(bufnr, top, pos)
	end

	-- Auto-exit if cursor leaves the buffer
	local aug = vim.api.nvim_create_augroup("TablatureModeExit_" .. bufnr, { clear = true })
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = aug,
		buffer = bufnr,
		once = true,
		callback = function()
			if state.active and state.bufnr == bufnr then
				M.exit()
			end
		end,
	})

	-- Wipe buffer on bufwipeout
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = aug,
		buffer = bufnr,
		once = true,
		callback = function()
			if state.active and state.bufnr == bufnr then
				M.exit()
			end
		end,
	})
end

--- Exit tab editing mode.
function M.exit()
	if not state.active then
		return
	end

	local bufnr = state.bufnr

	uninstall_keymaps(bufnr)
	hl.clear(bufnr)

	-- Clean up the auto-exit augroup
	pcall(vim.api.nvim_del_augroup_by_name, "TablatureModeExit_" .. bufnr)

	state.reset()
end

--- Open a tuning picker. Safe to call from both normal mode and tab mode.
--- When called from tab mode, restores cursor and re-enters after selection.
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
				vim.schedule(function()
					vim.api.nvim_win_set_cursor(win, cursor)
					M.enter()
				end)
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
			vim.schedule(function()
				vim.api.nvim_win_set_cursor(win, cursor)
				M.enter()
			end)
		end
	end)
end

return M
