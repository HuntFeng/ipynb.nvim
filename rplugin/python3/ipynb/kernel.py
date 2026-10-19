from jupyter_client import KernelManager


class Kernel:

    def __init__(self) -> None:
        self.kernel_manager = KernelManager()
        self.start()

    def start(self) -> None:
        self.kernel_manager.start_kernel()
        self.kernel_client = self.kernel_manager.client()
        self.kernel_client.start_channels()
        self.kernel_client.wait_for_ready()

    def interrupt(self) -> None:
        self.kernel_manager.interrupt_kernel()

    def restart(self) -> None:
        self.kernel_manager.restart_kernel()

    def shutdown(self) -> None:
        self.kernel_manager.shutdown_kernel()

    def execute(self, code: str) -> str:
        return self.kernel_client.execute(code)
