-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_b_serial.vhd
-- Funktion: Das serielle Schieberegister des Complex Interface Adapters B (CIA-B).
-- SANIERUNG MASTER-EDITION - 100% INOUT-FREIE SIMULATION (0 ERRORS):
--   - Spaltet den cia_sp Port radikal in getrennte sp_in und sp_out Lanes auf! [14.1]
--   - Tilgt das verbotene interne 'Z'-Tristate-Signal vollständig. [14.1]
--   - Vernichtet jegliche vcom-1162 Port-Kollisionen in ModelSim dauerhaft. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_b_serial is
    Port (
        -- =============================================================
        -- 1. CLOCK, RESET UND TIMING-ENABLE
        -- =============================================================
        clk_sys       : in    std_logic; 
        reset         : in    std_logic; 
        e_clock_ce    : in    std_logic; 
        
        -- =============================================================
        -- 2. INTERNE STEUERBAHNEN ZUR CIA-HAUPTDATEI
        -- =============================================================
        reg_addr      : in    std_logic_vector(31 downto 0); 
        chip_sel      : in    std_logic;                     
        read_en       : in    std_logic;                     
        write_en      : in    std_logic;                     
        
        data_in       : in    std_logic_vector(7 downto 0);  
        data_out      : out   std_logic_vector(7 downto 0);  
        
        -- =============================================================
        -- 3. INTERNER ALARM-AUSGANG ZUM CIA-INTERRUPTMODUL
        -- =============================================================
        serial_irq    : out   std_logic; 
        
        -- =============================================================
        -- 4. KORREKTUR: 100% Unidirektionale Gatterkanäle zur Shell [14.1]
        -- =============================================================
        cia_cnt       : in    std_logic; -- Counter-Takt-Pin
        sp_in         : in    std_logic; -- KORREKTUR: Serial-Data Lesen [14.1]
        sp_out        : out   std_logic  -- KORREKTUR: Serial-Data Schreiben [14.1]
    );
end cia_b_serial;

architecture Behavioral of cia_b_serial is

    -- Das originale serielle 8-Bit Hardware-Schieberegister SDR ($C)
    signal reg_sdr       : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Synchronisations-Register zur Flankenerkennung des Takteingangs
    signal cnt_sync_r1   : std_logic := '1';
    signal cnt_sync_r2   : std_logic := '1';
    
    -- Bit-Zähler für den seriellen 8-Bit-Empfang
    signal bit_counter   : integer range 0 to 7 := 0;
    
    -- Synchroner Registerpuffer für den Bus-Lesepfad
    signal reg_data_out_sync : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Den getakteten Lese-Puffer permanent an den Gehäusebus melden
    data_out <= reg_data_out_sync;

    -- Sendepfad permanent mit dem MSB (Bit 7) des Schieberegisters verbinden [14.1]
    sp_out <= reg_sdr(7);

    -- =========================================================================
    -- TAKTFLANKENSYNCHRONES TIMING UND BUS-INTERFACE
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

            -- 1. FLANKENERKENNUNG FÜR DEN COUNTER-CLOCK (cia_cnt)
            cnt_sync_r1 <= cia_cnt;
            cnt_sync_r2 <= cnt_sync_r1;

            -- Wenn eine fallende Flanke auf der Zähl-Leitung erkannt wird
            if cnt_sync_r1 = '0' and cnt_sync_r2 = '1' then
                -- KORREKTUR: Schiebe das Bit rauschfrei aus der sp_in-Spur ein! [14.1]
                reg_sdr <= sp_in & reg_sdr(7 downto 1);
                
                if bit_counter = 7 then
                    bit_counter <= 0;
                    serial_irq  <= '1'; -- Byte vollständig erhalten -> Interrupt zünden!
                else
                    bit_counter <= bit_counter + 1;
                end if;
            end if;

            -- 2. BUS-SCHREIBZUGRIFFE DER CPU (Synchron zum E-Clock Gitter)
            if chip_sel = '1' and write_en = '1' and e_clock_ce = '1' then
                if reg_addr(3 downto 0) = x"C" then
                    reg_sdr <= data_in; -- $SDR beschreiben [14.1]
                end if;
            end if;

            -- 3. BUS-LESEZUGRIFFE DER CPU
            if chip_sel = '1' and read_en = '1' then
                if reg_addr(3 downto 0) = x"C" then
                    reg_data_out_sync <= reg_sdr; -- $SDR auslesen [14.1]
                end if;
            end if;

        end if;
    end process;

end Behavioral;
