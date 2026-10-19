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
		{ { string.format("[%s]:", self.execution_count), hl_group } },
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

---@param image_path string
local function copy_image_to_clipboard(image_path)
	local os_name = vim.loop.os_uname().sysname
	local clipboard_command

	if os_name == "Windows_NT" then
		-- Use win32clipboard for Windows
		clipboard_command = string.format(
			[[powershell -Command "$image = [System.Drawing.Image]::FromFile('%s'); $data = [System.Windows.Forms.Clipboard]::SetImage($image)"]],
			image_path
		)
	elseif os_name == "Darwin" then
		-- Use AppleScript or pbcopy for macOS
		clipboard_command =
			string.format("osascript -e 'set the clipboard to (read (POSIX file \"%s\") as JPEG picture)'", image_path)
	elseif os_name == "Linux" then
		-- Use xclip for Linux
		clipboard_command = string.format("xclip -selection clipboard -t image/png -i '%s'", image_path)
	else
		vim.notify("Unsupported operating system")
		return
	end

	-- Execute the clipboard command
	local success = os.execute(clipboard_command)
	if success then
		vim.notify("Image copied to clipboard!")
	else
		vim.notify("Failed to copy image to clipboard.")
	end
end

---@param buf integer
local function prepare_output_buffer(outputs, buf)
	local lines = {}

	local images = {}
	for _, output in ipairs(outputs) do
		if output.output_type == "execute_result" then
			for line in tostring(output.data["text/plain"]):gmatch("([^" .. "\n" .. "]+)") do
				table.insert(lines, line)
			end
		elseif output.output_type == "stream" then
			if #lines == 0 then
				table.insert(lines, "")
			end
			local line = lines[#lines][1][1]
			for char in tostring(output.text):gmatch(".") do
				if char == "\n" then
					line = ""
					table.insert(lines, line)
				elseif char == "\r" then
					line = ""
					lines[#lines] = line
				else
					line = line .. char
					lines[#lines] = line
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
					table.insert(lines, line)
				end
			end
		end
	end

	vim.cmd([[
  syntax region ConcealInnerText start=/\[\[/ end=/\]\]/ contains=InnerText
  syntax match InnerText /\%(\[\[Image \d\+\)\@<=\zs.\{-}\ze\]\]/ conceal
  setlocal conceallevel=2
  setlocal concealcursor=n
	]])

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local row = #lines
	for i, img in ipairs(images) do
		local placeholders = image.generate_unicode_placeholders(img.id, img.dims.width, img.dims.height)
		vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { string.format("[[Image %d@%s]]", i, img.path) })
		vim.api.nvim_buf_set_extmark(buf, image.ns_id, row, 0, {
			virt_text = { { "◀ Yank this line to copy image", "DiagnosticVirtualTextInfo" } },
		})
		vim.api.nvim_buf_set_extmark(buf, image.ns_id, row, 0, { virt_lines = placeholders, virt_lines_above = false })
		row = row + 1
	end

	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

---Enter output window for copying
function Cell:enter_output_window()
	if self.cell_type == "markdown" then
		return
	end

	-- create a floating window
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
		title = string.format("[%s]", self.execution_count),
	})

	prepare_output_buffer(self.outputs, buf)

	-- yank handler
	vim.api.nvim_create_autocmd("TextYankPost", {
		buffer = buf,
		callback = function(args)
			local yanked_content = vim.fn.getreg("+"):gsub("^%s+", ""):gsub("%s+$", "")
			local img_path = yanked_content:match("^%[%[Image %d+@(.*)%]%]$")
			if img_path then
				copy_image_to_clipboard(img_path)
			end
		end,
	})
end

return Cell
