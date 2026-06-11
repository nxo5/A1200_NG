# =========================================================================
# Projekt: A1200_NG
# Datei:   template.qip / template.sdc
# Teil:    1 von 2 (Automatische PLL-Takterkennung)
# Funktion: Synopsys Design Constraints für das MiSTer DE10-Nano Board.
#           PUNKT 2: Automatische Erkennung der PLL-Frequenzen und des Jitters.
# =========================================================================

# 1. AUTOMATISCHE STRUKTUR-ANALYSE DER INTEL / ALTERA HARDWARE-PLL
# Berechnet im Flug alle abgeleiteten Frequenzen (clk_sys, clk_video etc.)
derive_pll_clocks

# 2. EINPREISUNG DES PHYSIKALISCHEN TAKTZITTERNS (JITTER) IM FPGA-SILIZIUM
# Zwingt den Analyzer, das thermische Rauschen der Gatter unbestechlich zu prüfen
derive_clock_uncertainty

# =========================================================================
# # core specific constraints (FOLGT IN TEIL 2)
# =========================================================================
# =========================================================================
# # core specific constraints (PUNKT 2 – ASYNCHRONER TIMING-SCHUTZWALL)
# Trennt den CPU-Speicherraum unbestechlich von den Video-Taktbereichen!
# =========================================================================

# 1. ENTFASTUNG DER ENTKOPPELTEN PLL-AUSGÄNGE (OFFIZIELLER MISTER-DEVEL-STANDARD)
# Schneidet alle asynchronen Taktübergänge der Altera-PLL-Ausgänge im Analyzer ab
set_false_path -from [get_clocks {*|general|divclk*}] -to [get_clocks {*|general|divclk*}]

# 2. SEPARATE ISOLIERUNG DES INTERNEN VIDEO-TAKTS VOM RECHENWERK
# Schützt das BRAM vor zeitkritischen Falschberechnungen zwischen Core und Scaler
set_false_path -from [get_clocks {clk_sys}]   -to [get_clocks {clk_video}]
set_false_path -from [get_clocks {clk_video}] -to [get_clocks {clk_sys}]

# 3. ZUSÄTZLICHE ABSICHERUNG FÜR DIE HIGH-SPEED HDMI PIXELDOMÄNE (M10K PROTECTION)
# Verriegelt jegliches fälschliche Timing-Checking in den asynchronen Zeilenpuffern
set_false_path -from [get_clocks {clk_sys}]   -to [get_clocks {clk_hdmi}]
set_false_path -from [get_clocks {clk_hdmi}]  -to [get_clocks {clk_sys}]
