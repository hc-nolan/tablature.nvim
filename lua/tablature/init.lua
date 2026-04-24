local M = {}

--- Setup the plugin. Call this from your Neovim config.
---@param opts table|nil  User configuration (see config.lua for available keys)
function M.setup(opts)
	local config = require("tablature.config")
	config.set(opts)
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
