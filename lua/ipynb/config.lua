local default_options = {
	image_scale_factor = 1.0,
	save_outputs = true,
}

local opts = {}

setmetatable(opts, {
	__index = function(_, key)
		return default_options[key]
	end,
	__newindex = function(_, key, value)
		default_options[key] = value
	end,
})

---@param options table
local function setup(options)
	default_options = vim.tbl_extend("force", default_options, options)
end

return {
	opts = opts,
	setup = setup,
}
