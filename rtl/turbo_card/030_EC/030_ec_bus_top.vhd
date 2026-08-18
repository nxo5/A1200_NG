-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cpu_030_ec_bus.vhd
-- Teil:    1 von 2 (Entity und Komponentendeklarationen)
-- Funktion: Die übergeordnete Bus Interface Unit (BIU-Wrapper) des 68EC030.
--           Verdrahtet die Bus-FSM, den MUX und den separaten Daten-Sizer.
-- KORREKTUR FULL-FIX:
--   - Beseitigt den harten Treiberkonflikt (Error 13076) am internal_D_in.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_bus is
    Port (
        -- Globale Taktsignale
        CLK             : in    std_logic;
        RESET_N         : in    std_logic;

        -- Physikalische Signalaustritts-Pins nach außen zur Turbokarte
        ext_A           : out   std_logic_vector(31 downto 0);  
        ext_AS_N        : out   std_logic;
        ext_DS_N        : out   std_logic;
        ext_RW          : out   std_logic;
        ext_SIZ         : out   std_logic_vector(1 downto 0);
        ext_FC          : out   std_logic_vector(2 downto 0);
        ext_OCS_N       : out   std_logic;
        ext_ECS_N       : out   std_logic;
        ext_CIOUT_N     : out   std_logic;

        -- Physikalische Quittungs-Eingangspins von der Turbokarte / Chipsatz
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
        
        -- Die heraufgereichten Arbitrierungspins zur Außenhaut
        ext_BR_N        : in    std_logic;                      
        ext_BG_N        : out   std_logic;                      
        ext_BGACK_N     : in    std_logic;                      

        -- Physikalische Datenbus-Kopplungsdrähte
        ext_D_in_pins   : in    std_logic_vector(31 downto 0);  
        ext_D_out_pins  : out   std_logic_vector(31 downto 0);  

        -- Interne Signalbahnen zum Core (Decoder / Rechenwerk / Cache)
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

        -- Statussignale an das übergeordnete Steuerwerk
        bus_busy        : out   std_logic;                      
        cycle_done      : out   std_logic                       
    );
end cpu_030_ec_bus;

