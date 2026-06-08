library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity blitter_fsm is
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
        reg_write_en  : in    std_logic;                     -- CPU startet oder konfiguriert
        blitter_done  : out   std_logic;                     -- '1' wenn fertig (BLTDONE-Flag)
        
        -- =============================================================
        -- 3. KONTROLLLINIEN ZU DEN REINEN BRUDER-UNTERMODULEN (AUSGÄNGE)
        -- =============================================================
        fsm_chan_sel  : out   std_logic_vector(1 downto 0);  -- Kanalauswahl ("00"=A, "01"=B, "10"=C, "11"=D)
        fsm_ptr_inc   : out   std_logic;                     -- Pointer um 2 Byte erhöhen/verringern
        fsm_mod_add   : out   std_logic;                     -- Zeilen-Modulo aufaddieren
        fsm_chan_load : out   std_logic_vector(1 downto 0);  -- Ladebefehl für Grafikdaten-Puffer
        fsm_line_mode : out   std_logic;                     -- Aktiviert den Hardware-Linienzeichner
        fsm_calc_tick : out   std_logic;                     -- Aktiviert die Minterm-Berechnung
        
        -- NEU: Gekapselte Wortstatus-Signale direkt für blitter_shift.vhd
        fsm_first_word: out   std_logic;                     -- Zeigt an, dass das erste Wort läuft
        fsm_last_word : out   std_logic;                     -- Zeigt an, dass das letzte Wort läuft
        
        -- =============================================================
        -- 4. SPEICHER-ANFORDERUNGEN ZUR ÜBERGEORDNETEN CHIP-ZENTRALE
        -- =============================================================
        fsm_dma_req   : out   std_logic;                     -- Blitter fordert eine DMA-Zeitscheibe an
        fsm_dma_rw    : out   std_logic;                     -- '1' = DMA-Lesen, '0' = DMA-Schreiben
        dma_granted   : in    std_logic                      -- Alice-Zentrale meldet: "Slot aktiv!"
    );
end blitter_fsm;

architecture Behavioral of blitter_fsm is

    type blt_state_t is (
        ST_IDLE,          -- Bereit und wartet auf Start über BLTSIZE
        ST_DECIDE_NEXT,   -- Prüft, welcher der aktiven Kanäle an der Reihe ist
        ST_FETCH_A,       -- Holt Daten für Kanal A aus dem RAM
        ST_FETCH_B,       -- Holt Daten für Kanal B aus dem RAM
        ST_FETCH_C,       -- Holt Daten für Kanal C aus dem RAM
        ST_WRITE_D,       -- Schreibt berechnetes Ergebnis in Kanal D
        ST_LINE_STEP,     -- Spezifischer Ablaufschritt für den Linienmodus
        ST_NEXT_WORD,     -- Schaltet die Adress-Pointer für das nächste Wort weiter
        ST_NEXT_LINE      -- Zeilenende erreicht: Berechnet die Modulo-Sprünge
    );
    signal current_state : blt_state_t := ST_IDLE;

    signal words_per_line : unsigned(5 downto 0) := (others => '0');  
    signal line_count     : unsigned(9 downto 0) := (others => '0');  
    
    signal cnt_word       : unsigned(5 downto 0) := (others => '0');
    signal cnt_line       : unsigned(9 downto 0) := (others => '0');

    signal use_chan_a     : std_logic := '0'; 
    signal use_chan_b     : std_logic := '0'; 
    signal use_chan_c     : std_logic := '0'; 
    signal use_chan_d     : std_logic := '0'; 
    signal line_mode_en   : std_logic := '0'; 

