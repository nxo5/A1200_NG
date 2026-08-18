-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle.vhd
-- Teil:    1 von 2 (Geöffnete Gehäusepforte & Komponentenschablonen)
-- Funktion: Das strukturelle Gehäuse (Shell) des Gayle-Chips.
-- SANIERUNG OSD-WEICHE:
--   - Öffnung der Haupt-Entity für die 6 indexgetrennten ioctl_*-Downloadflags! [14.1]
--   - Deklaration der neuen Komponente gayle_ide_bram im Kopfbereich. [14.1]
--   - Tilgt alle verbleibenden "Port does not exist" Warnungen an Gayle. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle is
    Port (
        -- =============================================================
        -- 1. CLOCK-, RESET- UND TIMING-EINGÄNGE (VON ALICE)
        -- =============================================================
        i_clk_sys         : in    std_logic; -- 14,18 MHz Systemtakt von Alice [14.1]
        i_clk_cck         : in    std_logic; -- 3,54 MHz Color-Clock von Alice [14.1]
        i_master_rst_n    : in    std_logic; -- Globaler Power-On Reset (aktiv niedrig) [14.1]
        i_kbrst_n         : in    std_logic; -- Tastatur-Reset-Ader (aktiv niedrig) [14.1]
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM GEMEINSAMEN INTERNEN CPU-BUS
        -- =============================================================
        i_bus_as_n        : in    std_logic; -- Address Strobe [14.1]
        i_bus_rw          : in    std_logic; -- Read (1) / Write (0) [14.1]
        i_bus_ds_n        : in    std_logic_vector(1 downto 0); -- Data Strobes
        i_bus_addr        : in    std_logic_vector(23 downto 0); -- System-Adressbus (A23..A0) [14.1]
        i_bus_data_w32    : in    std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten von der CPU
        o_bus_data_r32    : out   std_logic_vector(31 downto 0); -- 32-Bit Lesedaten zurück zur CPU [14.1]
        
        -- =============================================================
        -- 3. PHYSISCHE PERIPHERIE-PINS NACH AUSSEN (HARDWARE-PORTS)
        -- =============================================================
        floppy_raw_read   : in    std_logic; -- MFM-Strom von der Floppy
        floppy_raw_write  : out   std_logic; -- MFM-Strom zur Floppy
        rxd               : in    std_logic; -- Serielles RX
        txd               : out   std_logic; -- Serielles TX
        
        -- =============================================================
        -- 4. SYSTEMWEITE ALARM- UND RESET-REAKTIONEN
        -- =============================================================
        o_gayle_global_irq: out   std_logic; -- Zusammengefasster Interrupt (INT2) an Alice [14.1]
        o_generated_rst_n : out   std_logic; -- Der gestreckte/sanierten System-Reset [14.1]
        
        -- =============================================================
        -- 5. KORREKTUR-EINGÄNGE: MISTER IOCTL INTERFACE (VOM MAINBOARD) [14.1]
        -- =============================================================
        i_ioctl_addr        : in    std_logic_vector(24 downto 0);
        i_ioctl_data        : in    std_logic_vector(7 downto 0);
        i_ioctl_wr          : in    std_logic;
        
        -- Die 6 indexgetrennten Downloadflags von deiner OSD-Weiche [14.1]
        i_ioctl_ks_download : in    std_logic;
        i_ioctl_fdd_download: in    std_logic;
        i_ioctl_hdf0_download: in   std_logic;
        i_ioctl_hdf1_download: in   std_logic;
        i_ioctl_hdf2_download: in   std_logic;
        i_ioctl_hdf3_download: in   std_logic
    );
end gayle;

