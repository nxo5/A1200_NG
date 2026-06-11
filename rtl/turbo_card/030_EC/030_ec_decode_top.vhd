-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_decode_top.vhd
-- Teil:    1 von 5 (Vollständige Entity-Schnittstelle)
-- Funktion: Die übergeordnete Instruction Control Unit (ICU-Wrapper).
--           FPGA-REFACORING (HEBEL 1): 
--           Kompression des internen Programmzählers auf 31 Bit (31 downto 1).
--           Eliminiert den massiven 32-Bit-Addierer aus der Carry-Chain,
--           ohne an Zyklustreue oder Funktion gegenüber der 030 zu verlieren!
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
        alu_opcode          : out   std_logic_vector(7 downto 0);   -- Bestimmt die ALU-Rechenoperation
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
    signal s_master_state       : integer range 0 to 2 := 0; -- 0=Boot, 1=Exec, 2=Trap
    signal s_internal_long      : std_logic_vector(31 downto 0) := (others => '0');

    -- OPTIMIERUNG HEBEL 1: carry-chain-schonender 31-Bit Programmzähler (Bit 0 gekappt)
    signal s_internal_pc        : unsigned(31 downto 1) := "0001111100000000000000000000000"; -- x"00F80000" shifted right 1

    -- Internes lacht-freies Freeze-Netzwerk
    signal pipeline_freeze      : std_logic := '0';

    -- Sub-Aktivierungssignale der Teil-Zustandsmaschinen
    signal s_boot_en            : std_logic := '1'; 
    signal s_boot_done          : std_logic;
    signal s_exec_en            : std_logic := '0';
    signal s_trap_en            : std_logic := '0'; 
    signal s_trap_done          : std_logic;

    -- Sub-PC-Rückführungen an die Master-Weiche (Ebenfalls auf 31 Bit optimiert)
    signal s_pc_boot            : unsigned(31 downto 1);
    signal s_pc_exec            : unsigned(31 downto 1);
    signal s_pc_trap            : unsigned(31 downto 1);

    -- Bus-Drahtbrücken von den neuen Sub-Modulen zum Weichenwerk
    signal s_bus_req_boot       : std_logic; 
    signal s_bus_w_boot         : std_logic;
    signal s_bus_addr_boot      : std_logic_vector(31 downto 0); 
    signal s_bus_type_boot      : std_logic_vector(2 downto 0);
    signal s_bus_req_trap       : std_logic; 
    signal s_bus_w_trap         : std_logic;
    signal s_bus_addr_trap      : std_logic_vector(31 downto 0); 
    signal s_bus_type_trap      : std_logic_vector(2 downto 0);

    -- Koordinierte Multiplexer-Busleitungen der FSM-Ebene
    signal s_fsm_running_mode   : std_logic := '0';
    signal s_fsm_bus_req        : std_logic := '0';
    signal s_fsm_bus_write      : std_logic := '0';
    signal s_fsm_bus_addr       : std_logic_vector(31 downto 0) := (others => '0');
    signal s_fsm_bus_data_out   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_fsm_bus_type       : std_logic_vector(2 downto 0) := (others => '0');

    -- Kombinatorische Aktivitäts-Meldungen für das Weichenwerk
    signal s_move_active        : std_logic := '0';
    signal s_alu_active         : std_logic := '0';
    signal s_bitfield_active    : std_logic := '0';
    signal s_special_active     : std_logic := '0';
    signal s_cache_inhibit_act  : std_logic := '0';

    -- Entflochtenes internes Signalnetzwerk der Teildecoder
    signal dec_move_en          : std_logic := '0'; 
    signal dec_move_ready       : std_logic;
    signal dec_alu_en           : std_logic := '0'; 
    signal dec_branch_en        : std_logic := '0'; 
    signal dec_branch_ready     : std_logic;
    signal dec_special_en       : std_logic := '0'; 
    signal dec_special_ready    : std_logic;
    signal s_alu_decoder_done   : std_logic := '0';
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

    -- Dummy-Leitungen für ungenutzte Ports der Sub-Decoder
    signal s_bus_req_spec       : std_logic;
    signal dummy_ea_start_m     : std_logic; 
    signal dummy_ea_start_a     : std_logic;
    signal dummy_ea_mode_m      : std_logic_vector(2 downto 0); 
    signal dummy_ea_mode_a      : std_logic_vector(2 downto 0);
    signal dummy_ea_reg_m       : std_logic_vector(2 downto 0); 
    signal dummy_ea_reg_a       : std_logic_vector(2 downto 0);

    -- =====================================================================
    -- COMPONENTEN-DEKLARATIONEN DER 3 NEUEN MASTER-SUBMODULE (31-BIT PC)
    -- =====================================================================
    component cpu_030_ec_dec_boot_fsm
        Port (
            CLK                 : in    std_logic; RESET_N : in std_logic;
            boot_en             : in    std_logic; boot_busy : in std_logic; boot_done : out std_logic;
            internal_pc_in      : in    unsigned(31 downto 1); internal_pc_out : out unsigned(31 downto 1);
            internal_D_in       : in    std_logic_vector(31 downto 0);
            fsm_bus_req         : out   std_logic; fsm_bus_write : out std_logic; fsm_bus_addr : out std_logic_vector(31 downto 0); fsm_bus_type : out std_logic_vector(2 downto 0);
            boot_ssp_load       : out   std_logic; boot_ssp_new : out std_logic_vector(31 downto 0);
            boot_pc_load        : out   std_logic; boot_pc_new : out std_logic_vector(31 downto 0)
        );
    end component;

    component cpu_030_ec_dec_exec_fsm
        Port (
            CLK                 : in    std_logic; RESET_N : in std_logic;
            exec_en             : in    std_logic; exec_busy : in std_logic; exec_irq_pending : in std_logic; exec_trap_pending : in std_logic; exec_trap_trigger : out std_logic;
            pipeline_word       : in    std_logic_vector(15 downto 0); pipeline_req : out std_logic; cache_cpu_req : out std_logic; cache_hit : in std_logic; cache_miss : in std_logic;
            internal_pc_in      : in    unsigned(31 downto 1); internal_pc_out : out unsigned(31 downto 1);
            s_fsm_running_mode  : out   std_logic; s_move_active : out std_logic; s_alu_active : out std_logic; s_special_active : out std_logic;
            dec_move_en         : out   std_logic; dec_move_ready : in std_logic; dec_alu_en : out std_logic; s_alu_decoder_done : in std_logic;
            dec_branch_en       : out   std_logic; dec_branch_ready : in std_logic; dec_special_en : out std_logic; dec_special_ready : in std_logic;
            s_branch_pc_load    : in    std_logic; s_branch_pc_new : in std_logic_vector(31 downto 0);
            s_cache_inhibit_act : out   std_logic; bus_cycle_done : in std_logic
        );
    end component;

    component cpu_030_ec_dec_trap_unit
        Port (
            CLK                 : in    std_logic; RESET_N : in std_logic;
            trap_en             : in    std_logic; trap_busy : in std_logic; trap_done : out std_logic;
            exception_div_zero  : in    std_logic; s_irq_latch : in std_logic_vector(2 downto 0);
            internal_D_in       : in    std_logic_vector(31 downto 0); s_data_hold_latch : out std_logic_vector(31 downto 0); internal_pc_out : out unsigned(31 downto 1);
            fsm_running_mode    : out   std_logic; fsm_bus_req : out std_logic; fsm_bus_write : out std_logic; fsm_bus_addr : out std_logic_vector(31 downto 0); fsm_bus_type : out std_logic_vector(2 downto 0);
            bus_cycle_done      : in    std_logic
        );
    end component;

    -- =====================================================================
    -- COMPONENTEN-DEKLARATIONEN IHRER FILIAL-DECODER UND DES WEICHENWERKS
    -- =====================================================================
    component cpu_030_ec_dec_move
        Port (
            CLK : in std_logic; RESET_N : in std_logic; move_en : in std_logic; opcode : in std_logic_vector(15 downto 0);
            ea_calc_start : out std_logic; ea_mode : out std_logic_vector(2 downto 0); ea_reg : out std_logic_vector(2 downto 0); ea_ready : in std_logic; ea_final_addr : in std_logic_vector(31 downto 0); ea_is_register  : in std_logic;
            move_size : out std_logic_vector(1 downto 0); move_bus_req : out std_logic; move_bus_write : out std_logic; move_alu_op : out std_logic_vector(7 downto 0); move_src_reg : out std_logic_vector(3 downto 0); move_dst_reg : out std_logic_vector(3 downto 0); move_ready : out std_logic
        );
    end component;

    component cpu_030_ec_dec_alu
        Port (
            CLK : in std_logic; RESET_N : in std_logic; alu_dec_en : in std_logic; opcode : in std_logic_vector(15 downto 0);
            ea_calc_start : out std_logic; ea_mode : out std_logic_vector(2 downto 0); ea_reg : out std_logic_vector(2 downto 0); ea_ready : in std_logic; ea_final_addr : in std_logic_vector(31 downto 0); ea_is_register  : in std_logic;
            dec_alu_size : out std_logic_vector(1 downto 0); dec_alu_bus_req : out   std_logic; dec_alu_bus_w : out std_logic; dec_alu_op : out std_logic_vector(7 downto 0); dec_alu_src_reg : out std_logic_vector(3 downto 0); dec_alu_dst_reg : out std_logic_vector(3 downto 0); dec_alu_ready : out std_logic
        );
    end component;

    component cpu_030_ec_dec_branch
        Port (
            CLK : in std_logic; RESET_N : in std_logic; branch_en : in std_logic; opcode : in std_logic_vector(15 downto 0); pc_current : in std_logic_vector(31 downto 0); alu_flags : in std_logic_vector(4 downto 0); pipeline_long : in std_logic_vector(31 downto 0);
            branch_pc_load : out std_logic; branch_pc_new : out std_logic_vector(31 downto 0); branch_ready : out std_logic
        );
    end component;

    component cpu_030_ec_dec_special
        Port (
            CLK : in std_logic; RESET_N : in std_logic; special_en : in std_logic; opcode : in std_logic_vector(15 downto 0); extension_word : in std_logic_vector(15 downto 0); supervisor_mode : in std_logic; exception_priv : out std_logic; reg_data_in : in std_logic_vector(31 downto 0); spec_bus_req : out std_logic;
            cacr_ei : out std_logic; cacr_fi : out std_logic; cacr_ed : out std_logic; cacr_fd : out std_logic; cacr_ci : out std_logic; cacr_cd : out std_logic; special_ready : out std_logic
        );
    end component;

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

    -- Sichere Vorab-Erdung des 32-Bit-Erweiterungsbusses für den Branch-Decoder
    s_internal_long <= x"0000" & pipeline_word;

    -- =====================================================================
    -- STRUKTURELLE VERDRAHTUNG DER ORIGINAL-DEC-BLÖCKE (0 % CO-TREIBER)
    -- =====================================================================
    i_dec_move : cpu_030_ec_dec_move
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            move_en         => dec_move_en,
            opcode          => s_fsm_bus_addr(15 downto 0),
            ea_calc_start   => dummy_ea_start_m,
            ea_mode         => dummy_ea_mode_m,
            ea_reg          => dummy_ea_reg_m,
            ea_ready        => '1',
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
            opcode          => s_fsm_bus_addr(15 downto 0),
            ea_calc_start   => dummy_ea_start_a,
            ea_mode         => dummy_ea_mode_a,
            ea_reg          => dummy_ea_reg_a,
            ea_ready        => '1',
            ea_final_addr   => (others => '0'),
            ea_is_register  => '1',
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
            opcode          => s_fsm_bus_addr(15 downto 0),
            -- 31-Bit PC wird kombinatorisch mit starrer Null an den 32-Bit-Port übergeben
            pc_current      => std_logic_vector(s_internal_pc) & '0',
            alu_flags       => alu_flags,
            pipeline_long   => s_internal_long,
            branch_pc_load  => s_branch_pc_load,
            branch_pc_new   => s_branch_pc_new,
            branch_ready    => dec_branch_ready
        );

    i_dec_special : cpu_030_ec_dec_special
        port map (
            CLK            => CLK,            
            RESET_N        => RESET_N,
            special_en     => dec_special_en, 
            opcode         => s_fsm_bus_addr(15 downto 0),
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
    -- INSTANZIIERUNG DES WEICHENWERKS (ALLEINIGE HAUPT-TREIBERHOHEIT)
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
            alu_op_bf           => x"00",         -- FIX: Auf namentliche Zuweisung saniert
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

    -- OPTIMIERUNG HEBEL 1: Der Cache-Adressbus speist sich aus dem 31-Bit-PC plus starrer Null
    cache_cpu_A   <= std_logic_vector(s_internal_pc) & '0';
    cache_is_code <= '1' when (s_master_state = 1) else '0';

    -- =====================================================================
    -- STRUKTURELLE VERDRAHTUNG DER DREI NEUEN MASTER-SUBMODULE (31-BIT PC)
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
            s_irq_latch         => ext_IPL_N,
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
    -- SYNCHRONER KOORDINATIONS-PROZESS (MASTER STATE MACHINE)
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            s_master_state <= 0;
            s_boot_en      <= '1';
            s_exec_en      <= '0';
            s_trap_en      <= '0';
            s_internal_pc  <= "0001111100000000000000000000000"; -- x"00F80000" shifted right 1
        elsif rising_edge(CLK) then
            case s_master_state is
                when 0 =>
                    s_internal_pc <= s_pc_boot;
                    if s_boot_done = '1' then
                        s_boot_en      <= '0';
                        s_exec_en      <= '1';
                        s_master_state <= 1;
                    end if;
                when 1 =>
                    s_internal_pc <= s_pc_exec;
                    if exception_div_zero = '1' or ext_IPL_N /= "111" then
                        s_exec_en      <= '0';
                        s_trap_en      <= '1';
                        s_master_state <= 2;
                    end if;
                when 2 =>
                    s_internal_pc <= s_pc_trap;
                    if s_trap_done = '1' then
                        s_trap_en      <= '0';
                        s_exec_en      <= '1';
                        s_master_state <= 1;
                    end if;
            end case;
        end if;
    end process;

    -- LATCH-FREIE COMBINATORIAL FREEZE-WEICHE
    process(bus_busy, s_master_state)
    begin
        pipeline_freeze <= '0';
        if bus_busy = '1' and s_master_state = 1 then
            pipeline_freeze <= '1';
        end if;
    end process;

end behavioral;
