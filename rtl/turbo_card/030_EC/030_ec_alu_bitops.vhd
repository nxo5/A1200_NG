-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_alu_bitops.vhd
-- Funktion: Das rein kombinatorische Bit-Test- und Manipulationswerk (68030).
--           Verarbeitet BTST, BSET, BCLR und BCHG ohne Taktverzögerung.
--           Steuert das Zero-Flag (Z) starr nach originalem Motorola-Standard.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_alu_bitops is
    Port (
        -- Operations-Parameter vom Decoder
        alu_opcode      : in    std_logic_vector(7 downto 0);   -- Rechenbefehl (x"0D"=BTST, x"0E"=BSET, x"0F"=BCLR, x"15"=BCHG)
        alu_size        : in    std_logic_vector(1 downto 0);   -- Operationsbreite (00=Byte bei RAM, 10=Longword bei Register)
        
        -- Die ermittelte Bit-Position (0 bis 7 bei Byte, 0 bis 31 bei Longword)
        bit_pos         : in    std_logic_vector(4 downto 0);
        
        -- Operanden-Eingänge aus der Registerbank
        dst_val         : in    std_logic_vector(31 downto 0);  -- Das zu testende/manipulierende Ziel
        current_flags   : in    std_logic_vector(4 downto 0);   -- Aktuelle CCR-Flags (X, N, Z, V, C)
        
        -- Kombinatorische Ausgänge an den Top-Wrapper
        result_out      : out   std_logic_vector(31 downto 0);  -- Das manipulierte Ergebnis
        new_flags_out   : out   std_logic_vector(15 downto 0);  -- Vollständiger neuer Statusvektor
        flags_update_en : out   std_logic                       -- '1' signalisiert: Flags im SR aktualisieren
    );
end cpu_030_ec_alu_bitops;

architecture behavioral of cpu_030_ec_alu_bitops is
begin

    -- =====================================================================
    -- COMBINATORIAL BIT-MANIPULATION MATRIX (REINES HARDWARE-ROUTING)
    -- =====================================================================
    process(alu_opcode, alu_size, bit_pos, dst_val, current_flags)
        variable bit_idx : integer range 0 to 31;
        variable res_v   : std_logic_vector(31 downto 0);
        variable flags   : std_logic_vector(15 downto 0);
        variable bit_st  : std_logic;
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        res_v           := dst_val;
        flags           := x"27" & "000" & current_flags;
        flags_update_en <= '0';
        bit_st          := '0';
        
        -- Bit-Index anhand der Operationsbreite maskieren
        if alu_size = "00" then
            bit_idx := to_integer(unsigned(bit_pos(2 downto 0))); -- Byte-Zugriff (0 bis 7)
        else
            bit_idx := to_integer(unsigned(bit_pos));             -- Longword-Zugriff (0 bis 31)
        end if;

        if alu_opcode = x"0D" or alu_opcode = x"0E" or alu_opcode = x"0F" or alu_opcode = x"15" then
            flags_update_en <= '1';
            
            -- 1. SCHRITT: ZUSTAND DES ZIEL-BITS ERMITTELN (FÜR DAS ZERO-FLAG)
            bit_st := dst_val(bit_idx);

            -- 2. SCHRITT: BIT-MANIPULATION JE NACH BEFEHLSTYP AUSFÜHREN
            case alu_opcode is
                when x"0D" => -- BTST (Bit Test): Das Ziel bleibt vollkommen unberührt
                    res_v := dst_val;
                    
                when x"0E" => -- BSET (Bit Test and Set): Setzt das Bit starr auf '1'
                    res_v := dst_val;
                    res_v(bit_idx) := '1';
                    
                when x"0F" => -- BCLR (Bit Test and Clear): Löscht das Bit starr auf '0'
                    res_v := dst_val;
                    res_v(bit_idx) := '0';
                    
                when x"15" => -- BCHG (Bit Test and Change): Invertiert den aktuellen Zustand des Bits
                    res_v := dst_val;
                    res_v(bit_idx) := not bit_st;
                    
                when others =>
                    res_v := dst_val;
            end case;

            -- 3. SCHRITT: UNBESTECHLICHE MOTOROLA-FLAG-STEUERUNG
            -- Eiserne 68000/020/030-Regel: Das Zero-Flag (Z) wird auf das INVERSE des getesteten Bits gesetzt!
            -- War das Bit '0', wird Z '1' (Befehl meldet Treffer / Gleichheit). War das Bit '1', wird Z '0'.
            flags(2) := not bit_st;

            -- Alle anderen Zustandbits (X, N, V, C) verbleiben laut Motorola-Spezifikation unberührt!
            flags(4) := current_flags(4); -- X intakt
            flags(3) := current_flags(3); -- N intakt
            flags(1) := current_flags(1); -- V intakt
            flags(0) := current_flags(0); -- C intakt
            
        end if;

        -- Werte stabil ausgeben
        result_out    <= res_v;
        new_flags_out <= flags;
    end process;

end behavioral;
