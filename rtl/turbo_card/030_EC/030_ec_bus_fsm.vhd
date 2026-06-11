-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_bus_fsm.vhd
-- Teil:    1 von 4 (Entity-Schnittstelle der BIU-Ablaufsteuerung)
-- Funktion: Die zentrale, taktgesteuerte Bus-Zustandsmaschine (BIU FSM).
--           PUNKT 4: Maximale elektrische Absicherung gegen Bus Contention!
--                    Erzwingt nach jedem Transfer eine BUS_TURN_AROUND-Phase
--                    zur hochohmigen Bus-Entlastung im FPGA-Silizium.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_bus_fsm is
    Port (
        -- Globale Systemsignale
        CLK             : in    std_logic;
        RESET_N         : in    std_logic;

        -- Steuerschnittstelle vom Haupt-Decoder / Rechenkern
        cycle_start     : in    std_logic;                      -- Impuls: Externen Buszyklus starten
        cycle_write     : in    std_logic;                      -- '1' = Write, '0' = Read
        cycle_rmw       : in    std_logic;                      -- '1' = Ununterbrochener Read-Modify-Write (TAS)
        
        -- Physikalische Quittungseingänge von der Turbokarte / Chipsatz
        ext_DSACK0_N    : in    std_logic;                      
        ext_DSACK1_N    : in    std_logic;                      
        ext_STERM_N     : in    std_logic;                      
        ext_BERR_N      : in    std_logic;                      
        
        -- Arbitrierungspins der CPU-Außenhaut (Turbokarten-DMA-Logik)
        ext_BR_N        : in    std_logic;                      
        ext_BG_N        : out   std_logic;                      
        ext_BGACK_N     : in    std_logic;                      

        -- Physische L1-Cache-Burstpins
        ext_CBREQ_N     : out   std_logic;                      
        ext_CBACK_N     : in    std_logic;                      
        
        -- Physischer Read-Modify-Write Sperrpin zur CPU-Außenhaut
        ext_RMC_N       : out   std_logic;                      -- '0' blockiert Fremd-DMA auf der Platine!

        -- Ausgänge an den Bus-Muxer und das Top-Gehäuse
        fsm_busy        : out   std_logic;                      -- '1' = Bus belegt
        fsm_cycle_done  : out   std_logic;                      -- '1' = Gesamter Transfer beendet
        fsm_strobe_en   : out   std_logic;                      -- Schaltet AS_N frei
        fsm_ds_en       : out   std_logic;                      -- Schaltet das Daten-Strobe DS_N frei
        fsm_write_en    : out   std_logic;                      -- Steuert die Richtung des RW-Pins
        fsm_tristate_en : out   std_logic;                      -- Zwingt Bus-Pins auf Hochohmig
        fsm_burst_cnt   : out   std_logic_vector(1 downto 0);   -- Burst-Zählerstand
        
        -- Dynamischer Adress-Offset-Vorschub an den Bus-Muxer bei schmalem Bus
        fsm_sizing_offset : out  std_logic_vector(1 downto 0)    
    );
end cpu_030_ec_bus_fsm;

