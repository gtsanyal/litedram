Running ncverilog ..........
    irun15 +access+rwc +sv   +define+T3200  W66AP6NB.nc.svp  W66AP6NB_sim.v (your test pattern)

Running VCS ................
    vcs -V -notice -full64 -debug_access+all -sverilog -R +define+T3200 W66AP6NB.vcs.svp W66AP6NB_sim.v (your test pattern)

Running Intel Modelsim FPGA (free ver)...........
    rm -fr work
    vlib work
    vmap work work
    vlog -sv -sv09compat +define+T3200 W66AP6NB.modelsim.svp  W66AP6NB_sim.v (your test pattern)
    vsim tb -batch -do "run -all" -logfile modelsim.log 

