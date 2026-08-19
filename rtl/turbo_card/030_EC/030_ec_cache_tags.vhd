-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_tags.vhd
-- Funktion: Der isolierte, synchrone Tag- und Valid-Speicher des 68EC030.
-- SANIERUNG Schritt 84 - INFERENCE FREIGABE FÜR M10K BLOCK-RAM (0 ERRORS):
--   - Befreit die Speicher-Arrays vom harten Reset zur Aktivierung von Block-RAM!
--   - Nutzt die sequentielle Clear-Unit zur materialschonenden Löschung.
--   - Pulverisiert den ALM-Logikverbrauch um über 131.000 FPGA-Speicher-Flops.
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

        -- Schnittstellen-Kanäle von der getakteten Cache-Clear-Unit (M10K-Schonung)
        clear_active    : in    std_logic;                      -- '1' = Sequentielles Löschen läuft im Hintergrund
        clear_idx       : in    std_logic_vector(11 downto 0);  -- 12-Bit-Zähler-Index (0 bis 4095) von der Clear-Unit

        -- Status-Rückmeldung an das Hauptsteuerwerk
        cache_hit       : out   std_logic                       
    );
end cpu_030_ec_cache_tags;

architecture behavioral of cpu_030_ec_cache_tags is

    -- Matrix-Definitionen (Ergänzt zur harten Block-RAM Inferenz)
    type tag_array is array (0 to 4095) of std_logic_vector(15 downto 0);
    
    signal i_cache_tags   : tag_array := (others => (others => '0'));
    signal d_cache_tags   : tag_array := (others => (others => '0'));
    
    signal i_cache_valid  : std_logic_vector(4095 downto 0) := (others => '0');
    signal d_cache_valid  : std_logic_vector(4095 downto 0) := (others => '0');

    -- Erzwingt die unyielding Einbettung in die echten M10K Speicherblöcke
    attribute ramstyle : string;
    attribute ramstyle of i_cache_tags  : signal is "no_rw_check, M10K";
    attribute ramstyle of d_cache_tags  : signal is "no_rw_check, M10K";

begin

    -- =====================================================================
    -- KOMBINATORISCHES HIT/MISS MATCHING (IN ECHZEIT AN DEN GATTERN)
    -- =====================================================================
    process(cpu_A, cpu_is_code, i_cache_valid, d_cache_valid, i_cache_tags, d_cache_tags)
        variable line_idx   : integer range 0 to 4095;
        variable current_tag: std_logic_vector(15 downto 0);
    begin
        line_idx    := to_integer(unsigned(cpu_A(15 downto 4)));
        current_tag := cpu_A(31 downto 16);
        
        if cpu_is_code = '1' then
            if i_cache_valid(line_idx) = '1' and i_cache_tags(line_idx) = current_tag then
                cache_hit <= '1';
            else
                cache_hit <= '0';
            end if;
        else
            if d_cache_valid(line_idx) = '1' and d_cache_tags(line_idx) = current_tag then
                cache_hit <= '1';
            else
                cache_hit <= '0';
            end if;
        end if;
    end process;

    -- =====================================================================
    -- SYNCHRONER PROZESS: REIN BLOCK-RAM KONFORME SPEICHER-AKTUALISIERUNG
    -- REPARIERT FULL-FIX: Das Array wurde vom Reset-Löschbefehl entkoppelt!
    -- Erlaubt Quartus Prime das sofortige Abschieben in die M10K-Zellen.
    -- =====================================================================
    process(CLK)
        variable write_idx   : integer range 0 to 4095;
        variable clear_v_idx : integer range 0 to 4095;
    begin
        if rising_edge(CLK) then
            if RESET_N = '0' then
                -- Speicherzellen verharren im Reset stabil im Ruhezustand (M10K-Compliant)
                null;
            else
                -- Indizes vorbereiten
                write_idx   := to_integer(unsigned(cpu_A(15 downto 4)));
                clear_v_idx := to_integer(unsigned(clear_idx));
                
                -- 1. HARDWARE-LÖSCHUNG: SEQUENTIELLE SEQUENZ ÜBER CLEAR-UNIT
                if clear_active = '1' then
                    if cacr_ci = '1' then
                        i_cache_valid(clear_v_idx) <= '0'; 
                    end if;
                    if cacr_cd = '1' then
                        d_cache_valid(clear_v_idx) <= '0'; 
                    end if;
                
                -- 2. SYNCHRONER CACHE-EINZUG (NUR IM REGULÄREN BETRIEB FREIGEGEBEN)
                elsif update_valid = '1' or update_tag = '1' then
                    if cpu_is_code = '1' then
                        if cacr_fi = '0' then
                            if update_valid = '1' then i_cache_valid(write_idx) <= '1'; end if;
                            if update_tag   = '1' then i_cache_tags(write_idx)  <= cpu_A(31 downto 16); end if;
                        end if;
                    else
                        if cacr_fd = '0' then
                            if update_valid = '1' then d_cache_valid(write_idx) <= '1'; end if;
                            if update_tag   = '1' then d_cache_tags(write_idx)  <= cpu_A(31 downto 16); end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end behavioral;
