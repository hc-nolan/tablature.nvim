require("tablature").setup()
local hl = require("tablature.highlights")
hl.init_highlights()

-- Insert a new staff block
vim.keymap.set("n", "<Plug>(tablature-insert)", function()
	local staff = require("tablature.staff")
	local bufnr = vim.api.nvim_get_current_buf()
	staff.insert_below_cursor(bufnr)
end, { desc = "Tablature: insert new tab staff below cursor" })

-- Enter tab mode (only meaningful when on a staff block)
vim.keymap.set("n", "<Plug>(tablature-edit)", function()
	require("tablature.mode").enter()
end, { desc = "Tablature: enter tab editing mode" })

-- Change active tuning (also works in tab mode)
vim.keymap.set("n", "<Plug>(tablature-change-tuning)", function()
	require("tablature.mode").pick_tuning()
end, { desc = "Tablature: select tuning" })
