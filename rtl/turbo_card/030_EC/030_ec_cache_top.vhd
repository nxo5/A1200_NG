-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cpu_030_ec_cache_top.vhd
-- Teil:    1 von 4 (Bereinigte Entity-Schnittstelle)
-- Funktion: Das 32-KB L1-Cache-Subsystem (4-Way Associative).
-- KORREKTUREN:
--   - Umstellung der äußeren M10K-Schnittstellen auf PORT A Hoheit!
--   - Hinzufügen von bridge_data_r zur Deadlock-Behebung beim Burst-Fill.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_top is
    Port (
        -- Globale Systemsynchronisation
        CLK             : in    std_logic;                      
        RESET_N         : in    std_logic;                      

        -- Datenpfad-Anbindung an den CPU-Core / Decoder
        cpu_A           : in    std_logic_vector(31 downto 0);  
        cpu_D_in        : in    std_logic_vector(31 downto 0);  
        cpu_D_out       : out   std_logic_vector(31 downto 0);  
        cpu_RW          : in    std_logic;                      
        cpu_req         : in    std_logic;                      
        cpu_is_code     : in    std_logic;                      

        -- Originale Motorola CACR-Steuerleitungen
        cacr_ei         : in    std_logic;                      
        cacr_fi         : in    std_logic;                      
        cacr_ed         : in    std_logic;                      
        cacr_fd         : in    std_logic;                      
        cacr_ci         : in    std_logic;                      
        cacr_cd         : in    std_logic;                      

        -- Status-Rückmeldungen an das CPU-Haupthaus
        cache_hit       : out   std_logic;                      
        cache_miss      : out   std_logic;                      

        -- KORREKTUR PORT A: Physische Leitungen zum Cache-Kanal des BRAMs
        bram_a_addr     : out   std_logic_vector(18 downto 0);  
        bram_a_data_w   : out   std_logic_vector(31 downto 0);  
        bram_a_data_r   : in    std_logic_vector(31 downto 0);  
        bram_a_we       : out   std_logic;                      

        -- Verbindung zur Fast-RAM-Bridge (DDR-RAM) bei einem Cache Miss
        bridge_req      : out   std_logic;                      
        bridge_burst_en : out   std_logic;                      
        bridge_ready    : in    std_logic;                      
        bridge_data_r   : in    std_logic_vector(31 downto 0)   -- KORREKTUR: Reale Nachladedaten der Bridge!
    );
end cpu_030_ec_cache_top;

