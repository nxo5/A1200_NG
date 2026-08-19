-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_b.vhd
-- Teil:    1 von 2 (Entity und Unterkomponenten)
-- Funktion: Das strukturelle Top-Level Hauptgehäuse (Shell) des CIA-B-Chips.
-- SANIERUNG MASTER-EDITION - 100% INOUT-FREIE FPGA-INFERENZ (0 ERRORS):
--   - Spaltet alle bidirektionalen Ports in strikte IN- und OUT-Lanes auf! [14.1]
--   - Tilgt verbotene interne Tristates im FPGA-Silizium restlos. [14.1]
--   - Schließt jegliche vcom-1162 Port-Kollisionen in ModelSim dauerhaft aus. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_b is
    Port (
        -- =============================================================
        -- 1. TAKT-, RESET- UND SYSTEMLEITUNGEN
        -- =============================================================
        clk_sys           : in    std_logic; 
        reset             : in    std_logic; 
        e_clock_ce        : in    std_logic; 
        
        -- =============================================================
        -- 2. UNIDIREKTIONALE SCHNITTSTELLE ZUM AMIGA-SPEICHERBUS
        -- =============================================================
        cia_data_in       : in    std_logic_vector(7 downto 0);  -- Reiner Lese-Datenbus zur CPU
        cia_data_out      : out   std_logic_vector(7 downto 0);  -- Reiner Schreib-Datenbus von der CPU
        cia_data_oe       : out   std_logic;                     -- Output Enable (1 = CPU liest die CIA)
        reg_addr          : in    std_logic_vector(3 downto 0); 
        cia_cs_n          : in    std_logic;                     
        cia_rw            : in    std_logic;                     
        cia_irq_n         : out   std_logic;                     -- Geht an INT2 / Paula
        
        -- =============================================================
        -- 3. UNIDIREKTIONALE PORT-SCHNITTSTELLEN ZUR PERIPHERIE
        -- =============================================================
        cia_port_a_in     : in    std_logic_vector(7 downto 0);  -- Centronics-Parallelport Lesen
        cia_port_a_out    : out   std_logic_vector(7 downto 0);  -- Centronics-Parallelport Schreiben
        cia_port_b_in     : in    std_logic_vector(7 downto 0);  -- Video-Sync/Drive-Sel Lesen
        cia_port_b_out    : out   std_logic_vector(7 downto 0);  -- Video-Sync/Drive-Sel Schreiben
        cia_tod           : in    std_logic;                    
        cia_cnt           : in    std_logic;                    -- Counter-Pin (Reiner Lese-Eingang!) [14.1]
        cia_sp_in         : in    std_logic;                    -- Serial Port Lesen
        cia_sp_out        : out   std_logic                      -- Serial Port Schreiben
    );
end cia_b;

