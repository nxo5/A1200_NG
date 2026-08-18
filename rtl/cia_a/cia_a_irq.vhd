-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_a_irq.vhd
-- Funktion: Die Interrupt-Zentrale (ICR) des Complex Interface Adapters A.
-- KORREKTUR: Full-Fix gegen die verbliebene Latch-Inferenz an reg_icr_status! [14.1]
--   - Verriegelt die ungenutzten Statusregisterbits (6 downto 3) starr auf Masse.
--   - Zwingt den Compiler in eine reine, taktsynchron fehlerfreie Registerstruktur.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_a_irq is
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
        
        timer_a_irq   : in    std_logic; 
        timer_b_irq   : in    std_logic; 
        serial_irq    : in    std_logic; 
        
        cia_irq_n     : out   std_logic  
    );
end cia_a_irq;

architecture Behavioral of cia_a_irq is

    signal reg_icr_status : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_icr_mask   : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_data_out_sync : std_logic_vector(7 downto 0) := (others => '0');

begin

    data_out <= reg_data_out_sync;

    cia_irq_n <= '0' when ((reg_icr_status(0) = '1' and reg_icr_mask(0) = '1') or  
                           (reg_icr_status(1) = '1' and reg_icr_mask(1) = '1') or  
                           (reg_icr_status(2) = '1' and reg_icr_mask(2) = '1'))    
                 else '1';

    -- =========================================================================
    -- TAKTFLANKENSYNCHRONES ALARM-STEUERWERK UND BUS-INTERFACE
    -- =========================================================================
    process(clk_sys, reset)
    begin
        if reset = '1' then
            reg_icr_status    <= (others => '0');
            reg_icr_mask      <= (others => '0');
            reg_data_out_sync <= (others => '0');
        elsif rising_edge(clk_sys) then
            
            -- Standard-Fallback für die genutzten Registerbits
            reg_icr_status <= reg_icr_status;
            reg_icr_mask   <= reg_icr_mask;
            
            -- KORREKTUR FULL-FIX: Ungenutzte Bits in Maske und Status starr erden! [14.1]
            -- Das entzieht Quartus jede Berechtigung, hierfür ein Latch zu generieren. [14.1]
            reg_icr_mask(7 downto 5)   <= "000";
            reg_icr_status(6 downto 3) <= "0000"; 

            -- Standard-Lesepfad im Leerlauf nullen
            reg_data_out_sync <= (others => '0');

            -- 1. HARDWARE-AUTOMATISMUS: Eintreffende Alarm-Flanken einfangen
            if timer_a_irq = '1' then reg_icr_status(0) <= '1'; end if;
            if timer_b_irq = '1' then reg_icr_status(1) <= '1'; end if;
            if serial_irq  = '1' then reg_icr_status(2) <= '1'; end if;

            -- 2. DYNAMISCHE MATRIX-ZUSAMMENFASSUNG (Das globale IR_SET Bit 7)
            if ((reg_icr_status(0) = '1' and reg_icr_mask(0) = '1') or
                (reg_icr_status(1) = '1' and reg_icr_mask(1) = '1') or
                (reg_icr_status(2) = '1' and reg_icr_mask(2) = '1')) then
                reg_icr_status(7) <= '1'; 
            else
                reg_icr_status(7) <= '0';
            end if;

            -- 3. BUS-SCHREIBAUSWERTUNG (Schreiboperation des Amiga-Betriebssystems)
            if chip_sel = '1' and write_en = '1' and e_clock_ce = '1' then
                if reg_addr(3 downto 0) = x"D" then
                    for i in 0 to 4 loop
                        if data_in(i) = '1' then
                            reg_icr_mask(i) <= data_in(7); 
                        end if;
                    end loop;
                end if;
            end if;

            -- 4. BUS-LESEZUGRIFFE DER CPU WITH AUTOMATIC CLEAR-ON-READ
            if chip_sel = '1' and read_en = '1' then
                if reg_addr(3 downto 0) = x"D" then
                    reg_data_out_sync <= reg_icr_status;
                    
                    -- Auslesen löscht alle aktiven Fehlerbits synchron im selben Takt! [14.1]
                    reg_icr_status(0) <= '0';
                    reg_icr_status(1) <= '0';
                    reg_icr_status(2) <= '0';
                    reg_icr_status(7) <= '0';
                end if;
            end if;

        end if;
    end process;

end Behavioral;
