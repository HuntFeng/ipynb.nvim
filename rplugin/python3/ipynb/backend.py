from typing import Dict, List, Tuple

from jupytext import jupytext, config
from jupyter_client.kernelspec import KernelSpecManager
from .kernel import Kernel
import pynvim

# import threading

# remove all metadata from the text representation of the notebook.
# minus sign - means remove
configuration = config.JupytextConfiguration(notebook_metadata_filter="-all")


@pynvim.plugin
class Backend:
    kernels: Dict[str, Kernel]
    notebooks: Dict[str, jupytext.NotebookNode]
    cell_ids: Dict[str, Dict[str, int]]

    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self.nvim.exec_lua("_ipynb = require('ipynb')")
        self.notebooks = dict()
        self.kernels = dict()
        self.cell_ids = dict()

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

        self.notebooks[notebook_path].cells = [
            jupytext.nbformat.from_dict(cell_data) for cell_data in cell_datas
        ]

        if not save_outputs:
            for cell in self.notebooks[notebook_path].cells:
                cell.outputs.clear()
                cell.execution_count = None

        jupytext.write(self.notebooks[notebook_path], notebook_path)

    @pynvim.function("ListKernels", sync=True)
    def list_kernels(self, _):
        manager = KernelSpecManager()
        return manager.get_all_specs()

    @pynvim.function("GetKernelSpec", sync=True)
    def get_kernel_spec(self, args: Tuple[str]):
        """
        Initializing jupyter kernel for a specific notebook.

        Input:
            args[0]: notebook_path
        """
        notebook_path = args[0]
        if not notebook_path in self.kernels:
            return
        return self.kernels[notebook_path].get_spec()

    @pynvim.function("StartKernel", sync=True)
    def init_kernel(self, args: Tuple[str, str]):
        """
        Initializing jupyter kernel for a specific notebook.

        Input:
            args[0]: notebook_path
            args[1]: kernel_key
        """
        notebook_path = args[0]
        kernel_key = args[1]
        self.kernels[notebook_path] = Kernel(kernel_key)
        self.cell_ids[notebook_path] = dict()

    @pynvim.function("InterruptKernel")
    def interrupt_kernel(self, args: Tuple[str]):
        """
        Interupt a kernel for a notebook.

        Input:
            args[0]: notebook_path
        """
        notebook_path = args[0]
        if notebook_path in self.kernels:
            self.kernels[notebook_path].interrupt()

    @pynvim.function("ShutdownKernel")
    def shutdown_kernel(self, args: Tuple[str]):
        """
        Shutdonw a kernel for a notebook.

        Input:
            args[0]: notebook_path
        """
        notebook_path = args[0]
        if notebook_path in self.kernels:
            self.kernels[notebook_path].shutdown()

    @pynvim.function("RestartKernel")
    def restart_kernels(self, args: Tuple[str]):
        """
        Restart a kernel for a notebook.

        Input:
            args[0]: notebook_path
        """
        notebook_path = args[0]
        if notebook_path in self.kernels:
            self.kernels[notebook_path].restart()

    @pynvim.function("RunCell")
    def run_cell(self, args: Tuple[str, int, str]):
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
        if not notebook_path in self.kernels:
            self.nvim.out_write("Haven't initialize kernel yet\n")
            return

        try:
            msg_id = self.kernels[notebook_path].execute(code)
            self.cell_ids[notebook_path][msg_id] = cell_id
            self.handle_messages(notebook_path)
        except Exception as e:
            self.nvim.out_write(f"python: run_cell(): {repr(e)}\n")

    def handle_messages(self, notebook_path: str):
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

        kernel = self.kernels[notebook_path]
        kernel_client = kernel.kernel_client
        while True:
            try:
                msg = kernel_client.get_iopub_msg(timeout=5)
                msg_id = msg["parent_header"]["msg_id"]
                if msg["parent_header"]["msg_type"] == "shutdown_request":
                    continue
                cell_id = self.cell_ids[notebook_path][msg_id]
                output = {"output_type": msg["msg_type"], **msg["content"]}
                self.nvim.lua._ipynb.update_cell_outputs(notebook_path, cell_id, output)

                if msg["content"].get("execution_state") == "idle":
                    break
            except Exception as e:
                self.nvim.out_write(f"python: update_cells(): {repr(e)}\n")
                break