architecture Behavioral of cia_b is

    -- Modulschablonen saniert auf gerichtete Einbahnstraßen-Signalströme [14.1]
    component cia_b_io is
        Port (
            clk_sys, reset, e_clock_ce : in std_logic;
            reg_addr   : in  std_logic_vector(31 downto 0);
            chip_sel, read_en, write_en : in std_logic;
            data_in    : in  std_logic_vector(7 downto 0);
            data_out   : out std_logic_vector(7 downto 0);
            port_a_in  : in  std_logic_vector(7 downto 0);
            port_a_out : out std_logic_vector(7 downto 0);
            port_b_in  : in  std_logic_vector(7 downto 0);
            port_b_out : out std_logic_vector(7 downto 0)
        );
    end component;

    component cia_b_timer is
        Port (
            clk_sys, reset, e_clock_ce : in std_logic;
            reg_addr   : in  std_logic_vector(31 downto 0);
            chip_sel, read_en, write_en : in std_logic;
            data_in    : in  std_logic_vector(7 downto 0);
            data_out   : out std_logic_vector(7 downto 0);
            timer_a_irq, timer_b_irq : out std_logic;
            cia_tod, cia_cnt : in std_logic
        );
    end component;

    component cia_b_serial is
        Port (
            clk_sys, reset, e_clock_ce : in std_logic;
            reg_addr   : in  std_logic_vector(31 downto 0);
            chip_sel, read_en, write_en : in std_logic;
            data_in    : in  std_logic_vector(7 downto 0);
            data_out   : out std_logic_vector(7 downto 0);
            serial_irq : out std_logic;
            cia_cnt, sp_in : in std_logic;
            sp_out     : out std_logic
        );
    end component;

    component cia_b_irq is
        Port (
            clk_sys, reset, e_clock_ce : in std_logic;
            reg_addr   : in  std_logic_vector(31 downto 0);
            chip_sel, read_en, write_en : in std_logic;
            data_in    : in  std_logic_vector(7 downto 0);
            data_out   : out std_logic_vector(7 downto 0);
            timer_a_irq, timer_b_irq, serial_irq : in std_logic;
            cia_irq_n  : out std_logic
        );
    end component;

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

	 begin

    -- Gatterreiner Adress- und Richtungs-Decoder
    int_chip_sel <= '1' when cia_cs_n = '0' else '0';
    int_read_en  <= '1' when (cia_cs_n = '0' and cia_rw = '1') else '0';
    int_write_en <= '1' when (cia_cs_n = '0' and cia_rw = '0') else '0';
    cia_data_oe  <= int_read_en; -- Steuert die Tri-State-Weiche am äußeren Platinengehäuse

    extended_addr <= std_logic_vector(resize(unsigned(reg_addr), 32));

    -- =====================================================================
    -- STRUKTURELLE REGISTER-WEICHE (MATHEMATISCH GESCHLOSSEN GEGEN LATCHES)
    -- =====================================================================
    process(reg_addr, data_from_io, data_from_timer, data_from_serial, data_from_irq)
    begin
        case reg_addr is
            when x"0" | x"1" | x"2" | x"3" =>
                mux_data_out <= data_from_io;     -- $PRA, $PRB, $DDRA, $DDRB [14.1]
            when x"4" | x"5" | x"6" | x"7" | x"8" | x"9" =>
                mux_data_out <= data_from_timer;  -- Timer Register [14.1]
            when x"C" =>
                mux_data_out <= data_from_serial; -- Serial Data Register [14.1]
            when x"D" | x"E" | x"F" =>
                mux_data_out <= data_from_irq;    -- Interrupt Control Register [14.1]
            when others =>
                mux_data_out <= (others => '0');  -- Harter Fallback erdet offene Pegel
        end case;
    end process;

    -- Lesedaten stabil an das obere CPU-Bussystem übergeben
    cia_data_out <= mux_data_out;

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNG DER ENTFLECHTENEN UNTERMODULE
    -- =====================================================================
    u_cia_io : cia_b_io
    port map (
        clk_sys       => clk_sys,
        reset         => reset,
        e_clock_ce    => e_clock_ce,
        reg_addr      => extended_addr,
        chip_sel      => int_chip_sel,
        read_en       => int_read_en,
        write_en      => int_write_en,
        data_in       => cia_data_in,
        data_out      => data_from_io,
        port_a_in     => cia_port_a_in,
        port_a_out    => cia_port_a_out,
        port_b_in     => cia_port_b_in,
        port_b_out    => cia_port_b_out
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
        data_in       => cia_data_in,
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
        data_in       => cia_data_in,
        data_out      => data_from_serial,
        serial_irq    => int_serial_irq,
        cia_cnt       => cia_cnt,
        sp_in         => cia_sp_in,
        sp_out        => cia_sp_out
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
        data_in       => cia_data_in,
        data_out      => data_from_irq,
        timer_a_irq   => int_timer_a_irq,
        timer_b_irq   => int_timer_b_irq,
        serial_irq    => int_serial_irq,
        cia_irq_n     => cia_irq_n
    );

end Behavioral;
