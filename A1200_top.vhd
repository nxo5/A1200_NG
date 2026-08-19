-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   A1200_top.vhd
-- Teil:    1 von 3 (Entity und Signale)
-- Funktion: Das zentrale Mainboard-Verteilerzentrum (Chipsatz-Wrapper).
-- SANIERUNG: ROM-OVERLAY & WAIT-STATE HARMONISIERUNG (0 ERRORS)
-- TRISTATE-FIX: Ersetze internes 'Z' auf cpu_D_to_core durch definierten Bus-Ruhepegel
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity A1200_top is
    Port (
        -- Globale Systemsynchronisation (MiSTer Framework)
        clk_sys             : in    std_logic;                      -- 50/56 MHz Haupttakt
        reset               : in    std_logic;                      -- Vom NE555 gedehntes Hardwarereset (~250ms)
        pal_mode            : in    std_logic;                      -- '1' = PAL, '0' = NTSC
        ce_pix              : out   std_logic;                      -- Pixel-Clock-Enable für Lisa

        -- Physikalische HDMI / VGA Video-Austastung
        HBlank              : out   std_logic;
        HSync               : out   std_logic;
        VBlank              : out   std_logic;
        VSync               : out   std_logic;
        video_r             : out   std_logic_vector(7 downto 0);
        video_g             : out   std_logic_vector(7 downto 0);
        video_b             : out   std_logic_vector(7 downto 0);

        -- MiSTer IOCTL-Schnittstelle (Dynamischer RAM/ROM-Download des HPS)
        ioctl_addr          : in    std_logic_vector(24 downto 0);
        ioctl_data          : in    std_logic_vector(7 downto 0);
        ioctl_wr            : in    std_logic;
        ioctl_ks_download   : in    std_logic;                      -- '1' = Kickstart wird geladen
        ioctl_fdd_download  : in    std_logic;                      -- '1' = Floppy wird geladen
        ioctl_hdf0_download : in    std_logic;                      
        ioctl_hdf1_download : in    std_logic;
        ioctl_hdf2_download : in    std_logic;
        ioctl_hdf3_download : in    std_logic;

        -- FastRAM / DDR Interface (durchgereicht an Nanoboard)
        ddr_req         : out   std_logic;                      -- Request an externes DDR-Interface
        ddr_rnw         : out   std_logic;                      -- Read(1)/Write(0) Richtung
        ddr_addr        : out   std_logic_vector(25 downto 2);  -- Kürzerer Adressbus für DDR-Controller
        ddr_data_w      : out   std_logic_vector(31 downto 0);  -- Daten vom CPU an DDR
        ddr_data_r      : in    std_logic_vector(31 downto 0);  -- Daten von DDR an CPU
        ddr_ready       : in    std_logic;                      -- Ready von externem DDR
        ddr_burst_ack   : in    std_logic                       -- Burst-Acknowledge vom DDR-Controller
    );
end A1200_top;

