-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   sdram_bridge.vhd
-- Teil:    1 von 2 (Die echte, unidirektionale Gatter-Schnittstelle)
-- Funktion: Die getaktete 114-MHz SDR-SDRAM-Schnittstelle des Mainboards.
-- SANIERUNG Schritt 70 - REIN SYNCHRONER HARDWARE-RESET (0 ERRORS):
--   - Entfernt den asynchronen Reset zur Einhaltung der RAM-Spezifikation! [14.1]
--   - Schaltet alle Steuerleitungen phasengerecht und fehlerfrei ab. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sdram_bridge is
    Port (
        -- 1. TAKT- UND SYSTEMBASIS
        clk_amiga       : in    std_logic;
        clk_sdram       : in    std_logic;
        reset           : in    std_logic; -- Gekoppelt an s_ram_reset vom Board [14.1]
        
        -- 2. INNENWELT: GEKOPPELT AN DEN RAM-DECODER & MASTER-BUS
        dec_sb_addr     : in    std_logic_vector(26 downto 0);
        dec_sb_req      : in    std_logic;
        dec_sb_is_chip  : in    std_logic;
        
        am_data_in      : in    std_logic_vector(31 downto 0); 
        am_data_out     : out   std_logic_vector(31 downto 0); 
        
        am_as_n         : in    std_logic;
        am_ds_n         : in    std_logic;
        am_rw           : in    std_logic;
        
        am_siz0         : in    std_logic;
        am_siz1         : in    std_logic;
        
        am_dsack0_n     : out   std_logic;
        am_dsack1_n     : out   std_logic;
        
        -- INTERFACES FÜR DEN DIREKTEN KICKSTART-DOWNLOAD
        i_ks_download   : in    std_logic;                     
        i_ks_addr       : in    std_logic_vector(26 downto 2); 
        i_ks_data_w     : in    std_logic_vector(31 downto 0); 
        i_ks_we         : in    std_logic;                     
        
        -- 3. AUSSENWELT: FIXE PHYSISCHE PINS ZUM MISTER-SDRAM-BOARD
        sdram_clk       : out   std_logic;
        sdram_data      : inout std_logic_vector(15 downto 0); 
        sdram_addr      : out   std_logic_vector(12 downto 0);
        sdram_ba        : out   std_logic_vector(1 downto 0);
        sdram_ras_n     : out   std_logic;
        sdram_cas_n     : out   std_logic;
        sdram_we_n      : out   std_logic;
        sdram_dqm_lo    : out   std_logic;
        sdram_dqm_hi    : out   std_logic
    );
end sdram_bridge;

