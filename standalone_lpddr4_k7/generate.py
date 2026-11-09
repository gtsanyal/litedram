#!/usr/bin/env python3
"""Generate a standalone LPDDR4 subsystem built around the Kintex-7 soft PHY (K7LPDDR4PHY).

This mirrors the LPDDR4 part of the Antmicro LPDDR4 Test Board target (litex-boards 2024.12,
`antmicro_lpddr4_test_board.py`) without the CPU/SoC:

    * K7LPDDR4PHY (unmodified LiteDRAM PHY): OSERDESE2/ISERDESE2 8:1, IDELAYE2/ODELAYE2,
      IOBUF/IOBUFDS/OBUFDS Xilinx primitives. Simulated with Xilinx unisim models.
    * IDELAYCTRL fed by a 200 MHz reference clock (S7IDELAYCTRL, as in the board CRG).
    * LiteDRAM core (DFI injector, controller, crossbar) with one native port.
    * 32-bit CSR bus so that the testbench can play the role of the LiteX BIOS.

Clocking is the board's CRG: the only clock input is the 100 MHz board oscillator (`clk100`),
from which an S7PLL (PLLE2_ADV + BUFG, speed grade -1) generates sys = 50 MHz, sys2x = 100 MHz,
sys8x = 400 MHz (DRAM CK, LPDDR4-800) and idelay = 200 MHz. Resets are synchronized with the
Xilinx lowering of AsyncResetSynchronizer (FDPE), exactly as in a Vivado build.

Boot clock: the Winbond part must be initialized with tCKb >= 18 ns. The PHY boot mode
(`boot_clk_div`) generates a 50 MHz CK through the same OSERDESE2 used for the 400 MHz CK,
so no FPGA clock changes when switching to the operating frequency.

Outputs (in build/standalone_lpddr4_k7/):
    lpddr4_k7_top.v     generated RTL (instantiates Xilinx primitives)
    lpddr4_csr.svh      CSR addresses (LiteX naming: CSR_<BANK>_<NAME>_ADDR)
    lpddr4_params.svh   PHY/DRAM parameters and mode register values for the testbench
    xilinx_primitives.txt  Xilinx primitives instantiated (unisim models needed for simulation)
"""

import argparse
import math
import re
from pathlib import Path

from migen import *
from migen.fhdl import verilog

from litex.soc.interconnect import csr_bus
from litex.soc.cores.clock import S7PLL, S7IDELAYCTRL
from litex.build.xilinx.common import xilinx_special_overrides, xilinx_s7_special_overrides

from litedram import modules
from litedram.core import LiteDRAMCore
from litedram.core.controller import ControllerSettings
from litedram.init import get_sdram_phy_init_sequence
from litedram.phy.lpddr4.s7phy import K7LPDDR4PHY

# Configuration (Antmicro LPDDR4 Test Board defaults) --------------------------------------------

SYS_CLK_FREQ     = 50e6         # board default; DRAM CK = 8 x sys = 400 MHz
IODELAY_CLK_FREQ = 200e6        # board default; IDELAY/ODELAY tap = 1/(64*200 MHz) = 78.125 ps
CLK100_FREQ      = 100e6        # board oscillator
TCKB_MIN         = 18e-9        # LPDDR4 boot clock period minimum (JESD209-4)
BOOT_CLK_DIV     = math.ceil(TCKB_MIN * SYS_CLK_FREQ)   # boot CK period in sys cycles (1 -> 20 ns)

MODULES = {
    "W66AP6NB":      modules.W66AP6NB,       # Winbond model used in simulation
    "MT53E256M16D1": modules.MT53E256M16D1,  # part fitted on the Antmicro board
}

CSR_DATA_WIDTH    = 32
CSR_ADDRESS_WIDTH = 14
CSR_PAGING        = 0x800
CSR_MAP           = {"ddrphy": 0, "sdram": 1}

# Pads --------------------------------------------------------------------------------------------

class LPDDR4K7Pads:
    """Same names/widths as the board's `lpddr4` resource"""
    def __init__(self, databits=16, prefix="ddram"):
        nbytes = databits // 8
        self.clk_p   = Signal(name=f"{prefix}_clk_p")
        self.clk_n   = Signal(name=f"{prefix}_clk_n")
        self.cke     = Signal(name=f"{prefix}_cke")
        self.odt     = Signal(name=f"{prefix}_odt")
        self.reset_n = Signal(name=f"{prefix}_reset_n")
        self.cs      = Signal(name=f"{prefix}_cs")
        self.ca      = Signal(6, name=f"{prefix}_ca")
        self.dq      = Signal(databits, name=f"{prefix}_dq")
        self.dqs_p   = Signal(nbytes, name=f"{prefix}_dqs_p")
        self.dqs_n   = Signal(nbytes, name=f"{prefix}_dqs_n")
        self.dmi     = Signal(nbytes, name=f"{prefix}_dmi")

    def get_ios(self):
        return {self.clk_p, self.clk_n, self.cke, self.odt, self.reset_n, self.cs, self.ca,
                self.dq, self.dqs_p, self.dqs_n, self.dmi}

