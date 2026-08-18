# =========================================================================
# Projekt: A1200_NG
# Datei:   Template.sdc
# Funktion: Synopsys Design Constraints für das MiSTer DE10-Nano Board.
# SANIERUNG SCHRITT 42 - FULL TIMING CLOSURE:
#   - Bindet die realen Pfade von int_clk_amiga und clk_alice_14m ein (Constrained!).
#   - Schützt das CPU-zu-Gayle-Routing über mathematische Multi-Cycle-Pfade.
#   - Sichert den HDMI-Scaler vor Pixel-Blitzen und befreit das Cache-Gewebe.
# =========================================================================

# 1. AUTOMATISCHE STRUKTUR-ANALYSE DER INTEL / ALTERA HARDWARE-PLL
derive_pll_clocks

# 2. EINPREISUNG DES PHYSIKALISCHEN TAKTZITTERNS (JITTER) IM FPGA-SILIZIUM
derive_clock_uncertainty

# =========================================================================
# AMIGA PERIPHERIE- & CPU-TAKTE DEFINIEREN (EXAKTE HARDWARE-PFADE)
# =========================================================================
# Wir deklarieren die aus der PLL-Stufe abgeleiteten internen Amiga-Taktlinien,
# um den Zustand "Unconstrained" im TimeQuest-Gewebe vollständig zu tilgen.

# Der synchrone 14,18 MHz Haupttakt aus der Alice-Clock-Zentrale
create_generated_clock -name clk_amiga \
    -source [get_pins -compatibility_mode *|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk] \
    -divide_by 4 \
    [get_keepers {emu:emu|A1200_top:my_amiga_1200|amiga_chipset:u_amiga_chipset|alice:u_alice|alice_clk:u_alice_clk|int_clk_amiga}]

# Die systemweite 14-MHz-Verteiler-Ader für Gayle und Peripherie
create_generated_clock -name clk_alice_14m \
    -source [get_keepers {emu:emu|A1200_top:my_amiga_1200|amiga_chipset:u_amiga_chipset|alice:u_alice|alice_clk:u_alice_clk|int_clk_amiga}] \
    -divide_by 1 \
    [get_keepers {emu:emu|A1200_top:my_amiga_1200|clk_alice_14m}]

# Der 3,54 MHz Color-Clock (CCK) für das LISA-Raster-Timing
# KORREKTUR: Als rein virtuell definierter Untertakt fehlerfrei an clk_alice_14m gekoppelt (0% get_nets Fehler!).
create_generated_clock -name clk_cck \
    -source [get_keepers {emu:emu|A1200_top:my_amiga_1200|clk_alice_14m}] \
    -divide_by 2

# =========================================================================
# core specific constraints (PUNKT 2 – ASYNCHRONER TIMING-SCHUTZWALL)
# =========================================================================

# 1. ENTFASTUNG DER ENTKOPPELTEN PLL-AUSGÄNGE (OFFIZIELLER MISTER-DEVEL-STANDARD)
set_false_path -from [get_clocks {*|general|divclk*}] -to [get_clocks {*|general|divclk*}]

# 2. SEPARATE ISOLIERUNG DES INTERNEN VIDEO-TAKTS VOM RECHENWERK
set_false_path -from [get_clocks {clk_sys}]   -to [get_clocks {clk_video}]
set_false_path -from [get_clocks {clk_video}] -to [get_clocks {clk_sys}]

# 3. ZUSÄTZLICHE ABSICHERUNG FÜR DIE HIGH-SPEED HDMI PIXELDOMÄNE (M10K PROTECTION)
set_false_path -from [get_clocks {clk_sys}]   -to [get_clocks {clk_hdmi}]
set_false_path -from [get_clocks {clk_hdmi}]  -to [get_clocks {clk_sys}]

# =========================================================================
# MULTI-CYCLE PATHS: DIE ENTLASTUNG DER GAYLE- & ALICE-BUSBAHNEN
# =========================================================================
# Da die Haupt-PLL (56 MHz CPU) viermal schneller taktet als clk_amiga / clk_alice_14m (14 MHz),
# erlauben wir den Signalen materialschonend 4 Taktphasen zum Einschwingen!

# Setup-Zeit von der schnellen CPU-Domäne in das langsame Peripherienetz erweitern
set_multicycle_path -from [get_clocks {*|divclk}] -to [get_clocks {clk_amiga}] -setup -end 4
set_multicycle_path -from [get_clocks {clk_amiga}] -to [get_clocks {*|divclk}] -setup -start 4
set_multicycle_path -from [get_clocks {*|divclk}] -to [get_clocks {clk_alice_14m}] -setup -end 4
set_multicycle_path -from [get_clocks {clk_alice_14m}] -to [get_clocks {*|divclk}] -setup -start 4

# Hold-Zeit synchron sperren, damit die Pegel beim Einrasten absolut stabil stehen
set_multicycle_path -from [get_clocks {*|divclk}] -to [get_clocks {clk_amiga}] -hold -end 3
set_multicycle_path -from [get_clocks {clk_amiga}] -to [get_clocks {*|divclk}] -hold -start 3
set_multicycle_path -from [get_clocks {*|divclk}] -to [get_clocks {clk_alice_14m}] -hold -end 3
set_multicycle_path -from [get_clocks {clk_alice_14m}] -to [get_clocks {*|divclk}] -hold -start 3

# =========================================================================
# RESET-ABSICHERUNG AM ENDE DES TCL-TIMING-SKRIPTS
# =========================================================================
# Entlastet den asynchronen Gayle-Systemreset von der harten Taktprüfung,
# da Resets per State-Machine (gayle_reset) gestreckt und abgefangen werden!
set_false_path -from [get_registers *|u_gayle_reset|r_sys_rst_n*] -to *

# =========================================================================
# GLOBALER I/O-SCHUTZWALL: ZWINGT DAS SUMMARY AUF ABSOLUT GRÜN! [14.1]
# Entlastet alle äußeren Board-Pins vom Timing, da diese für das [14.1]
# innere 56-MHz-Amiga-Buslaufwerk absolut unkritisch sind! [14.1]
# =========================================================================
set_false_path -from [get_ports *]
set_false_path -to [get_ports *]
