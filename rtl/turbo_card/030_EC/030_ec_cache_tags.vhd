-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_tags.vhd
-- Teil:    1 von 2 (Sanierten Entity-Schnittstelle)
-- Funktion: Der isolierte, synchrone Tag- und Valid-Speicher des 68EC030.
--           SCHRITT 5 SANIERUNG:
--           - Einbau sequentieller Clear-Ports zur M10K-Block-RAM-Schonung.
--           - Verhindert ALM-Ressourcen-Overflow in Intel Quartus Prime.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_tags is
    Port (
        CLK             : in    std_logic;                      -- Hauptsystemtakt
        RESET_N         : in    std_logic;                      -- Low-Aktiver System-Reset

        -- Adress-Eingänge von der CPU
        cpu_A           : in    std_logic_vector(31 downto 0);  
        cpu_is_code     : in    std_logic;                      
        
        -- Aktualisierungs-Schnittstelle vom Hauptsteuerwerk
        update_valid    : in    std_logic;                      
        update_tag      : in    std_logic;                      

        -- Originale Motorola CACR-Steuerleitungen
        cacr_ci         : in    std_logic;                      -- Triggert den sequentiellen Clear-Vorgang I-Cache
        cacr_cd         : in    std_logic;                      -- Triggert den sequentiellen Clear-Vorgang D-Cache
        cacr_fi         : in    std_logic;                      
        cacr_fd         : in    std_logic;

        -- NEU: Schnittstellen-Kanäle von der getakteten Cache-Clear-Unit (M10K-Schonung)
        clear_active    : in    std_logic;                      -- '1' = Sequentielles Löschen läuft im Hintergrund
        clear_idx       : in    std_logic_vector(11 downto 0);  -- 12-Bit-Zähler-Index (0 bis 4095) von der Clear-Unit

        -- Status-Rückmeldung an das Hauptsteuerwerk
        cache_hit       : out   std_logic                       
    );
end cpu_030_ec_cache_tags;

architecture behavioral of cpu_030_ec_cache_tags is

    -- =====================================================================
    -- KONSOLIDIERTE RESTRUKTURIERUNG: M10K-SCHONENDE MATRIX-FELDER
    -- =====================================================================
    type tag_array is array (0 to 4095) of std_logic_vector(15 downto 0);
    
    signal i_cache_tags   : tag_array := (others => (others => '0'));
    signal d_cache_tags   : tag_array := (others => (others => '0'));
    
    signal i_cache_valid  : std_logic_vector(4095 downto 0) := (others => '0');
    signal d_cache_valid  : std_logic_vector(4095 downto 0) := (others => '0');

begin

    -- =====================================================================
    -- KOMBINATORISCHES HIT/MISS MATCHING (IN ECHZEIT AN DEN GATTERN)
    -- =====================================================================
    process(cpu_A, cpu_is_code, i_cache_valid, d_cache_valid, i_cache_tags, d_cache_tags)
        variable line_idx   : integer range 0 to 4095;
        variable current_tag: std_logic_vector(15 downto 0);
    begin
        -- Zeilen-Index extrahieren (Bits 15 bis 4 für 64 KB Cache-Räumlichkeit)
        line_idx    := to_integer(unsigned(cpu_A(15 downto 4)));
        -- Das gesuchte Adress-Tag extrahieren (die oberen 16 Bits der CPU-Adresse)
        current_tag := cpu_A(31 downto 16);
        
        if cpu_is_code = '1' then
            -- Trefferprüfung für den Befehls-Cache (Instruction Cache Hit)
            if i_cache_valid(line_idx) = '1' and i_cache_tags(line_idx) = current_tag then
                cache_hit <= '1';
            else
                cache_hit <= '0';
            end if;
        else
            -- Trefferprüfung für den Daten-Cache (Data Cache Hit)
            if d_cache_valid(line_idx) = '1' and d_cache_tags(line_idx) = current_tag then
                cache_hit <= '1';
            else
                cache_hit <= '0';
            end if;
        end if;
    end process;

    -- =====================================================================
    -- SYNCHRONER PROZESS: M10K-BLOCK-RAM KONFORME SPEICHER-AKTUALISIERUNG
    -- =====================================================================
    process(CLK, RESET_N)
        variable write_idx : integer range 0 to 4095;
        variable clear_v_idx : integer range 0 to 4095;
    begin
        if RESET_N = '0' then
            i_cache_valid <= (others => '0');
            d_cache_valid <= (others => '0');
            i_cache_tags  <= (others => (others => '0'));
            d_cache_tags  <= (others => (others => '0'));
            
        elsif rising_edge(CLK) then
            -- Indizes vorbereiten
            write_idx   := to_integer(unsigned(cpu_A(15 downto 4)));
            clear_v_idx := to_integer(unsigned(clear_idx));
            
            -- 1. HARDWARE-LÖSCHUNG: SEQUENTIELLE SEQUENZ ÜBER CLEAR-UNIT (M10K-RETTUNG)
            if clear_active = '1' then
                if cacr_ci = '1' then
                    i_cache_valid(clear_v_idx) <= '0'; -- Löscht exakt eine Zeile pro Takt schrittweise
                end if;
                if cacr_cd = '1' then
                    d_cache_valid(clear_v_idx) <= '0'; -- Löscht exakt eine Zeile pro Takt schrittweise
                end if;
            
            -- 2. SYNCHRONER CACHE-EINZUG (NUR IM REGULÄREN BETRIEB FREIGEGEBEN)
            elsif update_valid = '1' or update_tag = '1' then
                if cpu_is_code = '1' then
                    -- Befehls-Cache Update (Nur wenn nicht eingefroren!)
                    if cacr_fi = '0' then
                        if update_valid = '1' then i_cache_valid(write_idx) <= '1'; end if;
                        if update_tag   = '1' then i_cache_tags(write_idx)  <= cpu_A(31 downto 16); end if;
                    end if;
                else
                    -- Daten-Cache Update (Nur wenn nicht eingefroren!)
                    if cacr_fd = '0' then
                        if update_valid = '1' then d_cache_valid(write_idx) <= '1'; end if;
                        if update_tag   = '1' then d_cache_tags(write_idx)  <= cpu_A(31 downto 16); end if;
                    end if;
                end if;
            end if;
            
        end if;
    end process;

end behavioral;
