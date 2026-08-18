-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   A1200_top.vhd
-- Teil:    1 von 3 (Die Hauptplatine-Pforte nach außen)
-- Funktion: Das Haupt-Mainboard (Top-Level-Entity) des Gesamtsystems.
-- ENTTECHTUNG FIX:
--   - Reicht die True-Color Graphikdaten von LISA fehlerfrei weiter.
--   - Bereitet die Port-Infrastruktur auf die Richtungstrennung vor.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity A1200_top is
    Port (
        -- 1. CLOCK-, RESET- UND SYSTEMLEITUNGEN VOM MISTER
        clk_sys           : in    std_logic; 
        reset             : in    std_logic; 
        pal_mode          : in    std_logic; 
        
        -- 2. GRAPHIK- UND TRUECOLOR-AUSGÄNGE ZUM SCALER/HDMI
        ce_pix            : out   std_logic; 
        HBlank            : out   std_logic; 
        HSync             : out   std_logic; 
        VBlank            : out   std_logic; 
        VSync             : out   std_logic; 
        video_r           : out   std_logic_vector(7 downto 0); 
        video_g           : out   std_logic_vector(7 downto 0); 
        video_b           : out   std_logic_vector(7 downto 0); 
        
        -- 3. NEXT-GEN OSD ADF-FLOPPY SCHNITTSTELLE
        img_fdd_raw_read  : in    std_logic; 
        img_fdd_raw_write : out   std_logic; 
        
        -- 4. EXKUSIVE 4-KANAL HDF-FESTPLATTEN-SCHNITTSTELLE
        hdf0_data_i       : in    std_logic_vector(15 downto 0); 
        hdf0_data_o       : out   std_logic_vector(15 downto 0);
        hdf1_data_i       : in    std_logic_vector(15 downto 0); 
        hdf1_data_o       : out   std_logic_vector(15 downto 0);
        hdf2_data_i       : in    std_logic_vector(15 downto 0); 
        hdf2_data_o       : out   std_logic_vector(15 downto 0);
        hdf3_data_i       : in    std_logic_vector(15 downto 0); 
        hdf3_data_o       : out   std_logic_vector(15 downto 0);
        
        -- 5. USB-TASTATUR UND MAUS-STACK VOM HPS-ARM-KERN
        kbd_clk           : in    std_logic; 
        kbd_data          : in    std_logic; 
        kbd_reset         : in    std_logic; 
        mouse_x           : in    std_logic_vector(1 downto 0); 
        mouse_y           : in    std_logic_vector(1 downto 0); 
        mouse_btn         : in    std_logic_vector(1 downto 0);
        
        -- GEMEINSAM GENUTZTE INFRASTRUKTUR-BUSSE FÜR DEN DOWNLOAD
        ioctl_addr        : in    std_logic_vector(24 downto 0); 
        ioctl_data        : in    std_logic_vector(7 downto 0);  
        ioctl_wr          : in    std_logic;                     
        
        -- Die 6 indexgetrennten Download-Adern vom Framework
        ioctl_ks_download : in    std_logic;
        ioctl_fdd_download: in    std_logic;
        ioctl_hdf0_download: in   std_logic;
        ioctl_hdf1_download: in   std_logic;
        ioctl_hdf2_download: in   std_logic;
        ioctl_hdf3_download: in   std_logic
    );
end A1200_top;