# Top ---------------------------------------------------------------------------------------------

class CRG(Module):
    """Same as the _CRG of litex_boards/targets/antmicro_lpddr4_test_board.py"""
    def __init__(self, clk100, rst):
        self.clock_domains.cd_sys    = ClockDomain()
        self.clock_domains.cd_sys2x  = ClockDomain()
        self.clock_domains.cd_sys8x  = ClockDomain()
        self.clock_domains.cd_idelay = ClockDomain()

        self.submodules.pll = pll = S7PLL(speedgrade=-1)
        self.comb += pll.reset.eq(rst)
        pll.register_clkin(clk100, CLK100_FREQ)
        pll.create_clkout(self.cd_sys,    SYS_CLK_FREQ)
        pll.create_clkout(self.cd_sys2x,  2 * SYS_CLK_FREQ)
        pll.create_clkout(self.cd_sys8x,  8 * SYS_CLK_FREQ)
        pll.create_clkout(self.cd_idelay, IODELAY_CLK_FREQ)

        self.submodules.idelayctrl = S7IDELAYCTRL(self.cd_idelay)


class LPDDR4K7Standalone(Module):
    def __init__(self, module_name="W66AP6NB"):
        self.clk100 = Signal(name="clk100")
        self.rst    = Signal(name="rst")  # board button / power-on reset
        self.submodules.crg = CRG(self.clk100, self.rst)

        # PHY: what the board target instantiates, plus the boot (low frequency CK) mode.
        self.pads = pads = LPDDR4K7Pads()
        self.submodules.ddrphy = phy = K7LPDDR4PHY(pads,
            iodelay_clk_freq = IODELAY_CLK_FREQ,
            sys_clk_freq     = SYS_CLK_FREQ,
            boot_clk_div     = BOOT_CLK_DIV,
        )

        # DRAM module / core
        self.dram_module = module = MODULES[module_name](SYS_CLK_FREQ, "1:8")
        self.submodules.sdram = LiteDRAMCore(
            phy                      = phy,
            geom_settings            = module.geom_settings,
            timing_settings          = module.timing_settings,
            clk_freq                 = SYS_CLK_FREQ,
            controller_settings      = ControllerSettings(with_refresh=True),
            dfii_sw_control_on_reset = True,
        )
        self.port = self.sdram.crossbar.get_port(mode="both")

        # CSR bus
        self.submodules.csrbankarray = csr_bus.CSRBankArray(self,
            address_map   = lambda name, memory: CSR_MAP.get(name, None),
            data_width    = CSR_DATA_WIDTH,
            address_width = CSR_ADDRESS_WIDTH,
            paging        = CSR_PAGING)
        bus = csr_bus.Interface(data_width=CSR_DATA_WIDTH, address_width=CSR_ADDRESS_WIDTH)
        self.submodules.csrcon = csr_bus.Interconnect(bus, self.csrbankarray.get_buses())

        self.csr_adr   = Signal(CSR_ADDRESS_WIDTH, name="csr_adr")
        self.csr_we    = Signal(name="csr_we")
        self.csr_re    = Signal(name="csr_re")
        self.csr_dat_w = Signal(CSR_DATA_WIDTH, name="csr_dat_w")
        self.csr_dat_r = Signal(CSR_DATA_WIDTH, name="csr_dat_r")
        self.comb += [
            bus.adr.eq(self.csr_adr),
            bus.we.eq(self.csr_we),
            bus.re.eq(self.csr_re),
            bus.dat_w.eq(self.csr_dat_w),
            self.csr_dat_r.eq(bus.dat_r),
        ]

    def get_ios(self):
        ios = {self.clk100, self.rst}
        ios.update(self.port.cmd.flatten())
        ios.update(self.port.wdata.flatten())
        ios.update(self.port.rdata.flatten())
        ios.update({self.csr_adr, self.csr_we, self.csr_re, self.csr_dat_w, self.csr_dat_r})
        ios.update(self.pads.get_ios())
        return ios

# Exports -----------------------------------------------------------------------------------------

