-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_ea_shared.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle)
-- Funktion: Zentrale, geteilte Berechnungs-Matrix für effektive Adressen (EA).
--           Dient als exklusiver Dienstleister für MOVE- und ALU-Decoder.
--           Verhindert das doppelte Aufbauen der EA-LUT-Bäume im FPGA,
--           wodurch massiv Logikelemente (ALMs) eingespart werden!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_ea_shared is
    Port (
        -- Globale Systemsynchronisation
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Statussignale von der Master-Koordinierung
        opcode              : in    std_logic_vector(15 downto 0);  -- Das aktuelle Befehlswort
        move_active         : in    std_logic;                      -- '1' = MOVE-Decoder steuert den Befehl
        alu_active          : in    std_logic;                      -- '1' = ALU-Decoder steuert den Befehl

        -- Steuersignale an die internen Adressregister / Registerbank
        ea_calc_start       : out   std_logic;                      -- Trigger an das EA-Adressregister-Werk
        ea_mode             : out   std_logic_vector(2 downto 0);   -- Extrahierter Adressmodus (Bits 5-3)
        ea_reg              : out   std_logic_vector(2 downto 0);   -- Extrahierte Registernummer (Bits 2-0)
        
        -- Quittungs- und Adressrückmeldungen an das übergeordnete System
        ea_ready            : out   std_logic;                      -- Signalisiert dem Core ein stabiles EA-Ergebnis
        ea_final_addr       : out   std_logic_vector(31 downto 0);  -- Berechnete physische Zieladresse
        ea_is_register      : out   std_logic                       -- '1' = EA verbleibt intern im Daten-/Adressregister
    );
end cpu_030_ec_dec_ea_shared;

architecture behavioral of cpu_030_ec_dec_ea_shared is

begin

    -- =====================================================================
    -- REIN KOMBINATORISCHE EA-MATRIX-AUSWERTUNG (0 WAIT-STATES)
    -- =====================================================================
    process(opcode, move_active, alu_active)
        variable v_mode : std_logic_vector(2 downto 0);
        variable v_reg  : std_logic_vector(2 downto 0);
    begin
        -- Standard-Voreinstellung im Ruhezustand (Harte Nullen)
        v_mode         := "000";
        v_reg          := "000";
        ea_calc_start  <= '0';
        ea_ready       <= '1'; -- Standardmäßig sofort stabil
        ea_final_addr  <= (others => '0');
        ea_is_register <= '0';

        -- WEICHE: Welcher Decoder-Zweig fordert die EA-Matrix an?
        if move_active = '1' then
            -- Beim MOVE-Befehl liegen Modus und Register in den Bits 5-3 und 2-0 (Quell-EA)
            v_mode := opcode(5 downto 3);
            v_reg  := opcode(2 downto 0);
            ea_calc_start <= '1';
            
            -- Prüfen, ob es sich um einen reinen Register-Direktmodus handelt (D-Reg oder A-Reg)
            if v_mode = "000" or v_mode = "001" then
                ea_is_register <= '1';
            end if;

        elsif alu_active = '1' then
            -- Bei regulären ALU-Operationen liegen Modus und Register ebenfalls in den Bits 5-3 und 2-0
            v_mode := opcode(5 downto 3);
            v_reg  := opcode(2 downto 0);
            ea_calc_start <= '1';

            if v_mode = "000" or v_mode = "001" then
                ea_is_register <= '1';
            end if;
        end if;

        -- Datenkanäle permanent an die Ausgangs-Ports durchreichen
        ea_mode <= v_mode;
        ea_reg  <= v_reg;
    end process;

end behavioral;
