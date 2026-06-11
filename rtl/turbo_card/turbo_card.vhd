-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_card.vhd
-- Teil:    1 von 2 (Entity und Komponentendeklarationen)
-- Funktion: Das übergeordnete Platinen-Gehäuse (Top-Level der Turbokarte).
--           Verhält sich wie eine echte physische Erweiterungskarte.
--           Verdrahtet CPU, Takt-Chip, RTC und FastRAM-Bridge lokal.
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

        -- Rückmeldungen vom Mainboard-Chipsatz (Gayle/Alice/CIAs)
        DSACK0_N    : in    std_logic;                      -- Daten-Ack Bit 0
        DSACK1_N    : in    std_logic                       -- Daten-Ack Bit 1
    );
end turbo_card;

architecture structural of turbo_card is

    -- =====================================================================
    -- KORRIGIERTE KOMPONENTENDEKLARATIONEN (Unsere neuen VHDL-konformen Cores)
    -- =====================================================================
    
    -- Der neue, gereinigte 68EC030 CPU-Kern
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

    -- Der neue, separate Takt-Manager der Turbokarte
    component turbo_clk is
        Port (
            clk_in_14m  : in    std_logic;                      -- Eingang von Alice
            clk_out_56m : out   std_logic                       -- Multiplizierter CPU-Takt (4x)
        );
    end component;

    -- =====================================================================
    -- Interne Verbindungssignale (Die Kupferbahnen auf der Turbokarte)
    -- =====================================================================
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
    -- Signaldurchreichung zum Amiga-Mainboard (Äußere Pins treiben)
    -- =====================================================================
    A    <= local_addr;
    D    <= local_data;
    AS_N <= local_as_n;
    DS_N <= local_ds_n;
    RW   <= local_rw;
    SIZ  <= local_siz;
    FC   <= local_fc;

    -- =====================================================================
    -- Instanziierung: Lokaler Takt-Manager (Vervielfacher)
    -- =====================================================================
    i_turbo_clk : turbo_clk
        port map (
            clk_in_14m  => CLK_14M,         -- 14 MHz von Alice geht rein
            clk_out_56m => local_cpu_clk    -- 56 MHz phasenstarr kommt raus
        );

    -- =====================================================================
    -- Instanziierung: Der neue 68EC030 CPU-Kern
    -- =====================================================================
    i_cpu_core : cpu_030_ec
        port map (
            CLK         => local_cpu_clk,   -- CPU läuft auf schnellem Takt
            RESET_N     => RESET_N,
            A           => local_addr,      -- Lokaler Adressbus
            D           => local_data,      -- Lokaler, bidirektionaler Datenbus
            AS_N        => local_as_n,
            DS_N        => local_ds_n,
            RW          => local_rw,
            SIZ         => local_siz,
            FC          => local_fc,
            OCS_N       => open,            -- Vorläufig offen
            ECS_N       => open,
            CIOUT_N     => open,
            DSACK0_N    => DSACK0_N,        -- Mainboard-Bestätigung durchreichen
            DSACK1_N    => DSACK1_N,
            STERM_N     => '1',             -- Pull-Up (DDR-FastRAM noch inaktiv)
            CIIN_N      => '1',             -- Cache Inhibit inaktiv
            HALT_N      => '1',             -- CPU läuft frei
            BERR_N      => '1',             -- Kein Bus-Fehler simuliert
            CBREQ_N     => open,
            CBACK_N     => '1',             -- Burst-Bestätigung inaktiv
            IPL_N       => "111",           -- Keine Interrupts aktiv (High-Aktiv maskiert)
            BR_N        => '1',             -- Bus frei
            BG_N        => open,
            BGACK_N     => '1'
        );

end structural;
