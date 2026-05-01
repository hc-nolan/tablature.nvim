local M = {}

--- Setup the plugin. Call this from your Neovim config.
---@param opts tablature.UserConfig|nil  User configuration (see config.lua for available keys)
function M.setup(opts)
	local config = require("tablature.config")
	config.set(opts)
	if config.options.default_mappings then
		vim.keymap.set("n", "<leader>ti", "<Plug>(tablature-insert)")
		vim.keymap.set("n", "<leader>te", "<Plug>(tablature-edit)")
		vim.keymap.set("n", "<leader>tt", "<Plug>(tablature-change-tuning)")
	end

	local tuning = config.options.tunings[1]
	require("tablature.state").set_tuning(tuning)
end

M.enter = function()
	require("tablature.mode").enter()
end
M.exit = function()
	require("tablature.mode").exit()
end
M.insert = function()
	local staff = require("tablature.staff")
	staff.insert_below_cursor(vim.api.nvim_get_current_buf())
end

return M
