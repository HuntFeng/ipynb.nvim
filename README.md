# ipynb.nvim

All-in-one solution for jupyter notebook support in neovim in Kitty terminal.

## Python dependencies
```bash
pip install pynvim
```

## Install via Lazy
```lua
{
	"HuntFeng/ipynb.nvim",
	config = function()
		require("ipynb").setup()
	end,
}
```

## Default configs
```lua
{
	image_scale_factor = 1.0,
	save_outputs = false,
}
```