def csr_svh(top):
    shift = (CSR_PAGING // 4).bit_length() - 1
    lines = ["// Auto-generated by standalone_lpddr4_k7/generate.py -- do not edit", ""]
    for name, csrs, mapaddr, rmap in top.csrbankarray.banks:
        lines.append(f"// {name} (bank {mapaddr})")
        index = 0
        for c in csrs:
            nwords = (c.size + CSR_DATA_WIDTH - 1) // CSR_DATA_WIDTH
            ident  = f"CSR_{name}_{c.name}_ADDR".upper()
            lines.append(f"localparam int {ident:<44} = 'h{(mapaddr << shift) | index:04x};  // {c.size} bit(s)")
            index += nwords
        assert index == len(rmap.simple_csrs)
        lines.append("")
    return "\n".join(lines)


def params_svh(top, module_name):
    phy      = top.ddrphy
    settings = phy.settings
    geom     = top.dram_module.geom_settings
    _, mr    = get_sdram_phy_init_sequence(settings, top.dram_module.timing_settings)
    p = {
        "SYS_CLK_PERIOD_PS":  int(round(1e12 / SYS_CLK_FREQ)),
        "CLK100_PERIOD_PS":   int(round(1e12 / CLK100_FREQ)),
        "BOOT_CLK_DIV":       BOOT_CLK_DIV,
        "IDELAY_CLK_FREQ_MHZ": int(IODELAY_CLK_FREQ / 1e6),
        "NPHASES":            settings.nphases,
        "DATABITS":           settings.databits,
        "NBYTES":             settings.databits // 8,
        "DFI_DATABITS":       settings.dfi_databits,
        "RDPHASE":            settings.rdphase.reset.value,
        "WRPHASE":            settings.wrphase.reset.value,
        "READ_LATENCY":       settings.read_latency,
        "WRITE_LATENCY":      settings.write_latency,
        "CL":                 settings.cl,
        "CWL":                settings.cwl,
        "DELAYS":             settings.delays,
        "BITSLIPS":           settings.bitslips,
        "HALF_SYS8X_TAPS":    phy._half_sys8x_taps.storage.reset.value,
        "BANKBITS":           geom.bankbits,
        "ROWBITS":            geom.rowbits,
        "COLBITS":            geom.colbits,
        "NATIVE_ADDR_WIDTH":  len(top.port.cmd.addr),
        "NATIVE_DATA_WIDTH":  len(top.port.wdata.data),
    }
    lines = ["// Auto-generated by standalone_lpddr4_k7/generate.py -- do not edit", "",
             f"// DRAM module: {module_name}"]
    lines += [f"localparam int {k} = {v};" for k, v in p.items()]
    lines += ["", f"localparam real TAP_PS = {1e12 / (64 * IODELAY_CLK_FREQ)};"]
    lines += ["", "// Mode register values (litedram.init)"]
    lines += [f"localparam logic [7:0] MR{ma}_VALUE = 8'h{op:02x};" for ma, op in sorted(mr.items())]
    lines += ["",
        "localparam logic [3:0] DFII_CONTROL_SEL     = 4'h1;",
        "localparam logic [3:0] DFII_CONTROL_CKE     = 4'h2;",
        "localparam logic [3:0] DFII_CONTROL_ODT     = 4'h4;",
        "localparam logic [3:0] DFII_CONTROL_RESET_N = 4'h8;",
        "localparam logic [5:0] DFII_COMMAND_CS      = 6'h01;",
        "localparam logic [5:0] DFII_COMMAND_WE      = 6'h02;",
        "localparam logic [5:0] DFII_COMMAND_CAS     = 6'h04;",
        "localparam logic [5:0] DFII_COMMAND_RAS     = 6'h08;",
        "localparam logic [5:0] DFII_COMMAND_WRDATA  = 6'h10;",
        "localparam logic [5:0] DFII_COMMAND_RDDATA  = 6'h20;",
        "",
    ]
    return "\n".join(lines)

# Main --------------------------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Generate standalone LiteDRAM LPDDR4 + K7LPDDR4PHY")
    parser.add_argument("--output-dir", default="build/standalone_lpddr4_k7")
    parser.add_argument("--module", default="W66AP6NB", choices=sorted(MODULES))
    args = parser.parse_args()

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    top = LPDDR4K7Standalone(args.module)
    overrides = {**xilinx_special_overrides, **xilinx_s7_special_overrides}
    rtl = str(verilog.convert(top, ios=top.get_ios(), name="lpddr4_k7_top", special_overrides=overrides))
    (out / "lpddr4_k7_top.v").write_text(rtl)

    # Xilinx primitives used by the netlist (their unisim models are needed for simulation).
    prims = sorted(set(re.findall(r"^([A-Z][A-Z0-9_]+)\s*(?:#\s*\(|\w+\s*\()", rtl, flags=re.M)))
    (out / "xilinx_primitives.txt").write_text("\n".join(prims) + "\n")
    (out / "lpddr4_csr.svh").write_text(csr_svh(top))
    (out / "lpddr4_params.svh").write_text(params_svh(top, args.module))

    s = top.ddrphy.settings
    print(f"Generated {out}/lpddr4_k7_top.v  module={args.module} CL={s.cl} CWL={s.cwl} "
          f"read_latency={s.read_latency} write_latency={s.write_latency} "
          f"rdphase={s.rdphase.reset.value} wrphase={s.wrphase.reset.value} "
          f"half_sys8x_taps={top.ddrphy._half_sys8x_taps.storage.reset.value} boot_clk_div={BOOT_CLK_DIV}")
    print(f"Xilinx primitives: {' '.join(prims)}")


if __name__ == "__main__":
    main()
