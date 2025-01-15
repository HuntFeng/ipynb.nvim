local commands = {}

---Hook commands to notebook class
---@param notebook Notebook
function commands.init(notebook)
	vim.api.nvim_buf_create_user_command(notebook.buf, "NBRunCell", function()
		commands.run_cell(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBEnterCellOutput", function()
		commands.enter_cell_output(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBNextCell", function()
		commands.goto_next_cell(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBPrevCell", function()
		commands.goto_prev_cell(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBAddCellAbove", function()
		commands.add_cell_above(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBAddCellBelow", function()
		commands.add_cell_below(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBRunAndAddCellBelow", function()
		commands.run_and_add_cell_below(notebook)
	end, {})
end

---@param notebook Notebook
function commands.run_cell(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for _, cell in ipairs(notebook.cells) do
		if cell.cell_type == "code" and row >= cell.range[1] and row < cell.range[2] then
			cell.execution_count = "*"
			cell.outputs = {}
			cell:render_output(notebook.buf)
			vim.fn.RunCell(notebook.file, cell.id, cell.source)
		end
	end
end

---@param notebook Notebook
function commands.enter_cell_output(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for _, cell in ipairs(notebook.cells) do
		if cell.cell_type == "code" and row >= cell.range[1] and row < cell.range[2] then
			cell:enter_output_window()
		end
	end
end

---@param notebook Notebook
function commands.goto_next_cell(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for i, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] and #notebook.cells > i then
			vim.api.nvim_win_set_cursor(0, { notebook.cells[i + 1].range[1] + 1, 0 })
		end
	end
end

---@param notebook Notebook
function commands.goto_prev_cell(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for i, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] and i > 1 then
			vim.api.nvim_win_set_cursor(0, { notebook.cells[i - 1].range[1] + 1, 0 })
		end
	end
end

---@param notebook Notebook
function commands.add_cell_above(notebook)
	local row = vim.fn.getcurpos()[2] - 1 -- row is 0-based
	for _, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] then
			-- set_line index is 0-based
			vim.api.nvim_buf_set_lines(notebook.buf, cell.range[1], cell.range[1], true, { "```python", "```" })
			-- set_cursor index is 1-based
			vim.api.nvim_win_set_cursor(0, { cell.range[1] + 1, 0 }) -- set cursor is 1-based
		end
	end
end

---@param notebook Notebook
function commands.add_cell_below(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for _, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] then
			vim.api.nvim_buf_set_lines(notebook.buf, cell.range[2], cell.range[2], true, { "```python", "```" })
			vim.api.nvim_win_set_cursor(0, { cell.range[2] + 1, 0 })
		end
	end
end

---@param notebook Notebook
function commands.run_and_add_cell_below(notebook)
	commands.run_cell(notebook)
	commands.add_cell_below(notebook)
end

return commands
