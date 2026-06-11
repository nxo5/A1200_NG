-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_interrupt.vhd
-- Funktion: Das rein kombinatorische Hardware-Interrupt-Filterwerk (68030).
--           Wertet IPL_N aus und prüft Pegel gegen die SR-Maskenbits.
--           Gibt bei Gültigkeit das Signal zur Befehlsunterbrechung frei.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_interrupt is
    Port (
        -- Physikalische Pins der Gehäuse-Außenhaut (Low-Aktiv vom Amiga-Chipsatz)
        ext_IPL_N       : in    std_logic_vector(2 downto 0);
        
        -- Heraufgereichte Maskierungsbits aus dem Statusregister (SR Bits 10..8)
        sr_interrupt_mask : in    std_logic_vector(2 downto 0);
        
        -- Kombinatorische Ausgänge an den Top-Decoder-Wrapper
        irq_asserted    : out   std_logic;                      -- '1' = Gültiger Interrupt steht an!
        irq_level       : out   std_logic_vector(2 downto 0)    -- Der erkannte Level (001 bis 111)
    );
end cpu_030_ec_dec_interrupt;

architecture behavioral of cpu_030_ec_dec_interrupt is
begin

    -- =====================================================================
    -- KOMBINAOTORISCHES INTERRUPTION-FILTER (0 WAIT-STATES)
    -- =====================================================================
    process(ext_IPL_N, sr_interrupt_mask)
        variable raw_level : unsigned(2 downto 0);
        variable mask      : unsigned(2 downto 0);
    begin
        -- 1. HARDWARE-INVERTIERUNG: Motorola-Pins sind Low-Aktiv!
        -- "111" an den Pins bedeutet kein Interrupt (Level 0)
        -- "000" an den Pins bedeutet höchster Interrupt (Level 7)
        case ext_IPL_N is
            when "111" => raw_level := "000"; -- Level 0 (Kein IRQ)
            when "110" => raw_level := "001"; -- Level 1
            when "101" => raw_level := "010"; -- Level 2
            when "100" => raw_level := "011"; -- Level 3
            when "011" => raw_level := "100"; -- Level 4
            when "010" => raw_level := "101"; -- Level 5
            when "001" => raw_level := "110"; -- Level 6
            when "000" => raw_level := "111"; -- Level 7 (NMI)
            when others => raw_level := "000";
        end case;

        mask := unsigned(sr_interrupt_mask);

        -- Standardwerte initialisieren, um Latches zu verhindern
        irq_asserted <= '0';
        irq_level    <= std_logic_vector(raw_level);

        -- 2. UNBESTECHLICHE MOTOROLA-MASKENPRÜFUNG
        if raw_level > 0 then
            -- REGEL 1: Level 7 (NMI) bricht IMMER durch, egal wie das SR maskiert ist!
            if raw_level = "111" then
                irq_asserted <= '1';
            -- REGEL 2: Alle anderen Level müssen strikt HÖHER sein als die Maske
            elsif raw_level > mask then
                irq_asserted <= '1';
            else
                irq_asserted <= '0'; -- IRQ wird von der CPU passiv ignoriert (gesperrt)
            end if;
        end if;
    end process;

end behavioral;
