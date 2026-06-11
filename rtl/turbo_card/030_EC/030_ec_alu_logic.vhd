-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_alu_logic.vhd
-- Funktion: Das rein kombinatorische Logik-Gatterwerk des 68EC030.
--           Verarbeitet AND, OR, EOR und NOT ohne Taktverzögerung.
--           Berechnet die CCR-Flags buchstabengetreu nach Motorola-Standard.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_alu_logic is
    Port (
        -- Operations-Parameter vom Decoder
        alu_opcode      : in    std_logic_vector(7 downto 0);   -- Rechenbefehl (x"03"=AND, x"04"=OR, x"05"=EOR, x"06"=NOT)
        alu_size        : in    std_logic_vector(1 downto 0);   -- Operationsbreite (00=B, 01=W, 10=L)
        
        -- Operanden-Eingänge aus der Registerbank
        src_val         : in    std_logic_vector(31 downto 0);  -- Quell-Operand
        dst_val         : in    std_logic_vector(31 downto 0);  -- Ziel-Operand
        current_flags   : in    std_logic_vector(4 downto 0);   -- Aktuelle CCR-Flags (X, N, Z, V, C)
        
        -- Kombinatorische Ausgänge an den Top-Wrapper
        result_out      : out   std_logic_vector(31 downto 0);  -- Berechnetes Logik-Ergebnis
        new_flags_out   : out   std_logic_vector(15 downto 0);  -- Vollständiger neuer Statusvektor
        flags_update_en : out   std_logic                       -- '1' signalisiert: Flags im SR aktualisieren
    );
end cpu_030_ec_alu_logic;

architecture behavioral of cpu_030_ec_alu_logic is
begin

    -- =====================================================================
    -- REINE KOMBINAOTORISCHE LOGIK-MATRIX (0 WAIT-STATES)
    -- =====================================================================
    process(alu_opcode, alu_size, src_val, dst_val, current_flags)
        variable res_v    : std_logic_vector(31 downto 0);
        variable flags    : std_logic_vector(15 downto 0);
        variable sign_bit : std_logic;
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        res_v           := dst_val;
        flags           := x"27" & "000" & current_flags; -- Aktuelle System-Bits beibehalten
        flags_update_en <= '0';
        sign_bit        := '0';

        if alu_opcode = x"03" or alu_opcode = x"04" or alu_opcode = x"05" or alu_opcode = x"06" then
            flags_update_en <= '1';
            
            -- 1. SCHRITT: REINE BITWEISE VERKNÜPFUNG JE NACH OP-CODE
            case alu_opcode is
                when x"03" => -- AND
                    res_v := dst_val and src_val;
                when x"04" => -- OR
                    res_v := dst_val or src_val;
                when x"05" => -- EOR (Exclusive OR)
                    res_v := dst_val xor src_val;
                when x"06" => -- NOT (Invertierung des Ziels)
                    res_v := not dst_val;
                when others =>
                    res_v := dst_val;
            end case;

            -- 2. SCHRITT: BREITEN-ABTASTUNG FÜR MOTOROLA-FLAGS
            -- Vorzeichen-Bit (Sign) für das Negative-Flag (N) ermitteln
            if alu_size = "10" then
                sign_bit := res_v(31);
            elsif alu_size = "01" then
                sign_bit := res_v(15);
            else
                sign_bit := res_v(7);
            end if;

            -- 3. SCHRITT: UNBESTECHLICHE MOTOROLA-FLAG-GENERIERUNG
            -- Negative-Flag (N): Setzen, wenn das MSB der aktiven Breite '1' ist
            flags(3) := sign_bit;

            -- Zero-Flag (Z): Prüfen, ob der aktive Datenraum komplett Null ist
            if (alu_size = "10" and res_v = x"00000000") or
               (alu_size = "01" and res_v(15 downto 0) = x"0000") or
               (alu_size = "00" and res_v(7 downto 0) = x"00") then
                flags(2) := '1';
            else
                flags(2) := '0';
            end if;

            -- EISERNE MOTOROLA-LOGIK-REGEL: V (Overflow) und C (Carry) werden IMMER gelöscht!
            flags(1) := '0'; -- Overflow = 0
            flags(0) := '0'; -- Carry = 0
            
            -- X (Extend) bleibt bei logischen Operationen laut Spezifikation völlig unberührt!
            flags(4) := current_flags(4);
            
        end if;

        -- Daten stabil an die Ausgänge übergeben
        result_out    <= res_v;
        new_flags_out <= flags;
    end process;

end behavioral;
