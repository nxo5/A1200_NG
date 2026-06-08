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

    -- -----------------------------------------------------------------
    -- CHIP-DEKLARATIONEN (NUR CPU UND DIAGNOSE-BOARD)
    -- -----------------------------------------------------------------
    -- Die Motorola 68020 CPU
    component M68020_cpu is
        Port (
            clk           : in  std_logic;
            reset         : in  std_logic;
            address_bus   : out std_logic_vector(31 downto 0);
            data_in       : in  std_logic_vector(31 downto 0);
            data_out      : out std_logic_vector(31 downto 0);
            as_n          : out std_logic;
            ds_n          : out std_logic;
            rw            : out std_logic;
            fc            : out std_logic_vector(2 downto 0);
            siz0          : out std_logic;
            siz1          : out std_logic;
            dsack0_n      : in  std_logic;
            dsack1_n      : in  std_logic
        );
    end component;

    -- Das virtuelle Amiga-1200-Testboard (Chip-RAM + ROM Dummy)
    component M68020_test_board is
        Port (
            clk           : in  std_logic;
            reset         : in  std_logic;
            cpu_addr      : in  std_logic_vector(31 downto 0);
            cpu_data_out  : in  std_logic_vector(31 downto 0);
            cpu_data_in   : out std_logic_vector(31 downto 0);
            cpu_as_n      : in  std_logic;
            cpu_ds_n      : in  std_logic;
            cpu_rw        : in  std_logic;
            cpu_dsack0_n  : out std_logic;
            cpu_dsack1_n  : out std_logic
        );
    end component;

    -- -----------------------------------------------------------------
    -- INTERNE KUPFERBAHNEN DER PLATINE (SIGNALE)
    -- -----------------------------------------------------------------
    signal clk_amiga   : std_logic := '0';
    signal clk_div     : unsigned(2 downto 0) := (others => '0');

    -- Gemeinsame Leitungen des Amiga-32-Bit-Busses
    signal am_addr     : std_logic_vector(31 downto 0);
    signal am_as_n     : std_logic;
    signal am_ds_n     : std_logic;
    signal am_rw       : std_logic;
    signal am_fc       : std_logic_vector(2 downto 0);
    signal am_siz0     : std_logic;
    signal am_siz1     : std_logic;
    signal am_dsack0_n : std_logic;
    signal am_dsack1_n : std_logic;

    -- Der gemeinsame, parallele Datenbus-Verlauf (Zwei-Wege-Fluss)
    signal am_data_cpu_to_board : std_logic_vector(31 downto 0);
    signal am_data_board_to_cpu : std_logic_vector(31 downto 0);

begin

    -- TAKTERZEUGUNG (Synchroner Basistakt ca. 14 MHz)
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            clk_div <= clk_div + 1;
        end if;
    end process;
    
    clk_amiga <= clk_div(2); 
    ce_pix    <= clk_div(2); 

    -- =================================================================
    -- CHIP-BESTÜCKUNG (Komponenten auf die Platine löten)
    -- =================================================================
    
    -- 1. Die CPU wird platziert
    amiga_cpu : M68020_cpu
    port map (
        clk          => clk_amiga, 
        reset        => reset,
        address_bus  => am_addr,
        data_out     => am_data_cpu_to_board, -- CPU sendet zum Board
        data_in      => am_data_board_to_cpu, -- CPU empfängt vom Board
        as_n         => am_as_n,
        ds_n         => am_ds_n,
        rw           => am_rw,
        fc           => am_fc,
        siz0         => am_siz0,
        siz1         => am_siz1,
        dsack0_n     => am_dsack0_n,
        dsack1_n     => am_dsack1_n
    );

    -- 2. Das Diagnose-Testboard wird als direkter Gegenpart platziert
    amiga_test_board : M68020_test_board
    port map (
        clk           => clk_amiga,
        reset         => reset,
        cpu_addr      => am_addr,
        cpu_data_out  => am_data_cpu_to_board, -- Board empfängt Schreibdaten
        cpu_data_in   => am_data_board_to_cpu, -- Board sendet Lesedaten
        cpu_as_n      => am_as_n,
        cpu_ds_n      => am_ds_n,
        cpu_rw        => am_rw,
        cpu_dsack0_n  => am_dsack0_n,
        cpu_dsack1_n  => am_dsack1_n
    );

    -- TEMPORÄRE DUMMYS FÜR CHIPSATZ-AUSGÄNGE
    HBlank    <= '0'; HSync <= '0'; VBlank <= '0'; VSync <= '0';
    video_r   <= (others => '0'); video_g <= (others => '0'); video_b <= (others => '0'); 

end Behavioral;
