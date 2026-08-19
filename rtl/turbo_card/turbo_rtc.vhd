-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_rtc.vhd
-- Funktion: Die Next-Gen Echtzeituhr (RTC) der Turbokarte.
--           Emuliert das Register-Interface des Oki MSM6242 Uhren-Chips
--           an der historischen Amiga-Basisadresse $00DC0000.
-- SANIERUNG Schritt 73 - GATTERREINE REINIGUNG (0 ERRORS):
--   - Entfernt die ungenutzten Pins CLK und RESET_N restlos aus der Entity! [14.1]
--   - Schützt das HPS-Zeitbündel rein passiv vor Überschreibversuchen. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity turbo_rtc is
    Port (
        -- =============================================================
        -- 1. SCHNITTSTELLE ZUM CPU-BUS (TURBOKARTE / DEC-MUX)
        -- =============================================================
        cpu_A           : in    std_logic_vector(3 downto 0);   -- Untere 4 Adressbits (A5..A2 für die 16 Register)
        cpu_D_in        : in    std_logic_vector(31 downto 0);  -- CPU-Schreibdaten (ALU)
        cpu_D_out       : out   std_logic_vector(31 downto 0);  -- Zeitdaten-Auslesung an den Core
        cpu_RW          : in    std_logic;                      -- '1'=Read, '0'=Write
        rtc_cs          : in    std_logic;                      -- Chip-Select von der Gayle-Logik

        -- =============================================================
        -- 2. HARDWARE-INTERFACE ZUR NANO-BOARD ZEITBASIS (HPS/ARM)
        -- =============================================================
        hps_sec_0       : in    std_logic_vector(3 downto 0);   -- Sekunden (Einer-Stelle, 0-9)
        hps_sec_1       : in    std_logic_vector(3 downto 0);   -- Sekunden (Zehner-Stelle, 0-5)
        hps_min_0       : in    std_logic_vector(3 downto 0);   -- Minuten (Einer-Stelle, 0-9)
        hps_min_1       : in    std_logic_vector(3 downto 0);   -- Minuten (Zehner-Stelle, 0-5)
        hps_hour_0      : in    std_logic_vector(3 downto 0);   -- Stunden (Einer-Stelle, 0-9)
        hps_hour_1      : in    std_logic_vector(3 downto 0);   -- Stunden (Zehner-Stelle, 0-2)
        hps_day_0       : in    std_logic_vector(3 downto 0);   -- Tag (Einer-Stelle, 0-9)
        hps_day_1       : in    std_logic_vector(3 downto 0);   -- Tag (Zehner-Stelle, 0-3)
        hps_month_0     : in    std_logic_vector(3 downto 0);   -- Monat (Einer-Stelle, 0-9)
        hps_month_1     : in    std_logic_vector(3 downto 0);   -- Monat (Zehner-Stelle, 0-1)
        hps_year_0      : in    std_logic_vector(3 downto 0);   -- Jahr (Einer-Stelle, 0-9)
        hps_year_1      : in    std_logic_vector(3 downto 0)    -- Jahr (Zehner-Stelle, 0-9)
    );
end turbo_rtc;

architecture behavioral of turbo_rtc is
begin

    -- =====================================================================
    -- REIN KOMBINAOTORISCHES OKI-REGISTER-MULTIPLEXING (0 WAIT-STATES)
    -- =====================================================================
    process(rtc_cs, cpu_A, cpu_RW, 
            hps_sec_0, hps_sec_1, hps_min_0, hps_min_1, 
            hps_hour_0, hps_hour_1, hps_day_0, hps_day_1, 
            hps_month_0, hps_month_1, hps_year_0, hps_year_1)
    begin
        -- Standard-Voreinstellung: Bus im Ruhezustand auf Null halten
        cpu_D_out <= (others => '0');

        if rtc_cs = '1' and cpu_RW = '1' then
            case cpu_A is
                when x"0" => cpu_D_out(3 downto 0) <= hps_sec_0;   -- 1er-Sekunden
                when x"1" => cpu_D_out(3 downto 0) <= hps_sec_1;   -- 10er-Sekunden
                when x"2" => cpu_D_out(3 downto 0) <= hps_min_0;   -- 1er-Minuten
                when x"3" => cpu_D_out(3 downto 0) <= hps_min_1;   -- 10er-Minuten
                when x"4" => cpu_D_out(3 downto 0) <= hps_hour_0;  -- 1er-Stunden
                when x"5" => cpu_D_out(3 downto 0) <= hps_hour_1;  -- 10er-Stunden
                
                when x"6" => cpu_D_out(3 downto 0) <= hps_day_0;   -- 1er-Tage
                when x"7" => cpu_D_out(3 downto 0) <= hps_day_1;   -- 10er-Tage
                when x"8" => cpu_D_out(3 downto 0) <= hps_month_0; -- 1er-Monate
                when x"9" => cpu_D_out(3 downto 0) <= hps_month_1; -- 10er-Monate
                when x"A" => cpu_D_out(3 downto 0) <= hps_year_0;  -- 1er-Jahre
                when x"B" => cpu_D_out(3 downto 0) <= hps_year_1;  -- 10er-Jahre
                
                when x"C" => cpu_D_out(3 downto 0) <= "0000";      -- Wochentag
                when x"D" => cpu_D_out(3 downto 0) <= "0000";      -- Control Register A
                when x"E" => cpu_D_out(3 downto 0) <= "0000";      -- Control Register B
                when x"F" => cpu_D_out(3 downto 0) <= "0000";      -- Control Register C
                when others => cpu_D_out <= (others => '0');
            end case;
        end if;
    end process;

end behavioral;
