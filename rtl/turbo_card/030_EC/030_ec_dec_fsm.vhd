-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_fsm.vhd
-- Teil:    1 von 4 (Entity-Schnittstelle der Master-Steuerung)
-- Funktion: Die zentrale, synchrone Ablaufsteuerung (Master-FSM) des 68EC030.
--           Verwaltet den Reset-Boot, Interrupts und System-Exceptions.
--           SCHRITT 3: Ausbau der Fehler-Exceptions (Illegal, Line-A/F, TRAPs)!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_fsm is
    Port (
        -- Globale Systemschnittstellen
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Schnittstelle zur Befehls-Pipeline (Prefetch/Opcode-Erkennung)
        pipeline_word       : in    std_logic_vector(15 downto 0);  -- Aktueller Befehl
        pipeline_empty      : in    std_logic;                      -- Pipeline-Leerstand (Stall)
        
        -- Schnittstelle zur Bus Interface Unit (BIU via TK)
        bus_cycle_done      : in    std_logic;                      -- BIU meldet: Transfer beendet
        internal_D_in       : in    std_logic_vector(31 downto 0);  -- Eingehende 32-Bit Daten vom Außenbus
        
        -- Schnittstelle zum Rechenwerk (ALU / Registerbank)
        alu_ready           : in    std_logic;                      -- ALU meldet: Befehl fertig ausgeführt
        alu_flags           : in    std_logic_vector(4 downto 0);   -- Aktuelle CCR-Flags aus der Registerbank
        
        -- Fehlersignale und Trigger aus den Modulen
        exception_div_zero  : in    std_logic;                      -- '1' = Division durch Null erkannt!
        
        -- ERWEITERUNG SCHRITT 3: Neue Ausnahme-Triggerleitungen vom Vordecoder
        dec_exc_illegal     : in    std_logic;                      -- '1' = Unzulässiger Opcode (Vektor #4)
        dec_exc_line_a      : in    std_logic;                      -- '1' = Line-A Opcode-Muster (Vektor #10)
        dec_exc_line_f      : in    std_logic;                      -- '1' = Line-F Opcode-Muster (Vektor #11)
        
        -- Schnittstelle zur Interrupt-Filterung
        irq_asserted        : in    std_logic;                      -- '1' = Gültiger Paula-Interrupt steht an
        irq_level           : in    std_logic_vector(2 downto 0);   -- Der ermittelte Interrupt-Level

        -- Kombinatorische Ausgänge an das Bus-Weichenwerk (dec_mux)
        fsm_bus_req         : out   std_logic;                      -- Buszyklus-Anforderung von der FSM
        fsm_bus_write       : out   std_logic;                      -- '1' = Schreiben (Push), '0' = Lesen (Pop/Vektor)
        fsm_bus_addr        : out   std_logic_vector(31 downto 0);  -- Generierte Adresse für Sonderzyklen
        fsm_bus_data_out    : out   std_logic_vector(31 downto 0);  -- Auszugebende Daten für Stack-Schreibzyklen
        fsm_bus_type        : out   std_logic_vector(2 downto 0);   -- FC-Funktionscodes für CPU-Space / Supervisor
        
        -- Rückmeldetrigger direkt an die Hauptregisterbank (Vorschub und Laden)
        fsm_pc_load         : out   std_logic;                      -- Trigger: PC mit neuem Wert laden
        fsm_pc_new          : out   std_logic_vector(31 downto 0);  -- Der neue PC-Wert für die Registerbank
        fsm_ssp_load        : out   std_logic;                      -- Trigger: Supervisor Stack Pointer (A7) laden
        fsm_ssp_new         : out   std_logic_vector(31 downto 0);  -- Der neue A7-Wert (nach Push/Pop Modifikation)
        
        -- Interne Zustandssignale an die Decoder-Klassen
        fsm_running_mode    : out   std_logic;                      -- '1' = CPU arbeitet im regulären Fließband
        fsm_supervisor_mode : out   std_logic                       -- '1' = CPU befindet sich im Supervisor-Modus
    );
end cpu_030_ec_dec_fsm;

architecture behavioral of cpu_030_ec_dec_fsm is

    -- =====================================================================
    -- ERWEITERTES MOTOROLA-ZUSTANDSNETZWERK (MASTER-STEUERUNG)
    -- =====================================================================
    type state_type is (
        -- Reset- und Boot-Sequenz (Einlesen aus BRAM/Mainboard via TK)
        BOOT_INIT,           -- System-Reset verlassen
        BOOT_FETCH_SSP,      -- SSP-Vektor einlesen (Adresse 0x00F80000)
        BOOT_FETCH_PC,       -- PC-Vektor einlesen (Adresse 0x00F80004)
        BOOT_APPLY,          -- Vektoren in Registerbank einrasten
        
        -- Regulärer Fließbandbetrieb
        RUNNING,             -- Normale Befehlsdekodierung und Ausführung
        
        -- EXCEPTION-STACK-PUSH (Sichern auf den Supervisor-Stack)
        EXC_PUSH_PC,         -- Programmzähler dekrementieren und auf Stack schreiben
        EXC_PUSH_SR,         -- Statusregister dekrementieren und auf Stack schreiben
        EXC_FETCH_VECTOR,    -- Sprungadresse des OS-Handlers aus RAM/BRAM laden
        EXC_APPLY,           -- Fehlerroutine anspringen und SR anpassen
        
        -- PRIVILEGIERTE RTE-RÜCKKEHR (Pop vom Supervisor-Stack)
        RTE_POP_SR,          -- Altes Statusregister vom Stack lesen
        RTE_POP_PC,          -- Alten Programmzähler vom Stack lesen
        RTE_APPLY            -- Zustand wiederherstellen, zurück zum Anwenderprogramm
    );

    -- Interne Register zur taktgenauen Zustandsspeicherung
    signal current_state      : state_type := BOOT_INIT;
    signal internal_pc        : unsigned(31 downto 0) := x"00F80000";
    signal internal_ssp       : unsigned(31 downto 0) := x"00000000";
    
    -- Lokale Datenpuffer zum Sichern der Zwischenstände
    signal reg_ssp_buffer     : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_pc_buffer      : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_sr_buffer      : std_logic_vector(15 downto 0) := x"2700";
    
    -- Cache für den aktuellen Ausnahme-Vektor (Adresse im RAM)
    signal reg_vector_addr    : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Gespeichertes Interrupt-Filter-Register
    signal reg_sr_mask        : std_logic_vector(2 downto 0) := "000";
    signal supervisor_active  : std_logic := '1'; -- '1' = Supervisor, '0' = User Mode

begin

    -- Permanente Hardware-Rückmeldung an die übergeordneten Decoder-Klassen
    fsm_supervisor_mode <= supervisor_active;

    -- =====================================================================
    -- KOMBINAOTORISCHES STEUER-MULTIPLEXING DER MASTER-Ablaufsteuerung
    -- Schaltet die Bus- und Registersteuerleitungen je nach Zustand stabil.
    -- =====================================================================
    process(current_state, internal_pc, internal_ssp, reg_vector_addr, 
            reg_sr_buffer, reg_ssp_buffer, reg_pc_buffer)
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        fsm_bus_req      <= '0';
        fsm_bus_write    <= '0';
        fsm_bus_addr     <= (others => '0');
        fsm_bus_data_out <= (others => '0');
        fsm_bus_type     <= "101"; -- Standard: Supervisor Data Space
        
        fsm_pc_load      <= '0';
        fsm_pc_new       <= (others => '0');
        fsm_ssp_load     <= '0';
        fsm_ssp_new      <= (others => '0');
        fsm_running_mode <= '0';

        case current_state is
            
            when BOOT_INIT =>
                fsm_bus_addr <= x"00F80000";
                fsm_bus_req  <= '1';

            when BOOT_FETCH_SSP =>
                fsm_bus_addr <= x"00F80000";
                fsm_bus_req  <= '1';

            when BOOT_FETCH_PC =>
                fsm_bus_addr <= x"00F80004";
                fsm_bus_req  <= '1';

            when BOOT_APPLY =>
                fsm_ssp_new  <= reg_ssp_buffer;
                fsm_pc_new   <= reg_pc_buffer;
                fsm_ssp_load <= '1';
                fsm_pc_load  <= '1';

            when RUNNING =>
                fsm_running_mode <= '1';

            -- EXCEPTION STACK PUSH (PC und SR sichern)
            when EXC_PUSH_PC =>
                fsm_bus_req      <= '1';
                fsm_bus_write    <= '1'; -- Echtes Schreiben auf den Stack (Push)
                fsm_bus_addr     <= std_logic_vector(internal_ssp - 4); -- PC belegt 4 Bytes
                fsm_bus_data_out <= std_logic_vector(internal_pc);      -- Aktuellen PC herausschreiben
                fsm_bus_type     <= "101";

            when EXC_PUSH_SR =>
                fsm_bus_req      <= '1';
                fsm_bus_write    <= '1'; -- Echtes Schreiben auf den Stack (Push)
                fsm_bus_addr     <= std_logic_vector(internal_ssp - 6); -- Zusätzliche 2 Bytes für SR
                fsm_bus_data_out <= reg_sr_buffer & x"0000";            -- SR-Word in den oberen Datenraum packen
                fsm_bus_type     <= "101";

            when EXC_FETCH_VECTOR =>
                fsm_bus_req  <= '1';
                fsm_bus_write <= '0'; -- Passives Auslesen des Handlers aus dem RAM (Read)
                fsm_bus_addr  <= reg_vector_addr;
                fsm_bus_type  <= "111"; -- CPU Space Cycle für Exception-Vektoren

            when EXC_APPLY =>
                fsm_pc_new   <= reg_pc_buffer;
                fsm_pc_load  <= '1';
                fsm_ssp_new  <= std_logic_vector(internal_ssp - 6); -- Stack Pointer permanent absenken
                fsm_ssp_load <= '1';

            -- EXCEPTION STACK POP VIA RTE
            when RTE_POP_SR =>
                fsm_bus_req  <= '1';
                fsm_bus_write <= '0'; -- Einlesen vom Stack (Pop/Read)
                fsm_bus_addr  <= std_logic_vector(internal_ssp);
                fsm_bus_type  <= "101";

            when RTE_POP_PC =>
                fsm_bus_req  <= '1';
                fsm_bus_write <= '0'; -- Einlesen vom Stack (Pop/Read)
                fsm_bus_addr  <= std_logic_vector(internal_ssp + 2); -- PC liegt hinter dem SR
                fsm_bus_type  <= "101";

            when RTE_APPLY =>
                fsm_pc_new   <= reg_pc_buffer;
                fsm_pc_load  <= '1';
                fsm_ssp_new  <= std_logic_vector(internal_ssp + 6); -- Stack Pointer wieder freigeben
                fsm_ssp_load <= '1';

            when others => null;
        end case;
    end process;

    -- =====================================================================
    -- SYNCHRONER CONTROL-PROZESS: ZYKLUSTREUE MOTOROLA-EXCEPTION-FSM
    -- KORREKTUR: Symmetrischer Ausbau aller Fehler- und System-Exceptions!
    -- =====================================================================
    process(CLK, RESET_N)
        variable irq_offset : unsigned(31 downto 0);
    begin
        if RESET_N = '0' then
            current_state    <= BOOT_INIT;
            internal_pc      <= x"00F80000";
            internal_ssp     <= (others => '0');
            reg_ssp_buffer   <= (others => '0');
            reg_pc_buffer    <= (others => '0');
            reg_sr_buffer    <= x"2700";
            reg_vector_addr  <= (others => '0');
            reg_sr_mask      <= "000";
            supervisor_active <= '1'; -- Bootet starr im Supervisor-Modus

        elsif rising_edge(CLK) then
            case current_state is

                -- =========================================================
                -- RECHTMÄSSIGER RE-BOOT-ABLAUF BEIM EINSCHALTEN
                -- =========================================================
                when BOOT_INIT =>
                    current_state <= BOOT_FETCH_SSP;

                when BOOT_FETCH_SSP =>
                    if bus_cycle_done = '1' then
                        reg_ssp_buffer <= internal_D_in;
                        current_state  <= BOOT_FETCH_PC;
                    end if;

                when BOOT_FETCH_PC =>
                    if bus_cycle_done = '1' then
                        reg_pc_buffer <= internal_D_in;
                        current_state <= BOOT_APPLY;
                    end if;

                when BOOT_APPLY =>
                    internal_ssp  <= unsigned(reg_ssp_buffer);
                    internal_pc   <= unsigned(reg_pc_buffer);
                    current_state <= RUNNING;

                -- =========================================================
                -- REGULÄRES FLIESSBAND MIT INTEGRIERTER EXCEPTION-WEICHE
                -- =========================================================
                when RUNNING =>
                    if alu_ready = '1' then
                        
                        -- A: PRIVILEGIERTER RÜCKKEHR-BEFEHL (RTE) ERKANNT?
                        if pipeline_empty = '0' and pipeline_word = x"4E73" then
                            current_state <= RTE_POP_SR;

                        -- B: PRIO 1 - ILLEGAL INSTRUCTION EXCEPTION (Vektor #4)
                        elsif pipeline_empty = '0' and dec_exc_illegal = '1' then
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            reg_vector_addr <= x"00000010"; -- Vektor #4 RAM-Adresse (4 * 4)
                            current_state   <= EXC_PUSH_PC;

                        -- C: PRIO 2 - DIVISION DURCH NULL EXCEPTION (Vektor #5)
                        elsif exception_div_zero = '1' then
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            reg_vector_addr <= x"00000014"; -- Vektor #5 RAM-Adresse (5 * 4)
                            current_state   <= EXC_PUSH_PC;

                        -- D: PRIO 3 - LINE-A EMULATOR EXCEPTION (Vektor #10)
                        elsif pipeline_empty = '0' and dec_exc_line_a = '1' then
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            reg_vector_addr <= x"00000028"; -- Vektor #10 RAM-Adresse (10 * 4)
                            current_state   <= EXC_PUSH_PC;

                        -- E: PRIO 4 - LINE-F EMULATOR EXCEPTION (Vektor #11)
                        elsif pipeline_empty = '0' and dec_exc_line_f = '1' then
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            reg_vector_addr <= x"0000002C"; -- Vektor #11 RAM-Adresse (11 * 4)
                            current_state   <= EXC_PUSH_PC;

                        -- F: PRIO 5 - SOFTWARE INTERRUPT: TRAP #x BEFEHLE (Vektoren #32 bis #47)
                        -- Opcode-Bereich von 0x4E40 bis 0x4E4F
                        elsif pipeline_empty = '0' and pipeline_word(15 downto 4) = x"4E4" then
                            reg_pc_buffer   <= std_logic_vector(internal_pc + 2); -- Nachfolgenden Befehl als Rückkehr-PC merken
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            -- Originale Motorola-Offset-Berechnung: Adresse = 0x00000080 + (TRAP_Nummer * 4)
                            irq_offset      := x"00000080" + resize(unsigned(pipeline_word(3 downto 0)) * 4, 32);
                            reg_vector_addr <= std_logic_vector(irq_offset);
                            current_state   <= EXC_PUSH_PC;

                        -- G: PRIO 6 - ASYNCHRONER HARDWARE-INTERRUPT VON PAULA
                        elsif irq_asserted = '1' then
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000";
                            irq_offset      := x"00000060" + resize(unsigned(irq_level) * 4, 32);
                            reg_vector_addr <= std_logic_vector(irq_offset);
                            current_state   <= EXC_PUSH_PC;

                        -- H: REINER LINEARER BEFEHLSVORSCHUB
                        else
                            internal_pc <= internal_pc + 2;
                        end if;
                    end if;

                -- =========================================================
                -- HARDWARE STACK PUSH SEQUENZ (SCHREIBEN)
                -- =========================================================
                when EXC_PUSH_PC =>
                    if bus_cycle_done = '1' then
                        current_state <= EXC_PUSH_SR;
                    end if;

                when EXC_PUSH_SR =>
                    if bus_cycle_done = '1' then
                        current_state <= EXC_FETCH_VECTOR;
                    end if;

                when EXC_FETCH_VECTOR =>
                    if bus_cycle_done = '1' then
                        reg_pc_buffer <= internal_D_in; 
                        current_state <= EXC_APPLY;
                    end if;

                when EXC_APPLY =>
                    internal_pc       <= unsigned(reg_pc_buffer);
                    internal_ssp      <= internal_ssp - 6; 
                    supervisor_active <= '1'; 
                    current_state     <= RUNNING;

                -- =========================================================
                -- HARDWARE STACK POP SEQUENZ VIA RTE (LESEN)
                -- =========================================================
                when RTE_POP_SR =>
                    if bus_cycle_done = '1' then
                        reg_sr_buffer(15 downto 0) <= internal_D_in(31 downto 16); 
                        current_state              <= RTE_POP_PC;
                    end if;

                when RTE_POP_PC =>
                    if bus_cycle_done = '1' then
                        reg_pc_buffer <= internal_D_in; 
                        current_state <= RTE_APPLY;
                    end if;

                when RTE_APPLY =>
                    internal_pc    <= unsigned(reg_pc_buffer);
                    internal_ssp   <= internal_ssp + 6; 
                    reg_sr_mask    <= reg_sr_buffer(10 downto 8); 
                    current_state  <= RUNNING;

                when others =>
                    current_state <= RUNNING;
            end case;
        end if;
    end process;

end behavioral;