architecture structural of gayle is

    -- =========================================================================
    -- NEW COMPONENT: DER SYNCHRONE M10K-SEKTORPUFFER (UNSER STABILITÄTSKERN) [14.1]
    -- =========================================================================
    component gayle_ide_bram is
        Port (
            i_clk_sys             : in    std_logic;
            i_ioctl_addr          : in    std_logic_vector(24 downto 0);
            i_ioctl_data          : in    std_logic_vector(7 downto 0);
            i_ioctl_wr            : in    std_logic;
            i_ioctl_hdf0_download : in    std_logic;
            i_ioctl_hdf1_download : in    std_logic;
            i_ioctl_hdf2_download : in    std_logic;
            i_ioctl_hdf3_download : in    std_logic;
            i_clk_amiga           : in    std_logic;
            i_am_hdf_sel          : in    std_logic_vector(1 downto 0);
            i_am_sector_addr      : in    std_logic_vector(8 downto 0);
            o_am_data_out         : out   std_logic_vector(7 downto 0)
        );
    end component;

    -- =========================================================================
    -- STANDARD UNTERMODULE-SCHABLONEN
    -- =========================================================================
    component gayle_regs is
        Port (
            i_clk_sys    : in  std_logic;
            i_clk_cck    : in  std_logic;
            i_rst_n      : in  std_logic;
            i_as_n       : in  std_logic;
            i_rw         : in  std_logic;
            i_reg_addr   : in  std_logic_vector(15 downto 0);
            i_reg_data   : in  std_logic_vector(7 downto 0);
            o_reg_data   : out std_logic_vector(7 downto 0);
            i_ide_irq    : in  std_logic;
            i_pcmcia_irq : in  std_logic;
            o_gayle_irq  : out std_logic
        );
    end component;

	     component gayle_ide is
        Port (
            i_clk_sys           : in  std_logic;
            i_rst_n             : in  std_logic;
            i_as_n              : in  std_logic;
            i_rw                : in  std_logic;
            i_ds_n              : in  std_logic_vector(1 downto 0);
            i_ide_addr          : in  std_logic_vector(5 downto 0);
            i_ide_data          : in  std_logic_vector(15 downto 0);
            o_ide_data          : out std_logic_vector(15 downto 0);
            o_ide_irq           : out std_logic;
            o_bram_hdf_sel      : out std_logic_vector(1 downto 0);
            o_bram_sector_addr  : out std_logic_vector(8 downto 0);
            i_bram_data         : in  std_logic_vector(7 downto 0)
        );
    end component;

    component gayle_pcmcia is
        Port (
            i_clk_sys      : in  std_logic;
            i_rst_n        : in  std_logic;
            i_as_n         : in  std_logic;
            i_rw           : in  std_logic;
            i_pcm_addr     : in  std_logic_vector(15 downto 0);
            i_pcm_data     : in  std_logic_vector(7 downto 0);
            o_pcm_data     : out std_logic_vector(7 downto 0);
            o_pcmcia_irq   : out std_logic
        );
    end component;

    component gayle_reset is
        Port (
            i_clk_sys       : in  std_logic;
            i_clk_cck       : in  std_logic;
            i_rst_n         : in  std_logic;
            i_kbrst_n       : in  std_logic;
            o_sys_rst_n     : out std_logic
        );
    end component;

    -- Interne Signalkoppelungen
    signal s_ide_irq         : std_logic;
    signal s_pcmcia_irq      : std_logic;
    signal s_generated_rst_n : std_logic;
    
    signal s_data_from_regs   : std_logic_vector(7 downto 0);
    signal s_data_from_ide    : std_logic_vector(15 downto 0);
    signal s_data_from_pcmcia : std_logic_vector(7 downto 0);

    -- Neue Koppeldrähte zum HDF-Sektorpuffer [14.1]
    signal s_am_hdf_sel       : std_logic_vector(1 downto 0) := "00";
    signal s_am_sector_addr   : std_logic_vector(8 downto 0) := (others => '0');
    signal s_bram_data_out    : std_logic_vector(7 downto 0);

