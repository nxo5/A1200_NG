-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_alu_op.vhd
-- Funktion: Der isolierte, kombinatorische Opcode-Klassifizierer für ALU-Befehle.
--           Analysiert Operationen wie ADD/SUB starr nach Motorola 68030.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_alu_op is
    Port (
        opcode          : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode aus der Pipeline
        alu_dec_en      : in    std_logic;                      -- Freigabe vom Top-Decoder
        
        -- Kombinatorische Ausgänge ans Hauptsteuerwerk / Untermodule
        ea_calc_start   : out   std_logic;                      -- Trigger für effektive Adressberechnung
        ea_mode         : out   std_logic_vector(2 downto 0);   -- Adressierungsmodus (Bits 5..3)
        ea_reg          : out   std_logic_vector(2 downto 0);   -- Adressierungsregister (Bits 2..0)
        
        dec_alu_bus_req : out   std_logic;                      -- Bus-Zyklus für Operandenzugriff anfordern
        dec_alu_bus_w   : out   std_logic;                      -- '1' = Speicher beschreiben, '0' = Lesen
        dec_alu_op      : out   std_logic_vector(7 downto 0);   -- Interne Operations-ID für das Rechenwerk
        dec_alu_src_reg : out   std_logic_vector(3 downto 0);   -- Quellregister-Vektor an die ALU
        dec_alu_dst_reg : out   std_logic_vector(3 downto 0)    -- Zielregister-Vektor an die ALU
    );
end cpu_030_ec_dec_alu_op;

architecture behavioral of cpu_030_ec_dec_alu_op is
begin

    -- =====================================================================
    -- KOMBINATORISCHE MATHEMATIK-ANALYSE (REINES HARDWARE-ROUTING)
    -- =====================================================================
    process(opcode, alu_dec_en)
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        ea_calc_start   <= '0';
        ea_mode         <= "000";
        ea_reg          <= "000";
        dec_alu_bus_req <= '0';
        dec_alu_bus_w   <= '0';
        dec_alu_op      <= x"00";
        dec_alu_src_reg <= x"0";
        dec_alu_dst_reg <= x"0";

        if alu_dec_en = '1' then
            -- Wenn die Arithmetik-Klasse aktiv ist, wird standardmäßig die EA-Berechnung gestartet
            ea_calc_start <= '1';
            ea_mode       <= opcode(5 downto 3);
            ea_reg        <= opcode(2 downto 0);

            -- Extraktion der Registervektoren nach Motorola-Standard
            -- Bits 11..9 deklarieren immer das primäre Core-Register (Dn)
            -- Das effektive Adressfeld (Bits 5..0) deklariert den zweiten Operanden
            dec_alu_src_reg <= '0' & opcode(2 downto 0);  -- Quell-Register (Standard aus EA-Feld)
            dec_alu_dst_reg <= '0' & opcode(11 downto 9); -- Ziel-Register (Standard Dn)

            -- UNBESTECHLICHE OP-CODE-WEICHE FÜR ARITHMETISCHE HARDWARE-BEFEHLE
            case opcode(15 downto 12) is
                when "1101" =>
                    -- OP-CODE REIHE '1101': ADD / ADDA (Addition)
                    dec_alu_op <= x"01"; -- ALU-ID für Addition
                    
                    -- Richtungsauswertung über Bit 8 (0 = Dn + EA -> Dn, 1 = EA + Dn -> EA)
                    if opcode(8) = '1' and opcode(5 downto 3) /= "001" then
                        dec_alu_bus_req <= '1';
                        dec_alu_bus_w   <= '1'; -- Ergebnis wird zurück in den Speicherraum geschrieben
                        dec_alu_src_reg <= '0' & opcode(11 downto 9);
                        dec_alu_dst_reg <= '0' & opcode(2 downto 0);
                    end if;

                when "1001" =>
                    -- OP-CODE REIHE '1001': SUB / SUBA (Subtraktion)
                    dec_alu_op <= x"02"; -- ALU-ID für Subtraktion
                    
                    -- Richtungsauswertung über Bit 8 (0 = Dn - EA -> Dn, 1 = EA - Dn -> EA)
                    if opcode(8) = '1' and opcode(5 downto 3) /= "001" then
                        dec_alu_bus_req <= '1';
                        dec_alu_bus_w   <= '1';
                        dec_alu_src_reg <= '0' & opcode(11 downto 9);
                        dec_alu_dst_reg <= '0' & opcode(2 downto 0);
                    end if;

                when others =>
                    dec_alu_op <= x"00";
            end case;
            
        end if;
    end process;

end behavioral;
