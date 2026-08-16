-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   copper_sync.vhd
-- Funktion: Die synchrone Video-Strahl-Vergleicher-Matrix des Coppers.
-- SANIERUNG SCHRITT 24:
--   - Überführung der Treffer-Entscheidung in die 14,18-MHz Takt-Pipeline! [14.1]
--   - Eliminierung aller kombinatorischen Laufzeit-Glitches (Hazards).
--   - Garantiert, dass der Copper zeilen- und pixelgenau aufschließt.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity copper_sync is
    Port (
        -- =============================================================
        -- 1. SCHNITTSTELLE ZUM VIDEO-STRAHLZÄHLER (VON ALICE_BEAM.VHD)
        -- =============================================================
        beam_h_pos    : in    unsigned(8 downto 0);          -- Aktueller H-Strahl (0-226)
        beam_v_pos    : in    unsigned(8 downto 0);          -- Aktuelle V-Zeile (0-311)
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM BEFEHLS-DECODER (VON COPPER_DEC.VHD)
        -- =============================================================
        target_h_pos  : in    unsigned(8 downto 0);
        target_v_pos  : in    unsigned(8 downto 0);
        target_mask_h : in    std_logic_vector(8 downto 0);
        target_mask_v : in    std_logic_vector(8 downto 0);
        
        -- Statussignal vom Blitter für WAIT-Befehle auf Blitter-Ende
        blitter_done  : in    std_logic;                     
        
        -- Takt für den synchronen Latenz-Prozess
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
    
    -- Das Pipeline-Register zur Erzeugung der historischen 1-Takt-Latenz
    signal blitter_done_delayed : std_logic := '1';
    signal blitter_wait_satisfied : std_logic;

begin

    -- =================================================================
    -- 1. BIT-MASKIERUNG DER KOORDINATEN (GATTERGETREUER FILTER)
    -- =================================================================
    masked_beam_v   <= beam_v_pos and unsigned(target_mask_v);
    masked_target_v <= target_v_pos and unsigned(target_mask_v);
    
    masked_beam_h   <= beam_h_pos and unsigned(target_mask_h);
    masked_target_h <= target_h_pos and unsigned(target_mask_h);

    -- =================================================================
    -- 2. HISTORISCHE GRÖSSER-GLEICH-AUSWERTUNG (>= RASTER DES AMIGAS)
    -- =================================================================
    v_equal   <= '1' when masked_beam_v = masked_target_v else '0';
    v_greater <= '1' when masked_beam_v > masked_target_v else '0';
    
    h_equal_greater <= '1' when masked_beam_h >= masked_target_h else '0';

    -- SONDERLOGIK: WARTEN AUF HARDWARE-BLITTER
    blitter_wait_satisfied <= '1' when (target_mask_v(8) = '1' or blitter_done_delayed = '1') else '0';

    -- =================================================================
    -- 3. REPARATUR: VOLL-SYNCHRONER ENTSCHEIDUNGS- UND PIPELINE-PROZESS
    -- =================================================================
    -- Überführt alle Vergleiche starr unter den Haupttakt. Alle Hazard-Wechsel
    -- während des Strahlvorschubs werden im Flip-Flop-Bett restlos abgefangen [14.1].
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            blitter_done_delayed <= '1';
            position_match       <= '0';
        elsif rising_edge(clk_amiga) then
            -- Zyklustreuer Daten-Verzug für den Blitter-Handshake [14.1]
            blitter_done_delayed <= blitter_done;

            -- Taktgenaue Absicherung des Ausgangs-Pins zur FSM
            if blitter_wait_satisfied = '1' then
                if v_greater = '1' then
                    position_match <= '1'; -- Wunschzeile weit überschritten
                elsif v_equal = '1' and h_equal_greater = '1' then
                    position_match <= '1'; -- Exakte Strahlposition erreicht/überschritten
                else
                    position_match <= '0'; -- Strahl befindet sich noch vor der Zielkoordinate
                end if;
            else
                position_match <= '0'; -- Blitter läuft noch ➔ Weitermarsch blockieren!
            end if;
        end if;
    end process;

end Behavioral;
