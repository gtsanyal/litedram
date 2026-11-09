
from pathlib import Path

from migen import *
from migen.fhdl import verilog

from litedram.phy.lpddr4.simphy import LPDDR4SimPHY


# Configuration ---------------------------------------------------------------

SYS_CLK_FREQ = 100e6
OUTPUT_DIR = Path("build/standalone_lpddr4")


# Standalone LPDDR4 Simulation PHY -------------------------------------------

class LPDDR4StandaloneSimPHY(Module):
    def __init__(self):

        # 1. Instantiate Antmicro's LPDDR4 simulation PHY.
        self.submodules.phy = LPDDR4SimPHY(
            sys_clk_freq=SYS_CLK_FREQ,
            aligned_reset_zero=True,
            masked_write=True,
        )

        # 2. Create explicit top-level LPDDR4 data signals.
        #
        # SimPad represents bidirectional buses using:
        #   pads.dq     : incoming data
        #   pads.dq_o   : outgoing data
        #   pads.dq_oe  : output enable
        #
        # The same applies to DQS and DMI.

        self.dq_i = Signal(16, name="dq_i")
        self.dq_o = Signal(16, name="dq_o")
        self.dq_oe = Signal(name="dq_oe")

        self.dqs_i = Signal(2, name="dqs_i")
        self.dqs_o = Signal(2, name="dqs_o")
        self.dqs_oe = Signal(name="dqs_oe")

        self.dmi_i = Signal(2, name="dmi_i")
        self.dmi_o = Signal(2, name="dmi_o")
        self.dmi_oe = Signal(name="dmi_oe")

        # 3. Connect the top-level signals to the PHY pads.
        pads = self.phy.pads

        # Drive the `_i` pads: SimulationPads already drives `pads.dq` (= oe ? dq_o : dq_i).
        self.comb += [
            pads.dq_i.eq(self.dq_i),
            self.dq_o.eq(pads.dq_o),
            self.dq_oe.eq(pads.dq_oe),

            pads.dqs_i.eq(self.dqs_i),
            self.dqs_o.eq(pads.dqs_o),
            self.dqs_oe.eq(pads.dqs_oe),

            pads.dmi_i.eq(self.dmi_i),
            self.dmi_o.eq(pads.dmi_o),
            self.dmi_oe.eq(pads.dmi_oe),
        ]


# Verilog Generation ----------------------------------------------------------

def main():

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    dut = LPDDR4StandaloneSimPHY()

    ios = set()

    # 4. Export the entire DFI interface.
    for phase in dut.phy.dfi.phases:
        ios.update(phase.flatten())

    # 5. Export LPDDR4 command/address/control pads.
    pads = dut.phy.pads

    for name in [
        "clk",
        "cke",
        "odt",
        "reset_n",
        "cs",
        "ca",
    ]:
        ios.add(getattr(pads, name))

    # 6. Export explicitly named LPDDR4 data signals.
    ios.update([
        dut.dq_i,
        dut.dq_o,
        dut.dq_oe,

        dut.dqs_i,
        dut.dqs_o,
        dut.dqs_oe,

        dut.dmi_i,
        dut.dmi_o,
        dut.dmi_oe,
    ])

    # 7. Generate Verilog.
    #
    # Migen automatically exposes the clock domains used
    # by the PHY when converting the design.
    output = verilog.convert(
        dut,
        ios=ios,
        name="lpddr4_simphy",
    )

    output_path = OUTPUT_DIR / "lpddr4_simphy.v"
    output.write(str(output_path))

    print(f"Generated: {output_path}")


if __name__ == "__main__":
    main()
