-- Implements chord mode: a persistent sub-mode layered on top of tab mode.
-- Stays active until the user presses <Esc> or q, which returns to plain tab
-- mode (not a full exit).
--
-- Cursor/movement functions are injected by mode.lua to avoid circular requires.
-- See M.enter() for the full deps contract.

local config = require("tablature.config")
local state = require("tablature.state")
local staff = require("tablature.staff")
local hl = require("tablature.highlights")

local M = {}

local CHORD_PREVIEW_NS = vim.api.nvim_create_namespace("tablature_chord_preview")

local chord_mode = {
	active = false,
	shapes = {}, -- merged {[name]=shape} for current session
	shape_names = {}, -- sorted keys of chord_mode.shapes
	shape_idx = 1, -- index into chord_mode.shape_names
	offset = 0, -- root fret offset applied to all numeric values
}

-- Active keymap layer (nil when chord mode is not running).
local chord_layer = nil

--- Redraw the chord preview overlay at the current cursor position.
---@param bufnr integer
---@param ctx_fn function  injected get_cursor_context
local function draw_chord_preview(bufnr, ctx_fn)
	vim.api.nvim_buf_clear_namespace(bufnr, CHORD_PREVIEW_NS, 0, -1)
	local ctx = ctx_fn()
	if not ctx then
		return
	end
	local shape_name = chord_mode.shape_names[chord_mode.shape_idx]
	local shape = chord_mode.shapes[shape_name]
	local voicing = staff.apply_offset(shape, chord_mode.offset)
	local num_strings = #state.tuning.strings
	local col = staff.buf_position_to_col(state.bufnr, state.staff_top, ctx.pos)
	for string_idx = 0, num_strings - 1 do
		local v = voicing[num_strings - string_idx] or "-"
		local row = ctx.staff_top + string_idx
		vim.api.nvim_buf_set_extmark(bufnr, CHORD_PREVIEW_NS, row, col, {
			virt_text = { { v, "TabChordPreview" } },
			virt_text_pos = "overlay",
		})
	end
	hl.show_chord_legend(
		CHORD_PREVIEW_NS,
		bufnr,
		ctx.staff_top,
		shape_name,
		chord_mode.offset,
		chord_layer.get_keylist()
	)
end

--- Exit chord mode, restoring the tab-mode keymaps chord mode shadowed.
--- Returns to plain tab mode (does NOT call mode.exit()).
function M.exit()
	if not chord_mode.active then
		return
	end
	chord_mode.active = false

	local bufnr = state.bufnr
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_clear_namespace(bufnr, CHORD_PREVIEW_NS, 0, -1)
	end

	if chord_layer then
		chord_layer.uninstall()
		chord_layer = nil
	end

	chord_mode.shapes = {}
	chord_mode.shape_names = {}
	chord_mode.shape_idx = 1
	chord_mode.offset = 0

	-- Restore the tab mode legend
	if state.bufnr and state.staff_top and vim.api.nvim_buf_is_valid(state.bufnr) then
		hl.show_tab_legend(state.bufnr, state.staff_top)
	end
end

---@return boolean
function M.is_active()
	return chord_mode.active
end

--- Enter chord mode. Tab mode must already be active.
--- Installs chord-mode keymaps on top of the existing tab-mode keymaps.
---@param bufnr integer
---@param initial_shape_name string  name of the shape to start with
---@param shapes table<string, string[]>  merged {[name]=shape} for this session
---@param deps table  injected dependencies:
---   deps.new_layer(bufnr) -> layer   keymap layer factory from mode.lua
---   deps.get_context() -> ctx|nil    get_cursor_context from mode.lua
---   deps.movement.left()             move functions from mode.lua
---   deps.movement.right()
---   deps.movement.previous_measure()
---   deps.movement.next_measure()
---   deps.reenter()                   M.insert_chord from mode.lua (for C key)
function M.enter(bufnr, initial_shape_name, shapes, deps)
	if chord_mode.active then
		M.exit()
	end

	local names = vim.tbl_keys(shapes)
	table.sort(names)

	chord_mode.active = true
	chord_layer = deps.new_layer(bufnr)
	chord_mode.shapes = shapes
	chord_mode.shape_names = names
	chord_mode.offset = 0

	-- Hide the tab legend while chord mode shows its own
	hl.clear_tab_legend(bufnr)

	-- Find the index of the initially selected shape
	chord_mode.shape_idx = 1
	for i, name in ipairs(names) do
		if name == initial_shape_name then
			chord_mode.shape_idx = i
			break
		end
	end

	local ctx_fn = deps.get_context
	local function preview()
		draw_chord_preview(bufnr, ctx_fn)
	end

	-- Tab / S-Tab: cycle through shapes
	chord_layer.set("<Tab>", function()
		chord_mode.shape_idx = (chord_mode.shape_idx % #chord_mode.shape_names) + 1
		preview()
	end, "Chord mode: next shape")

	chord_layer.set("<S-Tab>", function()
		chord_mode.shape_idx = ((chord_mode.shape_idx - 2) % #chord_mode.shape_names) + 1
		preview()
	end, "Chord mode: previous shape")

	-- + / = / - : adjust root fret offset
	local function offset_up()
		chord_mode.offset = chord_mode.offset + 1
		preview()
	end
	local function offset_down()
		chord_mode.offset = math.max(0, chord_mode.offset - 1)
		preview()
	end
	chord_layer.set("+", offset_up, "Chord mode: root fret up")
	chord_layer.set("=", offset_up, "Chord mode: root fret up")
	chord_layer.set("-", offset_down, "Chord mode: root fret down")

	-- CR: write the current voicing and stay in chord mode
	chord_layer.set("<CR>", function()
		local ctx = ctx_fn()
		if ctx then
			local shape_name = chord_mode.shape_names[chord_mode.shape_idx]
			local shape = chord_mode.shapes[shape_name]
			local voicing = staff.apply_offset(shape, chord_mode.offset)
			staff.write_chord(bufnr, ctx.staff_top, ctx.pos, voicing)
		end
		preview()
	end, "Chord mode: insert chord and stay")

	chord_layer.set("<Esc>", M.exit, "Chord mode: exit to tab mode")
	chord_layer.set("q", M.exit, "Chord mode: exit to tab mode")

	chord_layer.set("C", function()
		M.exit()
		deps.reenter()
	end, "Chord mode: re-pick shape")

	local move_map = {
		{ key = "h", fn = deps.movement.left },
		{ key = "<Left>", fn = deps.movement.left },
		{ key = "l", fn = deps.movement.right },
		{ key = "<Right>", fn = deps.movement.right },
		{ key = "H", fn = deps.movement.previous_measure },
		{ key = "L", fn = deps.movement.next_measure },
		{ key = "{", fn = deps.movement.previous_measure },
		{ key = "}", fn = deps.movement.next_measure },
	}
	for _, m in ipairs(move_map) do
		chord_layer.set(m.key, function()
			m.fn()
			preview()
		end, "Chord mode: move")
	end

	preview()
end

return M
