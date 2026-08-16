-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_ea_shared.vhd
-- Teil:    1 von 2 (Sanierten Entity-Schnittstelle)
-- Funktion: Zentrale, geteilte Berechnungs-Matrix für effektive Adressen (EA).
--           SCHRITT 6 SANIERUNG:
--           - Einbau von ea_sel_dest zur fehlerfreien MOVE-Zielphasen-Weiche.
--           - Rettet Speicher-zu-Speicher-Transfers vor Datenverlust.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_ea_shared is
    Port (
        -- Globale Systemsynchronisation
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Statussignale von der Master-Koordinierung / Exec-FSM
        opcode              : in    std_logic_vector(15 downto 0);  -- Das aktuelle Befehlswort
        move_active         : in    std_logic;                      -- '1' = MOVE-Decoder steuert den Befehl
        alu_active          : in    std_logic;                      -- '1' = ALU-Decoder steuert den Befehl
        
        -- KORREKTUR HEBEL A: Weichensignal zur Phasentrennung (0=Source, 1=Destination)
        ea_sel_dest         : in    std_logic;                      -- Schaltet bei MOVE auf die Ziel-Bits um

        -- Steuersignale an die internen Adressregister / Registerbank
        ea_calc_start       : out   std_logic;                      
        ea_mode             : out   std_logic_vector(2 downto 0);   
        ea_reg              : out   std_logic_vector(2 downto 0);   
        
        -- Quittungs- und Adressrückmeldungen an das übergeordnete System
        ea_ready            : out   std_logic;                      
        ea_final_addr       : out   std_logic_vector(31 downto 0);  
        ea_is_register      : out   std_logic                       
    );
end cpu_030_ec_dec_ea_shared;

architecture behavioral of cpu_030_ec_dec_ea_shared is

begin

    -- =====================================================================
    -- KORREKTUR HEBEL A: UMSCHALTBARE REIN KOMBINAOTORISCHE EA-AUSWERTUNG
    -- Schaltet Modus und Register je nach Befehlsphase (0=Src, 1=Dst) um.
    -- =====================================================================
    process(opcode, move_active, alu_active, ea_sel_dest)
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

        -- =================================================================
        -- FALLE 1: MOVE-DECODER AKTIV (SPEICHER-ZU-SPEICHER WEICHE)
        -- =================================================================
        if move_active = '1' then
            ea_calc_start <= '1';
            
            if ea_sel_dest = '1' then
                -- PHASE 2 (DESTINATION): Extrahiert die Ziel-Bits des MOVE [14.1]
                -- Modus liegt verdreht in 8..6, Registernummer in 11..9 [14.1]
                v_mode := opcode(8 downto 6);
                v_reg  := opcode(11 downto 9);
            else
                -- PHASE 1 (SOURCE): Extrahiert klassisch die Quell-Bits [14.1]
                v_mode := opcode(5 downto 3);
                v_reg  := opcode(2 downto 0);
            end if;

            -- Unbestechliche Register-Direktprüfung für das aktuelle Segment
            if v_mode = "000" or v_mode = "001" then
                ea_is_register <= '1';
            end if;

        -- =================================================================
        -- FALLE 2: REINES ALU-RECHENWERK AKTIV
        -- =================================================================
        elsif alu_active = '1' then
            -- Bei standardmäßigen ALU-Operationen immer Feld 5..3 und 2..0 [14.1]
            v_mode := opcode(5 downto 3);
            v_reg  := opcode(2 downto 0);
            ea_calc_start <= '1';

            if v_mode = "000" or v_mode = "001" then
                ea_is_register <= '1';
            end if;
        end if;

        -- Datenkanäle permanent und ohne Latenz an die Ausgangs-Ports durchreichen
        ea_mode <= v_mode;
        ea_reg  <= v_reg;
    end process;

end behavioral;