architecture Behavioral of A1200_top is

    component turbo_card is
        Port (
            CLK_14M     : in    std_logic;
            RESET_N     : in    std_logic;
            A           : out   std_logic_vector(31 downto 0);
            D_in        : in    std_logic_vector(31 downto 0); 
            D_out       : out   std_logic_vector(31 downto 0);         
            AS_N        : out   std_logic;
            DS_N        : out   std_logic;
            RW          : out   std_logic;
            SIZ         : out   std_logic_vector(1 downto 0);
            FC          : out   std_logic_vector(2 downto 0);
            DSACK0_N    : in    std_logic;
            DSACK1_N    : in    std_logic;
            IPL_N       : in    std_logic_vector(2 downto 0)
        );
    end component;

    component amiga_chipset is
        Port (
            clk_sys           : in    std_logic;
            clk_alice_14m     : in    std_logic;
            reset             : in    std_logic;
            kbd_reset         : in    std_logic;
            kbd_clk           : in    std_logic;
            kbd_data          : in    std_logic;
            img_fdd_raw_read  : in    std_logic;
            img_fdd_raw_write : out   std_logic;
            
            am_addr           : in    std_logic_vector(31 downto 0);
            am_data_in        : in    std_logic_vector(31 downto 0); 
            am_data_out       : out   std_logic_vector(31 downto 0);
            am_as_n           : in    std_logic;
            am_ds_n           : in    std_logic;
            am_rw             : in    std_logic;
            am_dsack0_n       : out   std_logic;
            am_dsack1_n       : out   std_logic;
            o_generated_rst_n : out   std_logic;
            
            hdf0_data_o       : out   std_logic_vector(15 downto 0);
            hdf1_data_o       : out   std_logic_vector(15 downto 0);
            hdf2_data_o       : out   std_logic_vector(15 downto 0);
            hdf3_data_o       : out   std_logic_vector(15 downto 0);
            
            ioctl_addr        : in    std_logic_vector(24 downto 0);
            ioctl_data        : in    std_logic_vector(7 downto 0);
            ioctl_wr          : in    std_logic;
            
            ioctl_ks_download : in    std_logic;
            ioctl_fdd_download: in    std_logic;
            ioctl_hdf0_download: in   std_logic;
            ioctl_hdf1_download: in   std_logic;
            ioctl_hdf2_download: in   std_logic;
            ioctl_hdf3_download: in   std_logic;

            o_ks_sdram_addr   : out   std_logic_vector(26 downto 2);
            o_ks_sdram_data_w : out   std_logic_vector(31 downto 0);
            o_ks_sdram_we     : out   std_logic;

            o_vid_rgb_r       : out   std_logic_vector(7 downto 0);
            o_vid_rgb_g       : out   std_logic_vector(7 downto 0);
            o_vid_rgb_b       : out   std_logic_vector(7 downto 0);
            o_vid_hblank      : out   std_logic;
            o_vid_vblank      : out   std_logic
        );
    end component;

    component sdram_bridge is
        Port (
            clk_amiga       : in    std_logic;
            clk_sdram       : in    std_logic;
            reset           : in    std_logic;
            dec_sb_addr     : in    std_logic_vector(26 downto 0);
            dec_sb_req      : in    std_logic;
            dec_sb_is_chip  : in    std_logic;
            
            am_data_in      : in    std_logic_vector(31 downto 0); 
            am_data_out     : out   std_logic_vector(31 downto 0);
            am_as_n         : in    std_logic;
            am_ds_n         : in    std_logic;
            am_rw           : in    std_logic;
            am_siz0         : in    std_logic;
            am_siz1         : in    std_logic;
            am_dsack0_n     : out   std_logic;
            am_dsack1_n     : out   std_logic;
            
            i_ks_download   : in    std_logic;
            i_ks_addr       : in    std_logic_vector(26 downto 2);
            i_ks_data_w     : in    std_logic_vector(31 downto 0);
            i_ks_we         : in    std_logic;
            
            sdram_clk       : out   std_logic;
            sdram_data      : inout std_logic_vector(15 downto 0);
            sdram_addr      : out   std_logic_vector(12 downto 0);
            sdram_ba        : out   std_logic_vector(1 downto 0);
            sdram_ras_n     : out   std_logic;
            sdram_cas_n     : out   std_logic;
            sdram_we_n      : out   std_logic;
            sdram_dqm_lo    : out   std_logic;
            sdram_dqm_hi    : out   std_logic
        );
    end component;

    -- Das übergeordnete Adress- und Kontrollnetzwerk
    signal clk_alice_14m     : std_logic := '0';
    signal int_generated_rst : std_logic;
    signal am_addr           : std_logic_vector(31 downto 0);
    signal am_as_n           : std_logic;
    signal am_ds_n           : std_logic;
    signal am_rw             : std_logic;
    signal am_dsack0_n       : std_logic;
    signal am_dsack1_n       : std_logic;

    -- =========================================================================
    -- NATIVE ENTFLECHTUNGSSIGNALE (RICHTUNGSCONFORM OHNE INTERNE INOUT-LANES) [14.1]
    -- =========================================================================
    signal bus_cpu_to_chipset : std_logic_vector(31 downto 0); -- Schreibbus CPU -> Peripherie [14.1]
    signal bus_chipset_to_cpu : std_logic_vector(31 downto 0); -- Lesebus Custom-Chips -> CPU [14.1]
    signal bus_sdram_to_cpu   : std_logic_vector(31 downto 0); -- Lesebus Speicherbrücke -> CPU [14.1]

    -- Interne Koppeldrähte für das SDRAM-Lade-Handshake
    signal s_ks_sdram_addr   : std_logic_vector(26 downto 2);
    signal s_ks_sdram_data_w : std_logic_vector(31 downto 0);
    signal s_ks_sdram_we     : std_logic;

    -- Interne Graphikbahnen für die fehlerfreie True-Color-Ausleitung
    signal s_vid_rgb_r       : std_logic_vector(7 downto 0);
    signal s_vid_rgb_g       : std_logic_vector(7 downto 0);
    signal s_vid_rgb_b       : std_logic_vector(7 downto 0);
    signal s_vid_hblank      : std_logic;
    signal s_vid_vblank      : std_logic;

	     -- Lokaler 32-Bit bidirektionaler CPU-Busdraht (Einzig zulässiges inout im Top-Level!)
    signal am_data_local     : std_logic_vector(31 downto 0);