architecture structural of cpu_030_ec_bus is

    -- 1. Die erweiterte Bus-Zustandsmaschine (FSM)
    component cpu_030_ec_bus_fsm
        Port (
            CLK             : in    std_logic; RESET_N : in std_logic;
            cycle_start     : in    std_logic; cycle_write : in std_logic; cycle_rmw : in std_logic;
            ext_DSACK0_N    : in    std_logic; ext_DSACK1_N : in std_logic;
            ext_STERM_N     : in    std_logic; ext_BERR_N : in std_logic;
            ext_BR_N        : in    std_logic; ext_BG_N : out std_logic; ext_BGACK_N : in std_logic;
            ext_CBREQ_N     : out   std_logic; ext_CBACK_N : in std_logic; ext_RMC_N : out std_logic;
            fsm_busy        : out   std_logic; fsm_cycle_done : out std_logic;
            fsm_strobe_en   : out   std_logic; fsm_ds_en : out std_logic; fsm_write_en : out std_logic;
            fsm_tristate_en : out   std_logic; fsm_burst_cnt : out std_logic_vector(1 downto 0);
            fsm_sizing_offset : out std_logic_vector(1 downto 0)
        );
    end component;

    -- 2. Der erweiterte kombinatorische Bus-Multiplexer (MUX)
    component cpu_030_ec_bus_mux
        Port (
            fsm_tristate_en : in    std_logic; fsm_strobe_en : in std_logic; fsm_ds_en : in std_logic;
            fsm_write_en    : in    std_logic; fsm_burst_cnt : in std_logic_vector(1 downto 0);
            fsm_sizing_offset : in    std_logic_vector(1 downto 0); fsm_irq_level : in std_logic_vector(2 downto 0);
            internal_A      : in    std_logic_vector(31 downto 0); internal_D_out : in std_logic_vector(31 downto 0);
            cycle_size      : in    std_logic_vector(1 downto 0); cycle_type : in std_logic_vector(2 downto 0);
            ext_A           : out   std_logic_vector(31 downto 0); ext_D_out : out std_logic_vector(31 downto 0);
            ext_AS_N        : out   std_logic; ext_DS_N : out std_logic; ext_RW : out std_logic;
            ext_SIZ         : out   std_logic_vector(1 downto 0); ext_FC : out std_logic_vector(2 downto 0)
        );
    end component;

    -- 3. Das kombinatorische Daten-Sizing-Modul
    component cpu_030_ec_bus_sizer
        Port (
            fsm_sizing_offset   : in    std_logic_vector(1 downto 0);
            cycle_write         : in    std_logic;
            ext_dsack_width     : in    std_logic_vector(1 downto 0);
            core_D_out          : in    std_logic_vector(31 downto 0);
            core_D_in           : out   std_logic_vector(31 downto 0);
            ext_D_in_pins       : in    std_logic_vector(31 downto 0);
            ext_D_out_pins      : out   std_logic_vector(31 downto 0)
        );
    end component;

    -- Signalbündel der metastabilen Synchronisations-Pipeline
    signal dsack0_r1         : std_logic := '1'; signal dsack0_r2 : std_logic := '1';
    signal dsack1_r1         : std_logic := '1'; signal dsack1_r2 : std_logic := '1';
    signal ipl0_r1           : std_logic := '1'; signal ipl0_r2   : std_logic := '1';
    signal ipl1_r1           : std_logic := '1'; signal ipl1_r2   : std_logic := '1';
    signal ipl2_r1           : std_logic := '1'; signal ipl2_r2   : std_logic := '1';

    -- Interne Verbindungssignale
    signal strobe_aktiv     : std_logic;
    signal ds_aktiv         : std_logic; 
    signal richtung_schreib : std_logic;
    signal tristate_sperre  : std_logic;
    signal internal_A_pins  : std_logic_vector(31 downto 0);
    signal burst_zeiger     : std_logic_vector(1 downto 0);
    signal sizing_zeiger    : std_logic_vector(1 downto 0);
    signal dsack_width_sig  : std_logic_vector(1 downto 0);
    signal sizer_D_out_pins : std_logic_vector(31 downto 0);

	 begin

    -- =====================================================================
    -- HARDWARE-SICHERUNG SCHRITT 1: DIE METASTABILE 2-STUFIGE PIPELINE
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            dsack0_r1 <= '1'; dsack0_r2 <= '1';
            dsack1_r1 <= '1'; dsack1_r2 <= '1';
            ipl0_r1   <= '1'; ipl0_r2   <= '1';
            ipl1_r1   <= '1'; ipl1_r2   <= '1';
            ipl2_r1   <= '1'; ipl2_r2   <= '1';
        elsif rising_edge(CLK) then
            dsack0_r1 <= ext_DSACK0_N;
            dsack1_r1 <= ext_DSACK1_N;
            ipl0_r1   <= ext_IPL_N(0);
            ipl1_r1   <= ext_IPL_N(1);
            ipl2_r1   <= ext_IPL_N(2);

            dsack0_r2 <= dsack0_r1;
            dsack1_r2 <= dsack1_r1;
            ipl0_r2   <= ipl0_r1;
            ipl1_r2   <= ipl1_r1;
            ipl2_r2   <= ipl2_r1;
        end if;
    end process;

    sync_ipl_n <= ipl2_r2 & ipl1_r2 & ipl0_r2;

    -- =====================================================================
    -- LOGISCHES LEITUNGSNETZ MIT SYNCHRONISIERTEN QUITTUNGEN
    -- =====================================================================
    -- KORREKTUR FULL-FIX: Die starre Direktverbindung wurde gelöscht! [14.1]
    -- Verhindert den Fehler 13076, da internal_D_in nur vom Sizer geladen wird! [14.1]

    ext_OCS_N   <= '1'; 
    ext_ECS_N   <= '1'; 
    ext_CIOUT_N <= '1'; 

    ext_A <= internal_A_pins;

    dsack_width_sig <= dsack1_r2 & dsack0_r2;

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNG: DIE BUS-ZUSTANDSMASCHINE (FSM)
    -- =====================================================================
    i_bus_state_machine : cpu_030_ec_bus_fsm
        port map (
            CLK               => CLK,
            RESET_N           => RESET_N,
            cycle_start       => cycle_start,
            cycle_write       => cycle_write,
            cycle_rmw         => cycle_rmw,
            ext_DSACK0_N      => dsack0_r2,
            ext_DSACK1_N      => dsack1_r2,
            ext_STERM_N       => ext_STERM_N,
            ext_BERR_N        => ext_BERR_N,
            ext_BR_N          => ext_BR_N,
            ext_BG_N          => ext_BG_N,
            ext_BGACK_N       => ext_BGACK_N,
            ext_CBREQ_N       => ext_CBREQ_N,
            ext_CBACK_N       => ext_CBACK_N,
            ext_RMC_N         => ext_RMC_N,
            fsm_busy          => bus_busy,
            fsm_cycle_done    => cycle_done,
            fsm_strobe_en     => strobe_aktiv,
            fsm_ds_en         => ds_aktiv, 
            fsm_write_en      => richtung_schreib,
            fsm_tristate_en   => tristate_sperre,
            fsm_burst_cnt     => burst_zeiger,
            fsm_sizing_offset => sizing_zeiger
        );

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNG: DER BUS-MULTIPLEXER (MUX)
    -- =====================================================================
    i_bus_multiplexer : cpu_030_ec_bus_mux
        port map (
            fsm_tristate_en   => tristate_sperre,
            fsm_strobe_en     => strobe_aktiv,
            fsm_ds_en         => ds_aktiv, 
            fsm_write_en      => richtung_schreib,
            fsm_burst_cnt     => burst_zeiger,
            fsm_sizing_offset => sizing_zeiger,
            fsm_irq_level     => fsm_irq_level,
            internal_A        => internal_A,
            internal_D_out    => sizer_D_out_pins,
            cycle_size        => cycle_size,
            cycle_type        => cycle_type,
            ext_A             => internal_A_pins,
            ext_D_out         => ext_D_out_pins,
            ext_AS_N          => ext_AS_N,
            ext_DS_N          => ext_DS_N,
            ext_RW            => ext_RW,
            ext_SIZ           => ext_SIZ,
            ext_FC            => ext_FC
        );

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNG: DAS AUSGELAGERTE DATEN-SIZING-MODUL
    -- =====================================================================
    i_bus_sizer : cpu_030_ec_bus_sizer
        port map (
            fsm_sizing_offset => sizing_zeiger,
            cycle_write       => richtung_schreib,
            ext_dsack_width   => dsack_width_sig,
            core_D_out        => internal_D_out,
            core_D_in         => internal_D_in, -- Treibt nun exklusiv das innere Signal! [14.1]
            ext_D_in_pins     => ext_D_in_pins,
            ext_D_out_pins    => sizer_D_out_pins
        );

end structural;
