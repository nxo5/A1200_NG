-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_decode_top.vhd
-- Teil:    1 von 5 (Bereinigte Entity-Schnittstelle)
-- Funktion: Die übergeordnete Instruction Control Unit (ICU-Wrapper).
-- REPARATUR: 
--   - Doppeldeklaration von alu_opcode restlos eliminiert!
--   - Indexierungs-Fehler im ALU-Kanal behoben.
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
        bus_busy            : in    std_logic;                      -- '1' = BIU besetzt
        bus_cycle_done      : in    std_logic;                      -- Das trennende Semikolon steht unbestechlich!

        -- Steuerschnittstelle zum mathematischen Rechenkern (ALU-Top)
        -- REPARATUR: Eindeutige Deklaration des 8-Bit Opcode-Kanals ohne Doppel-Müll
        alu_opcode          : out   std_logic_vector(7 downto 0);   -- Fixierter 8-Bit Opcode-Vektor
        alu_size            : out   std_logic_vector(1 downto 0);   -- Operationsbreite an die ALU
        alu_src_reg         : out   std_logic_vector(3 downto 0);   -- Quellregister-Auswahl
        alu_dst_reg         : out   std_logic_vector(3 downto 0);   -- Zielregister-Adresse
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

        -- Echte, physikalische Interrupt-Eingänge (Paula-Leitungen via BIU)
        ext_IPL_N           : in    std_logic_vector(2 downto 0);   
        internal_D_in       : in    std_logic_vector(31 downto 0);  -- Gelesene Daten aus dem Bus-Sizer
        
        -- Exception-Eingang vom mathematischen Rechenkern (ALU-Top)
        exception_div_zero  : in    std_logic                       -- Exception-Meldung der ALU
    );
end cpu_030_ec_decode_top;