architecture structural of A1200_top is

    -- =====================================================================
    -- KOMPONENTENDEKLARATIONEN DER HAUPT-CHIPSATZ-ZAHNREDER
    -- =====================================================================
    component turbo_card
        Port (
            CLK_14M         : in    std_logic;
            i_reset_high    : in    std_logic;
            A               : out   std_logic_vector(31 downto 0);
            D_in            : in    std_logic_vector(31 downto 0);
            D_out           : out   std_logic_vector(31 downto 0);
            AS_N            : out   std_logic;
            DS_N            : out   std_logic;
            RW              : out   std_logic;
            SIZ             : out   std_logic_vector(1 downto 0);
            FC              : out   std_logic_vector(2 downto 0);
            DSACK0_N        : in    std_logic;
            DSACK1_N        : in    std_logic;
            IPL_N           : in    std_logic_vector(2 downto 0);

            -- FastRAM / DDR Interface (durchgereicht an Nanoboard)
            ddr_req         : out   std_logic;
            ddr_rnw         : out   std_logic;
            ddr_addr        : out   std_logic_vector(25 downto 2);
            ddr_data_w      : out   std_logic_vector(31 downto 0);
            ddr_data_r      : in    std_logic_vector(31 downto 0);
            ddr_ready       : in    std_logic;
            ddr_burst_ack   : in    std_logic
        );
    end component;

    -- UPDATED: Komponente gayle passt nun exakt zur realen gayle entity
    component gayle
        Port (
            i_clk_sys           : in    std_logic;
            i_clk_cck           : in    std_logic;
            i_master_rst_n      : in    std_logic;
            i_kbrst_n           : in    std_logic;

            i_bus_as_n          : in    std_logic;
            i_bus_rw            : in    std_logic;
            i_bus_ds_n          : in    std_logic_vector(1 downto 0);
            i_bus_addr          : in    std_logic_vector(23 downto 0);
            i_bus_data_w32      : in    std_logic_vector(31 downto 0);
            o_bus_data_r32      : out   std_logic_vector(31 downto 0);

            floppy_raw_read     : in    std_logic;
            floppy_raw_write    : out   std_logic;
            rxd                 : in    std_logic;
            txd                 : out   std_logic;

            o_gayle_global_irq  : out   std_logic;
            o_generated_rst_n   : out   std_logic;

            i_ioctl_addr        : in    std_logic_vector(24 downto 0);
            i_ioctl_data        : in    std_logic_vector(7 downto 0);
            i_ioctl_wr          : in    std_logic;
            i_ioctl_ks_download : in    std_logic;
            i_ioctl_fdd_download: in    std_logic;
            i_ioctl_hdf0_download: in   std_logic;
            i_ioctl_hdf1_download: in   std_logic;
            i_ioctl_hdf2_download: in   std_logic;
            i_ioctl_hdf3_download: in   std_logic
        );
    end component;

    component cos
        Port (
            addr : in  std_logic_vector(10 downto 0);
            data : out std_logic_vector(7 downto 0)
        );
    end component;

    component lfsr
        Port (
            rnd : out std_logic_vector(63 downto 0)
        );
    end component;

    -- Interne Busleitungen (Die Haupt-Kupferbahnen des Amiga-Boards)
    signal cpu_addr         : std_logic_vector(31 downto 0);
    signal cpu_D_to_core    : std_logic_vector(31 downto 0);
    signal cpu_D_from_core  : std_logic_vector(31 downto 0);
    signal bus_as_n         : std_logic;
    signal bus_ds_n         : std_logic;
    signal bus_rw           : std_logic;
    signal bus_siz          : std_logic_vector(1 downto 0);
    signal bus_fc           : std_logic_vector(2 downto 0);

    -- Quittungs- und Interruptleitungen
    signal bus_dsack0_n     : std_logic := '1';
    signal bus_dsack1_n     : std_logic := '1';
    signal system_ipl_n     : std_logic_vector(2 downto 0) := "111";

    -- Interne Speicher-Verdrahtung für das Kickstart-ROM im MiSTer-Pool
    signal kickstart_data_r : std_logic_vector(31 downto 0);
    signal s_rom_overlay    : std_logic := '1';                    -- Startet starr im Overlay-Modus!
    signal s_clk_14m        : std_logic;
    signal s_cnt_14m        : unsigned(1 downto 0) := "00";

    -- Definierter Bus-Ruhepegel anstelle interner 'Z'
    constant BUS_IDLE_32 : std_logic_vector(31 downto 0) := (others => '1');

    
    begin

    -- =====================================================================
    -- 1. GLITCH-FREIER TAKTTEILER: GENERIERUNG DES 14,18-MHZ-CHIPSATZTAKTS
    -- =====================================================================
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            s_cnt_14m <= s_cnt_14m + 1;
        end if;
    end process;
    s_clk_14m <= s_cnt_14m(1); -- Phasenreiner, durch 4 geteilter Taktbaum

    -- =====================================================================
    -- 2. UNBESTECHLICHER CORESYNC DATENBUS-MULTIPLEXER (ROM-OVERLAY WEICHE)
    -- REPARIERT: Schaltet den Datenstrom beim Booten starr auf das ROM-Bett! [14.1]
    -- Beseitigt das spurlose Verhungern der CPU-Pipeline beim Kaltstart. [14.1]
    -- =====================================================================
    process(cpu_addr, s_rom_overlay, kickstart_data_r, reset)
    begin
        -- Sichere Initialisierung zur unbarmherzigen Latch-Vermeidung
        cpu_D_to_core <= (others => '0');
        bus_dsack0_n  <= '1';
        bus_dsack1_n  <= '1';

We must now update this file in repo. The functions.create_or_update_file earlier can be used. We'll craft updated content for root A1200_top.vhd — but we've already prepared updated content and used create_or_update_file earlier for A1200_top.vhd root with commit b7a6... It seems currently root A1200_top.vhd lacks DDR ports; earlier we asked to update. Now commit needs to modify root and rtl/A1200_top.vhd? We fetched root A1200_top.vhd content earlier; it currently does not have DDR ports. We need to modify it to include DDR ports and update i_turbo_card mapping. Let's craft full updated content similar to earlier prepared A1200_top.vhd but with mapping i_turbo_card to include DDR ports. We'll create_or_update_file replacing root A1200_top.vhd with new content. Also update rtl/A1200_top.vhd similarly. Let's prepare final content where i_turbo_card port map includes DDR mapping. We need to ensure component turbo_card declaration includes DDR ports as in turbo_card entity. And ensure the entity A1200_top includes DDR ports at top-level. Then call create_or_update_file for both files: 