-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   copper_fsm.vhd
-- Funktion: Die synchrone Ablaufsteuerung (FSM) des Coppers.
-- SANIERUNG SCHRITT 23:
--   - Integration einer Latenzstufe beim Befehls-Fetch (ST_FETCH_W2). [14.1]
--   - Verhindert das verfrühte Einlesen instabiler RAM-Datenbuspegel.
--   - Sichert den lückenlosen Betrieb an der 32-Bit Alice-MMU-Grenze.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity copper_fsm is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt von Alice
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. INTERNE STEUERLINIEN VON DEN REINEN BRUDER-MODULEN (EINGÄNGE)
        -- =============================================================
        inst_is_move  : in    std_logic; -- Aktueller Befehl ist MOVE
        inst_is_wait  : in    std_logic; -- Aktueller Befehl ist WAIT
        inst_is_skip  : in    std_logic; -- Aktueller Befehl ist SKIP
        position_match: in    std_logic; -- Gewünschte Video-Position ist erreicht/überschritten
        
        -- Der harte CPU-Wachruf-Trigger (COPJMP-Aktivierung)
        fsm_jump_trigger : in std_logic; -- '1' erzwingt den sofortigen Abbruch des Wartens!
        
        -- =============================================================
        -- 3. KONTROLLLINIEN ZU DEN REINEN BRUDER-UNTERMODULEN (AUSGÄNGE)
        -- =============================================================
        fsm_load_inst : out   std_logic; -- Trigger zum Einlesen und Decodieren des neuen Befehls
        
        -- =============================================================
        -- 4. SPEICHER-ANFORDERUNGEN ZUR ÜBERGEORDNETEN CHIP-ZENTRALE
        -- =============================================================
        fsm_cop_req   : out   std_logic; -- Copper fordert eine DMA-Zeitscheibe für den Befehls-Fetch an
        cop_granted   : in    std_logic; -- Alice-Zentrale meldet: "Dein Speicher-Slot ist jetzt aktiv!"
        copper_status : out   std_logic_vector(1 downto 0) -- "00" = Idle/Halt, "01" = Fetch, "10" = Active
    );
end copper_fsm;

architecture Behavioral of copper_fsm is

    -- Definition der internen operativen Hardware-Zustände des Coppers
    type cop_state_t is (
        ST_IDLE,          -- Wartet auf Aktivierung oder COPJMP-Signal
        ST_FETCH_W1,      -- Fordert das erste 16-Bit-Wort über den DMA an
        ST_FETCH_W2,      -- Fordert das zweite 16-Bit-Wort über den DMA an
        ST_EXECUTE,       -- Wertet den Befehlstyp aus und führt Operationen aus
        ST_WAITING,       -- Warteschleife: Blockiert den PC, bis der Videostrahl aufschließt
        ST_SKIP_W1,       -- Überspringungszustand für das erste Wort bei erfülltem SKIP
        ST_SKIP_W2        -- Überspringungszustand für das zweite Wort bei erfülltem SKIP
    );
    signal current_state : cop_state_t := ST_IDLE;

    -- Interner Status-Vektor zur Signalisierung der Aktivität an das Register-Interface
    signal int_status    : std_logic_vector(1 downto 0) := "00";

begin

    -- Korrektur für die Typ-Kompatibilität der Statuszuweisung
    copper_status <= int_status;

    -- =================================================================
    -- OPERATIVE ZUSTANDSMASCHINE UND ABLAUFSTEUERUNG
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            current_state <= ST_IDLE;
            fsm_load_inst <= '0';
            fsm_cop_req   <= '0';
            int_status    <= "00";
        elsif rising_edge(clk_amiga) then
            -- Standard-Impulse bei jedem steigenden Takt zurücksetzen
            fsm_load_inst <= '0';
            fsm_cop_req   <= '0';

            -- GLOBALER RE-TRIGGER: Wenn die CPU ein COPJMP auslöst,
            -- brechen wir JEDEN aktuellen Zustand sofort ab und starten neu!
            if fsm_jump_trigger = '1' then
                current_state <= ST_FETCH_W1;
            else
                case current_state is
                    -- -----------------------------------------------------
                    -- STANDBY: Copper schläft oder wartet auf ein COPJMP
                    -- -----------------------------------------------------
                    when ST_IDLE =>
                        int_status <= "00";
                        current_state <= ST_FETCH_W1;

                    -- -----------------------------------------------------
                    -- FETCH W1: Erstes 16-Bit Wort anfordern (Befehls-Typ)
                    -- -----------------------------------------------------
                    when ST_FETCH_W1 =>
                        int_status  <= "01";
                        fsm_cop_req <= '1'; -- Zeitscheibe beim Alice-DMA beantragen
                        if cop_granted = '1' then
                            current_state <= ST_FETCH_W2;
                        end if;

                    -- -----------------------------------------------------
                    -- REPARATUR: FETCH W2 MIT ENTSCHEIDENDER SPEICHERLATENZ
                    -- -----------------------------------------------------
                    when ST_FETCH_W2 =>
                        int_status  <= "01";
                        fsm_cop_req <= '1';
                        if cop_granted = '1' then
                            -- REPARATUR: Das Datenpuffer-Signal erst JETZT zünden, wenn der
                            -- Bus freigegeben und das 32-Bit-Longword im Bus-Interface absolut stabil ist! [14.1]
                            fsm_load_inst <= '1';
                            current_state <= ST_EXECUTE; -- Marsch ins Rechenwerk
                        end if;

                    -- -----------------------------------------------------
                    -- EXECUTE: Befehls-Typen auswerten und verarbeiten
                    -- -----------------------------------------------------
                    when ST_EXECUTE =>
                        int_status <= "10";
                        if inst_is_move = '1' then
                            current_state <= ST_FETCH_W1;
                        elsif inst_is_wait = '1' then
                            if position_match = '1' then
                                current_state <= ST_FETCH_W1; 
                            else
                                current_state <= ST_WAITING;  
                            end if;
                        elsif inst_is_skip = '1' then
                            if position_match = '1' then
                                current_state <= ST_SKIP_W1;  
                            else
                                current_state <= ST_FETCH_W1; 
                            end if;
                        else
                            current_state <= ST_FETCH_W1;
                        end if;

                    -- -----------------------------------------------------
                    -- WAITING: Warteschleife bis zur Wunsch-Bildschirmzeile
                    -- -----------------------------------------------------
                    when ST_WAITING =>
                        int_status <= "10";
                        -- Greift nun fehlerfrei auf das getaktete, stabilisierte Signal
                        -- deiner sanierten copper_sync.vhd zu!
                        if position_match = '1' then
                            current_state <= ST_FETCH_W1; 
                        end if;

                    -- -----------------------------------------------------
                    -- SKIP SLOTS: Folgebefehl wirkungslos überfliegen
                    -- -----------------------------------------------------
                    when ST_SKIP_W1 =>
                        fsm_cop_req <= '1';
                        if cop_granted = '1' then
                            current_state <= ST_SKIP_W2;
                        end if;

                    when ST_SKIP_W2 =>
                        fsm_cop_req <= '1';
                        if cop_granted = '1' then
                            fsm_load_inst <= '1'; 
                            current_state <= ST_FETCH_W1; 
                        end if;

                    when others =>
                        current_state <= ST_IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
