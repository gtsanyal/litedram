#
# This file is part of LiteDRAM.
#
# SPDX-License-Identifier: BSD-2-Clause

"""LPDDR4 PHY with JEDEC-accurate pad timing and DQS-strobed read capture.

Unlike `LPDDR4SimPHY` (made for LiteDRAM's idealized DRAM simulator), this PHY is meant to drive a
real JEDEC behavioral model (e.g. Winbond W66AP6NB) and models the parts of a physical PHY that
such a model is sensitive to:

Write path
    * DQS edges are aligned to CK rising edges, so tDQSS = 1.0 tCK (spec: 0.75..1.25 tCK).
    * 2 tCK static write preamble and 0.5 tCK postamble, with per-UI output-enable so that DQS
      is not driven outside of the preamble/burst/postamble window.
    * DQ/DMI are launched through a per-byte TX delay line (`wdly_dq<n>`, in taps). LPDDR4 DRAMs
      have an unmatched DQ receiver and sample DQ at DQS + tDQS2DQ (200..800 ps), so the delay
      must be trained (write DQ-DQS training).

Read path
    * The incoming differential DQS is delayed by a per-byte RX delay line (`rdly_dqs<n>`) to
      center it in the (edge-aligned) DQ eye, and DQ is captured on both DQS edges.
    * A per-byte DQS gate (`rdly_gate<n>`, in UI) masks DQS outside of read bursts. The gate opens
      during the read preamble and closes itself after 16 DQS edges (or later for back-to-back
      reads), so Hi-Z DQS never clocks the capture logic.
    * Captured bursts go into an asynchronous FIFO and are popped at a fixed latency
      (`read_latency - 2` after the DFI read), which absorbs tDQSCK and board delay.

The analog/IO parts (pads, delay lines, DQS-clocked capture, async FIFO) are implemented as a
behavioral "hard macro" in `verilog/lpddr4_phy_io.sv`, instantiated through `Instance`, in the same
way FPGA PHYs instantiate IDELAY/ISERDES primitives.

Clock domains: `sys` (controller), `sys8x` (CA/CS, 1 bit per tCK) and `sys8x_ddr` (CK/DQ/DQS, 1 bit
per UI). All three must have aligned rising edges, and the reset has to be released synchronously
to a `sys` rising edge.
"""

import os
from operator import or_
from functools import reduce

from migen import *

from litex.soc.interconnect.csr import CSR, CSRStorage, CSRStatus

from litedram.common import TappedDelayLine, BitSlip
from litedram.phy.utils import Latency, Serializer, delayed
from litedram.phy.sim_utils import SimSerDesMixin
from litedram.phy.lpddr4.basephy import LPDDR4PHY

VERILOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "verilog")


def verilog_sources():
    """SystemVerilog sources of the IO macro required by LPDDR4StrobePHY."""
    return [os.path.join(VERILOG_DIR, "lpddr4_phy_io.sv")]


class LPDDR4Pads:
    """Top-level LPDDR4 pads (single channel, single rank)"""
    def __init__(self, databits=16, prefix="ddram"):
        nbytes = databits // 8
        self.ck_t    = Signal(name=f"{prefix}_ck_t")
        self.ck_c    = Signal(name=f"{prefix}_ck_c")
        self.cke     = Signal(name=f"{prefix}_cke")
        self.cs      = Signal(name=f"{prefix}_cs")
        self.ca      = Signal(6, name=f"{prefix}_ca")
        self.reset_n = Signal(name=f"{prefix}_reset_n")
        self.odt_ca  = Signal(name=f"{prefix}_odt_ca")
        self.dq      = Signal(databits, name=f"{prefix}_dq")
        self.dqs_t   = Signal(nbytes, name=f"{prefix}_dqs_t")
        self.dqs_c   = Signal(nbytes, name=f"{prefix}_dqs_c")
        self.dmi     = Signal(nbytes, name=f"{prefix}_dmi")

    def get_ios(self):
        return {self.ck_t, self.ck_c, self.cke, self.cs, self.ca, self.reset_n, self.odt_ca,
                self.dq, self.dqs_t, self.dqs_c, self.dmi}


