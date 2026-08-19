-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_bus_fsm.vhd
-- Teil:    1 (Entity und interne Signalpuffer)
-- Funktion: Die getaktete Protokoll-Zustandsmaschine (BIU-FSM) des 68EC030.
--           Zyklustreues 32-Bit-Design mit RMW-Verriegelung.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_bus_fsm is
    Port (
        CLK                 : in    std_logic;                      
        RESET_N             : in    std_logic;                      

        -- Steuerkanäle vom internen Core / Decoder
        cycle_start         : in    std_logic;                      
        cycle_write         : in    std_logic;                      
        cycle_rmw           : in    std_logic;                      
        cycle_size          : in    std_logic_vector(1 downto 0);   

        -- Synchronisierte Quittungsleitungen aus der BIU-Pipeline
        ext_DSACK0_N        : in    std_logic;                      
        ext_DSACK1_N        : in    std_logic;                      
        ext_STERM_N         : in    std_logic;                      
        ext_BERR_N          : in    std_logic;                      

        -- Arbitrierungsleitungen nach außen (Hardware-DMA)
        ext_BR_N            : in    std_logic;                      
        ext_BG_N            : out   std_logic;                      
        ext_BGACK_N         : in    std_logic;                      

        -- Express-Cache-Signale
        ext_CBREQ_N         : out   std_logic;                      
        ext_CBACK_N         : in    std_logic;                      
        ext_RMC_N           : out   std_logic;                      

        -- Interne Statussignale an das Core-Fließband
        fsm_busy            : out   std_logic;                      
        fsm_cycle_done      : out   std_logic;                      
        
        -- Treiber-Leitungen an den Datenbus-Multiplexer (cpu_030_ec_bus_mux)
        fsm_strobe_en       : out   std_logic;                      
        fsm_ds_en           : out   std_logic;                      
        fsm_write_en        : out   std_logic;                      
        fsm_tristate_en     : out   std_logic;                      
        fsm_burst_cnt       : out   std_logic_vector(1 downto 0);   
        fsm_sizing_offset   : out   std_logic_vector(1 downto 0)    
    );
end cpu_030_ec_bus_fsm;

