from pathlib import Path

from migen import *             #Describe signals
from migen.fhdl import verilog  #Convert migen to verilog 

from litedram.core.controller import LiteDRAMController, ControllerSettings
from litedram.core.crossbar import LiteDRAMCrossbar
from litedram.phy.lpddr5.simphy import LPDDR5SimPHY
from litedram.phy.lpddr5.simsoc import LPDDR5ExampleModule

class StandaloneLPDDR5Controller(Module):
    
    def __init__(self, phy_settings, geom_settings, timing_settings, clk_freq):

        controller_settings = ControllerSettings(
            with_refresh        = False, #TODO: Change this
            with_auto_precharge = False,
        )

        self.submodules.controller = LiteDRAMController(
            phy_settings=phy_settings,
            geom_settings=geom_settings,
            timing_settings=timing_settings,
            clk_freq=clk_freq,
            controller_settings=controller_settings,
        )

        self.submodules.crossbar = LiteDRAMCrossbar(
            self.controller.interface
        )

        self.native = self.crossbar.get_port(mode="both")
        self.dfi = self.controller.dfi
        self.crossbar.finalize()

def generate_verilog(dut, ios):
    output_dir = Path("build/standalone_lpddr5")
    output_dir.mkdir(parents=True, exist_ok=True)

    rtl = verilog.convert(
        dut,
        ios=ios,
        name="lpddr5_controller",
    )

    output_file = output_dir / "lpddr5_controller.v"
    output_file.write_text(str(rtl))

    print(f"Generated: {output_file}")

def main():
    clk_freq = 100e6 #100MHz

    sdram_module = LPDDR5ExampleModule(
        clk_freq=clk_freq,
        rate="1:1",
    )

    geom_settings = sdram_module.geom_settings
    timing_settings = sdram_module.timing_settings

    phy = LPDDR5SimPHY(
        sys_clk_freq=clk_freq,
        wck_ck_ratio=2,
        aligned_reset_zero=True,
        masked_write=True,
    )

    phy_settings = phy.settings

    dut = StandaloneLPDDR5Controller(
        phy_settings=phy_settings,
        geom_settings=geom_settings,
        timing_settings=timing_settings,
        clk_freq=clk_freq,
    )

    ios = set()

    # Native frontend
    ios.update(dut.native.cmd.flatten())
    ios.update(dut.native.wdata.flatten())
    ios.update(dut.native.rdata.flatten())

    # DFI interface
    for phase in dut.dfi.phases:
        ios.update(phase.flatten())

    generate_verilog(dut, ios)

if __name__ == "__main__":
    main()

