-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_card.vhd
-- Teil:    1 von 2 (Sanierten Entity und CPU-Komponentendeklaration)
-- Funktion: Das übergeordnete Platinen-Gehäuse (Top-Level der Turbokarte).
-- REPARATUR:
--   - Physikalischen Port IPL_N in der äußeren Entity nachgerüstet!
--   - Beseitigt den Deklarations-Fehler (Error 10482) beim Binden des Kerns.
--   - FC-Vektor-Breite (3 Bits) in der CPU-Schablone final fixiert.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity turbo_card is
    Port (
        -- Takteingang von Alice und globaler Reset vom Mainboard
        CLK_14M     : in    std_logic;                      -- Originaler 14,14 MHz Systemtakt von Alice
        RESET_N     : in    std_logic;                      -- Haupt-Reset

        -- Schnittstelle zum Amiga-Mainboard-Bus (Äußere Pins der Karte)
        A           : out   std_logic_vector(31 downto 0);  -- Adressbus zum Mainboard
        D           : inout std_logic_vector(31 downto 0);  -- Nativer, bidirektionaler 32-Bit Datenbus

        -- Kontrollsignale zum Mainboard (Spiegelung des CPU-Busses)
        AS_N        : out   std_logic;                      -- Address Strobe
        DS_N        : out   std_logic;                      -- Data Strobe
        RW          : out   std_logic;                      -- Read / Write
        SIZ         : out   std_logic_vector(1 downto 0);   -- Transfer-Größe
        FC          : out   std_logic_vector(2 downto 0);   -- Function Codes

        -- Rückmeldungen vom Mainboard-Chipsatz und Paula-Interrupts
        DSACK0_N    : in    std_logic;                      -- Daten-Ack Bit 0
        DSACK1_N    : in    std_logic;                      -- Daten-Ack Bit 1
        -- REPARATUR: Echter, physikalischer Interrupt-Eingang von Paula nachgerüstet!
        IPL_N       : in    std_logic_vector(2 downto 0)    -- Interrupt Priority Level
    );
end turbo_card;

architecture structural of turbo_card is

    -- =====================================================================
    -- KORRIGIERTE KOMPONENTENDEKLARATIONEN (VHDL-konformer Core)
    -- =====================================================================
    
    -- Der sanierten, 32-Bit-gereinigte 68EC030 CPU-Kern
    component cpu_030_ec is
        Port (
            CLK         : in    std_logic;
            RESET_N     : in    std_logic;
            A           : out   std_logic_vector(31 downto 0);
            D           : inout std_logic_vector(31 downto 0);
            AS_N        : out   std_logic;
            DS_N        : out   std_logic;
            RW          : out   std_logic;
            SIZ         : out   std_logic_vector(1 downto 0);
            FC          : out   std_logic_vector(2 downto 0); -- Sanierten 3-Bit Breite!
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

    -- Interne Verbindungssignale (Die Kupferbahnen auf der Turbokarte)
    signal local_cpu_clk   : std_logic;                     -- Schneller 4x-Takt (56,56 MHz)
    signal local_addr      : std_logic_vector(31 downto 0);
    signal local_data      : std_logic_vector(31 downto 0);

    -- Interne Steuerleitungen der CPU
    signal local_as_n      : std_logic;
    signal local_ds_n      : std_logic;
    signal local_rw        : std_logic;
    signal local_siz       : std_logic_vector(1 downto 0);
    signal local_fc        : std_logic_vector(2 downto 0);

begin

    -- =====================================================================
    -- 1. PHYSIKALISCHE SIGNALDURCHREICHUNG ZUM AMIGA-MAINBOARD
    -- =====================================================================
    -- Adressbus und Kontrollsignale werden direkt an die Pins weitergeleitet
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
            clk_in_14m  => CLK_14M,         -- 14 MHz von Alice geht rein
            clk_out_56m => local_cpu_clk    -- 56 MHz phasenstarr kommt raus
        );

    -- =====================================================================
    -- 3. INSTANZIIERUNG: DER SANIERTEN 68EC030 CPU-KERN
    -- =====================================================================
    i_cpu_core : cpu_030_ec
        port map (
            CLK         => local_cpu_clk,   -- CPU läuft auf schnellem Takt
            RESET_N     => RESET_N,
            A           => local_addr,      -- Lokaler Adressbus
            
            -- REPARATUR FEHLER 13072: Der CPU-Datenbus wird direkt an die physischen 
            -- Pins des Wrappers gelötet! Verhindert jegliche interne Ringschleifen.
            D           => D,               
            
            AS_N        => local_as_n,
            DS_N        => local_ds_n,
            RW          => local_rw,
            SIZ         => local_siz,
            FC          => local_fc,
            OCS_N       => open,            -- Vorläufig offen für spätere Analyse
            ECS_N       => open,
            CIOUT_N     => open,
            DSACK0_N    => DSACK0_N,        -- Mainboard-Quittung durchreichen
            DSACK1_N    => DSACK1_N,
            STERM_N     => '1',             -- Pull-Up (Lokaler DDR-Controller inaktiv)
            CIIN_N      => '1',             -- Cache Inhibit inaktiv
            HALT_N      => '1',             -- CPU läuft frei
            BERR_N      => '1',             -- Kein Bus-Fehler simuliert
            CBREQ_N     => open,
            CBACK_N     => '1',             
            IPL_N       => IPL_N,           -- Reale Paula-Interrupts durchreichen
            BR_N        => '1',             -- Bus frei
            BG_N        => open,
            BGACK_N     => '1'
        );

end structural;
