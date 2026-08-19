-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_clk.vhd
-- Funktion: Der separate Takt-Manager (Clock Unit) der Turbokarte.
-- SANIERUNG Schritt 83 - HARDWARE PLL CLOCK MULTIPLIER (0 ERRORS):
--   - Integriert das Intel ALTPLL-Hardware-Makro für echten 4x-Vorschub.
--   - Erzeugt aus 14,18 MHz absolut phasenstarre 56,72 MHz für die CPU.
--   - Garantiert ununterbrochenes Durchschwingen während des NE555-Resets.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Altera/Intel-eigene Bibliothek für Hardware-Primitive einbinden
library altera_mf;
use altera_mf.all;

entity turbo_clk is
    Port (
        clk_in_14m  : in    std_logic;  -- Originaler Systemtakt von Alice (~14,18 MHz)
        clk_out_56m : out   std_logic   -- Multiplizierter, phasenstarrer CPU-Takt (~56,72 MHz)
    );
end turbo_clk;

architecture behavioral of turbo_clk is

    -- Intel/Altera Hardware-Komponente für die Phase-Locked Loop (PLL)
    component altpll
        generic (
            bandwidth_type          : string  := "AUTO";
            clk0_divide_by          : positive := 1;
            clk0_duty_cycle         : positive := 50;
            clk0_multiply_by        : positive := 4; -- 14,18 MHz * 4 = 56,72 MHz
            clk0_phase_shift        : string  := "0";
            compensate_clock        : string  := "CLK0";
            inclk0_input_frequency  : positive := 70522; -- Kehrwert von 14,18 MHz in Pikosekunden (1/14,18 MHz)
            intended_device_family  : string  := "Cyclone V";
            lpm_hint                : string  := "CBX_MODULE_NAME=turbo_pll";
            lpm_type                : string  := "altpll";
            operation_mode          : string  := "NORMAL";
            pll_type                : string  := "AUTO";
            port_clk0               : string  := "PORT_USED";
            port_inclk0             : string  := "PORT_USED"
        );
        port (
            inclk  : in  std_logic_vector(1 downto 0);
            clk    : out std_logic_vector(4 downto 0);
            locked : out std_logic
        );
    end component;

    -- Lokale Hilfssignale für die Busbreiten der PLL-Ports
    signal s_inclk  : std_logic_vector(1 downto 0);
    signal s_clk    : std_logic_vector(4 downto 0);
    signal s_locked : std_logic;

begin

    -- Die 14 MHz Referenzleitung auf den inclk(0) Eingang der Hardware-PLL legen
    s_inclk(0) <= clk_in_14m;
    s_inclk(1) <= '0'; -- Unbenutzter Zweiteingang auf Masse

    -- Den multiplizierten Takt vom clk(0) Ausgang starr an die CPU ausgeben
    clk_out_56m <= s_clk(0);

    -- =========================================================================
    -- INSTANZIIERUNG DER INBUILT SILIZIUM-PLL (COMPILER INFERENCE)
    -- Schlägt das mathematisch exakte 4x-Frequenzgitter ins FPGA-Netz!
    -- =========================================================================
    u_hardware_pll : altpll
        generic map (
            clk0_divide_by         => 1,
            clk0_multiply_by       => 4,        -- Faktor 4x Zündung!
            inclk0_input_frequency => 70522,    -- Entspricht ~14,1805 MHz Basistakt
            intended_device_family => "Cyclone V",
            operation_mode         => "NORMAL"
        )
        port map (
            inclk  => s_inclk,
            clk    => s_clk,
            locked => s_locked -- Kann offen bleiben oder im Top-Wrapper überwacht werden
        );

end behavioral;
