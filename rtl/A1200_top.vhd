-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   A1200_top.vhd
-- Funktion: Das Haupt-Mainboard (Top-Level-Entity) des Gesamtsystems.
--           Verbindet das MiSTer-Framework mit den Custom-Chips und der TK.
--           KORREKTUR: Altes 68020-Testboard entfernt, Platz für turbo_card.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity A1200_top is
    Port (
        -- 1. System-Signale vom MiSTer-Framework
        clk_sys     : in  STD_LOGIC; -- Haupttakt vom DE10-Nano (50 MHz)
        reset       : in  STD_LOGIC; -- System-Reset
        pal_mode    : in  STD_LOGIC; -- '1' für PAL, '0' für NTSC
        
        -- 2. Ausgänge zum MiSTer-Videosystem (AGA 24-Bit Farbtiefe)
        ce_pix      : out STD_LOGIC; 
        HBlank      : out STD_LOGIC; 
        HSync       : out STD_LOGIC; 
        VBlank      : out STD_LOGIC; 
        VSync       : out STD_LOGIC; 
        video_r     : out STD_LOGIC_VECTOR(7 downto 0);
        video_g     : out STD_LOGIC_VECTOR(7 downto 0);
        video_b     : out STD_LOGIC_VECTOR(7 downto 0)
    );
end A1200_top;

architecture Behavioral of A1200_top is

    -- =====================================================================
    -- CHIP-DEKLARATION: DIE NEUE TURBOKARTE (Das Platinen-Gehäuse)
    -- =====================================================================
    component turbo_card is
        Port (
            -- Takteingang von Alice und globaler Reset
            CLK_14M     : in    std_logic;                      -- Originaler 14,14 MHz Systemtakt von Alice
            RESET_N     : in    std_logic;                      -- Haupt-Reset

            -- Schnittstelle zum Amiga-Mainboard-Bus (32-Bit)
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
    end component;

    -- =====================================================================
    -- INTERNE KUPFERBAHNEN DER PLATINE (Der globale Amiga-32-Bit-Bus)
    -- =====================================================================
    signal clk_alice_14m : std_logic := '0';                    -- Wird später von der echten Alice getrieben

    signal am_addr       : std_logic_vector(31 downto 0);
    signal am_data       : std_logic_vector(31 downto 0);       -- Jetzt sauber als EIN bidirektionaler Bus!
    signal am_as_n       : std_logic;
    signal am_ds_n       : std_logic;
    signal am_rw         : std_logic;
    signal am_fc         : std_logic_vector(2 downto 0);
    signal am_siz        : std_logic_vector(1 downto 0);
    signal am_dsack0_n   : std_logic;
    signal am_dsack1_n   : std_logic;

begin

    -- PROVISORISCHER TAKT-DUMMY FÜR ALICE (Fällt weg, sobald die echte Alice instanziiert wird)
    -- Erzeugt die 14,14 MHz synchron aus den 50 MHz des MiSTer-Frameworks
    process(clk_sys)
        variable count : integer range 0 to 3 := 0;
    begin
        if rising_edge(clk_sys) then
            if count = 3 then
                count := 0;
                clk_alice_14m <= not clk_alice_14m;
            else
                count := count + 1;
            end if;
        end if;
    end process;
    
    ce_pix <= clk_alice_14m; 

    -- =====================================================================
    -- CHIP-BESTÜCKUNG: DIE TURBOKARTE WIRD AUFGESTECKT
    -- =====================================================================
    i_amiga_turbo_card : turbo_card
        port map (
            CLK_14M     => clk_alice_14m,   -- Takt von Alice geht rein
            RESET_N     => reset,           -- Reset vom Framework
            A           => am_addr,         -- Adressbus-Kopplung
            D           => am_data,         -- Bidirektionale Datenbus-Kopplung
            AS_N        => am_as_n,
            DS_N        => am_ds_n,
            RW          => am_rw,
            SIZ         => am_siz,
            FC          => am_fc,
            DSACK0_N    => am_dsack0_n,
            DSACK1_N    => am_dsack1_n
        );

    -- [Hier werden im nächsten Schritt Gayle, Alice und die CIAs an denselben Bus gekoppelt]
    -- Für den Moment legen wir feste Dummys an, damit der Compiler terminieren kann:
    am_dsack0_n <= '1'; -- Pull-Up (Mainboard antwortet noch nicht)
    am_dsack1_n <= '1'; -- Pull-Up

    -- TEMPORÄRE DUMMYS FÜR CHIPSATZ-AUSGÄNGE
    HBlank    <= '0'; HSync <= '0'; VBlank <= '0'; VSync <= '0';
    video_r   <= (others => '0'); video_g <= (others => '0'); video_b <= (others => '0'); 

end Behavioral;
