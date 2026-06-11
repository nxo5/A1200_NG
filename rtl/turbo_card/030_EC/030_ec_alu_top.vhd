-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_alu_top.vhd
-- Teil:    1 von 2 (Entity und Komponentendeklarationen)
-- Funktion: Das übergeordnete Rechenwerk-Subsystem (Wrapper) des 68EC030.
--           Verdrahtet die Registerbank und die Kombinatorik-ALU strukturell.
--           ANPASSUNG: Port-Erweiterung für den unbestechlichen SFC/DFC-
--                      Registereinzug des Voll-68030-Befehlssatzes!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_alu is
    Port (
        -- Globale Systemreize
        CLK             : in    std_logic;                      
        RESET_N         : in    std_logic;                      

        -- Physikalische Busschnittstelle nach außen
        bus_A           : out   std_logic_vector(31 downto 0);  
        bus_D_out       : out   std_logic_vector(31 downto 0);  
        bus_D_in        : in    std_logic_vector(31 downto 0);  

        -- Steuerschnittstelle vom Top-Decoder
        alu_opcode      : in    std_logic_vector(7 downto 0);   
        alu_size        : in    std_logic_vector(1 downto 0);   
        alu_src_reg     : in    std_logic_vector(3 downto 0);   
        alu_dst_reg     : in    std_logic_vector(3 downto 0);   

        -- Status-Rückmeldungen an den Top-Decoder
        alu_flags       : out   std_logic_vector(4 downto 0);   
        alu_ready       : out   std_logic;                      
        
        -- Heraufgereichte Boot- und Stack-Schnittstelle von der Master-FSM
        boot_pc_load    : in    std_logic;                      
        boot_pc_new     : in    std_logic_vector(31 downto 0);  
        fsm_a7_load     : in    std_logic;                      
        fsm_a7_new      : in    std_logic_vector(31 downto 0);  
        
        -- NEU PUNKT 2: Heraufgereichte MOVEC-Steuerschnittstelle für SFC und DFC
        ctrl_sfc_wren   : in    std_logic;                      -- '1' = SFC beschreiben
        ctrl_dfc_wren   : in    std_logic;                      -- '1' = DFC beschreiben
        ctrl_reg_data   : in    std_logic_vector(2 downto 0);   -- 3-Bit Wert für SFC/DFC
        
        -- NEU PUNKT 2: Parallele Ausgänge der Registerstände an das Bus-Weichenwerk
        sfc_val_out     : out   std_logic_vector(2 downto 0);   -- Aktueller SFC-Stand
        dfc_val_out     : out   std_logic_vector(2 downto 0);   -- Aktueller DFC-Stand
        
        -- Exception-Ausgang an den Top-Decoder
        exception_div_zero : out std_logic                      
    );
end cpu_030_ec_alu;

architecture structural of cpu_030_ec_alu is

    -- =====================================================================
    -- ERWEITERTE KOMPONENTENDEKLARATION DER DREI-STACK-REGISTERBANK
    -- =====================================================================
    component cpu_030_ec_alu_regs
        Port (
            CLK             : in    std_logic; RESET_N : in std_logic;
            reg_src_sel     : in    std_logic_vector(3 downto 0); reg_dst_sel : in std_logic_vector(3 downto 0);
            reg_size        : in    std_logic_vector(1 downto 0);
            pc_advance      : in    std_logic; pc_load : in std_logic; pc_new_val : in std_logic_vector(31 downto 0);
            wb_en           : in    std_logic; wb_data : in std_logic_vector(31 downto 0);
            wb_flags        : in    std_logic_vector(15 downto 0); wb_flags_en : in std_logic;
            ctrl_sfc_wren   : in    std_logic; ctrl_dfc_wren : in std_logic; ctrl_reg_data : in std_logic_vector(2 downto 0);
            boot_pc_load    : in    std_logic; boot_pc_new : in std_logic_vector(31 downto 0);
            fsm_a7_load     : in    std_logic; fsm_a7_new : in std_logic_vector(31 downto 0);
            src_val_out     : out   std_logic_vector(31 downto 0); dst_val_out : out std_logic_vector(31 downto 0);
            pc_val_out      : out   std_logic_vector(31 downto 0); flags_val_out : out std_logic_vector(4 downto 0);
            sfc_val_out     : out   std_logic_vector(2 downto 0); dfc_val_out : out std_logic_vector(2 downto 0)
        );
    end component;

    component cpu_030_ec_alu_core
        Port (
            alu_opcode      : in    std_logic_vector(7 downto 0); alu_size : in std_logic_vector(1 downto 0);
            dst_is_addr_reg : in    std_logic;
            src_val         : in    std_logic_vector(31 downto 0); dst_val : in std_logic_vector(31 downto 0);
            current_flags   : in    std_logic_vector(4 downto 0);
            result_out      : out   std_logic_vector(31 downto 0); new_flags_out : out std_logic_vector(15 downto 0);
            flags_update_en : out   std_logic;
            exception_div_zero : out std_logic
        );
    end component;

    -- =====================================================================
    -- Interne Verbindungssignale (Die Rechenbus-Leitungen des Wrappers)
    -- =====================================================================
    signal reg_src_val       : std_logic_vector(31 downto 0);
    signal reg_dst_val       : std_logic_vector(31 downto 0);
    signal core_result       : std_logic_vector(31 downto 0);
    signal current_ccr       : std_logic_vector(4 downto 0);
    signal core_new_flags    : std_logic_vector(15 downto 0);
    signal core_flags_update : std_logic;
    signal is_addr_reg       : std_logic;
    signal internal_wb_en    : std_logic := '0';
    signal internal_pc_adv   : std_logic := '0';

