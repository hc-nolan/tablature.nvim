local M = {}

--- Describes a key mapping
---@class tablature.KeyMap
---@field key string  The key to map
---@field func function  Function for the keymap to call
---@field desc string  Keymap description

--- Describes a tuning
---@class tablature.Tuning
---@field name string  The name of the tuning, e.g. "Drop D"
---@field strings string[]  String names from low to high (e.g. E A D G B e for standard)

--- A chord shape: one fret value per string (low→high).
--- Each value is either "x" (muted) or a numeric string giving the fret
--- offset from the root (e.g. "0", "2", "12"). The root fret is added to
--- all non-muted values at insert time, so the same shape can be slid up
--- and down the neck.
---@alias tablature.ChordShape string[]

--- Chord shape library. Keys are tuning names (matching tablature.Tuning.name)
--- plus the special key "default" for shapes that apply to all tunings.
--- At runtime, the active tuning's shapes are merged with "default" (tuning-
--- specific shapes take precedence on name collisions).
---@alias tablature.ChordsConfig table<string, table<string, tablature.ChordShape>>

---@class tablature.UserConfig
---@field default_mappings boolean  Whether or not to register the default keymaps
---@field tabmode_keys table<tablature.KeyMap>
---@field divisions integer  How many columns per beat (4 = quarter notes, 8 = eighths, etc.)
---@field beats_per_measure integer  Number of beats per measure
---@field default_measures integer  Number of measures to insert when creating a new staff block
---@field tunings tablature.Tuning[]  Any number of tunings to use when generating staves
---@field chords tablature.ChordsConfig  Per-tuning chord shape libraries
---@field filler string  Character used to fill empty columns
---@field measure_sep string  Character used as the measure separator

M.defaults = {
	default_mappings = true,
	divisions = 4,
	beats_per_measure = 4,
	default_measures = 2,
	tunings = {
		{
			name = "Standard",
			strings = { "E", "A", "D", "G", "B", "e" },
		},
		{
			name = "Drop D",
			strings = { "D", "A", "D", "G", "B", "e" },
		},
	},
	-- Per-tuning chord shape libraries.
	-- "default" shapes are available in all tunings; tuning-specific shapes
	-- (keyed by tuning name) are merged on top at runtime.
	-- Each shape is a low→high list of fret offsets from a root fret.
	-- "x" = muted; numeric strings shift together when the root fret changes.
	chords = {
		-- ── Tuning-agnostic shapes ────────────────────────────────────────
		default = {
			["Power 5th (E root)"] = { "0", "2", "2", "x", "x", "x" },
			["Power 5th (A root)"] = { "x", "0", "2", "2", "x", "x" },
			["Power 5th (D root)"] = { "x", "x", "0", "2", "2", "x" },
		},
		-- ── Standard tuning (E A D G B e) ────────────────────────────────
		Standard = {
			-- Movable barre shapes (E-string root)
			["Major (E shape)"]  = { "0", "2", "2", "1", "0", "0" },
			["Minor (E shape)"]  = { "0", "2", "2", "0", "0", "0" },
			["7th (E shape)"]    = { "0", "2", "0", "1", "0", "0" },
			["Maj7 (E shape)"]   = { "0", "2", "1", "1", "0", "0" },
			["m7 (E shape)"]     = { "0", "2", "0", "0", "0", "0" },
			-- Movable barre shapes (A-string root)
			["Major (A shape)"]  = { "x", "0", "2", "2", "2", "0" },
			["Minor (A shape)"]  = { "x", "0", "2", "2", "1", "0" },
			["7th (A shape)"]    = { "x", "0", "2", "0", "2", "0" },
			["Maj7 (A shape)"]   = { "x", "0", "2", "1", "2", "0" },
			-- Movable shapes (D-string root)
			["Major (D shape)"]  = { "x", "x", "0", "2", "3", "2" },
			["Minor (D shape)"]  = { "x", "x", "0", "2", "3", "1" },
			["7th (D shape)"]    = { "x", "x", "0", "2", "1", "2" },
			-- Open/unique shapes (play at root fret 0)
			["C major"]          = { "x", "3", "2", "0", "1", "0" },
			["G major"]          = { "3", "2", "0", "0", "0", "3" },
			["G7"]               = { "3", "2", "0", "0", "0", "1" },
		},
		-- ── Drop D tuning (D A D G B e) ───────────────────────────────────
		["Drop D"] = {
			-- Movable barre shapes (D-string root, all three low strings)
			["Major (E shape)"]  = { "0", "2", "2", "1", "0", "0" },
			["Minor (E shape)"]  = { "0", "2", "2", "0", "0", "0" },
			["7th (E shape)"]    = { "0", "2", "0", "1", "0", "0" },
			-- Drop D-specific: one-finger power chord on low three strings
			["Power (Drop D)"]   = { "0", "0", "0", "x", "x", "x" },
			-- A-string and D-string shapes carry over from Standard
			["Major (A shape)"]  = { "x", "0", "2", "2", "2", "0" },
			["Minor (A shape)"]  = { "x", "0", "2", "2", "1", "0" },
			["7th (A shape)"]    = { "x", "0", "2", "0", "2", "0" },
			["Major (D shape)"]  = { "x", "x", "0", "2", "3", "2" },
			["Minor (D shape)"]  = { "x", "x", "0", "2", "3", "1" },
			["G major"]          = { "x", "2", "0", "0", "0", "3" },
		},
	},
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
		{
			key = "<leader>tt",
			desc = "Tab mode: change tuning",
			func = function()
				require("tablature.mode").pick_tuning()
			end,
		},
		{
			key = "C",
			desc = "Tab mode: insert chord",
			func = function()
				require("tablature.mode").insert_chord()
			end,
		},
	},
}

-- Merged config (populated by setup())
M.options = {}

---Merge user opts with defaults. Safe to call multiple times.
---@param opts tablature.UserConfig|nil
function M.set(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
