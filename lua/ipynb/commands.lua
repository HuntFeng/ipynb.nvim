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

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBDeleteCell", function()
		commands.delete_cell(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBCopyCell", function()
		commands.copy_cell(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBPasteCell", function()
		commands.paste_cell(notebook)
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
			break
		end
	end
end

---@param notebook Notebook
function commands.enter_cell_output(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for _, cell in ipairs(notebook.cells) do
		if cell.cell_type == "code" and row >= cell.range[1] and row < cell.range[2] then
			cell:enter_output_window()
			break
		end
	end
end

---@param notebook Notebook
function commands.goto_next_cell(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for i, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] and #notebook.cells > i then
			vim.api.nvim_win_set_cursor(0, { notebook.cells[i + 1].range[1] + 1, 0 })
			break
		end
	end
end

---@param notebook Notebook
function commands.goto_prev_cell(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for i, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] and i > 1 then
			vim.api.nvim_win_set_cursor(0, { notebook.cells[i - 1].range[1] + 1, 0 })
			break
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
			break
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
			break
		end
	end
end

---@param notebook Notebook
function commands.run_and_add_cell_below(notebook)
	commands.run_cell(notebook)
	commands.add_cell_below(notebook)
end

---Delete / Cut  cell
---@param notebook Notebook
function commands.delete_cell(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for _, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] then
			notebook.copied_cell = cell
			vim.api.nvim_buf_set_lines(notebook.buf, cell.range[1], cell.range[2], true, {})
			break
		end
	end
end

---Copy cell with its output
---@param notebook Notebook
function commands.copy_cell(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	for _, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] then
			notebook.copied_cell = cell
			break
		end
	end
end

---Paste cell with its output below the current cell
---@param notebook Notebook
function commands.paste_cell(notebook)
	local paste_cell = notebook.copied_cell
	if not paste_cell then
		return
	end

	local row = vim.fn.getcurpos()[2] - 1
	for _, cell in ipairs(notebook.cells) do
		if row >= cell.range[1] and row < cell.range[2] then
			local lines = { "```python" }
			for line in paste_cell.source:gmatch("[^\n\r]+") do
				table.insert(lines, line)
			end
			lines[#lines + 1] = "```"
			vim.api.nvim_buf_set_lines(notebook.buf, cell.range[2], cell.range[2], true, lines)
			vim.api.nvim_win_set_cursor(0, { cell.range[2] + 1, 0 })
			break
		end
	end

	if paste_cell.cell_type == "code" then
		vim.schedule(function()
			-- notebook.cells have been updated
			-- cursor position has been updated
			row = vim.fn.getcurpos()[2] - 1
			for _, cell in ipairs(notebook.cells) do
				if row >= cell.range[1] and row < cell.range[2] then
					cell.outputs = paste_cell.outputs
					cell:render_output(notebook.buf)
				end
			end
		end)
	end
end
return commands
