-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle_pcmcia.vhd
-- Funktion: Originalgetreue PCMCIA-Schnittstellenlogik des Gayle-Chips.
--           Verwaltet den Card-Status und generiert Status-Wechsel-IRQs.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_pcmcia is
    Port (
        -- Versorgung und Takte vom Gehäuse
        i_clk_sys      : in  std_logic; -- 14 MHz SCLK von Alice über das Gehäuse
        i_rst_n        : in  std_logic; -- System-Reset (aktiv niedrig)
        
        -- Bus-Steuerung vom Gehäuse
        i_as_n         : in  std_logic; -- Address Strobe (aktiv niedrig)
        i_rw           : in  std_logic; -- Read/Write (1 = Read, 0 = Write)
        
        -- Interner Adress- und Datenbus zum Gehäuse
        i_pcm_addr     : in  std_logic_vector(15 downto 0); -- Untere Adressbits
        i_pcm_data     : in  std_logic_vector(7 downto 0);  -- Daten von der CPU
        o_pcm_data     : out std_logic_vector(7 downto 0);  -- Daten zur CPU
        
        -- Statusmeldung zurück an die Register-Hülle (über das Gehäuse)
        o_pcmcia_irq   : out std_logic  -- Meldet PCMCIA-Status-IRQs an gayle_regs
    );
end gayle_pcmcia;

architecture rtl of gayle_pcmcia is

    -- Interne Hardware-Registerebene für den PCMCIA-Slot im Gayle
    -- Standardmäßig simulieren wir: Keine Karte eingesteckt (Card Detect High / Inaktiv)
    signal r_pcm_status     : std_logic_vector(7 downto 0) := x"0C"; -- Bit 3 & 2 sind CD1 & CD2 (1 = Keine Karte)
    signal r_pcm_control    : std_logic_vector(7 downto 0) := x"00"; -- Spannungssteuerung / Zeiteinstellungen

    -- Interne Steuerflags für die Simulation von Hardware-Signalen
    signal r_card_inserted  : std_logic := '0'; -- 1 = Virtuelle Karte im Slot
    signal r_card_wp        : std_logic := '0'; -- 1 = Schreibgeschützt
    
    -- Flankenerkennung für Interrupts
    signal r_card_state_last: std_logic := '0';
    signal r_pcmcia_irq_reg : std_logic := '0';

begin

    -- Melde den internen Interrupt-Status an das Gehäuse
    o_pcmcia_irq <= r_pcmcia_irq_reg;

    -- =========================================================================
    -- NATIVE LOGIK FÜR HARDWARE-STATUSAUSWERTUNG
    -- =========================================================================
    process(i_clk_sys, i_rst_n)
    begin
        if i_rst_n = '0' then
            r_pcm_status     <= x"0C"; -- Zustand nach Reset: Slot leer
            r_pcm_control    <= x"00";
            r_card_state_last<= '0';
            r_pcmcia_irq_reg <= '0';
        elsif rising_edge(i_clk_sys) then
            
            r_card_state_last <= r_card_inserted;
            
            -- Dynamic Hardware Mirroring: Bilde die Pins auf das Status-Register ab
            -- Im originalen Amiga zieht eine eingesteckte Karte CD1 und CD2 auf Masse (0)
            if r_card_inserted = '1' then
                r_pcm_status(3) <= '0'; -- CD1 aktiv (niedrig)
                r_pcm_status(2) <= '0'; -- CD2 aktiv (niedrig)
            else
                r_pcm_status(3) <= '1'; -- CD1 inaktiv (hoch)
                r_pcm_status(2) <= '1'; -- CD2 inaktiv (hoch)
            end if;
            
            -- Write Protect Flag spiegeln (Bit 4)
            r_pcm_status(4) <= r_card_wp;
            
            -- Zyklusgenauer Statuswechsel-Interrupt:
            -- Wenn eine Karte eingesteckt oder abgezogen wird, löst Gayle einen Interrupt aus
            if r_card_inserted /= r_card_state_last then
                r_pcmcia_irq_reg <= '1'; -- Feuere Interrupt an gayle_regs
            end if;
            
            -- =========================================================================
            -- REGISTERZUGRIFFE VOM GEHÄUSE (PCMCIA-Steuerraum)
            -- =========================================================================
            if i_as_n = '0' and i_rw = '0' then
                -- Das Kickstart schreibt hierhin, um PCMCIA-Optionen zu setzen
                if i_pcm_addr(15 downto 12) = x"8" then -- Basisoffset für PCMCIA-Control
                    r_pcm_control <= i_pcm_data;
                    
                    -- Wenn das Betriebssystem den Interrupt verarbeitet hat, 
                    -- kann es das IRQ-Signal über ein Steuerbit zurücksetzen
                    if i_pcm_data(0) = '1' then
                        r_pcmcia_irq_reg <= '0';
                    end if;
                end if;
            end if;
            
        end if;
    end process;

    -- =========================================================================
    -- ASYNCHRONER LESEPFAD FÜR PCMCIA-DATEN
    -- =========================================================================
    o_pcm_data <= r_pcm_status  when i_pcm_addr(15 downto 12) = x"8" else
                  r_pcm_control when i_pcm_addr(15 downto 12) = x"A" else
                  x"FF";

end rtl;
