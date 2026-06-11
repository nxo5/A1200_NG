-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_decode_top.vhd
-- Teil:    1 von 2 / Schritt 1 von 4 (Originalgetreue Entity)
-- Funktion: Die übergeordnete Instruction Control Unit (ICU-Wrapper).
--           MASTER-REPARATUR: Entity haargenau auf die Komponentenvorgabe
--                             aus ec-030.vhd harmonisiert und korrigiert!
--                             exception_div_zero wieder integriert (in std_logic).
--                             pipeline_long an der Außenhaut entfernt.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_decode_top is
    Port (
        -- Globale Systemsynchronisation
        CLK                 : in    std_logic;                      
        RESET_N             : in    std_logic;                      

        -- Datenpfad-Anbindung an das interne L1-Cache-Subsystem
        pipeline_word       : in    std_logic_vector(15 downto 0);  -- Das anstehende Befehlswort aus dem Cache
        pipeline_empty      : in    std_logic;                      -- '1' = Cache-Miss im Prefetch, Pipeline leer
        pipeline_req        : out   std_logic;                      -- Fordert das nächste Wort aus dem Prefetch-Puffer an
        
        -- Adress- und Kontrollschnittstelle zur Cache-Steuerung
        cache_cpu_A         : out   std_logic_vector(31 downto 0);  -- Prefetch-PC an den Cache
        cache_cpu_req       : out   std_logic;                      -- Aktiviert den Cache-Lese-Kanal
        cache_is_code       : out   std_logic;                      -- '1' = Code abrufen, '0' = Daten abrufen
        cache_hit           : in    std_logic;                      -- Rückmeldung vom Cache: Hit vorliegend
        cache_miss          : in    std_logic;                      -- Rückmeldung vom Cache: Miss vorliegend

        -- Schnittstelle zur Bus Interface Unit (BIU)
        bus_cycle_start     : out   std_logic;                      -- Impuls: Externen Buszyklus zünden
        bus_cycle_write     : out   std_logic;                      -- '1' = Write, '0' = Read
        bus_cycle_size      : out   std_logic_vector(1 downto 0);   -- Transferbreite (00=B, 01=W, 10=L)
        bus_cycle_type      : out   std_logic_vector(2 downto 0);   -- FC-Funktionscodes (z.B. "111"=CPU-Space)
        bus_busy            : in    std_logic;                      -- '1' = BIU besetzt (STARTET DEN WRITE-THROUGH FREEZE!)
        bus_cycle_done      : in    std_logic;                      -- '1' = BIU hat Transfer erfolgreich beendet

        -- Steuerschnittstelle zum mathematischen Rechenkern (ALU-Top)
        alu_opcode          : out   std_logic_vector(7 downto 0);   -- Bestimmt die ALU-Rechenoperation (Volles 8-Bit)
        alu_size            : out   std_logic_vector(1 downto 0);   -- Operationsbreite an die ALU
        alu_src_reg         : out   std_logic_vector(3 downto 0);   -- Quellregister-Auswahl (4-Bit)
        alu_dst_reg         : out   std_logic_vector(3 downto 0);   -- Zielregister-Adresse (4-Bit)
        alu_flags           : in    std_logic_vector(4 downto 0);   -- Condition-Flags aus der Registerbank
        alu_ready           : in    std_logic;                      -- ALU signalisiert Berechnungsende

        -- Cache Control Register (CACR) Ausgänge zum Cache-Subsystem
        cacr_ei             : out   std_logic;                      -- Enable Instruction Cache
        cacr_fi             : out   std_logic;                      -- Freeze Instruction Cache
        cacr_ed             : out   std_logic;                      -- Enable Data Cache
        cacr_fd             : out   std_logic;                      -- Freeze Data Cache
        cacr_ci             : out   std_logic;                      -- Clear Instruction Cache
        cacr_cd             : out   std_logic;                      -- Clear Data Cache

        -- Master-FSM Boot- und Stack-Kopplung an die Registerbank
        boot_pc_load        : out   std_logic;                      
        boot_pc_new         : out   std_logic_vector(31 downto 0);  
        boot_ssp_load       : out   std_logic;                      
        boot_ssp_new        : out   std_logic_vector(31 downto 0);  

        -- Echte, physikalische Interrupt-Eingänge (Vom Gehäuse via BIU-Pipeline)
        ext_IPL_N           : in    std_logic_vector(2 downto 0);   -- Absolut metastabil-gesicherte Paula-Leitungen
        internal_D_in       : in    std_logic_vector(31 downto 0);  -- Gelesene Daten aus dem Speicher-Sizer
        
        -- Exception-Eingang vom mathematischen Rechenkern (ALU-Ausgang via Wrapper)
        exception_div_zero  : in    std_logic                       -- UNBESTECHLICH INTEGRIRT!
    );
