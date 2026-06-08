# 1. Laufende Simulation sauber beenden
quit -sim

# 2. VHDL-Bibliothek "work" im Projektordner anlegen/bereinigen
vlib work
vmap work work

# 3. Alle Projekt-Dateien im VHDL-2008-Modus kompilieren
vcom -2008 -reportprogress 300 -work work rtl/cpu/M68020_pkg.vhd
vcom -2008 -reportprogress 300 -work work rtl/bram.vhd
vcom -2008 -reportprogress 300 -work work rtl/cpu/M68020_fetch.vhd
vcom -2008 -reportprogress 300 -work work rtl/cpu/M68020_decode.vhd
vcom -2008 -reportprogress 300 -work work rtl/cpu/M68020_ea.vhd
vcom -2008 -reportprogress 300 -work work rtl/cpu/M68020_execute.vhd
vcom -2008 -reportprogress 300 -work work rtl/cpu/M68020_execute.vhd
vcom -2008 -reportprogress 300 -work work rtl/cpu/M68020_bus_ctrl.vhd
vcom -2008 -work work rtl/cpu/M68020_cpu.vhd
vcom -2008 -reportprogress 300 -work work rtl/M68020_test_board.vhd
vcom -2008 -reportprogress 300 -work work rtl/A1200_top.vhd
vcom -2008 -reportprogress 300 -work work A1200_tb.vhd

# 4. Die Simulation scharfschalten und die echte CPU-Hierarchie binden
vsim -voptargs="+acc" work.a1200_tb

# 5. Alle wichtigen Kern-Signale der CPU automatisch ins Wave-Fenster werfen
add wave -divider "SYSTEM-BASIS"
add wave -position insertpoint sim:/a1200_tb/tb_clk_sys
add wave -position insertpoint sim:/a1200_tb/tb_reset

add wave -divider "68020 CPU-KERN"
add wave -color "Yellow"  -position insertpoint sim:/a1200_tb/uut/amiga_cpu/current_state
add wave -color "Orange"  -radix hexadecimal -position insertpoint sim:/a1200_tb/uut/amiga_cpu/reg_pc
add wave -color "Cyan"    -radix hexadecimal -position insertpoint sim:/a1200_tb/uut/amiga_cpu/int_bus_data_r

add wave -divider "AMIGA BUS-HANDSHAKE"
add wave -position insertpoint sim:/a1200_tb/uut/amiga_cpu/as_n
add wave -position insertpoint sim:/a1200_tb/uut/amiga_cpu/ds_n
add wave -position insertpoint sim:/a1200_tb/uut/amiga_cpu/dsack0_n
add wave -position insertpoint sim:/a1200_tb/uut/amiga_cpu/dsack1_n

add wave -divider "PIPELINE / DECODER"
add wave -radix hexadecimal -position insertpoint sim:/a1200_tb/uut/amiga_cpu/int_stage_c
add wave -position insertpoint sim:/a1200_tb/uut/amiga_cpu/int_op_nop
add wave -position insertpoint sim:/a1200_tb/uut/amiga_cpu/int_exec_done

# 6. Protokollierung in eine Textdatei starten (vor dem Run-Befehl!)
transcript file cpu_simulation.log

echo "=== START DER CHIP-SIMULATION ==="

# 7. Den virtuellen Amiga 1200 für exakt 1000 Nanosekunden einschalten
run 5000 ns

# 8. Protokollierung sauber schließen und wegschreiben
transcript file ""

# 9. Die Wellenform-Ansicht optimal zoomen, damit alles sofort sichtbar ist
wave zoomfull
