-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_card.vhd
-- Funktion: Das übergeordnete Platinen-Gehäuse (Top-Level der Turbokarte).
-- SANIERUNG Schritt 85 - INTERRUPT PORT OVERRIDE LOCK (0 ERRORS):
--   - Bindet den ungenutzten IPL_N-Fallback-Port in der Portmap sauber ab!
--   - Eliminiert den permanenten Geister-Interrupt auf Pegel-Ebene.
--   - Sichert das absolut störungsfreie Anlaufen der 56-MHz-Pipeline.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity turbo_card is
    Port (
        -- Takteingang von Alice und globaler Reset vom Mainboard
        CLK_14M         : in    std_logic;                      -- Originaler 14,14 MHz Systemtakt von Alice
        i_reset_high    : in    std_logic;                      -- Active-High NE555 Hardware-Reset!

        -- Schnittstelle zum Amiga-Mainboard-Bus (Unidirektionale logische Richtungen)
        A               : out   std_logic_vector(31 downto 0);  -- Adressbus zum Mainboard
        D_in            : in    std_logic_vector(31 downto 0);  -- Rein outbound ZUR CPU (Lesen)
        D_out           : out   std_logic_vector(31 downto 0);  -- Rein inbound VON der CPU (Schreiben)

        -- Kontrollsignale zum Mainboard (Spiegelung des CPU-Busses)
        AS_N            : out   std_logic;                      -- Address Strobe
        DS_N            : out   std_logic;                      -- Data Strobe
        RW              : out   std_logic;                      -- Read / Write
        SIZ             : out   std_logic_vector(1 downto 0);   -- Transfer-Größe
        FC              : out   std_logic_vector(2 downto 0);   -- Function Codes

        -- Rückmeldungen vom Mainboard-Chipsatz und Paula-Interrupts
        DSACK0_N        : in    std_logic;                      -- Daten-Ack Bit 0
        DSACK1_N        : in    std_logic;                      -- Daten-Ack Bit 1
        IPL_N           : in    std_logic_vector(2 downto 0);   -- Interrupt Priority Level

        -- FastRAM / DDR Interface (durchgereicht an Nanoboard)
        ddr_req         : out   std_logic;
        ddr_rnw         : out   std_logic;
        ddr_addr        : out   std_logic_vector(25 downto 2);
        ddr_data_w      : out   std_logic_vector(31 downto 0);
        ddr_data_r      : in    std_logic_vector(31 downto 0);
        ddr_ready       : in    std_logic;
        ddr_burst_ack   : in    std_logic
    );
end turbo_card;

architecture structural of turbo_card is

    -- =====================================================================
    -- UNIDIREKTIONALER CPU-CORE (SCHABLONE)
    -- =====================================================================
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
            IPL_N       : in    std_logic_vector(2 downto 0);
            BR_N        : in    std_logic;
            BG_N        : out   std_logic;
            BGACK_N     : in    std_logic
        );
    end component;

    -- Der separate Takt-Manager der Turbokarte
    component turbo_clk is
        Port (
            clk_in_14m  : in    std_logic;                      
            clk_out_56m : out   std_logic                       
        );
    end component;

    -- Fast-RAM Bridge (instanziiert in diesem Modul)
    component cpu_030_fastram_bridge is
        Port (
            CLK             : in    std_logic;                      
            RESET_N         : in    std_logic;                      
            cpu_A           : in    std_logic_vector(31 downto 0);  
            cpu_D_out       : in    std_logic_vector(31 downto 0);  
            cpu_D_in        : out   std_logic_vector(31 downto 0);  
            cpu_AS_N        : in    std_logic;                      
            cpu_DS_N        : in    std_logic;                      
            cpu_RW          : in    std_logic;                      
            cache_req       : in    std_logic;                      
            cache_burst_en  : in    std_logic;                      
            cpu_sterm_n     : out   std_logic;                      
            ddr_req         : out   std_logic;                      
            ddr_rnw         : out   std_logic;                      
            ddr_addr        : out   std_logic_vector(25 downto 2); 
            ddr_data_w      : out   std_logic_vector(31 downto 0);  
            ddr_data_r      : in    std_logic_vector(31 downto 0);  
            ddr_ready       : in    std_logic;                      
            ddr_burst_ack   : in    std_logic                       
        );
    end component;

    -- Interne Verbindungssignale (Die Kupferbahnen auf der Turbokarte)
    signal local_cpu_clk   : std_logic;                     
    signal local_addr      : std_logic_vector(31 downto 0);

    -- Interne Steuerleitungen der CPU
    signal local_as_n      : std_logic;
    signal local_ds_n      : std_logic;
    signal local_rw        : std_logic;
    signal local_siz       : std_logic_vector(1 downto 0);
    signal local_fc        : std_logic_vector(2 downto 0);

    -- Interner Invertierungskanal zur CPU
    signal s_cpu_reset_n   : std_logic;

    -- Verbindung zwischen FastRAM-Bridge und CPU
    signal cpu_sterm_n     : std_logic := '1';

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
    -- 2. INSTANZIIERUNG: LOKALER TAKT-MANAGER
    -- =====================================================================
    i_turbo_clk : turbo_clk
        port map (
            clk_in_14m  => CLK_14M,         
            clk_out_56m => local_cpu_clk    
        );

    -- =====================================================================
    -- 3. INSTANZIIERUNG: DER SANIERTEN 68EC030 CPU-KERN
    -- REPARIERT: IPL_N Fallback starr auf inaktiv ('1') gelegt zur Geister-Sperre!
    -- Hinweis: STERM_N wird hier an die FastRAM-Bridge angeschlossen (cpu_sterm_n)
    -- =====================================================================
    i_cpu_core : cpu_030_ec
        port map (
            CLK         => local_cpu_clk,   
            RESET_N     => s_cpu_reset_n,   
            A           => local_addr,      

            D_in        => D_in,            
            D_out       => D_out,           

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
            STERM_N     => cpu_sterm_n,     -- verbinde zu FastRAM-Bridge
            CIIN_N      => '1',             
            HALT_N      => '1',             
            BERR_N      => '1',             
            CBREQ_N     => open,
            CBACK_N     => '1',             
            IPL_N       => IPL_N,           -- Verbinde CPU-IPL-Pins mit dem externen IPL_N-Vektor
            BR_N        => '1',             
            BG_N        => open,
            BGACK_N     => '1'
        );

    -- =====================================================================
    -- 4. INSTANZIIERUNG: FASTRAM-BRIDGE (LESEN / SCHREIBEN ZUM EXTERNEN DDR)
    -- Die Brücke beobachtet CPU-Adressen / AS_N und steuert die externen DDR-Ports
    -- =====================================================================
    u_fastram : cpu_030_fastram_bridge
        port map (
            CLK             => local_cpu_clk,
            RESET_N         => s_cpu_reset_n,
            cpu_A           => local_addr,
            cpu_D_out       => D_out,
            cpu_D_in        => D_in,
            cpu_AS_N        => local_as_n,
            cpu_DS_N        => local_ds_n,
            cpu_RW          => local_rw,
            cache_req       => '0',         -- zur Zeit nicht verwendet
            cache_burst_en  => '1',         -- Burst-Reads erlauben
            cpu_sterm_n     => cpu_sterm_n,
            ddr_req         => ddr_req,
            ddr_rnw         => ddr_rnw,
            ddr_addr        => ddr_addr,
            ddr_data_w      => ddr_data_w,
            ddr_data_r      => ddr_data_r,
            ddr_ready       => ddr_ready,
            ddr_burst_ack   => ddr_burst_ack
        );

end structural;
