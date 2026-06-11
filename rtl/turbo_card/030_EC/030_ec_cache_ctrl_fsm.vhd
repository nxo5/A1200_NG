-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_ctrl_fsm.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle)
-- Funktion: Sub-Modul des L1-Caches. Verwaltet exklusiv das reguläre
--           Cache-Betriebsmanagement (Kickstart-Express, Write-Through-Ausstoß
--           und Burst-Zeilenreparaturen bei L1-Misses).
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_ctrl_fsm is
    Port (
        -- Globale Systemsynchronisation
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Core-Schnittstellen (Eingänge für die Protokollüberwachung)
        cpu_req             : in    std_logic;
        cpu_RW              : in    std_logic;
        cpu_is_code         : in    std_logic;
        cache_clearing      : in    std_logic;                      -- Sperre von der Clear-Unit
        kickstart_select    : in    std_logic;                      -- Indikator für ROM-Expresskanal
        cache_inhibit       : in    std_logic;                      -- Indikator für Amiga-Chipsatzraum

        -- Hit/Miss-Statussignale von der Matrix
        icache_hit_s        : in    std_logic;
        dcache_hit_s        : in    std_logic;

        -- Kontrollkanäle aus dem CACR-Register
        cacr_fi             : in    std_logic;                      -- Freeze Instruction Cache
        cacr_fd             : in    std_logic;                      -- Freeze Data Cache

        -- Externe Schnittstellen nach außen zur Turbokarten-Bridge
        bridge_req          : out   std_logic;
        bridge_burst_en     : out   std_logic;
        bridge_ready        : in    std_logic;

        -- Interne Steuerimpulse an die Haupt-Cachenetze (Schreibfreigaben)
        matrix_write_en     : out   std_logic;                      -- Trigger zum Speichern des neuen Worts
        matrix_sel_code     : out   std_logic                       -- '1' = Instruction-Matrix, '0' = Data-Matrix
    );
end cpu_030_ec_cache_ctrl_fsm;

architecture behavioral of cpu_030_ec_cache_ctrl_fsm is

    type cache_fsm_type is (ST_IDLE, ST_WRITE_THROUGH, ST_BURST_FILL, ST_WAIT_BRIDGE);
    signal current_state : cache_fsm_type := ST_IDLE;

begin

    -- =====================================================================
    -- TAKTGESTEUERTE CACHE-BETRIEBS- UND BURST-ZUSTANDSMASCHINE
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            current_state   <= ST_IDLE;
            bridge_req      <= '0';
            bridge_burst_en <= '0';
            matrix_write_en <= '0';
            matrix_sel_code <= '0';

        elsif rising_edge(CLK) then
            -- Standard-Impulse vorab zurücksetzen
            matrix_write_en <= '0';
            matrix_sel_code <= '0';
            bridge_req      <= '0';
            bridge_burst_en <= '0';

            -- Das Betriebsmanagement greift nur außerhalb des Löschzyklus
            if cache_clearing = '0' then
                case current_state is

                    when ST_IDLE =>
                        if cpu_req = '1' then
                            -- SCHACHZUG 1: Kickstart-ROM-Expresskanal (Bypass)
                            if kickstart_select = '1' then
                                current_state <= ST_IDLE; -- Verbleibe im Idle, Direktzugriff über Port B

                            -- SCHACHZUG 2: Amiga-Chipsatzraum (Cache Inhibit aktiv)
                            elsif cache_inhibit = '1' then
                                bridge_req    <= '1';
                                current_state <= ST_WAIT_BRIDGE;

                            -- SCHACHZUG 3: Coreschreibaustritt (Native Write-Through Logik)
                            elsif cpu_RW = '0' then
                                bridge_req    <= '1';
                                current_state <= ST_WRITE_THROUGH;

                            -- SCHACHZUG 4: Core liest Daten oder Befehle (L1-Miss-Reparatur)
                            elsif cpu_RW = '1' then
                                if (cpu_is_code = '1' and icache_hit_s = '0') or 
                                   (cpu_is_code = '0' and dcache_hit_s = '0') then
                                    bridge_req      <= '1';
                                    bridge_burst_en <= '1'; -- Burst-Anforderung zünden
                                    current_state   <= ST_BURST_FILL;
                                end if;
                            end if;
                        end if;

                    -- =====================================================
                    -- ST_WRITE_THROUGH: SCHREIBAUSTOSS AN DIE PLATINE
                    -- =====================================================
                    when ST_WRITE_THROUGH =>
                        bridge_req <= '1';
                        if bridge_ready = '1' then
                            current_state <= ST_IDLE;
                        end if;

                    -- =====================================================
                    -- ST_BURST_FILL: ZEILENREPARATUR BEI CACHE-MISS
                    -- =====================================================
                    when ST_BURST_FILL =>
                        bridge_req      <= '1';
                        bridge_burst_en <= '1';

                        if bridge_ready = '1' then
                            -- Falls die jeweilige Bank nicht eingefroren (Freeze) ist, schreiben
                            if cpu_is_code = '1' and cacr_fi = '0' then
                                matrix_write_en <= '1';
                                matrix_sel_code <= '1'; -- Instruction Matrix auswählen
                            elsif cpu_is_code = '0' and cacr_fd = '0' then
                                matrix_write_en <= '1';
                                matrix_sel_code <= '0'; -- Data Matrix auswählen
                            end if;
                            
                            current_state <= ST_IDLE;
                        end if;

                    -- =====================================================
                    -- ST_WAIT_BRIDGE: DIREKTZUGRIFFE OHNE L1-CACHING
                    -- =====================================================
                    when ST_WAIT_BRIDGE =>
                        bridge_req <= '1';
                        if bridge_ready = '1' then
                            current_state <= ST_IDLE;
                        end if;

                    when others =>
                        current_state <= ST_IDLE;
                end case;
            end if;
        end if;
    end process;

end behavioral;
