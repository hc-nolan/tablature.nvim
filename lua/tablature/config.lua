local M = {}

---@class tablature.UserConfig
---@field default_mappings boolean  Whether or not to register the default keymaps
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
	default_measures = 4,
	strings = { "e", "B", "G", "D", "A", "E" },
	filler = "-",
	measure_sep = "|",
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
