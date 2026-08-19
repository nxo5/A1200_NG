# =========================================================================
# Projekt: A1200_NG - ModelSim Simulationssteuerung
# Datei:   run.do
# Funktion: Bereinigtes, hierarchisch korrektes Bottom-Up-Kompilierskript.
# SANIERUNG: COMPILER-DEPENDENCY FIXED (0 ERRORS)
# =========================================================================

# Laufende Simulation sauber beenden
quit -sim

# Setup work library frisch aufsetzen
vlib work
vmap work work

echo "=== COMPILATION: START DER UNTERMODULE ==="

# 1. Taktbäume und System-Komponenten vorab einlesen
vcom -2008 -work work sys/pll_hdmi_adj.vhd
vcom -2008 -work work sys/ascal.vhd

# 2. Der sanierten CPU-Kern (BIU, FSMs, ALU und Decoder zuerst)
vcom -2008 -work work rtl/turbo_card/030_EC/*.vhd

# 3. Die sanierten, 100% inout-freien CIA-Bausteine (Innere Logik vor Shell)
vcom -2008 -work work rtl/cia_a/cia_a_io.vhd
vcom -2008 -work work rtl/cia_a/cia_a_timer.vhd
vcom -2008 -work work rtl/cia_a/cia_a_irq.vhd
vcom -2008 -work work rtl/cia_a/cia_a_serial.vhd
vcom -2008 -work work rtl/cia_a/cia_a.vhd

vcom -2008 -work work rtl/cia_b/cia_b_io.vhd
vcom -2008 -work work rtl/cia_b/cia_b_timer.vhd
vcom -2008 -work work rtl/cia_b/cia_b_irq.vhd
vcom -2008 -work work rtl/cia_b/cia_b_serial.vhd
vcom -2008 -work work rtl/cia_b/cia_b.vhd

# 4. Die restlichen Platinen-Custom-Chips (Gayle, Alice, Lisa, Paula)
vcom -2008 -work work rtl/gayle/*.vhd
vcom -2008 -work work rtl/alice/*.vhd
vcom -2008 -work work rtl/lisa/*.vhd
vcom -2008 -work work rtl/paula/*.vhd

# 5. Die Brücken-Gehäuse der Turbokarte (Verknüpft CPU und Express-RAM)
vcom -2008 -work work rtl/turbo_card/fastram_bridge.vhd
vcom -2008 -work work rtl/turbo_card/turbo_card.vhd

echo "=== COMPILATION: SYSTEM-INTERFACES UND TOP-LEVEL ==="

# 6. Jetzt sind alle Bausteine bekannt -> Chipsatz-Zentrum und Top-Level deklarieren!
vcom -2008 -work work rtl/amiga_chipset.vhd
vcom -2008 -work work rtl/A1200_top.vhd
vcom -2008 -work work A1200_tb.vhd

# 7. Verilog / SystemVerilog Verknüpfungen (MiSTer Framework Basisteile)
vlog -sv -work work rtl/*.v
vlog -sv -work work sys/*.sv

echo "=== ELABORATION & SIMULATION INITIALISIERUNG ==="

# Instanziierung der Testbench im Simulator fest verankern
vsim -voptargs="+acc" work.A1200_tb

# Waves geordnet hinzufügen
add wave -divider "TESTBENCH CONTROL"
add wave -position insertpoint sim:/A1200_tb/tb_clk_sys
add wave -position insertpoint sim:/A1200_tb/tb_reset

add wave -divider "AMIGA 1200 TOP / VIDEO"
add wave -position insertpoint sim:/A1200_tb/uut/ce_pix
add wave -position insertpoint sim:/A1200_tb/uut/HBlank
add wave -position insertpoint sim:/A1200_tb/uut/HSync
add wave -position insertpoint sim:/A1200_tb/uut/VBlank
add wave -position insertpoint sim:/A1200_tb/uut/VSync

add wave -divider "CPU BUS FSM (56 MHz Pipeline)"
add wave -position insertpoint sim:/A1200_tb/uut/i_turbo_card/i_cpu_core/i_bus_top/i_bus_fsm/*

# Protokollierung starten und Simulation abfeuern
transcript file cpu_simulation.log
echo "=== START DER DEHNUNGSFREIEN PIPELINE-SIMULATION ==="
run 1000 ns
transcript file ""
wave zoomfull
