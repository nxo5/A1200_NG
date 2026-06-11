-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_clear_unit.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle)
-- Funktion: Sub-Modul des L1-Caches. Kapselt exklusiv den synchronen 
--           256-Takt-Löschzähler für die Valid-Matrizen zur echten M10K-
--           Ressourcenschonung im Cyclone-V-FPGA.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_clear_unit is
    Port (
        -- Globale Systemsynchronisation
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Kontrollkanäle vom CACR-Register / Cache-Management
        cacr_ci             : in    std_logic;                      -- Impuls: Lösche Instruction Cache
        cacr_cd             : in    std_logic;                      -- Impuls: Lösche Data Cache
        
        -- Statussignale an das übergeordnete Cache-Subsystem
        cache_clearing      : out   std_logic;                      -- '1' blockiert alle Hit/Miss-Evaluierungen
        clear_idx           : out   integer range 0 to 255;         -- Aktueller Lösch-Index für die Zeilen-Adressierung
        clear_pulse         : out   std_logic                       -- Steuerimpuls zum aktiven Ausnullen im M10K
    );
end cpu_030_ec_cache_clear_unit;

architecture behavioral of cpu_030_ec_cache_clear_unit is

    -- Interner Zähler für die 256 Cache-Sets
    signal r_clear_counter : integer range 0 to 255 := 0;
    signal r_clearing      : std_logic := '1'; -- Startet aktiv nach Power-On

begin

    -- Permanente Durchleitung der internen Zustandsregister an die Außenhaut
    cache_clearing <= r_clearing;
    clear_idx      <= r_clear_counter;

    -- =====================================================================
    -- SYNCHRONER CONTROL-PROZESS: HARDWAREGERECHTE INITIALISIERUNG
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            r_clear_counter <= 0;
            r_clearing      <= '1'; -- Erzwinge Schutzraum beim Einschalten
            clear_pulse     <= '0';

        elsif rising_edge(CLK) then
            clear_pulse <= '0';

            -- 1. HARDWAREGERECHTE SEQUENZIELLE LÖSCH-ZUSTANDSMASCHINE
            if r_clearing = '1' then
                clear_pulse <= '1'; -- Signalisiert der Matrix: Zeile jetzt nullen!
                
                if r_clear_counter = 255 then
                    r_clearing  <= '0'; -- Initialisierung nach 256 Takten stabil beendet!
                    clear_pulse <= '0';
                else
                    r_clear_counter <= r_clear_counter + 1;
                end if;

            -- 2. REGULÄRE ÜBERWACHUNG IM FLIESSBAND-BETRIEB
            else
                -- SOFTWARE-GESTEUERTER GLOBALER CACHE-CLEAR (CACR-BEFEHL)
                -- Zündet den Löschzähler im Flug neu, ohne den Core abstürzen zu lassen
                if cacr_ci = '1' or cacr_cd = '1' then
                    r_clear_counter <= 0;
                    r_clearing      <= '1'; -- Aktiviert den Schutzraum erneut
                end if;
            end if;
        end if;
    end process;

end behavioral;
