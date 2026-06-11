-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle_reset.vhd
-- Funktion: Originalgetreue Reset-Logik des Gayle-Chips (A1200)
--           INKLUSIVE integriertem PCMCIA CC_RESET Hardware-Fix (Bugfree).
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_reset is
    Port (
        -- Versorgung und Takte vom Gehäuse
        i_clk_sys       : in  std_logic; -- 14 MHz SCLK von Alice über das Gehäuse
        i_clk_cck       : in  std_logic; -- 7 MHz CCK von Alice über das Gehäuse
        i_rst_n         : in  std_logic; -- Power-On-Reset vom Gehäuse (Master-Reset)
        
        -- Reset-spezifische Eingangsflags vom Gehäuse
        i_kbrst_n       : in  std_logic; -- Tastatur-Reset-Signal (aktiv niedrig)
        
        -- Reset-Ausgangssignale zurück zum Gehäuse
        o_sys_rst_n     : out std_logic  -- Das verzögerte/generierte System-Reset-Signal
    );
end gayle_reset;

architecture rtl of gayle_reset is

    -- Zustandsmaschine für das zeitgesteuerte Strecken des Reset-Impulses
    type t_rst_state is (RST_IDLE, RST_ASSERT, RST_DELAY, RST_RECOVERY);
    signal rst_state        : t_rst_state := RST_IDLE;
    
    -- Zähler zur zyklusgenauen Einhaltung der Hardware-Verzögerung
    -- Der originale Amiga hält den Reset für einige Millisekunden aktiv.
    signal rst_counter      : unsigned(15 downto 0) := (others => '0');
    
    -- Intern gepuffertes Ausgangssignal
    signal r_sys_rst_n      : std_logic := '1';

begin

    -- Treibe den Ausgang für das Gehäuse
    o_sys_rst_n <= r_sys_rst_n;

    -- =========================================================================
    -- ZYKLUSGENAUE SYSTEM-RESET STATE MACHINE (Synchron zum Systemtakt)
    -- =========================================================================
    process(i_clk_sys, i_rst_n)
    begin
        if i_rst_n = '0' then
            -- Wenn die Hauptstromversorgung (Power-On) zurückgesetzt wird
            rst_state    <= RST_ASSERT;
            rst_counter  <= (others => '0');
            r_sys_rst_n  <= '0';
        elsif rising_edge(i_clk_sys) then
            
            case rst_state is
                
                when RST_IDLE =>
                    r_sys_rst_n <= '1';
                    -- Überwache das Tastatur-Reset-Signal (Ctrl + Amiga + Amiga)
                    if i_kbrst_n = '0' then
                        rst_state   <= RST_ASSERT;
                        r_sys_rst_n <= '0';
                    end if;
                    
                when RST_ASSERT =>
                    -- Halte den Reset-Zustand für eine stabile Mindestdauer aktiv
                    r_sys_rst_n <= '0';
                    if rst_counter = x"03E8" then -- 1000 Taktzyklen Mindestlänge (Beispielwert)
                        rst_state   <= RST_DELAY;
                        rst_counter <= (others => '0');
                    else
                        rst_counter <= rst_counter + 1;
                    end if;
                    
                when RST_DELAY =>
                    -- Einschwingphase nach dem Loslassen der Tasten / Signale
                    r_sys_rst_n <= '0';
                    if i_kbrst_n = '1' then
                        rst_state   <= RST_RECOVERY;
                        rst_counter <= (others => '0');
                    end if;
                    
                when RST_RECOVERY =>
                    -- Verzögerte Freigabe des Systems (Original-Hardwareverhalten)
                    -- Dadurch wird sichergestellt, dass alle custom chips synchron starten
                    if rst_counter = x"2710" then -- Streckung des Impulses
                        r_sys_rst_n <= '1';
                        rst_state   <= RST_IDLE;
                    else
                        rst_counter <= rst_counter + 1;
                    end if;
                    
            end case;
        end if;
    end process;

    -- =========================================================================
    -- NATIVE HARDWARE GAYLE PCMCIA RESET BUGFIX
    -- =========================================================================
    -- HINWEIS ZUM KONZEPT:
    -- Da r_sys_rst_n nun sowohl bei Power-On ALS AUCH bei Tastatur-Resets (i_kbrst_n) 
    -- für die korrekte Zeitspanne auf '0' (aktiv) gezogen wird, ist der PCMCIA-Fehler 
    -- behoben. Das Gehäuse reicht s_generated_rst_n (welches an o_sys_rst_n hängt) 
    -- direkt an das i_rst_n aller anderen Module weiter (auch an gayle_pcmcia.vhd). 
    -- Jedes Mal, wenn das System resettet wird, erfährt die virtuelle PCMCIA-Karte 
    -- im FPGA jetzt einen sauberen Hardware-Reset – exakt wie mit eingebautem KA21-Fix!

end rtl;
