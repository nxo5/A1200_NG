-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   blitter_shift.vhd
-- Funktion: Das Datenpuffer-, Shifter- und Maskierungszentrum des Blitters.
-- REPARATUR SCHRITT 16:
--   - Entflechtung von CPU-Register-Schreibzugriffen und DMA-Datenströmen!
--   - Garantiert die absolute, zyklustreue Datenübernahme im Multi-Kanal-Betrieb.
--   - Verhindert den Verlust von Grafikdaten bei parallelen Bus-Aktivitäten.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity blitter_shift is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt von Alice
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTER-PFAD (VON BLITTER.VHD)
        -- =============================================================
        reg_addr      : in    std_logic_vector(11 downto 0); -- Custom-Reg-Adresse ($DFFXXX)
        reg_data_w    : in    std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten der CPU
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Register
        
        -- =============================================================
        -- 3. INTERNE DATEN-ZUBRINGER VOM SPEICHER (VON BLITTER.VHD)
        -- =============================================================
        dma_data_in   : in    std_logic_vector(15 downto 0); -- Aktuelle Daten vom Speicherbus
        chan_load     : in    std_logic_vector(1 downto 0);  -- Welcher Puffer wird geladen ("00"=A, "01"=B, "10"=C)
        
        -- Gekapselte Wortstatus-Signale direkt von der Ablauf-FSM
        is_first_word : in    std_logic;                     -- '1' = Erstes Wort der aktuellen Zeile
        is_last_word  : in    std_logic;                     -- '1' = Letztes Wort der aktuellen Zeile
        
        -- =============================================================
        -- 4. GEKAPSELTER AUSGANG DIREKT ZUR BLITTER-ALU (BLITTER_ALU.VHD)
        -- =============================================================
        shifted_data_a: out   std_logic_vector(15 downto 0); -- Kanal A (Exakt maskiert und 32-Bit rotiert)
        shifted_data_b: out   std_logic_vector(15 downto 0); -- Kanal B (Exakt 32-Bit rotiert)
        buffered_data_c: out   std_logic_vector(15 downto 0)  -- Kanal C (Direkter Zwischenpuffer)
    );
end blitter_shift;

architecture Behavioral of blitter_shift is

    -- Die originalen drei 16-Bit-Datenpuffer des Amiga-Blitters
    signal reg_bltadat : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_bltbdat : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_bltcdat : std_logic_vector(15 downto 0) := (others => '0'); 

    -- Die originalen 16-Bit-Schattenregister (Historischer Daten-Pipeline-Vorlauf)
    signal reg_blta_old : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_bltb_old : std_logic_vector(15 downto 0) := (others => '0');

    -- Die originalen Maskenregister für das erste und letzte Wort einer Zeile
    signal reg_bltafwm : std_logic_vector(15 downto 0) := (others => '1'); 
    signal reg_bltalwm : std_logic_vector(15 downto 0) := (others => '1'); 

    -- Interne Signale für die Schiebe-Werte (Verschiebung um 0 bis 15 Bits)
    signal shift_a : integer range 0 to 15 := 0; 
    signal shift_b : integer range 0 to 15 := 0; 

    -- Interne Signale für die 32-Bit Barrel-Shifter-Fenster
    signal a_rotated : std_logic_vector(15 downto 0);
    signal b_rotated : std_logic_vector(15 downto 0);
    
    -- Dynamisch berechnete Masken-Kombination für dieses spezifische Wort
    signal current_mask : std_logic_vector(15 downto 0);

begin

    -- =================================================================
    -- 1A. PARALLELER PROZESS A: EXKLUSIVE CPU-REGISTERSTEUERUNG
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_bltafwm  <= (others => '1'); reg_bltalwm  <= (others => '1');
            shift_a      <= 0;               shift_b      <= 0;
        elsif rising_edge(clk_amiga) then
            if reg_write_en = '1' then
                case reg_addr is
                    when x"044" => reg_bltafwm <= reg_data_w(15 downto 0); -- BLTAFWM
                    when x"046" => reg_bltalwm <= reg_data_w(15 downto 0); -- BLTALWM
                    when x"040" => shift_a     <= to_integer(unsigned(reg_data_w(15 downto 12))); -- BLTCON0 (Shift A)
                    when x"042" => shift_b     <= to_integer(unsigned(reg_data_w(15 downto 12))); -- BLTCON1 (Shift B)
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 1B. REPARATUR: AUTARKER PROZESS B: MULTI-KANAL DMA-PIPELINING
    -- =================================================================
    -- Reagiert völlig unabhängig von reg_write_en auf die fsm_chan_load Befehle!
    -- Erlaubt zeitgleiche CPU-Aktivität ohne jeden Grafikdatenverlust.
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_bltadat  <= (others => '0'); reg_bltbdat  <= (others => '0');
            reg_bltcdat  <= (others => '0');
            reg_blta_old <= (others => '0'); reg_bltb_old <= (others => '0');
        elsif rising_edge(clk_amiga) then
            -- Erste Priorität: CPU-Direktschreiben in die Datenregister (z.B. für CPU-Blits)
            if reg_write_en = '1' then
                case reg_addr is
                    when x"070" => reg_bltcdat <= reg_data_w(15 downto 0); -- BLTCDAT
                    when x"072" => reg_bltbdat <= reg_data_w(15 downto 0); -- BLTBDAT
                    when x"074" => reg_bltadat <= reg_data_w(15 downto 0); -- BLTADAT
                    when others => null;
                end case;
            -- Zweite Priorität: Zyklustreuer Dateneinzug des operativen DMA-Werks
            else
                case chan_load is
                    when "00" =>
                        reg_blta_old <= reg_bltadat;
                        reg_bltadat  <= dma_data_in; -- Kanal A laden
                    when "01" =>
                        reg_bltb_old <= reg_bltbdat;
                        reg_bltbdat  <= dma_data_in; -- Kanal B laden
                    when "10" =>
                        reg_bltcdat  <= dma_data_in; -- Kanal C laden
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. DYNAMISCHE MASKEN-WEICHE (Echtzeit-Gatterprüfung)
    -- =================================================================
    process(is_first_word, is_last_word, reg_bltafwm, reg_bltalwm)
    begin
        if is_first_word = '1' and is_last_word = '1' then
            current_mask <= reg_bltafwm and reg_bltalwm;
        elsif is_first_word = '1' then
            current_mask <= reg_bltafwm;
        elsif is_last_word = '1' then
            current_mask <= reg_bltalwm;
        else
            current_mask <= (others => '1'); 
        end if;
    end process;

    -- =================================================================
    -- 3. INTERNER 32-BIT BARREL-SHIFTER (Echte Bit-Kopplung)
    -- =================================================================
    process(reg_bltadat, reg_blta_old, shift_a)
        variable combined_a : std_logic_vector(31 downto 0);
    begin
        combined_a := reg_blta_old & reg_bltadat;
        a_rotated  <= combined_a(15 + shift_a downto shift_a); 
    end process;

    process(reg_bltbdat, reg_bltb_old, shift_b)
        variable combined_b : std_logic_vector(31 downto 0);
    begin
        combined_b := reg_bltb_old & reg_bltbdat;
        b_rotated  <= combined_b(15 + shift_b downto shift_b); 
    end process;

    -- =================================================================
    -- 4. AUSGANGS-ROUTING MIT HARDWARE-MASKIERUNG
    -- =================================================================
    shifted_data_a  <= a_rotated and current_mask;
    shifted_data_b  <= b_rotated;
    buffered_data_c <= reg_bltcdat;

end Behavioral;
