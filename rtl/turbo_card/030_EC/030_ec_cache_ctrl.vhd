-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_ctrl.vhd
-- Teil:    1 von 2 (Entity und Komponentendeklarationen)
-- Funktion: Das übergeordnete Haupt-Steuerwerk (Top-Unit) des Caches.
--           Instanziiert die Tag-Unit und den Adress-Muxer strukturell.
--           Verwaltet die reine, zyklustreue Motorola-Zustandsmaschine.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_ctrl is
    Port (
        -- Takt und System-Zustand
        CLK             : in    std_logic;
        RESET_N         : in    std_logic;

        -- Schnittstelle zur CPU
        cpu_A           : in    std_logic_vector(31 downto 0);  -- Gesuchte Adresse der CPU
        cpu_D_in        : in    std_logic_vector(31 downto 0);  -- Schreibdaten von der ALU
        cpu_D_out       : out   std_logic_vector(31 downto 0);  -- Lesedaten an die CPU
        cpu_RW          : in    std_logic;                      -- Lese-/Schreibrichtung (1=Read, 0=Write)
        cpu_req         : in    std_logic;                      -- CPU fordert Speicherzugriff an
        cpu_is_code     : in    std_logic;                      -- '1' = Befehlsabfrage, '0' = Daten

        -- Originale Motorola CACR-Steuerleitungen
        cacr_ei         : in    std_logic;                      -- Enable Instruction Cache
        cacr_fi         : in    std_logic;                      -- Freeze Instruction Cache
        cacr_ed         : in    std_logic;                      -- Enable Data Cache
        cacr_fd         : in    std_logic;                      -- Freeze Data Cache
        cacr_ci         : in    std_logic;                      -- Clear Instruction Cache
        cacr_cd         : in    std_logic;                      -- Clear Data Cache

        -- Physikalische Schnittstelle nach außen zum BRAM-Chip (Exklusiv Port B)
        bram_b_addr     : out   std_logic_vector(18 downto 0);  -- 19-Bit Adresse an das BRAM
        bram_b_data_w   : out   std_logic_vector(31 downto 0);  -- Schreibdaten an das BRAM
        bram_b_data_r   : in    std_logic_vector(31 downto 0);  -- Lesedaten aus dem BRAM
        bram_b_we       : out   std_logic;                      -- Schreib-Aktivierung an Port B

        -- Schnittstelle zur Fast-RAM-Bridge (DDR-RAM) bei einem Cache Miss
        bridge_req      : out   std_logic;                      -- Anforderung an DDR-Bridge
        bridge_burst_en : out   std_logic;                      -- Triggert den 16-Byte-Burst-Mode
        bridge_ready    : in    std_logic;                      -- Rückmeldung von DDR-Bridge: Daten bereit

        -- Status-Rückmeldung an das CPU-Steuerwerk
        cache_hit       : out   std_logic;                      -- '1' falls Daten direkt im BRAM liegen
        cache_miss      : out   std_logic                       -- '1' falls die Pipeline einfrieren muss
    );
end cpu_030_ec_cache_ctrl;

architecture structural of cpu_030_ec_cache_ctrl is

    -- =====================================================================
    -- KOMPONENTENDEKLARATIONEN DER BEIDEN NEUEN UNTERMODULE
    -- =====================================================================
    component cpu_030_ec_cache_tags
        Port (
            CLK             : in    std_logic; RESET_N : in std_logic;
            cpu_A           : in    std_logic_vector(31 downto 0); cpu_is_code : in std_logic;
            update_valid    : in    std_logic; update_tag : in std_logic;
            cacr_ci         : in    std_logic; cacr_cd : in std_logic;
            cacr_fi         : in    std_logic; cacr_fd : in std_logic;
            cache_hit       : out   std_logic
        );
    end component;

    component cpu_030_ec_cache_addr
        Port (
            cpu_A               : in  std_logic_vector(31 downto 0);
            internal_bram_addr  : in  unsigned(18 downto 0);
            burst_counter       : in  unsigned(1 downto 0);
            use_burst_addr      : in  std_logic;
            cpu_is_code         : in  std_logic;
            bram_b_addr         : out std_logic_vector(18 downto 0)
        );
    end component;

    -- Zustandstypen für die reine Ablaufsteuerung
    type cache_state_type is (
        CACHE_IDLE, CACHE_CHECK_HIT, CACHE_MISS_STALL, 
        CACHE_BURST_FILL, CACHE_UPDATE_TAGS, CACHE_RESUME
    );
    
    signal current_state : cache_state_type := CACHE_IDLE;

    -- Konstante BRAM-Basisbereiche für die interne Adresspufferung
    constant I_CACHE_BASE : unsigned(18 downto 0) := "1000000000000000000"; -- 0x80000
    constant D_CACHE_BASE : unsigned(18 downto 0) := "1001000000000000000"; -- 0x90000

    -- Interne Steuerdrähte zur Kapselung der Submodule
    signal internal_bram_addr : unsigned(18 downto 0) := (others => '0');
    signal burst_counter       : unsigned(1 downto 0) := "00";
    
    signal tag_update_valid    : std_logic := '0';
    signal tag_update_sig      : std_logic := '0';
    signal mux_use_burst       : std_logic := '0';
    signal sub_cache_hit       : std_logic;

