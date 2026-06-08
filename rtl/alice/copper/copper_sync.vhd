library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity copper_sync is
    Port (
        -- =============================================================
        -- 1. SCHNITTSTELLE ZUM VIDEO-STRAHLZÄHLER (VON ALICE_BEAM.VHD)
        -- =============================================================
        beam_h_pos    : in    unsigned(8 downto 0);          -- Aktueller horizontaler Strahl (0-226)
        beam_v_pos    : in    unsigned(8 downto 0);          -- Aktuelle vertikale Videozeile (0-311)
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM BEFEHLS-DECODER (VON COPPER_DEC.VHD)
        -- =============================================================
        target_h_pos  : in    unsigned(8 downto 0);
        target_v_pos  : in    unsigned(8 downto 0);
        target_mask_h : in    std_logic_vector(8 downto 0);
        target_mask_v : in    std_logic_vector(8 downto 0);
        
        -- Statussignal vom Blitter für WAIT-Befehle auf Blitter-Ende
        blitter_done  : in    std_logic;                     
        
        -- NEU: Takt für den synchronen Latenz-Prozess
        clk_amiga     : in    std_logic;                     -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic;                     -- Globaler System-Reset
        
        -- =============================================================
        -- 3. INTERNER GEKAPSELTER FREIGABE-AUSGANG ZUR FSM (COPPER_FSM.VHD)
        -- =============================================================
        position_match: out   std_logic                      -- '1' = Video-Bedingung erfüllt / überschritten
    );
end copper_sync;

architecture Behavioral of copper_sync is

    -- Lokale Signale für die maskierten Echtzeit-Vergleiche
    signal masked_beam_v : unsigned(8 downto 0);
    signal masked_target_v: unsigned(8 downto 0);
    signal masked_beam_h : unsigned(8 downto 0);
    signal masked_target_h: unsigned(8 downto 0);
    
    signal v_equal       : std_logic;
    signal v_greater     : std_logic;
    signal h_equal_greater: std_logic;
    
    -- NEU: Das Pipeline-Register zur Erzeugung der historischen 1-Takt-Latenz
    signal blitter_done_delayed : std_logic := '1';
    signal blitter_wait_satisfied : std_logic;

begin

    -- =================================================================
    -- 1. NEU: SYNCHRONER LATENZ-PROZESS (Pipeline-Verzögerung)
    -- =================================================================
    -- Verzögert das Blitter-Done-Signal um exakt 1 Color Clock, damit der
    -- Copper nach dem Aufwachen nicht unberechtigt in den Bus grätscht.
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            blitter_done_delayed <= '1';
        elsif rising_edge(clk_amiga) then
            blitter_done_delayed <= blitter_done;
        end if;
    end process;

    -- =================================================================
    -- 2. BIT-MASKIERUNG DER KOORDINATEN (Gattergetreuer Filter)
    -- =================================================================
    masked_beam_v   <= beam_v_pos and unsigned(target_mask_v);
    masked_target_v <= target_v_pos and unsigned(target_mask_v);
    
    masked_beam_h   <= beam_h_pos and unsigned(target_mask_h);
    masked_target_h <= target_h_pos and unsigned(target_mask_h);

    -- =================================================================
    -- 3. HISTORISCHE GRÖSSER-GLEICH-AUSWERTUNG (>= Raster des Amigas)
    -- =================================================================
    v_equal   <= '1' when masked_beam_v = masked_target_v else '0';
    v_greater <= '1' when masked_beam_v > masked_target_v else '0';
    
    h_equal_greater <= '1' when masked_beam_h >= masked_target_h else '0';

    -- =================================================================
    -- 4. SONDERLOGIK: WARTEN AUF HARDWARE-BLITTER (KORRIGIERT)
    -- =================================================================
    -- Greift nun auf das um 1 Takt verzögerte Pipeline-Signal zurück!
    blitter_wait_satisfied <= '1' when (target_mask_v(8) = '1' or blitter_done_delayed = '1') else '0';

    -- =================================================================
    -- 5. FINALER KOMBINATORISCHER TREFFER-AUSGANG (Zur FSM)
    -- =================================================================
    process(v_greater, v_equal, h_equal_greater, blitter_wait_satisfied)
    begin
        if blitter_wait_satisfied = '1' then
            if v_greater = '1' then
                position_match <= '1'; 
            elsif v_equal = '1' and h_equal_greater = '1' then
                position_match <= '1'; 
            else
                position_match <= '0';
            end if;
        else
            position_match <= '0'; 
        end if;
    end process;

end Behavioral;
