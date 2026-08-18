-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   paula_regs.vhd
-- Funktion: Das Custom-Registerfeld und Interrupt-Schaltwerk von PAULA.
-- BEREINIGUNG SCHRITT 1:
--   - Erweiterung der Lautstärkeregister (CH0-CH3) von 6 auf 8 Bit! [14.1]
--   - Verhindert den Vektor-Breitenkonflikt (Width Mismatch) mit der Audio-Engine.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity paula_regs is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM CPU-REGISTERPFAD (VON PAULA.VHD)
        -- =============================================================
        reg_addr      : in    std_logic_vector(11 downto 0); -- Custom-Reg-Adresse ($DFFXXX)
        reg_data_w    : in    std_logic_vector(31 downto 0); -- Schreibdaten der CPU
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Register
        reg_read_en   : in    std_logic;                     -- CPU liest aus einem Register
        
        -- =============================================================
        -- 3. INTERNE VERBINDUNGEN ZU DEN DREI BRUDER-MODULEN (AUSGÄNGE)
        -- =============================================================
        -- REPARATUR: Ausgänge auf 8 Bit erweitert zur Vektor-Harmonisierung [14.1]
        aud_period_ch0 : out   std_logic_vector(15 downto 0);
        aud_volume_ch0 : out   std_logic_vector(7 downto 0);
        aud_period_ch1 : out   std_logic_vector(15 downto 0);
        aud_volume_ch1 : out   std_logic_vector(7 downto 0);
        aud_period_ch2 : out   std_logic_vector(15 downto 0);
        aud_volume_ch2 : out   std_logic_vector(7 downto 0);
        aud_period_ch3 : out   std_logic_vector(15 downto 0);
        aud_volume_ch3 : out   std_logic_vector(7 downto 0);
        
        -- Floppy-Parameter an paula_floppy.vhd
        dsk_sync_word : out   std_logic_vector(15 downto 0);
        dsk_dma_en    : out   std_logic;
        dsk_write_mode: out   std_logic;
        
        -- UART-Parameter an paula_uart.vhd
        uart_period   : out   std_logic_vector(14 downto 0);
        uart_data_w   : out   std_logic_vector(8 downto 0);
        uart_tx_start : out   std_logic;
        uart_read_strobe : out std_logic;                    
        
        -- =============================================================
        -- 4. INTERRUPT-ALARMLEITUNGEN VON DEN BRUDER-MODULEN (EINGÄNGE)
        -- =============================================================
        irq_fdd_sync  : in    std_logic; 
        irq_uart_rx   : in    std_logic; 
        irq_uart_tx   : in    std_logic; 
        
        -- Sammel-Interruptleitung direkt zum Alice-Hauptdach
        paula_irq_out : out   std_logic                      
    );
end paula_regs;

architecture Behavioral of paula_regs is

    -- Interne Hardware-Register für die vier PCM-Audiokanäle
    signal reg_aud0per : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_aud1per : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_aud2per : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_aud3per : std_logic_vector(15 downto 0) := (others => '0');

    -- Schattenregister intern ebenfalls auf 8 Bit erweitert
    signal reg_aud0vol : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_aud1vol : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_aud2vol : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_aud3vol : std_logic_vector(7 downto 0) := (others => '0');

    -- Interne Kontrollregister für Diskette und UART
    signal reg_dsksync : std_logic_vector(15 downto 0) := x"4489"; 
    signal reg_dsklen  : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_serper  : std_logic_vector(14 downto 0) := (others => '0');

    -- Das interne Interrupt-Anforderungsregister für Paula-Peripherie
    signal intreq_p    : std_logic_vector(3 downto 0)  := (others => '0');

