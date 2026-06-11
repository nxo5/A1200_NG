-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle_regs.vhd
-- Funktion: Originalgetreue Register-Verwaltung des Gayle-Chips (A1200).
--           Verarbeitet die Register INTREQ, INTENA, CONFIG und CSSTAT.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_regs is
    Port (
        -- Versorgung und Takte vom Gehäuse
        i_clk_sys    : in  std_logic; -- 14 MHz SCLK von Alice
        i_clk_cck    : in  std_logic; -- 7 MHz CCK von Alice
        i_rst_n      : in  std_logic; -- System-Reset (aktiv niedrig)
        
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
    signal r_GAYLE_CSSTAT : std_logic_vector(7 downto 0) := x"00"; -- Statusflags (PCMCIA)

    -- Synchronisations-Register zur Flankenerkennung der externen Interrupts
    signal r_ide_irq_last : std_logic := '0';
    signal r_pcm_irq_last : std_logic := '0';

begin

    -- =========================================================================
    -- INTERNE INTERRUPT-ERFASSUNG & COMPONENT-STATUS
    -- =========================================================================
    process(i_clk_sys, i_rst_n)
    begin
        if i_rst_n = '0' then
            r_ide_irq_last <= '0';
            r_pcm_irq_last <= '0';
            r_GAYLE_CSSTAT <= x"0C"; -- Standard: Keine PCMCIA-Karte im Slot (CD-Bits auf '1')
        elsif rising_edge(i_clk_sys) then
            r_ide_irq_last <= i_ide_irq;
            r_pcm_irq_last <= i_pcmcia_irq;
            
            -- Zyklusgenaue Erfassung: Wenn das IDE-Modul einen IRQ meldet (steigende Flanke)
            if i_ide_irq = '1' and r_ide_irq_last = '0' then
                r_GAYLE_INTREQ(7) <= '1'; -- Setze IDE-Interrupt-Flag (Bit 7)
            end if;
            
            -- Wenn das PCMCIA-Modul einen IRQ meldet
            if i_pcmcia_irq = '1' and r_pcm_irq_last = '0' then
                r_GAYLE_INTREQ(3) <= '1'; -- Setze PCMCIA-Interrupt-Flag (Bit 3)
            end if;
            
            -- Kontinuierliche interne Zustandspiegelung für PCMCIA Card Status ($DA8000)
            -- Hier verknüpfen wir später die echten Pegel aus gayle_pcmcia.
            -- Bit 3/2 spiegeln im Original die Card-Detect-Pins.
        end if;
    end process;


    -- =========================================================================
    -- SYNC REGISTER ACCES (Lese- und Schreibzyklen auf dem Systembus)
    -- =========================================================================
    process(i_clk_sys, i_rst_n)
    begin
        if i_rst_n = '0' then
            -- Gayle setzt INTREQ und INTENA beim Hardware-Reset komplett zurück
            r_GAYLE_INTREQ(6 downto 4) <= (others => '0');
            r_GAYLE_INTREQ(2 downto 0) <= (others => '0');
            -- Hinweis: Bit 7 und 3 werden durch die IRQ-Logik oben gesteuert, hier sicherheitshalber löschen:
            r_GAYLE_INTREQ(7) <= '0';
            r_GAYLE_INTREQ(3) <= '0';
            
            r_GAYLE_INTENA <= x"00";
            r_GAYLE_CONFIG <= x"00";
        elsif rising_edge(i_clk_sys) then
            -- Wenn das Address Strobe aktiv ist (CPU greift auf den Bus zu)
            if i_as_n = '0' then
                
                -- Schreibzugriff (i_rw = '0')
                if i_rw = '0' then
                    case i_reg_addr(15 downto 12) is
                        when x"9" => -- $DA9000: GAYLE_INTREQ
                            -- Original-Hardware-Verhalten (Write-to-Clear): 
                            -- Eine geschriebene '1' löscht das entsprechende Bit im Register.
                            r_GAYLE_INTREQ(7) <= r_GAYLE_INTREQ(7) and not i_reg_data(7);
                            r_GAYLE_INTREQ(3) <= r_GAYLE_INTREQ(3) and not i_reg_data(3);
                            
                        when x"A" => -- $DAA000: GAYLE_INTENA
                            r_GAYLE_INTENA <= i_reg_data;
                            
                        when x"B" => -- $DAB000: GAYLE_CONFIG
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
    -- Wenn die CPU liest, legen wir die Registerinhalte unverzüglich auf den Ausgang
    o_reg_data <= r_GAYLE_CSSTAT when i_reg_addr(15 downto 12) = x"8" else -- $DA8000
                  r_GAYLE_INTREQ when i_reg_addr(15 downto 12) = x"9" else -- $DA9000
                  r_GAYLE_INTENA when i_reg_addr(15 downto 12) = x"A" else -- $DAA000
                  r_GAYLE_CONFIG when i_reg_addr(15 downto 12) = x"B" else -- $DAB000
                  x"FF"; -- Offener Bus liefert standardmäßig High-Pegel im Amiga

    -- =========================================================================
    -- GAYLE INTERRUPT GENERATION (Ausgabe ans Gehäuse)
    -- =========================================================================
    -- Logische Verknüpfung: Ein Interrupt wird ans System (INT2) weitergegeben,
    -- wenn das Interrupt-Flag aktiv ist UND das entsprechende Enable-Bit gesetzt wurde.
    o_gayle_irq <= '1' when ((r_GAYLE_INTREQ(7) = '1' and r_GAYLE_INTENA(7) = '1') or  -- IDE
                             (r_GAYLE_INTREQ(3) = '1' and r_GAYLE_INTENA(3) = '1'))    -- PCMCIA
                   else '0';

end rtl;
