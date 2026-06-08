library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity paula_uart is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTERWERK (VON PAULA_REGS.VHD)
        -- =============================================================
        uart_period   : in    std_logic_vector(14 downto 0); -- Baudraten-Teilerwert aus SERPER
        uart_data_w   : in    std_logic_vector(8 downto 0);  -- Zu sendende Daten (9-Bit fähig)
        uart_tx_start : in    std_logic;                     -- CPU triggert Sendevorgang
        
        -- NEU VERDRAHTET: Das Lese-Quittierungssignal vom Registerblock
        uart_read_strobe : in std_logic;                     -- '1' löscht das rx_data_ready Flag augenblicklich
        
        uart_data_r   : out   std_logic_vector(15 downto 0); -- Status- und Empfangsdaten für CPU
        
        -- =============================================================
        -- 3. PHYSISCHE SERIELLE PINS NACH AUSSEN (UART-SCHNITTSTELLE)
        -- =============================================================
        rxd           : in    std_logic;                     -- Physische Empfangsleitung (Receive Data)
        txd           : out   std_logic;                     -- Physische Sendeleitung (Transmit Data)
        
        -- =============================================================
        -- 4. STATUSMELDUNGEN AN DAS INTERRUPT-SYSTEM VON PAULA
        -- =============================================================
        uart_rx_irq   : out   std_logic;                     
        uart_tx_irq   : out   std_logic                      
    );
end paula_uart;

architecture Behavioral of paula_uart is

    -- Baudraten-Zähler (Herunterteiler basierend auf uart_period)
    signal baud_cnt       : unsigned(14 downto 0) := (others => '0');
    signal baud_tick      : std_logic := '0';
    
    -- Empfänger-Zustandsmaschine (RX-FSM)
    type rx_state_t is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state       : rx_state_t := RX_IDLE;
    signal rx_baud_cnt    : integer range 0 to 15 := 0; 
    signal rx_bit_cnt     : integer range 0 to 8 := 0;
    signal rx_shift_reg   : std_logic_vector(8 downto 0) := (others => '0');
    signal rx_buf         : std_logic_vector(8 downto 0) := (others => '0');
    
    -- Die operativen Statusregister für das CPU-Interface
    signal rx_data_ready  : std_logic := '0';
    signal rx_overrun     : std_logic := '0';
    
    -- Sender-Zustandsmaschine (TX-FSM)
    type tx_state_t is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state       : tx_state_t := TX_IDLE;
    signal tx_bit_cnt     : integer range 0 to 8 := 0;
    signal tx_shift_reg   : std_logic_vector(8 downto 0) := (others => '0');
    signal tx_buffer_empty: std_logic := '1';

