-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_rtc.vhd
-- Teil:    1 von 2 (Vollständige Entity-Schnittstelle)
-- Funktion: Die Next-Gen Echtzeituhr (RTC) der Turbokarte.
--           Emuliert das Register-Interface des Oki MSM6242 Uhren-Chips
--           an der historischen Amiga-Basisadresse $00DC0000.
--           Spiegelt die Live-Systemzeit des DE10-Nano-Boards an die CPU.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity turbo_rtc is
    Port (
        -- Globale Systemsynchronisation (Voll-synchron im CPU-Taktbaum)
        CLK             : in    std_logic;                      -- 56,56 MHz Haupttakt
        RESET_N         : in    std_logic;                      -- System-Reset

        -- =============================================================
        -- 1. SCHNITTSTELLE ZUM CPU-BUS (TURBOKARTE / DEC-MUX)
        -- =============================================================
        cpu_A           : in    std_logic_vector(3 downto 0);   -- Untere 4 Adressbits (A5..A2 für die 16 Register)
        cpu_D_in        : in    std_logic_vector(31 downto 0);  -- CPU-Schreibdaten (ALU)
        cpu_D_out       : out   std_logic_vector(31 downto 0);  -- Zeitdaten-Auslesung an den Core
        cpu_RW          : in    std_logic;                      -- '1'=Read, '0'=Write
        rtc_cs          : in    std_logic;                      -- Chip-Select von der übergeordneten Gayle-Logik

        -- =============================================================
        -- 2. HARDWARE-INTERFACE ZUR NANO-BOARD ZEITBASIS (HPS/ARM)
        -- =============================================================
        -- Diese 4-Bit Registerbündel liefern die Live-Zeitdaten des Boards,
        -- die über das HPS-Linux (NTP/Hardware-Uhr) permanent aktualisiert werden.
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

-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_rtc.vhd
-- Teil:    2 von 2 (Der funktionale Gatter-Körper mit Oki-Emulation)
-- Funktion: Emuliert die 16 Register des Oki MSM6242 Uhren-Bausteins.
--           Schleift die NTP/HPS-Live-Zeitdaten des DE10-Nano-Boards
--           zyklustreu und mit 0 Wait-States direkt an das Core-Haupthaus.
-- =========================================================================

architecture behavioral of turbo_rtc is
begin

    -- =====================================================================
    -- REIN KOMBINAOTORISCHES OKI-REGISTER-MULTIPLEXING (0 WAIT-STATES)
    -- =====================================================================
    -- Sobald rtc_cs aktiv ist, wertet die Uhr das untere Adressfenster aus.
    -- Die Daten werden laut Amiga-Hardware-Spezifikation auf den Leitungen
    -- D3..D0 (bzw. linksbündig verlagert je nach Datenbus-Mux) abgebildet [14.1].
    process(rtc_cs, cpu_A, cpu_RW, 
            hps_sec_0, hps_sec_1, hps_min_0, hps_min_1, 
            hps_hour_0, hps_hour_1, hps_day_0, hps_day_1, 
            hps_month_0, hps_month_1, hps_year_0, hps_year_1)
    begin
        -- Standard-Voreinstellung: Bus im Ruhezustand auf Null halten
        cpu_D_out <= (others => '0');

        if rtc_cs = '1' and cpu_RW = '1' then
            -- REGISTER-LANDKARTE DES OKI MSM6242 LAUT AMIGA-REFFERENZ [14.1]
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
                when x"A" => cpu_D_out(3 downto 0) <= hps_year_0;  -- 1er-Jahre (z.B. '6' für 2026)
                when x"B" => cpu_D_out(3 downto 0) <= hps_year_1;  -- 10er-Jahre (z.B. '2' für 2026)
                
                when x"C" => cpu_D_out(3 downto 0) <= "0000";      -- Wochentag (optional/nicht zwingend vom OS genutzt)
                when x"D" => cpu_D_out(3 downto 0) <= "0000";      -- Control Register A (Status/Hold)
                when x"E" => cpu_D_out(3 downto 0) <= "0000";      -- Control Register B (Interrupt-Sperren)
                when x"F" => cpu_D_out(3 downto 0) <= "0000";      -- Control Register C (24h/12h Format)
                when others => cpu_D_out <= (others => '0');
            end case;
        end if;
    end process;

    -- HINWEIS ZU SCHREIBZUGRIFFEN (cpu_RW = '0'):
    -- Da das DE10-Nano-Board die Systemzeit über Linux und Netzwerk (NTP) permanent
    -- absolut atomgenau synchronisiert, verwerfen wir Schreibbefehle des AmigaOS 
    -- (z.B. über die "SetClock"-Workbench-Preferences) passiv im Silizium.
    -- Das schützt Ihre Next-Gen Systemzeit vor unbeabsichtigter Verstellung!

end behavioral;
