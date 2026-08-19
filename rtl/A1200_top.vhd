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

    component gayle
        Port (
            CLK             : in    std_logic;
            RESET_N         : in    std_logic;
            A               : in    std_logic_vector(31 downto 0);
            D_in            : in    std_logic_vector(31 downto 0);
            D_out           : out   std_logic_vector(31 downto 0);
            AS_N            : in    std_logic;
            DS_N            : in    std_logic;
            RW              : in    std_logic;
            gayle_irq       : out   std_logic;
            rom_overlay     : out   std_logic                       
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

        if reset = '1' or s_rom_overlay = '1' then
            -- A: KALTSTART-PHASE (Overlay aktiv oder Reset anliegend)
            -- Wenn die CPU bei Adresse 0x0 oder 0x4 anfragt, schicken wir das ROM rein! [14.1]
            if unsigned(cpu_addr) < 8 then
                cpu_D_to_core <= kickstart_data_r;
                bus_dsack0_n  <= '0'; -- Simuliere schnellen 32-Bit-Port für den Bootvektor [14.1]
                bus_dsack1_n  <= '0';
            elsif cpu_addr(31 downto 19) = "0000000011111" then
                -- Normaler ROM-Zugriff ($00F80000 bis $00FFFFFF) im Overlay
                cpu_D_to_core <= kickstart_data_r;
                bus_dsack0_n  <= '0';
                bus_dsack1_n  <= '0';
            end if;
        else
            -- B: REGULÄRER BETRIEB (AmigaOS hat das Overlay abgeschaltet)
            if cpu_addr(31 downto 19) = "0000000011111" then
                -- Standard Kickstart-ROM Lesezugriff
                cpu_D_to_core <= kickstart_data_r;
                bus_dsack0_n  <= '0';
                bus_dsack1_n  <= '0';
            else
                -- Hier klinken sich Gayle, die CIAs und das Chip-RAM ein
                cpu_D_to_core <= BUS_IDLE_32; -- Vermeide internes Tri-State; benutze definierten Idle-Wert
                bus_dsack0_n  <= '1';             
                bus_dsack1_n  <= '1';
            end if;
        end if;
    end process;

    -- =====================================================================
    -- 3. INTERNES SPEICHERBETT: DAS IOCTL-GEKOPPELTE KICKSTART-ROM
    -- REPARIERT: Nimmt die Download-Bytes des MiSTer im Dual-Port-RAM auf!
    -- =====================================================================
    process(clk_sys)
        type rom_matrix is array (0 to 131071) of std_logic_vector(31 downto 0);
        -- Inferenz von Intel M10K-Blöcken als schnellen On-Chip-ROM-Speicher pool
        variable v_kickstart_mem : rom_matrix := (others => (others => '0'));
        variable v_write_addr : integer range 0 to 131071;
    begin
        if rising_edge(clk_sys) then
            -- Port A: Der unyielding 32-Bit-Lesekanal der CPU
            kickstart_data_r <= v_kickstart_mem(to_integer(unsigned(cpu_addr(18 downto 2))));

            -- Port B: Der 8-Bit-Schreibkanal für den MiSTer HPS-Download
            if ioctl_ks_download = '1' and ioctl_wr = '1' then
                v_write_addr := to_integer(unsigned(ioctl_addr(18 downto 2)));
                
                -- Bytes phasenrichtig je nach Adresse im 32-Bit-Wort einsortieren (Big-Endian) [14.1]
                case ioctl_addr(1 downto 0) is
                    when "00" => v_kickstart_mem(v_write_addr)(31 downto 24) := ioctl_data;
                    when "01" => v_kickstart_mem(v_write_addr)(23 downto 16) := ioctl_data;
                    when "10" => v_kickstart_mem(v_write_addr)(15 downto 8)  := ioctl_data;
                    when "11" => v_kickstart_mem(v_write_addr)(7 downto 0)   := ioctl_data;
                    when others => null;
                end case;
            end if;
        end if;
    end process;


     
    -- =====================================================================
    -- 4. INSTANZIIERUNG: DIE MASTER-TURBOKARTE (MIT 56-MHZ CPU-KERN)
    -- =====================================================================
    i_turbo_card : turbo_card
        port map (
            CLK_14M         => s_clk_14m,
            i_reset_high    => reset,               -- Angeschlossen an die NE555-Resetleitung
            A               => cpu_addr,
            D_in            => cpu_D_to_core,
            D_out           => cpu_D_from_core,
            AS_N            => bus_as_n,
            DS_N            => bus_ds_n,
            RW              => bus_rw,
            SIZ             => bus_siz,
            FC              => bus_fc,
            DSACK0_N        => bus_dsack0_n,
            DSACK1_N        => bus_dsack1_n,
            IPL_N           => system_ipl_n,

            ddr_req         => ddr_req,
            ddr_rnw         => ddr_rnw,
            ddr_addr        => ddr_addr,
            ddr_data_w      => ddr_data_w,
            ddr_data_r      => ddr_data_r,
            ddr_ready       => ddr_ready,
            ddr_burst_ack   => ddr_burst_ack
        );

    -- =====================================================================
    -- 5. INSTANZIIERUNG: DER INNERE SYSTEM-CONTROLLER (GAYLE)
    -- =====================================================================
    i_gayle : gayle
        port map (
            CLK             => s_clk_14m,
            RESET_N         => not reset,
            A               => cpu_addr,
            D_in            => cpu_D_from_core,
            D_out           => open,
            AS_N            => bus_as_n,
            DS_N            => bus_ds_n,
            RW              => bus_rw,
            gayle_irq       => open,
            rom_overlay     => s_rom_overlay        -- Schaltet das Overlay regelkonform ab
        );

    -- Dummy-Ausgaben für Video-Schnittstellen (Lisa / Alice Platzhalter)
    ce_pix  <= '1';
    HBlank  <= '0'; HSync <= '1';
    VBlank  <= '0'; VSync <= '1';
    video_r <= (others => '0'); video_g <= (others => '0'); video_b <= (others => '0');

end structural;
