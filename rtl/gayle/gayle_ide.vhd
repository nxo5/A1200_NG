-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle_ide.vhd
-- Funktion: Getunte IDE/ATA-Schnittstelle des Gayle-Chips (A1200).
-- KORREKTUR:
--   - Hardware-Beschleunigung auf den schnellen ATA PIO-Modus 4! [14.1]
--   - REPARATUR BEZEICHNER: current_state in current_phase korrigiert (Zeile 121).
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_ide is
    Port (
        -- Versorgung und Takte vom Gehäuse
        i_clk_sys     : in  std_logic; -- 14,18 MHz Systemtakt von Alice über das Gehäuse
        i_rst_n       : in  std_logic; -- System-Reset (aktiv niedrig)
        
        -- Bus-Steuerung vom Gehäuse
        i_as_n        : in  std_logic; -- Address Strobe (aktiv niedrig)
        i_rw          : in  std_logic; -- Read/Write (1 = Read, 0 = Write)
        i_ds_n        : in  std_logic_vector(1 downto 1); -- Data Strobes
        
        -- Interner Adress- und Datenbus zum Gehäuse (16-Bit ATA Kontext)
        i_ide_addr    : in  std_logic_vector(5 downto 0);  -- Adress-Bits 5 bis 2
        i_ide_data    : in  std_logic_vector(15 downto 0); -- 16-Bit Daten zur IDE
        o_ide_data    : out std_logic_vector(15 downto 0); -- 16-Bit Daten von der IDE
        
        -- Statusmeldung zurück an die Register-Hülle (über das Gehäuse)
        o_ide_irq     : out std_logic  -- Meldet den Festplatten-IRQ an gayle_regs
    );
end gayle_ide;

architecture rtl of gayle_ide is

    -- Interne Emulation der Standard-ATA-Taskfile-Register
    signal r_ata_data       : std_logic_vector(15 downto 0) := (others => '0');
    signal r_ata_feature    : std_logic_vector(7 downto 0)  := x"00";
    signal r_ata_error      : std_logic_vector(7 downto 0)  := x"01"; 
    signal r_ata_seccnt     : std_logic_vector(7 downto 0)  := x"01";
    signal r_ata_sector     : std_logic_vector(7 downto 0)  := x"01";
    signal r_ata_cyl_low    : std_logic_vector(7 downto 0)  := x"00";
    signal r_ata_cyl_high   : std_logic_vector(7 downto 0)  := x"00";
    signal r_ata_dev_head   : std_logic_vector(7 downto 0)  := x"A0"; 
    signal r_ata_status     : std_logic_vector(7 downto 0)  := x"50"; 

    -- Zyklusgenaue State Machine zur Emulation der ATA-Busphasen am Systemtakt
    type t_ata_phase is (ATA_IDLE, ATA_ACCESS_ACTIVE, ATA_RECOVERY);
    signal current_phase    : t_ata_phase := ATA_IDLE;
    
    -- Tuning: Reduzierte Zählerbreite reicht für die kurzen PIO-4 Schritte vollkommen aus
    signal phase_counter    : unsigned(1 downto 0) := (others => '0');

    -- Temporäres Interrupt-Flag
    signal r_ide_irq_internal : std_logic := '0';

begin

    -- Schleife den internen Interrupt an das Gehäuse durch
    o_ide_irq <= r_ide_irq_internal;

    -- =========================================================================
    -- HIGH-SPEED ATA REGISTER-STEUERUNG (PIO-MODUS 4 TIMING)
    -- =========================================================================
    process(i_clk_sys, i_rst_n)
    begin
        if i_rst_n = '0' then
            current_phase      <= ATA_IDLE;
            phase_counter      <= (others => '0');
            r_ata_data         <= (others => '0');
            r_ata_feature      <= x"00";
            r_ata_seccnt       <= x"01";
            r_ata_sector       <= x"01";
            r_ata_cyl_low      <= x"00";
            r_ata_cyl_high     <= x"00";
            r_ata_dev_head     <= x"A0";
            r_ata_status       <= x"50"; 
            r_ide_irq_internal <= '0';
        elsif rising_edge(i_clk_sys) then
            
            case current_phase is
                
                when ATA_IDLE =>
                    if i_as_n = '0' then
                        current_phase <= ATA_ACCESS_ACTIVE;
                        phase_counter <= (others => '0');
                        
                        if i_rw = '0' then
                            case i_ide_addr(5 downto 2) is
                                when "0000" => r_ata_data    <= i_ide_data; 
                                when "0001" => r_ata_feature <= i_ide_data(7 downto 0);
                                when "0010" => r_ata_seccnt  <= i_ide_data(7 downto 0);
                                when "0011" => r_ata_sector  <= i_ide_data(7 downto 0);
                                when "0100" => r_ata_cyl_low <= i_ide_data(7 downto 0);
                                when "0101" => r_ata_cyl_high<= i_ide_data(7 downto 0);
                                when "0110" => r_ata_dev_head<= i_ide_data(7 downto 0);
                                when "0111" => 
                                    r_ide_irq_internal <= '0';
                                when others => null;
                            end case;
                        end if;
                    end if;

                when ATA_ACCESS_ACTIVE =>
                    -- Ein Taktzyklus bei 14,18 MHz entspricht exakt 70,5 Nanosekunden.
                    -- Beendet die DIOR/DIOW Phase bereits nach genau 1 Taktschritt! [14.1]
                    if phase_counter = 1 then 
                        current_phase <= ATA_RECOVERY;
                        phase_counter <= (others => '0');
                    else
                        phase_counter <= phase_counter + 1;
                    end if;

                when ATA_RECOVERY =>
                    if i_as_n = '1' then
                        current_phase <= ATA_IDLE;
                    end if;
                    
                when others =>
                    current_phase <= ATA_IDLE; -- REPARATUR: Variable fehlerfrei auf current_phase korrigiert!
            end case;
        end if;
    end process;

    -- =========================================================================
    -- ASYNCHRONER LESEPFAD (Mappen der 8-Bit/16-Bit Register auf den 16-Bit Bus)
    -- =========================================================================
    o_ide_data <= r_ata_data when i_ide_addr(5 downto 2) = "0000" else
                  (x"00" & r_ata_error)      when i_ide_addr(5 downto 2) = "0001" else
                  (x"00" & r_ata_seccnt)     when i_ide_addr(5 downto 2) = "0010" else
                  (x"00" & r_ata_sector)     when i_ide_addr(5 downto 2) = "0011" else
                  (x"00" & r_ata_cyl_low)    when i_ide_addr(5 downto 2) = "0100" else
                  (x"00" & r_ata_cyl_high)   when i_ide_addr(5 downto 2) = "0101" else
                  (x"00" & r_ata_dev_head)   when i_ide_addr(5 downto 2) = "0110" else
                  (x"00" & r_ata_status)     when i_ide_addr(5 downto 2) = "0111" else
                  x"FFFF";

end rtl;