begin

    fsm_line_mode <= line_mode_en;

    -- NEU: Kombinatorische Echtzeit-Berechnung des Wort-Status für die Masken-Weiche
    fsm_first_word <= '1' when (cnt_word = words_per_line and current_state /= ST_IDLE) else '0';
    fsm_last_word  <= '1' when (cnt_word = 1 and current_state /= ST_IDLE) else '0';

    -- =================================================================
    -- OPERATIVE ZUSTANDSMASCHINE UND ABLAUFSTEUERUNG
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            current_state  <= ST_IDLE;
            words_per_line <= (others => '0');
            line_count     <= (others => '0');
            cnt_word       <= (others => '0');
            cnt_line       <= (others => '0');
            use_chan_a     <= '0'; use_chan_b <= '0'; use_chan_c <= '0'; use_chan_d <= '0';
            line_mode_en   <= '0';
            blitter_done   <= '1';
            fsm_dma_req    <= '0'; fsm_dma_rw <= '1'; fsm_calc_tick <= '0';
            fsm_ptr_inc    <= '0'; fsm_mod_add <= '0';
            fsm_chan_sel   <= "00"; fsm_chan_load <= "00";
        elsif rising_edge(clk_amiga) then
            -- Standard-Impulse bei jedem Takt zurücksetzen
            fsm_ptr_inc   <= '0';
            fsm_mod_add   <= '0';
            fsm_calc_tick <= '0';
            fsm_dma_req   <= '0';

            case current_state is
                -- Warten auf CPU-Startbefehl über BLTSIZE ($DFF058)
                when ST_IDLE =>
                    blitter_done <= '1';
                    if reg_write_en = '1' then
                        if reg_addr = x"040" then
                            use_chan_a <= reg_data_w(11);
                            use_chan_b <= reg_data_w(10);
                            use_chan_c <= reg_data_w(9);
                            use_chan_d <= reg_data_w(8);
                        elsif reg_addr = x"042" then
                            line_mode_en <= reg_data_w(0);
                        elsif reg_addr = x"058" then
                            words_per_line <= unsigned(reg_data_w(5 downto 0));
                            line_count     <= unsigned(reg_data_w(15 downto 6));
                            cnt_word       <= unsigned(reg_data_w(5 downto 0));
                            cnt_line       <= unsigned(reg_data_w(15 downto 6));
                            blitter_done   <= '0';
                            current_state  <= ST_DECIDE_NEXT;
                        end if;
                    end if;

                -- Prüft, welcher Kanal als Nächstes dran ist
                when ST_DECIDE_NEXT =>
                    if line_mode_en = '1' then
                        current_state <= ST_LINE_STEP;
                    elsif use_chan_a = '1' and cnt_word = words_per_line then
                        current_state <= ST_FETCH_A;
                    elsif use_chan_b = '1' and cnt_word = words_per_line then
                        current_state <= ST_FETCH_B;
                    elsif use_chan_c = '1' then
                        current_state <= ST_FETCH_C;
                    else
                        current_state <= ST_WRITE_D;
                    end if;

                -- Speicher-Slots über DMA abrufen
                when ST_FETCH_A =>
                    fsm_dma_req  <= '1'; fsm_dma_rw  <= '1'; fsm_chan_sel <= "00";
                    if dma_granted = '1' then
                        fsm_chan_load <= "00"; fsm_ptr_inc <= '1';
                        if use_chan_b = '1' then current_state <= ST_FETCH_B;
                        elsif use_chan_c = '1' then current_state <= ST_FETCH_C;
                        else current_state <= ST_WRITE_D; end if;
                    end if;

                when ST_FETCH_B =>
                    fsm_dma_req  <= '1'; fsm_dma_rw  <= '1'; fsm_chan_sel <= "01";
                    if dma_granted = '1' then
                        fsm_chan_load <= "01"; fsm_ptr_inc <= '1';
                        if use_chan_c = '1' then current_state <= ST_FETCH_C;
                        else current_state <= ST_WRITE_D; end if;
                    end if;

                when ST_FETCH_C =>
                    fsm_dma_req  <= '1'; fsm_dma_rw  <= '1'; fsm_chan_sel <= "10";
                    if dma_granted = '1' then
                        fsm_chan_load <= "10"; fsm_ptr_inc <= '1';
                        current_state <= ST_WRITE_D;
                    end if;

                when ST_WRITE_D =>
                    if use_chan_d = '1' then
                        fsm_dma_req   <= '1'; fsm_dma_rw   <= '0'; fsm_chan_sel  <= "11";
                        fsm_calc_tick <= '1';
                        if dma_granted = '1' then
                            fsm_ptr_inc   <= '1'; current_state <= ST_NEXT_WORD;
                        end if;
                    else
                        fsm_calc_tick <= '1'; current_state <= ST_NEXT_WORD;
                    end if;

                -- Spezialtakt für Bresenham-Linienzeichnung
                when ST_LINE_STEP =>
                    fsm_calc_tick <= '1';
                    if cnt_line > 0 then
                        cnt_line      <= cnt_line - 1;
                        current_state <= ST_DECIDE_NEXT;
                    else
                        current_state <= ST_IDLE;
                    end if;

                -- Zähler dekrementieren und Wort weiterreichen
                when ST_NEXT_WORD =>
                    if cnt_word > 1 then
                        cnt_word      <= cnt_word - 1;
                        current_state <= ST_DECIDE_NEXT;
                    else
                        current_state <= ST_NEXT_LINE;
                    end if;

                -- Zeilenende erreicht: Modulo-Sprünge berechnen
                when ST_NEXT_LINE =>
                    if cnt_line > 1 then
                        cnt_line      <= cnt_line - 1;
                        cnt_word      <= words_per_line;
                        fsm_mod_add   <= '1';
                        current_state <= ST_DECIDE_NEXT;
                    else
                        current_state <= ST_IDLE;
                    end if;

                when others =>
                    current_state <= ST_IDLE;
            end case;
        end if;
    end process;

end Behavioral;

