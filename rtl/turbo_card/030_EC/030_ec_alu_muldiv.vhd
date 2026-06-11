-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_alu_muldiv.vhd
-- Funktion: Das rein kombinatorische Multiplikations- & Divisionswerk (030).
--           Verarbeitet MULU, MULS, DIVU und DIVS ohne Taktverzögerung.
--           Inklusive unbestechlicher Division-by-Zero Exception-Weiche.
--           KORREKTUR: Divisions-Operandenbreiten via IEEE-Resize abgeglichen!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_alu_muldiv is
    Port (
        -- Operations-Parameter vom Decoder
        alu_opcode         : in    std_logic_vector(7 downto 0);   -- x"16"=MULU, x"17"=MULS, x"18"=DIVU, x"19"=DIVS
        
        -- Operanden-Eingänge aus der Registerbank
        src_val            : in    std_logic_vector(31 downto 0);  -- Quell-Operand (Divisor / Multiplikator)
        dst_val            : in    std_logic_vector(31 downto 0);  -- Ziel-Operand (Dividend / Multiplikand)
        current_flags      : in    std_logic_vector(4 downto 0);   -- Aktuelle CCR-Flags (X, N, Z, V, C)
        
        -- Kombinatorische Ausgänge an den Top-Wrapper
        result_out         : out   std_logic_vector(31 downto 0);  -- Berechnetes Gesamtergebnis
        new_flags_out      : out   std_logic_vector(15 downto 0);  -- Vollständiger neuer Statusvektor
        flags_update_en    : out   std_logic;                      -- Flags im SR aktualisieren
        
        -- Exception-Schnittstelle an das Steuerwerk
        exception_div_zero : out   std_logic                       -- Trigger für Division-by-Zero Exception (Vektor #5)
    );
end cpu_030_ec_alu_muldiv;

architecture behavioral of cpu_030_ec_alu_muldiv is
begin

    -- =====================================================================
    -- REINE SCHNELLE MATHEMATIK-MATRIX (0 WAIT-STATES GATTERLOGIK)
    -- =====================================================================
    process(alu_opcode, src_val, dst_val, current_flags)
        variable res_32          : std_logic_vector(31 downto 0);
        variable flags           : std_logic_vector(15 downto 0);
        
        -- Isolierte 16-Bit Zwischenvariablen zur Umgehung von Multiplikations-Konflikten
        variable src_16u         : unsigned(15 downto 0);
        variable dst_16u         : unsigned(15 downto 0);
        variable src_16s         : signed(15 downto 0);
        variable dst_16s         : signed(15 downto 0);
        
        variable mul_u32         : unsigned(31 downto 0);
        variable mul_s32         : signed(31 downto 0);
        
        -- NEU: 32-Bit erweiterte Divisoren für absolut symmetrische IEEE-Divisionen!
        variable src_32u         : unsigned(31 downto 0);
        variable src_32s         : signed(31 downto 0);
        
        variable quotient_32     : unsigned(31 downto 0);
        variable remainder_32    : unsigned(31 downto 0);
        variable quotient_32s    : signed(31 downto 0);
        variable remainder_32s   : signed(31 downto 0);
        
        variable div_zero_flag   : std_logic;
        variable overflow_flag   : std_logic;
    begin
        -- Sichere Standardwerte initialisieren, um Synthese-Latches zu verhindern
        res_32             := dst_val;
        flags              := x"27" & "000" & current_flags;
        flags_update_en    <= '0';
        div_zero_flag      := '0';
        overflow_flag      := '0';
        mul_u32            := (others => '0');
        mul_s32            := (others => '0');
        
        -- Operanden stabil für die Multiplikation vordefinieren
        src_16u            := unsigned(src_val(15 downto 0));
        dst_16u            := unsigned(dst_val(15 downto 0));
        src_16s            := signed(src_val(15 downto 0));
        dst_16s            := signed(dst_val(15 downto 0));
        
        -- KORREKTUR: Divisoren haargenau auf die geforderten 32 Bit expandieren (Resizing)
        src_32u            := resize(src_16u, 32);
        src_32s            := resize(src_16s, 32);

        if alu_opcode = x"16" or alu_opcode = x"17" or alu_opcode = x"18" or alu_opcode = x"19" then
            flags_update_en <= '1';
            
            case alu_opcode is
                
                -- =========================================================
                -- MULTIPLIKATION: MULU (Unsigned 16 x 16 -> 32 Bit)
                -- =========================================================
                when x"16" =>
                    mul_u32 := dst_16u * src_16u;
                    res_32  := std_logic_vector(mul_u32);
                    
                    flags(3) := res_32(31); -- N
                    if res_32 = x"00000000" then flags(2) := '1'; else flags(2) := '0'; end if; -- Z
                    flags(1) := '0'; -- V
                    flags(0) := '0'; -- C

                -- =========================================================
                -- MULTIPLIKATION: MULS (Signed 16 x 16 -> 32 Bit)
                -- =========================================================
                when x"17" =>
                    mul_s32 := dst_16s * src_16s;
                    res_32  := std_logic_vector(mul_s32);
                    
                    flags(3) := res_32(31);
                    if res_32 = x"00000000" then flags(2) := '1'; else flags(2) := '0'; end if;
                    flags(1) := '0';
                    flags(0) := '0';

                -- =========================================================
                -- DIVISION: DIVU (Unsigned 32 / 32 -> 16R_16Q)
                -- =========================================================
                when x"18" =>
                    if src_val(15 downto 0) = x"0000" then
                        div_zero_flag := '1';
                        res_32        := dst_val;
                    else
                        -- KORREKTUR: Symmetrische 32-Bit/32-Bit-Operation nach IEEE-Vorgabe!
                        quotient_32  := unsigned(dst_val) / src_32u;
                        remainder_32 := unsigned(dst_val) rem src_32u;
                        
                        -- Motorola-Hardware-Regel für Divisionsüberlauf (Quotient > 16 Bit)
                        if quotient_32 > 65535 then
                            overflow_flag := '1';
                            res_32        := dst_val; -- Register bleibt intakt
                        else
                            res_32 := std_logic_vector(remainder_32(15 downto 0)) & std_logic_vector(quotient_32(15 downto 0));
                        end if;
                    end if;
                    
                    if div_zero_flag = '0' then
                        flags(3) := res_32(15); -- N
                        if res_32(15 downto 0) = x"0000" then flags(2) := '1'; else flags(2) := '0'; end if; -- Z
                        flags(1) := overflow_flag;
                        flags(0) := '0'; -- C
                    end if;

                -- =========================================================
                -- DIVISION: DIVS (Signed 32 / 32 -> 16R_16Q)
                -- =========================================================
                when x"19" =>
                    if src_val(15 downto 0) = x"0000" then
                        div_zero_flag := '1';
                        res_32        := dst_val;
                    else
                        -- KORREKTUR: Symmetrische 32-Bit/32-Bit-Operation nach IEEE-Vorgabe!
                        quotient_32s  := signed(dst_val) / src_32s;
                        remainder_32s := signed(dst_val) rem src_32s;
                        
                        if quotient_32s > 32767 or quotient_32s < -32768 then
                            overflow_flag := '1';
                            res_32        := dst_val;
                        else
                            res_32 := std_logic_vector(remainder_32s(15 downto 0)) & std_logic_vector(quotient_32s(15 downto 0));
                        end if;
                    end if;
                    
                    if div_zero_flag = '0' then
                        flags(3) := res_32(15);
                        if res_32(15 downto 0) = x"0000" then flags(2) := '1'; else flags(2) := '0'; end if;
                        flags(1) := overflow_flag;
                        flags(0) := '0';
                    end if;

                when others =>
                    res_32 := dst_val;
            end case;
            
            flags(4) := current_flags(4);
        end if;

        -- Werte stabil ausgeben
        result_out         <= res_32;
        new_flags_out      <= flags;
        exception_div_zero <= div_zero_flag;
    end process;

end behavioral;
