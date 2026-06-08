library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Einbindung des globalen CPU-Wörterbuchs
use work.M68020_pkg.all;

entity M68020_cpu is
    Port (
        -- System-Basis
        clk           : in  std_logic;
        reset         : in  std_logic;

        -- Adress- und Datenbus (Vollständige 32 Bit)
        address_bus   : out std_logic_vector(31 downto 0);
        data_in       : in  std_logic_vector(31 downto 0);
        data_out      : out std_logic_vector(31 downto 0);

        -- Originale Bus-Steuersignale des Motorola 68020
        as_n          : out std_logic; -- Address Strobe
        ds_n          : out std_logic; -- Data Strobe
        rw            : out std_logic; -- Read (1) / Write (0)
        
        -- Function Codes (Zeigt den CPU-Status: User/Supervisor, Prog/Data)
        fc            : out std_logic_vector(2 downto 0); 
        
        -- Size-Pins (Zeigt an, wie viele Bytes die CPU übertragen will)
        siz0          : out std_logic; 
        siz1          : out std_logic; 
        
        -- Getrennte DSACK-Pins für das originale Amiga 1200 Bus-Sizing
        dsack0_n      : in  std_logic; -- Data Transfer Acknowledge 0
        dsack1_n      : in  std_logic  -- Data Transfer Acknowledge 1
    );
end M68020_cpu;

