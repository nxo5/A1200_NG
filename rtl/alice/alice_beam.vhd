library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice_beam is
    Port (
        -- =============================================================
        -- 1. CLOCK-, RESET- UND TIMING-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        cck_tick      : in    std_logic; -- Color Clock Puls vom Takt-Schaltwerk
        pal_mode      : in    std_logic; -- '1' = PAL, '0' = NTSC
        
        -- =============================================================
        -- 2. AUSGÄNGE ZUM VIDEOSYSTEM (PHYSISCHE BLANK- UND SYNC-PINS)
        -- =============================================================
        hblank        : out   std_logic; 
        hsync         : out   std_logic; 
        vblank        : out   std_logic; 
        vsync         : out   std_logic; 
        
        -- =============================================================
        -- 3. INTERNE CHIP-SCHNITTSTELLEN (AUSGÄNGE FÜR REG- UND DMA-MODUL)
        -- =============================================================
        h_pos         : out   unsigned(8 downto 0); -- Horizontale Position (0 bis 226 CCKs)
        v_pos         : out   unsigned(8 downto 0)  -- Vertikale Zeile (0 bis 311/312 bzw. 261)
    );
end alice_beam;

architecture Behavioral of alice_beam is

    -- Interne Register für die Strahl-Koordinaten
    signal h_cnt : unsigned(8 downto 0) := (others => '0');
    signal v_cnt : unsigned(8 downto 0) := (others => '0');

    -- NEU: Das 1-Bit Interlace-Umschaltregister für den Halbbild-Wechsel (Even/Odd Frame)
    signal toggle_frame : std_logic := '0';

    -- Dynamische Grenzwerte für das vertikale Zeilenende
    signal max_v_lines : unsigned(8 downto 0);

begin

    -- =================================================================
    -- 1. KORRIGIERT: INTERLACE-NORM-AUSWAHL (Halbbild-Grenzensteuerung)
    -- =================================================================
    process(pal_mode, toggle_frame)
    begin
        if pal_mode = '1' then
            if toggle_frame = '0' then
                max_v_lines <= to_unsigned(311, 9); -- Kurzes Halbbild (0 bis 311 = 312 Zeilen)
            else
                max_v_lines <= to_unsigned(312, 9); -- Langes Halbbild (0 bis 312 = 313 Zeilen)
            end if;
        else
            max_v_lines <= to_unsigned(261, 9);    -- Standard-NTSC (0 bis 261 = 262 Zeilen)
        end if;
    end process;

    -- =================================================================
    -- 2. OPERATIVER STRAHLZÄHLER-PROZESS WITH INTERLACE-TOGGLE
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            h_cnt        <= (others => '0');
            v_cnt        <= (others => '0');
            toggle_frame <= '0';
        elsif rising_edge(clk_amiga) then
            if cck_tick = '1' then
                -- Horizontale Zählung (0 bis 226 Color Clocks)
                if h_cnt = 226 then
                    h_cnt <= (others => '0');
                    
                    -- Vertikale Zeilen-Zählung am Zeilenende weiterschalten
                    if v_cnt = max_v_lines then
                        v_cnt <= (others => '0');
                        -- NEU: Am Ende des gesamten Bildes das Halbbild-Bit zyklustreu invertieren!
                        toggle_frame <= not toggle_frame;
                    else
                        v_cnt <= v_cnt + 1;
                    end if;
                else
                    h_cnt <= h_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- Live-Koordinaten starr an die internen Busleitungen ausgeben
    h_pos <= h_cnt;
    v_pos <= v_cnt;

    -- =================================================================
    -- 3. KOMBINATORISCHE VIDEO-GATTER-LOGIK (Echtzeit-Austastung)
    -- =================================================================
    hsync  <= '0' when (h_cnt >= 200 and h_cnt < 220) else '1';
    hblank <= '1' when (h_cnt >= 180) else '0';

    vsync  <= '0' when (v_cnt >= 0 and v_cnt < 4) else '1';
    vblank <= '1' when (v_cnt >= 300 or v_cnt < 10) else '0';

end Behavioral;
