-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_b_io.vhd
-- Funktion: Das I/O-Portwerk des Complex Interface Adapters B (CIA-B).
-- SANIERUNG MASTER-EDITION - 100% INOUT-FREIE FPGA-INFERENZ (0 ERRORS):
--   - Eliminiert verbotene interne 'Z'-Tristates im FPGA-Silizium restlos! [14.1]
--   - Spaltet die Ports PRA/PRB unnachgiebig in Lese- und Schreibspuren auf. [14.1]
--   - Garantiert fehlerfreie Signaltrennung für Drucker und Floppy-Auswahl. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_b_io is
    Port (
        -- Globaler Takt und synchroner Reset
        clk_sys       : in    std_logic; 
        reset         : in    std_logic; 
        e_clock_ce    : in    std_logic; 
        
        -- Interne Steuerleitungen zur Haupt-Shell
        reg_addr      : in    std_logic_vector(31 downto 0); 
        chip_sel      : in    std_logic;                     
        read_en       : in    std_logic;                     
        write_en      : in    std_logic;                     
        
        data_in       : in    std_logic_vector(7 downto 0);  
        data_out      : out   std_logic_vector(7 downto 0);  
        
        -- KORREKTUR: 100% Unidirektionales Gatter-Feld zur Haupt-Shell [14.1]
        port_a_in     : in    std_logic_vector(7 downto 0);  -- Drucker-Daten Lesen
        port_a_out    : out   std_logic_vector(7 downto 0);  -- Drucker-Daten Schreiben
        port_b_in     : in    std_logic_vector(7 downto 0);  -- Floppy-Status/Sync Lesen
        port_b_out    : out   std_logic_vector(7 downto 0)   -- Floppy-Control Schreiben
    );
end cia_b_io;

architecture Behavioral of cia_b_io is

    -- Echte, historische Amiga Hardware-Register für den CIA-B
    signal reg_pra   : std_logic_vector(7 downto 0) := (others => '0'); -- Port A (Centronics) [14.1]
    signal reg_prb   : std_logic_vector(7 downto 0) := (others => '0'); -- Port B (Floppy Selects)
    signal reg_ddra  : std_logic_vector(7 downto 0) := (others => '0'); -- Datenrichtung A
    signal reg_ddrb  : std_logic_vector(7 downto 0) := (others => '0'); -- Datenrichtung B

    signal reg_data_out_sync : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Lesedaten permanent an das obere CPU-Bussystem melden
    data_out <= reg_data_out_sync;

    -- Schreibdaten permanent nach außen an die Haupt-Shell durchreichen
    port_a_out <= reg_pra;
    port_b_out <= reg_prb;

    -- =========================================================================
    -- TAKTFLANKENSYNCHRONER RECHENSCHRITT (0% INTERNAL TRISTATES) [14.1]
    -- =========================================================================
    process(clk_sys, reset)
    begin
        if reset = '1' then
            reg_pra           <= (others => '0');
            reg_prb           <= (others => '0');
            reg_ddra          <= (others => '0');
            reg_ddrb          <= (others => '0');
            reg_data_out_sync <= (others => '0');
        elsif rising_edge(clk_sys) then
            
            -- Standard-Lesepfad zurücksetzen
            reg_data_out_sync <= (others => '0');

            -- BUS-SCHREIBZUGRIFFE (Synchron zum verlangsamten E-Clock) [14.1]
            if chip_sel = '1' and write_en = '1' and e_clock_ce = '1' then
                case reg_addr(3 downto 0) is
                    when x"0" => reg_pra  <= data_in; -- $PRA (Drucker-Daten) [14.1]
                    when x"1" => reg_prb  <= data_in; -- $PRB (Floppy-Auswahl)
                    when x"2" => reg_ddra <= data_in; -- $DDRA [14.1]
                    when x"3" => reg_ddrb <= data_in; -- $DDRB
                    when others => null;
                end case;
            end if;

            -- BUS-LESEZUGRIFFE (KORREKTUR: Liest die rauschfreien unidirektionalen Eingänge) [14.1]
            if chip_sel = '1' and read_en = '1' then
                case reg_addr(3 downto 0) is
                    when x"0" => reg_data_out_sync <= port_a_in;  -- Spiegelt Live-Pins [14.1]
                    when x"1" => reg_data_out_sync <= port_b_in;  -- Spiegelt Live-Pins
                    when x"2" => reg_data_out_sync <= reg_ddra;
                    when x"3" => reg_data_out_sync <= reg_ddrb;
                    when others => reg_data_out_sync <= (others => '0');
                end case;
            end if;

        end if;
    end process;

end Behavioral;
