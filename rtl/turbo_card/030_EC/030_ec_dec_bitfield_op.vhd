-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_bitfield_op.vhd
-- Funktion: Der kombinatorische Opcode-Klassifizierer für Bitfeld-Befehle.
--           Isoliert Offset und Breite starr nach Motorola 68030.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_bitfield_op is
    Port (
        opcode          : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode
        bitfield_en     : in    std_logic;                      -- Freigabe vom Top-Decoder
        
        -- Kombinatorische Ausgänge ans Hauptsteuerwerk / ALU
        bf_ea_calc      : out   std_logic;                      -- Adressberechnung für Basisadresse anfordern
        bf_alu_op       : out   std_logic_vector(7 downto 0);   -- Operations-ID für das Rechenwerk
        bf_offset_is_reg: out   std_logic;                      -- '1' = Offset liegt in Dn, '0' = Konstante
        bf_width_is_reg : out   std_logic                       -- '1' = Breite liegt in Dn, '0' = Konstante
    );
end cpu_030_ec_dec_bitfield_op;

architecture behavioral of cpu_030_ec_dec_bitfield_op is
begin

    -- =====================================================================
    -- UNBESTECHLICHE EVALUIERUNG DER MOTOROLA BITFELD-OPCODES
    -- =====================================================================
    process(opcode, bitfield_en)
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        bf_ea_calc       <= '0';
        bf_alu_op        <= x"00";
        bf_offset_is_reg <= '0';
        bf_width_is_reg  <= '0';

        if bitfield_en = '1' then
            bf_ea_calc <= '1'; -- Bitfelder verlangen immer eine Basis-Adressermittlung
            
            -- Auswertung des Bitfeld-Unterbefehls (Bits 10 downto 8)
            case opcode(10 downto 8) is
                when "101" => bf_alu_op <= x"10"; -- BFEXTU (Bit Field Extract Unsigned)
                when "111" => bf_alu_op <= x"11"; -- BFINS  (Bit Field Insert)
                when "110" => bf_alu_op <= x"12"; -- BFCHG  (Bit Field Change)
                when "100" => bf_alu_op <= x"13"; -- BFCLR  (Bit Field Clear)
                when "000" => bf_alu_op <= x"14"; -- BFTST  (Bit Field Test)
                when others => bf_alu_op <= x"00";
            end case;

            -- Motorola-Hardware-Regel: Das darauffolgende Extension-Word (hier simuliert)
            -- bestimmt, ob Offset und Breite Konstanten oder dynamische Registerwerte sind.
            -- Bit 11 im Opcode/Extension bestimmt das Offset-Verhalten (0=Imm, 1=Reg)
            bf_offset_is_reg <= opcode(11);
            -- Bit 5 im Opcode/Extension bestimmt das Breiten-Verhalten (0=Imm, 1=Reg)
            bf_width_is_reg  <= opcode(5);
            
        end if;
    end process;

end behavioral;
