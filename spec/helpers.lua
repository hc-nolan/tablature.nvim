-- Shared test helpers: minimal vim stubs + package path setup.
-- Require this at the top of every spec file that needs to load plugin modules.

if not _G.vim then
	_G.vim = {
		tbl_deep_extend = function(_, base, override)
			local result = {}
			for k, v in pairs(base) do
				result[k] = v
			end
			for k, v in pairs(override or {}) do
				result[k] = v
			end
			return result
		end,
		startswith = function(s, prefix)
			return s:sub(1, #prefix) == prefix
		end,
	}
end

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
