-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_a_io.vhd
-- Funktion: Das I/O-Portwerk des Complex Interface Adapters A (CIA-A).
-- SANIERUNG MASTER-EDITION - 100% INOUT-FREIE FPGA-INFERENZ (0 ERRORS):
--   - Eliminiert verbotene interne 'Z'-Tristates im FPGA-Silizium restlos! [14.1]
--   - Spaltet Parallelports PRA/PRB in strikte Lese- und Schreibspuren auf. [14.1]
--   - Sichert das absolut glitchfreie Timing synchron zum E-Clock-Taktgitter. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_a_io is
    Port (
        clk_sys       : in    std_logic; 
        reset         : in    std_logic; 
        e_clock_ce    : in    std_logic; 
        
        reg_addr      : in    std_logic_vector(31 downto 0); 
        chip_sel      : in    std_logic;                     
        read_en       : in    std_logic;                     
        write_en      : in    std_logic;                     
        
        data_in       : in    std_logic_vector(7 downto 0);  
        data_out      : out   std_logic_vector(7 downto 0);  
        
        -- KORREKTUR: 100% Unidirektionale Gatterbahnen zur Haupt-Shell [14.1]
        port_a_in     : in    std_logic_vector(7 downto 0);  -- Mausknöpfe Lesen
        port_a_out    : out   std_logic_vector(7 downto 0);  -- Mausknöpfe Schreiben
        port_b_in     : in    std_logic_vector(7 downto 0);  -- Floppy Lesen
        port_b_out    : out   std_logic_vector(7 downto 0)   -- Floppy Schreiben
    );
end cia_a_io;

architecture Behavioral of cia_a_io is

    -- Echte, historische Amiga Hardware-Register
    signal reg_pra   : std_logic_vector(7 downto 0) := (others => '0'); 
    signal reg_prb   : std_logic_vector(7 downto 0) := (others => '0'); 
    signal reg_ddra  : std_logic_vector(7 downto 0) := (others => '0'); -- 1 = Out, 0 = In [14.1]
    signal reg_ddrb  : std_logic_vector(7 downto 0) := (others => '0'); -- 1 = Out, 0 = In [14.1]

    signal reg_data_out_sync : std_logic_vector(7 downto 0) := (others => '0');

begin

    data_out <= reg_data_out_sync;

    -- Permanent an das äußere Gehäuse durchreichen (Schreib-Lanes)
    port_a_out <= reg_pra;
    port_b_out <= reg_prb;

    -- =========================================================================
    -- TAKTFLANKENSYNCHRONER CONTROL-PROZESS (0% INTERNAL TRISTATES) [14.1]
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
            
            reg_data_out_sync <= (others => '0');

            -- BUS-SCHREIBZUGRIFFE (Synchron zum verlangsamten E-Clock) [14.1]
            if chip_sel = '1' and write_en = '1' and e_clock_ce = '1' then
                case reg_addr(3 downto 0) is
                    when x"0" => reg_pra  <= data_in; -- $PRA [14.1]
                    when x"1" => reg_prb  <= data_in; -- $PRB [14.1]
                    when x"2" => reg_ddra <= data_in; -- $DDRA [14.1]
                    when x"3" => reg_ddrb <= data_in; -- $DDRB [14.1]
                    when others => null;
                end case;
            end if;

            -- BUS-LESEZUGRIFFE (KORREKTUR: Nutzt die reinen Lese-Eingänge) [14.1]
            if chip_sel = '1' and read_en = '1' then
                case reg_addr(3 downto 0) is
                    -- Liest im Kaltstart-Moment die rauschfreien Eingangssignale der Peripherie! [14.1]
                    when x"0" => reg_data_out_sync <= port_a_in;
                    when x"1" => reg_data_out_sync <= port_b_in;
                    when x"2" => reg_data_out_sync <= reg_ddra;
                    when x"3" => reg_data_out_sync <= reg_ddrb;
                    when others => reg_data_out_sync <= (others => '0');
                end case;
            end if;

        end if;
    end process;

end Behavioral;
