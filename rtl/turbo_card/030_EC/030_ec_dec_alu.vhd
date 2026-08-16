-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_alu.vhd
-- Funktion: Der entflochtene ALU-Filial-Decoder des 68EC030.
-- REPARATUR:
--   - Richtungskonflikt (Error 10577/10599) restlos aufgelöst!
--   - ea_mode und ea_reg werden regelkonform als reine IN-Ports gelesen.
--   - Interne Treiber-Zuweisungen im Gatterkörper vollständig bereinigt.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_alu is
    Port (
        -- Globale Systemsynchronisation
        CLK             : in    std_logic; 
        RESET_N         : in    std_logic; 
        
        -- Aktivierungssignal von der übergeordneten Exec-FSM
        alu_dec_en      : in    std_logic; 
        opcode          : in    std_logic_vector(15 downto 0);
        
        -- Schnittstelle zur geteilten Adress-Matrix (Echte IN-Eingänge!)
        ea_calc_start   : out   std_logic; 
        ea_mode         : in    std_logic_vector(2 downto 0); -- Passiver Lese-Eingang
        ea_reg          : in    std_logic_vector(2 downto 0); -- Passiver Lese-Eingang
        ea_ready        : in    std_logic; 
        ea_final_addr   : in    std_logic_vector(31 downto 0); 
        ea_is_register  : in    std_logic;
        
        -- Datenpfad-Ausgänge an den zentralen Core-Muxer
        dec_alu_size    : out   std_logic_vector(1 downto 0); 
        dec_alu_bus_req : out   std_logic; 
        dec_alu_bus_w   : out   std_logic; 
        dec_alu_op      : out   std_logic_vector(7 downto 0); 
        dec_alu_src_reg : out   std_logic_vector(3 downto 0); 
        dec_alu_dst_reg : out   std_logic_vector(3 downto 0); 
        dec_alu_ready   : out   std_logic
    );
end cpu_030_ec_dec_alu;

architecture behavioral of cpu_030_ec_dec_alu is
    -- Interne Registerstufen zur Entkopplung des Fließbands
    signal reg_alu_ready : std_logic := '0';
begin

    -- Bereitschaftsmeldung direkt an das übergeordnete System spiegeln
    dec_alu_ready <= reg_alu_ready;

    -- =====================================================================
    -- KOMBINAOTORISCHES DECODER-NETZWERK (0 WAIT-STATES PHASENPRÜFUNG)
    -- REPARATUR: Liest ea_mode / ea_reg rein passiv aus, kein unzulässiges Schreiben!
    -- =====================================================================
    process(alu_dec_en, opcode, ea_mode, ea_reg, ea_ready, ea_final_addr, ea_is_register)
    begin
        -- Sichere Standardwerte im Ruhezustand initialisieren
        ea_calc_start   <= '0';
        dec_alu_size    <= "00";
        dec_alu_bus_req <= '0';
        dec_alu_bus_w   <= '0';
        dec_alu_op      <= x"00";
        dec_alu_src_reg <= (others => '0');
        dec_alu_dst_reg <= (others => '0');

        if alu_dec_en = '1' then
            ea_calc_start <= '1'; -- Aktiviert das geteilte Adresswerk

            -- Motorola-Größencodierung für Standard-ALU-Befehle (Bits 7-6: 00=B, 01=W, 10=L)
            case opcode(7 downto 6) is
                when "00"   => dec_alu_size <= "01"; -- Byte
                when "01"   => dec_alu_size <= "10"; -- Word
                when "10"   => dec_alu_size <= "00"; -- Longword
                when others => dec_alu_size <= "00";
            end case;

            -- Extraktion des echten Opcodes für das Rechenwerk (ALU-Execution-Top)
            -- Filtert typische Muster wie ADD, SUB, AND, OR aus den oberen Bits
            dec_alu_op <= opcode(15 downto 12) & opcode(11 downto 8);

            -- UNBESTECHLICHE LANES-ABTASTUNG:
            -- Nutzt die eintreffenden Matrix-Signale absolut fehlerfrei als reine Lese-Quellen!
            if ea_ready = '1' then
                if ea_is_register = '0' then
                    -- Speicher-Zugriff erforderlich (Daten für Operation von Außen holen)
                    dec_alu_bus_req <= '1';
                end if;

                -- Extraktion der Register-IDs für die Hauptregisterbank
                dec_alu_src_reg <= '0' & ea_reg; -- Quellregister aus den Matrix-Bits
                dec_alu_dst_reg <= '0' & opcode(11 downto 9); -- Zielregister starr aus dem Opcode
            end if;
        end if;
    end process;

    -- =====================================================================
    -- SYNCHRONER PROZESS: PIPELINE-VERRASTUNG (TAKTSTEUERUNG)
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            reg_alu_ready <= '0';
        elsif rising_edge(CLK) then
            if alu_dec_en = '1' then
                -- Quittiert den Befehl, sobald das Adress-Stellwerk stabil meldet
                reg_alu_ready <= ea_ready;
            else
                reg_alu_ready <= '0';
            end if;
        end if;
    end process;

end behavioral;
