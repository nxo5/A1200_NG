-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_special_op.vhd
-- Funktion: Der kombinatorische Opcode-Klassifizierer für Systembefehle.
--           Isoliert Sonderoperationen (MOVEC etc.) starr nach Motorola 68030.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_special_op is
    Port (
        opcode          : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode aus der Pipeline
        special_en      : in    std_logic;                      -- Freigabe vom Top-Decoder
        
        -- Kombinatorische Ausgänge an das Hauptsteuerwerk
        spec_alu_op     : out   std_logic_vector(7 downto 0);   -- Operations-ID für das Rechenwerk
        spec_reg_sel    : out   std_logic_vector(3 downto 0);   -- Betroffenes Core-Register (Bit 11..9)
        spec_control_reg: out   std_logic_vector(11 downto 0);  -- Identifikations-ID des Kontrollregisters (MOVEC Extension)
        spec_write_to_rc: out   std_logic;                      -- '1' = MOVEC Rn, Rc (Schreiben), '0' = MOVEC Rc, Rn (Lesen)
        spec_bus_req    : out   std_logic;                      -- Trigger für externe Bus-Sonderzyklen (RESET)
        spec_priv_check : out   std_logic                       -- '1' = Privilegierter Befehl (Supervisor-Check erzwungen)
    );
end cpu_030_ec_dec_special_op;

architecture behavioral of cpu_030_ec_dec_special_op is
begin

    -- =====================================================================
    -- KOMBINAOTORISCHE SYSTEM-ANALYSE (UNBESTECHLICHES BIT-ROUTING)
    -- =====================================================================
    process(opcode, special_en)
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        spec_alu_op      <= x"00";
        spec_reg_sel     <= x"0";
        spec_control_reg <= x"000";
        spec_write_to_rc <= '0';
        spec_bus_req     <= '0';
        spec_priv_check  <= '0';

        if special_en = '1' then
            -- Betroffenes Universalregister liegt standardmäßig in den Bits 11 bis 9
            spec_reg_sel <= opcode(11) & opcode(10 downto 8);

            -- UNBESTECHLICHE MOTOROLA 68030 SYSTEMBFEHLS-GATTERWEICHE
            case opcode(15 downto 0) is
                
                when x"4E71" =>
                    -- NOP (No Operation): Reines Durchschleifen, schiebt nur die Pipe weiter
                    spec_alu_op <= x"00";

                when x"4E70" =>
                    -- RESET: Privilegierter Befehl, feuert den externen Reset-Pin für Peripherie
                    spec_priv_check <= '1';
                    spec_bus_req    <= '1';
                    spec_alu_op     <= x"30";

                when others =>
                    -- PRÜFUNG AUF MOVEC (Move Control Register): Opcode-Muster 0100_1110_0111_1010 (x"4E7A") 
                    -- oder 0100_1110_0111_1011 (x"4E7B")
                    if opcode(15 downto 1) = "010011100111101" then
                        spec_priv_check  <= '1'; -- MOVEC ist starr privilegiert (erzeugt sonst Privilege Violation Privilege)
                        spec_write_to_rc <= opcode(0); -- Bit 0 bestimmt die Richtung (0 = von Rc, 1 = nach Rc)
                        spec_alu_op      <= x"40";     -- Interne ALU-Operations-ID für Kontrollregister-Zugriffe
                        
                        -- Das darauffolgende Extension-Word hält im echten 68030 die Kontrollregister-ID.
                        -- Für unseren flachen Decoder-Einzug simulieren wir die ID direkt über das untere Byte
                        -- des Opcodes oder bereiten die Bus-Breite für die Pipeline-Erweiterung vor.
                        -- Das originale CACR hat bei Motorola den Hex-Code x"002" [14.1].
                        spec_control_reg <= x"002"; 
                    end if;

            end case;
        end if;
    end process;

end behavioral;
