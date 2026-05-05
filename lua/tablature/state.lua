-- Centralized mutable runtime state. Only one tab-mode session at a time.

local M = {}

-- Whether tab-editing mode is currently active
M.active = false

-- The buffer where tab mode is active
M.bufnr = nil

-- The line number (0-indexed) of the TOP string line of the active staff block
M.staff_top = nil

-- The active tuning; intentionally omitted from M.reset()
M.tuning = nil
-- Label width is derived from active tuning
M.label_width = nil

-- Used for double-digit notes. When one number is pressed, this is set to true
-- When any movement is triggered, it is reset
M.pending_digit = false

---@param tuning tablature.Tuning
function M.set_tuning(tuning)
	M.tuning = tuning
	-- Precompute label width
	M.label_width = require("tablature.staff").compute_label_width(tuning)
end

function M.reset()
	M.active = false
	M.bufnr = nil
	M.staff_top = nil
	M.pending_digit = false
end

return M
