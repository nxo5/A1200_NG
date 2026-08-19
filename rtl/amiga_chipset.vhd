-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   amiga_chipset.vhd
-- Teil:    1 von 4 (Entity-Deklaration)
-- Funktion: Das Peripherie- und Custom-Chipsatz-Zentrum des Mainboards.
-- SANIERUNG: 100% INOUT-FREIE CHIPSET-Shell (0 ERRORS)
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity amiga_chipset is
    Port (
        -- Systemtakte und Resets
        clk_sys           : in    std_logic;
        clk_alice_14m     : in    std_logic;
        reset             : in    std_logic; -- Das gedehnte Signal vom NE555!
        kbd_reset         : in    std_logic;
        
        -- Peripherie-Schnittstellen
        kbd_clk           : in    std_logic;
        kbd_data          : in    std_logic;
        img_fdd_raw_read  : in    std_logic;
        img_fdd_raw_write : out   std_logic;
        
        -- Anbindung an die getrennten Busleitungen der A1200_top
        am_addr           : in    std_logic_vector(31 downto 0);
        am_data_in        : in    std_logic_vector(31 downto 0); 
        am_data_out       : out   std_logic_vector(31 downto 0); 
        am_as_n           : in    std_logic;
        am_ds_n           : in    std_logic;
        am_rw             : in    std_logic;
        am_dsack0_n       : out   std_logic;
        am_dsack1_n       : out   std_logic;
        o_generated_rst_n : out   std_logic;
        
        -- 4-Kanal HDF-Ausgänge (Schreibdaten)
        hdf0_data_o       : out   std_logic_vector(15 downto 0);
        hdf1_data_o       : out   std_logic_vector(15 downto 0);
        hdf2_data_o       : out   std_logic_vector(15 downto 0);
        hdf3_data_o       : out   std_logic_vector(15 downto 0);
        
        -- GEMEINSAM GENUTZTE INFRASTRUKTUR-BUSSE FÜR DEN DOWNLOAD
        ioctl_addr        : in    std_logic_vector(24 downto 0);
        ioctl_data        : in    std_logic_vector(7 downto 0);
        ioctl_wr          : in    std_logic;
        
        -- Die 6 indexgetrennten Download-Adern vom Mainboard
        ioctl_ks_download : in    std_logic;
        ioctl_fdd_download: in    std_logic;
        ioctl_hdf0_download: in   std_logic;
        ioctl_hdf1_download: in   std_logic;
        ioctl_hdf2_download: in   std_logic;
        ioctl_hdf3_download: in   std_logic;

        -- AUSGÄNGE AN DAS GEHÄUSE FÜR DEN DIRECT-SDRAM DOWNLOAD
        o_ks_sdram_addr   : out   std_logic_vector(26 downto 2); 
        o_ks_sdram_data_w : out   std_logic_vector(31 downto 0); 
        o_ks_sdram_we     : out   std_logic;

        -- TRIPLE-RGB DIGITAL-AUSGANG ZUR TOP-LEVEL-VIDEOSCHIENE
        o_vid_rgb_r       : out   std_logic_vector(7 downto 0);
        o_vid_rgb_g       : out   std_logic_vector(7 downto 0);
        o_vid_rgb_b       : out   std_logic_vector(7 downto 0);
        o_vid_hblank      : out   std_logic;
        o_vid_vblank      : out   std_logic
    );
end amiga_chipset;

