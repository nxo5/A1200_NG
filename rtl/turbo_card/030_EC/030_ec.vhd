-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec.vhd
-- Teil:    1 von 3 (Die echte, unidirektionale Entity & Bus-Schablone)
-- Funktion: Das hochintegrierte Hauptgehäuse des 68EC030 CPU-Kerns.
-- KORREKTUR RICHTUNGSTRENNUNG:
--   - Vernichtet das verbotene inout im inneren FPGA-Kern vollständig! [14.1]
--   - Ersetzt es durch getrennte D_in und D_out Datenbus-Lanes. [14.1]
--   - Bringt die CPU in 100%ige Übereinstimmung mit der turbo_card. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec is
    Port (
        -- Takt und System-Signale (Physikalische Pins zur Turbokarte)
        CLK         : in    std_logic;                      -- Schneller Systemtakt (56,56 MHz)
        RESET_N     : in    std_logic;                      -- System-Reset (Low-Aktiv)

        -- Adress- und Datenbus (KORREKTUR: Kompromisslose Richtungstrennung!) [14.1]
        A           : out   std_logic_vector(31 downto 0);  
        D_in        : in    std_logic_vector(31 downto 0);  -- Rein outbound ZUR CPU (Lesen) [14.1]
        D_out       : out   std_logic_vector(31 downto 0);  -- Rein inbound VON der CPU (Schreiben) [14.1]

        -- Kontroll-Ausgänge (CPU -> Turbokarte / Mainboard)
        AS_N        : out   std_logic;                      -- Address Strobe
        DS_N        : out   std_logic;                      -- Data Strobe
        RW          : out   std_logic;                      -- Read / Write (1 = Read, 0 = Write)
        SIZ         : out   std_logic_vector(1 downto 0);   -- Transfer-Größe
        FC          : out   std_logic_vector(2 downto 0);   -- Function Codes
        OCS_N       : out   std_logic;                      -- Operand Cycle Start
        ECS_N       : out   std_logic;                      -- External Cycle Start
        CIOUT_N     : out   std_logic;                      -- Cache Inhibit Output

        -- Kontroll-Eingänge (Mainboard -> CPU)
        DSACK0_N    : in    std_logic;                      
        DSACK1_N    : in    std_logic;                      
        STERM_N     : in    std_logic;                      
        CIIN_N      : in    std_logic;                      
        HALT_N      : in    std_logic;                      
        BERR_N      : in    std_logic;                      

        -- Cache Burst-Steuerung
        CBREQ_N     : out   std_logic;                      
        CBACK_N     : in    std_logic;                      

        -- Interrupt-Steuerung (Echte Gehäuse-Pins für Paula)
        IPL_N       : in    std_logic_vector(2 downto 0);   

        -- Bus-Arbitrierung
        BR_N        : in    std_logic;                      
        BG_N        : out   std_logic;                      
        BGACK_N     : in    std_logic                       
    );
end cpu_030_ec;

