-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_tags.vhd
-- Funktion: Der isolierte, synchrone Tag- und Valid-Speicher des 68EC030.
--           Verwaltet 4096 Cache-Zeilen mit 16-Bit Adress-Tags.
--           Bietet ultraschnelles Hit/Miss-Matching für Befehle und Daten.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_tags is
    Port (
        CLK             : in    std_logic;                      -- Schneller 4x-Systemtakt
        RESET_N         : in    std_logic;                      -- System-Reset

        -- Adress-Eingänge von der CPU
        cpu_A           : in    std_logic_vector(31 downto 0);  -- Aktuelle CPU-Adresse
        cpu_is_code     : in    std_logic;                      -- '1' = Instruction, '0' = Data
        
        -- Aktualisierungs-Schnittstelle vom Hauptsteuerwerk (Cache Update)
        update_valid    : in    std_logic;                      -- '1' triggert das Setzen des Valid-Bits
        update_tag      : in    std_logic;                      -- '1' triggert das Schreiben des neuen Tags

        -- Originale Motorola CACR-Löschimpulse (Vom System-Register)
        cacr_ci         : in    std_logic;                      -- Clear Instruction Cache (Flash Invalidate)
        cacr_cd         : in    std_logic;                      -- Clear Data Cache (Flash Invalidate)
        cacr_fi         : in    std_logic;                      -- Freeze Instruction Cache
        cacr_fd         : in    std_logic;                      -- Freeze Data Cache

        -- Kombinatorische Status-Rückmeldungen ans Hauptsteuerwerk
        cache_hit       : out   std_logic                       -- '1' bei gültigem Tag-Treffer
    );
end cpu_030_ec_cache_tags;

architecture behavioral of cpu_030_ec_cache_tags is

    -- =====================================================================
    -- UNBESTECHLICHES 64-KB HARDWARE-TAG-RAM (4096 ZEILEN)
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
    -- SYNCHRONER PROZESS: SPEICHER-AKTUALISIERUNG UND OS-LÖSCHUNG
    -- =====================================================================
    process(CLK, RESET_N)
        variable line_idx : integer range 0 to 4095;
    begin
        if RESET_N = '0' then
            i_cache_valid <= (others => '0');
            d_cache_valid <= (others => '0');
            i_cache_tags  <= (others => (others => '0'));
            d_cache_tags  <= (others => (others => '0'));
            
        elsif rising_edge(CLK) then
            -- Zeilen-Index für das Schreiben vorbereiten
            line_idx := to_integer(unsigned(cpu_A(15 downto 4)));
            
            -- 1. HARDWARE-LÖSCHUNG (FLASH INVALIDATION PER AMIGA OS IMPULS)
            if cacr_ci = '1' then
                i_cache_valid <= (others => '0'); -- Befehls-Cache in einem Takt komplett nullen
            end if;
            if cacr_cd = '1' then
                d_cache_valid <= (others => '0'); -- Daten-Cache in einem Takt komplett nullen
            end if;
            
            -- 2. SYNCHRONER CACHE-EINZUG (VOM CONTROL-STATE-AUTOMATEN GEZEICHNET)
            if update_valid = '1' or update_tag = '1' then
                if cpu_is_code = '1' then
                    -- Befehls-Cache Update (Nur wenn nicht eingefroren!)
                    if cacr_fi = '0' then
                        if update_valid = '1' then i_cache_valid(line_idx) <= '1'; end if;
                        if update_tag   = '1' then i_cache_tags(line_idx)  <= cpu_A(31 downto 16); end if;
                    end if;
                else
                    -- Daten-Cache Update (Nur wenn nicht eingefroren!)
                    if cacr_fd = '0' then
                        if update_valid = '1' then d_cache_valid(line_idx) <= '1'; end if;
                        if update_tag   = '1' then d_cache_tags(line_idx)  <= cpu_A(31 downto 16); end if;
                    end if;
                end if;
            end if;
            
        end if;
    end process;

end behavioral;