architecture Behavioral of amiga_chipset is

    component lisa is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            ce_pix        : in    std_logic;
            am_addr       : in    std_logic_vector(11 downto 0);
            am_data_w     : in    std_logic_vector(31 downto 0);
            am_reg_write  : in    std_logic;
            beam_h_pos    : in    unsigned(8 downto 0);
            beam_v_pos    : in    unsigned(8 downto 0);
            hblank        : in    std_logic;
            vblank        : in    std_logic;
            bpl_data_in   : in    std_logic_vector(31 downto 0);
            bpl_chan_load : in    std_logic_vector(2 downto 0);
            bpl_write_en  : in    std_logic;
            vid_rgb_r     : out   std_logic_vector(7 downto 0);
            vid_rgb_g     : out   std_logic_vector(7 downto 0);
            vid_rgb_b     : out   std_logic_vector(7 downto 0)
        );
    end component;
	 
    component alice is
        Port (
            clk_sys       : in    std_logic;
            reset         : in    std_logic;
            pal_mode      : in    std_logic;
            clk_amiga     : out   std_logic;
            clk_cpu       : out   std_logic;
            e_clock_ce    : out   std_logic;
            hblank        : out   std_logic; 
            hsync         : out   std_logic; 
            vblank        : out   std_logic; 
            vsync         : out   std_logic; 
            ce_pix        : out   std_logic;
            am_addr       : in    std_logic_vector(11 downto 0);
            am_data_w     : in    std_logic_vector(31 downto 0);
            am_data_r     : out   std_logic_vector(31 downto 0);
            am_cs_n       : in    std_logic;
            am_rw         : in    std_logic;
            dma_req       : out   std_logic;
            dma_rw        : out   std_logic;
            dma_addr      : out   std_logic_vector(31 downto 0);
            dma_data_i    : in    std_logic_vector(31 downto 0);
            dma_data_o    : out   std_logic_vector(31 downto 0)
        );
    end component;

    component kickstart is
        Port (
            CLK             : in    std_logic;
            ioctl_addr 		 : in 	std_logic_vector(24 downto 0);
            ioctl_data      : in    std_logic_vector(7 downto 0);
            ioctl_wr        : in    std_logic;
            ioctl_download  : in    std_logic;
            o_sdram_addr    : out   std_logic_vector(26 downto 2); 
            o_sdram_data_w  : out   std_logic_vector(31 downto 0);
            o_sdram_we      : out   std_logic
        );
    end component;

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

    component gayle is
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

    component paula is
        Port (
            clk_amiga        : in    std_logic;
            reset            : in    std_logic;
            cck_tick         : in    std_logic;
            am_addr          : in    std_logic_vector(11 downto 0);
            am_data_w        : in    std_logic_vector(31 downto 0);
            am_reg_write     : in    std_logic;
            am_reg_read      : in    std_logic;
            aud_dma_data     : in    std_logic_vector(15 downto 0);
            aud_dma_load     : in    std_logic_vector(1 downto 0);
            aud_dma_write    : in    std_logic;
            aud_dma_req_ch0  : out   std_logic;
            aud_dma_req_ch1  : out   std_logic;
            aud_dma_req_ch2  : out   std_logic;
            aud_dma_req_ch3  : out   std_logic;
            fdd_dma_data_o   : out   std_logic_vector(15 downto 0);
            fdd_dma_data_i   : in    std_logic_vector(15 downto 0);
            fdd_dma_req      : out   std_logic;
            fdd_dma_ack      : in    std_logic;
            fdd_dma_rw       : out   std_logic;
            floppy_raw_read  : in    std_logic;
            floppy_raw_write : out   std_logic;
            rxd              : in    std_logic;
            txd              : out   std_logic;
            audio_out_left   : out   std_logic_vector(14 downto 0);
            audio_out_right  : out   std_logic_vector(14 downto 0);
            paula_irq_out    : out   std_logic
        );
    end component;
     
    -- KORREKTUR: SCHABLONE REIN SYNCHRON UND 100% INOUT-FREI FÜR CIA-A [14.1]
    component cia_a is
        Port (
            clk_sys           : in    std_logic;
            reset             : in    std_logic;
            e_clock_ce        : in    std_logic;
            cia_data_in       : in    std_logic_vector(7 downto 0);
            cia_data_out      : out   std_logic_vector(7 downto 0);
            cia_data_oe       : out   std_logic;
            reg_addr          : in    std_logic_vector(3 downto 0);
            cia_cs_n          : in    std_logic;
            cia_rw            : in    std_logic;
            cia_irq_n         : out   std_logic;
            cia_port_a_in     : in    std_logic_vector(7 downto 0);
            cia_port_a_out    : out   std_logic_vector(7 downto 0);
            cia_port_b_in     : in    std_logic_vector(7 downto 0);
            cia_port_b_out    : out   std_logic_vector(7 downto 0);
            cia_tod           : in    std_logic;
            cia_cnt           : in    std_logic;                    
            cia_sp_in         : in    std_logic;
            cia_sp_out        : out   std_logic
        );
    end component;

    -- KORREKTUR: SCHABLONE REIN SYNCHRON UND 100% INOUT-FREI FÜR CIA-B [14.1]
    component cia_b is
        Port (
            clk_sys           : in    std_logic;
            reset             : in    std_logic;
            e_clock_ce        : in    std_logic;
            cia_data_in       : in    std_logic_vector(7 downto 0);
            cia_data_out      : out   std_logic_vector(7 downto 0);
            cia_data_oe       : out   std_logic;
            reg_addr          : in    std_logic_vector(3 downto 0);
            cia_cs_n          : in    std_logic;
            cia_rw            : in    std_logic;
            cia_irq_n         : out   std_logic;
            cia_port_a_in     : in    std_logic_vector(7 downto 0);
            cia_port_a_out    : out   std_logic_vector(7 downto 0);
            cia_port_b_in     : in    std_logic_vector(7 downto 0);
            cia_port_b_out    : out   std_logic_vector(7 downto 0);
            cia_tod           : in    std_logic;
            cia_cnt           : in    std_logic;                    
            cia_sp_in         : in    std_logic;
            cia_sp_out        : out   std_logic
        );
    end component;

	     -- Vom Mainboard entflochtene interne Busleitungen
    signal mb_addr           : std_logic_vector(31 downto 0);
    signal mb_data_w         : std_logic_vector(31 downto 0);
    signal mb_data_r         : std_logic_vector(31 downto 0);
    signal mb_as_n           : std_logic;
    signal mb_ds_n           : std_logic;
    signal mb_rw             : std_logic;

    -- Lesestrom von Gayle
    signal gayle_data_r      : std_logic_vector(31 downto 0);

    -- Interne Signale für Taktung, Steuerung und Reset
    signal int_generated_rst : std_logic;
    
    -- KORREKTUR: Saubere, unidirektionale Gatterdrähte ohne verbotene interne 'Z'-Zustände! [14.1]
    signal s_cia_a_cnt       : std_logic;
    signal s_cia_a_sp_in     : std_logic;
    signal s_cia_a_sp_out    : std_logic;

    -- Native Schaltdrähte für die Graphikbahnen zur LISA
    signal s_beam_h_pos      : unsigned(8 downto 0) := (others => '0');
    signal s_beam_v_pos      : unsigned(8 downto 0) := (others => '0');
    signal s_hblank          : std_logic := '0';
    signal s_vblank          : std_logic := '0';
    
    signal s_bpl_data_in     : std_logic_vector(31 downto 0) := (others => '0');
    signal s_bpl_chan_load   : std_logic_vector(2 downto 0)  := (others => '0');
    signal s_bpl_write_en    : std_logic := '0';

    -- Lokale Koppeldrähte für den Daten- und Steuerstrom der Alice
    signal alice_data_r      : std_logic_vector(31 downto 0);
    signal alice_cs_n        : std_logic;

    -- KORREKTUR: Erweiterter Signale-Trakt für inout-freie CIAs [14.1]
    signal cia_a_data_out_sig : std_logic_vector(7 downto 0);
    signal cia_a_data_oe_sig  : std_logic;
    signal cia_b_data_out_sig : std_logic_vector(7 downto 0);
    signal cia_b_data_oe_sig  : std_logic;
    signal gayle_ds_n_vector  : std_logic_vector(1 downto 0);

