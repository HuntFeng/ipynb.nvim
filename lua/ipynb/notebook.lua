local Cell = require("ipynb.cell")
local ns_id = require("ipynb.image").ns_id
local opts = require("ipynb.config").opts
local commands = require("ipynb.commands")

---@class Notebook
---@field buf integer
---@field file string
---@field cells Cell[]
---@field copied_cell Cell | nil
---@field is_kernel_started boolean
---@field id2idx table
local Notebook = {}

---@param buf integer
---@param file string
---@return Notebook
function Notebook:new(buf, file)
	local notebook = {}
	setmetatable(notebook, self)
	self.__index = self
	notebook.cells = {}
	notebook.copied_cell = nil
	notebook.buf = buf
	notebook.file = file
	notebook.is_kernel_started = false
	notebook.id2idx = {}
	local results = vim.fn.LoadNotebook(file)
	local lines = results[1]
	local cell_datas = results[2]
	notebook:set_buffer_content(lines)
	notebook:prepare_cells(cell_datas)
	notebook:setup_on_changedtree_handler()

	commands.init(notebook)
	return notebook
end

---@param  lines string[]
function Notebook:set_buffer_content(lines)
	if not vim.api.nvim_buf_is_valid(self.buf) then
		return
	end

	table.insert(lines, 1, "") -- add empty line for undo
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(self.buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(self.buf, "modified", false)
	-- In order to make :undo a no-op immediately after the buffer is read, we
	-- need to do this dance with 'undolevels'.  Actually discarding the undo
	-- history requires performing a change after setting 'undolevels' to -1 and,
	-- luckily, we have one we need to do (delete the extra line from the :r
	-- command)
	-- (Comment straight from goerz/jupytext.vim)
	local levels = vim.o.undolevels
	vim.opt_local.undolevels = -1
	vim.api.nvim_command("silent 1delete")
	vim.opt_local.undolevels = levels
end

---@param cell_datas cell_data[]
function Notebook:prepare_cells(cell_datas)
	if not vim.api.nvim_buf_is_valid(self.buf) then
		return
	end

	local parser = vim.treesitter.get_parser(self.buf, "markdown", {})
	local tree = parser:parse()[1]

	local query = vim.treesitter.query.parse(
		"markdown",
		[[
	       (fenced_code_block) @code_block
	   ]]
	)

	---@type Cell[]
	local code_cell_ranges = {}
	for _, match, _ in query:iter_matches(tree:root(), self.buf) do
		for _, node in pairs(match) do
			local start_row, _, end_row, _ = vim.treesitter.get_node_range(node)
			table.insert(code_cell_ranges, { start_row, end_row })
		end
	end

	local i = 1
	for idx, cell_data in ipairs(cell_datas) do
		local cell = Cell:new(cell_data)
		if cell.cell_type == "code" then
			cell.range = code_cell_ranges[i]
			cell:render_output(self.buf)
			i = i + 1
		elseif cell.cell_type == "markdown" then
			local start_row = 0
			local end_row = #vim.api.nvim_buf_get_lines(self.buf, 0, -1, true)
			if i > 1 then
				start_row = code_cell_ranges[i - 1][2]
			end
			if i <= #code_cell_ranges then
				end_row = code_cell_ranges[i][1]
			end
			cell.range = { start_row, end_row }
		end
		table.insert(self.cells, cell)
		self.id2idx[cell.id] = idx
	end
end

function Notebook:handle_removed_code_blocks()
	--TODO we can improve the range of extmarks here
	local extmarks = vim.api.nvim_buf_get_extmarks(self.buf, ns_id, 0, -1, {})
	for _, extmark in ipairs(extmarks) do
		local extmark_id = extmark[1]
		local row = extmark[2]
		local line = vim.api.nvim_buf_get_lines(self.buf, row, row + 1, false)[1]
		if not (line and line:match("^```")) then
			vim.api.nvim_buf_del_extmark(self.buf, ns_id, extmark_id)
			table.remove(self.cells, self.id2idx[extmark_id])
		end
	end

	for i = 1, #self.cells do
		self.id2idx[self.cells[i].id] = i
	end

	-- sometimes neovim does not redraw after large extmarks deleted
	vim.cmd("redraw!")
end

function Notebook:handle_added_code_blocks()
	local parser = vim.treesitter.get_parser(self.buf, "markdown")
	local tree = parser:parse()[1]
	local query = vim.treesitter.query.parse(
		"markdown",
		[[
        (fenced_code_block
          (info_string
            (language))) @code_block
    ]]
	)

	for _, node in query:iter_captures(tree:root(), self.buf, 0, -1) do
		local start_row, _, end_row, _ = node:range()
		local extmarks = vim.api.nvim_buf_get_extmarks(self.buf, ns_id, { end_row - 1, 0 }, { end_row, 0 }, {})
		if #extmarks == 0 then
			local cell = Cell:new({ cell_type = "code", source = "", range = { start_row, end_row } })
			cell:render_output(self.buf)
			extmarks = vim.api.nvim_buf_get_extmarks(self.buf, ns_id, { 0, 0 }, { end_row, 0 }, {})
			table.insert(self.cells, #extmarks, cell)
		end
	end

	for i = 1, #self.cells do
		self.id2idx[self.cells[i].id] = i
	end
end

function Notebook:update_code_cells()
	local extmarks = vim.api.nvim_buf_get_extmarks(self.buf, ns_id, 0, -1, {})
	for _, extmark in ipairs(extmarks) do
		local cell_id = extmark[1]
		local row = extmark[2]
		local delimiter_node = vim.treesitter.get_node({ pos = { row, 0 } })
		if delimiter_node == nil then
			goto continue
		end
		local code_block_node = delimiter_node:parent()
		if code_block_node == nil then
			goto continue
		end
		local start_row, _, end_row, _ = code_block_node:range()
		self.cells[self.id2idx[cell_id]].range = { start_row, end_row }
		for child in code_block_node:iter_children() do
			if child:type() == "code_fence_content" then
				local source = vim.treesitter.get_node_text(child, self.buf)
				self.cells[self.id2idx[cell_id]].source = source
			end
		end

		::continue::
	end

	for _, cell in ipairs(self.cells) do
		cell:render_output(self.buf)
	end
end

---check if the code block is complete, or user still creating it
---@return boolean
function Notebook:has_incomplete_code_block()
	local parser = vim.treesitter.get_parser(self.buf, "markdown")
	local tree = parser:parse()[1]
	local query = vim.treesitter.query.parse(
		"markdown",
		[[
        (fenced_code_block
          (info_string
            (language))? @lang) @code_block
    ]]
	)

	for _, match, _ in query:iter_matches(tree:root(), self.buf, 0, -1, { all = true }) do
		local incomplete = true
		for id, _ in pairs(match) do
			if query.captures[id] == "lang" then
				incomplete = false
			end
		end

		if incomplete then
			return true
		end
	end

	return false
end

function Notebook:update_markdown_cells()
	local parser = vim.treesitter.get_parser(self.buf, "markdown")
	local tree = parser:parse()[1]

	---@type Cell[]
	local cells = {}
	for _, cell in ipairs(self.cells) do
		if cell.cell_type == "code" then
			table.insert(cells, cell)
		end
	end
	self.cells = {}

	local query_section = vim.treesitter.query.parse(
		"markdown",
		[[
        (section) @section
    ]]
	)

	for _, section in query_section:iter_captures(tree:root(), self.buf, 0, -1) do
		local cell_data = nil
		local position = 1
		for node in section:iter_children() do
			if node:type() ~= "fenced_code_block" then
				-- part of the markdown code cell
				if not cell_data then
					cell_data = { cell_type = "markdown" }
					cell_data.source = vim.treesitter.get_node_text(node, self.buf)
					local start_row, _, end_row, _ = vim.treesitter.get_node_range(node)
					cell_data.range = { start_row, end_row }
				else
					cell_data.source = cell_data.source .. "\n" .. vim.treesitter.get_node_text(node, self.buf)
					local _, _, end_row, _ = vim.treesitter.get_node_range(node)
					cell_data.range[2] = end_row
				end
			else
				-- here we put the accumulated markdown cell into notebook
				if cell_data then
					local cell = Cell:new(cell_data)
					table.insert(cells, position, cell)
					cell_data = nil
				end
				position = position + 1
			end
		end

		-- insert the last accumulated markdown cell into notebook
		if cell_data then
			local cell = Cell:new(cell_data)
			table.insert(cells, position, cell)
		end

		self.cells = cells
		for i = 1, #self.cells do
			self.id2idx[self.cells[i].id] = i
		end
	end
end

function Notebook:setup_on_changedtree_handler()
	vim.api.nvim_buf_attach(self.buf, false, {
		--- @param _ string
		--- @param _ integer
		--- @param changedtick integer number of edits
		--- @param start_row integer edit range start (0-based index)
		--- @param end_row integer  edit range end (exclusive)
		--- @param new_end_row integer after editing, end_row is now at new_end_row
		on_lines = function(_, _, changedtick, start_row, end_row, new_end_row)
			vim.schedule(function()
				self:handle_removed_code_blocks()
				self:handle_added_code_blocks()
				self:update_code_cells()
				self:update_markdown_cells()
			end)
		end,
	})
end

function Notebook:save_notebook()
	vim.fn.SaveNotebook(self.file, self.cells, opts.save_outputs)
	vim.api.nvim_buf_set_option(self.buf, "modified", false)
end

return Notebook