architecture behavioral of cpu_030_ec_bus_fsm is

    type bus_state_type is (
        BUS_IDLE, BUS_ARBITRATED, BUS_S0, BUS_S2, BUS_S4_WAIT, 
        BUS_BURST_1, BUS_BURST_2, BUS_BURST_3, BUS_S5_DONE, 
        BUS_TURN_AROUND,
        BUS_SIZ_PAUSE_2, BUS_SIZ_CYCLE_2, 
        BUS_SIZ_PAUSE_3, BUS_SIZ_CYCLE_3,
        BUS_SIZ_PAUSE_4, BUS_SIZ_CYCLE_4
    );
    
    signal current_bus_state : bus_state_type := BUS_IDLE;

    -- Synchrone Registerpuffer zur Leitungsisolierung
    signal reg_strobe_en     : std_logic := '0';
    signal reg_ds_en         : std_logic := '0';
    signal fsm_write_en_sig  : std_logic := '0';
    signal reg_bg_n          : std_logic := '1';
    signal reg_tristate      : std_logic := '0';
    signal reg_cbreq_n       : std_logic := '1';
    signal reg_rmc_n         : std_logic := '1';
    signal reg_burst_cnt     : std_logic_vector(1 downto 0) := "00";
    signal reg_sizing_offset : std_logic_vector(1 downto 0) := "00";

	 begin

    -- Physikalische Kontroll-Ausgänge permanent stabil an das Weichenwerk koppeln
    ext_BG_N          <= reg_bg_n;
    fsm_tristate_en   <= reg_tristate;
    ext_CBREQ_N       <= reg_cbreq_n;
    fsm_strobe_en     <= reg_strobe_en;
    fsm_ds_en         <= reg_ds_en; 
    fsm_write_en      <= fsm_write_en_sig;
    fsm_burst_cnt     <= reg_burst_cnt;
    fsm_sizing_offset <= reg_sizing_offset;
    ext_RMC_N         <= reg_rmc_n;

    -- =====================================================================
    -- SYNCHRONER CONTROL-PROZESS: SYSTEMTAKTIERTE BUS-ZUSTANDSMASCHINE
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            current_bus_state <= BUS_IDLE;
            fsm_busy          <= '0';
            fsm_cycle_done    <= '0';
            reg_strobe_en     <= '0';
            reg_ds_en         <= '0';
            fsm_write_en_sig  <= '0';
            reg_bg_n          <= '1';
            reg_tristate      <= '0';
            reg_cbreq_n       <= '1';
            reg_rmc_n         <= '1'; 
            reg_burst_cnt     <= "00";
            reg_sizing_offset <= "00";
            
        elsif rising_edge(CLK) then
            fsm_cycle_done <= '0'; -- Standard-Impuls pro Takt zurücksetzen
            
            case current_bus_state is
                
                -- ---------------------------------------------------------
                -- BUS_IDLE: RESETS UND UNBESTECHLICHE RMC-SPERR-PRÜFUNG
                -- ---------------------------------------------------------
                when BUS_IDLE =>
                    fsm_busy          <= '0';
                    reg_strobe_en     <= '0';
                    reg_ds_en         <= '0';
                    fsm_write_en_sig  <= '0';
                    reg_tristate      <= '0';
                    reg_cbreq_n       <= '1'; 
                    reg_burst_cnt     <= "00"; 
                    reg_sizing_offset <= "00";

                    if cycle_rmw = '0' then
                        reg_rmc_n <= '1'; -- RMC-Sperre nur fallen lassen, wenn Core freigibt
                    end if;

                    -- EXKLUSIVER DMA-TÜRSTEHER: Blockiert externe Busanforderungen bei RMC = '0'
                    if ext_BR_N = '0' and reg_rmc_n = '1' then
                        reg_bg_n          <= '0';
                        if ext_BGACK_N = '0' then
                            reg_tristate      <= '1';
                            fsm_busy          <= '1';
                            current_bus_state <= BUS_ARBITRATED;
                        end if;
                        
                    elsif cycle_start = '1' then
                        fsm_busy <= '1';
                        reg_bg_n <= '1';
                        
                        if cycle_rmw = '1' then
                            reg_rmc_n <= '0'; -- Unteilbare Hardware-Sperre sofort verriegeln
                        end if;
                        
                        current_bus_state <= BUS_S0;
                    else
                        reg_bg_n <= '1';
                    end if;

						                  -- ---------------------------------------------------------
                -- BUS_S0: DER ABSTREIF-TAKTMUX (ADRESSEN STABILISIEREN)
                -- ---------------------------------------------------------
                when BUS_S0 =>
                    reg_strobe_en    <= '1'; -- AS_N wird unbarmherzig gefeuert
                    fsm_write_en_sig <= cycle_write;
                    current_bus_state <= BUS_S2;

                -- ---------------------------------------------------------
                -- BUS_S2: DATEN-STROBE AKTIVIEREN
                -- ---------------------------------------------------------
                when BUS_S2 =>
                    reg_ds_en <= '1'; -- DS_N atmet ein
                    if cycle_write = '0' and cycle_rmw = '0' then
                        reg_cbreq_n <= '0'; -- Cache-Zeile nur bei reinem Lesen anfordern
                    end if;
                    current_bus_state <= BUS_S4_WAIT;

                -- ---------------------------------------------------------
                -- BUS_S4_WAIT: KORREKTUR: ZYKLUSTREUER WAIT-STATE-GENERATOR [14.1]
                -- Hält die Strobes starr aktiv, bis das langsame Mainboard quittiert!
                -- ---------------------------------------------------------
                when BUS_S4_WAIT =>
                    if ext_BERR_N = '0' then
                        reg_cbreq_n       <= '1';
                        current_bus_state <= BUS_S5_DONE;
                        
                    elsif ext_STERM_N = '0' then
                        if ext_CBACK_N = '0' and cycle_write = '0' then
                            reg_burst_cnt     <= "01"; 
                            current_bus_state <= BUS_BURST_1;
                        else
                            reg_cbreq_n       <= '1';
                            current_bus_state <= BUS_S5_DONE;
                        end if;
                        
                    elsif ext_DSACK1_N = '0' or ext_DSACK0_N = '0' then
                        reg_cbreq_n <= '1'; 
                        
                        if ext_DSACK1_N = '0' and ext_DSACK0_N = '0' then
                            current_bus_state <= BUS_S5_DONE; -- Voller 32-Bit Port fertig
                            
                        elsif cycle_size = "00" then
                            current_bus_state <= BUS_S5_DONE;
                            
                        elsif cycle_size = "01" and ext_DSACK1_N = '0' and ext_DSACK0_N = '1' then
                            current_bus_state <= BUS_S5_DONE;
                        else
                            current_bus_state <= BUS_SIZ_PAUSE_2;
                        end if;
                    else
                        -- ANSONSTEN: Halte die Daten- und Adressstrobes unnachgiebig auf Active-Low! [14.1]
                        reg_strobe_en     <= '1';
                        reg_ds_en         <= '1';
                        current_bus_state <= BUS_S4_WAIT; -- Schleife schließt latch- und glitchfrei [14.1]
                    end if;


					 -- =========================================================
                -- RESTRICHTE SCHLEIFENPHASEN FÜR SIZING-FOLGEZYKLEN
                -- =========================================================
                when BUS_SIZ_PAUSE_2 =>
                    reg_strobe_en <= '1'; -- Address Strobe bleibt starr aktiv!
                    reg_ds_en     <= '0'; -- Data Strobe atmet kurz aus
                    
                    if ext_DSACK1_N = '0' and ext_DSACK0_N = '1' then
                        reg_sizing_offset <= "10"; 
                    else
                        reg_sizing_offset <= "01"; 
                    end if;
                    current_bus_state <= BUS_SIZ_CYCLE_2;

                when BUS_SIZ_CYCLE_2 =>
                    reg_strobe_en <= '1';
                    reg_ds_en     <= '1'; 
                    
                    if ext_DSACK1_N = '0' or ext_DSACK0_N = '0' or ext_STERM_N = '0' then
                        if reg_sizing_offset = "10" then
                            current_bus_state <= BUS_S5_DONE; 
                        else
                            current_bus_state <= BUS_SIZ_PAUSE_3; 
                        end if;
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

                when BUS_SIZ_PAUSE_3 =>
                    reg_strobe_en     <= '1';
                    reg_ds_en         <= '0'; 
                    reg_sizing_offset <= "10"; 
                    current_bus_state <= BUS_SIZ_CYCLE_3;

                when BUS_SIZ_CYCLE_3 =>
                    reg_strobe_en <= '1';
                    reg_ds_en     <= '1'; 
                    
                    if ext_DSACK1_N = '0' or ext_DSACK0_N = '0' or ext_STERM_N = '0' then
                        current_bus_state <= BUS_SIZ_PAUSE_4; 
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

                when BUS_SIZ_PAUSE_4 =>
                    reg_strobe_en     <= '1';
                    reg_ds_en         <= '0'; 
                    reg_sizing_offset <= "11"; 
                    current_bus_state <= BUS_SIZ_CYCLE_4;

                when BUS_SIZ_CYCLE_4 =>
                    reg_strobe_en <= '1';
                    reg_ds_en     <= '1'; 
                    
                    if ext_DSACK1_N = '0' or ext_DSACK0_N = '0' or ext_STERM_N = '0' then
                        current_bus_state <= BUS_S5_DONE; 
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

                -- =========================================================
                -- REGULÄRE BURST-EXPRESS-PHASEN (L1-CACHE BURST FILL)
                -- =========================================================
                when BUS_BURST_1 =>
                    reg_strobe_en <= '1'; reg_ds_en <= '1';
                    if ext_STERM_N = '0' then
                        reg_burst_cnt     <= "10";
                        current_bus_state <= BUS_BURST_2;
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

                when BUS_BURST_2 =>
                    reg_strobe_en <= '1'; reg_ds_en <= '1';
                    if ext_STERM_N = '0' then
                        reg_burst_cnt     <= "11";
                        current_bus_state <= BUS_BURST_3;
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

                when BUS_BURST_3 =>
                    reg_strobe_en <= '1'; reg_ds_en <= '1';
                    if ext_STERM_N = '0' then
                        reg_cbreq_n       <= '1';
                        current_bus_state <= BUS_S5_DONE;
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

						                  -- =========================================================
                -- PHASE S5: ERFOLGREICHER TRANSFER-ABSCHLUSS & RMW-SCHLEIFE
                -- =========================================================
                when BUS_S5_DONE =>
                    reg_strobe_en  <= '0';
                    reg_ds_en      <= '0';
                    reg_cbreq_n    <= '1';
                    fsm_cycle_done <= '1'; 
                    
                    -- KORREKTUR RMW-VERRIEGELUNG: 
                    -- Wenn es der Lese-Teil einer unteilbaren Operation war (cycle_write = '0' 
                    -- und cycle_rmw = '1'), halten wir reg_rmc_n starr auf '0' und springen 
                    -- SOFORT nach BUS_S0, um den Schreib-Teil anzuhängen, ohne die Strobes abzuwerfen!
                    if cycle_rmw = '1' and cycle_write = '0' then
                        reg_strobe_en     <= '1'; -- AS_N bleibt nahtlos aktiv!
                        current_bus_state <= BUS_S0;
                    else
                        current_bus_state <= BUS_TURN_AROUND;
                    end if;

                -- =========================================================
                -- BUS_TURN_AROUND: DATA BUS VACUUM (TREIBERKONFLIKT-SCHUTZ)
                -- =========================================================
                when BUS_TURN_AROUND =>
                    reg_strobe_en  <= '0';
                    reg_ds_en      <= '0';
                    reg_tristate   <= '1'; -- Zwingt alle Pins in Hochohmigkeit ('Z')
                    fsm_cycle_done <= '0';
                    reg_rmc_n      <= '1'; -- RMC-Sperre nach vollem Zyklus freigeben
                    
                    if ext_BR_N = '0' then
                        reg_bg_n <= '0';
                        if ext_BGACK_N = '0' then
                            current_bus_state <= BUS_ARBITRATED;
                        else
                            current_bus_state <= BUS_IDLE;
                        end if;
                    else
                        current_bus_state <= BUS_IDLE;
                    end if;

                -- =========================================================
                -- ARBITRIERUNGSZUSTAND (DMA-FREIGABE AN ERWEITERUNGEN)
                -- =========================================================
                when BUS_ARBITRATED =>
                    fsm_busy     <= '1';
                    reg_tristate <= '1';
                    if ext_BGACK_N = '1' and ext_BR_N = '1' then
                        reg_bg_n          <= '1';
                        reg_tristate      <= '0';
                        fsm_busy          <= '0';
                        current_bus_state <= BUS_IDLE;
                    else
                        reg_bg_n <= ext_BR_N;
                    end if;

                when others =>
                    current_bus_state <= BUS_IDLE;
            end case;
        end if;
    end process;

end behavioral;
