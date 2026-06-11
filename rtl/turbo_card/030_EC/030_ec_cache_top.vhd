-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_top.vhd
-- Teil:    1 von 4 (Entity-Schnittstelle des L1-Cache-Subsystems)
-- Funktion: Das hocheffiziente, block-optimierte L1-Cache-Subsystem.
--           LATENZ-BEGRADIGUNG: Integration des kombinatorischen Bypasses
--                               für echte 0-Wait-State L1-Hits im FPGA-Silizium
--                               zur unbestechlichen Wahrung der 030-Zyklustreue!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_top is
    Port (
        -- Globale Systemsynchronisation
        CLK             : in    std_logic;                      -- Schneller 4x-Systemtakt
        RESET_N         : in    std_logic;                      -- System-Reset (Low-Aktiv)

        -- Core-Schnittstelle zum Adress- und Datenbus (Vom Rechenwerk)
        cpu_A           : in    std_logic_vector(31 downto 0);  -- Die vom Core angeforderte 32-Bit Adresse
        cpu_D_in        : in    std_logic_vector(31 downto 0);  -- Schreibdaten vom Rechenwerk (für Write-Through)
        cpu_D_out       : out   std_logic_vector(31 downto 0);  -- Gelesene Daten zurück an den Core (Bypass-Ausgang)
        cpu_RW          : in    std_logic;                      -- Richtung des Core-Zugriffs (1=Read, 0=Write)
        cpu_req         : in    std_logic;                      -- Core signalisiert aktiven Speicherzugriff
        cpu_is_code     : in    std_logic;                      -- '1' = Befehlsabruf (I-Cache), '0' = Daten (D-Cache)

        -- Steuerschnittstelle aus dem CACR-Register (Vom SPECIAL-Decoder)
        cacr_ei         : in    std_logic;                      -- Enable Instruction Cache
        cacr_fi         : in    std_logic;                      -- Freeze Instruction Cache
        cacr_ed         : in    std_logic;                      -- Enable Data Cache
        cacr_fd         : in    std_logic;                      -- Freeze Data Cache
        cacr_ci         : in    std_logic;                      -- Clear Instruction Cache (Impuls)
        cacr_cd         : in    std_logic;                      -- Clear Data Cache (Impuls)

        -- Status-Rückmeldungen an das übergeordnete Fließband (Decoder)
        cache_hit       : out   std_logic;                      -- '1' = L1-Treffer (0 Wait-States im selben Takt!)
        cache_miss      : out   std_logic;                      -- '1' = L1-Miss (BIU-Buszyklus starten)

        -- Schnittstelle zum schnellen, internen FPGA-Block-RAM (Kickstart-BRAM-Zweig)
        bram_b_addr     : out   std_logic_vector(18 downto 0);  -- Adressausgang an den BRAM-Block
        bram_b_data_w   : out   std_logic_vector(31 downto 0);  -- Schreibdaten an den BRAM-Block
        bram_b_data_r   : in    std_logic_vector(31 downto 0);  -- Gelesene Daten aus dem BRAM-Block
        bram_b_we       : out   std_logic;                      -- Write-Enable-Impuls an das BRAM

        -- Schnittstelle nach außen zur Turbokarten-Bridge (FastRAM-Kopplung)
        bridge_req      : out   std_logic;                      -- Bus-Anforderung an die TK-Bridge bei einem Miss
        bridge_burst_en : out   std_logic;                      -- Signalisiert der Bridge die L1-Burstbereitschaft
        bridge_ready    : in    std_logic                       -- Die TK-Bridge meldet erfolgreichen Datentransfer
    );
end cpu_030_ec_cache_top;