begin

    -- Treffersignale an das CPU-Haupthaus spiegeln
    cache_hit <= sub_cache_hit;

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNG: DER SYNCHRONE TAG-SPEICHER
    -- =====================================================================
    i_cache_tags_ram : cpu_030_ec_cache_tags
        port map (
            CLK             => CLK,
            RESET_N         => RESET_N,
            cpu_A           => cpu_A,
            cpu_is_code     => cpu_is_code,
            update_valid    => tag_update_valid,
            update_tag      => tag_update_sig,
            cacr_ci         => cacr_ci,
            cacr_cd         => cacr_cd,
            cacr_fi         => cacr_fi,
            cacr_fd         => cacr_fd,
            cache_hit       => sub_cache_hit
        );

    -- =====================================================================
    -- STRUKTURELLE INSTANZIIERUNG: DER ISOLIERTE HARDWARE-ADRESS-MUXER
    -- =====================================================================
    i_cache_addr_routing : cpu_030_ec_cache_addr
        port map (
            cpu_A               => cpu_A,
            internal_bram_addr  => internal_bram_addr,
            burst_counter       => burst_counter,
            use_burst_addr      => mux_use_burst,
            cpu_is_code         => cpu_is_code,
            bram_b_addr         => bram_b_addr
        );

    -- =====================================================================
    -- SYNCHRONER PROZESS: REINE CACHE-ZUSTANDSMASCHINE (STEUERWERK)
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            current_state       <= CACHE_IDLE;
            bram_b_data_w       <= (others => '0');
            bram_b_we           <= '0';
            bridge_req          <= '0';
            bridge_burst_en     <= '0';
            cache_miss          <= '0';
            cpu_D_out           <= (others => '0');
            internal_bram_addr  <= (others => '0');
            burst_counter       <= "00";
            tag_update_valid    <= '0';
            tag_update_sig      <= '0';
            mux_use_burst       <= '0';
            
        elsif rising_edge(CLK) then
            -- Standardwerte für Steuerleitungen pro Takt zurücksetzen
            bram_b_we        <= '0';
            bridge_req       <= '0';
            bridge_burst_en  <= '0';
            tag_update_valid <= '0';
            tag_update_sig   <= '0';
            
            case current_state is
                
                when CACHE_IDLE =>
                    cache_miss    <= '0';
                    mux_use_burst <= '0';
                    
                    if cpu_req = '1' then
                        current_state <= CACHE_CHECK_HIT;
                    end if;
                    
                when CACHE_CHECK_HIT =>
                    -- Basisadresse im Puffer-Register für eventuelle Miss-Zyklen vorbereiten
                    -- KORREKTUR: Mathematisch sichere 32-Bit Integer Multiplikation vor dem Slice-Kürzen
                    if cpu_is_code = '1' then
                        internal_bram_addr <= I_CACHE_BASE + resize(unsigned(cpu_A(15 downto 2)) * 4, 19);
                    else
                        internal_bram_addr <= D_CACHE_BASE + resize(unsigned(cpu_A(15 downto 2)) * 4, 19);
                    end if;

                    -- Das kombinatorische Hit-Signal der ausgelagerten Tag-Unit abfragen
                    if sub_cache_hit = '1' then
                        current_state <= CACHE_RESUME;
                    else
                        current_state <= CACHE_MISS_STALL;
                    end if;
                    
                when CACHE_MISS_STALL =>
                    cache_miss <= '1';
                    bridge_req <= '1';
                    
                    if cpu_RW = '1' then
                        -- Lese-Miss: Schnellen 16-Byte Burst-Einzug vorbereiten
                        bridge_burst_en <= '1';
                        burst_counter   <= "00";
                        mux_use_burst   <= '1'; -- Adress-Muxer auf Burst-Pfad umschalten
                        current_state   <= CACHE_BURST_FILL;
                    else
                        -- MOTOROLA WRITE-THROUGH LOGIK FÜR SCHREIB-ZYKLEN:
                        bram_b_data_w <= cpu_D_in;
                        if cacr_fd = '0' then bram_b_we <= '1'; end if; -- Lokales BRAM mitschreiben
                        
                        if bridge_ready = '1' then
                            current_state <= CACHE_IDLE;
                        end if;
                    end if;
                    
                when CACHE_BURST_FILL =>
                    cache_miss    <= '1';
                    bridge_req    <= '1';
                    mux_use_burst <= '1';
                    
                    -- Taktgenauer Einzug der Longwords über Port B des BRAMs
                    if bridge_ready = '1' then
                        bram_b_we     <= '1';
                        bram_b_data_w <= bram_b_data_r; -- Nimmt die gelesenen RAM-Daten der Bridge entgegen
                        
                        if burst_counter = "11" then
                            current_state <= CACHE_UPDATE_TAGS;
                        else
                            burst_counter <= burst_counter + 1;
                        end if;
                    end if;
                    
                when CACHE_UPDATE_TAGS =>
                    cache_miss <= '1';
                    -- Impuls an die ausgelagerte Tag-Unit senden, um Valid-Bit und Tag einzurasten
                    tag_update_valid <= '1';
                    tag_update_sig   <= '1';
                    current_state    <= CACHE_RESUME;
                    
                when CACHE_RESUME =>
                    -- Daten stabil an die CPU übergeben und Pipeline freigeben
                    cpu_D_out     <= bram_b_data_r;
                    current_state <= CACHE_IDLE;
                    
                when others =>
                    current_state <= CACHE_IDLE;
            end case;
        end if;
    end process;

end structural;