architecture behavioral of cpu_030_ec_bus_fsm is

    -- =====================================================================
    -- REPARIERTES TIMING-NETZWERK: JETZT MIT MAXIMALER TURN-AROUND-SPERRE
    -- =====================================================================
    type bus_state_type is (
        BUS_IDLE,           -- Bus frei, wartet auf Start-Impuls oder DMA
        BUS_S0,             -- Phase 0: Adressleitungen, SIZ und FC stabilisieren
        BUS_S2,             -- Phase 2: Address Strobe (AS_N) und DS_N zünden
        BUS_S4_WAIT,        -- Phase 4: Haupt-Wartestation auf STERM / DSACK / BERR
        
        -- Express-Zustände für das Cache-Zeilen-Filling (Schritt 5)
        BUS_BURST_1,        
        BUS_BURST_2,        
        BUS_BURST_3,        
        
        -- Dedizierte Hold-Time-Pausen (Datenstrobe atmet kurz aus)
        BUS_SIZ_PAUSE_2,    
        BUS_SIZ_PAUSE_3,    
        BUS_SIZ_PAUSE_4,    
        
        -- Folge-Zyklen für die dynamische Busbreite (8/16-Bit Mainboard)
        BUS_SIZ_CYCLE_2,    
        BUS_SIZ_CYCLE_3,    
        BUS_SIZ_CYCLE_4,    
        
        BUS_S5_DONE,        -- Phase 5: Transfer beenden / Quittung an Core absetzen
        
        -- PUNKT 4: Maximale Absicherung gegen Bus-Kollisionen (Bus Contention)
        BUS_TURN_AROUND,    -- Eiserner Leerlauf-Takt: Zwingt Datenbus auf 'Z' (Vakuum)!
        
        BUS_ARBITRATED      -- DMA-Modus aktiv (CPU hochohmig verlassen)
    );

    signal current_bus_state : bus_state_type := BUS_IDLE;
    
    -- Interne Pufferregister zur Vermeidung von kombinatorischen Glitches
    signal reg_bg_n          : std_logic := '1';
    signal reg_tristate      : std_logic := '0';
    signal reg_cbreq_n       : std_logic := '1';
    signal reg_rmc_n         : std_logic := '1'; 
    signal reg_strobe_en     : std_logic := '0';
    signal reg_ds_en         : std_logic := '0'; 
    
    signal reg_burst_cnt     : std_logic_vector(1 downto 0) := "00";
    signal reg_sizing_offset : std_logic_vector(1 downto 0) := "00";

