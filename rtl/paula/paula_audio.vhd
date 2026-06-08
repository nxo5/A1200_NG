library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity paula_audio is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTERWERK (VON PAULA_REGS.VHD)
        -- =============================================================
        -- KORREKTUR: Erweiterung auf 8 Bits (7 downto 0), um den originalen
        -- Amiga-Lautstärkebereich von 0 bis 64 (Protracker-Norm) fehlerfrei abzufangen!
        aud_period_ch0 : in    std_logic_vector(15 downto 0); -- AUD0PER
        aud_volume_ch0 : in    std_logic_vector(7 downto 0);  -- AUD0VOL (Bits 7-0)
        aud_period_ch1 : in    std_logic_vector(15 downto 0); -- AUD1PER
        aud_volume_ch1 : in    std_logic_vector(7 downto 0);  -- AUD1VOL
        aud_period_ch2 : in    std_logic_vector(15 downto 0); -- AUD2PER
        aud_volume_ch2 : in    std_logic_vector(7 downto 0);  -- AUD2VOL
        aud_period_ch3 : in    std_logic_vector(15 downto 0); -- AUD3PER
        aud_volume_ch3 : in    std_logic_vector(7 downto 0);  -- AUD3VOL
        
        -- =============================================================
        -- 3. GRAPHIK- UND DMA-SCHNITTSTELLEN (VON/ZU PAULA.VHD)
        -- =============================================================
        aud_dma_data   : in    std_logic_vector(15 downto 0); 
        aud_dma_load   : in    std_logic_vector(1 downto 0);  
        aud_dma_write  : in    std_logic;                     
        
        -- Autonome DMA-Bedarfsanforderungen an die Master-Zentrale
        aud_dma_req_ch0: out   std_logic;                     
        aud_dma_req_ch1: out   std_logic;                     
        aud_dma_req_ch2: out   std_logic;                     
        aud_dma_req_ch3: out   std_logic;                     
        
        -- =============================================================
        -- 4. INTERNE AUSGÄNGE DIREKT ZUR PAULA-HAUPTDATEI (PAULA.VHD)
        -- =============================================================
        audio_out_left  : out  std_logic_vector(14 downto 0); -- Kombinierter linker Kanal (CH0 + CH3)
        audio_out_right : out  std_logic_vector(14 downto 0)  -- Kombinierter rechter Kanal (CH1 + CH2)
    );
end paula_audio;

architecture Behavioral of paula_audio is

    -- Strukturierte Definition eines originalen Amiga-Audiokanals
    type audio_channel_t is record
        period_cnt   : unsigned(15 downto 0); 
        sample_buffer: std_logic_vector(7 downto 0);  
        sample_shadow: std_logic_vector(7 downto 0);  
        shadow_empty : std_logic;                     
        current_sample: signed(7 downto 0);           
        mixed_val    : signed(14 downto 0);           -- Erweitert auf 15 Bit (Sample * Vol_clamped)
    end record;

    type audio_array_t is array (0 to 3) of audio_channel_t;
    signal ch : audio_array_t;

