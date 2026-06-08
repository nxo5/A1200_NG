library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.M68020_pkg.all;

entity cia_b is
    Port (
        -- =============================================================
        -- 1. TAKT-, RESET- UND SYSTEMLEITUNGEN
        -- =============================================================
        clk_sys       : in    std_logic; -- Der schnelle Basistakt des Gesamtsystems
        reset         : in    std_logic; -- Globaler System-Reset
        e_clock_ce    : in    std_logic; -- Der verlangsamte E-Clock Takt-Enable (~0,71 MHz)
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM INTERNEN AMIGA-BUS (Historisches 8-Bit Interface)
        -- =============================================================
        -- Hinweis: Wird später auf der Hauptplatine exakt an D0-D7 gelötet!
        cia_data      : inout std_logic_vector(7 downto 0); 
        reg_addr : in std_logic_vector(3 downto 0);			 -- 16 interne Register
        cia_cs_n      : in    std_logic;                     -- Chip Select
        cia_rw        : in    std_logic;                     -- Read (1) / Write (0)
        cia_irq_n     : out   std_logic;                     -- Interrupt-Ausgang (geht an INT2 / Paula)
        
        -- =============================================================
        -- 3. INTERFACES ZUR AUSSENWELT (Original-Hardware-Ports)
        -- =============================================================
        cia_port_a    : inout std_logic_vector(7 downto 0); -- Centronics-Parallelport (Drucker)
        cia_port_b    : inout std_logic_vector(7 downto 0); -- Video-Sync & Laufwerksauswahl
        cia_tod       : in    std_logic;                    -- Time of Day Netztakt
        cia_cnt       : inout std_logic;                    -- Counter-Pin
        cia_sp        : inout std_logic                     -- Serial Port Pin
    );
end cia_b;

architecture Behavioral of cia_b is

    -- -----------------------------------------------------------------
    -- DEKLARATION DER VIER INTERNEN FUNKTIONSBLÖCKE
    -- -----------------------------------------------------------------
    component cia_b_io is
        Port (
            clk_sys       : in    std_logic;
            reset         : in    std_logic;
            e_clock_ce    : in    std_logic;
            reg_addr      : in    std_logic_vector(31 downto 0);
            chip_sel      : in    std_logic;
            read_en       : in    std_logic;
            write_en      : in    std_logic;
            data_in       : in    std_logic_vector(7 downto 0);
            data_out      : out   std_logic_vector(7 downto 0);
            cia_port_a    : inout std_logic_vector(7 downto 0);
            cia_port_b    : inout std_logic_vector(7 downto 0)
        );
    end component;

    component cia_b_timer is
        Port (
            clk_sys       : in    std_logic;
            reset         : in    std_logic;
            e_clock_ce    : in    std_logic;
            reg_addr      : in    std_logic_vector(31 downto 0);
            chip_sel      : in    std_logic;
            read_en       : in    std_logic;
            write_en      : in    std_logic;
            data_in       : in    std_logic_vector(7 downto 0);
            data_out      : out   std_logic_vector(7 downto 0);
            timer_a_irq   : out   std_logic;
            timer_b_irq   : out   std_logic;
            cia_tod       : in    std_logic;
            cia_cnt       : in    std_logic
        );
    end component;

    component cia_b_serial is
        Port (
            clk_sys       : in    std_logic;
            reset         : in    std_logic;
            e_clock_ce    : in    std_logic;
            reg_addr      : in    std_logic_vector(31 downto 0);
            chip_sel      : in    std_logic;
            read_en       : in    std_logic;
            write_en      : in    std_logic;
            data_in       : in    std_logic_vector(7 downto 0);
            data_out      : out   std_logic_vector(7 downto 0);
            serial_irq    : out   std_logic;
            cia_cnt       : in    std_logic;
            cia_sp        : inout std_logic
        );
    end component;

    component cia_b_irq is
        Port (
            clk_sys       : in    std_logic;
            reset         : in    std_logic;
            e_clock_ce    : in    std_logic;
            reg_addr      : in    std_logic_vector(31 downto 0);
            chip_sel      : in    std_logic;
            read_en       : in    std_logic;
            write_en      : in    std_logic;
            data_in       : in    std_logic_vector(7 downto 0);
            data_out      : out   std_logic_vector(7 downto 0);
            timer_a_irq   : in    std_logic;
            timer_b_irq   : in    std_logic;
            serial_irq    : in    std_logic;
            cia_irq_n     : out   std_logic
        );
    end component;

    -- -----------------------------------------------------------------
    -- CHIPINTERNE KUPFERBAHNEN (SIGNALE)
    -- -----------------------------------------------------------------
    -- Das zentrale, kombinatorische 8-Bit-Datenbus-Rückgrat
    signal internal_data_in  : std_logic_vector(7 downto 0);
    signal data_from_io      : std_logic_vector(7 downto 0);
    signal data_from_timer   : std_logic_vector(7 downto 0);
    signal data_from_serial  : std_logic_vector(7 downto 0);
    signal data_from_irq     : std_logic_vector(7 downto 0);

    -- Die internen Alarm-Zubringerleitungen zur Interrupt-Zentrale (ICR)
    signal int_timer_a_irq   : std_logic;
    signal int_timer_b_irq   : std_logic;
    signal int_serial_irq    : std_logic;

    -- Bereinigte Steuersignale für den Buszugriff
    signal int_chip_sel      : std_logic;
    signal int_read_en       : std_logic;
    signal int_write_en      : std_logic;
    signal extended_addr     : std_logic_vector(31 downto 0);

