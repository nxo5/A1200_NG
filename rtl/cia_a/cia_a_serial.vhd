-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_a_serial.vhd
-- Funktion: Das serielle Schieberegister des Complex Interface Adapters A (CIA-A).
--           Verwaltet das SDR-Register ($C) für das Amiga-Tastaturprotokoll.
-- IMPLEMENTIERUNG SCHRITT 3:
--   - Native 8-Bit SDR-Registersteuerung ($C) integriert. [14.1]
--   - Flankenerkennung für den Keyboard-Clock (cia_cnt) zur Bit-Übernahme. [14.1]
--   - Automatisches Zünden des serial_irq nach exakt 8 empfangenen Bits. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_a_serial is
    Port (
        -- =============================================================
        -- 1. CLOCK, RESET UND TIMING-ENABLE
        -- =============================================================
        clk_sys       : in    std_logic; -- Der schnelle Basistakt des Gesamtsystems
        reset         : in    std_logic; -- Globaler System-Reset
        e_clock_ce    : in    std_logic; -- Das verlangsamte E-Clock Takt-Enable (~0,71 MHz)
        
        -- =============================================================
        -- 2. INTERNE STEUERBAHNEN ZUR CIA-HAUPTDATEI
        -- =============================================================
        reg_addr      : in    std_logic_vector(31 downto 0); -- Ausrichtung auf den 32-Bit-Busrahmen
        chip_sel      : in    std_logic;                     -- Internes Aktivierungssignal (Aktiv '1')
        read_en       : in    std_logic;                     -- Lese-Anforderung der CPU
        write_en      : in    std_logic;                     -- Schreib-Anforderung der CPU
        
        -- Der chipinterne 8-Bit-Datenbus
        data_in       : in    std_logic_vector(7 downto 0);  -- Daten von der CPU zum Schieberegister
        data_out      : out   std_logic_vector(7 downto 0);  -- Daten vom Schieberegister zur CPU
        
        -- =============================================================
        -- 3. INTERNER ALARM-AUSGANG ZUM CIA-INTERRUPTMODUL
        -- =============================================================
        serial_irq    : out   std_logic; -- Impuls bei vollem/leerem Schieberegister
        
        -- =============================================================
        -- 4. AUSSENWELT: PHYSISCHE SCHALTPINS (Direkt zur Chip-Entity)
        -- =============================================================
        cia_cnt       : in    std_logic; -- Taktleitung der Tastatur (Keyboard Clock)
        cia_sp        : inout std_logic  -- Datenleitung der Tastatur (Keyboard Data)
    );
end cia_a_serial;

architecture Behavioral of cia_a_serial is

    -- Das originale serielle 8-Bit Hardware-Schieberegister SDR ($C)
    signal reg_sdr       : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Synchronisations-Register zur Flankenerkennung des Keyboard-Clocks
    signal cnt_sync_r1   : std_logic := '1';
    signal cnt_sync_r2   : std_logic := '1';
    
    -- Bit-Zähler für den seriellen 8-Bit-Empfang
    signal bit_counter   : integer range 0 to 7 := 0;
    
    -- Synchroner Registerpuffer für den Bus-Lesepfad
    signal reg_data_out_sync : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Physische Tristate-Kopplung für den SP-Pin (Standardmäßig als Eingang für Tastatur-Daten)
    cia_sp <= 'Z';

    -- Den getakteten Lese-Puffer permanent an den Gehäusebus melden
    data_out <= reg_data_out_sync;

    -- =========================================================================
    -- TACTFLANKENSYNCHRONES EMPFANGS- TIMING UND BUS-INTERFACE
    -- =========================================================================
    process(clk_sys, reset)
    begin
        if reset = '1' then
            reg_sdr           <= (others => '0');
            cnt_sync_r1       <= '1';
            cnt_sync_r2       <= '1';
            bit_counter       <= 0;
            reg_data_out_sync <= (others => '0');
            serial_irq        <= '0';
        elsif rising_edge(clk_sys) then
            
            -- Standard-Impulse bei jedem Takt zurücksetzen
            serial_irq        <= '0';
            reg_data_out_sync <= (others => '0');

            -- 1. FLANKENERKENNUNG FÜR DEN KEYBOARD-CLOCK (cia_cnt) [14.1]
            cnt_sync_r1 <= cia_cnt;
            cnt_sync_r2 <= cnt_sync_r1;

            -- Wenn eine fallende Flanke auf der Tastatur-Taktleitung erkannt wird
            if cnt_sync_r1 = '0' and cnt_sync_r2 = '1' then
                -- Schiebe das aktuelle Bit vom SP-Pin linksbündig ein [14.1]
                reg_sdr <= cia_sp & reg_sdr(7 downto 1);
                
                if bit_counter = 7 then
                    bit_counter <= 0;
                    serial_irq  <= '1'; -- Byte vollständig erhalten -> Interrupt zünden! [14.1]
                else
                    bit_counter <= bit_counter + 1;
                end if;
            end if;

            -- 2. BUS-SCHREIBZUGRIFFE DER CPU (Synchron zum E-Clock Gitter) [14.1]
            if chip_sel = '1' and write_en = '1' and e_clock_ce = '1' then
                if reg_addr(3 downto 0) = x"C" then
                    reg_sdr <= data_in; -- $SDR beschreiben (z.B. für Sendevorgänge) [14.1]
                end if;
            end if;

            -- 3. BUS-LESEZUGRIFFE DER CPU (CPU holt empfangene Tastaturdaten ab) [14.1]
            if chip_sel = '1' and read_en = '1' then
                if reg_addr(3 downto 0) = x"C" then
                    reg_data_out_sync <= reg_sdr; -- $SDR auslesen [14.1]
                end if;
            end if;

        end if;
    end process;

end Behavioral;