begin

    -- =================================================================
    -- 1. OPERATIVER LADE- UND DEKREMENTIERUNGSPROZESS WITH CLAMPING
    -- =================================================================
    process(clk_amiga, reset)
        variable c_idx : integer range 0 to 3;
        -- Lokale Hilfsvariablen für die gattergetreue 64er-Lautstärken-Sperre
        variable vol_ch0_v : unsigned(7 downto 0);
        variable vol_ch1_v : unsigned(7 downto 0);
        variable vol_ch2_v : unsigned(7 downto 0);
        variable vol_ch3_v : unsigned(7 downto 0);
    begin
        if reset = '1' then
            for i in 0 to 3 loop
                ch(i).period_cnt     <= (others => '0');
                ch(i).sample_buffer  <= (others => '0');
                ch(i).sample_shadow  <= (others => '0');
                ch(i).shadow_empty   <= '1';
                ch(i).current_sample <= (others => '0');
                ch(i).mixed_val      <= (others => '0');
            end loop;
            aud_dma_req_ch0 <= '0'; aud_dma_req_ch1 <= '0';
            aud_dma_req_ch2 <= '0'; aud_dma_req_ch3 <= '0';
        elsif rising_edge(clk_amiga) then
            
            -- PFAD A: DMA-BUFFER-SPEISUNG
            if aud_dma_write = '1' then
                c_idx := to_integer(unsigned(aud_dma_load));
                ch(c_idx).sample_buffer <= aud_dma_data(15 downto 8); 
                ch(c_idx).sample_shadow <= aud_dma_data(7 downto 0);   
                ch(c_idx).shadow_empty  <= '0';                        
            end if;

            -- PFAD B: GETAKTETES DEKREMENTIEREN DER VIER OPERATIVEN ABTASTRATEN
            -- Kanal 0
            if ch(0).period_cnt = x"0000" then
                ch(0).period_cnt <= unsigned(aud_period_ch0);
                if ch(0).shadow_empty = '0' then
                    ch(0).current_sample <= signed(ch(0).sample_shadow);
                    ch(0).shadow_empty   <= '1'; 
                end if;
            else
                ch(0).period_cnt <= ch(0).period_cnt - 1;
            end if;

            -- Kanal 1
            if ch(1).period_cnt = x"0000" then
                ch(1).period_cnt <= unsigned(aud_period_ch1);
                if ch(1).shadow_empty = '0' then
                    ch(1).current_sample <= signed(ch(1).sample_shadow);
                    ch(1).shadow_empty   <= '1';
                end if;
            else
                ch(1).period_cnt <= ch(1).period_cnt - 1;
            end if;

            -- Kanal 2
            if ch(2).period_cnt = x"0000" then
                ch(2).period_cnt <= unsigned(aud_period_ch2);
                if ch(2).shadow_empty = '0' then
                    ch(2).current_sample <= signed(ch(2).sample_shadow);
                    ch(2).shadow_empty   <= '1';
                end if;
            else
                ch(2).period_cnt <= ch(2).period_cnt - 1;
            end if;

            -- Kanal 3
            if ch(3).period_cnt = x"0000" then
                ch(3).period_cnt <= unsigned(aud_period_ch3);
                if ch(3).shadow_empty = '0' then
                    ch(3).current_sample <= signed(ch(3).sample_shadow);
                    ch(3).shadow_empty   <= '1';
                end if;
            else
                ch(3).period_cnt <= ch(3).period_cnt - 1;
            end if;

            -- KORREKTUR: Die gattergetreue 64er Lautstärken-Sperre (No-Overrun-Gatter)
            -- Wenn das Register 64 oder mehr anfordert, wird der Vektor starr gekappt.
            if unsigned(aud_volume_ch0) >= 64 then vol_ch0_v := to_unsigned(64, 8); else vol_ch0_v := unsigned(aud_volume_ch0); end if;
            if unsigned(aud_volume_ch1) >= 64 then vol_ch1_v := to_unsigned(64, 8); else vol_ch1_v := unsigned(aud_volume_ch1); end if;
            if unsigned(aud_volume_ch2) >= 64 then vol_ch2_v := to_unsigned(64, 8); else vol_ch2_v := unsigned(aud_volume_ch2); end if;
            if unsigned(aud_volume_ch3) >= 64 then vol_ch3_v := to_unsigned(64, 8); else vol_ch3_v := unsigned(aud_volume_ch3); end if;

            -- MATHEMATISCHE LAUTSTÄRKEN-MATRIZIERUNG (Jetzt absolut überlaufsicher!)
            ch(0).mixed_val <= ch(0).current_sample * signed("0" & std_logic_vector(vol_ch0_v));
            ch(1).mixed_val <= ch(1).current_sample * signed("0" & std_logic_vector(vol_ch1_v));
            ch(2).mixed_val <= ch(2).current_sample * signed("0" & std_logic_vector(vol_ch2_v));
            ch(3).mixed_val <= ch(3).current_sample * signed("0" & std_logic_vector(vol_ch3_v));

            -- Autonome Bedarfs-Signale weiterreichen
            aud_dma_req_ch0 <= ch(0).shadow_empty;
            aud_dma_req_ch1 <= ch(1).shadow_empty;
            aud_dma_req_ch2 <= ch(2).shadow_empty;
            aud_dma_req_ch3 <= ch(3).shadow_empty;
        end if;
    end process;

    -- =================================================================
    -- 2. STEREO-ADDITIONS-STUFE (Linearmischung)
    -- =================================================================
    process(ch)
    begin
        audio_out_left  <= std_logic_vector(resize(ch(0).mixed_val, 15) + resize(ch(3).mixed_val, 15));
        audio_out_right <= std_logic_vector(resize(ch(1).mixed_val, 15) + resize(ch(2).mixed_val, 15));
    end process;

end Behavioral;
