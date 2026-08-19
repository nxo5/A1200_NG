library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity A1200_tb is
-- Eine Testbench hat keine externen Ports nach außen
end A1200_tb;

architecture Simulation of A1200_tb is

    -- 1. Deklaration der zu testenden Hauptplatine (Unit Under Test)
    component A1200_top is
        Port (
            clk_sys     : in  STD_LOGIC;
            reset       : in  STD_LOGIC;
            pal_mode    : in  STD_LOGIC;
            ce_pix      : out STD_LOGIC;
            HBlank      : out STD_LOGIC;
            HSync       : out STD_LOGIC;
            VBlank      : out STD_LOGIC;
            VSync       : out STD_LOGIC;
            video_r     : out STD_LOGIC_VECTOR(7 downto 0);
            video_g     : out STD_LOGIC_VECTOR(7 downto 0);
            video_b     : out STD_LOGIC_VECTOR(7 downto 0);
            ioctl_addr  : in  STD_LOGIC_VECTOR(24 downto 0);
            ioctl_data  : in  STD_LOGIC_VECTOR(7 downto 0);
            ioctl_wr    : in  STD_LOGIC;
            ioctl_ks_download   : in  STD_LOGIC;
            ioctl_fdd_download  : in  STD_LOGIC;
            ioctl_hdf0_download : in  STD_LOGIC;
            ioctl_hdf1_download : in  STD_LOGIC;
            ioctl_hdf2_download : in  STD_LOGIC;
            ioctl_hdf3_download : in  STD_LOGIC
        );
    end component;

    -- 2. Interne Stimuli-Signale zur Steuerung der Simulation
    signal tb_clk_sys   : std_logic := '0';
    signal tb_reset     : std_logic := '1';
    signal tb_pal_mode  : std_logic := '1'; -- Fest auf PAL-Modus eingestellt

    -- IOCTL / MiSTer download signals
    signal tb_ioctl_addr : std_logic_vector(24 downto 0) := (others => '0');
    signal tb_ioctl_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tb_ioctl_wr   : std_logic := '0';
    signal tb_ioctl_ks_download  : std_logic := '0';
    signal tb_ioctl_fdd_download : std_logic := '0';
    signal tb_ioctl_hdf0_download: std_logic := '0';
    signal tb_ioctl_hdf1_download: std_logic := '0';
    signal tb_ioctl_hdf2_download: std_logic := '0';
    signal tb_ioctl_hdf3_download: std_logic := '0';

    -- Ausgänge (Vorerst nur zur Vervollständigung, werden im Wave-Fenster sichtbar)
    signal tb_ce_pix    : std_logic;
    signal tb_hblank    : std_logic;
    signal tb_hsync     : std_logic;
    signal tb_vblank    : std_logic;
    signal tb_vsync     : std_logic;
    signal tb_video_r   : std_logic_vector(7 downto 0);
    signal tb_video_g   : std_logic_vector(7 downto 0);
    signal tb_video_b   : std_logic_vector(7 downto 0);

    -- Takt-Konstante: 50 MHz MiSTer-Systemtakt (1 Periode = 20 Nanosekunden)
    constant CLK_PERIOD : time := 20 ns;

begin

    -- 3. Instanziierung des virtuellen Amiga 1200
    uut: A1200_top
    port map (
        clk_sys  => tb_clk_sys,
        reset    => tb_reset,
        pal_mode => tb_pal_mode,
        ce_pix   => tb_ce_pix,
        HBlank   => tb_hblank,
        HSync    => tb_hsync,
        VBlank   => tb_vblank,
        VSync    => tb_vsync,
        video_r  => tb_video_r,
        video_g  => tb_video_g,
        video_b  => tb_video_b,
        ioctl_addr  => tb_ioctl_addr,
        ioctl_data  => tb_ioctl_data,
        ioctl_wr    => tb_ioctl_wr,
        ioctl_ks_download   => tb_ioctl_ks_download,
        ioctl_fdd_download  => tb_ioctl_fdd_download,
        ioctl_hdf0_download => tb_ioctl_hdf0_download,
        ioctl_hdf1_download => tb_ioctl_hdf1_download,
        ioctl_hdf2_download => tb_ioctl_hdf2_download,
        ioctl_hdf3_download => tb_ioctl_hdf3_download
    );

    -- 4. Oszillator-Prozess: Erzeugt einen dauerhaften 50 MHz Takt
    clk_process: process
    begin
        tb_clk_sys <= '0';
        wait for CLK_PERIOD / 2;
        tb_clk_sys <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- 5. Stimuli-Prozess: Steuert den virtuellen Power-Knopf des Amiga
    stimuli_process: process
    begin
        -- Der Amiga wird eingeschaltet. Reset bleibt für 100 ns aktiv ('1')
        tb_reset <= '1';
        wait for 100 ns;
        
        -- Reset wird gelöst. Die CPU-Zustandsmaschine startet im nächsten Takt!
        tb_reset <= '0';
        
        -- Die Simulation läuft für das gewünschte Zeitfenster weiter
        wait for 900 ns;
        
        -- Ende der Simulation nach insgesamt 1000 ns
        wait;
    end process;

end Simulation;
