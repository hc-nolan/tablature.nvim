-- Implements the tab-editing "mode" overlay.
--
--   1. Save any existing buffer-local keymaps that we're about to shadow.
--   2. Install buffer-local keymaps that intercept character input.
--   3. On exit, restore the original keymaps and clean up.
--
-- Behaviours:
--   - Printable chars  → write character at cursor position, advance right
--   - h / <Left>       → move left one sub-column
--   - l / <Right>      → move right one sub-column
--   - H                → move left one beat
--   - L                → move right one beat
--   - {                → move left one measure
--   - }                → move right one measure
--   - j / k            → move down/up one string (row)
--   - <Space>          → write filler char (clear the cell)
--   - <BS>             → move left and clear
--   - <Esc> / q        → exit tab mode

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
	local num_strings = #cfg.strings

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

	-- Clamp measure
	new_pos.measure = math.max(0, math.min(default_measures - 1, new_pos.measure))

	-- Clamp beat within the (possibly clamped) measure
	new_pos.beat = math.max(0, math.min(bpm - 1, new_pos.beat))

	-- Clamp string
	local si = new_string_idx or ctx.string_idx
	si = math.max(0, math.min(num_strings - 1, si))

	local new_row = ctx.staff_top + si + 1 -- 1-indexed for nvim_win_set_cursor
	local new_col = staff.position_to_col(new_pos)

	vim.api.nvim_win_set_cursor(0, { new_row, new_col })

	-- Update highlights
	local beat_start_pos = { measure = new_pos.measure, beat = new_pos.beat, sub = 0 }
	hl.highlight_beat_column(state.bufnr, ctx.staff_top, staff.position_to_col(beat_start_pos), div)
	hl.show_mode_indicator(state.bufnr, ctx.staff_top, new_pos)
end

--- Write a character at the cursor, then advance right.
---@param char string
local function write_and_advance(char)
	local ctx = get_cursor_context()
	if not ctx then
		return
	end

	staff.write_char(state.bufnr, ctx.staff_top, ctx.string_idx, ctx.pos, char)

	-- Advance right by one sub-column
	local new_pos = vim.deepcopy(ctx.pos)
	new_pos.sub = new_pos.sub + 1
	if new_pos.sub >= config.options.divisions then
		new_pos.sub = 0
		new_pos.beat = new_pos.beat + 1
	end
	move_to(ctx, new_pos)
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

local function move_left()
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

local function move_right()
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

--- Install all tab-mode keymaps on the buffer.
---@param bufnr integer
local function install_keymaps(bufnr)
	TAB_MODE_KEYS = {}
	saved_keymaps = {}

	-- Movement
	set_tab_keymap(bufnr, "h", move_left, "Tab mode: move left")
	set_tab_keymap(bufnr, "<Left>", move_left, "Tab mode: move left")

	set_tab_keymap(bufnr, "l", move_right, "Tab mode: move right")
	set_tab_keymap(bufnr, "<Right>", move_right, "Tab mode: move right")

	set_tab_keymap(bufnr, "H", function()
		local ctx = get_cursor_context()
		if not ctx then
			return
		end
		local p = vim.deepcopy(ctx.pos)
		p.sub = 0
		p.beat = p.beat - 1
		move_to(ctx, p)
	end, "Tab mode: previous beat")

	set_tab_keymap(bufnr, "L", function()
		local ctx = get_cursor_context()
		if not ctx then
			return
		end
		local p = vim.deepcopy(ctx.pos)
		p.sub = 0
		p.beat = p.beat + 1
		move_to(ctx, p)
	end, "Tab mode: next beat")

	set_tab_keymap(bufnr, "{", function()
		local ctx = get_cursor_context()
		if not ctx then
			return
		end
		local p = vim.deepcopy(ctx.pos)
		p.sub = 0
		p.beat = 0
		p.measure = p.measure - 1
		move_to(ctx, p)
	end, "Tab mode: previous measure")

	set_tab_keymap(bufnr, "}", function()
		local ctx = get_cursor_context()
		if not ctx then
			return
		end
		local p = vim.deepcopy(ctx.pos)
		p.sub = 0
		p.beat = 0
		p.measure = p.measure + 1
		move_to(ctx, p)
	end, "Tab mode: next measure")

	set_tab_keymap(bufnr, "j", function()
		local ctx = get_cursor_context()
		if not ctx then
			return
		end
		move_to(ctx, ctx.pos, ctx.string_idx + 1)
	end, "Tab mode: next string (lower pitch)")

	set_tab_keymap(bufnr, "k", function()
		local ctx = get_cursor_context()
		if not ctx then
			return
		end
		move_to(ctx, ctx.pos, ctx.string_idx - 1)
	end, "Tab mode: prev string (higher pitch)")

	-- Writing: fret numbers 0-9
	for _, digit in ipairs({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }) do
		local d = digit -- capture for closure
		set_tab_keymap(bufnr, d, function()
			write_and_advance(d)
		end, "Tab mode: write fret " .. d)
	end

	-- Space clears the current cell
	set_tab_keymap(bufnr, "<Space>", function()
		local ctx = get_cursor_context()
		if not ctx then
			return
		end
		staff.write_char(state.bufnr, ctx.staff_top, ctx.string_idx, ctx.pos, config.options.filler)
	end, "Tab mode: clear cell")

	-- Backspace: clear and move left
	set_tab_keymap(bufnr, "<BS>", function()
		move_left()
		-- Then clear the cell we moved to (need fresh ctx after move)
		local ctx2 = get_cursor_context()
		if ctx2 then
			staff.write_char(state.bufnr, ctx2.staff_top, ctx2.string_idx, ctx2.pos, config.options.filler)
		end
	end, "Tab mode: backspace")

	set_tab_keymap(bufnr, "<Esc>", M.exit, "Tab mode: exit")
	set_tab_keymap(bufnr, "q", M.exit, "Tab mode: exit")
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
		hl.highlight_beat_column(bufnr, top, staff.position_to_col(beat_start), config.options.divisions)
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

	vim.notify("tablature: entered tab mode  (<Esc> or q to exit)", vim.log.levels.INFO)
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
	vim.notify("tablature: exited tab mode", vim.log.levels.INFO)
end

return M
