local codes = require("ipynb.codes")
local term = require("ipynb.term")
local opts = require("ipynb.config").opts

local uv = vim.loop

local stdout = uv.new_tty(1, false)
if not stdout then
	error("failed to open stdout")
end

local ns_id = vim.api.nvim_create_namespace("ipynb")

---@param image_id integer
---@param width integer
---@param height integer
---@return table virt_lines
local function generate_unicode_placeholders(image_id, width, height)
	local virt_lines = {}
	local hl_group = "@ipynb-image-id-" .. tostring(image_id)
	vim.api.nvim_set_hl(0, hl_group, { fg = string.format("#%06X", image_id) })
	for i = 1, height do
		local characters = ""
		for j = 1, width do
			characters = characters .. codes.placeholder .. codes.diacritics[i] .. codes.diacritics[j]
		end
		table.insert(virt_lines, { { characters, hl_group } })
	end
	return virt_lines
end

local function kitty_send(params, payload)
	if not params.q then
		params.q = 2
	end

	local tbl = {}

	for k, v in pairs(params) do
		tbl[#tbl + 1] = tostring(k) .. "=" .. tostring(v)
	end

	params = table.concat(tbl, ",")

	local message
	if payload ~= nil then
		message = string.format("\x1b_G%s;%s\x1b\\", params, vim.base64.encode(payload))
	else
		message = string.format("\x1b_G%s\x1b\\", params)
	end
	stdout:write(message)
end

local _id = 1
local function next_id()
	local id = _id
	_id = _id + 1
	return id
end

---@param image_path string
---@param width integer
---@param height integer
---@return integer image_id
local function transmit_image(image_path, width, height)
	local image_id = next_id()
	kitty_send({ i = image_id, f = 100, t = "f" }, image_path)
	kitty_send({ i = image_id, U = 1, a = "p", r = height, c = width })
	return image_id
end

---@param base64_str string
local function save_temp_image(base64_str)
	local tmp_b64_path = vim.fn.tempname() .. ".png"
	local decoded = vim.base64.decode(base64_str)

	local file = io.open(tmp_b64_path, "wb")
	if file ~= nil then
		file:write(decoded)
		file:close()
	end

	return tmp_b64_path
end

---@param bytes string
---@param start_idx integer
---@param length integer
---@return integer
local function bytes_to_int_be(bytes, start_idx, length)
	local value = 0
	for i = 0, length - 1 do
		value = bit.lshift(value, 8) + string.byte(bytes, start_idx + i)
	end
	return value
end

---@param base64_str string
---@return { width: integer, height: integer } dims
local function get_image_dimensions(base64_str)
	local bytes = vim.base64.decode(base64_str)
	local pixel_width = bytes_to_int_be(bytes, 17, 4) -- Offset 16-19 for width
	local pixel_height = bytes_to_int_be(bytes, 21, 4) -- Offset 20-23 for height

	-- scale image
	local term_size = term.get_size()
	local scale_factor = opts.image_scale_factor
	local width = math.floor(pixel_width / term_size.cell_width * scale_factor)
	local height = math.floor(pixel_height / term_size.cell_height * scale_factor)
	return { width = width, height = height }
end

return {
	ns_id = ns_id,
	transmit_image = transmit_image,
	generate_unicode_placeholders = generate_unicode_placeholders,
	save_temp_image = save_temp_image,
	get_image_dimensions = get_image_dimensions,
}
