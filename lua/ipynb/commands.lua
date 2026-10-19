local commands = {}

---Hook commands to notebook class
---@param notebook Notebook
function commands.init(notebook)
	vim.api.nvim_buf_create_user_command(notebook.buf, "NBStartKernel", function()
		commands.start_kernel(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBInterruptKernel", function()
		vim.fn.InterruptKernel(notebook.file)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBShutdownKernel", function()
		vim.fn.ShutdownKernel(notebook.file)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBRestartKernel", function()
		vim.fn.RestartKernel(notebook.file)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBGetKernelSpec", function()
		commands.get_kernel_spec(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBRunCell", function()
		commands.run_cell(notebook)
	end, {})

	vim.api.nvim_buf_create_user_command(notebook.buf, "NBRunAllCell", function()
		commands.run_all_cell(notebook)
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
function commands.start_kernel(notebook)
	---@type table
	local kernels = vim.fn.ListKernels()
	if next(kernels) == nil then
		vim.notify("Jupyter kernels not found")
		return
	end

	local display_list = {}
	local kernel_keys = {}
	for key, value in pairs(kernels) do
		table.insert(display_list, value.spec.display_name)
		table.insert(kernel_keys, key)
	end

	if #kernel_keys == 1 then
		vim.fn.StartKernel(notebook.file, kernel_keys[1])
	else
		vim.ui.select(display_list, {
			prompt = "Select Jupyter Kernel:",
			format_item = function(item)
				return item
			end,
		}, function(choice)
			if choice then
				-- Find the corresponding kernel key
				for key, kernel in pairs(kernels) do
					if kernel.spec.display_name == choice then
						vim.fn.StartKernel(notebook.file, key)
						break
					end
				end
			end
		end)
	end

	notebook.is_kernel_started = true
end

---@param notebook Notebook
function commands.get_kernel_spec(notebook)
	local buf = vim.api.nvim_create_buf(false, true)
	local win_width = vim.api.nvim_win_get_width(0)
	local win_height = vim.api.nvim_win_get_height(0)
	local width = math.floor(win_width * 0.80)
	local height = math.floor(win_height * 0.80)
	vim.api.nvim_open_win(buf, true, {
		relative = "win",
		width = width,
		height = height,
		row = math.floor((win_height - height) / 2),
		col = math.floor((win_width - width) / 2),
		style = "minimal",
		border = "single",
		title = "Kernel Info",
	})

	---@param tbl table
	---@param indent integer
	local function table_to_lines(tbl, indent)
		-- Convert a Lua table to an array of lines with indentation for readability
		indent = indent or 0
		local lines = {}
		local padding = string.rep("  ", indent)

		for key, value in pairs(tbl) do
			local formatted_key = tostring(key)
			if type(value) == "table" then
				table.insert(lines, padding .. formatted_key .. ":")
				local child_lines = table_to_lines(value, indent + 1)
				for _, line in ipairs(child_lines) do
					table.insert(lines, line)
				end
			else
				local formatted_value = tostring(value)
				table.insert(lines, padding .. formatted_key .. ": " .. formatted_value)
			end
		end

		return lines
	end

	local kernel_spec = vim.fn.GetKernelSpec(notebook.file)
	local lines = {}
	if kernel_spec == vim.NIL then
		table.insert(lines, "No Kernel Activated")
	else
		lines = table_to_lines(kernel_spec, 4)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

---@param notebook Notebook
function commands.run_cell(notebook)
	if not notebook.is_kernel_started then
		commands.start_kernel(notebook)
	end

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
function commands.run_all_cell(notebook)
	if not notebook.is_kernel_started then
		commands.start_kernel(notebook)
	end

	for _, cell in ipairs(notebook.cells) do
		cell.execution_count = "*"
		cell.outputs = {}
		cell:render_output(notebook.buf)
		vim.fn.RunCell(notebook.file, cell.id, cell.source)
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
	-- the cells are already sorted, we can do this
	for i = 1, #notebook.cells do
		local cell = notebook.cells[i]
		if row < cell.range[1] then
			vim.api.nvim_win_set_cursor(0, { cell.range[1] + 1, 0 })
			break
		end
	end
end

---@param notebook Notebook
function commands.goto_prev_cell(notebook)
	local row = vim.fn.getcurpos()[2] - 1
	-- the cells are already sorted, we can do this
	for i = #notebook.cells, 1, -1 do
		local cell = notebook.cells[i]
		if row > cell.range[1] then
			vim.api.nvim_win_set_cursor(0, { cell.range[1] + 1, 0 })
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

---Delete / Cut cell
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
