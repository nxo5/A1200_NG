-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_b.vhd
-- Teil:    1 von 2 (Schnittstelle & Komponenten)
-- Funktion: Das strukturelle Top-Level Hauptgehäuse (Shell) des CIA-B-Chips.
-- SANIERUNG SCHRITT 28 (A):
--   - Vorbereitung des Multiplexers für den Lese-Datenbus.
--   - Sichert zyklustreue Lesezugriffe für die CPU an der D0-D7 Busgrenze.
-- TRISTATE-FIX: Internes Tri-State auf cia_data durch definierten BUS_IDLE_VALUE ersetzen
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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
        cia_data      : inout std_logic_vector(7 downto 0); -- Wird an D0-D7 gelötet
        reg_addr      : in    std_logic_vector(3 downto 0); -- 16 interne Register
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
    -- COMPONENTEN-DEKLARATIONEN DER VIER UNTERMODULE
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

    -- CHIPINTERNE KUPFERBAHNEN (SIGNALE)
    signal internal_data_in  : std_logic_vector(7 downto 0);
    signal data_from_io      : std_logic_vector(7 downto 0);
    signal data_from_timer   : std_logic_vector(7 downto 0);
    signal data_from_serial  : std_logic_vector(7 downto 0);
    signal data_from_irq     : std_logic_vector(7 downto 0);
    
    signal mux_data_out      : std_logic_vector(7 downto 0);

    signal int_timer_a_irq   : std_logic;
    signal int_timer_b_irq   : std_logic;
    signal int_serial_irq    : std_logic;

    signal int_chip_sel      : std_logic;
    signal int_read_en       : std_logic;
    signal int_write_en      : std_logic;
    signal extended_addr     : std_logic_vector(31 downto 0);

    -- Ersatz für internes Tri-State: definiere einen festen Bus-Ruhepegel (Pull-High)
    constant BUS_IDLE_VALUE : std_logic_vector(7 downto 0) := (others => '1');

	 begin

    -- =================================================================
    -- 1. KOMBATORISCHE BUS-SCHNITTSTELLE (Echtzeit-Durchschaltung)
    -- =================================================================
    int_chip_sel <= '1' when cia_cs_n = '0' else '0';
    int_read_en  <= '1' when (cia_cs_n = '0' and cia_rw = '1') else '0';
    int_write_en <= '1' when (cia_cs_n = '0' and cia_rw = '0') else '0';

    extended_addr <= std_logic_vector(resize(unsigned(reg_addr), 32));
    internal_data_in <= cia_data;

    -- REPARATUR: CROSSFALL-FREIER REGISTER-MULTIPLEXER [14.1]
    -- Schaltet die Datenleitungen basierend auf der Registeradresse sauber um!
    process(reg_addr, data_from_io, data_from_timer, data_from_serial, data_from_irq)
    begin
        case reg_addr is
            when x"0" | x"1" | x"2" | x"3" =>
                mux_data_out <= data_from_io;     -- $PRA, $PRB, $DDRA, $DDRB [14.1]
            when x"4" | x"5" | x"6" | x"7" | x"8" | x"9" =>
                mux_data_out <= data_from_timer;  -- TA_LO, TA_HI, TB_LO, TB_HI etc. [14.1]
            when x"C" =>
                mux_data_out <= data_from_serial; -- SDR (Serial Data Register) [14.1]
            when x"D" | x"E" | x"F" =>
                mux_data_out <= data_from_irq;    -- ICR, CRA, CRB [14.1]
            when others =>
                mux_data_out <= (others => '0');
        end case;
    end process;

    -- ERSETZTER TRISTATE: Benutze einen definierten Bus-Ruhepegel anstelle von 'Z'
    cia_data <= mux_data_out when int_read_en = '1' else BUS_IDLE_VALUE;

    -- =================================================================
    -- 2. INTERNE CHIP-VERDRAHTUNG (PORT MAPS)
    -- =================================================================
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