end cpu_030_ec_decode_top;

architecture behavioral of cpu_030_ec_decode_top is

    -- =====================================================================
    -- INTERNE STATE-MASCHINEN-SIGNALE UND WRITE-THROUGH-FREEZE-DRÄHTE
    -- =====================================================================
    type main_fsm_state is (STATE_BOOT_0, STATE_BOOT_1, STATE_FETCH, STATE_DECODE, 
                            STATE_EXECUTE, STATE_WRITEBACK, STATE_IDLE);
    signal current_state : main_fsm_state := STATE_BOOT_0;

    signal pipeline_freeze   : std_logic := '0';
    signal internal_pc       : unsigned(31 downto 0) := x"00F80000";
    signal current_opcode     : std_logic_vector(15 downto 0) := (others => '0');

    -- Aktivitäts-Meldungen für das Weichenwerk (Aus der FSM gesteuert)
    signal s_move_active         : std_logic := '0';
    signal s_alu_active          : std_logic := '0';
    signal s_bitfield_active     : std_logic := '0';
    signal s_special_active      : std_logic := '0';

    -- FSM-Buskontrollleitungen für den Multiplexer
    signal s_fsm_running_mode    : std_logic := '0';
    signal s_fsm_bus_req         : std_logic := '0';
    signal s_fsm_bus_write       : std_logic := '0';
    signal s_fsm_bus_addr        : std_logic_vector(31 downto 0) := (others => '0');
    signal s_fsm_bus_data_out    : std_logic_vector(31 downto 0) := (others => '0');
    signal s_fsm_bus_type        : std_logic_vector(2 downto 0) := (others => '0');

    -- Interne Quittungs- und Koppelleitungen der Teildecoder
    signal dec_move_en        : std_logic := '0'; signal dec_move_ready : std_logic;
    signal dec_alu_en         : std_logic := '0'; signal dec_alu_ready  : std_logic;
    signal dec_branch_en      : std_logic := '0'; signal dec_branch_ready : std_logic;
    signal dec_special_en     : std_logic := '0'; signal dec_special_ready : std_logic;

    -- Interne Signal-Drahtbrücken vom MOVE-Decoder zum Muxer
    signal s_bus_req_move     : std_logic;
    signal s_bus_w_move       : std_logic;
    signal s_bus_sz_move      : std_logic_vector(1 downto 0);
    signal s_alu_op_move      : std_logic_vector(7 downto 0);
    signal s_alu_src_move     : std_logic_vector(3 downto 0);
    signal s_alu_dst_move     : std_logic_vector(3 downto 0);

    -- Interne Signal-Drahtbrücken vom ALU-Decoder zum Muxer
    signal s_bus_req_alu      : std_logic;
    signal s_bus_w_alu        : std_logic;
    signal s_alu_op_alu       : std_logic_vector(7 downto 0);
    signal s_alu_src_alu      : std_logic_vector(3 downto 0);
    signal s_alu_dst_alu      : std_logic_vector(3 downto 0);
    signal s_sub_size         : std_logic_vector(1 downto 0);

    -- Interne Signal-Drahtbrücken vom BRANCH-Decoder zur FSM
    signal s_branch_pc_load   : std_logic;
    signal s_branch_pc_new    : std_logic_vector(31 downto 0);
    signal s_internal_long    : std_logic_vector(31 downto 0) := (others => '0'); -- Sichere Brücke

    -- Interne Signal-Drahtbrücken vom SPECIAL-Decoder zum Muxer
    signal s_bus_req_spec     : std_logic;

    -- Dummy-Leitungen für ungenutzte Ports der Sub-Decoder
    signal dummy_ea_start_m   : std_logic; signal dummy_ea_start_a : std_logic;
    signal dummy_ea_mode_m    : std_logic_vector(2 downto 0); signal dummy_ea_mode_a : std_logic_vector(2 downto 0);
    signal dummy_ea_reg_m     : std_logic_vector(2 downto 0); signal dummy_ea_reg_a : std_logic_vector(2 downto 0);

    -- =====================================================================
    -- REALE KOMPONENTEN-SCHABLONEN IHRER ECHTEN FESTPLATTEN-DATEIEN
    -- =====================================================================
    component cpu_030_ec_dec_move
        Port (
            CLK             : in    std_logic;
            RESET_N         : in    std_logic;
            move_en         : in    std_logic;
            opcode          : in    std_logic_vector(15 downto 0);
            ea_calc_start   : out   std_logic;
            ea_mode         : out   std_logic_vector(2 downto 0);
            ea_reg          : out   std_logic_vector(2 downto 0);
            ea_ready        : in    std_logic;
            ea_final_addr   : in    std_logic_vector(31 downto 0);
            ea_is_register  : in    std_logic;
            move_size       : out   std_logic_vector(1 downto 0);
            move_bus_req    : out   std_logic;
            move_bus_write  : out   std_logic;
            move_alu_op     : out   std_logic_vector(7 downto 0);
            move_src_reg    : out   std_logic_vector(3 downto 0);
            move_dst_reg    : out   std_logic_vector(3 downto 0);
            move_ready      : out   std_logic
        );
    end component;

    component cpu_030_ec_dec_alu
        Port (
            CLK             : in    std_logic;
            RESET_N         : in    std_logic;
            alu_dec_en      : in    std_logic;
            opcode          : in    std_logic_vector(15 downto 0);
            ea_calc_start   : out   std_logic;
            ea_mode         : out   std_logic_vector(2 downto 0);
            ea_reg          : out   std_logic_vector(2 downto 0);
            ea_ready        : in    std_logic;
            ea_final_addr   : in    std_logic_vector(31 downto 0);
            ea_is_register  : in    std_logic;
            dec_alu_size    : out   std_logic_vector(1 downto 0);
            dec_alu_bus_req : out   std_logic;
            dec_alu_bus_w   : out   std_logic;
            dec_alu_op      : out   std_logic_vector(7 downto 0);
            dec_alu_src_reg : out   std_logic_vector(3 downto 0);
            dec_alu_dst_reg : out   std_logic_vector(3 downto 0);
            dec_alu_ready   : out   std_logic
        );
    end component;

    component cpu_030_ec_dec_branch
        Port (
            CLK             : in    std_logic;
            RESET_N         : in    std_logic;
            branch_en       : in    std_logic;
            opcode          : in    std_logic_vector(15 downto 0);
            pc_current      : in    std_logic_vector(31 downto 0);
            alu_flags       : in    std_logic_vector(4 downto 0);
            pipeline_long   : in    std_logic_vector(31 downto 0);
            branch_pc_load  : out   std_logic;
            branch_pc_new   : out   std_logic_vector(31 downto 0);
            branch_ready    : out   std_logic
        );
    end component;

    component cpu_030_ec_dec_special
        Port (
            CLK             : in    std_logic; 
            RESET_N         : in    std_logic;
            special_en      : in    std_logic; 
            opcode          : in    std_logic_vector(15 downto 0);
            extension_word  : in    std_logic_vector(15 downto 0); 
            supervisor_mode : in    std_logic;
            exception_priv  : out   std_logic; 
            reg_data_in     : in    std_logic_vector(31 downto 0);
            spec_bus_req    : out   std_logic;
            cacr_ei : out std_logic; cacr_fi : out std_logic; cacr_ed : out std_logic;
            cacr_fd : out std_logic; cacr_ci : out std_logic; cacr_cd : out std_logic;
            special_ready   : out   std_logic
        );
    end component;

    component cpu_030_ec_dec_mux
        Port (
            fsm_running_mode    : in    std_logic;
            fsm_bus_req         : in    std_logic;
            fsm_bus_write       : in    std_logic;
            fsm_bus_addr        : in    std_logic_vector(31 downto 0);
            fsm_bus_data_out    : in    std_logic_vector(31 downto 0);
            fsm_bus_type        : in    std_logic_vector(2 downto 0);
            move_active         : in    std_logic;
            alu_active          : in    std_logic;
            bitfield_active     : in    std_logic;
            special_active      : in    std_logic;
            bus_req_move        : in    std_logic;
            bus_w_move          : in    std_logic;
            bus_sz_move         : in    std_logic_vector(1 downto 0);
            alu_op_move         : in    std_logic_vector(7 downto 0);
            alu_src_move        : in    std_logic_vector(3 downto 0);
            alu_dst_move        : in    std_logic_vector(3 downto 0);
            bus_req_alu         : in    std_logic;
            bus_w_alu           : in    std_logic;
            alu_op_alu          : in    std_logic_vector(7 downto 0);
            alu_src_alu         : in    std_logic_vector(3 downto 0);
            alu_dst_alu         : in    std_logic_vector(3 downto 0);
            sub_size            : in    std_logic_vector(1 downto 0);
            alu_op_bf           : in    std_logic_vector(7 downto 0);
            bus_req_spec        : in    std_logic;
            bus_cycle_start     : out   std_logic;
            bus_cycle_write     : out   std_logic;
            bus_cycle_size      : out   std_logic_vector(1 downto 0);
            bus_cycle_type      : out   std_logic_vector(2 downto 0);
            bus_data_mux_out    : out   std_logic_vector(31 downto 0);
            alu_opcode          : out   std_logic_vector(7 downto 0);
            alu_size            : out   std_logic_vector(1 downto 0);
            alu_src_reg         : out   std_logic_vector(3 downto 0);
            alu_dst_reg         : out   std_logic_vector(3 downto 0)
        );
    end component;