architecture Behavioral of M68020_cpu is

    -- =================================================================
    -- 1. DEKLARATION DER INTERNEN CPU-BAUSTEINE
    -- =================================================================
    component M68020_fetch is
        Port (
            clk          : in  std_logic;
            reset        : in  std_logic;
            pc_in        : in  std_logic_vector(31 downto 0);
            pipe_hold    : in  std_logic;
            pipe_flush   : in  std_logic;
            stage_b      : out std_logic_vector(15 downto 0);
            stage_c      : out std_logic_vector(15 downto 0);
            stage_d      : out std_logic_vector(15 downto 0)
        );
    end component;

    component M68020_decode is
        Port (
            stage_c       : in  std_logic_vector(15 downto 0);
            op_is_nop     : out std_logic;
            op_is_illegal : out std_logic;
            ea_field      : out std_logic_vector(5 downto 0)
        );
    end component;

    component M68020_ea is
        Port (
            clk           : in  std_logic;
            reset         : in  std_logic;
            stage_b       : in  std_logic_vector(15 downto 0);
            ea_field      : in  std_logic_vector(5 downto 0);
            ea_start      : in  std_logic;
            ea_ready      : out std_logic;
            ea_address    : out std_logic_vector(31 downto 0)
        );
    end component;

    component M68020_execute is
        Port (
            clk           : in  std_logic;
            reset         : in  std_logic;
            stage_d       : in  std_logic_vector(15 downto 0);
            op_is_nop     : in  std_logic;
            op_is_illegal : in  std_logic;
            ea_address    : in  std_logic_vector(31 downto 0);
            ea_ready      : in  std_logic;
            exec_done     : out std_logic
        );
    end component;

    component M68020_bus_ctrl is
        Port (
            clk           : in  std_logic;
            reset         : in  std_logic;
            int_req       : in  std_logic;
            int_rw        : in  std_logic;
            int_addr      : in  std_logic_vector(31 downto 0);
            int_data_w    : in  std_logic_vector(31 downto 0);
            int_data_r    : out std_logic_vector(31 downto 0);
            int_busy      : out std_logic;
            ext_addr      : out std_logic_vector(31 downto 0);
            ext_data_in   : in  std_logic_vector(31 downto 0);
            ext_data_out  : out std_logic_vector(31 downto 0);
            ext_as_n      : out std_logic;
            ext_ds_n      : out std_logic;
            ext_rw        : out std_logic;
            dsack0_n      : in  std_logic;
            dsack1_n      : in  std_logic
        );
    end component;

    -- =================================================================
    -- 2. INTERNE REGISTERSÄTZE UND LEITUNGEN (BUSSE)
    -- =================================================================
    signal current_state : cpu_state_type := ST_INIT;
    signal next_state    : cpu_state_type := ST_INIT;

    -- Originale 68020-Zustandsregister
    signal reg_pc        : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_ssp       : std_logic_vector(31 downto 0) := (others => '0');

    -- Interne Leitungen zur Befehls-Pipeline (Fetch)
    signal int_pipe_hold  : std_logic := '0';
    signal int_pipe_flush : std_logic := '0';
    signal int_stage_b    : std_logic_vector(15 downto 0);
    signal int_stage_c    : std_logic_vector(15 downto 0);
    signal int_stage_d    : std_logic_vector(15 downto 0);

    -- Interne Leitungen des Befehlsdecoders (Decode)
    signal int_op_nop     : std_logic;
    signal int_op_illegal : std_logic;
    signal int_ea_field   : std_logic_vector(5 downto 0);

    -- Interne Leitungen des Adressdecoders (EA)
    signal int_ea_start   : std_logic := '0';
    signal int_ea_ready   : std_logic;
    signal int_ea_address : std_logic_vector(31 downto 0);

    -- Interne Leitungen der Ausführungseinheit (Execute)
    signal int_exec_done  : std_logic;

    -- Interne Leitungen des Bus-Controllers
    signal int_bus_req    : std_logic := '0';
    signal int_bus_rw     : std_logic := '1';
    signal int_bus_addr   : std_logic_vector(31 downto 0) := (others => '0');
    signal int_bus_data_w : std_logic_vector(31 downto 0) := (others => '0');
    signal int_bus_data_r : std_logic_vector(31 downto 0);
    signal int_bus_busy   : std_logic;

	 begin

    -- =================================================================
    -- 3. INTERNE CHIP-VERDRAHTUNG (INSTANZIIERUNG)
    -- =================================================================
    instruction_prefetch : M68020_fetch
    port map (
        clk          => clk,
        reset        => reset,
        pc_in        => reg_pc,
        pipe_hold    => int_pipe_hold,
        pipe_flush   => int_pipe_flush,
        stage_b      => int_stage_b,
        stage_c      => int_stage_c,
        stage_d      => int_stage_d
    );

    instruction_decoder : M68020_decode
    port map (
        stage_c       => int_stage_c,
        op_is_nop     => int_op_nop,
        op_is_illegal => int_op_illegal,
        ea_field      => int_ea_field
    );

    address_decoder : M68020_ea
    port map (
        clk           => clk,
        reset         => reset,
        stage_b       => int_stage_b,
        ea_field      => int_ea_field,
        ea_start      => int_ea_start,
        ea_ready      => int_ea_ready,
        ea_address    => int_ea_address
    );

    execution_unit : M68020_execute
    port map (
        clk           => clk,
        reset         => reset,
        stage_d       => int_stage_d,
        op_is_nop     => int_op_nop,
        op_is_illegal => int_op_illegal,
        ea_address    => int_ea_address,
        ea_ready      => int_ea_ready,
        exec_done     => int_exec_done
    );

    bus_controller : M68020_bus_ctrl
    port map (
        clk           => clk,
        reset         => reset,
        int_req       => int_bus_req,
        int_rw        => int_bus_rw,
        int_addr      => int_bus_addr,
        int_data_w    => int_bus_data_w,
        int_data_r    => int_bus_data_r,
        int_busy      => int_bus_busy,
        ext_addr      => address_bus,
        ext_data_in   => data_in,
        ext_data_out  => data_out,
        ext_as_n      => as_n,
        ext_ds_n      => ds_n,
        ext_rw        => rw,
        dsack0_n      => dsack0_n,
        dsack1_n      => dsack1_n
    );

    -- =================================================================
    -- 4. KOMBINATORISCHER PROZESS (Berechnung von next_state & Bussen)
    -- =================================================================
    process(current_state, int_bus_busy, reg_pc, int_exec_done)
    begin
        -- Standard-Zuweisungen (Verhindert Latches)
        next_state     <= current_state;
        int_bus_req    <= '0';
        int_bus_rw     <= '1';
        int_bus_addr   <= (others => '0');
        int_pipe_hold  <= '0';
        int_pipe_flush <= '0';
        int_ea_start   <= '0';

        case current_state is

            when ST_INIT =>
                next_state <= ST_RESET_SSP;

            -- 1. Schritt: SSP von $00000000 abrufen
            when ST_RESET_SSP =>
                int_bus_addr  <= x"00000000";
                int_bus_rw    <= '1';
                int_pipe_hold <= '1';
                int_bus_req   <= '1'; -- Request dauerhaft halten im Zustand

                -- Sobald der Bus-Controller fertig meldet (busy geht auf 0),
                -- schalten wir verzögerungsfrei auf das nächste Ziel um!
                if int_bus_busy = '0' then
                    next_state <= ST_RESET_PC;
                end if;

            -- 2. Schritt: Start-PC von $00000004 abrufen
            when ST_RESET_PC =>
                int_bus_addr  <= x"00000004";
                int_bus_rw    <= '1';
                int_pipe_hold <= '1';
                int_bus_req   <= '1';

                if int_bus_busy = '0' then
                    next_state <= ST_PREFETCH_1;
                end if;

            -- 3. Schritt: Erstes Wort vorladen (Prefetch)
            when ST_PREFETCH_1 =>
                int_bus_addr  <= reg_pc;
                int_bus_rw    <= '1';
                int_pipe_hold <= '1';
                int_bus_req   <= '1';

                if int_bus_busy = '0' then
                    next_state <= ST_PREFETCH_2;
                end if;

            -- 4. Schritt: Zweites Wort vorladen (Pipeline füllen)
            when ST_PREFETCH_2 =>
                int_bus_addr  <= reg_pc;
                int_bus_rw    <= '1';
                int_pipe_hold <= '1';
                int_bus_req   <= '1';

                if int_bus_busy = '0' then
                    next_state <= ST_FETCH;
                end if;

            -- Normaler Zyklus: Befehl prüfen
            when ST_FETCH =>
                next_state <= ST_DECODE;

            -- Normaler Zyklus: Dekodieren
            when ST_DECODE =>
                int_ea_start <= '1';
                next_state   <= ST_EXECUTE;

            -- Normaler Zyklus: Ausführen
            when ST_EXECUTE =>
                int_pipe_hold <= '1';
                if int_exec_done = '1' then
                    next_state <= ST_FETCH;
                end if;

            when others =>
                next_state <= ST_INIT;
        end case;
    end process;

    -- =================================================================
    -- 5. SEQUENZIELLER PROZESS (Zustandswechsel & Register laden)
    -- =================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            current_state  <= ST_INIT;
            reg_pc         <= (others => '0');
            reg_ssp        <= (others => '0');
            fc             <= "110"; -- Supervisor Program Space
            siz0           <= '0';
            siz1           <= '0';
            int_bus_data_w <= (others => '0');
        elsif rising_edge(clk) then
            current_state <= next_state;
            
            -- Standard-Ausgänge besetzen
            fc   <= "110";
            siz0 <= '0';
            siz1 <= '0';

            -- Synchrones Übernehmen der Bus-Daten an den Zustandsgrenzen
            case current_state is
                when ST_RESET_SSP =>
                    if int_bus_busy = '0' then
                        reg_ssp <= int_bus_data_r;
                    end if;

                when ST_RESET_PC =>
                    if int_bus_busy = '0' then
                        reg_pc <= int_bus_data_r;
                    end if;

                when ST_PREFETCH_1 =>
                    if int_bus_busy = '0' then
                        reg_pc <= std_logic_vector(unsigned(reg_pc) + 2);
                    end if;

                when ST_PREFETCH_2 =>
                    if int_bus_busy = '0' then
                        reg_pc <= std_logic_vector(unsigned(reg_pc) + 2);
                    end if;

                when ST_EXECUTE =>
                    if int_exec_done = '1' then
                        reg_pc <= std_logic_vector(unsigned(reg_pc) + 2);
                    end if;

                when others =>
                    null;
            end case;

            -- =================================================================
            -- DEEP-TRACING DIAGNOSE-LOG FÜR MODELSIM (Simulation Only)
            -- =================================================================
            -- pragma translate_off
            if current_state /= ST_INIT then
                report "Time: " & time'image(now) & 
                       " | CPU_State: " & cpu_state_type'image(current_state) &
                       " | PC: " & to_hstring(reg_pc) &
                       " | AS_N: " & std_logic'image(as_n) &
                       " | DSACK: " & std_logic'image(dsack0_n) & std_logic'image(dsack1_n) &
                       " | [BUS-INTF] REQ: " & std_logic'image(int_bus_req) &
                       " BUSY: " & std_logic'image(int_bus_busy) &
                       " ADDR: " & to_hstring(int_bus_addr);
            end if;
            -- pragma translate_on

        end if;
    end process;

end Behavioral;
