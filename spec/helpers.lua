-- Shared test helpers: minimal vim stubs + package path setup.
-- Require this at the top of every spec file that needs to load plugin modules.

if not _G.vim then
	local buffers = {}
	local next_bufnr = 1
	local win_cursor = { 1, 0 }
	local next_ns = 1
	local extmarks = {}

	_G.vim = {
		tbl_deep_extend = function(mode, base, ...)
			local result = {}
			for k, v in pairs(base) do
				result[k] = type(v) == "table" and vim.tbl_deep_extend(mode, v) or v
			end
			for _, override in ipairs({ ... }) do
				for k, v in pairs(override or {}) do
					if type(v) == "table" and type(result[k]) == "table" then
						result[k] = vim.tbl_deep_extend(mode, result[k], v)
					else
						result[k] = v
					end
				end
			end
			return result
		end,
		startswith = function(s, prefix)
			return s:sub(1, #prefix) == prefix
		end,
		pesc = function(s)
			return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
		end,
		api = {
			nvim_buf_line_count = function(bufnr)
				return #(buffers[bufnr] or {})
			end,
			nvim_buf_is_valid = function(bufnr)
				return buffers[bufnr] ~= nil
			end,
			nvim_buf_get_lines = function(bufnr, start, stop, _)
				local buf = buffers[bufnr] or {}
				local result = {}
				for i = start + 1, stop do
					result[#result + 1] = buf[i]
				end
				return result
			end,
			nvim_buf_set_lines = function(bufnr, start, stop, _, replacement)
				local buf = buffers[bufnr] or {}
				-- Remove lines in [start, stop) and insert replacement
				for _ = start + 1, stop do
					table.remove(buf, start + 1)
				end
				for i, line in ipairs(replacement) do
					table.insert(buf, start + i, line)
				end
				buffers[bufnr] = buf
			end,
			nvim_win_get_cursor = function(_)
				return { win_cursor[1], win_cursor[2] }
			end,
			nvim_win_set_cursor = function(_, pos)
				win_cursor = { pos[1], pos[2] }
			end,
			nvim_create_namespace = function(_)
				next_ns = next_ns + 1
				return next_ns
			end,
			nvim_buf_clear_namespace = function(bufnr, ns, _, _)
				local kept = {}
				for _, mark in ipairs(extmarks[bufnr] or {}) do
					if mark.ns ~= ns then
						kept[#kept + 1] = mark
					end
				end
				extmarks[bufnr] = kept
			end,
			nvim_buf_set_extmark = function(bufnr, ns, row, col, opts)
				extmarks[bufnr] = extmarks[bufnr] or {}
				extmarks[bufnr][#extmarks[bufnr] + 1] = { ns = ns, row = row, col = col, opts = opts }
				return #extmarks[bufnr]
			end,
		},
	}

	-- Helper: create a fake buffer from a list of lines; returns bufnr
	function _G.make_buffer(lines)
		local bufnr = next_bufnr
		next_bufnr = next_bufnr + 1
		buffers[bufnr] = {}
		for i, line in ipairs(lines) do
			buffers[bufnr][i] = line
		end
		return bufnr
	end

	-- Helper: read all lines from a fake buffer
	function _G.buf_lines(bufnr)
		return buffers[bufnr] or {}
	end

	-- Helper: place the cursor at a 1-indexed row and 0-indexed column
	function _G.set_cursor(row, col)
		win_cursor = { row, col }
	end

	-- Helper: read the cursor as { row, col } (1-indexed row, 0-indexed col)
	function _G.buf_cursor()
		return { win_cursor[1], win_cursor[2] }
	end

	-- Helper: read the extmarks placed in a buffer
	function _G.buf_extmarks(bufnr)
		return extmarks[bufnr] or {}
	end
end

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