architecture Behavioral of sdram_bridge is

    type sdram_fsm_type is (
        SD_IDLE, SD_PRECHARGE, SD_ACTIVATE, SD_CMD_1, SD_WAIT_1, SD_CMD_2, SD_WAIT_2, SD_ACK_PULSE, SD_CLEANUP,
        SD_BOOT_WRITE_1, SD_BOOT_WAIT_1, SD_BOOT_WRITE_2, SD_BOOT_WAIT_2
    );

    signal current_state : sdram_fsm_type := SD_IDLE;

    signal as_n_r1, as_n_r2 : std_logic := '1';
    signal ds_n_r1, ds_n_r2 : std_logic := '1';

    signal reg_read_accumulator : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_write_buffer     : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_latched_addr     : std_logic_vector(26 downto 0) := (others => '0');

    signal internal_sdram_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal select_width         : std_logic_vector(3 downto 0)  := (others => '0');
    signal sdram_oe             : std_logic := '0';

    signal reg_dsack0_n         : std_logic := '1';
    signal reg_dsack1_n         : std_logic := '1';
    
    signal ks_we_r1, ks_we_r2   : std_logic := '0';

    	 begin

    sdram_clk <= clk_sdram;
    
    -- ECHTES TRI-STATE: Nur hier am physischen, externen Board-Pin erlaubt und zwingend nötig!
    sdram_data <= internal_sdram_out when sdram_oe = '1' else (others => 'Z');

    -- Replace internal tri-state driven ack outputs with direct signals (synth-safe)
    am_dsack0_n <= reg_dsack0_n;
    am_dsack1_n <= reg_dsack1_n;

    select_width <= am_siz1 & am_siz0 & reg_latched_addr(1 downto 0);

    -- =====================================================================
    -- KORREKTUR: ABSOLUT LOGISCHER DATEN-AUSLASS OHNE INTERNE TRI-STATES! [14.1]
    -- =====================================================================
    am_data_out <= reg_read_accumulator when (am_rw = '1' and reg_dsack1_n = '0') else (others => '0');

    -- =====================================================================
    -- PHYSISCHER OUTBOUND-MULTIPLEXER ZUM MISTER-BOARD (UNVERÄNDERT SAUBER)
    -- =====================================================================
    process(select_width, reg_write_buffer, current_state)
    begin
        internal_sdram_out <= (others => '0');
        sdram_dqm_hi       <= '1'; 
        sdram_dqm_lo       <= '1';

        if current_state = SD_CMD_1 or current_state = SD_CMD_2 then
            case select_width is
                when "0000" | "0001" | "0010" | "0011" =>
                    if current_state = SD_CMD_2 then internal_sdram_out <= reg_write_buffer(15 downto 0);
                    else internal_sdram_out <= reg_write_buffer(31 downto 16); end if;
                    sdram_dqm_hi <= '0'; sdram_dqm_lo <= '0';
                when "1000" | "1001" => internal_sdram_out <= reg_write_buffer(31 downto 16); sdram_dqm_hi <= '0'; sdram_dqm_lo <= '0';
                when "1010" | "1011" => internal_sdram_out <= reg_write_buffer(15 downto 0);  sdram_dqm_hi <= '0'; sdram_dqm_lo <= '0';
                when "0100" => internal_sdram_out <= reg_write_buffer(31 downto 24) & reg_write_buffer(31 downto 24); sdram_dqm_hi <= '0'; sdram_dqm_lo <= '1';
                when "0101" => internal_sdram_out <= reg_write_buffer(23 downto 16) & reg_write_buffer(23 downto 16); sdram_dqm_hi <= '1'; sdram_dqm_lo <= '0';
                when "0110" => internal_sdram_out <= reg_write_buffer(15 downto 8)  & reg_write_buffer(15 downto 8);  sdram_dqm_hi <= '0'; sdram_dqm_lo <= '1';
                when "0111" => internal_sdram_out <= reg_write_buffer(7 downto 0)   & reg_write_buffer(7 downto 0);   sdram_dqm_hi <= '1'; sdram_dqm_lo <= '0';
                when others => null;
             end case;
        elsif current_state = SD_BOOT_WRITE_1 or current_state = SD_BOOT_WRITE_2 then
            if current_state = SD_BOOT_WRITE_2 then internal_sdram_out <= reg_write_buffer(15 downto 0);
            else internal_sdram_out <= reg_write_buffer(31 downto 16); end if;
            sdram_dqm_hi <= '0'; sdram_dqm_lo <= '0';
        end if;
    end process;

    -- =====================================================================
    -- 4. CENTRAL 114-MHZ SIZING- AND COMMAND-FSM (REIN SYNCHRONER RESET)
    -- REPARIERT: Entfernt asynchrones Verhalten zur Einhaltung der Specs! [14.1]
    -- =========================================================================
    process(clk_sdram) -- HIER REPARIERT: Sensitivitätsliste enthält NUR noch den Takt! [14.1]
        variable row_addr : std_logic_vector(12 downto 0);
        variable col_addr : std_logic_vector(8 downto 0);
        variable bank_sel : std_logic_vector(1 downto 0);
    begin
        if rising_edge(clk_sdram) then
            -- -----------------------------------------------------------------
            -- SYNCHRONER HARDWARE-STARTPFAD (COMMODORE SPEZIFIKATIONSKONFORM) [14.1]
            -- -----------------------------------------------------------------
            if reset = '1' then
                current_state <= SD_IDLE; as_n_r1 <= '1'; as_n_r2 <= '1'; ds_n_r1 <= '1'; ds_n_r2 <= '1';
                ks_we_r1 <= '0'; ks_we_r2 <= '0'; reg_read_accumulator <= (others => '0');
                reg_write_buffer <= (others => '0'); reg_latched_addr <= (others => '0');
                sdram_oe <= '0'; sdram_addr <= (others => '0'); sdram_ba <= (others => '0');
                sdram_ras_n <= '1'; sdram_cas_n <= '1'; sdram_we_n <= '1'; reg_dsack0_n <= '1'; reg_dsack1_n <= '1';
            else
                -- REINER HARDWARE-REGELBETRIEB BEI FALLENDEM RESET [14.1]
                sdram_ras_n <= '1'; sdram_cas_n <= '1'; sdram_we_n <= '1'; reg_dsack0_n <= '1'; reg_dsack1_n <= '1';

                as_n_r1 <= am_as_n; as_n_r2 <= as_n_r1; ds_n_r1 <= am_ds_n; ds_n_r2 <= ds_n_r1;
                ks_we_r1 <= i_ks_we; ks_we_r2 <= ks_we_r1;

                row_addr := reg_latched_addr(21 downto 9); col_addr := reg_latched_addr(8 downto 0); bank_sel := reg_latched_addr(23 downto 22);

                case current_state is
                    when SD_IDLE =>
                        sdram_oe <= '0';
                        if i_ks_download = '1' then
                            if ks_we_r2 = '1' then
                                reg_latched_addr <= i_ks_addr & "00";
                                reg_write_buffer <= i_ks_data_w;
                                current_state    <= SD_PRECHARGE;
                            end if;
                        else
                            if as_n_r2 = '0' and dec_sb_req = '1' then
                                reg_latched_addr <= dec_sb_addr; 
                                reg_write_buffer <= am_data_in; 
                                current_state    <= SD_PRECHARGE;
                            end if;
                        end if;

                    when SD_PRECHARGE =>
                        sdram_ras_n <= '0'; sdram_cas_n <= '1'; sdram_we_n <= '0'; 
                        sdram_addr  <= (10 => '1', others => '0');
                        current_state <= SD_ACTIVATE;

                    when SD_ACTIVATE =>
                        sdram_ras_n <= '0'; sdram_ba <= bank_sel; sdram_addr <= row_addr;
                        if i_ks_download = '1' then current_state <= SD_BOOT_WRITE_1;
                        else current_state <= SD_CMD_1; end if;

                    when SD_CMD_1 =>
                        sdram_cas_n <= '0'; sdram_we_n <= am_rw; sdram_ba <= bank_sel; 
                        sdram_addr  <= "0000" & col_addr;
                        if am_rw = '0' then sdram_oe <= '1'; end if;
                        current_state <= SD_WAIT_1;

                    when SD_WAIT_1 =>
                        if am_rw = '0' then sdram_oe <= '1'; end if;
                        if am_rw = '1' then
                            case select_width is
                                when "0000" | "0001" | "0010" | "0011" => reg_read_accumulator(31 downto 16) <= sdram_data;
                                when "1000" | "1001" => reg_read_accumulator(31 downto 16) <= sdram_data;
                                when "1010" | "1011" => reg_read_accumulator(15 downto 0) <= sdram_data;
                                when "0100" => reg_read_accumulator(31 downto 24) <= sdram_data(15 downto 8);
                                when "0101" => reg_read_accumulator(23 downto 16) <= sdram_data(7 downto 0);
                                when "0110" => reg_read_accumulator(15 downto 8) <= sdram_data(15 downto 8);
                                when "0111" => reg_read_accumulator(7 downto 0) <= sdram_data(7 downto 0);
                                when others => null;
                            end case;
                        end if;
                        if select_width(3 downto 2) = "00" then current_state <= SD_CMD_2; else current_state <= SD_ACK_PULSE; end if;

                    when SD_CMD_2 =>
                        sdram_cas_n <= '0'; sdram_we_n <= am_rw; sdram_ba <= bank_sel; sdram_addr <= "0000" & std_logic_vector(unsigned(col_addr) + 2);
                        current_state <= SD_WAIT_2;

                    when SD_WAIT_2 =>
                        if am_rw = '0' then sdram_oe <= '1'; end if;
                        if am_rw = '1' then reg_read_accumulator(15 downto 0) <= sdram_data; end if;
                        current_state <= SD_ACK_PULSE;

                    when SD_ACK_PULSE =>
                        reg_dsack0_n <= '1'; reg_dsack1_n <= '0'; current_state <= SD_CLEANUP;

                    when SD_CLEANUP =>
                        reg_dsack0_n <= '1'; reg_dsack1_n <= '0';
                        if as_n_r2 = '1' then reg_dsack0_n <= '1'; reg_dsack1_n <= '1'; sdram_oe <= '0'; current_state <= SD_IDLE; end if;

                    when SD_BOOT_WRITE_1 =>
                        sdram_cas_n <= '0'; sdram_we_n <= '0'; sdram_ba <= bank_sel; 
                        sdram_addr  <= "0000" & col_addr;
                        sdram_oe    <= '1';
                        current_state <= SD_BOOT_WAIT_1;

                    when SD_BOOT_WAIT_1 =>
                        sdram_oe <= '1'; current_state <= SD_BOOT_WRITE_2;

                    when SD_BOOT_WRITE_2 =>
                        sdram_cas_n <= '0'; sdram_we_n <= '0'; sdram_ba <= bank_sel; 
                        sdram_addr  <= "0000" & std_logic_vector(unsigned(col_addr) + 2);
                        sdram_oe    <= '1';
                        current_state <= SD_BOOT_WAIT_2;

                    when SD_BOOT_WAIT_2 =>
                        sdram_oe <= '1';
                        if ks_we_r2 = '0' then sdram_oe <= '0'; current_state <= SD_IDLE; end if;

                    when others => current_state <= SD_IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