begin

    -- =================================================================
    -- 1. KOMBATORISCHE BUS-SCHNITTSTELLE (Echtzeit-Durchschaltung)
    -- =================================================================
    -- Aktivierungssignale direkt aus dem Amiga-Bus ableiten
    int_chip_sel <= '1' when cia_cs_n = '0' else '0';
    int_read_en  <= '1' when (cia_cs_n = '0' and cia_rw = '1') else '0';
    int_write_en <= '1' when (cia_cs_n = '0' and cia_rw = '0') else '0';

    -- Adressvektor für den 32-Bit-Busrahmen der Untermodule auffüllen
    extended_addr <= std_logic_vector(resize(unsigned(reg_addr), 32));

    -- Schreibdaten von der CPU ins interne Bussystem einspeisen
    internal_data_in <= cia_data;

    -- TRISTATE-STEUERUNG FÜR DEN EXTERNEN 8-BIT-AMIGA-DATENBUS
    -- Wenn die CPU liest, schalten wir die gesammelten Registerdaten aktiv auf die Leitungen.
    -- Wenn die CPU schreibt oder der Chip inaktiv ist, schalten wir auf Hochohmig ('Z').
    cia_data <= (data_from_io or data_from_timer or data_from_serial or data_from_irq) 
                when int_read_en = '1' else (others => 'Z');

    -- =================================================================
    -- 2. INTERNE CHIP-VERDRAHTUNG (PORT MAPS)
    -- =================================================================
    
    -- Block 1: Die Parallelports
    u_cia_io : cia_b_io
    port map (
        clk_sys       => clk_sys,
        reset         => reset,
        e_clock_ce    => e_clock_ce,
        reg_addr      => extended_addr,
        chip_sel      => int_chip_sel,
        read_en       => int_read_en,
        write_en      => int_write_en,
        data_in       => internal_data_in,
        data_out      => data_from_io,
        cia_port_a    => cia_port_a,
        cia_port_b    => cia_port_b
    );

    -- Block 2: Die 16-Bit-Timer A & B
    u_cia_timer : cia_b_timer
    port map (
        clk_sys       => clk_sys,
        reset         => reset,
        e_clock_ce    => e_clock_ce,
        reg_addr      => extended_addr,
        chip_sel      => int_chip_sel,
        read_en       => int_read_en,
        write_en      => int_write_en,
        data_in       => internal_data_in,
        data_out      => data_from_timer,
        timer_a_irq   => int_timer_a_irq,
        timer_b_irq   => int_timer_b_irq,
        cia_tod       => cia_tod,
        cia_cnt       => cia_cnt
    );

    -- Block 3: Das serielle Schieberegister
    u_cia_serial : cia_b_serial
    port map (
        clk_sys       => clk_sys,
        reset         => reset,
        e_clock_ce    => e_clock_ce,
        reg_addr      => extended_addr,
        chip_sel      => int_chip_sel,
        read_en       => int_read_en,
        write_en      => int_write_en,
        data_in       => internal_data_in,
        data_out      => data_from_serial,
        serial_irq    => int_serial_irq,
        cia_cnt       => cia_cnt,
        cia_sp        => cia_sp
    );

    -- Block 4: Die Interrupt-Zentrale (ICR)
    u_cia_irq : cia_b_irq
    port map (
        clk_sys       => clk_sys,
        reset         => reset,
        e_clock_ce    => e_clock_ce,
        reg_addr      => extended_addr,
        chip_sel      => int_chip_sel,
        read_en       => int_read_en,
        write_en      => int_write_en,
        data_in       => internal_data_in,
        data_out      => data_from_irq,
        timer_a_irq   => int_timer_a_irq,
        timer_b_irq   => int_timer_b_irq,
        serial_irq    => int_serial_irq,
        cia_irq_n     => cia_irq_n
    );

end Behavioral;