begin

    -- Permanente Durchschaltung der Registerwerte an die Audio-Kanäle
    aud_period_ch0 <= reg_aud0per; aud_volume_ch0 <= reg_aud0vol;
    aud_period_ch1 <= reg_aud1per; aud_volume_ch1 <= reg_aud1vol;
    aud_period_ch2 <= reg_aud2per; aud_volume_ch2 <= reg_aud2vol;
    aud_period_ch3 <= reg_aud3per; aud_volume_ch3 <= reg_aud3vol;

    -- Permanente Durchschaltung der Disketten-Parameter
    dsk_sync_word  <= reg_dsksync;
    dsk_dma_en     <= reg_dsklen(14); 
    dsk_write_mode <= reg_dsklen(15); 

    -- Permanente Durchschaltung der seriellen Parameter
    uart_period <= reg_serper;

    -- =================================================================
    -- GENERIERUNG DES LESE-STROBES (QUITTUNG)
    -- =================================================================
    process(reg_addr, reg_read_en)
    begin
        if reg_read_en = '1' and reg_addr = x"018" then
            uart_read_strobe <= '1'; 
        else
            uart_read_strobe <= '0';
        end if;
    end process;

    -- =================================================================
    -- 1. PHYSIKALISCHER CPU-REGISTER-SCHREIBPROZESS
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_aud0per   <= (others => '0'); reg_aud0vol   <= (others => '0');
            reg_aud1per   <= (others => '0'); reg_aud1vol   <= (others => '0');
            reg_aud2per   <= (others => '0'); reg_aud2vol   <= (others => '0');
            reg_aud3per   <= (others => '0'); reg_aud3vol   <= (others => '0');
            reg_dsksync   <= x"4489";         reg_dsklen    <= (others => '0');
            reg_serper    <= (others => '0');
            uart_data_w   <= (others => '0'); uart_tx_start <= '0';
            intreq_p      <= (others => '0');
        elsif rising_edge(clk_amiga) then
            uart_tx_start <= '0'; 
            
            -- KORREKTUR FULL-FIX: Initialisiert alle Bits in jedem Takt vorab stabil mit sich selbst!
            intreq_p <= intreq_p;
            -- KORREKTUR ADRESS-LOCH: Bit 3 starr auf Null verriegeln tilgt das Latch restlos!
            intreq_p(3) <= '0'; 

            if reg_write_en = '1' then
                case reg_addr is
                    when x"030" => uart_data_w   <= reg_data_w(8 downto 0);   
                                   uart_tx_start <= '1';                      
                    when x"032" => reg_serper    <= reg_data_w(14 downto 0);  
                    when x"07E" => reg_dsksync   <= reg_data_w(15 downto 0);  
                    when x"024" => reg_dsklen    <= reg_data_w(15 downto 0);  
                    
                    -- Audio-Kanäle Register-Mapping
                    when x"0A4" => reg_aud0per   <= reg_data_w(15 downto 0);  
                    when x"0A6" => reg_aud0vol   <= reg_data_w(7 downto 0);   
                    when x"0B4" => reg_aud1per   <= reg_data_w(15 downto 0);  
                    when x"0B6" => reg_aud1vol   <= reg_data_w(7 downto 0);   
                    when x"0C4" => reg_aud2per   <= reg_data_w(15 downto 0);  
                    when x"0C6" => reg_aud2vol   <= reg_data_w(7 downto 0);   
                    when x"0D4" => reg_aud3per   <= reg_data_w(15 downto 0);  
                    when x"0D6" => reg_aud3vol   <= reg_data_w(7 downto 0);   
                    
                    when others => null;
                end case;
            end if;

            -- HARDWARE-AUTOMATISMUS (Interrupts der Peripherie einfangen)
            if irq_fdd_sync = '1' then
                intreq_p(0) <= '1'; 
            end if;
            if irq_uart_rx = '1' then
                intreq_p(1) <= '1'; 
            end if;
            if irq_uart_tx = '1' then
                intreq_p(2) <= '1'; 
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. HARDWARE-SAMMEL-INTERRUPT (Oder-Verknüpfung)
    -- =================================================================
    paula_irq_out <= '1' when intreq_p /= "0000" else '0';

end Behavioral;