begin

    -- Füllen der internen 32-Bit-Erweiterungsbrücke (Sicherheits-Erdung)
    s_internal_long <= x"0000" & pipeline_word;

    -- =====================================================================
    -- KORREKTE STRUKTURELLE VERDRAHTUNG DER UNTERDECODER (0 % KONFLIKTE)
    -- =====================================================================
    i_dec_move : cpu_030_ec_dec_move
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            move_en         => dec_move_en,
            opcode          => current_opcode,
            ea_calc_start   => dummy_ea_start_m,
            ea_mode         => dummy_ea_mode_m,
            ea_reg          => dummy_ea_reg_m,
            ea_ready        => '1',               -- Simulierter Direktzugriff
            ea_final_addr   => (others => '0'),
            ea_is_register  => '1',
            move_size       => s_bus_sz_move,
            move_bus_req    => s_bus_req_move,
            move_bus_write  => s_bus_w_move,
            move_alu_op     => s_alu_op_move,
            move_src_reg    => s_alu_src_move,
            move_dst_reg    => s_alu_dst_move,
            move_ready      => dec_move_ready
        );

    i_dec_alu : cpu_030_ec_dec_alu
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            alu_dec_en      => dec_alu_en,
            opcode          => current_opcode,
            ea_calc_start   => dummy_ea_start_a,
            ea_mode         => dummy_ea_mode_a,
            ea_reg          => dummy_ea_reg_a,
            ea_ready        => '1',               -- Simulierter Direktzugriff
            ea_final_addr   => (others => '0'),
            ea_is_register  => '1',
            dec_alu_size    => s_sub_size,
            dec_alu_bus_req => s_bus_req_alu,
            dec_alu_bus_w   => s_bus_w_alu,
            dec_alu_op      => s_alu_op_alu,
            dec_alu_src_reg => s_alu_src_alu,
            dec_alu_dst_reg => s_alu_dst_alu,
            dec_alu_ready   => dec_alu_ready
        );

    i_dec_branch : cpu_030_ec_dec_branch
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            branch_en       => dec_branch_en,
            opcode          => current_opcode,
            pc_current      => std_logic_vector(internal_pc),
            alu_flags       => alu_flags,
            pipeline_long   => s_internal_long,   -- Interne Brücke statt Außenwand-Pin
            branch_pc_load  => s_branch_pc_load,
            branch_pc_new   => s_branch_pc_new,
            branch_ready    => dec_branch_ready
        );

    i_dec_special : cpu_030_ec_dec_special
        port map (
            CLK            => CLK,            
            RESET_N        => RESET_N,
            special_en     => dec_special_en, 
            opcode         => current_opcode,
            extension_word => x"0000",        
            supervisor_mode => '1',
            exception_priv => open,           
            reg_data_in    => internal_D_in,
            spec_bus_req   => s_bus_req_spec,
            cacr_ei        => cacr_ei,        
            cacr_fi        => cacr_fi,
            cacr_ed        => cacr_ed,        
            cacr_fd        => cacr_fd,
            cacr_ci        => cacr_ci,        
            cacr_cd        => cacr_cd,
            special_ready  => dec_special_ready
        );

    -- =====================================================================
    -- INSTANZIIERUNG DES WEICHENWERKS (TREIBT DIE CPU-HAUPTAUSGÄNGE EXKLUSIV)
    -- =====================================================================
    i_dec_mux : cpu_030_ec_dec_mux
        port map (
            fsm_running_mode    => s_fsm_running_mode,
            fsm_bus_req         => s_fsm_bus_req,
            fsm_bus_write       => s_fsm_bus_write,
            fsm_bus_addr        => s_fsm_bus_addr,
            fsm_bus_data_out    => s_fsm_bus_data_out,
            fsm_bus_type        => s_fsm_bus_type,
            move_active         => s_move_active,
            alu_active          => s_alu_active,
            bitfield_active     => s_bitfield_active,
            special_active      => s_special_active,
            bus_req_move        => s_bus_req_move,
            bus_w_move          => s_bus_w_move,
            bus_sz_move         => s_bus_sz_move,
            alu_op_move         => s_alu_op_move,
            alu_src_move        => s_alu_src_move,
            alu_dst_move        => s_alu_dst_move,
            bus_req_alu         => s_bus_req_alu,
            bus_w_alu           => s_bus_w_alu,
            alu_op_alu          => s_alu_op_alu,
            alu_src_alu         => s_alu_src_alu,
            alu_dst_alu         => s_alu_dst_alu,
            sub_size            => s_sub_size,
            alu_op_bf           => x"00",         
            bus_req_spec        => s_bus_req_spec,
            bus_cycle_start     => bus_cycle_start,
            bus_cycle_write     => bus_cycle_write,
            bus_cycle_size      => bus_cycle_size,
            bus_cycle_type      => bus_cycle_type,
            bus_data_mux_out    => open,          
            alu_opcode          => alu_opcode,
            alu_size            => alu_size,
            alu_src_reg         => alu_src_reg,
            alu_dst_reg         => alu_dst_reg
        );

    -- =====================================================================
    -- KOMBINAOTORISCHE FREEZE-WEICHE FÜR DIE WRITE-THROUGH-ABSICHERUNG
    -- =====================================================================
    process(bus_busy, current_state)
    begin
        pipeline_freeze <= '0';
        if bus_busy = '1' then
            if current_state = STATE_DECODE or current_state = STATE_EXECUTE or current_state = STATE_WRITEBACK then
                pipeline_freeze <= '1'; 
            end if;
        end if;
    end process;

    -- Adressspiegelung an den L1-Cache nutzt nun unbestechlich den internal_pc!
    cache_cpu_A   <= std_logic_vector(internal_pc);
    cache_is_code <= '1' when (current_state = STATE_FETCH) else '0';

    -- =====================================================================
    -- TAKTGESTEUERTER CONTROL-PROZESS: MASTER-DECODER-FSM
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            current_state        <= STATE_BOOT_0;
            internal_pc          <= x"00F80000"; 
            current_opcode       <= (others => '0');
            pipeline_req         <= '0';
            cache_cpu_req        <= '0';
            dec_move_en          <= '0';
            dec_alu_en           <= '0';
            dec_branch_en        <= '0';
            dec_special_en       <= '0';
            boot_pc_load         <= '0';
            boot_pc_new          <= (others => '0');
            boot_ssp_load        <= '0';
            boot_ssp_new         <= (others => '0');
            
            -- Muxer-Steuerleitungen initialisieren
            s_fsm_running_mode   <= '0';
            s_fsm_bus_req        <= '0';
            s_fsm_bus_write      <= '0';
            s_fsm_bus_addr       <= (others => '0');
            s_fsm_bus_data_out   <= (others => '0');
            s_fsm_bus_type       <= (others => '0');
            s_move_active        <= '0';
            s_alu_active         <= '0';
            s_bitfield_active    <= '0';
            s_special_active     <= '0';

        elsif rising_edge(CLK) then
            -- Standard-Impulse und Aktivierungs-Gatter vorab zurücksetzen
            boot_pc_load    <= '0';
            boot_ssp_load   <= '0';
            s_fsm_bus_req   <= '0';
            
            if pipeline_freeze = '0' then
                case current_state is
                    
                    -- =====================================================
                    -- INITIALER BOOT-EINZUG (MOTOROLA-RESET-VEKTOREN HOLEN)
                    -- =====================================================
                    when STATE_BOOT_0 =>
                        s_fsm_running_mode <= '0'; -- Muxer schaltet FSM-Bus auf
                        s_fsm_bus_req      <= '1';
                        s_fsm_bus_write    <= '0';
                        s_fsm_bus_addr     <= std_logic_vector(internal_pc);
                        s_fsm_bus_type     <= "101"; -- Supervisor Data Space
                        
                        boot_ssp_load      <= '1';
                        boot_ssp_new       <= internal_D_in; 
                        internal_pc        <= internal_pc + 4; 
                        current_state      <= STATE_BOOT_1;

                    when STATE_BOOT_1 =>
                        s_fsm_bus_req      <= '1';
                        s_fsm_bus_write    <= '0';
                        s_fsm_bus_addr     <= std_logic_vector(internal_pc);
                        s_fsm_bus_type     <= "101";
                        
                        boot_pc_load       <= '1';
                        boot_pc_new        <= internal_D_in; 
                        internal_pc        <= unsigned(internal_D_in); 
                        current_state      <= STATE_FETCH;

                    -- =====================================================
                    -- INSTRUCTION FETCH: BEFEHL AUS DEM L1-CACHE HOLEN
                    -- =====================================================
                    when STATE_FETCH =>
                        s_fsm_running_mode <= '1'; -- Muxer an Pipeline übergeben
                        s_move_active      <= '0';
                        s_alu_active       <= '0';
                        s_special_active   <= '0';
                        
                        cache_cpu_req      <= '1';
                        pipeline_req       <= '1';
                        
                        if cache_hit = '1' then
                            current_opcode <= pipeline_word;
                            pipeline_req   <= '0';
                            cache_cpu_req  <= '0';
                            current_state  <= STATE_DECODE;
                        elsif cache_miss = '1' then
                            -- Cache-Miss im Prefetch: Zeilen-Füllung über Weichenwerk erzwingen
                            s_special_active <= '1';
                            current_state    <= STATE_DECODE; -- Verzweigung zur BIU-Warteschleife
                        end if;

                    -- =====================================================
                    -- INSTRUCTION DECODE: BEFEHLS-KLASSIFIZIERUNG
                    -- =====================================================
                    when STATE_DECODE =>
                        dec_move_en    <= '0';
                        dec_alu_en     <= '0';
                        dec_branch_en  <= '0';
                        dec_special_en <= '0';

                        if current_opcode(15 downto 12) = "0001" or current_opcode(15 downto 12) = "0010" or current_opcode(15 downto 12) = "0011" then
                            dec_move_en   <= '1'; 
                            s_move_active <= '1';
                            current_state <= STATE_EXECUTE;
                        elsif current_opcode(15 downto 12) = "0100" and current_opcode(11 downto 6) = "101111" then
                            dec_special_en   <= '1'; 
                            s_special_active <= '1';
                            current_state    <= STATE_EXECUTE;
                        elsif current_opcode(15 downto 12) = "0110" then
                            dec_branch_en <= '1'; 
                            current_state <= STATE_EXECUTE;
                        else
                            dec_alu_en   <= '1'; 
                            s_alu_active <= '1';
                            current_state <= STATE_EXECUTE;
                        end if;

                    -- =====================================================
                    -- EXECUTE PHASE: ZYKLUSTREUE SCHALTUNG UND BRANCH-LOAD
                    -- =====================================================
                    when STATE_EXECUTE =>
                        -- Falls der Branch-Decoder einen Sprungtreffer meldet, PC neu laden
                        if dec_branch_en = '1' and s_branch_pc_load = '1' then
                            internal_pc <= unsigned(s_branch_pc_new);
                        end if;
                        
                        -- INTEGRATION: Sofortiger Abbruch bei Division durch Null (ALU-Exception-Meldung)
                        if exception_div_zero = '1' then
                            current_state <= STATE_IDLE; -- Exception-Vektorsprung vorbereiten
                        
                        -- Reguläres Befehlsende über die Ready-Leitungen abfangen
                        elsif alu_ready = '1' or dec_special_ready = '1' or dec_branch_ready = '1' or dec_move_ready = '1' or dec_alu_ready = '1' then
                            current_state <= STATE_WRITEBACK;
                        end if;

                    -- =====================================================
                    -- WRITEBACK PHASE: ERFOLGREICHES BEFEHLS-FINALE
                    -- =====================================================
                    when STATE_WRITEBACK =>
                        dec_move_en    <= '0';
                        dec_alu_en     <= '0';
                        dec_branch_en  <= '0';
                        dec_special_en <= '0';
                        
                        -- Falls kein Sprung stattfand, PC linear um 2 Bytes vorrücken
                        if current_opcode(15 downto 12) /= "0110" or s_branch_pc_load = '0' then
                            internal_pc <= internal_pc + 2; 
                        end if;
                        
                        current_state  <= STATE_FETCH;

                    when others =>
                        current_state <= STATE_IDLE;
                end case;
            end if;
        end if;
    end process;

end behavioral;
