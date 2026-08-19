-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   NE555.vhd
-- Funktion: Getreue Nachbildung der Amiga 1200 Hardware-Reset-Logik (U14).
--           Nimmt ultrakurze OSD- oder Framework-Trigger entgegen und dehnt
--           das Reset-Signal synchron aus, um dem Core ein sauberes
--           Initialisieren aller Register und Speicherbänke zu garantieren.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity NE555 is
    port (
        i_clk_sys       : in  std_logic; -- Der synchrone 50,00 MHz Amiga-Systemtakt
        i_trigger_reset : in  std_logic; -- Der unbepufferte, kurze Reset-Impuls vom OSD/Framework
        o_amiga_reset   : out std_logic  -- Das gedehnte, unnachgiebige Reset-Signal für A1200_top
    );
end NE555;

architecture rtl of NE555 is

    -- Zeitkonstante für die Dehnung:
    -- Bei 50 MHz entspricht 1 Millisekunde genau 50.000 Taktzyklen.
    -- Um eine stabile, Commodore-konforme Hardware-Rücksetzung zu erzielen,
    -- dehnen wir das Signal auf ca. 250 Millisekunden aus (12.500.000 Zyklen).
    -- Das benötigt einen stabilen 24-Bit Hardware-Zähler.
    constant C_RESET_CYCLES : unsigned(23 downto 0) := to_unsigned(12500000, 24);
    
    signal r_reset_counter  : unsigned(23 downto 0) := (others => '0');
    signal r_reset_active   : std_logic := '1'; -- Startet beim Einschalten im Reset-Zustand

begin

    -- =========================================================================
    -- MONOSTABILES RESET-UHRWERK (EMULATION DES U14-NE555 TIMERS)
    -- =========================================================================
    process(i_clk_sys)
    begin
        if rising_edge(i_clk_sys) then
            if i_trigger_reset = '1' then
                -- Ein Impuls am Trigger-Eingang startet die Kippstufe sofort neu:
                -- Die Reset-Leitung wird aktiv geschaltet und der Zähler genullt.
                r_reset_counter <= (others => '0');
                r_reset_active  <= '1';
            else
                -- Wenn der Timer läuft (Reset ist aktiv):
                if r_reset_active = '1' then
                    if r_reset_counter < C_RESET_CYCLES then
                        r_reset_counter <= r_reset_counter + 1;
                    else
                        -- Die Haltezeit ist abgelaufen: Der Timer lässt die Leitung los.
                        r_reset_active <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Das fertige, gedehnte Signal geht direkt an den Hauptkern
    o_amiga_reset <= r_reset_active;

end rtl;
