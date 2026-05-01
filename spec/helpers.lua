-- Shared test helpers: minimal vim stubs + package path setup.
-- Require this at the top of every spec file that needs to load plugin modules.

if not _G.vim then
	local buffers = {}
	local next_bufnr = 1

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
		api = {
			nvim_buf_line_count = function(bufnr)
				return #(buffers[bufnr] or {})
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
end

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
