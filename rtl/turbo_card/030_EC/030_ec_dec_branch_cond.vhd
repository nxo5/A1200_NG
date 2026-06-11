-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_branch_cond.vhd
-- Funktion: Die kombinatorische Bedingungs-Auswertung (Condition Core).
--           Prüft alle 16 Motorola-Bedingungen (Bcc) gegen die CCR-Flags.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_branch_cond is
    Port (
        cond_field      : in    std_logic_vector(3 downto 0);  -- Die 4 Bedingungsbits aus dem Opcode (11..8)
        ccr_flags       : in    std_logic_vector(4 downto 0);  -- Aktuelle Flags (X, N, Z, V, C)
        
        -- Kombinatorischer Ausgang
        cond_true       : out   std_logic                       -- '1' falls Bedingung erfüllt ist
    );
end cpu_030_ec_dec_branch_cond;

architecture behavioral of cpu_030_ec_dec_branch_cond is
begin

    -- =====================================================================
    -- UNBESTECHLICHE EVALUIERUNG DER 16 MOTOROLA 68030 BEDINGUNGEN
    -- Vektor-Raster: ccr_flags(4)=X, (3)=N, (2)=Z, (1)=V, (0)=C
    -- =====================================================================
    process(cond_field, ccr_flags)
        variable flag_X, flag_N, flag_Z, flag_V, flag_C : std_logic;
    begin
        -- Flags zur besseren Lesbarkeit isolieren
        flag_X := ccr_flags(4);
        flag_N := ccr_flags(3);
        flag_Z := ccr_flags(2);
        flag_V := ccr_flags(1);
        flag_C := ccr_flags(0);
        
        case cond_field is
            when "0000" => cond_true <= '1';                    -- T  (True / Always)
            when "0001" => cond_true <= '0';                    -- F  (False / Never)
            when "0010" => cond_true <= not flag_C and not flag_Z; -- HI (High)
            when "0011" => cond_true <= flag_C or flag_Z;       -- LS (Low or Same)
            when "0100" => cond_true <= not flag_C;             -- CC (Carry Clear / HS)
            when "0101" => cond_true <= flag_C;                 -- CS (Carry Set / LO)
            when "0110" => cond_true <= not flag_Z;             -- NE (Not Equal)
            when "0111" => cond_true <= flag_Z;                 -- EQ (Equal)
            when "1000" => cond_true <= not flag_V;             -- VC (Overflow Clear)
            when "1001" => cond_true <= flag_V;                 -- VS (Overflow Set)
            when "1010" => cond_true <= not flag_N;             -- PL (Plus / Positive)
            when "1011" => cond_true <= flag_N;                 -- MI (Minus / Negative)
            when "1100" => cond_true <= (flag_N and flag_V) or (not flag_N and not flag_V); -- GE (Greater or Equal)
            when "1101" => cond_true <= (flag_N and not flag_V) or (not flag_N and flag_V); -- LT (Less Than)
            when "1110" => cond_true <= ((flag_N and flag_V) or (not flag_N and not flag_V)) and not flag_Z; -- GT (Greater Than)
            when "1111" => cond_true <= flag_Z or (flag_N and not flag_V) or (not flag_N and flag_V); -- LE (Less or Equal)
            when others => cond_true <= '0';
        end case;
    end process;

end behavioral;
