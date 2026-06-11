-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_alu_core.vhd
-- Teil:    1 von 3 (Entity und Untermodul-Deklarationen)
-- Funktion: Das arithmetische Verteilerzentrum (Core) des 68EC030.
--           Instanziiert Logik, Shifter, Bitops und das Mul/Div-Werk.
--           ANPASSUNG: Unbestechliche, hardwaregetreue 32-Bit Sign-Extension
--                      für alle Adressregister-Operationen (Schritt 1/3 für 32-Bit)!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_alu_core is
    Port (
        -- Operations-Parameter vom Decoder
        alu_opcode      : in    std_logic_vector(7 downto 0);   -- Rechenbefehl (01=ADD, 02=SUB, etc.)
        alu_size        : in    std_logic_vector(1 downto 0);   -- Operationsbreite (00=B, 01=W, 10=L)
        dst_is_addr_reg : in    std_logic;                      -- '1' falls das Ziel ein An-Register ist

        -- Operanden-Eingänge aus der Registerbank
        src_val         : in    std_logic_vector(31 downto 0);  -- Quell-Operand
        dst_val         : in    std_logic_vector(31 downto 0);  -- Ziel-Operand
        current_flags   : in    std_logic_vector(4 downto 0);   -- Aktuelle CCR-Flags (X, N, Z, V, C)

        -- Kombinatorische Ausgänge an den Top-Wrapper / Registerbank
        result_out      : out   std_logic_vector(31 downto 0);  -- Berechnetes Gesamtergebnis
        new_flags_out   : out   std_logic_vector(15 downto 0);  -- Vollständiger neuer Statusvektor
        flags_update_en : out   std_logic;                      -- '1' signalisiert: Flags im SR aktualisieren
        
        -- Exception-Ausgang an das übergeordnete Steuerwerk
        exception_div_zero : out std_logic                      -- Trigger für Division-by-Zero Exception (Vektor #5)
    );
end cpu_030_ec_alu_core;

architecture structural of cpu_030_ec_alu_core is

    -- =====================================================================
    -- KOMPONENTENDEKLARATIONEN DER FUNKTIONALEN UNTERMODULE
    -- =====================================================================
    
    component cpu_030_ec_alu_logic
        Port (
            alu_opcode      : in    std_logic_vector(7 downto 0); alu_size : in std_logic_vector(1 downto 0);
            src_val         : in    std_logic_vector(31 downto 0); dst_val : in std_logic_vector(31 downto 0);
            current_flags   : in    std_logic_vector(4 downto 0);
            result_out      : out   std_logic_vector(31 downto 0); new_flags_out : out std_logic_vector(15 downto 0);
            flags_update_en : out   std_logic
        );
    end component;

    component cpu_030_ec_alu_shift
        Port (
            alu_opcode      : in    std_logic_vector(7 downto 0); alu_size : in std_logic_vector(1 downto 0);
            shift_count     : in    std_logic_vector(4 downto 0);
            dst_val         : in    std_logic_vector(31 downto 0); current_flags : in std_logic_vector(4 downto 0);
            result_out      : out   std_logic_vector(31 downto 0); new_flags_out : out std_logic_vector(15 downto 0);
            flags_update_en : out   std_logic
        );
    end component;

    component cpu_030_ec_alu_bitops
        Port (
            alu_opcode      : in    std_logic_vector(7 downto 0); alu_size : in std_logic_vector(1 downto 0);
            bit_pos         : in    std_logic_vector(4 downto 0);
            dst_val         : in    std_logic_vector(31 downto 0); current_flags : in std_logic_vector(4 downto 0);
            result_out      : out   std_logic_vector(31 downto 0); new_flags_out : out std_logic_vector(15 downto 0);
            flags_update_en : out   std_logic
        );
    end component;

    component cpu_030_ec_alu_muldiv
        Port (
            alu_opcode      : in    std_logic_vector(7 downto 0);
            src_val         : in    std_logic_vector(31 downto 0); dst_val : in std_logic_vector(31 downto 0);
            current_flags   : in    std_logic_vector(4 downto 0);
            result_out      : out   std_logic_vector(31 downto 0); new_flags_out : out std_logic_vector(15 downto 0);
            flags_update_en : out   std_logic;
            exception_div_zero : out std_logic
        );
    end component;

    -- =====================================================================
    -- Interne Verbindungssignale (Die Rechenbus-Leitungen des Cores)
    -- =====================================================================
    signal logic_res          : std_logic_vector(31 downto 0);
    signal logic_flags        : std_logic_vector(15 downto 0);
    signal logic_flags_en     : std_logic;

    signal shift_res          : std_logic_vector(31 downto 0);
    signal shift_flags        : std_logic_vector(15 downto 0);
    signal shift_flags_en     : std_logic;

    signal bitops_res         : std_logic_vector(31 downto 0);
    signal bitops_flags       : std_logic_vector(15 downto 0);
    signal bitops_flags_en    : std_logic;

    signal muldiv_res         : std_logic_vector(31 downto 0);
    signal muldiv_flags       : std_logic_vector(15 downto 0);
    signal muldiv_flags_en    : std_logic;

    signal arith_res          : std_logic_vector(31 downto 0);
    signal arith_flags        : std_logic_vector(15 downto 0);
    signal arith_flags_en     : std_logic;

begin

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNGEN DER KOMBINATORISCHEN UNTERMODULE
    -- =====================================================================
    i_alu_logic_unit : cpu_030_ec_alu_logic
        port map (
            alu_opcode => alu_opcode, alu_size => alu_size, src_val => src_val, dst_val => dst_val,
            current_flags => current_flags, result_out => logic_res, new_flags_out => logic_flags,
            flags_update_en => logic_flags_en
        );

    i_alu_shift_unit : cpu_030_ec_alu_shift
        port map (
            alu_opcode => alu_opcode, alu_size => alu_size, shift_count => src_val(4 downto 0), dst_val => dst_val,
            current_flags => current_flags, result_out => shift_res, new_flags_out => shift_flags,
            flags_update_en => shift_flags_en
        );

    i_alu_bitops_unit : cpu_030_ec_alu_bitops
        port map (
            alu_opcode => alu_opcode, alu_size => alu_size, bit_pos => src_val(4 downto 0), dst_val => dst_val,
            current_flags => current_flags, result_out => bitops_res, new_flags_out => bitops_flags,
            flags_update_en => bitops_flags_en
        );

    i_alu_muldiv_unit : cpu_030_ec_alu_muldiv
        port map (
            alu_opcode => alu_opcode, src_val => src_val, dst_val => dst_val, current_flags => current_flags,
            result_out => muldiv_res, new_flags_out => muldiv_flags, flags_update_en => muldiv_flags_en,
            exception_div_zero => exception_div_zero
        );

    -- =====================================================================
    -- ERWEITERTER ARITHMETISCHER PROZESS: JETZT MIT 32-BIT ADRESS-TURBO!
    -- =====================================================================
    process(alu_opcode, alu_size, dst_is_addr_reg, src_val, dst_val, current_flags)
        variable src_extended : signed(31 downto 0);
        variable dst_signed   : signed(31 downto 0);
        variable res_signed   : signed(32 downto 0); -- 33 Bit für Carry-Erkennung
        variable flags        : std_logic_vector(15 downto 0);
        variable sign_src     : std_logic;
        variable sign_dst     : std_logic;
        variable sign_res     : std_logic;
    begin
        -- Sichere Initialisierungen für die Synthese
        src_extended    := (others => '0');
        dst_signed      := signed(dst_val);
        res_signed      := (others => '0');
        flags           := x"27" & "000" & current_flags;
        arith_flags_en  <= '0';
        sign_src        := '0';
        sign_dst        := '0';
        sign_res        := '0';

        -- KORREKTUR SCHRITT 1/3: 32-Bit Vorzeichen-Erweiterung des Quell-Operanden
        if dst_is_addr_reg = '1' then
            -- Adressregister-Operationen: Werden IMMER auf volle 32 Bit vorzeichenerweitert!
            if alu_size = "01" then
                src_extended := resize(signed(src_val(15 downto 0)), 32); -- Word -> Longword
            else
                src_extended := signed(src_val); -- Longword bleibt starr
            end if;
        else
            -- Normale Datenregister-Operationen (Größentreu spiegeln)
            if alu_size = "00" then
                src_extended(7 downto 0) := signed(src_val(7 downto 0));
            elsif alu_size = "01" then
                src_extended(15 downto 0) := signed(src_val(15 downto 0));
            else
                src_extended := signed(src_val);
            end if;
        end if;

        -- Bestimmung der Vorzeichen-Prüfbits für die Flag-Logik
        if alu_size = "10" or dst_is_addr_reg = '1' then
            sign_src := src_extended(31);
            sign_dst := dst_signed(31);
        elsif alu_size = "01" then
            sign_src := src_extended(15);
            sign_dst := dst_signed(15);
        else
            sign_src := src_extended(7);
            sign_dst := dst_signed(7);
        end if;

        -- Ausführung der mathematischen Gatteroperation
        case alu_opcode is
            
            when x"01" => -- ADD / ADDA
                if dst_is_addr_reg = '1' then
                    -- Adressrechnung arbeitet starr im vollen 32-Bit-Band
                    res_signed(31 downto 0) := dst_signed + src_extended;
                    arith_flags_en         <= '1'; -- Weist die Registerbank an, das Ergebnis zu sichern
                else
                    -- Standard-Datenrechnung
                    if alu_size = "00" then
                        res_signed(8 downto 0) := signed('0' & dst_val(7 downto 0)) + signed('0' & src_val(7 downto 0));
                    elsif alu_size = "01" then
                        res_signed(16 downto 0) := signed('0' & dst_val(15 downto 0)) + signed('0' & src_val(15 downto 0));
                    else
                        res_signed := signed('0' & dst_val) + signed('0' & src_extended);
                    end if;
                    arith_flags_en <= '1';
                end if;

                -- Flag-Generierung nach Motorola-Spezifikation
                if dst_is_addr_reg = '0' then
                    sign_res := res_signed(to_integer(unsigned(alu_size)) * 8 + 7);
                    flags(3) := sign_res; -- N
                    
                    if (alu_size = "10" and res_signed(31 downto 0) = x"00000000") or
                       (alu_size = "01" and res_signed(15 downto 0) = x"0000") or
                       (alu_size = "00" and res_signed(7 downto 0) = x"00") then 
                        flags(2) := '1'; 
                    else 
                        flags(2) := '0'; 
                    end if; -- Z
                    
                    if (sign_src = sign_dst) and (sign_res /= sign_src) then flags(1) := '1'; else flags(1) := '0'; end if; -- V
                    
                    if alu_size = "10" then flags(0) := res_signed(32); flags(4) := res_signed(32);
                    elsif alu_size = "01" then flags(0) := res_signed(16); flags(4) := res_signed(16);
                    else flags(0) := res_signed(8); flags(4) := res_signed(8); end if; -- C/X
                else
                    -- EISERNE REGEL: Operationen auf Adressregister verändern NIEMALS die CCR-Flags!
                    flags(4 downto 0) := current_flags;
                end if;

            when x"02" => -- SUB / SUBA
                if dst_is_addr_reg = '1' then
                    res_signed(31 downto 0) := dst_signed - src_extended;
                    arith_flags_en         <= '1';
                else
                    res_signed     := signed('0' & dst_val) - signed('0' & src_extended);
                    arith_flags_en <= '1';
                end if;

                if dst_is_addr_reg = '0' then
                    sign_res := res_signed(31);
                    flags(3) := sign_res;
                    if res_signed(31 downto 0) = x"00000000" then flags(2) := '1'; else flags(2) := '0'; end if;
                    if (sign_src /= sign_dst) and (sign_res /= sign_dst) then flags(1) := '1'; else flags(1) := '0'; end if;
                    flags(0) := res_signed(32); flags(4) := res_signed(32);
                else
                    flags(4 downto 0) := current_flags;
                end if;

            when others => null;
        end case;

        arith_res   <= std_logic_vector(res_signed(31 downto 0));
        arith_flags <= flags;
    end process;

    -- =====================================================================
    -- KOMBINATORISCHES AUSGANGS-MULTIPLEXER-FELD
    -- =====================================================================
    process(alu_opcode, dst_val, arith_res, arith_flags, arith_flags_en,
            logic_res, logic_flags, logic_flags_en,
            shift_res, shift_flags, shift_flags_en,
            bitops_res, bitops_flags, bitops_flags_en,
            muldiv_res, muldiv_flags, muldiv_flags_en)
    begin
        result_out      <= dst_val;
        new_flags_out   <= x"27" & "000" & current_flags;
        flags_update_en <= '0';

        case alu_opcode is
            when x"01" | x"02" =>
                result_out      <= arith_res;
                new_flags_out   <= arith_flags;
                flags_update_en <= arith_flags_en;

            when x"03" | x"04" | x"05" | x"06" =>
                result_out      <= logic_res;
                new_flags_out   <= logic_flags;
                flags_update_en <= logic_flags_en;

            when x"07" | x"08" | x"09" | x"0A" | x"0B" | x"0C" =>
                result_out      <= shift_res;
                new_flags_out   <= shift_flags;
                flags_update_en <= shift_flags_en;

            when x"0D" | x"0E" | x"0F" | x"15" =>
                result_out      <= bitops_res;
                new_flags_out   <= bitops_flags;
                flags_update_en <= bitops_flags_en;

            when x"16" | x"17" | x"18" | x"19" =>
                result_out      <= muldiv_res;
                new_flags_out   <= muldiv_flags;
                flags_update_en <= muldiv_flags_en;

            when others => null;
        end case;
    end process;

end structural;
