-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_boot_fsm.vhd
-- Sektion: Vollständiger All-Fix-Code (32-Bit PC Symmetrie)
-- Funktion: Sub-Modul der ICU. Verwaltet exklusiv die Vektor-Einzugsphasen
--           STATE_BOOT_0 und STATE_BOOT_1 beim CPU-Kaltstart.
--           SYMMETRIE-FIX: Ports und Logik vollständig auf 32-Bit saniert!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_boot_fsm is
    Port (
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;
        boot_en             : in    std_logic;                      
        boot_busy           : in    std_logic;                      
        boot_done           : out   std_logic;                      

        -- KORREKTUR: Symmetrische 32-Bit PC-Ports passend zum Hauptdecoder
        internal_pc_in      : in    unsigned(31 downto 0);          
        internal_pc_out     : out   unsigned(31 downto 0);          
        internal_D_in       : in    std_logic_vector(31 downto 0);  

        fsm_bus_req         : out   std_logic;
        fsm_bus_write       : out   std_logic;
        fsm_bus_addr        : out   std_logic_vector(31 downto 0);
        fsm_bus_type        : out   std_logic_vector(2 downto 0);

        boot_ssp_load       : out   std_logic;
        boot_ssp_new        : out   std_logic_vector(31 downto 0);
        boot_pc_load        : out   std_logic;
        boot_pc_new         : out   std_logic_vector(31 downto 0)
    );
end cpu_030_ec_dec_boot_fsm;

architecture behavioral of cpu_030_ec_dec_boot_fsm is
    type boot_state_type is (BOOT_IDLE, ST_BOOT_0, ST_BOOT_1, BOOT_FINISHED);
    signal boot_state : boot_state_type := BOOT_IDLE;
begin

    process(CLK, RESET_N)
        variable boot_word_align : std_logic_vector(31 downto 0);
    begin
        if RESET_N = '0' then
            boot_state      <= BOOT_IDLE;
            boot_done       <= '0';
            internal_pc_out <= x"00F80000"; 
            fsm_bus_req     <= '0';
            fsm_bus_write   <= '0';
            fsm_bus_addr    <= (others => '0');
            fsm_bus_type    <= "000";
            boot_ssp_load   <= '0';
            boot_ssp_new    <= (others => '0');
            boot_pc_load    <= '0';
            boot_pc_new     <= (others => '0');

        elsif rising_edge(CLK) then
            boot_ssp_load <= '0';
            boot_pc_load  <= '0';
            fsm_bus_req   <= '0';

            case boot_state is
                when BOOT_IDLE =>
                    boot_done <= '0';
                    if boot_en = '1' then
                        boot_state <= ST_BOOT_0;
                    end if;

                when ST_BOOT_0 =>
                    fsm_bus_req   <= '1';
                    fsm_bus_write <= '0';
                    -- HEBEL 1: Bit 0 wird hardwareseitig fest auf '0' maskiert (Carry-schonend!)
                    fsm_bus_addr  <= std_logic_vector(internal_pc_in(31 downto 1)) & '0';
                    fsm_bus_type  <= "101"; 

                    if boot_busy = '0' then
                        if internal_D_in(31 downto 16) = x"0000" or internal_D_in(31 downto 16) = x"FFFF" then
                            boot_word_align := internal_D_in(15 downto 0) & internal_D_in(15 downto 0);
                        else
                            boot_word_align := internal_D_in;
                        end if;

                        boot_ssp_load   <= '1';
                        boot_ssp_new    <= boot_word_align;
                        -- Zyklustreuer Vorschub im 32-Bit Raster (+4 Bytes)
                        internal_pc_out <= internal_pc_in + 4;
                        boot_state      <= ST_BOOT_1;
                    end if;

                when ST_BOOT_1 =>
                    fsm_bus_req   <= '1';
                    fsm_bus_write <= '0';
                    fsm_bus_addr  <= std_logic_vector(internal_pc_in(31 downto 1)) & '0';
                    fsm_bus_type  <= "101";

                    if boot_busy = '0' then
                        if internal_D_in(31 downto 16) = x"0000" or internal_D_in(31 downto 16) = x"FFFF" then
                            boot_word_align := internal_D_in(15 downto 0) & internal_D_in(15 downto 0);
                        else
                            boot_word_align := internal_D_in;
                        end if;

                        boot_pc_load    <= '1';
                        boot_pc_new     <= boot_word_align;
                        -- Der neue PC wird als nativer 32-Bit-Vektor übernommen, Bit 0 wird im Prozess maskiert
                        internal_pc_out <= unsigned(boot_word_align);
                        boot_state      <= BOOT_FINISHED;
                    end if;

                when BOOT_FINISHED =>
                    boot_done <= '1';
                    if boot_en = '0' then
                        boot_state <= BOOT_IDLE;
                    end if;

                when others =>
                    boot_state <= BOOT_IDLE;
            end case;
        end if;
    end process;
end behavioral;
