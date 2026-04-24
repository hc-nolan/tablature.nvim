-- tablature/state.lua
-- Centralized mutable runtime state. Only one tab-mode session at a time.

local M = {}

-- Whether tab-editing mode is currently active
M.active = false

-- The buffer where tab mode is active
M.bufnr = nil

-- The line number (0-indexed) of the TOP string line of the active staff block
M.staff_top = nil

function M.reset()
	M.active = false
	M.bufnr = nil
	M.staff_top = nil
end

return M