begin

    -- Datenbus-Zuweisung für das CPU-Register SERDATR ($DFF018)
    uart_data_r(15)           <= tx_buffer_empty; 
    uart_data_r(14)           <= rx_overrun;      
    uart_data_r(13)           <= rx_data_ready;   
    uart_data_r(12 downto 9)  <= (others => '0'); 
    uart_data_r(8 downto 0)   <= rx_buf;          

    -- =================================================================
    -- 1. DER INTEGRATIVE BAUDRATEN-GENERATOR
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            baud_cnt  <= (others => '0');
            baud_tick <= '0';
        elsif rising_edge(clk_amiga) then
            baud_tick <= '0';
            if baud_cnt = x"0000" then
                baud_cnt  <= unsigned(uart_period);
                baud_tick <= '1'; 
            else
                baud_cnt <= baud_cnt - 1;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. OPERATIVER EMPFÄNGER-PROZESS (RX-Oversampling-Getriebe)
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            rx_state      <= RX_IDLE;
            rx_baud_cnt   <= 0;
            rx_bit_cnt    <= 0;
            rx_shift_reg  <= (others => '0');
            rx_buf        <= (others => '0');
            rx_data_ready <= '0';
            rx_overrun    <= '0';
            uart_rx_irq   <= '0';
        elsif rising_edge(clk_amiga) then
            uart_rx_irq <= '0';

            -- HARDWARE-AUTOMATISMUS: Löschen des Ready-Flags bei CPU-Lesen
            if uart_read_strobe = '1' then
                rx_data_ready <= '0';
                rx_overrun    <= '0'; -- Auch den Overrun-Fehler beim Lesen zurücksetzen
            end if;

            case rx_state is
                when RX_IDLE =>
                    rx_baud_cnt <= 0;
                    if rxd = '0' then
                        rx_state <= RX_START;
                    end if;

                when RX_START =>
                    if baud_tick = '1' then
                        if rx_baud_cnt = 7 then
                            if rxd = '0' then
                                rx_baud_cnt <= 0;
                                rx_bit_cnt  <= 0;
                                rx_state    <= RX_DATA;
                            else
                                rx_state <= RX_IDLE;
                            end if;
                        else
                            rx_baud_cnt <= rx_baud_cnt + 1;
                        end if;
                    end if;

                when RX_DATA =>
                    if baud_tick = '1' then
                        if rx_baud_cnt = 15 then
                            rx_baud_cnt <= 0;
                            rx_shift_reg <= rxd & rx_shift_reg(8 downto 1);
                            
                            if rx_bit_cnt = 8 then
                                rx_state <= RX_STOP;
                            else
                                rx_bit_cnt <= rx_bit_cnt + 1;
                            end if;
                        else
                            rx_baud_cnt <= rx_baud_cnt + 1;
                        end if;
                    end if;

                when RX_STOP =>
                    if baud_tick = '1' then
                        if rx_baud_cnt = 15 then
                            if rxd = '1' then
                                if rx_data_ready = '1' then
                                    rx_overrun <= '1';
                                end if;
                                rx_buf        <= rx_shift_reg;
                                rx_data_ready <= '1';
                                uart_rx_irq   <= '1'; -- Interrupt zünden
                            end if;
                            rx_state <= RX_IDLE;
                        else
                            rx_baud_cnt <= rx_baud_cnt + 1;
                        end if;
                    end if;
            end case;
        end if;
    end process;

    -- =================================================================
    -- 3. OPERATIVER SENDER-PROZESS (TX-Baud-Takt-Schleife)
    -- =================================================================
    process(clk_amiga, reset)
        variable shift_out_var : std_logic_vector(8 downto 0) := (others => '1');
        variable bits_sent_var : integer range 0 to 9 := 0;
    begin
        if reset = '1' then
            tx_state        <= TX_IDLE;
            txd             <= '1';
            shift_out_var   := (others => '1');
            bits_sent_var   := 0;
            tx_buffer_empty <= '1';
            uart_tx_irq     <= '0';
        elsif rising_edge(clk_amiga) then
            uart_tx_irq <= '0';

            if uart_tx_start = '1' then
                shift_out_var   := uart_data_w;
                tx_buffer_empty <= '0';
            end if;

            case tx_state is
                when TX_IDLE =>
                    txd <= '1';
                    if tx_buffer_empty = '0' then
                        tx_state <= TX_START;
                    end if;

                when TX_START =>
                    if baud_tick = '1' then
                        txd           <= '0';
                        bits_sent_var := 0;
                        tx_state      <= TX_DATA;
                    end if;

                when TX_DATA =>
                    if baud_tick = '1' then
                        txd <= shift_out_var(0); 
                        shift_out_var := '1' & shift_out_var(8 downto 1);
                        
                        if bits_sent_var = 8 then
                            tx_state <= TX_STOP;
                        else
                            bits_sent_var := bits_sent_var + 1;
                        end if;
                    end if;

                when TX_STOP =>
                    if baud_tick = '1' then
                        txd             <= '1';
                        tx_buffer_empty <= '1';
                        uart_tx_irq     <= '1';
                        tx_state        <= TX_IDLE;
                    end if;
            end case;
        end if;
    end process;

end Behavioral;
