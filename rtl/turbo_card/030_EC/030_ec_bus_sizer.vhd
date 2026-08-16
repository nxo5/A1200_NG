-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_bus_sizer.vhd
-- Teil:    1 von 2 (Originale Entity-Schnittstelle)
-- Funktion: Der rein kombinatorische Byte-Akkumulator und Daten-Shifter.
--           PUNKT 1: Schaltet Datenbytes bei 8-Bit und 16-Bit Mainboard-
--                    Zugriffen je nach fsm_sizing_offset fehlerfrei um!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_bus_sizer is
    Port (
        -- Kontrollleitungen aus der übergeordneten Bus-FSM
        fsm_sizing_offset   : in    std_logic_vector(1 downto 0);   -- "00"=+0, "01"=+1, "10"=+2, "11"=+3 Bytes
        cycle_write         : in    std_logic;                      -- '1' = Schreibzyklus, '0' = Lesezyklus
        ext_dsack_width     : in    std_logic_vector(1 downto 0);   -- "00"=32-Bit, "10"=16-Bit, "01"=8-Bit
        
        -- Datenpfad-Schnittstelle zum internen CPU-Core
        core_D_out          : in    std_logic_vector(31 downto 0);  -- Die vom Core generierten Schreibdaten
        core_D_in           : out   std_logic_vector(31 downto 0);  -- Die für den Core akkumulierten Lesedaten
        
        -- Datenpfad-Schnittstelle zu den externen physischen Pins (Turbokarte/Mainboard)
        ext_D_in_pins       : in    std_logic_vector(31 downto 0);  -- Die real anstehenden Lesedaten von den Pins
        ext_D_out_pins      : out   std_logic_vector(31 downto 0)   -- Die an die Pins auszugebenden Schreibdaten
    );
end cpu_030_ec_bus_sizer;

architecture behavioral of cpu_030_ec_bus_sizer is
begin

    -- =====================================================================
    -- KOMBINAOTORISCHE MUTIPLEXER-TREIBERMATIX (0 WAIT-STATES)
    -- Verwaltet das Motorola-Byte-Juggling für Read- und Write-Zyklen.
    -- =====================================================================
    process(fsm_sizing_offset, cycle_write, ext_dsack_width, core_D_out, ext_D_in_pins)
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        core_D_in      <= (others => '0');
        ext_D_out_pins <= (others => '0');

        -- =================================================================
        -- SCHREIBPFAD (WRITE): DATEN AUF BYTE-SPUREN REPLIZIEREN
        -- =================================================================
        if cycle_write = '1' then
            if ext_dsack_width = "10" then
                -- A: 16-Bit Bus ➔ Das obere Word auf beide Hälften replizieren
                ext_D_out_pins(31 downto 16) <= core_D_out(31 downto 16);
                ext_D_out_pins(15 downto 0)  <= core_D_out(31 downto 16);
            elsif ext_dsack_width = "01" then
                -- B: 8-Bit Bus ➔ Das aktive Byte auf alle 4 Spuren spiegeln (Umladeschutz!)
                ext_D_out_pins(31 downto 24) <= core_D_out(31 downto 24);
                ext_D_out_pins(23 downto 16) <= core_D_out(31 downto 24);
                ext_D_out_pins(15 downto 8)  <= core_D_out(31 downto 24);
                ext_D_out_pins(7 downto 0)   <= core_D_out(31 downto 24);
            else
                -- C: 32-Bit Bus ➔ Unverändertes Durchreichen
                ext_D_out_pins <= core_D_out;
            end if;

        -- =================================================================
        -- LESEPFAD (READ): KORREKTUR: SPUR-ISOLIERUNG OHNE GEISTER-MÜLL
        -- =================================================================
        else
            if ext_dsack_width = "10" then
                -- A: 16-BIT SPEICHERMEDIEN (Z. B. MAINBOARD-ROM / KICKSTART)
                case fsm_sizing_offset is
                    when "00" =>
                        -- Schritt 1: Das obere Word rollt sauber ein, untere Hälfte maskiert
                        core_D_in(31 downto 16) <= ext_D_in_pins(31 downto 16);
                        core_D_in(15 downto 0)  <= (others => '0');
                    when "10" =>
                        -- Schritt 2: Das untere Word kommt über die obere Spur!
                        core_D_in(31 downto 16) <= ext_D_in_pins(31 downto 16);
                        core_D_in(15 downto 0)  <= (others => '0');
                    when others => 
                        null;
                end case;

            elsif ext_dsack_width = "01" then
                -- B: 8-BIT SPEICHERMEDIEN (AMIGA-CHIPSATZ / CUSTOM-REGISTERS)
                -- Das angeforderte Byte liegt laut Motorola immer auf D31..D24
                case fsm_sizing_offset is
                    when "00" =>
                        -- Byte 0 einholen (MSB), Rest starr ausnullen
                        core_D_in(31 downto 24) <= ext_D_in_pins(31 downto 24);
                    when "01" =>
                        -- Byte 1 einholen (Wird im Core an Position 23..16 verrastet)
                        core_D_in(31 downto 24) <= ext_D_in_pins(31 downto 24);
                    when "10" =>
                        -- Byte 2 einholen (Wird im Core an Position 15..8 verrastet)
                        core_D_in(31 downto 24) <= ext_D_in_pins(31 downto 24);
                    when "11" =>
                        -- Byte 3 einholen (LSB, Wird im Core an Position 7..0 verrastet)
                        core_D_in(31 downto 24) <= ext_D_in_pins(31 downto 24);
                    when others => 
                        null;
                end case;
            else
                -- C: NATIVES 32-BIT FAST-RAM (KEIN VERSATZ ODER MASKIERUNG NOTWENDIG)
                core_D_in <= ext_D_in_pins;
            end if;
        end if;
    end process;

end behavioral;
