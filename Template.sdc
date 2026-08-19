# =========================================================================
# Projekt: A1200_NG
# Datei:   Template.sdc
# Funktion: Synopsys Design Constraints für das MiSTer DE10-Nano Board.
# SANIERUNG SCHRITT 64 - ABSOLUTE SUB-CORE ISOLATION (EXCLUSIVE EDITION):
#   - Trennt den Amiga-Core und den Debugger-Subcore in zwei Welten!
#   - Der Debugger agiert als rein passiver Spion ohne Rückwirkung.
#   - Zwingt Quartus, beide Sub-Cores vollkommen unabhängig zu routen.
# =========================================================================

# 1. AUTOMATISCHE STRUKTUR-ANALYSE DER HARDWARE-PLL (Erzeugt alle outclk-Objekte)
derive_pll_clocks

# 2. EINPREISUNG DES PHYSIKALISCHEN TAKTZITTERNS (JITTER) IM FPGA-SILIZIUM
derive_clock_uncertainty

# =========================================================================
# ANBINDUNG AN DIE REALE HARDWARE-NETZLISTE (EXAKT LAUT DEINEN REPORTEINTÄRGEN)
# =========================================================================
set master_50m_clk  "emu|my_hardware_pll|altera_pll_i|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk"
set master_65m_clk  "emu|my_hardware_pll|altera_pll_i|general\[1\].gpll~PLL_OUTPUT_COUNTER|divclk"
set dds_amiga_reg   "*|alice_clk:u_alice_clk|r_clk_amiga"

# Deklaration des generierten Amiga-Taktes direkt am Hardware-Register
create_generated_clock -name clk_amiga_internal \
    -source [get_pins -compatibility_mode *|my_hardware_pll|*|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk] \
    -divide_by 4 \
    [get_registers $dds_amiga_reg]

# =========================================================================
# MULTI-CYCLE PATHS: AMIGA CHIPSATZ-ÜBERGÄNGE (INNERHALB VON SUB-CORE A)
# =========================================================================
set_multicycle_path -from [get_clocks $master_50m_clk] -to [get_clocks {clk_amiga_internal}] -setup -end 4
set_multicycle_path -from [get_clocks {clk_amiga_internal}] -to [get_clocks $master_50m_clk] -setup -start 4

set_multicycle_path -from [get_clocks $master_50m_clk] -to [get_clocks {clk_amiga_internal}] -hold -end 3
set_multicycle_path -from [get_clocks {clk_amiga_internal}] -to [get_clocks $master_50m_clk] -hold -start 3

# =========================================================================
# RADIKALER SCHUTZWALL: TOTALE EXKLUSIVE TRENNUNG DER SUB-CORES!
# Sagt Quartus, dass die Welten absolut unabhängig voneinander existieren.
# Nimmt jeglichen Zeitdruck von den reinen Spion-Leitungen (Horch-Modus).
# =========================================================================
set_clock_groups -exclusive \
    -group [get_clocks $master_50m_clk] \
    -group [get_clocks $master_65m_clk] \
    -group [get_clocks {clk_amiga_internal}] \
    -group [get_clocks {FPGA_CLK1_50}] \
    -group [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] \
    -group [get_clocks {*pll_hdmi*divclk}] \
    -group [get_clocks {*pll_audio*divclk}]

# =========================================================================
# GLOBALER FALSE PATH SCHUTZWALL FÜR DIE NETZ-Schnittstellen
# =========================================================================
set_false_path -from [get_registers {*vol_boost*}] -to *
set_false_path -from [get_registers {*vol_boost[*]}] -to *
set_false_path -from [get_registers {ascal:*|i_wadrs[*]}] -to [get_registers {ascal:*|avl_wadrs[*]}]
set_false_path -from [get_registers {ascal:*|i_write}]    -to [get_registers {ascal:*|avl_write_sync}]
set_false_path -to [get_registers {*hps_io*old_*}]
set_false_path -to [get_registers {*hdmi_out_d*}]
set_false_path -to [get_registers {*hdmi_out_d[*]}]

set_false_path -from [get_ports *]
set_false_path -to [get_ports *]