begin

    -- Physikalische Kontroll-Ausgänge permanent stabil treiben
    ext_BG_N          <= reg_bg_n;
    fsm_tristate_en   <= reg_tristate;
    ext_CBREQ_N       <= reg_cbreq_n;
    fsm_strobe_en     <= reg_strobe_en;
    fsm_ds_en         <= reg_ds_en; 
    fsm_burst_cnt     <= reg_burst_cnt;
    fsm_sizing_offset <= reg_sizing_offset;
    
    ext_RMC_N         <= reg_rmc_n;

    -- =====================================================================
    -- SYNCHRONER CONTROL-PROZESS: TAKTGESTEUERTE SIZING- UND RMC-FSM
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            current_bus_state <= BUS_IDLE;
            fsm_busy          <= '0';
            fsm_cycle_done    <= '0';
            reg_strobe_en     <= '0';
            reg_ds_en         <= '0';
            fsm_write_en      <= '0';
            reg_bg_n          <= '1';
            reg_tristate      <= '0';
            reg_cbreq_n       <= '1';
            reg_rmc_n         <= '1'; 
            reg_burst_cnt     <= "00";
            reg_sizing_offset <= "00";
            
        elsif rising_edge(CLK) then
            -- Standard-Impulse zurücksetzen
            fsm_cycle_done <= '0';
            
            case current_bus_state is
                
                -- =========================================================
                -- BUS LEERLAUF (IDLE): RESETS UND SPERR-PRÜFUNG
                -- =========================================================
                when BUS_IDLE =>
                    fsm_busy          <= '0';
                    reg_strobe_en     <= '0';
                    reg_ds_en         <= '0';
                    fsm_write_en      <= '0';
                    reg_tristate      <= '0';
                    reg_cbreq_n       <= '1'; 
                    reg_burst_cnt     <= "00"; 
                    reg_sizing_offset <= "00";

                    if cycle_rmw = '0' then
                        reg_rmc_n <= '1';
                    end if;

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
                            reg_rmc_n <= '0'; 
                        end if;
                        
                        current_bus_state <= BUS_S0;
                    else
                        reg_bg_n <= '1';
                    end if;

                when BUS_S0 =>
                    fsm_write_en <= cycle_write;
                    
                    if cycle_write = '0' then
                        reg_cbreq_n <= '0'; 
                    else
                        reg_cbreq_n <= '1'; 
                    end if;
                    
                    current_bus_state <= BUS_S2;

                when BUS_S2 =>
                    reg_strobe_en     <= '1';
                    reg_ds_en         <= '1'; 
                    current_bus_state <= BUS_S4_WAIT;

                -- =========================================================
                -- PHASE S4: DIE ERWEITERTE LOGISCHE SIZING-VERZWEIGUNG
                -- =========================================================
                when BUS_S4_WAIT =>
                    reg_strobe_en <= '1';
                    reg_ds_en     <= '1';
                    
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
                            current_bus_state <= BUS_S5_DONE;
                            
                        elsif ext_DSACK1_N = '0' and ext_DSACK0_N = '1' then
                            current_bus_state <= BUS_SIZ_PAUSE_2;
                            
                        elsif ext_DSACK1_N = '1' and ext_DSACK0_N = '0' then
                            current_bus_state <= BUS_SIZ_PAUSE_2;
                        end if;
                    end if;

                -- =========================================================
                -- RESTRICHTE SCHLEIFENPHASEN FÜR SIZING-FOLGEZYKLEN
                -- =========================================================
                when BUS_SIZ_PAUSE_2 =>
                    reg_strobe_en <= '1'; 
                    reg_ds_en     <= '0'; 
                    
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
                -- REGULÄRE BURST-EXPRESS-PHASEN
                -- =========================================================
                when BUS_BURST_1 =>
                    reg_strobe_en <= '1';
                    reg_ds_en     <= '1';
                    if ext_STERM_N = '0' then
                        reg_burst_cnt     <= "10";
                        current_bus_state <= BUS_BURST_2;
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

                when BUS_BURST_2 =>
                    reg_strobe_en <= '1';
                    reg_ds_en     <= '1';
                    if ext_STERM_N = '0' then
                        reg_burst_cnt     <= "11";
                        current_bus_state <= BUS_BURST_3;
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

                when BUS_BURST_3 =>
                    reg_strobe_en <= '1';
                    reg_ds_en     <= '1';
                    if ext_STERM_N = '0' then
                        reg_cbreq_n       <= '1';
                        current_bus_state <= BUS_S5_DONE;
                    elsif ext_BERR_N = '0' then
                        current_bus_state <= BUS_S5_DONE;
                    end if;

                -- =========================================================
                -- PHASE S5: ERFOLGREICHER TRANSFER-ABSCHLUSS & RMW-CHECK
                -- =========================================================
                when BUS_S5_DONE =>
                    reg_strobe_en  <= '0';
                    reg_ds_en      <= '0';
                    reg_cbreq_n    <= '1';
                    fsm_cycle_done <= '1'; 
                    
                    if cycle_rmw = '1' and cycle_write = '0' then
                        current_bus_state <= BUS_IDLE;
                    else
                        -- KORREKTUR PUNKT 4: Umleitung über den Turn-Around-Isolator!
                        current_bus_state <= BUS_TURN_AROUND;
                    end if;

                -- =========================================================
                -- PUNKT 4: ERZWUNGENER LEERLAUF-TAKTMUX (DATA BUS VACUUM)
                -- Trennt aufeinanderfolgende Buszyklen elektrisch sauber ab!
                -- =========================================================
                when BUS_TURN_AROUND =>
                    reg_strobe_en  <= '0';
                    reg_ds_en      <= '0';
                    reg_tristate   <= '1'; -- Erzwingt bedingungslos Hochohmig ('Z') an den Pins!
                    fsm_cycle_done <= '0';
                    
                    -- Nach exakt einem Takt Abkühlung wird der Bus wieder freigegeben
                    reg_rmc_n <= '1';
                    
                    if ext_BR_N = '0' then
                        reg_bg_n          <= '0';
                        if ext_BGACK_N = '0' then
                            current_bus_state <= BUS_ARBITRATED;
                        else
                            current_bus_state <= BUS_IDLE;
                        end if;
                    else
                        current_bus_state <= BUS_IDLE;
                    end if;

                -- =========================================================
                -- ARBITRIERUNGSZUSTAND (DMA-FREIGABE)
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
