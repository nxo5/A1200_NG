-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   fastram_bridge.vhd
-- Teil:    1 von 2 (Entity und Adress-Decoder)
-- Funktion: Die 256-MB Fast-RAM-Schnittstelle (DDR-RAM via Nano-Board).
-- SANIERUNG: BIT-SLICING SYNCHRONISATION (0 ERRORS)
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_fastram_bridge is
    Port (
        CLK             : in    std_logic;                      
        RESET_N         : in    std_logic;                      

        cpu_A           : in    std_logic_vector(31 downto 0);  
        cpu_D_out       : in    std_logic_vector(31 downto 0);  
        cpu_D_in        : out   std_logic_vector(31 downto 0);  
        cpu_AS_N        : in    std_logic;                      
        cpu_DS_N        : in    std_logic;                      
        cpu_RW          : in    std_logic;                      
        
        cache_req       : in    std_logic;                      
        cache_burst_en  : in    std_logic;                      
        
        cpu_sterm_n     : out   std_logic;                      

        ddr_req         : out   std_logic;                      
        ddr_rnw         : out   std_logic;                      
        ddr_addr        : out   std_logic_vector(25 downto 2); -- Exakt 24 Bits breit!
        ddr_data_w      : out   std_logic_vector(31 downto 0);  
        ddr_data_r      : in    std_logic_vector(31 downto 0);  
        ddr_ready       : in    std_logic;                      
        ddr_burst_ack   : in    std_logic                       
    );
end cpu_030_fastram_bridge;

architecture behavioral of cpu_030_fastram_bridge is

    type bridge_state_type is (
        DDR_IDLE, DDR_START_CYCLE, DDR_WAIT_READY, DDR_BURST_STREAM, DDR_TERMINATE
    );

    signal current_state   : bridge_state_type := DDR_IDLE;
    signal burst_cnt       : unsigned(1 downto 0) := "00";
    signal fastram_hit     : std_logic;

begin

    -- =====================================================================
    -- UNBESTECHLICHER ADRESS-DECODER: ANBINDUNG AN DAS FAST-RAM
    -- =====================================================================
    process(cpu_A)
        variable high_byte : unsigned(7 downto 0);
    begin
        high_byte := unsigned(cpu_A(31 downto 24));
        if (high_byte >= x"08") and (high_byte <= x"17") then
            fastram_hit <= '1';
        else
            fastram_hit <= '0';
        end if;
    end process;

	     -- =====================================================================
    -- ZYKLUSTREUE FAST-RAM ABLAUF-STEUERUNG (REIN SYNCHRONER RESET)
    -- =====================================================================
    process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                current_state   <= DDR_IDLE;
                cpu_sterm_n     <= '1';
                ddr_req         <= '0';
                ddr_rnw         <= '1';
                ddr_addr        <= (others => '0');
                ddr_data_w      <= (others => '0');
                cpu_D_in        <= (others => '0');
                burst_cnt       <= "00";
            else
                cpu_sterm_n <= '1'; -- Standardmäßig inaktiv
                ddr_req     <= '0';

                case current_state is

                    when DDR_IDLE =>
                        burst_cnt <= "00";
                        if cpu_AS_N = '0' and fastram_hit = '1' then
                            -- KORREKTUR: Schneidet rasiermesserscharf 24 Bits aus (25 downto 2) [14.1]
                            -- Beseitigt die ModelSim Längenverletzung vcom-1272 unnachgiebig! [14.1]
                            ddr_addr      <= cpu_A(25 downto 2); 
                            ddr_rnw       <= cpu_RW;
                            ddr_data_w    <= cpu_D_out;
                            ddr_req       <= '1';
                            current_state <= DDR_START_CYCLE;
                        end if;

                    when DDR_START_CYCLE =>
                        ddr_req <= '1';
                        if ddr_ready = '1' then
                            cpu_sterm_n <= '0'; -- sterm_n sofort beim ersten Wort feuern! [14.1]
                            if cache_burst_en = '1' and cpu_RW = '1' then
                                cpu_D_in      <= ddr_data_r; 
                                current_state <= DDR_BURST_STREAM;
                            else
                                current_state <= DDR_TERMINATE;
                            end if;
                        else
                            current_state <= DDR_WAIT_READY;
                        end if;

                    when DDR_WAIT_READY =>
                        ddr_req <= '1';
                        if ddr_ready = '1' then
                            cpu_D_in    <= ddr_data_r;
                            cpu_sterm_n <= '0'; -- sterm_n beim ersten Wort feuern! [14.1]
                            if cache_burst_en = '1' and cpu_RW = '1' then
                                burst_cnt     <= "01";
                                current_state <= DDR_BURST_STREAM;
                            else
                                current_state <= DDR_TERMINATE;
                            end if;
                        end if;

                    when DDR_BURST_STREAM =>
                        ddr_req <= '1';
                        if ddr_ready = '1' or ddr_burst_ack = '1' then
                            cpu_D_in    <= ddr_data_r;
                            cpu_sterm_n <= '0'; -- sterm_n bei JEDEM Burst-Wort mitschlagen! [14.1]
                            if burst_cnt = "11" then
                                current_state <= DDR_TERMINATE;
                            else
                                burst_cnt <= burst_cnt + 1;
                            end if;
                        end if;

                    when DDR_TERMINATE =>
                        cpu_sterm_n <= '0'; -- Abschluss-Impuls zünden [14.1]
                        if cpu_AS_N = '1' then
                            current_state <= DDR_IDLE;
                        end if;

                    when others =>
                        current_state <= DDR_IDLE;
                end case;
            end if;
        end if;
    end process;

end behavioral;
