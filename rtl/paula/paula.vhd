library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity paula is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE (VON DER MASTER-TAKTZENTRALE)
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM EXTERNEN REGISTERPFAD (CPU / COPPER-BUS)
        -- =============================================================
        am_addr       : in    std_logic_vector(11 downto 0); -- Custom-Registeradresse ($DFFXXX)
        am_data_w     : in    std_logic_vector(31 downto 0); -- Schreibdaten vom Bus
        am_reg_write  : in    std_logic;                     -- Schreibimpuls der Systemsteuerung
        am_reg_read   : in    std_logic;                     -- NEU VERDRAHTET: Leseimpuls der Systemsteuerung
        
        -- =============================================================
        -- 3. INTERNE SPEICHER- UND DMA-SCHNITTSTELLEN (ZUR ARBITRIERUNG)
        -- =============================================================
        -- Audio-DMA Kanäle (Zubringer vom RAM)
        aud_dma_data   : in    std_logic_vector(15 downto 0); -- Geladene PCM-Wörter
        aud_dma_load   : in    std_logic_vector(1 downto 0);  -- Kanalauswahl (0-3)
        aud_dma_write  : in    std_logic;                     -- Lade-Impuls
        
        -- Audio-DMA Bedarfsanforderungen an Alice
        aud_dma_req_ch0: out   std_logic;
        aud_dma_req_ch1: out   std_logic;
        aud_dma_req_ch2: out   std_logic;
        aud_dma_req_ch3: out   std_logic;
        
        -- Floppy-DMA Kanäle (Datenaustausch mit dem RAM)
        fdd_dma_data_o : out   std_logic_vector(15 downto 0); -- MFM-Lesedaten ans RAM
        fdd_dma_data_i : in    std_logic_vector(15 downto 0); -- MFM-Schreibdaten aus dem RAM
        fdd_dma_req    : out   std_logic;                     -- DMA-Slot-Anforderung
        fdd_dma_ack    : in    std_logic;                     -- Slot-Quittierung von Alice
        fdd_dma_rw     : out   std_logic;                     -- KORREKTUR: Richtungssignal an Alice ('0'=Schreiben)
        
        -- =============================================================
        -- 4. PHYSISCHE PERIPHERIE-PORTS (EXTERNE GERÄTE)
        -- =============================================================
        floppy_raw_read: in    std_logic;
        floppy_raw_write: out  std_logic;
        rxd           : in    std_logic;
        txd           : out   std_logic;
        
        -- =============================================================
        -- 5. ANALOGE SOUND-STREAMS UND GLOBALER SYSTEM-INTERRUPT
        -- =============================================================
        audio_out_left  : out  std_logic_vector(14 downto 0); -- Linker PCM-Stream
        audio_out_right : out  std_logic_vector(14 downto 0); -- Rechter PCM-Stream
        paula_irq_out   : out  std_logic                      -- Peripherie-Alarm an Alice
    );
end paula;