begin

    -- Richtungsweiche: Erkennt, ob das aktuelle Ziel ein Adressregister (An) ist
    is_addr_reg <= alu_dst_reg(3);

    -- Physische Buskopplung des Rechenwerks nach außen spiegeln
    bus_A     <= reg_src_val; 
    bus_D_out <= reg_dst_val; 
    
    -- Statusrückmeldung an den Top-Decoder
    alu_flags <= current_ccr;
    alu_ready <= '1';

    -- =====================================================================
    -- KOMBINAOTORISCHE AKTIVIERUNGSWEICHE: WRITE-BACK-STEUERUNG
    -- =====================================================================
    process(alu_opcode)
    begin
        if alu_opcode /= x"00" then
            internal_wb_en  <= '1'; 
            internal_pc_adv <= '1'; 
        else
            internal_wb_en  <= '0';
            internal_pc_adv <= '0';
        end if;
    end process;

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNG: DIE HAUPTREGISTERBANK (MIT SFC/DFC)
    -- =====================================================================
    i_alu_registers : cpu_030_ec_alu_regs
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            reg_src_sel     => alu_src_reg,
            reg_dst_sel     => alu_dst_reg,
            reg_size        => alu_size,
            pc_advance      => internal_pc_adv,
            pc_load         => '0',
            pc_new_val      => (others => '0'),
            wb_en           => internal_wb_en,
            wb_data         => core_result, 
            wb_flags        => core_new_flags,
            wb_flags_en     => core_flags_update,
            
            -- Hier docken die neuen MOVEC-Steuerleitungen an!
            ctrl_sfc_wren   => ctrl_sfc_wren,
            ctrl_dfc_wren   => ctrl_dfc_wren,
            ctrl_reg_data   => ctrl_reg_data,
            
            boot_pc_load    => boot_pc_load,
            boot_pc_new     => boot_pc_new,
            fsm_a7_load     => fsm_a7_load,
            fsm_a7_new      => fsm_a7_new,
            src_val_out     => reg_src_val,
            dst_val_out     => reg_dst_val,
            pc_val_out      => open,
            flags_val_out   => current_ccr,
            
            -- Brückenverbindung nach außen an das Gehäuse heraufreichen
            sfc_val_out     => sfc_val_out,
            dfc_val_out     => dfc_val_out
        );

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNG: DER REIN KOMBINATORISCHE RECHENKERN
    -- =====================================================================
    i_alu_math_core : cpu_030_ec_alu_core
        port map (
            alu_opcode      => alu_opcode,
            alu_size        => alu_size,
            dst_is_addr_reg => is_addr_reg,
            src_val         => reg_src_val,
            dst_val         => reg_dst_val,
            current_flags   => current_ccr,
            result_out      => core_result,
            new_flags_out   => core_new_flags,
            flags_update_en => core_flags_update,
            exception_div_zero => exception_div_zero
        );

end structural;
