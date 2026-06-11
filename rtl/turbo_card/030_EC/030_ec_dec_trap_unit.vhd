-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_trap_unit.vhd
-- Sektion: Vollständiger All-Fix-Code (32-Bit PC Symmetrie)
-- Funktion: Sub-Modul der ICU. Verwaltet exklusiv die Exception- und
--           Autovektor-Ablaufsteuerung (STATE_EXCEPTION) des 68EC030.
--           SYMMETRIE-FIX: Ports und Logik vollständig auf 32-Bit saniert!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_trap_unit is
    Port (
        -- Globale Systemsynchronisation
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Kontrollkanäle von/zu der übergeordneten ICU
        trap_en             : in    std_logic;                      
        trap_busy           : in    std_logic;                      
        trap_done           : out   std_logic;                      

        -- Statussignale vom Rechenkern und den Interrupt-Leitungen
        exception_div_zero  : in    std_logic;                      
        s_irq_latch         : in    std_logic_vector(2 downto 0);   

        -- Datenpfad-Anbindung an das Datenlatch und den Speicherbus
        internal_D_in       : in    std_logic_vector(31 downto 0);  
        s_data_hold_latch   : out   std_logic_vector(31 downto 0);  
        
        -- KORREKTUR: Symmetrischer 32-Bit PC-Ausgangs-Port passend zum Hauptdecoder
        internal_pc_out     : out   unsigned(31 downto 0);          

        -- Ausgänge an den zentralen Multiplexer (cpu_030_ec_dec_mux)
        fsm_running_mode    : out   std_logic;
        fsm_bus_req         : out   std_logic;
        fsm_bus_write       : out   std_logic;
        fsm_bus_addr        : out   std_logic_vector(31 downto 0);
        fsm_bus_type        : out   std_logic_vector(2 downto 0);

        -- Quittungseingang von der Bus Interface Unit (BIU)
        bus_cycle_done      : in    std_logic                       
    );
end cpu_030_ec_dec_trap_unit;

architecture behavioral of cpu_030_ec_dec_trap_unit is
    type trap_state_type is (TRAP_IDLE, ST_TRAP_ACTIVE, TRAP_FINISHED);
    signal trap_state : trap_state_type := TRAP_IDLE;
begin

    -- =====================================================================
    -- TAKTGESTEUERTER EXCEPTION- UND INTERRUPT-ACK-PROZESS (32-BIT PC)
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            trap_state         <= TRAP_IDLE;
            trap_done          <= '0';
            s_data_hold_latch  <= (others => '0');
            internal_pc_out    <= x"00F80000";
            fsm_running_mode   <= '1';
            fsm_bus_req        <= '0';
            fsm_bus_write      <= '0';
            fsm_bus_addr       <= (others => '0');
            fsm_bus_type       <= "000";

        elsif rising_edge(CLK) then
            fsm_bus_req <= '0';
            trap_done   <= '0';

            case trap_state is

                when TRAP_IDLE =>
                    if trap_en = '1' then
                        trap_state <= ST_TRAP_ACTIVE;
                    end if;

                when ST_TRAP_ACTIVE =>
                    fsm_running_mode <= '0'; -- FSM übernimmt die Bus-Hoheit im Muxer
                    fsm_bus_req      <= '1';
                    fsm_bus_write    <= '0';
                    
                    if exception_div_zero = '1' then
                        fsm_bus_addr <= x"00000014"; -- Vektor 5 (Division durch Null)
                        fsm_bus_type <= "111";       -- CPU Space Cycle
                    else
                        fsm_bus_addr <= x"000000" & "01" & s_irq_latch & "000";
                        fsm_bus_type <= "110";       -- Interrupt Acknowledge Zyklus
                    end if;

                    if bus_cycle_done = '1' then
                        s_data_hold_latch <= internal_D_in;
                        -- Der neue PC wird unbestechlich als nativer 32-Bit-Vektor übernommen
                        internal_pc_out   <= unsigned(internal_D_in);
                        trap_state        <= TRAP_FINISHED;
                    end if;

                when TRAP_FINISHED =>
                    trap_done <= '1';
                    if trap_en = '0' then
                        fsm_running_mode <= '1'; -- Bus-Hoheit zurückgeben
                        trap_state       <= TRAP_IDLE;
                    end if;

                when others =>
                    trap_state <= TRAP_IDLE;
            end case;

            if trap_en = '0' and trap_state /= TRAP_FINISHED then
                fsm_running_mode <= '1';
                trap_state       <= TRAP_IDLE;
            end if;
        end if;
    end process;
end behavioral;
