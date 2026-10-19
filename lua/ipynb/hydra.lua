local Hydra = require("hydra")

-- Define the cell navigation Hydra
local cell_mode = Hydra({
	name = "Cell Mode",
	mode = "n", -- Normal mode
	body = "<Esc>", -- Keybinding to enter cell mode (can be any key combo)
	config = {
		invoke_on_body = true,
	},
	heads = {
		-- { "<Esc>", nil, { exit = true, desc = "Exit Cell Mode" } },
		{
			"j",
			function()
				vim.cmd("NBNextCell")
			end,
			{ desc = "Next Cell" },
		},
		{
			"k",
			function()
				vim.cmd("NBPrevCell")
			end,
			{ desc = "Previous Cell" },
		},
		{
			"a",
			function()
				vim.cmd("NBAddCellAbove")
			end,
			{ desc = "Add Cell Above" },
		},
		{
			"b",
			function()
				vim.cmd("NBAddCellBelow")
			end,
			{ desc = "Add Cell Below" },
		},
		{
			"r",
			function()
				vim.cmd("NBRunCell")
			end,
			{ desc = "Run Cell" },
		},
		{
			"R",
			function()
				vim.cmd("NBRunCell")
				vim.cmd("NBNextCell")
			end,
			{ desc = "Run Cell And Goto Next Cell" },
		},
		{
			"d",
			function()
				vim.cmd("NBDeleteCell")
			end,
			{ desc = "Delete / Cut Cell" },
		},
		{
			"y",
			function()
				vim.cmd("NBCopyCell")
			end,
			{ desc = "Copy Cell" },
		},
		{
			"p",
			function()
				vim.cmd("NBPasteCell")
			end,
			{ desc = "Paste Cell" },
		},
		{
			"o",
			function()
				vim.cmd("NBEnterCellOutput")
			end,
			{ desc = "Enter Cell Output" },
		},
	},
})

return cell_mode
