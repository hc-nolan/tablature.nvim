local M = {}

--- Describes a key mapping
---@class tablature.KeyMap
---@field key string  The key to map
---@field func function  Function for the keymap to call
---@field desc string  Keymap description

---@class tablature.UserConfig
---@field default_mappings boolean  Whether or not to register the default keymaps
---@field tabmode_keys table<tablature.KeyMap>
---@field divisions integer  How many columns per beat (4 = quarter notes, 8 = eighths, etc.)
---@field beats_per_measure integer  Number of beats per measure
---@field default_measures integer  Number of measures to insert when creating a new staff block
---@field strings string[]  String names from high to low (displayed top to bottom)
---@field filler string  Character used to fill empty columns
---@field measure_sep string  Character used as the measure separator

---@class tablature.Config : tablature.UserConfig
---@field label_width integer  Derived: max length of any string label.

M.defaults = {
	default_mappings = true,
	divisions = 4,
	beats_per_measure = 4,
	default_measures = 2,
	strings = { "e", "B", "G", "D", "A", "E" },
	filler = "-",
	measure_sep = "|",
	tabmode_keys = {
		{
			key = "h",
			func = function()
				require("tablature.mode").move_left()
			end,
			desc = "Tab mode: move left",
		},
		{
			key = "<Left>",
			func = function()
				require("tablature.mode").move_left()
			end,
			desc = "Tab mode: move left",
		},
		{
			key = "l",
			func = function()
				require("tablature.mode").move_right()
			end,
			desc = "Tab mode: move right",
		},
		{
			key = "<Right>",
			func = function()
				require("tablature.mode").move_right()
			end,
			desc = "Tab mode: move right",
		},
		{
			key = "H",
			func = function()
				require("tablature.mode").move_previous_beat()
			end,
			desc = "Tab mode: move to previous beat",
		},
		{
			key = "L",
			func = function()
				require("tablature.mode").move_next_beat()
			end,
			desc = "Tab mode: move to next beat",
		},
		{
			key = "}",
			func = function()
				require("tablature.mode").move_next_measure()
			end,
			desc = "Tab mode: move to next measure",
		},
		{
			key = "{",
			func = function()
				require("tablature.mode").move_previous_measure()
			end,
			desc = "Tab mode: move to previous measure",
		},
		{
			key = "j",
			func = function()
				require("tablature.mode").move_next_string()
			end,
			desc = "Tab mode: move to next string",
		},
		{
			key = "k",
			func = function()
				require("tablature.mode").move_previous_string()
			end,
			desc = "Tab mode: move to previous string",
		},
		{
			key = "<Space>",
			func = function()
				require("tablature.mode").clear_cell()
			end,
			desc = "Tab mode: clear cell",
		},
		{
			key = "<BS>",
			func = function()
				require("tablature.mode").clear_cell_and_move_left()
			end,
			desc = "Tab mode: clear cell",
		},
		{
			key = "<Esc>",
			func = function()
				require("tablature.mode").exit()
			end,
			desc = "Tab mode: exit tab mode",
		},
		{
			key = "q",
			func = function()
				require("tablature.mode").exit()
			end,
			desc = "Tab mode: exit tab mode",
		},
	},
}

-- Merged config (populated by setup())
M.options = {}

---Merge user opts with defaults. Safe to call multiple times.
---@param opts tablature.UserConfig|nil
function M.set(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
	-- Precompute label width
	local longest = 0
	for _, v in ipairs(M.options.strings) do
		if #v > longest then
			longest = #v
		end
	end
	M.options.label_width = longest
end

return M
