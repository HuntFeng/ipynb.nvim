local image = require("ipynb.image")

local _id = 0
local function uid()
	_id = _id + 1
	return _id
end

---@alias cell_data {cell_type: "code" | "markdown", source: string, outputs: table[], execution_count: integer | vim.NIL, }

---@class Cell
---@field cell_type "code" | "markdown"
---@field execution_count integer | vim.NIL
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
	cell.execution_count = cell_data["execution_count"]
	cell.metadata = cell_data["metadata"] or vim.empty_dict()
	cell.source = cell_data["source"] or ""
	cell.outputs = cell_data["outputs"] or {}
	return cell
end

function Cell:render_output(buf)
	if self.cell_type == "markdown" then
		return
	end

	local virt_lines = {
		{ { string.format("cell_id: %d, range: {%d, %d}", self.id, self.range[1], self.range[2]), "Comment" } },
		{ { string.format("Out[%s]:", self.execution_count ~= vim.NIL and self.execution_count or " "), "Normal" } },
	}
	local images = {}
	for _, output in ipairs(self.outputs) do
		if output.output_type == "execute_result" then
			for line in tostring(output.data["text/plain"]):gmatch("([^" .. "\n" .. "]+)") do
				table.insert(virt_lines, { { line, "Normal" } })
			end
		elseif output.output_type == "stream" then
			for line in tostring(output.text):gmatch("([^" .. "\n" .. "]+)") do
				table.insert(virt_lines, { { line, "Normal" } })
			end
		elseif output.output_type == "display_data" then
			local base64_str = output.data["image/png"]
			local dims = image.get_image_dimensions(base64_str)
			local image_path = image.save_temp_image(base64_str)
			local image_id = image.transmit_image(image_path, dims.width, dims.height)
			table.insert(images, { path = image_path, dims = dims, id = image_id })
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
