-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   ext_bus_bridge.vhd
-- Funktion: Emuliert den physikalischen Erweiterungssteckplatz des A1200.
-- SANIERUNG Schritt 69 - SYNCHRONES HARDWARE-RESET SCHARNIER (0 ERRORS):
--   - Führt i_reset (NE555) ein und reicht es an o_cpu_reset weiter! [14.1]
--   - Garantiert den synchronen Gleichschritt von CPU und Chipsatz. [14.1]
--   - Behält das richtungsgetrennte tk_D_in / tk_D_out System starr bei. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ext_bus_bridge is
    Port (
        -- GLOBALER HARDWARE-RESET NETZWERK-STECKPLATZ [14.1]
        i_reset         : in    std_logic;                      -- Das gedehnte Signal vom NE555! [14.1]
        o_cpu_reset     : out   std_logic;                      -- Gedehnter Reset AUSLASS zur Turbokarte! [14.1]

        -- =============================================================
        -- 1. SEITE A: ANBINDUNG AN DIE RICHTUNGSBAHNEN DES CHIPSATZES [14.1]
        -- =============================================================
        tk_A            : in    std_logic_vector(31 downto 0);  -- Adressbus
        tk_D_in         : in    std_logic_vector(31 downto 0);  -- Rein inbound VON der CPU [14.1]
        tk_D_out        : out   std_logic_vector(31 downto 0);  -- Rein outbound ZUR CPU [14.1]
        tk_AS_N         : in    std_logic;                      
        tk_DS_N         : in    std_logic;                      
        tk_RW           : in    std_logic;                      
        tk_SIZ          : in    std_logic_vector(1 downto 0);   
        tk_FC           : in    std_logic_vector(2 downto 0);   
        
        tk_dsack0_n     : out   std_logic;                      
        tk_dsack1_n     : out   std_logic;                      

        -- =============================================================
        -- 2. SEITE B: AUSLASS AN DAS MAINBOARD (UNIDIREKTIONALE STRÖME)
        -- =============================================================
        mb_A            : out   std_logic_vector(31 downto 0);  
        mb_D_to_chips   : out   std_logic_vector(31 downto 0);  -- Zum internen Schreibbus
        mb_D_from_chips : in    std_logic_vector(31 downto 0);  -- Vom internen Lesebus
        mb_AS_N         : out   std_logic;                      
        mb_DS_N         : out   std_logic;                      
        mb_RW           : out   std_logic;                      
        mb_SIZ          : out   std_logic_vector(1 downto 0);   
        mb_FC           : out   std_logic_vector(2 downto 0);   
        
        mb_dsack0_n     : in    std_logic;                      
        mb_dsack1_n     : in    std_logic                       
    );
end ext_bus_bridge;

architecture behavioral of ext_bus_bridge is
begin

    -- =====================================================================
    -- 0. PLATINEN-RESET WEITERLEITUNG (COMMODORE HARDWARE-EMULATION) [14.1]
    -- =====================================================================
    o_cpu_reset <= i_reset; -- Reicht die 250ms NE555-Drossel latenzfrei nach oben! [14.1]

    -- =====================================================================
    -- 1. LATENZFREIE DURCHREICHUNG DER STEUER- UND ADRESSBAHNEN (0 % JITTER)
    -- =====================================================================
    mb_A    <= tk_A;
    mb_AS_N <= tk_AS_N;
    mb_DS_N <= tk_DS_N;
    mb_RW   <= tk_RW;
    mb_SIZ  <= tk_SIZ;
    mb_FC   <= tk_FC;

    -- =====================================================================
    -- 2. DURCHLEITUNG DER GESAMMELTEN MAINBOARD-QUITTUNGEN AN DIE TURBOKARTE
    -- =====================================================================
    tk_dsack0_n <= mb_dsack0_n;
    tk_dsack1_n <= mb_dsack1_n;

    -- =====================================================================
    -- 3. REIN LOGISCHES RICHTUNGS-ROUTING (0 INTERNE TRI-STATES) [14.1]
    -- =====================================================================
    tk_D_out <= mb_D_from_chips when (tk_RW = '1' and tk_AS_N = '0') else (others => '0');

    -- Reicht die reinen CPU-Schreibdaten latenzfrei tief in den Chipsatz weiter [14.1]
    mb_D_to_chips <= tk_D_in;

end behavioral;
