-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_move.vhd
-- Funktion: Der entflochtene MOVE-Filial-Decoder des 68EC030.
-- REPARATUR:
--   - Richtungskonflikt (Error 10577/10599) restlos aufgelöst!
--   - ea_mode und ea_reg werden regelkonform als reine IN-Ports gelesen.
--   - Interne Treiber-Zuweisungen im Gatterkörper vollständig bereinigt.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_move is
    Port (
        -- Globale Systemsynchronisation
        CLK             : in    std_logic; 
        RESET_N         : in    std_logic; 
        
        -- Aktivierungssignal von der übergeordneten Exec-FSM
        move_en         : in    std_logic; 
        opcode          : in    std_logic_vector(15 downto 0);
        
        -- Schnittstelle zur geteilten Adress-Matrix (Echte IN-Eingänge!)
        ea_calc_start   : out   std_logic; 
        ea_mode         : in    std_logic_vector(2 downto 0); -- Passiver Lese-Eingang
        ea_reg          : in    std_logic_vector(2 downto 0); -- Passiver Lese-Eingang
        ea_ready        : in    std_logic; 
        ea_final_addr   : in    std_logic_vector(31 downto 0); 
        ea_is_register  : in    std_logic;
        
        -- Datenpfad-Ausgänge an den zentralen Core-Muxer
        move_size       : out   std_logic_vector(1 downto 0); 
        move_bus_req    : out   std_logic; 
        move_bus_write  : out   std_logic; 
        move_alu_op     : out   std_logic_vector(7 downto 0); 
        move_src_reg    : out   std_logic_vector(3 downto 0); 
        move_dst_reg    : out   std_logic_vector(3 downto 0); 
        move_ready      : out   std_logic
    );
end cpu_030_ec_dec_move;

architecture behavioral of cpu_030_ec_dec_move is
    -- Interne Registerstufen zur Entkopplung des Fließbands
    signal reg_move_ready : std_logic := '0';
begin

    -- Bereitschaftsmeldung direkt an das übergeordnete System spiegeln
    move_ready <= reg_move_ready;

    -- =====================================================================
    -- KOMBINAOTORISCHES DECODER-NETZWERK (0 WAIT-STATES PHASENPRÜFUNG)
    -- REPARATUR: Liest ea_mode / ea_reg rein passiv aus, kein unzulässiges Schreiben!
    -- =====================================================================
    process(move_en, opcode, ea_mode, ea_reg, ea_ready, ea_final_addr, ea_is_register)
    begin
        -- Sichere Standardwerte im Ruhezustand initialisieren
        ea_calc_start  <= '0';
        move_size      <= "00";
        move_bus_req   <= '0';
        move_bus_write <= '0';
        move_alu_op    <= x"00"; -- MOVE entspricht in der ALU meist einem Pass-Through
        move_src_reg   <= (others => '0');
        move_dst_reg   <= (others => '0');

        if move_en = '1' then
            ea_calc_start <= '1'; -- Signalisiert der geteilten Matrix Aktivität

            -- Motorola-Größencodierung für MOVE extrahieren (Bits 13-12: 01=B, 11=W, 10=L)
            case opcode(13 downto 12) is
                when "01"   => move_size <= "01"; -- Byte
                when "11"   => move_size <= "10"; -- Word
                when "10"   => move_size <= "00"; -- Longword
                when others => move_size <= "00";
            end case;

            -- UNBESTECHLICHE LANES-ABTASTUNG:
            -- Nutzt die eintreffenden Matrix-Signale absolut fehlerfrei als reine Lese-Quellen!
            if ea_ready = '1' then
                if ea_is_register = '0' then
                    -- Speicher-Zugriff erforderlich (Daten müssen über die BIU rollen)
                    move_bus_req <= '1';
                end if;

                -- Extraktion der Register-IDs für die Hauptregisterbank
                move_src_reg <= '0' & ea_reg; -- Quellregister aus den Matrix-Bits
                move_dst_reg <= '0' & opcode(11 downto 9); -- Zielregister starr aus den MOVE-Bits
            end if;
        end if;
    end process;

    -- =====================================================================
    -- SYNCHRONER PROZESS: PIPELINE-VERRASTUNG (TAKTSTEUERUNG)
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            reg_move_ready <= '0';
        elsif rising_edge(CLK) then
            if move_en = '1' then
                -- Quittiert den Befehl, sobald die Adress-Matrix stabile Daten meldet
                reg_move_ready <= ea_ready;
            else
                reg_move_ready <= '0';
            end if;
        end if;
    end process;

end behavioral;