architecture Behavioral of paula is

    -- -----------------------------------------------------------------
    -- COMPONENTEN-DEKLARATIONEN DER VIER UNTERMODULE
    -- -----------------------------------------------------------------
    component paula_regs is
        Port (
            clk_amiga      : in    std_logic;
            reset          : in    std_logic;
            reg_addr       : in    std_logic_vector(11 downto 0);
            reg_data_w     : in    std_logic_vector(31 downto 0);
            reg_write_en   : in    std_logic;
            reg_read_en    : in    std_logic; -- Erweitert
            aud_period_ch0 : out   std_logic_vector(15 downto 0);
            aud_volume_ch0 : out   std_logic_vector(5 downto 0);
            aud_period_ch1 : out   std_logic_vector(15 downto 0);
            aud_volume_ch1 : out   std_logic_vector(5 downto 0);
            aud_period_ch2 : out   std_logic_vector(15 downto 0);
            aud_volume_ch2 : out   std_logic_vector(5 downto 0);
            aud_period_ch3 : out   std_logic_vector(15 downto 0);
            aud_volume_ch3 : out   std_logic_vector(5 downto 0);
            dsk_sync_word  : out   std_logic_vector(15 downto 0);
            dsk_dma_en     : out   std_logic;
            dsk_write_mode : out   std_logic;
            uart_period    : out   std_logic_vector(14 downto 0);
            uart_data_w    : out   std_logic_vector(8 downto 0);
            uart_tx_start  : out   std_logic;
            uart_read_strobe : out std_logic; -- Erweitert
            irq_fdd_sync   : in    std_logic;
            irq_uart_rx    : in    std_logic;
            irq_uart_tx    : in    std_logic;
            paula_irq_out  : out   std_logic
        );
    end component;

    component paula_audio is
        Port (
            clk_amiga       : in    std_logic;
            reset           : in    std_logic;
            aud_period_ch0  : in    std_logic_vector(15 downto 0);
            aud_volume_ch0  : in    std_logic_vector(5 downto 0);
            aud_period_ch1  : in    std_logic_vector(15 downto 0);
            aud_volume_ch1  : in    std_logic_vector(5 downto 0);
            aud_period_ch2  : in    std_logic_vector(15 downto 0);
            aud_volume_ch2  : in    std_logic_vector(5 downto 0);
            aud_period_ch3  : in    std_logic_vector(15 downto 0);
            aud_volume_ch3  : in    std_logic_vector(5 downto 0);
            aud_dma_data    : in    std_logic_vector(15 downto 0);
            aud_dma_load    : in    std_logic_vector(1 downto 0);
            aud_dma_write   : in    std_logic;
            aud_dma_req_ch0 : out   std_logic;
            aud_dma_req_ch1 : out   std_logic;
            aud_dma_req_ch2 : out   std_logic;
            aud_dma_req_ch3 : out   std_logic;
            audio_out_left  : out   std_logic_vector(14 downto 0);
            audio_out_right : out   std_logic_vector(14 downto 0)
        );
    end component;

    component paula_floppy is
        Port (
            clk_amiga       : in    std_logic;
            reset           : in    std_logic;
            dsk_sync_word   : in    std_logic_vector(15 downto 0);
            dsk_dma_en      : in    std_logic;
            dsk_write_mode  : in    std_logic;
            floppy_raw_read : in    std_logic;
            floppy_raw_write: out   std_logic;
            fdd_dma_data_o  : out   std_logic_vector(15 downto 0);
            fdd_dma_data_i  : in    std_logic_vector(15 downto 0);
            fdd_dma_req     : out   std_logic;
            fdd_dma_ack     : in    std_logic;
            fdd_sync_match  : out   std_logic
        );
    end component;

    component paula_uart is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            uart_period   : in    std_logic_vector(14 downto 0);
            uart_data_w   : in    std_logic_vector(8 downto 0);
            uart_tx_start : in    std_logic;
            uart_read_strobe : in std_logic; -- Erweitert
            uart_data_r   : out   std_logic_vector(15 downto 0);
            rxd           : in    std_logic;
            txd           : out   std_logic;
            uart_rx_irq   : out   std_logic;
            uart_tx_irq   : out   std_logic
        );
    end component;

    -- -----------------------------------------------------------------
    -- CHIPINTERNE BUSBAHNEN UND VERKNÜPFUNGSSIGNALE
    -- -----------------------------------------------------------------
    -- Interne Audio-Kontrollleitungen
    signal int_aud_period_ch0 : std_logic_vector(15 downto 0);
    signal int_aud_volume_ch0 : std_logic_vector(5 downto 0);
    signal int_aud_period_ch1 : std_logic_vector(15 downto 0);
    signal int_aud_volume_ch1 : std_logic_vector(5 downto 0);
    signal int_aud_period_ch2 : std_logic_vector(15 downto 0);
    signal int_aud_volume_ch2 : std_logic_vector(5 downto 0);
    signal int_aud_period_ch3 : std_logic_vector(15 downto 0);
    signal int_aud_volume_ch3 : std_logic_vector(5 downto 0);

    -- Interne Floppy-Kontrollleitungen
    signal int_dsk_sync_word  : std_logic_vector(15 downto 0);
    signal int_dsk_dma_en     : std_logic;
    signal int_dsk_write_mode : std_logic;

    -- Interne UART-Kontrollleitungen
    signal int_uart_period    : std_logic_vector(14 downto 0);
    signal int_uart_data_w    : std_logic_vector(8 downto 0);
    signal int_uart_tx_start  : std_logic;
    
    -- NEU VERKABELT: Die interne Lese-Quittungsader
    signal int_uart_read_strobe : std_logic;

    -- Interne Interrupt-Alarmleitungen
    signal int_irq_fdd_sync   : std_logic;
    signal int_irq_uart_rx    : std_logic;
    signal int_irq_uart_tx    : std_logic;

