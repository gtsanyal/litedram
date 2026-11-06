
from pathlib import Path

from migen import *
from migen.fhdl import verilog

from litedram.phy.lpddr5.s7phy import K7LPDDR5PHY


class LPDDR5Pads:
    def __init__(self):
        self.ck_p = Signal(name="ck_p")
        self.ck_n = Signal(name="ck_n")

        self.cs = Signal(name="cs")
        self.reset_n = Signal(name="reset_n")

        self.ca = Signal(7, name="ca")

        self.wck_p = Signal(2, name="wck_p")
        self.wck_n = Signal(2, name="wck_n")

        self.rdqs_p = Signal(2, name="rdqs_p")
        self.rdqs_n = Signal(2, name="rdqs_n")

        self.dmi = Signal(2, name="dmi")
        self.dq = Signal(16, name="dq")


def main():
    pads = LPDDR5Pads()

    phy = K7LPDDR5PHY(
        pads=pads,
        ck_freq=100e6,
        iodelay_clk_freq=200e6,
        wck_ck_ratio=2,
    )

    print("PHY:", phy.settings.phytype)
    print("DFI width:", phy.settings.dfi_databits)
    print("Read latency:", phy.settings.read_latency)
    print("Write latency:", phy.settings.write_latency)

    ios = set()

    # Physical LPDDR5 interface
    for name in [
        "ck_p", "ck_n", "cs", "reset_n", "ca",
        "wck_p", "wck_n", "rdqs_p", "rdqs_n",
        "dmi", "dq",
    ]:
        ios.add(getattr(pads, name))

    # DFI interface
    for phase in phy.dfi.phases:
        ios.update(phase.flatten())

    output_dir = Path("build/standalone_lpddr5")
    output_dir.mkdir(parents=True, exist_ok=True)

    rtl = verilog.convert(
        phy,
        ios=ios,
        name="lpddr5_phy",
    )

    output_file = output_dir / "lpddr5_phy.v"
    output_file.write_text(str(rtl))

    print(f"Generated: {output_file}")


if __name__ == "__main__":
    main()
