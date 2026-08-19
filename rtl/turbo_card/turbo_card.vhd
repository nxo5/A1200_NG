-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_card.vhd
-- Teil:    1 von 2 (Entity & Komponenten)
-- Funktion: Das übergeordnete Platinen-Gehäuse (Top-Level der Turbokarte).
-- SANIERUNG: REIN UNIDIREKTIONALER PORT-ABGLEICH (0 ERRORS)
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity turbo_card is
    Port (
        -- Takteingang von Alice und globaler Reset vom Mainboard
        CLK_14M         : in    std_logic;                      
        i_reset_high    : in    std_logic;                      

        -- Schnittstelle zum Amiga-Mainboard-Bus (Unidirektionale logische Richtungen)
        A               : out   std_logic_vector(31 downto 0);  
        D_in            : in    std_logic_vector(31 downto 0);  -- Reiner EINGANG zur Turbokarte
        D_out           : out   std_logic_vector(31 downto 0);  -- Reiner AUSGANG von der Turbokarte

        -- Kontrollsignale zum Mainboard (Spiegelung des CPU-Busses)
        AS_N            : out   std_logic;                      
        DS_N            : out   std_logic;                      
        RW              : out   std_logic;                      
        SIZ             : out   std_logic_vector(1 downto 0);   
        FC              : out   std_logic_vector(2 downto 0);   

        -- Rückmeldungen vom Mainboard-Chipsatz und Paula-Interrupts
        DSACK0_N        : in    std_logic;                      
        DSACK1_N        : in    std_logic;                      
        IPL_N           : in    std_logic_vector(2 downto 0)    
    );
end turbo_card;

architecture structural of turbo_card is

    component cpu_030_ec is
        Port (
            CLK         : in    std_logic;
            RESET_N     : in    std_logic;
            A           : out   std_logic_vector(31 downto 0);
            D_in        : in    std_logic_vector(31 downto 0); 
            D_out       : out   std_logic_vector(31 downto 0); 
            AS_N        : out   std_logic;
            DS_N        : out   std_logic;
            RW          : out   std_logic;
            SIZ         : out   std_logic_vector(1 downto 0);
            FC          : out   std_logic_vector(2 downto 0); 
            OCS_N       : out   std_logic;
            ECS_N       : out   std_logic;
            CIOUT_N     : out   std_logic;
            DSACK0_N    : in    std_logic;
            DSACK1_N    : in    std_logic;
            STERM_N     : in    std_logic;
            CIIN_N      : in    std_logic;
            HALT_N      : in    std_logic;
            BERR_N      : in    std_logic;
            CBREQ_N     : out   std_logic;
            CBACK_N     : in    std_logic;
            IPL_N       : in    std_logic_vector(2 downto 2); 
            IPL_N_v     : in    std_logic_vector(2 downto 0);                    
            BR_N        : in    std_logic;
            BG_N        : out   std_logic;
            BGACK_N     : in    std_logic
        );
    end component;

    component turbo_clk is
        Port (
            clk_in_14m  : in    std_logic;                      
            clk_out_56m : out   std_logic                       
        );
    end component;

    signal local_cpu_clk   : std_logic;                     
    signal local_addr      : std_logic_vector(31 downto 0);
    signal local_as_n      : std_logic;
    signal local_ds_n      : std_logic;
    signal local_rw        : std_logic;
    signal local_siz       : std_logic_vector(1 downto 0);
    signal local_fc        : std_logic_vector(2 downto 0);
    signal s_cpu_reset_n   : std_logic;

	 begin

    -- =====================================================================
    -- 0. HARDWARE RESET SPIEGELUNG (INVERTIERUNGS-GATTER)
    -- =====================================================================
    s_cpu_reset_n <= not i_reset_high;

    -- =====================================================================
    -- 1. PHYSIKALISCHE SIGNALDURCHREICHUNG ZUM AMIGA-MAINBOARD
    -- =====================================================================
    A    <= local_addr;
    AS_N <= local_as_n;
    DS_N <= local_ds_n;
    RW   <= local_rw;
    SIZ  <= local_siz;
    FC   <= local_fc;

    -- =====================================================================
    -- 2. INSTANZIIERUNG: LOKALER TAKT-MANAGER (Alice zu 56-MHz-Uhrwerk)
    -- =====================================================================
    i_turbo_clk : turbo_clk
        port map (
            clk_in_14m  => CLK_14M,         
            clk_out_56m => local_cpu_clk    
        );

    -- =====================================================================
    -- 3. INSTANZIIERUNG: DER SANIERTEN 68EC030 CPU-KERN
    -- REPARIERT: Richtungsgetreue Bus-Zuweisung löscht den In-Kanal-Fehler! [14.1]
    -- =====================================================================
    i_cpu_core : cpu_030_ec
        port map (
            CLK         => local_cpu_clk,   
            RESET_N     => s_cpu_reset_n,   
            A           => local_addr,      
            
            -- KORREKTUR: Die Signale liegen nun absolut richtungsgetreu an! [14.1]
            D_in        => D_in,            -- Platinen-Eingang treibt den CPU-Eingang
            D_out       => D_out,           -- CPU-Ausgang treibt den Platinen-Ausgang
            
            AS_N        => local_as_n,
            DS_N        => local_ds_n,
            RW          => local_rw,
            SIZ         => local_siz,
            FC          => local_fc,
            OCS_N       => open,            
            ECS_N       => open,
            CIOUT_N     => open,
            DSACK0_N    => DSACK0_N,        
            DSACK1_N    => DSACK1_N,
            STERM_N     => '1',             
            CIIN_N      => '1',             
            HALT_N      => '1',             
            BERR_N      => '1',             
            CBREQ_N     => open,
            CBACK_N     => '1',             
            IPL_N       => "1",             -- Geister-Interrupt-Sperre fest verriegelt
            IPL_N_v     => IPL_N,           -- Realer Interrupt-Vektor von der Außenwelt
            BR_N        => '1',             
            BG_N        => open,
            BGACK_N     => '1'
        );

end structural;
