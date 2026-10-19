local Cell = require("ipynb.cell")
local ns_id = require("ipynb.image").ns_id
local config = require("ipynb.config")

---@class Notebook
---@field buf integer
---@field file string
---@field cells Cell[]
local Notebook = {}

---@param buf integer
---@param file string
---@return Notebook
function Notebook:new(buf, file)
	local notebook = {}
	setmetatable(notebook, self)
	self.__index = self
	notebook.cells = {}
	notebook.buf = buf
	notebook.file = file
	local results = vim.fn.LoadNotebook(file)
	local lines = results[1]
	local cell_datas = results[2]
	notebook:set_buffer_content(lines)
	notebook:prepare_cells(cell_datas)
	notebook:setup_on_changedtree_handler()
	return notebook
end

---@param id integer
function Notebook:delete_cell(id)
	for i, cell in ipairs(self.cells) do
		if cell.id == id then
			table.remove(self.cells, i)
		end
	end
end

---@param id integer
---@param fields {source?: string, range?: [integer, integer], outputs?: table[]}
function Notebook:update_cell(id, fields)
	for _, cell in ipairs(self.cells) do
		if cell.id == id then
			if fields.source then
				cell.source = fields.source
			end

			if fields.range then
				cell.range = fields.range
			end

			if fields.outputs then
				cell.outputs = fields.outputs
			end
		end
	end
end

---@param  lines string[]
function Notebook:set_buffer_content(lines)
	if not vim.api.nvim_buf_is_valid(self.buf) then
		return
	end

	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(self.buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(self.buf, "modified", false)
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
	for _, cell_data in ipairs(cell_datas) do
		local cell = Cell:new(cell_data)
		if cell.cell_type == "code" then
			cell.range = code_cell_ranges[i]
			cell:render_output(self.buf)
			i = i + 1
		end
		table.insert(self.cells, cell)
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
			self:delete_cell(extmark_id)
		end
	end
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
		local start_row, start_col, end_row, end_col = code_block_node:range()
		self:update_cell(cell_id, { range = { start_row, end_row } })
		for child in code_block_node:iter_children() do
			if child:type() == "code_fence_content" then
				local source = vim.treesitter.get_node_text(child, self.buf)
				self:update_cell(cell_id, { source = source })
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
	if self:has_incomplete_code_block() then
		return
	end

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
				end
				cell_data.source = cell_data.source .. "\n" .. vim.treesitter.get_node_text(node, self.buf)
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
			self:handle_removed_code_blocks()
			self:handle_added_code_blocks()
			self:update_code_cells()
			self:update_markdown_cells()
		end,
	})
end

function Notebook:save_notebook()
	vim.fn.SaveNotebook(self.file, self.cells, config.save_outputs)
	vim.api.nvim_buf_set_option(self.buf, "modified", false)
end

function Notebook:run_cell()
	local row = vim.fn.getcurpos()[2]
	for _, cell in ipairs(self.cells) do
		if cell.cell_type == "code" and row >= cell.range[1] and row < cell.range[2] then
			cell.execution_count = "*"
			cell.outputs = {}
			cell:render_output(self.buf)
			vim.fn.RunCell(self.file, cell.id, cell.source)
		end
	end
end

return Notebook