architecture behavioral of cpu_030_ec_decode_top is

    -- =====================================================================
    -- STRUKTURELLE ZUSTANDSSIGNALE DER MASTER-KOORDINATION
    -- =====================================================================
    signal s_master_state       : integer range 0 to 2; -- 0=Boot, 1=Exec, 2=Trap
    signal s_internal_long      : std_logic_vector(31 downto 0);

    -- Symmetrischer 32-Bit-Programmzähler des Hauptfließbands
    signal s_internal_pc        : unsigned(31 downto 0); 

    -- Internes latch-freies Freeze-Netzwerk
    signal pipeline_freeze      : std_logic;

    -- Sub-Aktivierungssignale der Teil-Zustandsmaschinen
    signal s_boot_en            : std_logic; 
    signal s_boot_done          : std_logic; 
    signal s_exec_en            : std_logic;
    signal s_trap_en            : std_logic; 
    signal s_trap_done          : std_logic;

    -- Symmetrische 32-Bit-Bereiche für alle Sub-Rückführungen (PC-Quellen)
    signal s_pc_boot            : unsigned(31 downto 0);
    signal s_pc_exec            : unsigned(31 downto 0);
    signal s_pc_trap            : unsigned(31 downto 0);

    -- Bus-Drahtbrücken von den Sub-Modulen zum Weichenwerk
    signal s_bus_req_boot       : std_logic; 
    signal s_bus_w_boot         : std_logic;
    signal s_bus_addr_boot      : std_logic_vector(31 downto 0); 
    signal s_bus_type_boot      : std_logic_vector(2 downto 0);
    signal s_bus_req_trap       : std_logic; 
    signal s_bus_w_trap         : std_logic;
    signal s_bus_addr_trap      : std_logic_vector(31 downto 0); 
    signal s_bus_type_trap      : std_logic_vector(2 downto 0);

    -- Koordinierte Multiplexer-Busleitungen der FSM-Ebene
    signal s_fsm_running_mode   : std_logic;
    signal s_fsm_bus_req        : std_logic;
    signal s_fsm_bus_write      : std_logic;
    signal s_fsm_bus_addr       : std_logic_vector(31 downto 0);
    signal s_fsm_bus_data_out   : std_logic_vector(31 downto 0);
    signal s_fsm_bus_type       : std_logic_vector(2 downto 0);

    -- Kombinatorische Aktivitäts-Meldungen für das Weichenwerk
    signal s_move_active        : std_logic;
    signal s_alu_active         : std_logic;
    signal s_bitfield_active    : std_logic;
    signal s_special_active     : std_logic;
    signal s_cache_inhibit_act  : std_logic;

    -- Entflochtenes internes Signalnetzwerk der Teildecoder
    signal dec_move_en          : std_logic; 
    signal dec_move_ready       : std_logic;
    signal dec_alu_en           : std_logic; 
    signal dec_branch_en        : std_logic; 
    signal dec_branch_ready     : std_logic;
    signal dec_special_en       : std_logic; 
    signal dec_special_ready    : std_logic;
    signal s_alu_decoder_done   : std_logic;
    signal s_branch_pc_load     : std_logic;        
    signal s_branch_pc_new      : std_logic_vector(31 downto 0);

    -- Interne Signal-Drahtbrücken vom MOVE-Decoder zum Muxer
    signal s_bus_req_move       : std_logic; 
    signal s_bus_w_move         : std_logic; 
    signal s_bus_sz_move        : std_logic_vector(1 downto 0);
    signal s_alu_op_move        : std_logic_vector(7 downto 0); 
    signal s_alu_src_move       : std_logic_vector(3 downto 0); 
    signal s_alu_dst_move       : std_logic_vector(3 downto 0);

    -- Interne Signal-Drahtbrücken vom ALU-Decoder zum Muxer
    signal s_bus_req_alu        : std_logic; 
    signal s_bus_w_alu          : std_logic; 
    signal s_sub_size           : std_logic_vector(1 downto 0);
    signal s_alu_op_alu         : std_logic_vector(7 downto 0); 
    signal s_alu_src_alu        : std_logic_vector(3 downto 0); 
    signal s_alu_dst_alu        : std_logic_vector(3 downto 0);

    -- Gekoppeltes Adress-Netzwerk für die geteilte EA-Matrix
    signal s_ea_calc_start      : std_logic;
    signal s_ea_mode            : std_logic_vector(2 downto 0);
    signal s_ea_reg             : std_logic_vector(2 downto 0);
    signal s_ea_ready           : std_logic;
    signal s_ea_final_addr      : std_logic_vector(31 downto 0);
    signal s_ea_is_register     : std_logic;

    -- Dummies und Zusatzsignale für System-Ports
    signal s_bus_req_spec       : std_logic;
    signal s_extension_word     : std_logic_vector(15 downto 0);
    signal s_sync_ipl_n         : std_logic_vector(2 downto 0);

	     -- =====================================================================
    -- SCHABLONE: MASTER-BOOT-FSM (KALKSTART-EINZUG)
    -- =====================================================================
    component cpu_030_ec_dec_boot_fsm
        Port (
            CLK                 : in    std_logic; 
            RESET_N             : in    std_logic;
            boot_en             : in    std_logic; 
            boot_busy           : in    std_logic; 
            boot_done           : out   std_logic;
            internal_pc_in      : in    unsigned(31 downto 0); 
            internal_pc_out     : out   unsigned(31 downto 0);
            internal_D_in       : in    std_logic_vector(31 downto 0);
            fsm_bus_req         : out   std_logic; 
            fsm_bus_write       : out   std_logic; 
            fsm_bus_addr        : out   std_logic_vector(31 downto 0); 
            fsm_bus_type        : out   std_logic_vector(2 downto 0);
            boot_ssp_load       : out   std_logic; 
            boot_ssp_new        : out   std_logic_vector(31 downto 0);
            boot_pc_load        : out   std_logic; 
            boot_pc_new         : out   std_logic_vector(31 downto 0)
        );
    end component;

    -- =====================================================================
    -- SCHABLONE: FLIESSBAND-EXEC-FSM (REGULÄRER PIPELINE-BETRIEB)
    -- =====================================================================
    component cpu_030_ec_dec_exec_fsm
        Port (
            CLK                 : in    std_logic; 
            RESET_N             : in    std_logic;
            exec_en             : in    std_logic; 
            exec_busy           : in    std_logic; 
            exec_irq_pending    : in    std_logic; 
            exec_trap_pending   : in    std_logic; 
            exec_trap_trigger   : out   std_logic;
            pipeline_word       : in    std_logic_vector(15 downto 0); 
            pipeline_req        : out   std_logic; 
            cache_cpu_req       : out   std_logic; 
            cache_hit           : in    std_logic; 
            cache_miss          : in    std_logic;
            internal_pc_in      : in    unsigned(31 downto 0); 
            internal_pc_out     : out   unsigned(31 downto 0);
            s_fsm_running_mode  : out   std_logic; 
            s_move_active       : out   std_logic; 
            s_alu_active        : out   std_logic; 
            s_special_active    : out   std_logic;
            dec_move_en         : out   std_logic; 
            dec_move_ready      : in    std_logic; 
            dec_alu_en          : out   std_logic; 
            s_alu_decoder_done  : in    std_logic;
            dec_branch_en       : out   std_logic; 
            dec_branch_ready    : in    std_logic; 
            dec_special_en      : out   std_logic; 
            dec_special_ready   : in    std_logic;
            s_branch_pc_load    : in    std_logic; 
            s_branch_pc_new     : in    std_logic_vector(31 downto 0);
            s_cache_inhibit_act : out   std_logic; 
            bus_cycle_done      : in    std_logic
        );
    end component;

    -- =====================================================================
    -- SCHABLONE: TRAP-UNIT (AUSNAHME-FANGNETZ UND IACK)
    -- =====================================================================
    component cpu_030_ec_dec_trap_unit
        Port (
            CLK                 : in    std_logic; 
            RESET_N             : in    std_logic;
            trap_en             : in    std_logic; 
            trap_busy           : in    std_logic; 
            trap_done           : out   std_logic;
            exception_div_zero  : in    std_logic; 
            s_irq_latch         : in    std_logic_vector(2 downto 0);
            internal_D_in       : in    std_logic_vector(31 downto 0); 
            s_data_hold_latch   : out   std_logic_vector(31 downto 0); 
            internal_pc_out     : out   unsigned(31 downto 0);
            fsm_running_mode    : out   std_logic; 
            fsm_bus_req         : out   std_logic; 
            fsm_bus_write       : out   std_logic; 
            fsm_bus_addr        : out   std_logic_vector(31 downto 0); 
            fsm_bus_type        : out   std_logic_vector(2 downto 0);
            bus_cycle_done      : in    std_logic
        );
    end component;

	     -- =====================================================================
    -- SCHABLONE: GETEILTE ADRESS-MATRIX (ALM-SCHONUNG)
    -- =====================================================================
    component cpu_030_ec_dec_ea_shared
        Port (
            CLK                 : in    std_logic; 
            RESET_N             : in    std_logic;
            opcode              : in    std_logic_vector(15 downto 0);
            move_active         : in    std_logic;
            alu_active          : in    std_logic;
            ea_calc_start       : out   std_logic; 
            ea_mode             : out   std_logic_vector(2 downto 0); 
            ea_reg              : out   std_logic_vector(2 downto 0);
            ea_ready            : out   std_logic; 
            ea_final_addr       : out   std_logic_vector(31 downto 0); 
            ea_is_register      : out   std_logic
        );
    end component;

    -- =====================================================================
    -- SCHABLONE: ENTFIOCHTENER MOVE-FILIAL-DECODER
    -- =====================================================================
    component cpu_030_ec_dec_move
        Port (
            CLK             : in    std_logic; 
            RESET_N         : in    std_logic; 
            move_en         : in    std_logic; 
            opcode          : in    std_logic_vector(15 downto 0);
            ea_calc_start   : out   std_logic; 
            ea_mode         : in    std_logic_vector(2 downto 0); 
            ea_reg          : in    std_logic_vector(2 downto 0); 
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

    -- =====================================================================
    -- SCHABLONE: ENTFIOCHTENER ALU-FILIAL-DECODER
    -- =====================================================================
    component cpu_030_ec_dec_alu
        Port (
            CLK             : in    std_logic; 
            RESET_N         : in    std_logic; 
            alu_dec_en      : in    std_logic; 
            opcode          : in    std_logic_vector(15 downto 0);
            ea_calc_start   : out   std_logic; 
            ea_mode         : in    std_logic_vector(2 downto 0); 
            ea_reg          : in    std_logic_vector(2 downto 0); 
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

    -- =====================================================================
    -- SCHABLONE: BRANCH-DECODER FÜR WEITE SPRÜNGE
    -- =====================================================================
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

    -- =====================================================================
    -- SCHABLONE: PRIVILEGIERTER SYSTEM-DECODER
    -- =====================================================================
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
            cacr_ei         : out   std_logic; 
            cacr_fi         : out   std_logic; 
            cacr_ed         : out   std_logic; 
            cacr_fd         : out   std_logic; 
            cacr_ci         : out   std_logic; 
            cacr_cd         : out   std_logic; 
            special_ready   : out   std_logic
        );
    end component;

    -- =====================================================================
    -- SCHABLONE: CORESPEISENDES WEICHENWERK (MUX)
    -- =====================================================================
    component cpu_030_ec_dec_mux
        Port (
            fsm_running_mode : in std_logic; fsm_bus_req : in std_logic; fsm_bus_write : in std_logic; fsm_bus_addr : in std_logic_vector(31 downto 0); fsm_bus_data_out : in std_logic_vector(31 downto 0); fsm_bus_type : in std_logic_vector(2 downto 0);
            move_active : in std_logic; alu_active : in std_logic; bitfield_active : in std_logic; special_active : in std_logic;
            bus_req_move : in std_logic; bus_w_move : in std_logic; bus_sz_move : in std_logic_vector(1 downto 0); alu_op_move : in std_logic_vector(7 downto 0); alu_src_move : in std_logic_vector(3 downto 0); alu_dst_move : in std_logic_vector(3 downto 0);
            bus_req_alu : in std_logic; bus_w_alu : in std_logic; alu_op_alu : in std_logic_vector(7 downto 0); alu_src_alu : in std_logic_vector(3 downto 0); alu_dst_alu : in std_logic_vector(3 downto 0); sub_size : in std_logic_vector(1 downto 0);
            alu_op_bf : in std_logic_vector(7 downto 0); bus_req_spec : in std_logic;
            bus_cycle_start : out std_logic; bus_cycle_write : out std_logic; bus_cycle_size : out std_logic_vector(1 downto 0); bus_cycle_type : out std_logic_vector(2 downto 0); bus_data_mux_out : out std_logic_vector(31 downto 0);
            alu_opcode : out std_logic_vector(7 downto 0); alu_size : out std_logic_vector(1 downto 0); alu_src_reg : out std_logic_vector(3 downto 0); alu_dst_reg : out std_logic_vector(3 downto 0)
        );
    end component;

	 begin

    -- =====================================================================
    -- KORREKTUR: REINER COMBINATORIAL 0-LATENZ PROGRAMMZÄHLER-BYPASS
    -- ERZWINGT ABSOLUTE PIPELINE-SYNCHRONITÄT OHNE CACHE-WAIT-STATES!
    -- =====================================================================
    s_internal_pc <= s_pc_boot when (s_master_state = 0) else
                     s_pc_trap when (s_master_state = 2) else
                     s_pc_exec;

    -- Adressraumzuweisung permanent an das Cache-Subsystem weiterreichen
    cache_cpu_A   <= std_logic_vector(s_internal_pc);
    cache_is_code <= '1' when (s_master_state = 1) else '0';

    -- Vorab-Isolierung des 32-Bit-Erweiterungsbusses für den Branch-Decoder
    s_internal_long <= x"0000" & pipeline_word;
    s_extension_word <= pipeline_word;

    -- =====================================================================
    -- CO-PROZESSOR: DIE GETEILTE ADRESS-MATRIX INSTANZIIEREN (HEBEL A)
    -- KORREKTUR: opcode hört auf das echte Befehlswort, nicht auf Adressen!
    -- =====================================================================
    i_dec_ea_shared : cpu_030_ec_dec_ea_shared
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            opcode          => pipeline_word, -- ECHTER PROGRAMM-OPCODE!
            move_active     => s_move_active,
            alu_active      => s_alu_active,
            ea_calc_start   => s_ea_calc_start,
            ea_mode         => s_ea_mode,
            ea_reg          => s_ea_reg,
            ea_ready        => s_ea_ready,
            ea_final_addr   => s_ea_final_addr,
            ea_is_register  => s_ea_is_register
        );

    -- =====================================================================
    -- STRUKTURELLE VERDRAHTUNG DER FILIAL-DECODER (ECHTE PIPELINE-ANBINDUNG)
    -- =====================================================================
    i_dec_move : cpu_030_ec_dec_move
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            move_en         => dec_move_en,
            opcode          => pipeline_word, -- ECHTER PROGRAMM-OPCODE!
            ea_calc_start   => open,                  
            ea_mode         => s_ea_mode,             
            ea_reg          => s_ea_reg,              
            ea_ready        => s_ea_ready,            
            ea_final_addr   => s_ea_final_addr,       
            ea_is_register  => s_ea_is_register,      
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
            opcode          => pipeline_word, -- ECHTER PROGRAMM-OPCODE!
            ea_calc_start   => open,                  
            ea_mode         => s_ea_mode,             
            ea_reg          => s_ea_reg,              
            ea_ready        => s_ea_ready,            
            ea_final_addr   => s_ea_final_addr,       
            ea_is_register  => s_ea_is_register,      
            dec_alu_size    => s_sub_size,
            dec_alu_bus_req => s_bus_req_alu,
            dec_alu_bus_w   => s_bus_w_alu,
            dec_alu_op      => s_alu_op_alu,
            dec_alu_src_reg => s_alu_src_alu, 
            dec_alu_dst_reg => s_alu_dst_alu, 
            dec_alu_ready   => s_alu_decoder_done
        );

		      i_dec_branch : cpu_030_ec_dec_branch
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            branch_en       => dec_branch_en,
            opcode          => pipeline_word, -- ECHTER PROGRAMM-OPCODE!
            pc_current      => std_logic_vector(s_internal_pc),
            alu_flags       => alu_flags,
            pipeline_long   => s_internal_long,
            branch_pc_load  => s_branch_pc_load,
            branch_pc_new   => s_branch_pc_new,
            branch_ready    => dec_branch_ready
        );

    i_dec_special : cpu_030_ec_dec_special
        port map (
            CLK             => CLK,            
            RESET_N         => RESET_N,
            special_en      => dec_special_en, 
            opcode          => pipeline_word, -- ECHTER PROGRAMM-OPCODE!
            extension_word  => s_extension_word, -- ECHTES ERWEITERUNGSWORT!
            supervisor_mode => s_fsm_running_mode, -- An Master-Schutzleitung gekoppelt!
            exception_priv  => open,           
            reg_data_in     => internal_D_in,
            spec_bus_req    => s_bus_req_spec,
            cacr_ei         => cacr_ei,        
            cacr_fi         => cacr_fi,
            cacr_ed         => cacr_ed,        
            cacr_fd         => cacr_fd,
            cacr_ci         => cacr_ci,        
            cacr_cd         => cacr_cd,
            special_ready   => dec_special_ready
        );

    -- =====================================================================
    -- STRUKTURELLE VERDRAHTUNG DER DREI MASTER-SUBMODULE
    -- =====================================================================
    i_boot_fsm : cpu_030_ec_dec_boot_fsm
        port map (
            CLK                 => CLK,
            RESET_N             => RESET_N,
            boot_en             => s_boot_en,
            boot_busy           => bus_busy,
            boot_done           => s_boot_done,
            internal_pc_in      => s_internal_pc,
            internal_pc_out     => s_pc_boot,
            internal_D_in       => internal_D_in,
            fsm_bus_req         => s_bus_req_boot,
            fsm_bus_write       => s_bus_w_boot,
            fsm_bus_addr        => s_bus_addr_boot,
            fsm_bus_type        => s_bus_type_boot,
            boot_ssp_load       => boot_ssp_load,
            boot_ssp_new        => boot_ssp_new,
            boot_pc_load        => boot_pc_load,
            boot_pc_new         => boot_pc_new
        );

    i_exec_fsm : cpu_030_ec_dec_exec_fsm
        port map (
            CLK                 => CLK,
            RESET_N             => RESET_N,
            exec_en             => s_exec_en,
            exec_busy           => pipeline_freeze,
            exec_irq_pending    => '0',
            exec_trap_pending   => exception_div_zero,
            exec_trap_trigger   => open,
            pipeline_word       => pipeline_word,
            pipeline_req        => pipeline_req,
            cache_cpu_req       => cache_cpu_req,
            cache_hit           => cache_hit,
            cache_miss          => cache_miss,
            internal_pc_in      => s_internal_pc,
            internal_pc_out     => s_pc_exec,
            s_fsm_running_mode  => s_fsm_running_mode,
            s_move_active       => s_move_active,
            s_alu_active        => s_alu_active,
            s_special_active    => s_special_active,
            dec_move_en         => dec_move_en,
            dec_move_ready      => dec_move_ready,
            dec_alu_en          => dec_alu_en,
            s_alu_decoder_done  => s_alu_decoder_done,
            dec_branch_en       => dec_branch_en,
            dec_branch_ready    => dec_branch_ready,
            dec_special_en      => dec_special_en,
            dec_special_ready   => dec_special_ready,
            s_branch_pc_load    => s_branch_pc_load,
            s_branch_pc_new     => s_branch_pc_new,
            s_cache_inhibit_act => s_cache_inhibit_act,
            bus_cycle_done      => bus_cycle_done
        );

    i_trap_unit : cpu_030_ec_dec_trap_unit
        port map (
            CLK                 => CLK,
            RESET_N             => RESET_N,
            trap_en             => s_trap_en,
            trap_busy           => bus_busy,
            trap_done           => s_trap_done,
            exception_div_zero  => exception_div_zero,
            s_irq_latch         => s_sync_ipl_n, -- KORREKTUR: Stabilisierte Pipeline!
            internal_D_in       => internal_D_in,
            s_data_hold_latch   => open,
            internal_pc_out     => s_pc_trap,
            fsm_running_mode    => open,
            fsm_bus_req         => s_bus_req_trap,
            fsm_bus_write       => s_bus_w_trap,
            fsm_bus_addr        => s_bus_addr_trap,
            fsm_bus_type        => s_bus_type_trap,
            bus_cycle_done      => bus_cycle_done
        );

		      -- =====================================================================
    -- KOMBINAOTORISCHES BUS-MULTIPLEXING DER DREI TEIL-FSMS (0 % LATENZ)
    -- =====================================================================
    process(s_master_state, s_bus_req_boot, s_bus_w_boot, s_bus_addr_boot, s_bus_type_boot,
            s_bus_req_trap, s_bus_w_trap, s_bus_addr_trap, s_bus_type_trap)
    begin
        if s_master_state = 0 then
            s_fsm_bus_req   <= s_bus_req_boot;
            s_fsm_bus_write <= s_bus_w_boot;
            s_fsm_bus_addr  <= s_bus_addr_boot;
            s_fsm_bus_type  <= s_bus_type_boot;
        else
            s_fsm_bus_req   <= s_bus_req_trap;
            s_fsm_bus_write <= s_bus_w_trap;
            s_fsm_bus_addr  <= s_bus_addr_trap;
            s_fsm_bus_type  <= s_bus_type_trap;
        end if;
    end process;

    -- =====================================================================
    -- INSTANZIIERUNG DES WEICHENWERKS (OR-KOMPRIMIERTER STANDARD)
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
    -- SYNCHRONER KOORDINATIONS-PROZESS (MASTER STATE MACHINE)
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            s_master_state <= 0;
            s_boot_en      <= '1';
            s_exec_en      <= '0';
            s_trap_en      <= '0';
            s_sync_ipl_n   <= "111";
        elsif rising_edge(CLK) then
            -- Pipeline-Verrastung der Interrupt-Eingänge gegen metastabiles Rauschen
            s_sync_ipl_n <= ext_IPL_N;

            case s_master_state is
                when 0 =>
                    if s_boot_done = '1' then
                        s_boot_en      <= '0';
                        s_exec_en      <= '1';
                        s_master_state <= 1;
                    end if;
                when 1 =>
                    -- KORREKTUR: Unbestechliche, signal-synchronisierte Filter-Prüfung!
                    if exception_div_zero = '1' or s_sync_ipl_n /= "111" then
                        s_exec_en      <= '0';
                        s_trap_en      <= '1';
                        s_master_state <= 2;
                    end if;
                when 2 =>
                    if s_trap_done = '1' then
                        s_trap_en      <= '0';
                        s_exec_en      <= '1';
                        s_master_state <= 1;
                    end if;
            end case;
        end if;
    end process;

    -- =====================================================================
    -- LATCH-FREIE COMBINATORIAL FREEZE-WEICHE (STALL-STEUERUNG)
    -- =====================================================================
    process(bus_busy, s_master_state, cache_miss)
    begin
        pipeline_freeze <= '0';
        if (bus_busy = '1' and s_master_state = 1) or cache_miss = '1' then
            pipeline_freeze <= '1';
        end if;
    end process;

end behavioral;
