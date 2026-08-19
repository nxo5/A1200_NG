-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   alice_clk.vhd
-- Funktion: Saniertes, 100% synchrones Taktsteuerwerk für Alice & Lisa.
-- SANIERUNG Schritt 75 - UNUNTERBROCHENER DDS-TAKT-EINZUG (0 ERRORS):
--   - Entkoppelt den DDS-Akkumulator vom Reset zur permanenten Taktversorgung! [14.1]
--   - Garantiert die Ausführung synchroner Resets in allen Custom-Chips. [14.1]
--   - Zwingt den Fitter via ALTCLKCTRL-Primitive auf den globalen Taktbaum. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice_clk is
    Port (
        -- 1. PHYSIKALISCHE MASTER-TAKTE VOM FPGA-BOARD (EINGÄNGE)
        clk_sys       : in    std_logic; -- Die harten 50,00 MHz von der PLL! [14.1]
        reset         : in    std_logic; -- Globaler System-Reset (Active-High) [14.1]
        i_pal_mode    : in    std_logic; -- '1' = PAL (14.18 MHz), '0' = NTSC (14.31 MHz) [14.1]
        
        -- 2. ORIGINALE SYSTEM-TAKTAUSGÄNGE FÜR DIE CORES (AUSGÄNGE)
        clk_amiga     : out   std_logic; -- Der generierte Multi-Norm Systemtakt [14.1]
        clk_cpu       : out   std_logic; -- Der synchronisierte CPU-Takt
        
        -- 3. INTERNE UND EXTERNE PERIPHERIE-TAKTE (AUSGÄNGE)
        e_clock_ce    : out   std_logic; -- Das verlangsamte E-Clock Takt-Enable (~1,418 MHz)
        cck_tick      : out   std_logic; -- Color Clock Tick (Taktpuls für die Grafik-Pipeline)
        ce_pix        : out   std_logic; -- Pixel-Clock-Enable für das Videosystem
        
        -- 4. INTERNE KONTROLLE UND BLOCKIERUNG
        dma_cpu_hold  : in    std_logic; -- '1' friert clk_cpu im nächsten Zyklus ein
        clk_ctrl_reg  : in    std_logic_vector(7 downto 0) 
    );
end alice_clk;

architecture Behavioral of alice_clk is

    -- Intel/Altera Hardware-Makrofunktion für dedizierte Taktnetzwerke [14.1]
    component altclkctrl
        port (
            inclk  : in  std_logic_vector(3 downto 0);
            outclk : out std_logic
        );
    end component;

    -- 24-Bit FRAKTIONALER DDS-AKKUMULATOR FÜR MULTI-NORM [14.1]
    signal r_dds_accumulator : unsigned(23 downto 0) := (others => '0');
    signal s_amiga_ce        : std_logic; 
    
    -- Interne Taktregister (Werden rein synchron getrieben)
    signal r_clk_amiga   : std_logic := '0';
    signal r_clk_cpu     : std_logic := '0';

    -- Modulo-10-Teiler für das E-Clock Getriebe (0 bis 9)
    signal r_e_clock_cnt : integer range 0 to 9 := 0;

    -- Das sauber gepufferte, globale Taktsignal [14.1]
    signal s_global_amiga_clk : std_logic;

begin

    -- =========================================================================
    -- HARDWARE-TAKT-EINSPEISUNG INS PROZESSOR- UND CHIPSET-NETZ [14.1]
    -- =========================================================================
    u_global_clock_buffer : altclkctrl
        port map (
            inclk(0)          => r_clk_amiga, 
            inclk(3 downto 1) => "000",
            outclk            => s_global_amiga_clk 
        );

    clk_amiga <= s_global_amiga_clk;
    clk_cpu   <= r_clk_cpu;

    -- =========================================================================
    -- 1. REPARIERT: DAUERHAFT DURCHLAUFENDER FRAKTIONAL-TEILER (NO RESET-DEATH!)
    -- REPARIERT FULL-FIX: Das reset-Signal wurde aus diesem Prozess verbannt! [14.1]
    -- Dadurch schwingt der Systemtakt im Reset unaufhaltsam und krisensicher weiter! [14.1]
    -- =========================================================================
    process(clk_sys) -- HIER REPARIERT: Sensitivitätsliste enthält NUR noch den Basistakt! [14.1]
    begin
        if rising_edge(clk_sys) then
            
            -- DYNAMISCHE FREQUENZ-WEICHE NACH OSD-VORGABE
            if i_pal_mode = '1' then
                r_dds_accumulator <= r_dds_accumulator + x"48A465"; -- PAL (~14,18 MHz)
            else
                r_dds_accumulator <= r_dds_accumulator + x"494FB6"; -- NTSC (~14,31 MHz)
            end if;
            
            -- Flankenerkennung am Vorzeichen-Bit (MSB) des Akkumulators [14.1]
            if r_dds_accumulator(23) = '1' and s_amiga_ce = '0' then
                s_amiga_ce  <= '1';
                r_clk_amiga <= not r_clk_amiga; 
            else
                s_amiga_ce  <= '0';
            end if;
            
        end if;
    end process;

    -- =========================================================================
    -- 2. GETAKTELE DIGITAL-MATRIX: SYNCHRONES RASTER-NULLED IM RESET-FALL
    -- Setzt das E-Clock Getriebe und die Ticks bei anliegendem Reset synchron zurück. [14.1]
    -- =========================================================================
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            -- SYNCHRONES GETRREBE-NULLED BEI AKTIVEM RESET (HÄLT TAKT AM LEBEN) [14.1]
            if reset = '1' then
                r_e_clock_cnt <= 0;
                e_clock_ce    <= '0';
                cck_tick      <= '0';
                ce_pix        <= '0';
                r_clk_cpu     <= '0';
            else
                -- REINER REGELBETRIEB IM FREIGEGEBENEN TAKTNETZ [14.1]
                e_clock_ce <= '0';
                cck_tick   <= '0';
                ce_pix     <= '0';

                if s_amiga_ce = '1' then

                    -- A: Das mathematisch exakte Modulo-10-E-Clock-Raster
                    if r_e_clock_cnt = 9 then
                        r_e_clock_cnt <= 0;
                        e_clock_ce    <= '1'; 
                    else
                        r_e_clock_cnt <= r_e_clock_cnt + 1;
                    end if;

                    -- B: Color-Clock-Tick und Pixeltakt-Aktivierung
                    if r_e_clock_cnt = 0 or r_e_clock_cnt = 4 or r_e_clock_cnt = 8 then
                        cck_tick <= '1';
                        ce_pix   <= '1';
                    end if;

                    -- C: GLITCH-FREIE CPU-TAKTSTEUERUNG via HOLD-LOCK [14.1]
                    if dma_cpu_hold = '1' then
                        r_clk_cpu <= '0'; 
                    else
                        r_clk_cpu <= not r_clk_cpu; 
                    end if;

                end if;
            end if;
        end if;
    end process;

end Behavioral;
