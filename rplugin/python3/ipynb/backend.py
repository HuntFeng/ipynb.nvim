import os
from typing import Dict, List, Tuple

from jupytext import jupytext, config
from .kernel import Kernel
import pynvim
import threading

# remove all metadata from the text representation of the notebook.
# minus sign - means remove
configuration = config.JupytextConfiguration(notebook_metadata_filter="-all")


@pynvim.plugin
class Backend:
    kernels: Dict[str, Kernel]
    notebooks: Dict[str, jupytext.NotebookNode]

    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self.nvim.exec_lua("_ipynb = require('ipynb')")
        self.notebooks = dict()
        self.kernels = dict()

    # name should be PascalCase otherwise pynvim won't recognize
    # https://github.com/neovim/pynvim/issues/334
    # the arguments pass to pynvim.function will be a tuple/list in python
    @pynvim.function("LoadNotebook", sync=True)
    def load_notebook(
        self, args: Tuple[str]
    ) -> Tuple[List[str], List[jupytext.NotebookNode]]:
        """
        Load .ipynb notebook into buffer and memory
        Input:
            args[0]: notebook_path
        Output:
            lines: lines of the markdown representation of the notebook
            cells: cell datas of the loaded notebook
        """
        notebook_path = args[0]
        try:
            notebook = jupytext.read(notebook_path)
            lines = jupytext.writes(notebook, fmt="md", config=configuration).split(
                "\n"
            )
        except Exception:
            notebook = jupytext.new_notebook()
            lines = [""]

        self.notebooks[notebook_path] = notebook
        return lines, notebook.cells

    @pynvim.function("SaveNotebook")
    def save_notebook(self, args: Tuple[str, List[Dict], bool]) -> None:
        """
        Save notebook date to .ipynb file.

        Input:
            args[0]: notebook_path
            args[1]: cell_datas
            args[2]: save_outputs
        """
        notebook_path = args[0]
        cell_datas = args[1]
        save_outputs = args[2]

        dirname = os.path.dirname(notebook_path)
        basename = os.path.basename(notebook_path)

        self.notebooks[notebook_path].cells = [
            jupytext.nbformat.from_dict(cell_data) for cell_data in cell_datas
        ]

        if not save_outputs:
            for cell in self.notebooks[notebook_path].cells:
                cell.outputs.clear()
                cell.execution_count = None

        jupytext.write(
            self.notebooks[notebook_path], os.path.join(dirname, "saved" + basename)
        )
        # jupytext.write(self.notebooks[notebook_path], notebook_path)

    @pynvim.function("InitKernel")
    def init_kernel(self, args: Tuple[str]):
        """
        Initializing jupyter kernel for a specific notebook.

        Input:
            args[0]: notebook_path
        """
        notebook_path = args[0]
        self.nvim.out_write(f"Initializing kernel for {notebook_path}\n")
        self.kernels[notebook_path] = Kernel()

    @pynvim.function("ExecuteCell")
    def execute_cell(self, args: Tuple[str, int, str]):
        """
        Execute a cell in a .ipynb file

        Input:
            args[0]: notebook_path
            args[1]: cell_id
            args[2]: code
        """

        notebook_path = args[0]
        cell_id = args[1]
        code = args[2]
        # get kernel from the list, if kernel doesn't exist then initialize it
        self.kernels[notebook_path] = self.kernels.get(notebook_path, Kernel())
        try:
            msg_id = self.kernels[notebook_path].execute(code)
            threading.Thread(
                target=self.update_cells, args=(notebook_path, cell_id, msg_id)
            ).start()
        except Exception as e:
            self.nvim.out_write(f"{repr(e)}\n")

    def update_cells(self, notebook_path: str, cell_id: int, msg_id: str):
        """
        Get jupyter kernel reponse and update cells in neovim.


        Here are the return of different message type

        status
        msg["content"] = {
            "execution_state": "busy" | "idle"
        }

        execute_input
        msg["content"] = {
            "code": "...",
            "execution_count": 1
        }

        stream
        msg["content"] = {
            "name": "stdout" (normal text) | "stderr" (warnings),
            "text": "..."
        }

        execute_result
        msg["content"] = {
            "data": {
                "text/plain": "2"
            }
        }


        display_data
        msg["content"] = {
            "data": {
                "text/plain": "<Figure size 640x480 with 1 Axes>",
                "image/png": "base64 string",
            }
        }

        error
        msg["content"] = {
            "traceback": ["escape code colored error message"],
            "ename": "ErrorType",
            "evalue": "some other message we don't use",
        }
        """

        # self.nvim.out_write("in update_cells function\n")
        kernel = self.kernels[notebook_path]
        kernel_client = kernel.kernel_client
        while True:
            try:
                # self.nvim.out_write("getting message\n")
                # timeout will raise Empty error if no more message is available
                msg = kernel_client.get_iopub_msg(timeout=5)
                # self.nvim.out_write(f"got message, type {msg['msg_type']}\n")
                # self.nvim.out_write(
                # f"parent_header.msg_id {msg['parent_header']['msg_id']}\n"
                # )
                if msg["parent_header"]["msg_id"] != msg_id:
                    continue

                # self.nvim.out_write("sending msg back to lua\n")
                output = {"output_type": msg["msg_type"], **msg["content"]}
                # self.nvim.lua._ipynb.update_cell_outputs(notebook_path, cell_id, output)

                # must use async_call in a non-main thread
                # https://pynvim.readthedocs.io/en/latest/usage/python-plugin-api.html#async-calls
                self.nvim.async_call(
                    self.nvim.lua._ipynb.update_cell_outputs,
                    notebook_path,
                    cell_id,
                    output,
                )

                if msg["content"].get("execution_state") == "idle":
                    break
            except Exception as e:
                # self.nvim.out_write(f"{repr(e)}\n")
                self.nvim.async_call(self.nvim.out_write, f"{repr(e)}\n")
                break
