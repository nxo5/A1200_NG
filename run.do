# 1. Laufende Simulation sauber beenden
quit -sim

# 2. VHDL-Bibliothek "work" im Projektordner anlegen/bereinigen
vlib work
vmap work work

# 3. Wichtige Projekt-Dateien im VHDL-2008-Modus kompilieren (Basis-Set)
# Testbench und Top
vcom -2008 -work work A1200_tb.vhd
vcom -2008 -work work rtl/A1200_top.vhd

# Turbo card / CPU core (erste zentrale Komponenten)
vcom -2008 -work work rtl/turbo_card/turbo_card.vhd
vcom -2008 -work work rtl/turbo_card/030_EC/030_ec.vhd
vcom -2008 -work work rtl/turbo_card/030_EC/030_ec_bus_top.vhd

# Optional: kompiliere Verilog/Verilog-Module falls vorhanden
# (auskommentieren, falls kein Verilog-Compiler/Files benötigt werden)
# vlog -work work rtl/mycore.v
# vlog -work work rtl/lfsr.v
# vlog -sv -work work sys/*.sv

# 4. Elaborate / Starte Simulation der Testbench
vsim -voptargs="+acc" work.A1200_tb

# 5. Sichere, existierende Signale automatisch ins Wave-Fenster
add wave -divider "TESTBENCH"
add wave -position insertpoint sim:/A1200_tb/tb_clk_sys
add wave -position insertpoint sim:/A1200_tb/tb_reset
add wave -position insertpoint sim:/A1200_tb/tb_pal_mode

add wave -divider "TOP/UT"
add wave -position insertpoint sim:/A1200_tb/uut/ce_pix
add wave -position insertpoint sim:/A1200_tb/uut/HBlank
add wave -position insertpoint sim:/A1200_tb/uut/HSync
add wave -position insertpoint sim:/A1200_tb/uut/VBlank
add wave -position insertpoint sim:/A1200_tb/uut/VSync
add wave -position insertpoint sim:/A1200_tb/uut/video_r

# 6. Protokollierung in eine Textdatei starten (vor dem Run-Befehl!)
transcript file cpu_simulation.log

echo "=== START DER CHIP-SIMULATION ==="

# 7. Kurzer Simulationslauf (anpassbar)
run 1000 ns

# 8. Protokollierung sauber schließen und wegschreiben
transcript file ""

# 9. Wellenform-Ansicht optimieren
wave zoomfull
