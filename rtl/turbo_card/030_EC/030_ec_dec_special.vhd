-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_special.vhd
-- Teil:    1 von 2 (Reale Entity-Schnittstelle)
-- Funktion: Der Special-Befehlsdecoder des 68EC030.
--           REPARATUR: Alle realen System-Ports (CLK, RESET_N, supervisor_mode,
--                      exception_priv etc.) buchstabengetreu restauriert!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_special is
    Port (
        -- Die realen globalen Systemreize (Vom Compiler gefordert!)
        CLK                 : in    std_logic;                      
        RESET_N             : in    std_logic;                      

        -- Schnittstelle zum übergeordneten Decoder-Netzwerk
        special_en          : in    std_logic;                      -- '1' = Sonderbefehls-Gatter zünden
        opcode              : in    std_logic_vector(15 downto 0);  -- Der aktuelle Opcode aus der Pipeline
        extension_word      : in    std_logic_vector(15 downto 0);  -- Das nachfolgende Motorola-Erweiterungswort
        
        -- Privilegierte Motorola-Schutzleitungen
        supervisor_mode     : in    std_logic;                      -- Aktueller CPU-Zustand (1=S, 0=U)
        exception_priv      : out   std_logic;                      -- Treibt den Privilege-Violation-Vektor (#8)
        
        -- Datenbus-Kopplung für Registertransfers (MOVEC)
        reg_data_in         : in    std_logic_vector(31 downto 0);  -- Datenwert aus dem Quellregister für MOVEC
        spec_bus_req        : out   std_logic;                      -- Signalisiert Sonder-Buszugriff an die BIU
        
        -- Cache-Steuerleitungen zum 128-KB-Subsystem
        cacr_ei             : out   std_logic;                      -- Enable Instruction Cache
        cacr_fi             : out   std_logic;                      -- Freeze Instruction Cache
        cacr_ed             : out   std_logic;                      -- Enable Data Cache
        cacr_fd             : out   std_logic;                      -- Freeze Data Cache
        cacr_ci             : out   std_logic;                      -- Clear Instruction Cache
        cacr_cd             : out   std_logic;                      -- Clear Data Cache
        
        -- Steuerleitungen zur Hauptregisterbank (SFC/DFC-Schnittstelle)
        ctrl_sfc_wren       : out   std_logic;                      -- SFC Schreibimpuls
        ctrl_dfc_wren       : out   std_logic;                      -- DFC Schreibimpuls
        ctrl_reg_data       : out   std_logic_vector(2 downto 0);   -- 3-Bit Funktionscode-Daten
        
        -- Statusrückmeldung an die Haupt-FSM
        special_ready       : out   std_logic                       -- Decoder meldet: Auswertung stabil beendet
    );
end cpu_030_ec_dec_special;

architecture behavioral of cpu_030_ec_dec_special is

begin

    -- =====================================================================
    -- REINER SYSTEMDECODER-PROZESS (0 WAIT-STATES)
    -- REPARATUR: Volle logische Port-Abdeckung und Latch-Eliminierung!
    -- =====================================================================
    process(special_en, opcode, extension_word, supervisor_mode, reg_data_in)
        -- Interne Variable für das Cache-Control-Register
        variable reg_CACR : std_logic_vector(15 downto 0);
    begin
        -- UNBEDINGTE VORAB-INITIALISIERUNG ZUR 100% LATCH-ELIMINIERUNG
        reg_CACR      := (others => '0');
        cacr_ei       <= '0';
        cacr_fi       <= '0';
        cacr_ed       <= '0';
        cacr_fd       <= '0';
        cacr_ci       <= '0';
        cacr_cd       <= '0';
        ctrl_sfc_wren <= '0';
        ctrl_dfc_wren <= '0';
        ctrl_reg_data <= "000";
        exception_priv<= '0';
        spec_bus_req  <= '0';
        special_ready <= '0';

        if special_en = '1' then
            special_ready <= '1'; -- Berechnungs-Gatter steht im selben Takt stabil

            -- =============================================================
            -- MOTOROLA MOVEC-BEFEHL (Move Control Register, Opcode: 0x4E7B)
            -- =============================================================
            if opcode = x"4E7B" then
                
                -- EISERNER PROTEKTOR: Privilegierte Befehlsprüfung (Vektor #8)
                if supervisor_mode = '0' then
                    exception_priv <= '1'; -- Harter Abbruch: User darf MOVEC nicht ausführen!
                else
                    -- Supervisor-Zustand ist aktiv: Zugriff legal gewähren
                    case extension_word(11 downto 0) is
                        
                        -- A: ZUGRIFF AUF DAS CACHE CONTROL REGISTER (CACR, ID: 0x002)
                        when x"002" =>
                            -- Der neue Registerwert wird direkt aus den Leitungen der
                            -- Hauptregisterbank (reg_data_in) entnommen.
                            reg_CACR := reg_data_in(15 downto 0);
                            
                            cacr_ei <= reg_CACR(0);  -- Bit 0: Enable Instruction Cache
                            cacr_fi <= reg_CACR(1);  -- Bit 1: Freeze Instruction Cache
                            cacr_ci <= reg_CACR(3);  -- Bit 3: Clear Instruction Cache
                            cacr_ed <= reg_CACR(8);  -- Bit 8: Enable Data Cache
                            cacr_fd <= reg_CACR(9);  -- Bit 9: Freeze Data Cache
                            cacr_cd <= reg_CACR(11); -- Bit 11: Clear Data Cache

                        -- B: ZUGRIFF AUF DAS SOURCE FUNCTION CODE REGISTER (SFC, ID: 0x000)
                        when x"000" =>
                            ctrl_sfc_wren <= '1';
                            ctrl_reg_data <= reg_data_in(2 downto 0); -- Holt die 3-Bit Kennung aus der Registerbank

                        -- C: ZUGRIFF AUF DAS DESTINATION FUNCTION CODE REGISTER (DFC, ID: 0x001)
                        when x"001" =>
                            ctrl_dfc_wren <= '1';
                            ctrl_reg_data <= reg_data_in(2 downto 0); -- Holt die 3-Bit Kennung aus der Registerbank

                        when others =>
                            null;
                    end case;
                end if;

            -- =============================================================
            -- HIER FOLGEN DIE RESTLICHEN REINEN KOMBINAOTORISCHEN SPECIALS
            -- =============================================================
            else
                null;
            end if;
        end if;
    end process;

end behavioral;
