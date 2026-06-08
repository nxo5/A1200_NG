library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity paula_floppy is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTERWERK (VON PAULA_REGS.VHD)
        -- =============================================================
        dsk_sync_word : in    std_logic_vector(15 downto 0); -- Das Wunsch-Sync-Wort (Standard: x"4489")
        dsk_dma_en    : in    std_logic;                     -- DMA-Freigabe für das Diskettenlaufwerk
        dsk_write_mode: in    std_logic;                     -- '1' = Schreiben, '0' = Lesen
        
        -- =============================================================
        -- 3. PHYSISCHE LAUFWERKS-SCHNITTSTELLE (EINGÄNGE / AUSGÄNGE)
        -- =============================================================
        floppy_raw_read: in   std_logic;                     -- Der rohe Lese-Bitstrom vom Laufwerk
        floppy_raw_write: out std_logic;                     -- Der rohe Schreib-Bitstrom zum Laufwerk
        
        -- =============================================================
        -- 4. INTERNE TRANSFERSCHNITTSTELLE ZUR SPEICHER-ARBITRIERUNG
        -- =============================================================
        fdd_dma_data_o : out   std_logic_vector(15 downto 0); -- MFM-Lesedaten fürs RAM
        fdd_dma_data_i : in    std_logic_vector(15 downto 0); -- Zu schreibendes MFM-Wort aus dem RAM
        fdd_dma_req    : out   std_logic;                     
        fdd_dma_ack    : in    std_logic;                     
        
        -- Statussignal direkt an das Interruptsystem von Paula
        fdd_sync_match : out   std_logic                      
    );
end paula_floppy;

architecture Behavioral of paula_floppy is

    -- Internes 32-Bit-Echtzeit-Schieberegister für den MFM-Bitstrom
    signal shift_reg_in   : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Taktteiler zur Generierung des physikalischen Disketten-Bit-Fensters bei LESEN (~2 µs)
    signal fdd_clk_cnt    : integer range 0 to 27 := 0;
    signal fdd_bit_tick   : std_logic := '0';
    
    -- KORREKTUR: Autarker Modulo-28 Zähler für den Jitter-freien SCHREIBTAKTPFAD
    signal write_clk_cnt  : integer range 0 to 27 := 0;
    signal write_bit_tick : std_logic := '0';
    
    -- Bit- und Wortzähler für die DMA-Paketierung
    signal mfm_bit_cnt    : integer range 0 to 15 := 0;
    signal dma_word_buf   : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Interne Statussignale
    signal sync_found     : std_logic := '0';
    signal int_dma_req    : std_logic := '0';

begin

    fdd_dma_data_o <= dma_word_buf;
    fdd_dma_req    <= int_dma_req;
    fdd_sync_match <= sync_found;

    -- =================================================================
    -- 1. ADAPTER-TAKTTRENNUNG (Der Lese-Separator-Zähler)
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            fdd_clk_cnt  <= 0;
            fdd_bit_tick <= '0';
        elsif rising_edge(clk_amiga) then
            fdd_bit_tick <= '0';
            if fdd_clk_cnt = 27 then 
                fdd_clk_cnt  <= 0;
                fdd_bit_tick <= '1'; 
            else
                fdd_clk_cnt <= fdd_clk_cnt + 1;
            end if;
        end if;
    end process;

    -- =================================================================
    -- KORREKTUR: AUTARKER SCHREIBAUSGANGS-TAKTEILER (Modulo-28)
    -- =================================================================
    -- Läuft völlig unabhängig von der Lese-Abtastung starr im Hintergrund,
    -- um beim Schreiben jeglichen Phasen-Jitter auf der Datenleitung auszuschließen.
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            write_clk_cnt  <= 0;
            write_bit_tick <= '0';
        elsif rising_edge(clk_amiga) then
            write_bit_tick <= '0';
            if dsk_dma_en = '1' and dsk_write_mode = '1' then
                if write_clk_cnt = 27 then
                    write_clk_cnt  <= 0;
                    write_bit_tick <= '1'; -- Zünde den harten MFM-Schreibimpuls!
                else
                    write_clk_cnt <= write_clk_cnt + 1;
                end if;
            else
                write_clk_cnt <= 0;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. OPERATIVER MFM-LESE- UND SYNC-EINRASTPROZESS
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            shift_reg_in <= (others => '0');
            dma_word_buf <= (others => '0');
            mfm_bit_cnt  <= 0;
            sync_found   <= '0';
            int_dma_req  <= '0';
        elsif rising_edge(clk_amiga) then
            
            if fdd_dma_ack = '1' then
                int_dma_req <= '0';
            end if;

            if fdd_bit_tick = '1' and dsk_dma_en = '1' and dsk_write_mode = '0' then
                shift_reg_in <= shift_reg_in(30 downto 0) & floppy_raw_read;
                
                if shift_reg_in(15 downto 0) = dsk_sync_word then
                    sync_found  <= '1'; 
                    mfm_bit_cnt <= 0;   
                else
                    sync_found <= '0';
                    
                    if mfm_bit_cnt = 15 then
                        mfm_bit_cnt  <= 0;
                        dma_word_buf <= shift_reg_in(15 downto 0); 
                        int_dma_req  <= '1';                       
                    else
                        mfm_bit_cnt <= mfm_bit_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 3. KORRIGIERT: INTERNER MFM-SCHREIBPFAD (Über den starren Schreibzähler)
    -- =================================================================
    process(clk_amiga, reset)
        variable shift_out_reg : std_logic_vector(15 downto 0) := (others => '0');
        variable write_bit_cnt : integer range 0 to 15 := 0;
    begin
        if reset = '1' then
            floppy_raw_write <= '1';
            shift_out_reg    := (others => '0');
            write_bit_cnt    := 0;
        elsif rising_edge(clk_amiga) then
            -- Reagiert nun unerbittlich exakt auf das autarke write_bit_tick Signal!
            if write_bit_tick = '1' then
                if write_bit_cnt = 0 then
                    shift_out_reg := fdd_dma_data_i;
                    write_bit_cnt := 15;
                else
                    write_bit_cnt := write_bit_cnt - 1;
                end if;
                
                floppy_raw_write <= shift_out_reg(15);
                shift_out_reg    := shift_out_reg(14 downto 0) & '1';
            end if;
        end if;
    end process;

end Behavioral;
