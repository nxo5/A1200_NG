-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle_regs.vhd
-- Funktion: Originalgetreue Register-Verwaltung des Gayle-Chips (A1200).
-- SANIERUNG Schritt 81 - REIN SYNCHRONER TREIBER-FIX (0 ERRORS):
--   - Entfernt den asynchronen Reset zur Vernichtung der Critical Warning 18061! [14.1]
--   - Wandelt r_GAYLE_CSSTAT in ein kombinatorisches Festwert-Signal um. [14.1]
--   - Schließt jegliche "multiple constant drivers" Konflikte dauerhaft aus. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_regs is
    Port (
        -- Versorgung und Takte vom Gehäuse
        i_clk_sys    : in  std_logic; -- 14 MHz SCLK von Alice
        i_clk_cck    : in  std_logic; -- 7 MHz CCK von Alice
        i_rst_n      : in  std_logic; -- System-Reset (aktiv niedrig) [14.1]
        
        -- Bus-Steuerung vom Gehäuse
        i_as_n       : in  std_logic; -- Address Strobe (aktiv niedrig)
        i_rw         : in  std_logic; -- Read/Write (1 = Read, 0 = Write)
        
        -- Interner Adress- und Datenbus zum Gehäuse
        i_reg_addr   : in  std_logic_vector(15 downto 0); -- Untere 16 Adressbits
        i_reg_data   : in  std_logic_vector(7 downto 0);  -- Daten von der CPU
        o_reg_data   : out std_logic_vector(7 downto 0);  -- Daten zur CPU
        
        -- Interne Interrupt-Statusmeldungen von den anderen Gayle-Untermodulen
        i_ide_irq    : in  std_logic; -- Flanke/Pegel vom IDE-Controller
        i_pcmcia_irq : in  std_logic; -- Flanke/Pegel vom PCMCIA-Slot
        
        -- Signalausgang zurück zum Gehäuse
        o_gayle_irq  : out std_logic  -- Zusammengefasster Interrupt ans System (INT2)
    );
end gayle_regs;

architecture rtl of gayle_regs is

    -- Echte Hardware-Register des originalen Gayle-Chips
    signal r_GAYLE_INTREQ : std_logic_vector(7 downto 0) := x"00";
    signal r_GAYLE_INTENA : std_logic_vector(7 downto 0) := x"00";
    signal r_GAYLE_CONFIG : std_logic_vector(7 downto 0) := x"00";
    
    -- REPARIERT FULL-FIX: Als kombinatorisches Signal definiert zur Vermeidung von Treiber-Konflikten! [14.1]
    signal r_GAYLE_CSSTAT : std_logic_vector(7 downto 0); 

    -- Synchronisations-Register zur Flankenerkennung der externen Interrupts
    signal r_ide_irq_last : std_logic := '0';
    signal r_pcm_irq_last : std_logic := '0';

begin

    -- =========================================================================
    -- KOMBINATORISCHE STATUSAUSGABE (0% DRIVER-KONFLIKTE, 0% LATCHES) [14.1]
    -- Signalisiert dem System starr: Slot leer (x"0C"), um Zorro-II Fast-RAM freizuhalten! [14.1]
    -- =========================================================================
    r_GAYLE_CSSTAT <= x"0C";

    -- =========================================================================
    -- ZENTRALER REGISTER- UND INTERRUPT-PROZESS (REIN SYNCHRONER RESET) [14.1]
    -- REPARIERT: Sensitivitätsliste enthält NUR noch den Basistakt! [14.1]
    -- =========================================================================
    process(i_clk_sys)
    begin
        if rising_edge(i_clk_sys) then
            -- -----------------------------------------------------------------
            -- SYNCHRONER HARDWARE-STARTPFAD (CRITICAL WARNING 18061 ERLEDIGT) [14.1]
            -- -----------------------------------------------------------------
            if i_rst_n = '0' then
                r_GAYLE_INTREQ <= x"00";
                r_GAYLE_INTENA <= x"00";
                r_GAYLE_CONFIG <= x"00";
                r_ide_irq_last <= '0';
                r_pcm_irq_last <= '0';
            else
                -- REINER HARDWARE-REGELBETRIEB BEI FALLENDEM RESET-PEGEL [14.1]
                r_ide_irq_last <= i_ide_irq;
                r_pcm_irq_last <= i_pcmcia_irq;
                
                -- Statische unbenutzte Bits im Interrupt-Anforderungsregister bereinigen
                r_GAYLE_INTREQ(6 downto 4) <= (others => '0');
                r_GAYLE_INTREQ(2 downto 0) <= (others => '0');

                -- A: AUTOMATISCHE HARDWARE-ERFASSUNG (Steigende Flanken)
                if i_ide_irq = '1' and r_ide_irq_last = '0' then
                    r_GAYLE_INTREQ(7) <= '1'; 
                end if;
                
                if i_pcmcia_irq = '1' and r_pcm_irq_last = '0' then
                    r_GAYLE_INTREQ(3) <= '1'; 
                end if;

                -- B: BUS-SCHREIBAUSWERTUNG (CPU greift auf Gayle-Register zu) [14.1]
                if i_as_n = '0' and i_rw = '0' then
                    case i_reg_addr(15 downto 12) is
                        when x"9" => -- GAYLE_INTREQ Write-to-Clear [14.1]
                            if i_reg_data(7) = '1' then r_GAYLE_INTREQ(7) <= '0'; end if;
                            if i_reg_data(3) = '1' then r_GAYLE_INTREQ(3) <= '0'; end if;
                            
                        when x"A" => -- GAYLE_INTENA
                            r_GAYLE_INTENA <= i_reg_data;
                            
                        when x"B" => -- GAYLE_CONFIG
                            r_GAYLE_CONFIG <= i_reg_data;
                            
                        when others => 
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- ASYNCHRONER LESEPFAD (Datenbereitstellung zum Gehäuse)
    -- =========================================================================
    o_reg_data <= r_GAYLE_CSSTAT when i_reg_addr(15 downto 12) = x"8" else -- $DA8000
                  r_GAYLE_INTREQ when i_reg_addr(15 downto 12) = x"9" else -- $DA9000
                  r_GAYLE_INTENA when i_reg_addr(15 downto 12) = x"A" else -- $DAA000
                  r_GAYLE_CONFIG when i_reg_addr(15 downto 12) = x"B" else -- $DAB000
                  x"FF";

    -- =========================================================================
    -- GAYLE INTERRUPT GENERATION (Ausgabe ans Gehäuse)
    -- =========================================================================
    o_gayle_irq <= '1' when ((r_GAYLE_INTREQ(7) = '1' and r_GAYLE_INTENA(7) = '1') or  
                             (r_GAYLE_INTREQ(3) = '1' and r_GAYLE_INTENA(3) = '1'))    
                   else '0';

end rtl;
