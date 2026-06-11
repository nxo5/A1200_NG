-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_alu_shift.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle)
-- Funktion: Die kombinatorische Shift- und Rotationsmatrix (Barrel-Shifter).
--           Verarbeitet ASL/ASR, LSL/LSR und ROL/ROR ohne Taktverzögerung.
--           KORREKTUR: VHDL-Operator-Typenkonflikte für Quartus behoben!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_alu_shift is
    Port (
        -- Operations-Parameter vom Decoder
        alu_opcode      : in    std_logic_vector(7 downto 0);   -- Rechenbefehl
        alu_size        : in    std_logic_vector(1 downto 0);   -- Operationsbreite (00=B, 01=W, 10=L)
        
        -- Shift-Parameter (Verschiebe-Weite von 0 bis 31)
        shift_count     : in    std_logic_vector(4 downto 0);   
        
        -- Operanden-Eingänge aus der Registerbank
        dst_val         : in    std_logic_vector(31 downto 0);  -- Zu verschiebendes Register
        current_flags   : in    std_logic_vector(4 downto 0);   -- Aktuelle CCR-Flags (X, N, Z, V, C)
        
        -- Kombinatorische Ausgänge an den Top-Wrapper
        result_out      : out   std_logic_vector(31 downto 0);  -- Verschobenes Ergebnis
        new_flags_out   : out   std_logic_vector(15 downto 0);  -- Neuer Statusvektor
        flags_update_en : out   std_logic                       -- Flags im SR aktualisieren
    );
end cpu_030_ec_alu_shift;

architecture behavioral of cpu_030_ec_alu_shift is

