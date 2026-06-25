from siliconcompiler import Design


class IcarusCmdFile(Design):
    def __init__(self):
        super().__init__()

        self.set_name("icarus_cmd_file")

        self.set_dataroot("local", __file__)

        with self.active_dataroot("local"):
            with self.active_fileset("icarus"):
                self.add_file("icarus_cmd_file.f", filetype="commandfile")


class VerilatorCmdFile(Design):
    def __init__(self):
        super().__init__()

        self.set_name("verilator_cmd_file")

        self.set_dataroot("local", __file__)

        with self.active_dataroot("local"):
            with self.active_fileset("verilator"):
                self.add_file("verilator_cmd_file.vc", filetype="commandfile")
