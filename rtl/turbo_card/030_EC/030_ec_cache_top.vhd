-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_top.vhd
-- Teil:    1 von 4 (Entity-Schnittstelle des L1-Cache-Subsystems)
-- Funktion: Das hocheffiziente, block-optimierte 32-KB L1-Cache-Subsystem.
--           STABILITÄTS-FIX: Einbau eines synchronen Clear-Zählers für die
--                            Valid-Matrizen zur echten M10K-Ressourcenschonung.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_top is
    Port (
        -- Globale Systemsynchronisation
        CLK             : in    std_logic;                      -- Schneller Systemtakt
        RESET_N         : in    std_logic;                      -- System-Reset (Low-Aktiv)

        -- Core-Schnittstelle zum Adress- und Datenbus
        cpu_A           : in    std_logic_vector(31 downto 0);  
        cpu_D_in        : in    std_logic_vector(31 downto 0);  
        cpu_D_out       : out   std_logic_vector(31 downto 0);  
        cpu_RW          : in    std_logic;                      
        cpu_req         : in    std_logic;                      
        cpu_is_code     : in    std_logic;                      

        -- Steuerschnittstelle aus dem CACR-Register
        cacr_ei         : in    std_logic;                      
        cacr_fi         : in    std_logic;                      
        cacr_ed         : in    std_logic;                      
        cacr_fd         : in    std_logic;                      
        cacr_ci         : in    std_logic;                      
        cacr_cd         : in    std_logic;                      

        -- Status-Rückmeldungen an den Hauptdecoder
        cache_hit       : out   std_logic;                      
        cache_miss      : out   std_logic;                      

        -- Schnittstelle zum internen FPGA-Block-RAM (Kickstart-BRAM)
        bram_b_addr     : out   std_logic_vector(18 downto 0);  
        bram_b_data_w   : out   std_logic_vector(31 downto 0);  
        bram_b_data_r   : in    std_logic_vector(31 downto 0);  
        bram_b_we       : out   std_logic;                      

        -- Schnittstelle nach außen zur Turbokarten-Bridge
        bridge_req      : out   std_logic;                      
        bridge_burst_en : out   std_logic;                      
        bridge_ready    : in    std_logic                       
    );
end cpu_030_ec_cache_top;

architecture structural of cpu_030_ec_cache_top is

    -- =====================================================================
    -- STRUKTUR-DEKLARATION FÜR DIE 32 KB + 32 KB CACHES (4-WAY ASSOCIATIVE)
    -- =====================================================================
    subtype cache_word  is std_logic_vector(31 downto 0);
    type    way_array   is array (0 to 3) of cache_word;
    type    set_matrix  is array (0 to 255) of way_array;

    signal icache_data : set_matrix := (others => (others => (others => '0')));
    signal dcache_data : set_matrix := (others => (others => (others => '0')));

    -- HARDWARE-SICHERUNG: UNBESTECHLICHE INTEL M10K PRAGMAS
    attribute ramstyle : string;
    attribute ramstyle of icache_data : signal is "no_rw_check, M10K";
    attribute ramstyle of dcache_data : signal is "no_rw_check, M10K";

    -- =====================================================================
    -- TAG-SPEICHER UND VALID-BITS (ADRESS-SPIEGELUNG MIT ERWEITERTEM TAG)
    -- =====================================================================
    subtype tag_vector is std_logic_vector(19 downto 0);
    type    tag_array  is array (0 to 3) of tag_vector;
    type    tag_matrix is array (0 to 255) of tag_array;

    signal icache_tags : tag_matrix := (others => (others => (others => '0')));
    signal dcache_tags : tag_matrix := (others => (others => (others => '0')));

    type    valid_bits is array (0 to 3) of std_logic;
    type    valid_matrix is array (0 to 255) of valid_bits;

    signal icache_valid : valid_matrix := (others => (others => '0'));
    signal dcache_valid : valid_matrix := (others => (others => '0'));

    -- SILIZIUM-REPARATUR: Synchroner Clear-Zähler für hardwaregerechte Initialisierung
    signal clear_counter  : integer range 0 to 255 := 0;
    signal cache_clearing : std_logic := '1'; -- Startet aktiv nach Power-On

    -- Interne Hilfssignale zur scharfen Adress-Zerlegung
    signal s_tag        : std_logic_vector(19 downto 0); 
    signal s_index      : integer range 0 to 255;        
    signal s_word_sel   : integer range 0 to 3;          

    -- Kombinatorische Hit/Miss-Statussignale für die Auswertung
    signal ihit_way     : integer range 0 to 3 := 0;
    signal dhit_way     : integer range 0 to 3 := 0;
    signal icache_hit_s : std_logic := '0';
    signal dcache_hit_s : std_logic := '0';
    
    -- Eiserner Hardware-Schutz: Cache-Inhibit für den originalen Amiga-Chipsatz
    signal cache_inhibit : std_logic := '0';
    
    -- Interner Indikator für den 512 KB Kickstart-BRAM-Expresskanal
    signal kickstart_select : std_logic := '0';

