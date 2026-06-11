-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_exec_fsm.vhd
-- Sektion: Vollständiger All-Fix-Code (32-Bit PC Symmetrie)
-- Funktion: Sub-Modul der ICU. Verwaltet exklusiv die regulären Phasen
--           FETCH, DECODE, EXECUTE und WRITEBACK des 68EC030-Fließbands.
--           SYMMETRIE-FIX: Ports und Logik vollständig auf 32-Bit saniert!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_exec_fsm is
    Port (
        -- Globale Systemsynchronisation
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Kontrollkanäle von/zu der übergeordneten ICU
        exec_en             : in    std_logic;                      
        exec_busy           : in    std_logic;                      
        exec_irq_pending    : in    std_logic;                      
        exec_trap_pending   : in    std_logic;                      
        exec_trap_trigger   : out   std_logic;                      

        -- Datenpfad-Kopplung an die Pipeline und den Cache
        pipeline_word       : in    std_logic_vector(15 downto 0);  
        pipeline_req        : out   std_logic;                      
        cache_cpu_req       : out   std_logic;                      
        cache_hit           : in    std_logic;                      
        cache_miss          : in    std_logic;                      
        
        -- KORREKTUR: Symmetrische 32-Bit PC-Ports passend zum Hauptdecoder
        internal_pc_in      : in    unsigned(31 downto 0);          
        internal_pc_out     : out   unsigned(31 downto 0);          

        -- Ausgänge an den zentralen Multiplexer (Aktivitätsleitungen)
        s_fsm_running_mode  : out   std_logic;
        s_move_active       : out   std_logic;
        s_alu_active        : out   std_logic;
        s_special_active    : out   std_logic;

        -- Verbindungssignale zu den physischen Teildecodern
        dec_move_en         : out   std_logic;
        dec_move_ready      : in    std_logic;
        dec_alu_en          : out   std_logic;
        s_alu_decoder_done  : in    std_logic;
        dec_branch_en       : out   std_logic;
        dec_branch_ready    : in    std_logic;
        dec_special_en      : out   std_logic;
        dec_special_ready   : in    std_logic;

        -- Direkte Steuerleitungen vom Branch-Decoder für Sprünge
        s_branch_pc_load    : in    std_logic;
        s_branch_pc_new     : in    std_logic_vector(31 downto 0);

        -- Hardware-Sicherungs-Ausgänge für Cache-Inhibit-Verriegelung
        s_cache_inhibit_act : out   std_logic;
        bus_cycle_done      : in    std_logic
    );
end cpu_030_ec_dec_exec_fsm;

architecture behavioral of cpu_030_ec_dec_exec_fsm is
    type exec_state_type is (ST_IDLE, ST_FETCH, ST_DECODE, ST_EXECUTE, ST_WRITEBACK);
    signal current_state : exec_state_type := ST_IDLE;
    
    signal r_opcode           : std_logic_vector(15 downto 0) := (others => '0');
    signal r_cache_inhibit    : std_logic := '0';
    signal s_dec_branch_en_i  : std_logic := '0';