begin

    -- Den intern generierten System-Reset an die Gehäusepforte ausgeben
    o_generated_rst_n <= s_generated_rst_n;

    -- =========================================================================
    -- DATA ROUTING MULTIPLEXER (CPU BUS-LESEZUGRIFF)
    -- =========================================================================
    process(i_bus_as_n, i_bus_rw, i_bus_addr, s_data_from_regs, s_data_from_ide, s_data_from_pcmcia)
    begin
        o_bus_data_r32 <= (others => '1'); -- Offener Amiga-Bus liefert standardmäßig High-Pegel
        
        if i_bus_as_n = '0' and i_bus_rw = '1' then
            if i_bus_addr(23 downto 16) = x"DA" then
                case i_bus_addr(15 downto 12) is
                    when x"0" | x"1" | x"2" | x"3" =>
                        o_bus_data_r32(15 downto 0) <= s_data_from_ide;
                    when x"8" | x"9" | x"A" | x"B" =>
                        o_bus_data_r32(7 downto 0) <= s_data_from_regs;
                    when others =>
                        o_bus_data_r32(7 downto 0) <= s_data_from_pcmcia;
                end case;
            elsif i_bus_addr(23 downto 16) = x"DE" then
                o_bus_data_r32(7 downto 0) <= s_data_from_pcmcia;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- NEW INSTANCE 5: DER SYNCHRONE M10K-SEKTORPUFFER (FÜR DIE 4 HDF-IMAGES) [14.1]
    -- =========================================================================
    u_gayle_ide_bram : gayle_ide_bram
        port map (
            -- Port A: Framework-Schreibseite (SD-Karte befüllt das RAM) [14.1]
            i_clk_sys             => i_clk_sys,
            i_ioctl_addr          => i_ioctl_addr,
            i_ioctl_data          => i_ioctl_data,
            i_ioctl_wr            => i_ioctl_wr,
            i_ioctl_hdf0_download => i_ioctl_hdf0_download,
            i_ioctl_hdf1_download => i_ioctl_hdf1_download,
            i_ioctl_hdf2_download => i_ioctl_hdf2_download,
            i_ioctl_hdf3_download => i_ioctl_hdf3_download,
            
            -- Port B: Amiga-Leseseite (Gayle-Kopplung) [14.1]
            i_clk_amiga           => i_clk_sys, -- Arbeitet synchron im 14-MHz-Taktnetz von Alice
            i_am_hdf_sel          => s_am_hdf_sel,
            i_am_sector_addr      => s_am_sector_addr,
            o_am_data_out         => s_bram_data_out
        );

    -- =========================================================================
    -- INSTANZEN DER REGULÄREN UNTERMODULE
    -- =========================================================================

    -- 1. Register-Verwaltung
    u_gayle_regs : gayle_regs
        port map (
            i_clk_sys    => i_clk_sys,
            i_clk_cck    => i_clk_cck,
            i_rst_n      => s_generated_rst_n,
            i_as_n       => i_bus_as_n,
            i_rw         => i_bus_rw,
            i_reg_addr   => i_bus_addr(15 downto 0),
            i_reg_data   => i_bus_data_w32(7 downto 0),
            o_reg_data   => s_data_from_regs,
            i_ide_irq    => s_ide_irq,
            i_pcmcia_irq => s_pcmcia_irq,
            o_gayle_irq  => o_gayle_global_irq
        );

    -- 2. IDE/ATA-Controller (PIO-4)
    -- INSTANZ-UPGRADE: Schließt die Gatter-Kopplung zum BRAM fehlerfrei! [14.1]
    u_gayle_ide : gayle_ide
        port map (
            i_clk_sys          => i_clk_sys,
            i_rst_n            => s_generated_rst_n,
            i_as_n             => i_bus_as_n,
            i_rw               => i_bus_rw,
            i_ds_n             => i_bus_ds_n,
            i_ide_addr         => i_bus_addr(5 downto 0),
            i_ide_data         => i_bus_data_w32(15 downto 0),
            o_ide_data         => s_data_from_ide,
            o_ide_irq          => s_ide_irq,
            o_bram_hdf_sel     => s_am_hdf_sel,
            o_bram_sector_addr => s_am_sector_addr,
            i_bram_data        => s_bram_data_out
        );

    -- 3. PCMCIA-Schnittstelle
    u_gayle_pcmcia : gayle_pcmcia
        port map (
            i_clk_sys    => i_clk_sys,
            i_rst_n      => s_generated_rst_n,
            i_as_n       => i_bus_as_n,
            i_rw         => i_bus_rw,
            i_pcm_addr   => i_bus_addr(15 downto 0),
            i_pcm_data   => i_bus_data_w32(7 downto 0),
            o_pcm_data   => s_data_from_pcmcia,
            o_pcmcia_irq => s_pcmcia_irq
        );

    -- 4. Reset-Logik
    u_gayle_reset : gayle_reset
        port map (
            i_clk_sys    => i_clk_sys,
            i_clk_cck    => i_clk_cck,
            i_rst_n      => i_master_rst_n,
            i_kbrst_n    => i_kbrst_n,
            o_sys_rst_n  => s_generated_rst_n
        );
		  
	 -- =========================================================================
    -- KORREKTUR FULL-FIX: FESTE LOGIK-TREIBER GEGEN WARNING 10541 [14.1]
    -- Verriegelt die offenen Platinen-Adern auf sichere Standardwerte, [14.1]
    -- damit sie der Fitter materialschonend und fehlerfrei einlastet! [14.1]
    -- =========================================================================
    floppy_raw_write <= '0'; -- Floppy-Schreibspur im Ruhezustand inaktiv halten
    txd              <= '1'; -- RS232-Übertragungsleitung im Leerlauf standardmäßig High (Idle-Pegel)
	 
end structural;
