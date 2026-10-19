local options = {
	scale_factor = 1.0,
	save_outputs = false,
}

local function setup(opts)
	options = vim.tbl_extend("force", options, opts)
end

return {
	opts = options,
	setup = setup,
}
