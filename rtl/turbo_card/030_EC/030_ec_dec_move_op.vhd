-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_move_op.vhd
-- Funktion: Der isolierte, kombinatorische Opcode-Klassifizierer für MOVE.
--           Analysiert die Bitmuster des Opcodes starr nach Motorola 68030.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_move_op is
    Port (
        opcode          : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode aus der Pipeline
        move_en         : in    std_logic;                      -- Freigabe vom Top-Decoder
        
        -- Kombinatorische Ausgänge ans Hauptsteuerwerk
        ea_calc_start   : out   std_logic;                      -- Trigger für effektive Adressberechnung
        ea_mode         : out   std_logic_vector(2 downto 0);   -- Adressierungsmodus (Bits 5..3)
        ea_reg          : out   std_logic_vector(2 downto 0);   -- Adressierungsregister (Bits 2..0)
        
        move_bus_req    : out   std_logic;                      -- Bus-Zyklus für Transfer anfordern
        move_bus_write  : out   std_logic;                      -- '1' = Speicher beschreiben, '0' = Lesen
        move_alu_op     : out   std_logic_vector(7 downto 0);   -- Interne Operations-ID für das Rechenwerk
        move_src_reg    : out   std_logic_vector(3 downto 0);   -- Quellregister-Vektor an die ALU
        move_dst_reg    : out   std_logic_vector(3 downto 0)    -- Zielregister-Vektor an die ALU
    );
end cpu_030_ec_dec_move_op;

architecture behavioral of cpu_030_ec_dec_move_op is
begin

    -- =====================================================================
    -- REINES KOMBINAOTORISCHES BIT-ROUTING (DOPPEL-TREIBER-AUSWERTUNG)
    -- =====================================================================
    process(opcode, move_en)
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        ea_calc_start  <= '0';
        ea_mode        <= "000";
        ea_reg         <= "000";
        move_bus_req   <= '0';
        move_bus_write <= '0';
        move_alu_op    <= x"00";
        move_src_reg   <= x"0";
        move_dst_reg   <= x"0";

        if move_en = '1' then
            -- Ein MOVE-Befehl ist aktiv: Standardmäßig verlangt er Adressberechnung
            ea_calc_start <= '1';
            
            -- Extraktion der effektiven Quell-Adresse (Original Motorola Bits 5 downto 0)
            ea_mode <= opcode(5 downto 3);
            ea_reg  <= opcode(2 downto 0);
            
            -- Extraktion der Register-Vektoren für das Zusammenspiel mit der ALU
            -- Quellregister liegt in den Bits 2..0, Bit 3 bestimmt Dn/An über ea_mode
            if opcode(5 downto 3) = "001" then
                move_src_reg <= '1' & opcode(2 downto 0); -- Ziel ist ein Adressregister (An)
            else
                move_src_reg <= '0' & opcode(2 downto 0); -- Ziel ist ein Datenregister (Dn)
            end if;
            
            -- Zielregister liegt in den Bits 11..9, Bit 3 bestimmt Dn/An über Bits 8..6
            if opcode(8 downto 6) = "001" then
                move_dst_reg <= '1' & opcode(11 downto 9);
            else
                move_dst_reg <= '0' & opcode(11 downto 9);
            end if;

            -- UNBESTECHLICHE PROTOKOLL-WEICHE: Lese- oder Schreibzyklus ermitteln
            -- Wenn das Ziel kein Register ist (Bits 8..6 /= 000/001), geht der Wert ins RAM!
            if opcode(8 downto 6) /= "000" and opcode(8 downto 6) /= "001" then
                move_bus_req   <= '1';
                move_bus_write <= '1'; -- Echtes Schreiben in den Amiga-Speicherraum
                move_alu_op    <= x"00";
            else
                -- Register-zu-Register Transfer läuft rein intern über ein kurzes ALU-Durchschleifen
                move_bus_req   <= '0';
                move_bus_write <= '0';
                move_alu_op    <= x"01"; -- ALU-ID für die interne Register-Spiegelung
            end if;
            
        end if;
    end process;

end behavioral;
