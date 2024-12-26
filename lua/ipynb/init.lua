local config = require("ipynb.config")
local Notebook = require("ipynb.notebook")

---@type Notebook[]
local notebooks = {}

local function setup(opts)
	config.setup(opts or {})

	-- on load
	vim.api.nvim_create_autocmd("BufReadCmd", {
		pattern = "*.ipynb",
		callback = function(args)
			notebooks[args.file] = Notebook:new(args.buf, args.file)

			vim.api.nvim_buf_create_user_command(args.buf, "NBInit", function()
				vim.fn.InitKernel(args.file)
			end, {})

			vim.api.nvim_buf_create_user_command(args.buf, "NBRunCell", function()
				notebooks[args.file]:run_cell()
			end, {})
		end,
	})

	local wk = require("which-key")
	wk.add({
		{ "<leader>rr", "<cmd>NBRunCell<cr>", desc = "NBRunCell" },
	})

	-- on save
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		pattern = "*.ipynb",
		callback = function(args)
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
	for _, cell in ipairs(notebook.cells) do
		if cell.id == cell_id then
			if output["output_type"] == "status" then
				if output["execution_state"] == "busy" then
					-- clear cell outputs
					cell.outputs = {}
				end
			elseif output["output_type"] == "execute_input" then
				cell.execution_count = output["execution_count"] and tonumber(output["execution_count"]) or vim.NIL
			else
				table.insert(cell.outputs, output)
			end
			cell:render_output(notebook.buf)
		end
	end
end

return {
	setup = setup,
	update_cell_outputs = update_cell_outputs,
}
