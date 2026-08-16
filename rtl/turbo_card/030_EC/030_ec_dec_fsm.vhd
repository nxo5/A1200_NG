-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_fsm.vhd
-- Teil:    1 von 4 (Schnittstellendefinition der Master-Steuerung)
-- Funktion: Die zentrale, synchrone Ablaufsteuerung (Master-FSM) des 68EC030.
--           Nativer Vektor-Fetch für Boot, Interrupts und Exceptions.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_fsm is
    Port (
        -- Globale Systemsynchronisation
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Schnittstelle zur Befehls-Pipeline (Prefetch-Puffer)
        pipeline_word       : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode
        pipeline_empty      : in    std_logic;                      -- Pipeline leer (Stall)
        
        -- Schnittstelle zur Bus Interface Unit (BIU)
        bus_cycle_done      : in    std_logic;                      -- BIU meldet: Transfer beendet
        internal_D_in       : in    std_logic_vector(31 downto 0);  -- Gelesene 32-Bit Daten vom Bus
        
        -- Schnittstelle zur Execution Unit (ALU / Registerbank)
        alu_ready           : in    std_logic;                      -- ALU meldet: Befehl beendet
        alu_flags           : in    std_logic_vector(4 downto 0);   -- CCR-Flags aus der Hauptregisterbank
        
        -- Fehlersignale und Trigger aus den Modulen
        exception_div_zero  : in    std_logic;                      -- '1' = Division durch Null erkannt
        
        -- Ausnahme-Triggerleitungen vom Pipeline-Vordecoder
        dec_exc_illegal     : in    std_logic;                      -- '1' = Unzulässiger Opcode (Vektor #4)
        dec_exc_line_a      : in    std_logic;                      -- '1' = Line-A Opcode (Vektor #10)
        dec_exc_line_f      : in    std_logic;                      -- '1' = Line-F Opcode (Vektor #11)
        
        -- Schnittstelle zur Interrupt-Filterung (Paula-Anbindung)
        irq_asserted        : in    std_logic;                      -- '1' = Gültiger Interrupt steht an
        irq_level           : in    std_logic_vector(2 downto 0);   -- Der ermittelte Interrupt-Level

        -- Kombinatorische Ausgänge an das Bus-Weichenwerk (dec_mux)
        fsm_bus_req         : out   std_logic;                      -- Bus-Anforderung der FSM
        fsm_bus_write       : out   std_logic;                      -- '1' = Stack-Push, '0' = Read (Pop/Vektor)
        fsm_bus_addr        : out   std_logic_vector(31 downto 0);  -- Generierte Adresse für Sonderzyklen
        fsm_bus_data_out    : out   std_logic_vector(31 downto 0);  -- Daten für Stack-Schreibzyklen
        fsm_bus_type        : out   std_logic_vector(2 downto 0);   -- Funktionscodes (FC)
        
        -- Rückmeldetrigger an die Hauptregisterbank
        fsm_pc_load         : out   std_logic;                      -- Trigger: Programmzähler neu laden
        fsm_pc_new          : out   std_logic_vector(31 downto 0);  -- Der neue PC-Wert
        fsm_ssp_load        : out   std_logic;                      -- Trigger: Supervisor Stack Pointer laden
        fsm_ssp_new         : out   std_logic_vector(31 downto 0);  -- Der neue A7-Wert
        
        -- Interne Zustandssignale an das Core-Fließband
        fsm_running_mode    : out   std_logic;                      -- '1' = Normaler Befehlsablauf aktiv
        fsm_supervisor_mode : out   std_logic                       -- '1' = CPU im Supervisor-Zustand
    );
end cpu_030_ec_dec_fsm;

architecture behavioral of cpu_030_ec_dec_fsm is

    -- =====================================================================
    -- ERWEITERTES MOTOROLA-ZUSTANDSNETZWERK (MASTER-STEUERUNG)
    -- =====================================================================
    type state_type is (
        RESET_STATE,         -- System-Reset verlassen
        BOOT_FETCH_SSP,      -- SSP-Vektor einlesen (Adresse 0x00000000)
        BOOT_FETCH_PC,       -- PC-Vektor einlesen (Adresse 0x00000004)
        BOOT_APPLY,          -- Vektoren in Registerbank einrasten
        
        RUNNING,             -- Normale Befehlsdekodierung und Ausführung
        
        EXC_PUSH_PC,         -- Programmzähler dekrementieren und auf Stack schreiben
        EXC_PUSH_SR,         -- Statusregister dekrementieren und auf Stack schreiben
        EXC_FETCH_VECTOR,    -- Sprungadresse des OS-Handlers aus RAM/BRAM laden
        EXC_APPLY,           -- Fehlerroutine anspringen und SR anpassen
        
        RTE_POP_SR,          -- Altes Statusregister vom Stack lesen
        RTE_POP_PC,          -- Alten Programmzähler vom Stack lesen
        RTE_APPLY            -- Zustand wiederherstellen, zurück zum Anwenderprogramm
    );

    -- Interne Register zur taktgenauen Zustandsspeicherung
    signal current_state      : state_type := RESET_STATE;
    signal internal_pc        : unsigned(31 downto 0) := (others => '0');
    signal internal_ssp       : unsigned(31 downto 0) := (others => '0');
    
    -- Lokale Datenpuffer zum Sichern der Zwischenstände
    signal reg_ssp_buffer     : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_pc_buffer      : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_sr_buffer      : std_logic_vector(15 downto 0) := x"2700";
    
    -- Cache für den aktuellen Ausnahme-Vektor
    signal reg_vector_addr    : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Gespeichertes Interrupt-Filter-Register
    signal reg_sr_mask        : std_logic_vector(2 downto 0) := "111";
    signal supervisor_active  : std_logic := '1'; -- Bootet im Supervisor-Modus

begin

    -- Permanente Hardware-Rückmeldung an die übergeordneten Decoder-Klassen
    fsm_supervisor_mode <= supervisor_active;

    -- =====================================================================
    -- KOMBINAOTORISCHES STEUER-MULTIPLEXING DER MASTER-ABLIEFSTEUERUNG
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
            
            when RESET_STATE =>
                fsm_bus_addr <= x"00000000"; -- UNBESTECHLICH: Physischer Hardware-Start Vektor 0!
                fsm_bus_req  <= '1';

            when BOOT_FETCH_SSP =>
                fsm_bus_addr <= x"00000000"; -- SSP-Adresse laut Motorola-Handbuch
                fsm_bus_req  <= '1';

            when BOOT_FETCH_PC =>
                fsm_bus_addr <= x"00000004"; -- PC-Adresse laut Motorola-Handbuch
                fsm_bus_req  <= '1';

            when BOOT_APPLY =>
                fsm_ssp_new  <= reg_ssp_buffer;
                fsm_pc_new   <= reg_pc_buffer;
                fsm_ssp_load <= '1';
                fsm_pc_load  <= '1';

            when RUNNING =>
                fsm_running_mode <= '1';

					             -- =====================================================================
            -- EXCEPTION STACK PUSH: ISOLIERUNG DES FRAMES GEGEN SPEICHER-CORRUPTION
            -- =====================================================================
            when EXC_PUSH_PC =>
                fsm_bus_req      <= '1';
                fsm_bus_write    <= '1'; -- Schreiben auf den Stack (Push)
                fsm_bus_addr     <= std_logic_vector(internal_ssp - 4); -- PC belegt oberen Bereich des 6-Byte Frames
                fsm_bus_data_out <= std_logic_vector(internal_pc);      -- Rückkehr-Adresse sichern
                fsm_bus_type     <= "101";

            when EXC_PUSH_SR =>
                fsm_bus_req      <= '1';
                fsm_bus_write    <= '1'; 
                -- KORREKTUR: Sichert das SR-Word auf SP-6, ohne den bei SP-4 liegenden PC zu beschädigen!
                fsm_bus_addr     <= std_logic_vector(internal_ssp - 6); 
                fsm_bus_data_out <= reg_sr_buffer & x"0000";            -- Word linksbündig einbunden
                fsm_bus_type     <= "101";

            when EXC_FETCH_VECTOR =>
                fsm_bus_req   <= '1';
                fsm_bus_write <= '0'; -- Auflösen der OS-Routine (Read)
                fsm_bus_addr  <= reg_vector_addr;
                fsm_bus_type  <= "111"; -- CPU Space Cycle für Vektortabellen

            when EXC_APPLY =>
                fsm_pc_new   <= reg_pc_buffer;
                fsm_pc_load  <= '1';
                fsm_ssp_new  <= std_logic_vector(internal_ssp - 6); -- Stack Pointer permanent absenken
                fsm_ssp_load <= '1';

            -- =====================================================================
            -- EXCEPTION STACK POP VIA RTE
            -- =====================================================================
            when RTE_POP_SR =>
                fsm_bus_req   <= '1';
                fsm_bus_write <= '0'; -- Lesen vom Stack (Pop)
                fsm_bus_addr  <= std_logic_vector(internal_ssp);
                fsm_bus_type  <= "101";

            when RTE_POP_PC =>
                fsm_bus_req   <= '1';
                fsm_bus_write <= '0'; 
                fsm_bus_addr  <= std_logic_vector(internal_ssp + 2); -- PC liegt exakt hinter dem SR-Word
                fsm_bus_type  <= "101";

            when RTE_APPLY =>
                fsm_pc_new   <= reg_pc_buffer;
                fsm_pc_load  <= '1';
                fsm_ssp_new  <= std_logic_vector(internal_ssp + 6); -- Stack-Rahmen wieder freigeben
                fsm_ssp_load <= '1';

            when others => null;
        end case;
    end process;

	     -- =====================================================================
    -- 5. SYNCHRONER CONTROL-PROZESS: ZYKLUSTREUE MOTOROLA-EXCEPTION-FSM
    -- =====================================================================
    process(CLK, RESET_N)
        variable irq_offset : unsigned(31 downto 0);
    begin
        if RESET_N = '0' then
            current_state     <= RESET_STATE;
            internal_pc       <= (others => '0');
            internal_ssp      <= (others => '0');
            reg_ssp_buffer    <= (others => '0');
            reg_pc_buffer     <= (others => '0');
            reg_sr_buffer     <= x"2700";
            reg_vector_addr   <= (others => '0');
            reg_sr_mask       <= "111"; -- Startet voll maskiert auf Level 7
            supervisor_active <= '1';

        elsif rising_edge(CLK) then
            case current_state is

                when RESET_STATE =>
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
                    -- Rastet die echten Vektoren des Speicherbusses ein
                    internal_ssp  <= unsigned(reg_ssp_buffer);
                    internal_pc   <= unsigned(reg_pc_buffer);
                    current_state <= RUNNING;

                -- =========================================================
                -- RUNNING: ENTFIOCHTENE PIPELINE- UND EXCEPTION-WEICHE
                -- =========================================================
                when RUNNING =>
                
                    -- SONDER-PRIO A: ASYNCHRONER HARDWARE-INTERRUPT (PAULA)
                    -- Greift unbarmherzig VOR der ALU an der echten Befehlsgrenze!
                    if irq_asserted = '1' and (alu_ready = '1' or pipeline_empty = '1') then
                        reg_pc_buffer   <= std_logic_vector(internal_pc);
                        -- KORREKTUR: Hebt die Maske auf den irq_level an. Verhindert unendliche Interrupt-Fluten!
                        reg_sr_buffer   <= x"2" & "00" & irq_level & "0000000";
                        reg_sr_mask     <= irq_level;
                        supervisor_active <= '1';
                        
                        -- Autovektor-Tabellenplatz: 0x00000060 + (irq_level * 4)
                        irq_offset      := x"00000060" + resize(unsigned(irq_level) * 4, 32);
                        reg_vector_addr <= std_logic_vector(irq_offset);
                        current_state   <= EXC_PUSH_PC;

                    -- SONDER-PRIO B: PRIVILEGIERTER RÜCKKEHR-BEFEHL (RTE)
                    -- KORREKTUR: Aus alu_ready befreit, da administrativ autark!
                    elsif pipeline_empty = '0' and pipeline_word = x"4E73" then
                        current_state <= RTE_POP_SR;

                    -- CORE-AUSNAHMEN AN DER REGULÄREN BEFEHLSGRENZE (ALU_READY)
                    elsif alu_ready = '1' then
                        
                        if pipeline_empty = '0' and dec_exc_illegal = '1' then -- Illegal Opcode
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            reg_vector_addr <= x"00000010"; -- Vektor #4
                            current_state   <= EXC_PUSH_PC;

                        elsif exception_div_zero = '1' then -- Division durch Null
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            reg_vector_addr <= x"00000014"; -- Vektor #5
                            current_state   <= EXC_PUSH_PC;

                        elsif pipeline_empty = '0' and dec_exc_line_a = '1' then -- Line-A
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            reg_vector_addr <= x"00000028"; -- Vektor #10
                            current_state   <= EXC_PUSH_PC;

                        elsif pipeline_empty = '0' and dec_exc_line_f = '1' then -- Line-F
                            reg_pc_buffer   <= std_logic_vector(internal_pc);
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            reg_vector_addr <= x"0000002C"; -- Vektor #11
                            current_state   <= EXC_PUSH_PC;

                        elsif pipeline_empty = '0' and pipeline_word(15 downto 4) = x"4E4" then -- TRAP #x
                            reg_pc_buffer   <= std_logic_vector(internal_pc + 2); 
                            reg_sr_buffer   <= x"2" & "00" & reg_sr_mask & "0000000"; 
                            irq_offset      := x"00000080" + resize(unsigned(pipeline_word(3 downto 0)) * 4, 32);
                            reg_vector_addr <= std_logic_vector(irq_offset);
                            current_state   <= EXC_PUSH_PC;

                        else -- Linearer Befehlsvorschub
                            internal_pc <= internal_pc + 2;
                        end if;
                    end if;

                -- =========================================================
                -- HARDWARE STACK SEQUENCE STATUS-ÜBERGÄNGE
                -- =========================================================
                when EXC_PUSH_PC =>
                    if bus_cycle_done = '1' then current_state <= EXC_PUSH_SR; end if;

                when EXC_PUSH_SR =>
                    if bus_cycle_done = '1' then current_state <= EXC_FETCH_VECTOR; end if;

                when EXC_FETCH_VECTOR =>
                    if bus_cycle_done = '1' then
                        reg_pc_buffer <= internal_D_in; -- Holt echte Handler-Adresse aus der Tabelle!
                        current_state <= EXC_APPLY;
                    end if;

                when EXC_APPLY =>
                    internal_pc       <= unsigned(reg_pc_buffer);
                    internal_ssp      <= internal_ssp - 6; 
                    supervisor_active <= '1'; 
                    current_state     <= RUNNING;

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
                    internal_pc       <= unsigned(reg_pc_buffer);
                    internal_ssp      <= internal_ssp + 6; 
                    reg_sr_mask       <= reg_sr_buffer(10 downto 8); -- Restauriert alte Maske aus Stack
                    supervisor_active <= reg_sr_buffer(13);          -- Schaltet S/U-Modus zurück
                    current_state     <= RUNNING;

                when others => current_state <= RUNNING;
            end case;
        end if;
    end process;

end behavioral;
