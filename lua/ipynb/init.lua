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
			notebooks[args.file] = Notebook:new(args.buf, args.file)

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

	local wk = require("which-key")
	wk.add({
		{ "<localleader>r", "<cmd>NBRunCell<cr>", desc = "NBRunCell" },
		{ "<localleader>o", "<cmd>NBEnterCellOutput<cr>", desc = "NBEnterCellOutput" },
		{ "]c", "<cmd>NBNextCell<cr>", desc = "NBNextCell" },
		{ "[c", "<cmd>NBPrevCell<cr>", desc = "NBPrevCell" },
		{ "<localleader>a", "<cmd>NBAddCellAbove<cr>", desc = "NBAddCellAbove" },
		{ "<localleader>b", "<cmd>NBAddCellBelow<cr>", desc = "NBAddCellBelow" },
		{ "<localleader>R", "<cmd>NBRunAndAddCellBelow<cr>", desc = "NBRunAndAddCellBelow" },
		{ "<localleader>d", "<cmd>NBDeleteCell<cr>", desc = "NBDeleteCell" },
		{ "<localleader>y", "<cmd>NBCopyCell<cr>", desc = "NBCopyCell" },
		{ "<localleader>p", "<cmd>NBPasteCell<cr>", desc = "NBPasteCell" },
	})

	-- on save
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		pattern = "*.ipynb",
		callback = function(args)
			conform.format({ bufnr = args.buf })
			notebooks[args.file]:save_notebook()
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