begin

    s_cache_inhibit_act <= r_cache_inhibit;
    dec_branch_en       <= s_dec_branch_en_i;

    -- =====================================================================
    -- TAKTGESTEUERTER BEFEHLS-PREFETCH- UND EXECUTE-PROZESS (32-BIT PC)
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            current_state       <= ST_IDLE;
            pipeline_req        <= '0';
            cache_cpu_req       <= '0';
            internal_pc_out     <= x"00F80000";
            s_fsm_running_mode  <= '1';
            s_move_active       <= '0';
            s_alu_active        <= '0';
            s_special_active    <= '0';
            dec_move_en         <= '0';
            dec_alu_en          <= '0';
            s_dec_branch_en_i   <= '0';
            dec_special_en      <= '0';
            exec_trap_trigger   <= '0';
            r_opcode            <= (others => '0');
            r_cache_inhibit     <= '0';

        elsif rising_edge(CLK) then
            pipeline_req      <= '0';
            exec_trap_trigger <= '0';

            if exec_busy = '0' then
                case current_state is

                    when ST_IDLE =>
                        if exec_en = '1' then
                            current_state <= ST_FETCH;
                        end if;

                    when ST_FETCH =>
                        s_fsm_running_mode <= '1';
                        s_move_active      <= '0';
                        s_alu_active       <= '0';
                        s_special_active   <= '0';
                        r_cache_inhibit    <= '0';
                        
                        cache_cpu_req      <= '1';
                        pipeline_req       <= '1';

                        if exec_irq_pending = '1' then
                            exec_trap_trigger <= '1'; 
                            current_state     <= ST_IDLE;
                        elsif cache_hit = '1' then
                            r_opcode      <= pipeline_word;
                            pipeline_req  <= '0';
                            cache_cpu_req <= '0';
                            current_state <= ST_DECODE;
                        elsif cache_miss = '1' then
                            -- HEBEL 1 OPTIMIERUNG: Bit 0 wird für die Adressraum-Prüfung ignoriert
                            if internal_pc_in(31 downto 24) = x"00" then
                                r_cache_inhibit <= '1';
                            end if;
                            s_special_active <= '1';
                            current_state    <= ST_DECODE;
                        end if;

                    when ST_DECODE =>
                        dec_move_en       <= '0';
                        dec_alu_en        <= '0';
                        s_dec_branch_en_i <= '0';
                        dec_special_en    <= '0';

                        if r_opcode(15 downto 12) = "0001" or r_opcode(15 downto 12) = "0010" or r_opcode(15 downto 12) = "0011" then
                            dec_move_en   <= '1';
                            s_move_active <= '1';
                            current_state <= ST_EXECUTE;
                        elsif r_opcode(15 downto 12) = "0100" and r_opcode(11 downto 6) = "101111" then
                            dec_special_en   <= '1';
                            s_special_active <= '1';
                            current_state    <= ST_EXECUTE;
                        elsif r_opcode(15 downto 12) = "0110" then
                            s_dec_branch_en_i <= '1';
                            current_state     <= ST_EXECUTE;
                        else
                            dec_alu_en   <= '1';
                            s_alu_active <= '1';
                            current_state <= ST_EXECUTE;
                        end if;

                    when ST_EXECUTE =>
                        if s_dec_branch_en_i = '1' and s_branch_pc_load = '1' then
                            -- Sprungadresse direkt als 32-Bit übernehmen, Bit 0 wird im Hauptdecoder auf 0 gezwungen
                            internal_pc_out <= unsigned(s_branch_pc_new);
                        end if;

                        if exec_trap_pending = '1' then
                            exec_trap_trigger <= '1';
                            current_state     <= ST_IDLE;
                        elsif r_cache_inhibit = '1' and bus_cycle_done = '1' then
                            current_state <= ST_WRITEBACK;
                        elsif dec_move_ready = '1' or s_alu_decoder_done = '1' or dec_branch_ready = '1' or dec_special_ready = '1' then
                            current_state <= ST_WRITEBACK;
                        end if;

                    when ST_WRITEBACK =>
                        dec_move_en       <= '0';
                        dec_alu_en        <= '0';
                        s_dec_branch_en_i <= '0';
                        dec_special_en    <= '0';

                        -- HEBEL 1 OPTIMIERUNG: Zyklustreuer +2 Byte Vorschub im 32-Bit Raster
                        if r_opcode(15 downto 12) /= "0110" or s_branch_pc_load = '0' then
                            internal_pc_out <= internal_pc_in + 2;
                        end if;
                        
                        current_state <= ST_FETCH;

                    when others =>
                        current_state <= ST_IDLE;
                end case;
            end if;
            
            if exec_en = '0' then
                current_state <= ST_IDLE;
            end if;
        end if;
    end process;
end behavioral;