begin

    -- =====================================================================
    -- ADRESSZERLEGUNG AM CORE-BUS (KALIBRIERT AUF 256 SETS)
    -- =====================================================================
    s_tag      <= cpu_A(31 downto 12);
    s_index    <= to_integer(unsigned(cpu_A(11 downto 4)));
    s_word_sel <= to_integer(unsigned(cpu_A(3 downto 2)));

    -- EISERNER CHIP-RAM PROTEKTOR: Blockiert Caching im Amiga-Chipsatzraum!
    cache_inhibit <= '1' when unsigned(cpu_A(31 downto 24)) = x"00" else '0';
    
    -- Messerscharfe Erkennung des 512 KB Kickstart-Adressfensters
    kickstart_select <= '1' when (cpu_A(31 downto 19) = "0000000011111100000") else '0';

    -- =====================================================================
    -- KOMBINAOTORISCHE HIT-EVALUATION FÜR DIE BEIDEN 32-KB-BÄNKE (0 WAIT-STATES)
    -- =====================================================================
    process(cpu_req, cpu_is_code, s_index, s_tag, icache_tags, icache_valid, 
            dcache_tags, dcache_valid, cache_inhibit, kickstart_select, cacr_ei, cacr_ed, cache_clearing)
        variable i_hit : std_logic;
        variable d_hit : std_logic;
    begin
        i_hit        := '0';
        d_hit        := '0';
        ihit_way     <= 0;
        dhit_way     <= 0;
        icache_hit_s <= '0';
        dcache_hit_s <= '0';

        -- Trefferprüfung ist nur außerhalb des Löschzyklus zulässig
        if cpu_req = '1' and cache_inhibit = '0' and kickstart_select = '0' and cache_clearing = '0' then
            -- A: INSTRUCTION-CACHE AUSWERTUNG (BEFEHLSABRUF)
            if cpu_is_code = '1' and cacr_ei = '1' then
                for way in 0 to 3 loop
                    if icache_valid(s_index)(way) = '1' and icache_tags(s_index)(way) = s_tag then
                        i_hit        := '1';
                        ihit_way     <= way;
                        icache_hit_s <= '1';
                    end if;
                end loop;
            end if;

            -- B: DATA-CACHE AUSWERTUNG (DATENZUGRIFF)
            if cpu_is_code = '0' and cacr_ed = '1' then
                for way in 0 to 3 loop
                    if dcache_valid(s_index)(way) = '1' and dcache_tags(s_index)(way) = s_tag then
                        d_hit        := '1';
                        dhit_way     <= way;
                        dcache_hit_s <= '1';
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- =====================================================================
    -- SYSTEM-STATUSRÜCKMELDUNG AN DEN TOP-DECODER MITSAMT L1-HIT-BYPASS
    -- =====================================================================
    process(cpu_req, cpu_is_code, icache_hit_s, dcache_hit_s, cache_inhibit, 
            kickstart_select, icache_data, dcache_data, s_index, s_word_sel, 
            ihit_way, dhit_way, bram_b_data_r)
    begin
        cache_hit  <= '0';
        cache_miss <= '0';
        cpu_D_out  <= (others => '0');

        if cpu_req = '1' then
            -- 1. STRATEGISCHER SCHACHZUG: Der 0-Wait-State Kickstart-Expresskanal
            if kickstart_select = '1' then
                cache_hit <= '1';                    
                cpu_D_out <= bram_b_data_r;          
            
            -- 2. ORIGINALER CHIP-RAM / REGISTERSCHUTZ (CACHE INHIBIT AKTIV)
            elsif cache_inhibit = '1' then
                cache_miss <= '1';                   
                cpu_D_out  <= (others => '0');
                
            -- 3. REGULÄRE CACHE EVALUATION MIT UNBESTECHLICHEM KOMBINATORISCHEM BYPASS
            else
                if cpu_is_code = '1' then
                    if icache_hit_s = '1' then
                        cache_hit <= '1';
                        cpu_D_out <= icache_data(s_index)(ihit_way);
                    else
                        cache_miss <= '1';
                    end if;
                else
                    if dcache_hit_s = '1' then
                        cache_hit <= '1';
                        cpu_D_out <= dcache_data(s_index)(dhit_way);
                    else
                        cache_miss <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =====================================================================
    -- SYNCHRONER CONTROL-PROZESS: HARDWAREGERECHTE SEQUEZIELLE INITIALISIERUNG
    -- =====================================================================
    process(CLK, RESET_N)
        variable fill_way : integer range 0 to 3 := 0;
    begin
        if RESET_N = '0' then
            -- SILIZIUM-SICHERUNG: Keine asynchronen Schleifen über die ganze Matrix!
            -- Wir starten stattdessen einfach den synchronen Hardware-Löschzyklus.
            clear_counter   <= 0;
            cache_clearing  <= '1';
            
            bram_b_addr     <= (others => '0');
            bram_b_data_w   <= (others => '0'); 
            bram_b_we       <= '0';
            bridge_req      <= '0';
            bridge_burst_en <= '0';

        elsif rising_edge(CLK) then
            -- Standard-Impulse und Treiber-Drahtbrücken vorab zurücksetzen
            bram_b_we       <= '0';
            bram_b_data_w   <= (others => '0'); 
            bram_b_addr     <= (others => '0');
            bridge_req      <= '0';
            bridge_burst_en <= '0';

            -- 1. HARDWAREGERECHTE SEQUENZIELLE LÖSCH-ZUSTANDSMASCHINE
            if cache_clearing = '1' then
                -- Nullt taktgenau ein Set nach dem anderen aus (Verhindert LE-Explosion)
                for way in 0 to 3 loop
                    icache_valid(clear_counter)(way) <= '0';
                    dcache_valid(clear_counter)(way) <= '0';
                end loop;
                
                if clear_counter = 255 then
                    cache_clearing <= '0'; -- Initialisierung nach 256 Takten stabil beendet!
                else
                    clear_counter <= clear_counter + 1;
                end if;

            -- 2. REGULÄRES BETRIEBS-MANAGEMENT BEI REINEM FLIESSBAND-LAUF
            else
                -- SOFTWARE-GESTEUERTER GLOBALER CACHE-CLEAR (CACR-BEFEHL)
                -- Zündet den Löschzähler im Flug, ohne die CPU-Pipeline abstürzen zu lassen
                if cacr_ci = '1' or cacr_cd = '1' then
                    clear_counter  <= 0;
                    cache_clearing <= '1';
                end if;

                if cpu_req = '1' then
                    -- SCHACHZUG A: CPU FRAGT DAS KICKSTART-ROM AN (EXPRESSWEICHE PORT B)
                    if kickstart_select = '1' then
                        bram_b_addr   <= cpu_A(18 downto 0); 
                        bram_b_we     <= '0';                -- Absolute ROM-Schreibsperre
                        bram_b_data_w <= (others => '0');    
                        
                    -- SCHACHZUG B: CORESCHREIBAUSTRITT (NATIVE 68030 WRITE-THROUGH LOGIK)
                    elsif cpu_RW = '0' and cache_inhibit = '0' then
                        bridge_req <= '1'; -- Miss-Schreibzyklen gehen immer parallel zur TK-Bridge
                        
                        -- HIT-PRÜFUNG: Liegen die Daten im verkleinerten 32-KB D-Cache?
                        if dcache_hit_s = '1' and cacr_fd = '0' then
                            dcache_data(s_index)(dhit_way) <= cpu_D_in; -- Taktgenaues Zeilen-Update im M10K
                        end if;

                    -- SCHACHZUG C: CORE LIEST DATEN ODER BEFEHLE (32-KB L1-MISS-REPARATUR)
                    elsif cpu_RW = '1' and cache_inhibit = '0' then
                        if (cpu_is_code = '1' and icache_hit_s = '0') or 
                           (cpu_is_code = '0' and dcache_hit_s = '0') then
                            
                            bridge_req      <= '1';
                            bridge_burst_en <= '1'; -- Burst-Anforderung scharfschalten
                            
                            -- Sobald die TK-Bridge das FastRAM-Wort liefert, Zeile einrasten
                            if bridge_ready = '1' then
                                fill_way := to_integer(unsigned(cpu_A(5 downto 4)));
                                
                                if cpu_is_code = '1' and cacr_fi = '0' then
                                    icache_data(s_index)(fill_way)  <= bram_b_data_r;
                                    icache_tags(s_index)(fill_way)  <= s_tag;
                                    icache_valid(s_index)(fill_way) <= '1';
                                elsif cpu_is_code = '0' and cacr_fd = '0' then
                                    dcache_data(s_index)(fill_way)  <= bram_b_data_r;
                                    dcache_tags(s_index)(fill_way)  <= s_tag;
                                    dcache_valid(s_index)(fill_way) <= '1';
                                end if;
                            end if;
                        end if;
                        
                    -- SCHACHZUG D: REGULÄRER AMIGA-CHIPSATZRAUM (CACHE INHIBIT AKTIV)
                    elsif cache_inhibit = '1' then
                        bridge_req <= '1'; 
                    end if;
                end if;
            end if;
        end if;
    end process;

end structural;