architecture structural of cpu_030_ec_cache_top is

    -- Matrix-Definitionen (Intel M10K Blöcke erzwingen) [14.1]
    subtype cache_word  is std_logic_vector(31 downto 0);
    type    way_array   is array (0 to 3) of cache_word;
    type    set_matrix  is array (0 to 255) of way_array;

    signal icache_data : set_matrix := (others => (others => (others => '0')));
    signal dcache_data : set_matrix := (others => (others => (others => '0')));

    attribute ramstyle : string;
    attribute ramstyle of icache_data : signal is "no_rw_check, M10K";
    attribute ramstyle of dcache_data : signal is "no_rw_check, M10K";

    subtype tag_vector is std_logic_vector(19 downto 0);
    type    tag_array  is array (0 to 3) of tag_vector;
    type    tag_matrix is array (0 to 255) of tag_array;

    signal icache_tags : tag_matrix := (others => (others => (others => '0')));
    signal dcache_tags : tag_matrix := (others => (others => (others => '0')));

    type    valid_bits is array (0 to 3) of std_logic;
    type    valid_matrix is array (0 to 255) of valid_bits;

    signal icache_valid : valid_matrix := (others => (others => '0'));
    signal dcache_valid : valid_matrix := (others => (others => '0'));

    -- Interne Koppeldrähte für Adresszerlegung
    signal s_tag        : std_logic_vector(19 downto 0); 
    signal s_index      : integer range 0 to 255;        
    signal s_word_sel   : integer range 0 to 3;          

    signal ihit_way     : integer range 0 to 3 := 0;
    signal dhit_way     : integer range 0 to 3 := 0;
    signal icache_hit_s : std_logic := '0';
    signal dcache_hit_s : std_logic := '0';
    
    signal cache_inhibit    : std_logic := '0';
    signal kickstart_select : std_logic := '0';

    -- Signale zu den neuen Sub-Modulen
    signal s_cache_clearing : std_logic;
    signal s_clear_idx      : integer range 0 to 255;
    signal s_clear_pulse    : std_logic;
    signal s_matrix_write   : std_logic;
    signal s_matrix_sel_code: std_logic;

    -- Submodul-Schablonen für Löschung und FSM-Protokoll
    component cpu_030_ec_cache_clear_unit
        Port (
            CLK                 : in    std_logic;
            RESET_N             : in    std_logic;
            cacr_ci             : in    std_logic;
            cacr_cd             : in    std_logic;
            cache_clearing      : out   std_logic;
            clear_idx           : out   integer range 0 to 255;
            clear_pulse         : out   std_logic
        );
    end component;

    component cpu_030_ec_cache_ctrl_fsm
        Port (
            CLK                 : in    std_logic;
            RESET_N             : in    std_logic;
            cpu_req             : in    std_logic;
            cpu_RW              : in    std_logic;
            cpu_is_code         : in    std_logic;
            cache_clearing      : in    std_logic;
            kickstart_select    : in    std_logic;
            cache_inhibit       : in    std_logic;
            icache_hit_s        : in    std_logic;
            dcache_hit_s        : in    std_logic;
            cacr_fi             : in    std_logic;
            cacr_fd             : in    std_logic;
            bridge_req          : out   std_logic;
            bridge_burst_en     : out   std_logic;
            bridge_ready        : in    std_logic;
            matrix_write_en     : out   std_logic;
            matrix_sel_code     : out   std_logic
        );
    end component;

	 begin

    -- =====================================================================
    -- ADRESSZERLEGUNG AM CORE-BUS (KALIBRIERT AUF 256 SETS)
    -- =====================================================================
    s_tag      <= cpu_A(31 downto 12);
    s_index    <= to_integer(unsigned(cpu_A(11 downto 4)));
    s_word_sel <= to_integer(unsigned(cpu_A(3 downto 2)));

    -- CHIP-RAM- UND ADRESS-DETEKTION (Befehl oder Datenraum)
    cache_inhibit    <= '1' when unsigned(cpu_A(31 downto 24)) = x"00" else '0';
    kickstart_select <= '1' when (cpu_A(31 downto 19) = "0000000011111100000") else '0';

    -- OPTIMIERUNG HEBEL 3: Rein kombinatorische, registerfreie BRAM-Treiberleitung [14.1]
    -- KORREKTUR PORT A: Leitet Kickstart-Bypass-Anfragen direkt auf Port A um!
    bram_a_addr   <= cpu_A(18 downto 2) & "00" when (cpu_req = '1' and kickstart_select = '1') else (others => '0');
    bram_a_we     <= '0';
    bram_a_data_w <= (others => '0');

    -- =====================================================================
    -- KOMBINAOTORISCHE HIT-EVALUATION FÜR DIE BEIDEN BÄNKE (0 WAIT-STATES)
    -- =====================================================================
    process(cpu_req, cpu_is_code, s_index, s_tag, icache_tags, icache_valid, 
            dcache_tags, dcache_valid, cache_inhibit, kickstart_select, cacr_ei, cacr_ed, s_cache_clearing)
    begin
        ihit_way     <= 0;
        dhit_way     <= 0;
        icache_hit_s <= '0';
        dcache_hit_s <= '0';

        if cpu_req = '1' and cache_inhibit = '0' and kickstart_select = '0' and s_cache_clearing = '0' then
            if cpu_is_code = '1' and cacr_ei = '1' then
                for way in 0 to 3 loop
                    if icache_valid(s_index)(way) = '1' and icache_tags(s_index)(way) = s_tag then
                        ihit_way     <= way;
                        icache_hit_s <= '1';
                    end if;
                end loop;
            end if;

            if cpu_is_code = '0' and cacr_ed = '1' then
                for way in 0 to 3 loop
                    if dcache_valid(s_index)(way) = '1' and dcache_tags(s_index)(way) = s_tag then
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
            ihit_way, dhit_way, bram_a_data_r)
    begin
        cache_hit  <= '0';
        cache_miss <= '0';
        cpu_D_out  <= (others => '0');

        if cpu_req = '1' then
            if kickstart_select = '1' then
                cache_hit <= '1';                    
                cpu_D_out <= bram_a_data_r; -- KORREKTUR: Zieht Daten fehlerfrei von Port A!         
            elsif cache_inhibit = '1' then
                cache_miss <= '1';                   
                cpu_D_out  <= (others => '0');
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
    -- STRUKTURELLE VERDRAHTUNG DER BEIDEN SPEICHER-SUBMODULE
    -- =====================================================================
    i_cache_clear : cpu_030_ec_cache_clear_unit
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            cacr_ci         => cacr_ci,
            cacr_cd         => cacr_cd,
            cache_clearing  => s_cache_clearing,
            clear_idx       => s_clear_idx,
            clear_pulse     => s_clear_pulse
        );

    i_cache_ctrl : cpu_030_ec_cache_ctrl_fsm
        port map (
            CLK              => CLK,
            RESET_N          => RESET_N,
            cpu_req          => cpu_req,
            cpu_RW           => cpu_RW,
            cpu_is_code      => cpu_is_code,
            cache_clearing   => s_cache_clearing,
            kickstart_select => kickstart_select,
            cache_inhibit    => cache_inhibit,
            icache_hit_s     => icache_hit_s,
            dcache_hit_s     => dcache_hit_s,
            cacr_fi          => cacr_fi,
            cacr_fd          => cacr_fd,
            bridge_req       => bridge_req,
            bridge_burst_en  => bridge_burst_en,
            bridge_ready     => bridge_ready,
            matrix_write_en  => s_matrix_write,
            matrix_sel_code  => s_matrix_sel_code
        );

    -- =====================================================================
    -- SYNCHRONER SCHREIBZUGRIFF AUF DIE DATEN- UND VALID-MATRIZEN (M10K)
    -- =====================================================================
    process(CLK, RESET_N)
        variable fill_way : integer range 0 to 3 := 0;
    begin
        if RESET_N = '0' then
            -- Initialisierung der Valid-Matrizen läuft via Clear-Unit-Impuls
            null;
        elsif rising_edge(CLK) then
            -- 1. SEQUENZIELLE LÖSCHUNG DER VALID-BITS VIA CLEAR_UNIT (M10K-SCHONUNG)
            if s_cache_clearing = '1' and s_clear_pulse = '1' then
                for way in 0 to 3 loop
                    icache_valid(s_clear_idx)(way) <= '0';
                    dcache_valid(s_clear_idx)(way) <= '0';
                end loop;
            end if;

            -- 2. REGULÄRE CORE-SCHREIB- UND LESEEINZÜGE BEI CACHE-OPERATIONEN
            if s_cache_clearing = '0' and cpu_req = '1' then
                if cpu_RW = '0' and cache_inhibit = '0' then
                    if dcache_hit_s = '1' and cacr_fd = '0' then
                        dcache_data(s_index)(dhit_way) <= cpu_D_in; -- Motorola Write-Through Hit-Update
                    end if;
                elsif cpu_RW = '1' and cache_inhibit = '0' then
                    if s_matrix_write = '1' then
                        fill_way := to_integer(unsigned(cpu_A(5 downto 4)));
                        
                        if s_matrix_sel_code = '1' then
                            -- KORREKTUR: Speist die echten Daten der DDR Fast-RAM Bridge ein!
                            icache_data(s_index)(fill_way)  <= bridge_data_r;
                            icache_tags(s_index)(fill_way)  <= s_tag;
                            icache_valid(s_index)(fill_way) <= '1';
                        else
                            -- KORREKTUR: Speist die echten Daten der DDR Fast-RAM Bridge ein!
                            dcache_data(s_index)(fill_way)  <= bridge_data_r;
                            dcache_tags(s_index)(fill_way)  <= s_tag;
                            dcache_valid(s_index)(fill_way) <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end structural;
