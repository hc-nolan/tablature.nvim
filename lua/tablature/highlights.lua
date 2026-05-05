-- Defines and applies highlight groups for tab mode visual feedback.
local EXTMARK_MODE_INDICATOR = 1
local EXTMARK_CHORD_LEGEND = 99

local M = {}

local staff = require("tablature.staff")
local state = require("tablature.state")
local config = require("tablature.config")

local ns = vim.api.nvim_create_namespace("tablature")
M.ns = ns

local legend_ns = vim.api.nvim_create_namespace("tablature_legend")

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
	-- Chord voicing preview overlay
	vim.api.nvim_set_hl(0, "TabChordPreview", { link = "Search", default = true })
end

--- Clear all tablature extmarks from a buffer.
---@param bufnr integer
function M.clear(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(bufnr, legend_ns, 0, -1)
end

--- Clear only the tab mode legend virtual text.
---@param bufnr integer
function M.clear_tab_legend(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, legend_ns, 0, -1)
end

--- Build formatted legend lines from a list of {key, desc} mappings.
--- Keys sharing the same description are grouped: "[k1/k2: Desc]", 4 per line.
--- An optional strip_prefix string is removed from the start of each desc.
---@param mappings {key: string, desc: string}[]
---@param strip_prefix string|nil
---@return string[]
local function build_legend_lines(mappings, strip_prefix)
	local order = {}
	local groups = {}
	for _, mapping in ipairs(mappings) do
		local desc = strip_prefix and mapping.desc:gsub("^" .. vim.pesc(strip_prefix), "") or mapping.desc
		desc = desc:sub(1, 1):upper() .. desc:sub(2)
		if not groups[desc] then
			groups[desc] = {}
			order[#order + 1] = desc
		end
		groups[desc][#groups[desc] + 1] = mapping.key
	end
	local parts = {}
	for _, desc in ipairs(order) do
		local keys = table.concat(groups[desc], "/")
		parts[#parts + 1] = "[" .. keys .. ": " .. desc .. "]"
	end
	local lines = {}
	for i = 1, #parts, 4 do
		local count = math.min(4, #parts - i + 1)
		lines[#lines + 1] = "  " .. table.concat(parts, "  ", i, i + count - 1)
	end
	return lines
end

--- Show a legend below the staff listing available tab mode keybinds,
--- built dynamically from config.tabmode_keys.
---@param bufnr integer
---@param staff_top integer  0-indexed row of the top staff line
function M.show_tab_legend(bufnr, staff_top)
	local num_strings = #state.tuning.strings
	local bottom_row = staff_top + num_strings - 1
	local legend_lines = build_legend_lines(config.options.tabmode_keys, "Tab mode: ")
	local virt_lines = {}
	for _, line in ipairs(legend_lines) do
		virt_lines[#virt_lines + 1] = { { line, "Comment" } }
	end
	vim.api.nvim_buf_set_extmark(bufnr, legend_ns, bottom_row, 0, {
		virt_lines = virt_lines,
		virt_lines_above = false,
		id = 1,
	})
end

--- Show the chord mode legend below the staff.
--- Renders a header line with the shape name and fret offset, followed by
--- key hint lines formatted as "[key: Desc]", 4 per line.
---@param chord_ns integer       extmark namespace owned by chord mode
---@param bufnr integer
---@param staff_top integer
---@param shape_name string
---@param fret_offset integer
---@param keymaps {key: string, desc: string}[]  chord mode key list
function M.show_chord_legend(chord_ns, bufnr, staff_top, shape_name, fret_offset, keymaps)
	local num_strings = #state.tuning.strings
	local bottom_row = staff_top + num_strings - 1
	local header = string.format("  %s  fret: +%d", shape_name, fret_offset)
	local legend_lines = build_legend_lines(keymaps, "Chord mode: ")
	local virt_lines = { { { header, "TablatureMode" } } }
	for _, line in ipairs(legend_lines) do
		virt_lines[#virt_lines + 1] = { { line, "Comment" } }
	end
	vim.api.nvim_buf_set_extmark(bufnr, chord_ns, bottom_row, 0, {
		virt_lines = virt_lines,
		virt_lines_above = false,
		id = EXTMARK_CHORD_LEGEND,
	})
end

--- Highlight the current beat column across all 6 staff lines.
---@param bufnr integer
---@param staff_top integer   0-indexed line of top string
---@param col integer         0-indexed byte column of beat start
---@param divisions integer   width of the beat cell
function M.highlight_beat_column(bufnr, staff_top, col, divisions)
	local num_strings = #state.tuning.strings

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

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
		local total_beats = staff.get_measure_beats(bufnr, staff_top, pos.measure)
		text = string.format("-- TAB -- m:%d b:%d/%d", pos.measure + 1, pos.beat + 1, total_beats)
	end

	vim.api.nvim_buf_set_extmark(bufnr, ns, virt_row, 0, {
		virt_text = { { text, "TablatureMode" } },
		virt_text_pos = "eol",
		id = EXTMARK_MODE_INDICATOR, -- stable ID so we can update it in-place
	})
end

return M