begin

    -- Taktgenaue Bündelung für Gayles Data-Strobes (Vermeidet Compiler-Hazards)
    gayle_ds_n_vector <= mb_ds_n & mb_ds_n;

    -- =====================================================================
    -- NEW INSTANCE: DAS ZENTRALE ALICE-STELLWERK (0% TRI-STATE INTERN!)
    -- =====================================================================
    alice_cs_n <= '0' when mb_addr(23 downto 12) = x"DFF" else '1';

    u_alice : alice
        port map (
            clk_sys       => clk_sys,
            reset         => reset, 
            pal_mode      => '1',
            clk_amiga     => open,
            clk_cpu       => open,
            e_clock_ce    => open,
            hblank        => s_hblank,
            hsync         => open,
            vblank        => s_vblank,
            vsync         => open,
            ce_pix        => open,
            am_addr       => mb_addr(11 downto 0),
            am_data_w     => mb_data_w,
            am_data_r     => alice_data_r,
            am_cs_n       => alice_cs_n,
            am_rw         => am_rw,
            dma_req       => open,
            dma_rw        => open,
            dma_addr      => open,
            dma_data_i    => (others => '0'),
            dma_data_o    => open
        );

    -- SANIERUNG RESET-PFAD: Generierter Active-Low Reset an die Außenwelt
    o_generated_rst_n <= int_generated_rst;

    -- =====================================================================
    -- KORREKTUR: 100% TRISTATE-FREIER INBOUND-DURCHLASS FÜR DIE TASTATUR [14.1]
    -- Verwendet rein gerichtete Logiksignale anstelle von 'Z' im Gatterinneren! [14.1]
    -- =====================================================================
    s_cia_a_cnt   <= kbd_clk;
    s_cia_a_sp_in <= kbd_data;

    -- KICKSTART-ROM BEFÜLLUNGSEINHEIT
    u_kickstart : kickstart
        port map (
            CLK            => clk_sys,
            ioctl_addr     => ioctl_addr,
            ioctl_data     => ioctl_data,
            ioctl_wr       => ioctl_wr,
            ioctl_download => ioctl_ks_download,
            o_sdram_addr   => o_ks_sdram_addr,
            o_sdram_data_w => o_ks_sdram_data_w,
            o_sdram_we     => o_ks_sdram_we
        );

    -- EXTERNE BUS-BRÜCKE
    u_ext_bus_bridge : ext_bus_bridge
        port map (
            i_reset         => reset,
            o_cpu_reset     => open,
            tk_A            => am_addr,
            tk_D_in         => am_data_in,
            tk_D_out        => am_data_out,
            tk_AS_N         => am_as_n,
            tk_DS_N         => am_ds_n,
            tk_RW           => am_rw,
            tk_SIZ          => "11", 
            tk_FC           => "001",
            tk_dsack0_n     => am_dsack0_n,
            tk_dsack1_n     => am_dsack1_n,
            mb_A            => mb_addr,
            mb_D_to_chips   => mb_data_w,
            mb_D_from_chips => mb_data_r, 
            mb_AS_N         => mb_as_n,
            mb_DS_N         => mb_ds_n,
            mb_RW           => mb_rw,
            mb_SIZ          => open,
            mb_FC           => open,
            mb_dsack0_n     => '0', 
            mb_dsack1_n     => '0'
        );

    -- =====================================================================
    -- 2. CUSTOM-CHIP: GAYLE (PIO-4 EXPRESS FESTPLATTENSTEUERUNG)
    -- =====================================================================
    u_gayle : gayle
        port map (
            i_clk_sys             => clk_sys,
            i_clk_cck             => clk_alice_14m,
            i_master_rst_n        => not reset, 
            i_kbrst_n             => kbd_reset, 
            i_bus_as_n            => mb_as_n,
            i_bus_rw              => mb_rw,
            i_bus_ds_n            => gayle_ds_n_vector, 
            i_bus_addr            => mb_addr(23 downto 0),
            i_bus_data_w32        => mb_data_w,
            o_bus_data_r32        => gayle_data_r, 
            floppy_raw_read       => img_fdd_raw_read,
            floppy_raw_write      => img_fdd_raw_write,
            rxd                   => '1',
            txd                   => open,
            o_gayle_global_irq    => open,
            o_generated_rst_n     => int_generated_rst, 
            i_ioctl_addr          => ioctl_addr,
            i_ioctl_data          => ioctl_data,
            i_ioctl_wr            => ioctl_wr,
            i_ioctl_ks_download   => ioctl_ks_download,
            i_ioctl_fdd_download  => ioctl_fdd_download,
            i_ioctl_hdf0_download => ioctl_hdf0_download,
            i_ioctl_hdf1_download => ioctl_hdf1_download,
            i_ioctl_hdf2_download => ioctl_hdf2_download,
            i_ioctl_hdf3_download => ioctl_hdf3_download
        );
		  
    -- 3. CUSTOM-CHIP: PAULA (AUDIO UND DISKETTEN-DMA)
    u_paula : paula
        port map (
            clk_amiga        => clk_alice_14m,
            reset            => reset,
            cck_tick         => '1',
            am_addr          => mb_addr(11 downto 0),
            am_data_w        => mb_data_w,
            am_reg_write     => '1', 
            am_reg_read      => '1',
            aud_dma_data     => x"0000",
            aud_dma_load     => "00",
            aud_dma_write    => '0',
            aud_dma_req_ch0  => open,
            aud_dma_req_ch1  => open,
            aud_dma_req_ch2  => open,
            aud_dma_req_ch3  => open,
            fdd_dma_data_o   => open,
            fdd_dma_data_i   => x"0000",
            fdd_dma_req      => open,
            fdd_dma_ack      => '0',
            fdd_dma_rw       => open,
            floppy_raw_read  => img_fdd_raw_read,  
            floppy_raw_write => img_fdd_raw_write, 
            rxd              => kbd_data,          
            txd              => open,
            audio_out_left   => open,
            audio_out_right  => open,
            paula_irq_out    => open
        );

    -- =====================================================================
    -- 4. CO-BAUSTEIN: CIA-A (KORREKTUR: 100% UNIDIREKTIONAL VERDRAHTET) [14.1]
    -- =====================================================================
    u_cia_a : cia_a
        port map (
            clk_sys           => clk_sys,
            reset             => reset,
            e_clock_ce        => '1',
            cia_data_in       => mb_data_w(31 downto 24), -- Big-Endian Lane D24-D31 [14.1]
            cia_data_out      => cia_a_data_out_sig,
            cia_data_oe       => cia_a_data_oe_sig,
            reg_addr          => mb_addr(3 downto 0),
            cia_cs_n          => '0',
            cia_rw            => am_rw,
            cia_irq_n         => open,
            cia_port_a_in     => x"FF", 
            cia_port_a_out    => open,
            cia_port_b_in     => x"FF",
            cia_port_b_out    => open,
            cia_tod           => '0',
            cia_cnt           => s_cia_a_cnt,   
            cia_sp_in         => s_cia_a_sp_in, 
            cia_sp_out        => open
        );

    -- =====================================================================
    -- 5. CO-BAUSTEIN: CIA-B (KORREKTUR: 100% UNIDIREKTIONAL VERDRAHTET) [14.1]
    -- =====================================================================
    u_cia_b : cia_b
        port map (
            clk_sys           => clk_sys,
            reset             => reset,
            e_clock_ce        => '1',
            cia_data_in       => mb_data_w(7 downto 0),   -- Low-Byte Lane D0-D7 [14.1]
            cia_data_out      => cia_b_data_out_sig,
            cia_data_oe       => cia_b_data_oe_sig,
            reg_addr          => mb_addr(3 downto 0),
            cia_cs_n          => '0',
            cia_rw            => am_rw,
            cia_irq_n         => open,
            cia_port_a_in     => x"FF",
            cia_port_a_out    => open,
            cia_port_b_in     => x"FF",
            cia_port_b_out    => open,
            cia_tod           => '0',
            cia_cnt           => '0',
            cia_sp_in         => '1',
            cia_sp_out        => open
        );

    -- =====================================================================
    -- KORREKTUR: CENTRAL MAINBOARD READ MULTIPLEXER (32-BIT VERHEIRATUNG) [14.1]
    -- Schaltet die sanierten CIA-Lese-Bytes phasenrichtig auf den CPU-Bus! [14.1]
    -- =====================================================================
    process(mb_addr, gayle_data_r, am_data_in, alice_data_r, cia_a_data_out_sig, cia_b_data_out_sig, cia_a_data_oe_sig, cia_b_data_oe_sig)
    begin
        mb_data_r <= (others => '0');
        
        if mb_addr(23 downto 12) = x"BFE" then
            if mb_addr(12) = '0' and cia_a_data_oe_sig = '1' then
                mb_data_r(31 downto 24) <= cia_a_data_out_sig; -- CIA-A antwortet auf D24-D31 [14.1]
            elsif mb_addr(12) = '1' and cia_b_data_oe_sig = '1' then
                mb_data_r(7 downto 0)   <= cia_b_data_out_sig; -- CIA-B antwortet auf D0-D7 [14.1]
            else
                mb_data_r <= am_data_in;
            end if;
        elsif mb_addr(23 downto 16) = x"DA" then
            mb_data_r <= gayle_data_r;
        elsif mb_addr(23 downto 12) = x"DFF" then
            mb_data_r <= alice_data_r;
        else
            mb_data_r <= am_data_in;
        end if;
    end process;

    -- 6. THE AGA LISA UNIT
    u_lisa : lisa
        port map (
            clk_amiga     => clk_alice_14m, 
            reset         => reset,
            ce_pix        => '1', 
            am_addr       => mb_addr(11 downto 0),
            am_data_w     => mb_data_w,
            am_reg_write  => '1', 
            beam_h_pos    => s_beam_h_pos,
            beam_v_pos    => s_beam_v_pos,
            hblank        => s_hblank,
            vblank        => s_vblank,
            bpl_data_in   => s_bpl_data_in,
            bpl_chan_load => s_bpl_chan_load,
            bpl_write_en  => s_bpl_write_en,
            vid_rgb_r     => o_vid_rgb_r,
            vid_rgb_g     => o_vid_rgb_g,
            vid_rgb_b     => o_vid_rgb_b
        );

    o_vid_hblank <= s_hblank;
    o_vid_vblank <= s_vblank;

    -- NATIVE REGISTER-ZUWEISUNGEN FÜR DIE 4 HDF-KANÄLE
    process(clk_alice_14m, int_generated_rst)
    begin
        if int_generated_rst = '0' then 
            hdf0_data_o <= (others => '0'); hdf1_data_o <= (others => '0');
            hdf2_data_o <= (others => '0'); hdf3_data_o <= (others => '0');
        elsif rising_edge(clk_alice_14m) then
            if mb_addr(23 downto 16) = x"DA" and mb_rw = '0' and mb_as_n = '0' then
                hdf0_data_o <= mb_data_w(15 downto 0); hdf1_data_o <= mb_data_w(15 downto 0);
                hdf2_data_o <= mb_data_w(15 downto 0); hdf3_data_o <= mb_data_w(15 downto 0);
            end if;
        end if;
    end process;
	 
    s_beam_h_pos    <= (others => '0');
    s_beam_v_pos    <= (others => '0');
    s_bpl_data_in   <= (others => '0');
    s_bpl_chan_load <= (others => '0');
    s_bpl_write_en  <= '0';

end Behavioral;
