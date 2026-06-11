-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_move_size.vhd
-- Funktion: Die kombinatorische Größenfeld-Extraktion für MOVE-Befehle.
--           Übersetzt die Bit-Kombinationen starr nach Motorola 68030.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_move_size is
    Port (
        opcode          : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode
        move_en         : in    std_logic;                      -- Freigabe vom Top-Decoder
        
        -- Kombinatorischer Ausgang
        move_size       : out   std_logic_vector(1 downto 0)    -- Breite (00=Byte, 01=Word, 10=Long)
    );
end cpu_030_ec_dec_move_size;

architecture behavioral of cpu_030_ec_dec_move_size is
begin

    -- =====================================================================
    -- UNBESTECHLICHE MOTOROLA-BITREITEN-AUSWERTUNG
    -- =====================================================================
    process(opcode, move_en)
    begin
        -- Standardwert initialisieren, um Latches zu verhindern
        move_size <= "01"; -- Standardmäßig Word-Breite

        if move_en = '1' then
            -- MOVE nutzt ein spezifisches Größenraster in den Bits 13 und 12:
            -- "01" = Byte, "11" = Word, "10" = Longword
            case opcode(13 downto 12) is
                when "01" =>
                    move_size <= "00"; -- Byte-Transfer (8 Bit)
                when "11" =>
                    move_size <= "01"; -- Word-Transfer (16 Bit)
                when "10" =>
                    move_size <= "10"; -- Longword-Transfer (32 Bit)
                when others =>
                    move_size <= "01"; -- Undefinierte Muster fallen auf Word zurück
            end case;
        end if;
    end process;

end behavioral;