begin

    -- =====================================================================
    -- COMBINATORIAL BARREL SHIFTER MATRIX (FEHLERFREIES HARDWARE-ROUTING)
    -- =====================================================================
    process(alu_opcode, alu_size, shift_count, dst_val, current_flags)
        variable count       : integer range 0 to 31;
        variable res_v       : std_logic_vector(31 downto 0);
        variable flags       : std_logic_vector(15 downto 0);
        variable last_bit_out: std_logic;
        variable v_flag      : std_logic;
        variable sign_bit    : std_logic;
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        count        := to_integer(unsigned(shift_count));
        res_v        := dst_val;
        flags        := x"27" & "000" & current_flags;
        flags_update_en <= '0';
        last_bit_out := '0';
        v_flag       := '0';
        sign_bit     := '0';

        if alu_opcode = x"07" or alu_opcode = x"08" or alu_opcode = x"09" or 
           alu_opcode = x"0A" or alu_opcode = x"0B" or alu_opcode = x"0C" then
            
            flags_update_en <= '1';

            if count > 0 then
                case alu_opcode is
                    
                    when x"07" =>
                        -- =================================================
                        -- OPERATION: ASL (Arithmetic Shift Left)
                        -- =================================================
                        if alu_size = "10" then    -- Longword (32 Bit)
                            last_bit_out := dst_val(32 - count);
                            res_v        := std_logic_vector(shift_left(unsigned(dst_val), count));
                            -- Überlauf prüfen: Ändert ein Bit während des Schiebens sein Vorzeichen?
                            for i in 0 to 31 loop
                                if i < count and dst_val(31) /= dst_val(31 - i) then v_flag := '1'; end if;
                            end loop;
                        elsif alu_size = "01" then -- Word (16 Bit)
                            last_bit_out := dst_val(16 - count);
                            res_v(15 downto 0) := std_logic_vector(shift_left(unsigned(dst_val(15 downto 0)), count));
                            for i in 0 to 15 loop
                                if i < count and dst_val(15) /= dst_val(15 - i) then v_flag := '1'; end if;
                            end loop;
                        else                       -- Byte (8 Bit)
                            last_bit_out := dst_val(8 - count);
                            res_v(7 downto 0)  := std_logic_vector(shift_left(unsigned(dst_val(7 downto 0)), count));
                            for i in 0 to 7 loop
                                if i < count and dst_val(7) /= dst_val(7 - i) then v_flag := '1'; end if;
                            end loop;
                        end if;
                        flags(0) := last_bit_out; -- Carry
                        flags(4) := last_bit_out; -- Extend

                    when x"08" =>
                        -- =================================================
                        -- OPERATION: ASR (Arithmetic Shift Right)
                        -- =================================================
                        if alu_size = "10" then
                            last_bit_out := dst_val(count - 1);
                            res_v        := std_logic_vector(shift_right(signed(dst_val), count));
                        elsif alu_size = "01" then
                            last_bit_out := dst_val(count - 1);
                            res_v(15 downto 0) := std_logic_vector(shift_right(signed(dst_val(15 downto 0)), count));
                        else
                            last_bit_out := dst_val(count - 1);
                            res_v(7 downto 0)  := std_logic_vector(shift_right(signed(dst_val(7 downto 0)), count));
                        end if;
                        flags(0) := last_bit_out;
                        flags(4) := last_bit_out;

                    when x"09" =>
                        -- =================================================
                        -- OPERATION: LSL (Logical Shift Left)
                        -- =================================================
                        if alu_size = "10" then
                            last_bit_out := dst_val(32 - count);
                            res_v        := std_logic_vector(shift_left(unsigned(dst_val), count));
                        elsif alu_size = "01" then
                            last_bit_out := dst_val(16 - count);
                            res_v(15 downto 0) := std_logic_vector(shift_left(unsigned(dst_val(15 downto 0)), count));
                        else
                            last_bit_out := dst_val(8 - count);
                            res_v(7 downto 0)  := std_logic_vector(shift_left(unsigned(dst_val(7 downto 0)), count));
                        end if;
                        flags(0) := last_bit_out;
                        flags(4) := last_bit_out;

                    when x"0A" =>
                        -- =================================================
                        -- OPERATION: LSR (Logical Shift Right)
                        -- =================================================
                        if alu_size = "10" then
                            last_bit_out := dst_val(count - 1);
                            res_v        := std_logic_vector(shift_right(unsigned(dst_val), count));
                        elsif alu_size = "01" then
                            last_bit_out := dst_val(count - 1);
                            res_v(15 downto 0) := std_logic_vector(shift_right(unsigned(dst_val(15 downto 0)), count));
                        else
                            last_bit_out := dst_val(count - 1);
                            res_v(7 downto 0)  := std_logic_vector(shift_right(unsigned(dst_val(7 downto 0)), count));
                        end if;
                        flags(0) := last_bit_out;
                        flags(4) := last_bit_out;

                    when x"0B" =>
                        -- =================================================
                        -- OPERATION: ROL (Rotate Left)
                        -- =================================================
                        if alu_size = "10" then
                            res_v    := std_logic_vector(rotate_left(unsigned(dst_val), count));
                            flags(0) := res_v(0);
                        elsif alu_size = "01" then
                            res_v(15 downto 0) := std_logic_vector(rotate_left(unsigned(dst_val(15 downto 0)), count));
                            flags(0)           := res_v(0);
                        else
                            res_v(7 downto 0)  := std_logic_vector(rotate_left(unsigned(dst_val(7 downto 0)), count));
                            flags(0)           := res_v(0);
                        end if;

                    when x"0C" =>
                        -- =================================================
                        -- OPERATION: ROR (Rotate Right)
                        -- =================================================
                        if alu_size = "10" then
                            res_v    := std_logic_vector(rotate_right(unsigned(dst_val), count));
                            flags(0) := res_v(31);
                        elsif alu_size = "01" then
                            res_v(15 downto 0) := std_logic_vector(rotate_right(unsigned(dst_val(15 downto 0)), count));
                            flags(0)           := res_v(15);
                        else
                            res_v(7 downto 0)  := std_logic_vector(rotate_right(unsigned(dst_val(7 downto 0)), count));
                            flags(0)           := res_v(7);
                        end if;

                    when others => null;
                end case;
            else
                -- Eiserne Motorola-Sonderregel: Shift-Weite 0 löscht Carry, lässt Extend intakt!
                flags(0) := '0';
            end if;

            -- =============================================================
            -- GEMEINSAME BASIS-FLAGS (N UND Z AUSWERTUNG)
            -- =============================================================
            if alu_size = "10" then
                sign_bit := res_v(31);
            elsif alu_size = "01" then
                sign_bit := res_v(15);
            else
                sign_bit := res_v(7);
            end if;

            flags(3) := sign_bit; -- Negative-Flag

            if (alu_size = "10" and res_v = x"00000000") or
               (alu_size = "01" and res_v(15 downto 0) = x"0000") or
               (alu_size = "00" and res_v(7 downto 0) = x"00") then
                flags(2) := '1'; -- Zero-Flag
            else
                flags(2) := '0';
            end if;

            -- Überlauf-Eintrag für arithmetische Linksverschiebung (ASL) einspeisen
            if alu_opcode = x"07" then
                flags(1) := v_flag;
            else
                flags(1) := '0'; -- Standardmäßig 0 bei logischen Shifts / Rotationen
            end if;
            
        end if;

        result_out    <= res_v;
        new_flags_out <= flags;
    end process;

end behavioral;