class LPDDR4StrobePHY(SimSerDesMixin, LPDDR4PHY):
    """LPDDR4 PHY for use with external (JEDEC behavioral) DRAM models

    Parameters
    ----------
    sys_clk_freq : float
        Controller clock frequency; the DRAM clock is 8x this frequency.
    tap_ps : int
        Delay line resolution in picoseconds.
    tap_bits : int
        Delay line control width (number of taps = 2**tap_bits).
    rx_fifo_latency : int
        Extra read latency (sys cycles) reserved for DQS capture and FIFO synchronization.
    rdqs_delay_reset : int
        Reset value of the read DQS delay (taps), nominally 1/4 tCK.
    """
    def __init__(self, sys_clk_freq, *, databits=16, tap_ps=25, tap_bits=6, rx_fifo_latency=5,
                 rdqs_delay_reset=None, masked_write=True, **kwargs):
        pads = LPDDR4Pads(databits)
        super().__init__(pads,
            sys_clk_freq = sys_clk_freq,
            ser_latency  = Latency(sys=Serializer.LATENCY),
            des_latency  = Latency(sys=rx_fifo_latency),
            phytype      = "LPDDR4StrobePHY",
            masked_write = masked_write,
            **kwargs)

        nphases = self.nphases
        nbytes  = self.databits // 8
        ui_per_sys = 2*nphases  # 16 UI per controller cycle
        read_latency = self.settings.read_latency
        assert read_latency >= 4

        tck_ps = 1e12 / (nphases * sys_clk_freq)
        if rdqs_delay_reset is None:
            rdqs_delay_reset = int(round(tck_ps / 4 / tap_ps))
        self.tap_ps   = tap_ps
        self.tap_bits = tap_bits

        # Registers --------------------------------------------------------------------------------
        for n in range(nbytes):
            setattr(self, f"_wdly_dq{n}",  CSRStorage(tap_bits, name=f"wdly_dq{n}",
                description=f"Byte {n}: TX DQ/DMI delay (taps of {tap_ps} ps), trained for tDQS2DQ"))
            setattr(self, f"_rdly_dqs{n}", CSRStorage(tap_bits, name=f"rdly_dqs{n}", reset=rdqs_delay_reset,
                description=f"Byte {n}: RX DQS delay (taps of {tap_ps} ps), centers DQS in the read DQ eye"))
            setattr(self, f"_rdly_gate{n}", CSRStorage(7, name=f"rdly_gate{n}",
                description=f"Byte {n}: read DQS gate opening, in UI after the DFI read command cycle"))
        self._rdfifo_rst    = CSR(name="rdfifo_rst")
        self._rdfifo_status = CSRStatus(nbytes, name="rdfifo_status",
            description="Per-byte sticky read FIFO underflow (data not captured in time)")

        wdly_dq   = [getattr(self, f"_wdly_dq{n}").storage   for n in range(nbytes)]
        rdly_dqs  = [getattr(self, f"_rdly_dqs{n}").storage  for n in range(nbytes)]
        rdly_gate = [getattr(self, f"_rdly_gate{n}").storage for n in range(nbytes)]

        # Serializers ------------------------------------------------------------------------------
        sdr = dict(clkdiv="sys", clk="sys8x",     reset_cnt=0)
        ddr = dict(clkdiv="sys", clk="sys8x_ddr", reset_cnt=0)

        def ser(name, i, kind):
            o = Signal(name=f"ser_{name}")
            self.ser(i=i, o=o, name=name, **kind)
            return o

        # CK is inverted so that its rising edge is in the middle of each (SDR) CA bit.
        ck      = ser("ck",      ~self.out.clk,    ddr)
        cke     = ser("cke",     self.out.cke,     sdr)
        odt     = ser("odt",     self.out.odt,     sdr)
        reset_n = ser("reset_n", self.out.reset_n, sdr)
        cs      = ser("cs",      self.out.cs,      sdr)
        ca      = [ser(f"ca{i}", self.out.ca[i], sdr) for i in range(6)]

        # Write DQS / output enables ---------------------------------------------------------------
        # Re-derive the write data window (same taps as LPDDR4PHY uses for dq_oe) and build the DQS
        # waveform per UI. With the command pipeline used by LPDDR4PHY, the data cycle starts 2*WL+1
        # UI after the CK edge latching CAS-2, so DQS must rise in UI 1 of the data cycle (aligned
        # with the CK rising edge -> tDQSS = 1 tCK) and toggle every UI after that.
        wrtap = self.settings.write_latency - 1
        assert wrtap >= 1
        wr_en = reduce(or_, [p.wrdata_en for p in self.dfi.phases])
        wren  = TappedDelayLine(signal=wr_en, ntaps=wrtap + 2)
        self.submodules += wren
        cur  = wren.taps[wrtap]      # this cycle carries a burst
        nxt  = wren.taps[wrtap - 1]  # next cycle carries a burst
        prev = wren.taps[wrtap + 1]  # previous cycle carried a burst

        dqs_pattern = Signal(ui_per_sys)
        wr_oe       = Signal(ui_per_sys)
        self.comb += [
            # LSB first: UI0 low (end of preamble / falling edge after previous burst), rise at UI1, ...
            dqs_pattern.eq(Mux(cur, 0b1010101010101010, 0)),
            wr_oe.eq(Mux(cur, 0xffff, 0)
                     | Mux(nxt  & ~cur, 0xe000, 0)    # 2 tCK static preamble: UIs 13..15 + UI0 of data cycle
                     | Mux(prev & ~cur, 0x0001, 0)),  # 0.5 tCK postamble
        ]
        dq_window = Signal(ui_per_sys)
        self.comb += dq_window.eq(Replicate(cur, ui_per_sys))

        dq_ser, dmi_ser, dqs_ser, dqs_oe_ser, dq_oe_ser = [], [], [], [], []
        for byte in range(nbytes):
            # Same bitslip control as DQ, so write-latency calibration moves the whole burst.
            def wslip(i, name):
                o = Signal(ui_per_sys, name=name)
                self.submodules += BitSlip(
                    dw     = ui_per_sys,
                    cycles = 1,
                    rst    = self.get_rst(byte, self._wdly_dq_bitslip_rst.re),
                    slp    = self.get_inc(byte, self._wdly_dq_bitslip.re),
                    i      = i,
                    o      = o,
                )
                return o
            dqs_b    = wslip(dqs_pattern, f"dqs_pattern{byte}")
            dqs_oe_b = wslip(wr_oe,       f"dqs_oe{byte}")
            dq_oe_b  = wslip(dq_window,   f"dq_oe{byte}")
            dqs_ser.append(ser(f"dqs{byte}",    dqs_b,    ddr))
            dqs_oe_ser.append(ser(f"dqs_oe{byte}", dqs_oe_b, ddr))
            dq_oe_ser.append(ser(f"dq_oe{byte}",   dq_oe_b,  ddr))
            dmi_ser.append(ser(f"dmi{byte}", self.out.dmi_o[byte], ddr))
        for bit in range(self.databits):
            dq_ser.append(ser(f"dq{bit}", self.out.dq_o[bit], ddr))

        # Read gate --------------------------------------------------------------------------------
        # One gate pulse per read command per byte, positioned rdly_gate UI after the start of the
        # DFI cycle in which the read was issued (coarse: sys cycles, fine: UI within the cycle).
        rd_en = reduce(or_, [p.rddata_en for p in self.dfi.phases])
        rden  = TappedDelayLine(signal=rd_en, ntaps=7)
        self.submodules += rden
        rden_hist = Array([rd_en] + [rden.taps[i] for i in range(7)])
        gate_ser = []
        for byte in range(nbytes):
            sel      = Signal(name=f"gate_sel{byte}")
            gate_vec = Signal(ui_per_sys, name=f"gate_vec{byte}")
            self.comb += [
                sel.eq(rden_hist[rdly_gate[byte][4:7]]),
                Case(rdly_gate[byte][0:4], {ui: gate_vec.eq(sel << ui) for ui in range(ui_per_sys)}),
            ]
            gate_ser.append(ser(f"gate{byte}", gate_vec, ddr))

        # Read FIFO pop: data is presented on out.dq_i in cycle (read_latency - 1), so that after the
        # read BitSlip of LPDDR4PHY it reaches DFI rddata together with rddata_valid.
        pop      = delayed(self, rd_en, cycles=read_latency - 2)
        rx_data  = Signal(128*nbytes)
        rx_empty = Signal(nbytes)
        rx_rst   = Signal()
        self.comb += rx_rst.eq(self._rdfifo_rst.re | self._rst.storage | ResetSignal("sys"))

        for byte in range(nbytes):
            for j in range(8):
                for beat in range(ui_per_sys):
                    self.comb += self.out.dq_i[8*byte + j][beat].eq(rx_data[128*byte + 8*beat + j])

        underflow = self._rdfifo_status.status
        for byte in range(nbytes):
            self.sync += If(self._rdfifo_rst.re,
                underflow[byte].eq(0)
            ).Elif(pop & rx_empty[byte],
                underflow[byte].eq(1)
            )

        # IO macro ---------------------------------------------------------------------------------
        self.specials += Instance("lpddr4_phy_io",
            p_NBYTES   = nbytes,
            p_TAP_PS   = tap_ps,
            p_TAP_BITS = tap_bits,

            i_clk_ui    = ClockSignal("sys8x_ddr"),
            i_sys_clk   = ClockSignal("sys"),

            i_ck        = ck,
            i_cke       = cke,
            i_cs        = cs,
            i_ca        = Cat(*ca),
            i_reset_n   = reset_n,
            i_odt       = odt,

            i_dq_o      = Cat(*dq_ser),
            i_dq_oe     = Cat(*dq_oe_ser),
            i_dmi_o     = Cat(*dmi_ser),
            i_dqs_o     = Cat(*dqs_ser),
            i_dqs_oe    = Cat(*dqs_oe_ser),

            i_wdq_taps  = Cat(*wdly_dq),
            i_rdqs_taps = Cat(*rdly_dqs),

            i_gate      = Cat(*gate_ser),
            i_rx_rst    = rx_rst,
            i_pop       = pop,
            o_rx_data   = rx_data,
            o_rx_empty  = rx_empty,

            o_ck_t      = pads.ck_t,
            o_ck_c      = pads.ck_c,
            o_cke_pad   = pads.cke,
            o_cs_pad    = pads.cs,
            o_ca_pad    = pads.ca,
            o_reset_n_pad = pads.reset_n,
            o_odt_ca    = pads.odt_ca,
            io_dq       = pads.dq,
            io_dqs_t    = pads.dqs_t,
            io_dqs_c    = pads.dqs_c,
            io_dmi      = pads.dmi,
        )
