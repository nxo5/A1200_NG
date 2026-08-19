-- Testbench für cpu_030_fastram_bridge
-- Prüft: cpu_sterm_n Puls bei Burst-Reads und Durchgabe von ddr_req / ddr_addr

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_fastram is
end tb_fastram;

architecture sim of tb_fastram is

    -- Signale wie in der Bridge
    signal CLK             : std_logic := '0';
    signal RESET_N         : std_logic := '0';
    signal cpu_A           : std_logic_vector(31 downto 0) := (others => '0');
    signal cpu_D_out       : std_logic_vector(31 downto 0) := (others => '0');
    signal cpu_D_in        : std_logic_vector(31 downto 0);
    signal cpu_AS_N        : std_logic := '1';
    signal cpu_DS_N        : std_logic := '1';
    signal cpu_RW          : std_logic := '1';

    signal cache_req       : std_logic := '0';
    signal cache_burst_en  : std_logic := '1';

    signal cpu_sterm_n     : std_logic;

    signal ddr_req         : std_logic;
    signal ddr_rnw         : std_logic;
    signal ddr_addr        : std_logic_vector(25 downto 2);
    signal ddr_data_w      : std_logic_vector(31 downto 0);
    signal ddr_data_r      : std_logic_vector(31 downto 0) := (others => '0');
    signal ddr_ready       : std_logic := '0';
    signal ddr_burst_ack   : std_logic := '0';

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz Testclock

begin

    -- Clock generator
    clk_proc : process
    begin
        while now < 2000 ns loop
            CLK <= '0';
            wait for CLK_PERIOD/2;
            CLK <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process clk_proc;

    -- Instantiate the bridge under test
    uut: entity work.cpu_030_fastram_bridge
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            cpu_A           => cpu_A,
            cpu_D_out       => cpu_D_out,
            cpu_D_in        => cpu_D_in,
            cpu_AS_N        => cpu_AS_N,
            cpu_DS_N        => cpu_DS_N,
            cpu_RW          => cpu_RW,
            cache_req       => cache_req,
            cache_burst_en  => cache_burst_en,
            cpu_sterm_n     => cpu_sterm_n,
            ddr_req         => ddr_req,
            ddr_rnw         => ddr_rnw,
            ddr_addr        => ddr_addr,
            ddr_data_w      => ddr_data_w,
            ddr_data_r      => ddr_data_r,
            ddr_ready       => ddr_ready,
            ddr_burst_ack   => ddr_burst_ack
        );

    -- Stimulus process: reset and issue a burst read
    stim_proc: process
    begin
        -- Reset
        RESET_N <= '0';
        wait for 100 ns;
        RESET_N <= '1';
        wait for 40 ns;

        -- Prepare a read to FastRAM region (high byte 0x08 triggers fastram_hit)
        cpu_A <= x"08000000"; -- high_byte = 0x08
        cpu_RW <= '1';
        cpu_DS_N <= '0';
        cpu_AS_N <= '0'; -- start cycle

        report "CPU: AS_N asserted, starting FastRAM access";

        -- wait a few clocks and then make DDR ready with sequential data words
        wait for 30 ns;

        -- First DDR word available
        ddr_data_r <= x"11111111";
        ddr_ready <= '1';
        wait for CLK_PERIOD; -- one clock where ddr_ready is high

        -- Provide additional words to emulate burst transfer
        ddr_data_r <= x"22222222";
        wait for CLK_PERIOD;
        ddr_data_r <= x"33333333";
        wait for CLK_PERIOD;
        ddr_data_r <= x"44444444";
        wait for CLK_PERIOD;

        -- End of burst: deassert ready
        ddr_ready <= '0';

        wait for 40 ns;
        cpu_AS_N <= '1'; -- CPU releases bus; bridge should return to IDLE after terminate
        cpu_DS_N <= '1';

        report "CPU: AS_N deasserted, finished access";

        wait for 100 ns;
        report "Simulation finished";
        wait;
    end process stim_proc;

    -- Monitor cpu_sterm_n events
    monitor_sterm: process(cpu_sterm_n)
    begin
        if cpu_sterm_n'event then
            if cpu_sterm_n = '0' then
                report "cpu_sterm_n asserted (0) at " & integer'image(now / 1 ns) & " ns" severity note;
            else
                report "cpu_sterm_n deasserted (1) at " & integer'image(now / 1 ns) & " ns" severity note;
            end if;
        end if;
    end process monitor_sterm;

    -- Monitor ddr handshake signals for debugging
    monitor_ddr: process(ddr_req, ddr_addr, ddr_rnw)
    begin
        if ddr_req'event and ddr_req = '1' then
            report "ddr_req asserted at " & integer'image(now / 1 ns) & " ns, addr=" & to_hstring(ddr_addr) &
                   ", rnw=" & std_logic'image(ddr_rnw) severity note;
        end if;
    end process monitor_ddr;

end sim;
