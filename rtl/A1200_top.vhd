-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   A1200_top.vhd
-- Teil:    1.A (Die Hauptplatine-Pforte und Framework-Entity)
-- Funktion: Das Haupt-Mainboard (Top-Level-Entity) des Gesamtsystems.
-- SANIERUNG Schritt 67 - DEZENTRALE RESET-STRUKTUR (0 ERRORS):
--   - Die Schnittstellenports werden stabil deklariert. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity A1200_top is
    Port (
        -- 1. CLOCK-, RESET- UND SYSTEMLEITUNGEN VOM MISTER
        clk_sys           : in    std_logic; 
        reset             : in    std_logic; -- Das gedehnte Signal vom NE555! [14.1]
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

    component ext_bus_bridge is
        Port (
				i_reset         : in    std_logic;                      
            o_cpu_reset     : out   std_logic;	
		  
            tk_A            : in    std_logic_vector(31 downto 0);
            tk_D_in         : in    std_logic_vector(31 downto 0);
            tk_D_out        : out   std_logic_vector(31 downto 0);
            tk_AS_N         : in    std_logic;
            tk_DS_N         : in    std_logic;
            tk_RW           : in    std_logic;
            tk_SIZ          : in    std_logic_vector(1 downto 0);
            tk_FC           : in    std_logic_vector(2 downto 0);
            tk_dsack0_n     : out   std_logic;
            tk_dsack1_n     : out   std_logic;

            mb_A            : out   std_logic_vector(31 downto 0);
            mb_D_to_chips   : out   std_logic_vector(31 downto 0);
            mb_D_from_chips : in    std_logic_vector(31 downto 0);
            mb_AS_N         : out   std_logic;
            mb_DS_N         : out   std_logic;
            mb_RW           : out   std_logic;
            mb_SIZ          : out   std_logic_vector(1 downto 0);
            mb_FC           : out   std_logic_vector(2 downto 0);
            mb_dsack0_n     : in    std_logic;
            mb_dsack1_n     : in    std_logic
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
            
            ioctl_ks_download   : in    std_logic;
            ioctl_fdd_download  : in    std_logic;
            ioctl_hdf0_download : in    std_logic;
            ioctl_hdf1_download : in    std_logic;
            ioctl_hdf2_download : in    std_logic;
            ioctl_hdf3_download : in    std_logic;

            o_ks_sdram_addr     : out   std_logic_vector(26 downto 2);
            o_ks_sdram_data_w   : out   std_logic_vector(31 downto 0);
            o_ks_sdram_we       : out   std_logic;

            o_vid_rgb_r         : out   std_logic_vector(7 downto 0);
            o_vid_rgb_g         : out   std_logic_vector(7 downto 0);
            o_vid_rgb_b         : out   std_logic_vector(7 downto 0);
            o_vid_hblank        : out   std_logic;
            o_vid_vblank        : out   std_logic
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

    -- Das übergeordnete Adress- und Kontrollnetzwerk des Mainboards
    signal clk_alice_14m     : std_logic;
    signal am_addr           : std_logic_vector(31 downto 0);
    signal am_as_n           : std_logic;
    signal am_ds_n           : std_logic;
    signal am_rw             : std_logic;
    signal am_dsack0_n       : std_logic;
    signal am_dsack1_n       : std_logic;

    -- Rein unidirektionale Bussachienen
    signal bus_mb_to_periph   : std_logic_vector(31 downto 0); 
    signal bus_periph_to_mb   : std_logic_vector(31 downto 0); 
    signal bus_chipset_to_cpu : std_logic_vector(31 downto 0); 
    signal bus_sdram_to_cpu   : std_logic_vector(31 downto 0); 

    -- Interne Koppeldrähte für das SDRAM-Lade-Handshake
    signal s_ks_sdram_addr   : std_logic_vector(26 downto 2);
    signal s_ks_sdram_data_w : std_logic_vector(31 downto 0);
    signal s_ks_sdram_we     : std_logic;

    -- Interne Graphikbahnen für die True-Color-Ausleitung
    signal s_vid_rgb_r       : std_logic_vector(7 downto 0);
    signal s_vid_rgb_g       : std_logic_vector(7 downto 0);
    signal s_vid_rgb_b       : std_logic_vector(7 downto 0);
    signal s_vid_hblank      : std_logic;
    signal s_vid_vblank      : std_logic;

    -- Native Struct-Komponenten für die Synchron-Zellen
    signal r_clk_div_cnt     : unsigned(1 downto 0) := (others => '0');
    signal s_ce_14m          : std_logic;
	 
	 signal s_ram_reset       : std_logic; 

	 begin

    -- =========================================================================
    -- SAUBERER SYNCHRON-TEILER: TAKTET JEDEN VIERTEN IMPULS DER PLL!
    -- =========================================================================
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            r_clk_div_cnt <= r_clk_div_cnt + 1;
        end if;
    end process;
    
    s_ce_14m      <= '1' when r_clk_div_cnt = "11" else '0';
    ce_pix        <= s_ce_14m; 
    clk_alice_14m <= clk_sys; 

    -- =========================================================================
    -- 1. INSTANZ: DIE MODULARE STECKPLATZ-BRÜCKE (AUSTAUSCH-SCHARNIER)
    -- =========================================================================
    u_ext_bus_bridge : ext_bus_bridge
        port map (
				i_reset         => reset, 
            o_cpu_reset     => open,
		  
            tk_A            => (others => '0'),
            tk_D_in         => (others => '0'),
            tk_D_out        => open,
            tk_AS_N         => '1',
            tk_DS_N         => '1',
            tk_RW           => '1',
            tk_SIZ          => "11", 
            tk_FC           => "001",
            tk_dsack0_n     => open,
            tk_dsack1_n     => open,

            mb_A            => am_addr,
            mb_D_to_chips   => bus_mb_to_periph, 
            mb_D_from_chips => bus_periph_to_mb, 
            mb_AS_N         => am_as_n,
            mb_DS_N         => am_ds_n,
            mb_RW           => am_rw,
            mb_SIZ          => open,
            mb_FC           => open,
            mb_dsack0_n     => am_dsack0_n,
            mb_dsack1_n     => am_dsack1_n
        );

    -- =========================================================================
    -- 2. INSTANZ: DER CUSTOM-CHIPSATZ (MIT INTEGRIERTER AGA LISA)
    -- REPARIERT: Nutzt starr das unnachgiebig lange NE555-Reset-Signal! [14.1]
    -- =========================================================================
    u_amiga_chipset : amiga_chipset
        port map (
            clk_sys           => clk_sys,
            clk_alice_14m     => clk_alice_14m,
            reset             => reset, -- Das 250ms gedehnte Hardwarereset vom NE555! [14.1]
            kbd_reset         => kbd_reset,
            kbd_clk           => kbd_clk,
            kbd_data          => kbd_data,
            img_fdd_raw_read  => img_fdd_raw_read,
            img_fdd_raw_write => img_fdd_raw_write,
            
            am_addr           => am_addr,
            am_data_in        => bus_mb_to_periph, 
            am_data_out       => bus_chipset_to_cpu,
            am_as_n           => am_as_n,
            am_ds_n           => am_ds_n,
            am_rw             => am_rw,
            am_dsack0_n       => am_dsack0_n,
            am_dsack1_n       => am_dsack1_n,
            o_generated_rst_n => open,
            
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

    -- =========================================================================
    -- RAM-RESET-KOPPLUNG: ENTROSTET DEN DOWNLOAD-PFAD
    -- Schützt den RAM-Controller vor der 250ms-Blockade während IOCTL-Ladevorgängen.
    -- Erlaubt den RAM-Reset nur, wenn kein Kickstart-ROM-Download aktiv ist! [14.1]
    -- =========================================================================
    s_ram_reset <= '0' when ioctl_ks_download = '1' else reset;

    -- =========================================================================
    -- 3. INSTANZ: DIE GETAKTETE SPEICHERBRÜCKE (SDRAM-INTERFACE)
    -- REPARIERT: Gekoppelt an s_ram_reset für stoßfreie Downloads [14.1]
    -- =========================================================================
    u_sdram_bridge : sdram_bridge
        port map (
            clk_amiga       => clk_alice_14m,
            clk_sdram       => clk_sys, 
            reset           => s_ram_reset, -- Entkoppeltes Reset-Signal! [14.1]
            dec_sb_addr     => am_addr(26 downto 0), 
            dec_sb_req      => '1', 
            dec_sb_is_chip  => '0',
            
            am_data_in      => bus_mb_to_periph, 
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

    -- =========================================================================
    -- REIN UNIDIREKTIONALER LESE-MULTIPLEXER
    -- =========================================================================
    bus_periph_to_mb <= bus_sdram_to_cpu   when (am_rw = '1' and am_addr(31 downto 24) = x"00") else
                        bus_chipset_to_cpu when (am_rw = '1') else 
                        (others => '0'); 

    -- =========================================================================
    -- NATIVE SYNC-REKONSTRUKTION FÜR DEN AMIGA-MODUS [14.1]
    -- =========================================================================
    HSync <= '0' when s_vid_hblank = '1' else '1';
    VSync <= '0' when s_vid_vblank = '1' else '1';

    video_r <= s_vid_rgb_r;
    video_g <= s_vid_rgb_g;
    video_b <= s_vid_rgb_b;
    HBlank  <= s_vid_hblank;
    VBlank  <= s_vid_vblank;

end Behavioral;
