local image = require("ipynb.image")

local _id = 0
local function uid()
	_id = _id + 1
	return _id
end

---@alias cell_data {cell_type: "code" | "markdown", source: string, outputs: table[], execution_count: integer | vim.NIL, }

---@class Cell
---@field cell_type "code" | "markdown"
---@field execution_count string
---@field source string
---@field outputs table
---@field metadata table
---@field id integer
---@field range [integer, integer]
local Cell = {}

---@param cell_data cell_data
---@return Cell
function Cell:new(cell_data)
	local cell = {}
	setmetatable(cell, self)
	self.__index = self
	cell.id = uid()
	cell.range = cell_data["range"] or { -1, -1 }
	cell.cell_type = cell_data["cell_type"]
	cell.execution_count = cell_data["execution_count"] ~= vim.NIL and cell_data["execution_count"] or " "
	cell.metadata = cell_data["metadata"] or vim.empty_dict()
	cell.source = cell_data["source"] or ""
	cell.outputs = cell_data["outputs"] or {}
	return cell
end

local ansi_to_hl = {
	["0;31"] = "ErrorMsg", -- Red
	["0;32"] = "Character", -- Green
	["43"] = "CurSearch", -- Yellow background
	["49"] = "Normal", -- Default background
	["0"] = "Normal", -- Reset
}

local esc_pattern = "\x1b%[([0-9;]*)m"

local function process_line(line)
	local virtual_line = {}
	local last_end = 1
	local current_hl = "Normal" -- Default highlight group

	-- Iterate through all escape sequences in the line
	for start, codes, finish in line:gmatch("()" .. esc_pattern .. "()") do
		-- Append the text before the escape code with the current highlight
		if last_end < start then
			table.insert(virtual_line, {
				line:sub(last_end, start - 1),
				current_hl,
			})
		end

		-- Update the current highlight group
		current_hl = ansi_to_hl[codes] or "Normal"
		last_end = finish
	end

	-- Append remaining text after the last escape code
	if last_end <= #line then
		table.insert(virtual_line, {
			line:sub(last_end),
			current_hl,
		})
	end

	return virtual_line
end

function Cell:render_output(buf)
	if self.cell_type == "markdown" then
		return
	end

	local hl_group = "Special"

	local virt_lines = {
		{ { string.format("cell_id: %d, range: {%d, %d}", self.id, self.range[1], self.range[2]), "Comment" } },
		{ { string.format("Out[%s]:", self.execution_count), hl_group } },
	}
	local images = {}
	for _, output in ipairs(self.outputs) do
		if output.output_type == "execute_result" then
			for line in tostring(output.data["text/plain"]):gmatch("([^" .. "\n" .. "]+)") do
				table.insert(virt_lines, { { line, hl_group } })
			end
		elseif output.output_type == "stream" then
			if #virt_lines == 2 then
				table.insert(virt_lines, { { "", hl_group } })
			end
			local line = virt_lines[#virt_lines][1][1]
			for char in tostring(output.text):gmatch(".") do
				if char == "\n" then
					line = ""
					table.insert(virt_lines, { { line, hl_group } })
				elseif char == "\r" then
					line = ""
					virt_lines[#virt_lines] = { { line, hl_group } }
				else
					line = line .. char
					virt_lines[#virt_lines] = { { line, hl_group } }
				end
			end
		elseif output.output_type == "display_data" then
			local base64_str = output.data["image/png"]
			local dims = image.get_image_dimensions(base64_str)
			local image_path = image.save_temp_image(base64_str)
			local image_id = image.transmit_image(image_path, dims.width, dims.height)
			table.insert(images, { path = image_path, dims = dims, id = image_id })
		elseif output.output_type == "error" then
			for _, raw_line in ipairs(output.traceback) do
				for line in tostring(raw_line):gmatch("([^" .. "\n" .. "]+)") do
					table.insert(virt_lines, process_line(line))
				end
			end
		end
	end

	for _, img in ipairs(images) do
		local placeholders = image.generate_unicode_placeholders(img.id, img.dims.width, img.dims.height)
		for _, line in ipairs(placeholders) do
			table.insert(virt_lines, line)
		end
		table.insert(virt_lines, { { " ", "" } }) -- one empty line for padding
	end

	vim.api.nvim_buf_set_extmark(buf, image.ns_id, self.range[2] - 1, 0, {
		id = self.id,
		virt_lines = virt_lines,
		virt_lines_above = false,
	})
end

return Cell