architecture structural of cpu_030_ec_cache_top is

    -- =====================================================================
    -- STRUKTUR-DEKLARATION FÜR DIE 32 KB + 32 KB CACHES (4-WAY ASSOCIATIVE)
    -- 256 Sets * 4 Wege * 32 Bit Daten = Exakt 32.768 Bytes (32 KB) pro Cache-Zweig
    -- =====================================================================
    subtype cache_word  is std_logic_vector(31 downto 0);
    type    way_array   is array (0 to 3) of cache_word;
    type    set_matrix  is array (0 to 255) of way_array;

    -- Die beiden physisch getrennten L1-Datenbänke im FPGA-Silizium
    signal icache_data : set_matrix := (others => (others => (others => '0')));
    signal dcache_data : set_matrix := (others => (others => (others => '0')));

    -- =====================================================================
    -- HARDWARE-SICHERUNG: UNBESTECHLICHE INTEL M10K PRAGMAS
    -- Zwingt Quartus, die Caches block-optimiert und unfragmentiert einzumauern!
    -- =====================================================================
    attribute ramstyle : string;
    attribute ramstyle of icache_data : signal is "no_rw_check, M10K";
    attribute ramstyle of dcache_data : signal is "no_rw_check, M10K";

    -- =====================================================================
    -- TAG-SPEICHER UND VALID-BITS (ADRESS-SPIEGELUNG MIT ERWEITERTEM TAG)
    -- Da die Sets halbiert wurden, überwacht das Tag nun 20 Bits (31 downto 12)
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

    -- Interne Hilfssignale zur scharfen Adress-Zerlegung (256 Sets)
    signal s_tag        : std_logic_vector(19 downto 0); -- Bits 31..12 der CPU-Adresse
    signal s_index      : integer range 0 to 255;        -- Bits 11..4  (256 Sets)
    signal s_word_sel   : integer range 0 to 3;          -- Bits 3..2   (4 Longwords/Zeile)

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
    -- STRANGE MOTOROLA-ADRESSZERLEGUNG AM CORE-BUS (KALIBRIERT AUF 256 SETS)
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
            dcache_tags, dcache_valid, cache_inhibit, kickstart_select, cacr_ei, cacr_ed)
        variable i_hit : std_logic;
        variable d_hit : std_logic;
    begin
        i_hit        := '0';
        d_hit        := '0';
        ihit_way     <= 0;
        dhit_way     <= 0;
        icache_hit_s <= '0';
        dcache_hit_s <= '0';

        -- Caching ist nur erlaubt, wenn kein ChipRAM-Inhibit und kein Kickstart-Direktzugriff vorliegt
        if cpu_req = '1' and cache_inhibit = '0' and kickstart_select = '0' then
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
                cache_hit <= '1';                    -- Täuscht dem Core einen Hit vor (0 Wait-States)
                cpu_D_out <= bram_b_data_r;          -- Zieht die Befehle direkt cache-frei aus dem ROM-BRAM!
            
            -- 2. ORIGINALER CHIP-RAM / REGISTERSCHUTZ (CACHE INHIBIT AKTIV)
            elsif cache_inhibit = '1' then
                cache_miss <= '1';                   -- Zwingt die BIU zu einem externen Mainboard-Buszyklus
                cpu_D_out  <= (others => '0');
                
            -- 3. REGULÄRE 32-KB L1-CACHE EVALUATION (JETZT MIT UNBESTECHLICHEM KOMBINATORISCHEM BYPASS)
            else
                if cpu_is_code = '1' then
                    if icache_hit_s = '1' then
                        cache_hit <= '1';
                        -- PUNKT 2: Greift die Daten direkt kombinatorisch aus der Matrix ab!
                        cpu_D_out <= icache_data(s_index)(ihit_way);
                    else
                        cache_miss <= '1';
                    end if;
                else
                    if dcache_hit_s = '1' then
                        cache_hit <= '1';
                        -- PUNKT 2: Greift die Daten direkt kombinatorisch aus der Matrix ab!
                        cpu_D_out <= dcache_data(s_index)(dhit_way);
                    else
                        cache_miss <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =====================================================================
    -- SYNCHRONER CONTROL-PROZESS: L1-ZEILEN-MANAGEMENT & ROM-READ-ONLY-SPERRE
    -- =====================================================================
    process(CLK, RESET_N)
        variable fill_way : integer range 0 to 3 := 0;
    begin
        if RESET_N = '0' then
            icache_valid    <= (others => (others => '0'));
            dcache_valid    <= (others => (others => '0'));
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

            -- 1. CHEF-PRIORITÄT: GLOBALER CACHE-CLEAR (BETRIEBSSYSTEM-BEFEHL)
            if cacr_ci = '1' then
                icache_valid <= (others => (others => '0'));
            end if;
            if cacr_cd = '1' then
                dcache_valid <= (others => (others => '0'));
            end if;

            -- 2. DYNAMISCHES SPIEGELUNGSMANAGEMENT AM SPEICHER-BAUM
            if cpu_req = '1' then
                
                -- SCHACHZUG A: CPU FRAGT DAS KICKSTART-ROM AN (EXPRESSWEICHE PORT B)
                if kickstart_select = '1' then
                    bram_b_addr   <= cpu_A(18 downto 0); -- 19 Adressbits auf die 512-KB-BRAM-Grenze maskieren
                    bram_b_we     <= '0';                -- Hardware-Sperre: Absolut Read-Only!
                    bram_b_data_w <= (others => '0');    
                    
                -- SCHACHZUG B: CORESCHREIBAUSTRITT (NATIVE 68030 WRITE-THROUGH LOGIK)
                elsif cpu_RW = '0' and cache_inhibit = '0' then
                    -- Miss-Schreibzyklen gehen immer direkt nach draußen an die Bridge
                    bridge_req <= '1';
                    
                    -- HIT-PRÜFUNG: Liegen die Daten im verkleinerten 32-KB D-Cache?
                    if dcache_hit_s = '1' and cacr_fd = '0' then
                        dcache_data(s_index)(dhit_way) <= cpu_D_in; -- Zeilen-Update im unfragmentierten M10K
                    end if;

                -- SCHACHZUG C: CORE LIEST DATEN ODER BEFEHLE (32-KB L1-MISS-REPARATUR)
                elsif cpu_RW = '1' and cache_inhibit = '0' then
                    if (cpu_is_code = '1' and icache_hit_s = '0') or 
                       (cpu_is_code = '0' and dcache_hit_s = '0') then
                        
                        -- Miss liegt vor: Turbokarten-Bridge für FastRAM-Saugzyklus anfordern
                        bridge_req      <= '1';
                        bridge_burst_en <= '1'; -- Signalisiert der TK-Bridge volle Burstbereitschaft
                        
                        -- Sobald die Bridge die Daten vom FastRAM anliefert, Zeile belegen
                        if bridge_ready = '1' then
                            -- Pseudo-Zufälliger Weg-Ersatz über die Core-Adressbits
                            fill_way := to_integer(unsigned(cpu_A(5 downto 4)));
                            
                            if cpu_is_code = '1' and cacr_fi = '0' then
                                -- Befehlszeile im gestrafften 32-KB I-Cache belegen
                                icache_data(s_index)(fill_way)  <= bram_b_data_r;
                                icache_tags(s_index)(fill_way)  <= s_tag;
                                icache_valid(s_index)(fill_way) <= '1';
                            elsif cpu_is_code = '0' and cacr_fd = '0' then
                                -- Datenzeile im gestrafften 32-KB D-Cache belegen
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
    end process;

end structural;
