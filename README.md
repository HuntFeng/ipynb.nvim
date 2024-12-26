# ipynb.nvim

The combination of jupytext.nvim and molten-nvim has the following issues
1. can't render outputs into the converted python file automatically (MoltenImportOutput)
2. can't save outputs to the corresponding .ipynb file automatically (MoltenExportOutput)
3. does not offer good way to copy cell outputs (MoltenEnterOutput)
4. does not offer kernel selection (vim.fn.MoltenAvailableKernels())
5. does not define cells automatically (vim.fn.MoltenDefineCell(5, 10, 'python3'))
6. can't displays images properly, molten-nvim puts the image to a weird position and the image does not bind to window & buffer
7. hard to configure many plugins and their dependencies


python:
keeps notebook data
- handles jupyter kernel communication
- handles jupytext loading and saving

lua:
keeps cell frontend data
- handles buffer content

nvim:
users modify buffer -> triggers on_changedtree in nvim-treesitter
1-> modify cell frontend data in lua
2-> modify notebook data in python

* any control over the cell will change the buffer first, then the on_changedtree handles the rest

fixme:
- [ ] cannot run code for newly added cell
- [ ] cannot queue a cell for running, must wait until one finishes
- [ ] cannot delete cells properly when executing code

todo:
- [x] loading
    - [x] auto convert using jupytext
    - [x] render outputs
    - [x] add outputs to the buffer as virtual text
    - [x] dealing with empty notebook (create new notebook)
- [x] saving
    - [x] get cells
    - [x] get outputs 
        - enrich the Cell class in lua, we can store all data in lua instead of python
        - when saving, pass the cells in lua to python to use jupytext to save
    - [x] option to save code and outputs separately
- [x] jupyter kernel communication (use molten-nvim to do this, except saving)
    - [x] run kernel in the background
    - [x] send code to kernel
        - [x] need to clear old outputs after executing code
    - [x] receive outputs from kernel
        - [x] append newly recieved outputs to the cell outputs
- [ ] shortcuts
    - [ ] add cell below
    - [ ] add cell above
    - [ ] delete cell
    - [ ] cut cell
    - [ ] copy cell
    - [ ] paste cell
    - [ ] change cell type
    - [x] run cell
    - [ ] run cell and add cell below
    - [x] start kernel
    - [ ] stop kernel
    - [ ] interupt kernel
    - [ ] restart kernel
- [ ] optimize performance of cell parsing using changed range and changed subtree
