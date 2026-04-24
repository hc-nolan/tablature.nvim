-- Defines and applies highlight groups for tab mode visual feedback.

local M = {}

local ns = vim.api.nvim_create_namespace("tablature")
M.ns = ns

--- Define highlight groups. Called once during setup.
--- Links to standard groups so it respects the user's colorscheme.
function M.init_highlights()
	-- Active cursor column highlight (the beat column the cursor is in)
	vim.api.nvim_set_hl(0, "TablatureCursor", { link = "CursorColumn", default = true })
	-- Staff line separators
	vim.api.nvim_set_hl(0, "TablatureSep", { link = "Comment", default = true })
	-- Mode indicator text
	vim.api.nvim_set_hl(0, "TablatureMode", { link = "ModeMsg", default = true })
	-- Measure number virtual text
	vim.api.nvim_set_hl(0, "TablatureMeasure", { link = "LineNr", default = true })
end

--- Clear all tablature extmarks from a buffer.
---@param bufnr integer
function M.clear(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Highlight the current beat column across all 6 staff lines.
---@param bufnr integer
---@param staff_top integer   0-indexed line of top string
---@param col integer         0-indexed byte column of beat start
---@param divisions integer   width of the beat cell
function M.highlight_beat_column(bufnr, staff_top, col, divisions)
	local cfg = require("tablature.config").options
	local num_strings = #cfg.strings

	M.clear(bufnr)

	for i = 0, num_strings - 1 do
		local row = staff_top + i
		vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, {
			end_col = col + divisions,
			hl_group = "TablatureCursor",
			priority = 100,
		})
	end
end

--- Show a virtual text indicator above the staff that says "-- TAB --"
--- and the current position info.
---@param bufnr integer
---@param staff_top integer
---@param pos tablature.staff.position
function M.show_mode_indicator(bufnr, staff_top, pos)
	-- Place virtual text on the line ABOVE the staff (or inline if at top of file)
	local virt_row = math.max(0, staff_top - 1)
	local text = "-- TAB MODE --"
	if pos then
		text = string.format("-- TAB -- m:%d b:%d c:%d", pos.measure + 1, pos.beat + 1, pos.sub + 1)
	end

	vim.api.nvim_buf_set_extmark(bufnr, ns, virt_row, 0, {
		virt_text = { { text, "TablatureMode" } },
		virt_text_pos = "eol",
		id = 1, -- stable ID so we can update it in-place
	})
end

return M
