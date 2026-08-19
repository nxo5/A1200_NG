# stop any running sim
quit -sim

# setup work library
vlib work
vmap work work

# compile testbench + top first
vcom -2008 -work work A1200_tb.vhd
vcom -2008 -work work rtl/A1200_top.vhd

# compile all vhd files in rtl and subdirectories (up to 4 levels)
vcom -2008 -work work rtl/*.vhd
vcom -2008 -work work rtl/*/*.vhd
vcom -2008 -work work rtl/*/*/*.vhd
vcom -2008 -work work rtl/*/*/*/*.vhd

# compile system-level VHDL
vcom -2008 -work work sys/*.vhd
vcom -2008 -work work sys/*/*.vhd

# compile turbo_card 030_EC dir explicit (if still missing)
vcom -2008 -work work rtl/turbo_card/030_EC/*.vhd

# compile Verilog / SystemVerilog files
vlog -sv -work work rtl/*.v
vlog -sv -work work rtl/*/*.v
vlog -sv -work work sys/*.sv
vlog -sv -work work rtl/*/*.sv

# elaborate
vsim -voptargs="+acc" work.A1200_tb

# add safe waves
add wave -divider "TESTBENCH"
add wave -position insertpoint sim:/A1200_tb/tb_clk_sys
add wave -position insertpoint sim:/A1200_tb/tb_reset

add wave -divider "TOP/UT"
add wave -position insertpoint sim:/A1200_tb/uut/ce_pix
add wave -position insertpoint sim:/A1200_tb/uut/HBlank
add wave -position insertpoint sim:/A1200_tb/uut/HSync
add wave -position insertpoint sim:/A1200_tb/uut/VBlank
add wave -position insertpoint sim:/A1200_tb/uut/VSync

# transcript and run
transcript file cpu_simulation.log

echo "=== START DER CHIP-SIMULATION ==="
run 1000 ns
transcript file ""
wave zoomfull
