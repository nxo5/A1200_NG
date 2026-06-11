-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_alu_size.vhd
-- Funktion: Die kombinatorische Größenfeld-Extraktion für ALU-Befehle.
--           Übersetzt die Bit-Kombinationen starr nach Motorola 68030.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_alu_size is
    Port (
        opcode          : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode
        alu_dec_en      : in    std_logic;                      -- Freigabe vom Top-Decoder
        
        -- Kombinatorischer Ausgang
        dec_alu_size    : out   std_logic_vector(1 downto 0)    -- Breite (00=Byte, 01=Word, 10=Long)
    );
end cpu_030_ec_dec_alu_size;

architecture behavioral of cpu_030_ec_dec_alu_size is
begin

    -- =====================================================================
    -- UNBESTECHLICHE MOTOROLA-BITBREITEN-AUSWERTUNG
    -- =====================================================================
    process(opcode, alu_dec_en)
    begin
        -- Standardwert initialisieren, um Latches zu verhindern
        dec_alu_size <= "01"; -- Standardmäßig Word-Breite

        if alu_dec_en = '1' then
            -- Motorola ALU-Befehle (ADD/SUB) nutzen ein standardisiertes 2-Bit Feld:
            -- Bits 8=0 und 7..6 bestimmen die Breite: 00=Byte, 01=Word, 10=Longword
            -- Steht Bit 8 auf '1' (Richtung umgekehrt), bestimmen Bits 7..6 ebenfalls die Breite.
            -- Sonderfall ADDA/SUBA (Adressregister als Ziel): Bits 8..6 sind "011" oder "111" -> Fest Longword!
            
            if opcode(8 downto 6) = "011" or opcode(8 downto 6) = "111" then
                dec_alu_size <= "10"; -- ADDA / SUBA arbeitet intern IMMER mit 32-Bit Longwords
            else
                case opcode(7 downto 6) is
                    when "00" =>
                        dec_alu_size <= "00"; -- Byte-Operation (8 Bit)
                    when "01" =>
                        dec_alu_size <= "01"; -- Word-Operation (16 Bit)
                    when "10" =>
                        dec_alu_size <= "10"; -- Longword-Operation (32 Bit)
                    when others =>
                        dec_alu_size <= "01"; -- Fallback auf Word
                end case;
            end if;
        end if;
    end process;

end behavioral;