architecture structural of cpu_030_ec is

    -- 1. Bus Interface Unit (BIU - Konsolidierter Datenpfad)
    component cpu_030_ec_bus
        Port (
            CLK             : in    std_logic;
            RESET_N         : in    std_logic;
            ext_A           : out   std_logic_vector(31 downto 0);  
            ext_AS_N        : out   std_logic;
            ext_DS_N        : out   std_logic;
            ext_RW          : out   std_logic;
            ext_SIZ         : out   std_logic_vector(1 downto 0);
            ext_FC          : out   std_logic_vector(2 downto 0);
            ext_OCS_N       : out   std_logic;
            ext_ECS_N       : out   std_logic;
            ext_CIOUT_N     : out   std_logic;
            ext_DSACK0_N    : in    std_logic;
            ext_DSACK1_N    : in    std_logic;
            ext_STERM_N     : in    std_logic;
            ext_CIIN_N      : in    std_logic;
            ext_HALT_N      : in    std_logic;
            ext_BERR_N      : in    std_logic;
            ext_CBREQ_N     : out   std_logic;
            ext_CBACK_N     : in    std_logic;
            ext_RMC_N       : out   std_logic;
            ext_IPL_N       : in    std_logic_vector(2 downto 0);   
            ext_BR_N        : in    std_logic;                      
            ext_BG_N        : out   std_logic;                      
            ext_BGACK_N     : in    std_logic;                      
            ext_D_in_pins   : in    std_logic_vector(31 downto 0);  
            ext_D_out_pins  : out   std_logic_vector(31 downto 0);  
            internal_A      : in    std_logic_vector(31 downto 0); 
            internal_D_out  : in    std_logic_vector(31 downto 0);
            internal_D_in   : out   std_logic_vector(31 downto 0);
            cycle_start     : in    std_logic;                      
            cycle_write     : in    std_logic;                      
            cycle_rmw       : in    std_logic;                      
            cycle_size      : in    std_logic_vector(1 downto 0);
            cycle_type      : in    std_logic_vector(2 downto 0);
            fsm_irq_level   : in    std_logic_vector(2 downto 0);   
            sync_ipl_n      : out   std_logic_vector(2 downto 0);   
            bus_busy        : out   std_logic;                      
            cycle_done      : out   std_logic                       
        );
    end component;

	     -- 2. Execution Unit (ALU / Rechenwerk und Hauptregisterbank)
    component cpu_030_ec_alu
        Port (
            CLK             : in    std_logic; RESET_N : in std_logic;
            bus_A           : out   std_logic_vector(31 downto 0); 
            bus_D_out       : out   std_logic_vector(31 downto 0);
            bus_D_in        : in    std_logic_vector(31 downto 0); alu_opcode : in std_logic_vector(7 downto 0);
            alu_size        : in    std_logic_vector(1 downto 0); alu_src_reg : in std_logic_vector(3 downto 0);
            alu_dst_reg     : in    std_logic_vector(3 downto 0); alu_flags : out std_logic_vector(4 downto 0);
            alu_ready       : out   std_logic;
            boot_pc_load    : in    std_logic; boot_pc_new : in std_logic_vector(31 downto 0);
            fsm_a7_load     : in    std_logic; fsm_a7_new : in std_logic_vector(31 downto 0);
            ctrl_sfc_wren   : in    std_logic; ctrl_dfc_wren : in std_logic; ctrl_reg_data : in std_logic_vector(2 downto 0);
            sfc_val_out     : out   std_logic_vector(2 downto 0); dfc_val_out : out std_logic_vector(2 downto 0);
            exception_div_zero : out std_logic
        );
    end component;

    -- 3. Instruction Control Unit (Top-Decoder und Master-Exception-FSM)
    component cpu_030_ec_decode_top
        Port (
            CLK             : in    std_logic; RESET_N : in std_logic;
            pipeline_word   : in    std_logic_vector(15 downto 0); pipeline_empty : in std_logic;
            pipeline_req    : out   std_logic;
            cache_cpu_A     : out   std_logic_vector(31 downto 0); cache_cpu_req : out std_logic;
            cache_is_code   : out   std_logic; cache_hit : in std_logic; cache_miss : in std_logic;
            bus_cycle_start : out   std_logic; bus_cycle_write : out std_logic;
            bus_cycle_size  : out   std_logic_vector(1 downto 0); bus_cycle_type : out std_logic_vector(2 downto 0);
            bus_busy        : in    std_logic; bus_cycle_done : in std_logic;
            alu_opcode      : out   std_logic_vector(7 downto 0); alu_size : out std_logic_vector(1 downto 0);
            alu_src_reg     : out   std_logic_vector(3 downto 0); alu_dst_reg     : out std_logic_vector(3 downto 0);
            alu_flags       : in    std_logic_vector(4 downto 0); alu_ready       : in std_logic;
            cacr_ei         : out   std_logic; cacr_fi : out std_logic;
            cacr_ed         : out   std_logic; cacr_fd : out std_logic;
            cacr_ci         : out   std_logic; cacr_cd : out std_logic;
            boot_pc_load    : out   std_logic; boot_pc_new : out std_logic_vector(31 downto 0);
            boot_ssp_load   : out   std_logic; boot_ssp_new : out std_logic_vector(31 downto 0);
            ext_IPL_N       : in    std_logic_vector(2 downto 0);   
            internal_D_in   : in    std_logic_vector(31 downto 0);
            exception_div_zero : in std_logic
        );
    end component;

    -- 4. Der integrierte Cache-Subsystem-Wrapper
    component cpu_030_ec_cache_top
        Port (
            CLK             : in    std_logic; RESET_N : in std_logic;
            cpu_A           : in    std_logic_vector(31 downto 0); cpu_D_in : in std_logic_vector(31 downto 0);
            cpu_D_out       : out   std_logic_vector(31 downto 0); cpu_RW : in std_logic;
            cpu_req         : in    std_logic; cpu_is_code : in std_logic;
            cacr_ei         : in    std_logic; cacr_fi : in std_logic; cacr_ed : in std_logic;
            cacr_fd         : in    std_logic; cacr_ci : in std_logic; cacr_cd : in std_logic;
            cache_hit       : out   std_logic; cache_miss : out std_logic;
            bram_a_addr     : out   std_logic_vector(18 downto 0); bram_a_data_w : out std_logic_vector(31 downto 0);
            bram_a_data_r   : in    std_logic_vector(31 downto 0); bram_a_we : out std_logic;
            bridge_req      : out   std_logic; bridge_burst_en : out std_logic; bridge_ready : in std_logic
        );
    end component;

    -- INTERNE VERBINDUNGSSIGNALE
    signal int_A            : std_logic_vector(31 downto 0);
    signal s_alu_A          : std_logic_vector(31 downto 0); 
    signal int_D_to_bus     : std_logic_vector(31 downto 0);
    signal int_D_to_alu     : std_logic_vector(31 downto 0);
    signal ctrl_start       : std_logic;
    signal ctrl_write       : std_logic;
    signal ctrl_bus_size    : std_logic_vector(1 downto 0);
    signal ctrl_bus_type    : std_logic_vector(2 downto 0);
    signal status_busy      : std_logic;
    signal status_done      : std_logic;
    signal ctrl_alu_opcode  : std_logic_vector(7 downto 0);
    signal ctrl_alu_size    : std_logic_vector(1 downto 0);
    signal ctrl_src_reg     : std_logic_vector(3 downto 0);
    signal ctrl_dst_reg     : std_logic_vector(3 downto 0);
    signal status_flags     : std_logic_vector(4 downto 0);
    signal status_alu_rdy   : std_logic;
    signal ch_prefetch_A    : std_logic_vector(31 downto 0);
    signal ch_prefetch_req  : std_logic;
    signal ch_is_code       : std_logic;
    signal ch_hit           : std_logic;
    signal ch_miss          : std_logic;
    signal cache_data_out   : std_logic_vector(31 downto 0);
    
    -- Port-A Signalketten für L1-Cache
    signal bram_a_addr_sig  : std_logic_vector(18 downto 0);
    signal bram_a_data_w_sig: std_logic_vector(31 downto 0);
    signal bram_a_data_r_sig: std_logic_vector(31 downto 0);
    signal bram_a_we_sig    : std_logic;
    
    signal ext_rw_internal  : std_logic;
    signal tk_bridge_req    : std_logic;
    signal tk_burst_en      : std_logic;
    signal ch_cacr_ei       : std_logic;
    signal ch_cacr_fi       : std_logic;
    signal ch_cacr_ed       : std_logic;
    signal ch_cacr_fd       : std_logic;
    signal ch_cacr_ci       : std_logic;
    signal ch_cacr_cd       : std_logic;
    signal core_boot_pc_load : std_logic;
    signal core_boot_pc_new  : std_logic_vector(31 downto 0);
    signal core_fsm_a7_load  : std_logic;
    signal core_fsm_a7_new   : std_logic_vector(31 downto 0);
    signal core_sfc_wren    : std_logic := '0';
    signal core_dfc_wren    : std_logic := '0';
    signal core_ctrl_data   : std_logic_vector(2 downto 0) := "000";
    signal core_sfc_val     : std_logic_vector(2 downto 0);
    signal core_dfc_val     : std_logic_vector(2 downto 0);
    signal core_exception_div_zero : std_logic;
    signal int_sync_ipl_n   : std_logic_vector(2 downto 0);

