local config = require("ipynb.config")
local Notebook = require("ipynb.notebook")
local conform = require("conform")

---@type Notebook[]
local notebooks = {}

local function setup(opts)
	config.setup(opts or {})

	-- on load
	vim.api.nvim_create_autocmd("BufReadCmd", {
		pattern = "*.ipynb",
		callback = function(args)
			if notebooks[args.file] == nil then
				notebooks[args.file] = Notebook:new(args.buf, args.file)
			else
				notebooks[args.file]:set_buffer_content()
				-- refresh extmarks
				for _, cell in ipairs(notebooks[args.file].cells) do
					cell:render_output(args.buf)
				end
			end

			conform.setup({
				formatters_by_ft = {
					python = { "black" }, -- Define the formatter for python
					markdown = { "injected" }, -- Use injected formatter for Quarto files
				},
			})

			-- Injected language formatting setup
			conform.formatters.injected = {
				options = {
					ignore_errors = false,
					lang_to_ext = {
						python = "py",
					},
					lang_to_formatters = {
						python = { "black" }, -- Define the formatter for python
					},
				},
			}
		end,
	})

	-- on save
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		pattern = "*.ipynb",
		callback = function(args)
			conform.format({ bufnr = args.buf })
			notebooks[args.file]:save_notebook()
		end,
	})

	vim.api.nvim_create_autocmd("BufLeave", {
		pattern = "*.ipynb",
		callback = function(args)
			notebooks[args.file].lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, true)
		end,
	})

	-- on close buf
	vim.api.nvim_create_autocmd("BufUnload", {
		pattern = "*.ipynb",
		callback = function(args)
			notebooks[args.file] = nil
		end,
	})
end

---Udpate a cell's output data according to the received message from jupyter kernel
---@param notebook_path string
---@param cell_id integer
---@param output table
local function update_cell_outputs(notebook_path, cell_id, output)
	local notebook = notebooks[notebook_path]
	local cell = notebook.cells[notebook.id2idx[cell_id]]
	if output["output_type"] == "status" then
		-- do nothing
	elseif output["output_type"] == "execute_input" then
		cell.execution_count = tostring(output["execution_count"])
	else
		table.insert(cell.outputs, output)
	end
	cell:render_output(notebook.buf)
end

return {
	setup = setup,
	update_cell_outputs = update_cell_outputs,
}