begin

    -- Taktteiler-Prozess für die 14-MHz-Taktfamilie von Alice
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

    -- 1. INSTANZ: Die Turbokarte (68030-Core / L1-Cache)
    i_amiga_turbo_card : turbo_card
        port map (
            CLK_14M     => clk_alice_14m,
            RESET_N     => int_generated_rst, 
            A           => am_addr,
            D_in        => am_data_local,   
            D_out       => bus_cpu_to_chipset,             
            AS_N        => am_as_n,
            DS_N        => am_ds_n,
            RW          => am_rw,
            SIZ         => open,
            FC          => open,
            DSACK0_N    => am_dsack0_n,
            DSACK1_N    => am_dsack1_n,
            IPL_N       => (others => '1') -- Pull-Up für Interrupts falls Paula noch offen
        );

    -- 2. INSTANZ: Der Custom-Chipsatz (Mit integrierter AGA LISA) [14.1]
    u_amiga_chipset : amiga_chipset
        port map (
            clk_sys           => clk_sys,
            clk_alice_14m     => clk_alice_14m,
            reset             => reset,
            kbd_reset         => kbd_reset,
            kbd_clk           => kbd_clk,
            kbd_data          => kbd_data,
            img_fdd_raw_read  => img_fdd_raw_read,
            img_fdd_raw_write => img_fdd_raw_write,
            
            am_addr           => am_addr,
            am_data_in        => bus_cpu_to_chipset, -- Getrennte, unidirektionale Kanäle! [14.1]
            am_data_out       => bus_chipset_to_cpu,
            am_as_n           => am_as_n,
            am_ds_n           => am_ds_n,
            am_rw             => am_rw,
            am_dsack0_n       => am_dsack0_n,
            am_dsack1_n       => am_dsack1_n,
            o_generated_rst_n => int_generated_rst,
            
            hdf0_data_o       => hdf0_data_o,
            hdf1_data_o       => hdf1_data_o,
            hdf2_data_o       => hdf2_data_o,
            hdf3_data_o       => hdf3_data_o,
            
            ioctl_addr        => ioctl_addr,
            ioctl_data        => ioctl_data,
            ioctl_wr          => ioctl_wr,
            
            ioctl_ks_download   => ioctl_ks_download,
            ioctl_fdd_download  => ioctl_fdd_download,
            ioctl_hdf0_download => ioctl_hdf0_download,
            ioctl_hdf1_download => ioctl_hdf1_download,
            ioctl_hdf2_download => ioctl_hdf2_download,
            ioctl_hdf3_download => ioctl_hdf3_download,

            o_ks_sdram_addr     => s_ks_sdram_addr,
            o_ks_sdram_data_w   => s_ks_sdram_data_w,
            o_ks_sdram_we       => s_ks_sdram_we,

            o_vid_rgb_r         => s_vid_rgb_r,
            o_vid_rgb_g         => s_vid_rgb_g,
            o_vid_rgb_b         => s_vid_rgb_b,
            o_vid_hblank        => s_vid_hblank,
            o_vid_vblank        => s_vid_vblank
        );

    -- 3. INSTANZ: Die getaktete 114-MHz Speicherbrücke [14.1]
    u_sdram_bridge : sdram_bridge
        port map (
            clk_amiga       => clk_alice_14m,
            clk_sdram       => clk_sys, 
            reset           => reset,
            dec_sb_addr     => am_addr(26 downto 0), 
            dec_sb_req      => '1', 
            dec_sb_is_chip  => '0',
            
            am_data_in      => bus_cpu_to_chipset, -- Getrennte, unidirektionale Kanäle! [14.1]
            am_data_out     => bus_sdram_to_cpu,
            am_as_n         => am_as_n,
            am_ds_n         => am_ds_n,
            am_rw           => am_rw,
            am_siz0         => '0',
            am_siz1         => '0',
            am_dsack0_n     => open,
            am_dsack1_n     => open,
            
            i_ks_download   => ioctl_ks_download,
            i_ks_addr       => s_ks_sdram_addr,
            i_ks_data_w     => s_ks_sdram_data_w,
            i_ks_we         => s_ks_sdram_we,
            
            sdram_clk       => open, 
            sdram_data      => open,
            sdram_addr      => open,
            sdram_ba        => open,
            sdram_ras_n     => open,
            sdram_cas_n     => open,
            sdram_we_n      => open,
            sdram_dqm_lo    => open,
            sdram_dqm_hi    => open
        );

    -- =====================================================================
    -- KORREKTUR: REIN LOGISCHES TRI-STATE-STELLWERK (0 FEHLERHAFTE 'Z' INTERN) [14.1]
    -- =====================================================================
    -- CPU-Schreibdaten (Outbound) passiv an die internen Bus-Lanes koppeln
    bus_cpu_to_chipset <= am_data_local;

    -- Kombinatorischer Rücklese-Mux zur Turbokarte (Inbound) [14.1]
    am_data_local <= bus_sdram_to_cpu when (am_rw = '1' and am_addr(31 downto 24) = x"00") else
                     bus_chipset_to_cpu when (am_rw = '1') else 
                     (others => 'Z'); -- Hier ist 'Z' legal, da am_data_local an I/O pins gekoppelt ist [14.1]

    -- Speist die sanierten True-Color Videosignale direkt aus
    video_r <= s_vid_rgb_r;
    video_g <= s_vid_rgb_g;
    video_b <= s_vid_rgb_b;
    
    HBlank  <= s_vid_hblank;
    VBlank  <= s_vid_vblank;
    
    -- Statische Dummys für die Sync-Gatter
    HSync   <= '0'; 
    VSync   <= '0';

end Behavioral;