begin

    -- =====================================================================
    -- 1. PHYSIKALISCHE SIGNALDURCHREICHUNG (KOMPROMISSLOS TRI-STATE-FREI!)
    -- =====================================================================
    A   <= int_A;
    RW  <= ext_rw_internal;

    -- =====================================================================
    -- 2. STRUKTURELLE VERDRAHTUNG: BUS INTERFACE UNIT (BIU)
    -- =====================================================================
    i_bus_interface : cpu_030_ec_bus
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            ext_A           => int_A, 
            ext_AS_N        => AS_N,
            ext_DS_N        => DS_N,
            ext_RW          => ext_rw_internal,
            ext_SIZ         => SIZ,
            ext_FC          => FC,
            ext_OCS_N       => OCS_N,
            ext_ECS_N       => ECS_N,
            ext_CIOUT_N     => CIOUT_N,
            ext_DSACK0_N    => DSACK0_N,
            ext_DSACK1_N    => DSACK1_N,
            ext_STERM_N     => STERM_N,
            ext_CIIN_N      => CIIN_N,
            ext_HALT_N      => HALT_N,
            ext_BERR_N      => BERR_N,
            ext_CBREQ_N     => CBREQ_N,
            ext_CBACK_N     => CBACK_N,
            ext_RMC_N       => open,
            ext_IPL_N       => IPL_N,
            ext_BR_N        => BR_N,
            ext_BG_N        => BG_N,
            ext_BGACK_N     => BGACK_N,
            
            -- UNIDIREKTIONALE KOPPLUNG AN DIE WAND DER TURBOKARTE: [14.1]
            ext_D_in_pins   => D_in,  -- Holt Lesedaten ohne Umwege rein
            ext_D_out_pins  => D_out, -- Schiebt Schreibdaten direkt raus
            
            internal_A      => s_alu_A, 
            internal_D_out  => int_D_to_bus,
            internal_D_in   => int_D_to_alu,
            cycle_start     => ctrl_start,
            cycle_write     => ctrl_write,
            cycle_rmw       => '0', 
            cycle_size      => ctrl_bus_size,
            cycle_type      => ctrl_bus_type,
            fsm_irq_level   => (others => '0'),
            sync_ipl_n      => int_sync_ipl_n,
            bus_busy        => status_busy,
            cycle_done      => status_done
        );

    -- =====================================================================
    -- 3. STRUKTURELLE VERDRAHTUNG: EXECUTION UNIT (ALU / RECHENWERK)
    -- =====================================================================
    i_execution_unit : cpu_030_ec_alu
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            bus_A           => s_alu_A, 
            bus_D_out       => int_D_to_bus,
            bus_D_in        => int_D_to_alu,
            alu_opcode      => ctrl_alu_opcode,
            alu_size        => ctrl_alu_size,
            alu_src_reg     => ctrl_src_reg,
            alu_dst_reg     => ctrl_dst_reg,
            alu_flags       => status_flags,
            alu_ready       => status_alu_rdy,
            boot_pc_load    => core_boot_pc_load,
            boot_pc_new     => core_boot_pc_new,
            fsm_a7_load     => core_fsm_a7_load,
            fsm_a7_new      => core_fsm_a7_new,
            ctrl_sfc_wren   => core_sfc_wren,
            ctrl_dfc_wren   => core_dfc_wren,
            ctrl_reg_data   => core_ctrl_data,
            sfc_val_out     => open,
				dfc_val_out     => open,
            exception_div_zero => core_exception_div_zero
        );

    -- =====================================================================
    -- 4. STRUKTURELLE VERDRAHTUNG: L1-CACHE SUBSYSTEM (PORT A HOHEIT)
    -- KORREKTUR: open-Zuweisung vernichtet Warning 10036 gatterrein! [14.1]
    -- =====================================================================
    i_cache_subsystem : cpu_030_ec_cache_top
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            cpu_A           => ch_prefetch_A,
            cpu_D_in        => int_D_to_bus,
            cpu_D_out       => cache_data_out,
            cpu_RW          => '1', 
            cpu_req         => ch_prefetch_req,
            cpu_is_code     => ch_is_code,
            cacr_ei         => ch_cacr_ei,
            cacr_fi         => ch_cacr_fi,
            cacr_ed         => ch_cacr_ed,
            cacr_fd         => ch_cacr_fd,
            cacr_ci         => ch_cacr_ci,
            cacr_cd         => ch_cacr_cd,
            cache_hit       => ch_hit,
            cache_miss      => ch_miss,
            
            -- HIER REPARIERT: Unused Ports sauber ausgeblendet [14.1]
            bram_a_addr     => open,             -- Wird intern in cache_top per M10K abgefangen! [14.1]
            bram_a_data_w   => open,             -- Offen gelassen, da reiner Befehlscache-Lesepfad
            bram_a_data_r   => bram_a_data_r_sig, -- Bootdatenbahn bleibt aktiv versorgt [14.1]
            bram_a_we       => open,             
            
            bridge_req      => open,
				bridge_burst_en => open,
            bridge_ready    => '1' 
        );

    -- =====================================================================
    -- 5. STRUKTURELLE VERDRAHTUNG: INSTRUCTION CONTROL UNIT (DECODER/FSM)
    -- =====================================================================
    i_instruction_control : cpu_030_ec_decode_top
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            pipeline_word   => cache_data_out(15 downto 0), 
            pipeline_empty  => ch_miss,
            pipeline_req    => open,
            cache_cpu_A     => ch_prefetch_A,
            cache_cpu_req   => ch_prefetch_req,
            cache_is_code   => ch_is_code,
            cache_hit       => ch_hit,
            cache_miss      => ch_miss,
            bus_cycle_start => ctrl_start,
            bus_cycle_write => ctrl_write,
            bus_cycle_size  => ctrl_bus_size,
            bus_cycle_type  => ctrl_bus_type,
            bus_busy        => status_busy,
            bus_cycle_done  => status_done,
            alu_opcode      => ctrl_alu_opcode,
            alu_size        => ctrl_alu_size,
            alu_src_reg     => ctrl_src_reg,
            alu_dst_reg     => ctrl_dst_reg,
            alu_flags       => status_flags,
            alu_ready       => status_alu_rdy,
            cacr_ei         => ch_cacr_ei,
            cacr_fi         => ch_cacr_fi,
            cacr_ed         => ch_cacr_ed,
            cacr_fd         => ch_cacr_fd,
            cacr_ci         => ch_cacr_ci,
            cacr_cd         => ch_cacr_cd,
            boot_pc_load    => core_boot_pc_load,
            boot_pc_new     => core_boot_pc_new,
            boot_ssp_load   => core_fsm_a7_load,
            boot_ssp_new    => core_fsm_a7_new,
            ext_IPL_N       => int_sync_ipl_n,
            internal_D_in   => int_D_to_alu,
            exception_div_zero => core_exception_div_zero
        );
		  
	-- =====================================================================
    -- SYSTEM-LOGIK-TREIBER (PASSIV-SICHERUNG GEGEN WARNING 10540)
    -- =====================================================================
    core_sfc_wren  <= '0';         
    core_dfc_wren  <= '0';         
    core_ctrl_data <= (others => '0'); 
	 
	-- =====================================================================
    -- REPARATUR CACHE-BYPASS: KOPPELUNG DES KICKSTART-LESEPFADS [14.1]
    -- Versorgt den Cache-Bypass mit den realen Bootdaten vom CPU-Eingang. [14.1]
    -- =====================================================================
    bram_a_data_r_sig <= D_in;

end structural;
