-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_branch.vhd
-- Teil:    1 von 2 (Entity und Architektur-Deklaration)
-- Funktion: Der Sprung- & Schleifen-Decoder (BRANCH) des 68EC030.
--           Evaluiert Bcc, BRA und BSR auf Basis der CCR-Flags.
--           ANPASSUNG: Echtes 32-Bit-Offset-Saugverfahren bei Opcode-Indikator
--                      x"FF" für weite Sprünge im 4-GB-Raum (Schritt 2/3)!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_branch is
    Port (
        -- Globale Systemsignale
        CLK             : in    std_logic;
        RESET_N         : in    std_logic;

        -- Steuersignale vom Top-Decoder-Wrapper
        branch_en       : in    std_logic;                      -- '1' signalisiert: Befehl ist ein Branch
        opcode          : in    std_logic_vector(15 downto 0);  -- Das aktuelle Befehlswort aus der Pipeline
        pc_current      : in    std_logic_vector(31 downto 0);  -- Aktueller Stand des Programmzählers (PC)
        alu_flags       : in    std_logic_vector(4 downto 0);   -- Aktuelle CCR-Flags (X, N, Z, V, C)
        
        -- NEU SCHRITT 2/3: Zusätzlicher Pipeline-Eingang für das nachfolgende Longword bei weiten Sprüngen
        pipeline_long   : in    std_logic_vector(31 downto 0);  -- Das direkt nachfolgende 32-Bit Daten-Longword

        -- Kombinatorische Ausgänge an den Steuerungs-Muxer
        branch_pc_load  : out   std_logic;                      -- Trigger: Sprung ausführen ('1') oder linear weiter ('0')
        branch_pc_new   : out   std_logic_vector(31 downto 0);  -- Berechnete 32-Bit Sprung-Zieladresse
        branch_ready    : out   std_logic                       -- Decoder meldet: Befehlszyklus beendet
    );
end cpu_030_ec_dec_branch;

architecture behavioral of cpu_030_ec_dec_branch is

begin

    -- =====================================================================
    -- KOMBINAOTORISCHES SPRUNGSTEUERWERK MIT 32-BIT LONGWORD-OFFSET
    -- =====================================================================
    process(branch_en, opcode, pc_current, alu_flags, pipeline_long)
        variable cond_true    : std_logic;
        variable offset_32    : signed(31 downto 0);
        variable pc_base      : signed(31 downto 0);
        variable target_pc    : signed(31 downto 0);
        variable cc_field     : std_logic_vector(3 downto 0);
        
        -- Flag-Variablen zur besseren Gatterlesbarkeit
        variable flag_N       : std_logic;
        variable flag_Z       : std_logic;
        variable flag_V       : std_logic;
        variable flag_C       : std_logic;
    begin
        -- Standard-Zuweisungen zur Latch-Vermeidung
        cond_true      := '0';
        offset_32      := (others => '0');
        pc_base        := signed(pc_current);
        target_pc      := signed(pc_current);
        branch_pc_load <= '0';
        branch_pc_new  <= pc_current;
        branch_ready   <= '0';

        -- Extrahieren der Bedingung (Bits 11 bis 8) und der CCR-Flags
        cc_field := opcode(11 downto 8);
        flag_N   := alu_flags(3);
        flag_Z   := alu_flags(2);
        flag_V   := alu_flags(1);
        flag_C   := alu_flags(0);

        if branch_en = '1' then
            branch_ready <= '1'; -- Gatterlauf im selben Takt beendet (0 Wait-States)
            
            -- 1. SCHRITT: UNBESTECHLICHE EVALUIERUNG DER 16 MOTOROLA-BEDINGUNGEN
            case cc_field is
                when x"0" => cond_true := '1';                                      -- BRA (Always)
                when x"1" => cond_true := '0';                                      -- BSR (Subroutine / Link wird im Wrapper erledigt)
                when x"2" => cond_true := not flag_C and not flag_Z;                -- BHI (High)
                when x"3" => cond_true := flag_C or flag_Z;                         -- BLS (Low or Same)
                when x"4" => cond_true := not flag_C;                               -- BCC (Carry Clear)
                when x"5" => cond_true := flag_C;                                   -- BCS (Carry Set)
                when x"6" => cond_true := not flag_Z;                               -- BNE (Not Equal)
                when x"7" => cond_true := flag_Z;                                   -- BEQ (Equal)
                when x"8" => cond_true := not flag_V;                               -- BVC (Overflow Clear)
                when x"9" => cond_true := flag_V;                                   -- BVS (Overflow Set)
                when x"A" => cond_true := not flag_N;                               -- BPL (Plus / Positive)
                when x"B" => cond_true := flag_N;                                   -- BMI (Minus / Negative)
                when x"C" => cond_true := (flag_N and flag_V) or (not flag_N and not flag_V); -- BGE (Greater or Equal)
                when x"D" => cond_true := (flag_N and not flag_V) or (not flag_N and flag_V); -- BLT (Less Than)
                when x"E" => cond_true := ((flag_N and flag_V) or (not flag_N and not flag_V)) and not flag_Z; -- BGT (Greater Than)
                when x"F" => cond_true := flag_Z or ((flag_N and not flag_V) or (not flag_N and flag_V)); -- BLE (Less or Equal)
                when others => null;
            end case;

            -- 2. SCHRITT FÜR DEN 32-BIT AUSBAU: ERMITTLUNG DER SPEZIFISCHEN OFFSET-BREITE
            if opcode(7 downto 0) = x"FF" then
                -- REPARATUR SCHRITT 2/3: Echtes 32-Bit Motorola-Longword-Offset aus der Pipeline einsaugen!
                offset_32 := signed(pipeline_long);
            elsif opcode(7 downto 0) = x"00" then
                -- Standard 16-Bit-Word-Offset (Liegt im nachfolgenden Pipeline-Wort, hier simuliert aus src_val/opcode)
                offset_32 := resize(signed(pipeline_long(15 downto 0)), 32);
            else
                -- Altes kompaktes 8-Bit-Byte-Offset (Direkt im unteren Byte des Opcodes eingebettet)
                offset_32 := resize(signed(opcode(7 downto 0)), 32);
            end if;

            -- 3. SCHRITT: BERECHNUNG DER 32-BIT ZIELADRESSE (PC_NEW = PC_CURRENT + 2 + OFFSET)
            -- Der Programmzähler zeigt laut Motorola beim Berechnen bereits auf das Wort hinter dem Opcode (+2)
            target_pc := pc_base + 2 + offset_32;

            -- Schaltet die neue Sprungadresse an den Core-Ausgang durch, falls Bedingung wahr ist
            if cond_true = '1' then
                branch_pc_load <= '1';
                branch_pc_new  <= std_logic_vector(target_pc);
            end if;
        end if;
    end process;

end behavioral;