begin

    -- KORREKTUR: Den Disketten-Schreib/Lese-Status direkt an Alice übergeben!
    -- Wenn dsk_write_mode = '1' ist, schreiben wir ins RAM (Alice liest nicht, sondern schreibt)
    -- Da der dma_rw-Bus an Alice typischerweise '1' für Lesen und '0' für Schreiben erwartet,
    -- passen wir das Signal hier starr an die Busnorm an.
    fdd_dma_rw <= '0' when int_dsk_write_mode = '1' else '1';

    -- =================================================================
    -- CHIP-INTERNE VERDRAHTUNG (PORT MAPS)
    -- =================================================================
    
    -- Block 1: Das zentrale Register- und Interrupt-Schaltwerk
    u_paula_regs : paula_regs
    port map (
        clk_amiga        => clk_amiga,
        reset            => reset,
        reg_addr         => am_addr,
        reg_data_w       => am_data_w,
        reg_write_en     => am_reg_write,
        reg_read_en      => am_reg_read,       -- Neu verdrahtet
        aud_period_ch0   => int_aud_period_ch0,
        aud_volume_ch0   => int_aud_volume_ch0,
        aud_period_ch1   => int_aud_period_ch1,
        aud_volume_ch1   => int_aud_volume_ch1,
        aud_period_ch2   => int_aud_period_ch2,
        aud_volume_ch2   => int_aud_volume_ch2,
        aud_period_ch3   => int_aud_period_ch3,
        aud_volume_ch3   => int_aud_volume_ch3,
        dsk_sync_word    => int_dsk_sync_word,
        dsk_dma_en       => int_dsk_dma_en,
        dsk_write_mode   => int_dsk_write_mode,
        uart_period      => int_uart_period,
        uart_data_w      => int_uart_data_w,
        uart_tx_start    => int_uart_tx_start,
        uart_read_strobe => int_uart_read_strobe, -- Neu verdrahtet
        irq_fdd_sync     => int_irq_fdd_sync,
        irq_uart_rx      => int_irq_uart_rx,
        irq_uart_tx      => int_irq_uart_tx,
        paula_irq_out    => paula_irq_out
    );

    -- Block 2: Das 4-Kanal-PCM Stereo Soundzentrum
    u_paula_audio : paula_audio
    port map (
        clk_amiga       => clk_amiga,
        reset           => reset,
        aud_period_ch0  => int_aud_period_ch0,
        aud_volume_ch0  => int_aud_volume_ch0,
        aud_period_ch1  => int_aud_period_ch1,
        aud_volume_ch1  => int_aud_volume_ch1,
        aud_period_ch2  => int_aud_period_ch2,
        aud_volume_ch2  => int_aud_volume_ch2,
        aud_period_ch3  => int_aud_period_ch3,
        aud_volume_ch3  => int_aud_volume_ch3,
        aud_dma_data    => aud_dma_data,
        aud_dma_load    => aud_dma_load,
        aud_dma_write   => aud_dma_write,
        aud_dma_req_ch0 => aud_dma_req_ch0,
        aud_dma_req_ch1 => aud_dma_req_ch1,
        aud_dma_req_ch2 => aud_dma_req_ch2,
        aud_dma_req_ch3 => aud_dma_req_ch3,
        audio_out_left  => audio_out_left,
        audio_out_right => audio_out_right
    );

    -- Block 3: Der MFM-Disketten-Controller
    u_paula_floppy : paula_floppy
    port map (
        clk_amiga        => clk_amiga,
        reset            => reset,
        dsk_sync_word    => int_dsk_sync_word,
        dsk_dma_en       => int_dsk_dma_en,
        dsk_write_mode   => int_dsk_write_mode,
        floppy_raw_read  => floppy_raw_read,
        floppy_raw_write => floppy_raw_write,
        fdd_dma_data_o   => fdd_dma_data_o,
        fdd_dma_data_i   => fdd_dma_data_i,
        fdd_dma_req      => fdd_dma_req,
        fdd_dma_ack      => fdd_dma_ack,
        fdd_sync_match   => int_irq_fdd_sync
    );

    -- Block 4: Das serielle UART- und MIDI-Kommunikationszentrum
    u_paula_uart : paula_uart
    port map (
        clk_amiga        => clk_amiga,
        reset            => reset,
        uart_period      => int_uart_period,
        uart_data_w      => int_uart_data_w,
        uart_tx_start    => int_uart_tx_start,
        uart_read_strobe => int_uart_read_strobe, -- Neu verdrahtet
        uart_data_r      => open,
        rxd              => rxd,
        txd              => txd,
        uart_rx_irq      => int_irq_uart_rx,
        uart_tx_irq      => int_irq_uart_tx
    );

end Behavioral;
