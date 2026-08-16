-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   fastram_bridge.vhd
-- Funktion: Die 256-MB Fast-RAM-Schnittstelle (DDR-RAM via Nano-Board).
--           - Schließt LÜCKENLOS an das 128-MB SDRAM-Modul ($08000000) an!
--           - Verwaltet den schnellen 16-Byte Cache-Line-Burst-Einzug.
--           - Liefert das STERM_N Quittungssignal an den 030-Core.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_fastram_bridge is
    Port (
        -- Globale Systemsynchronisation (Phasenstarr zur CPU)
        CLK             : in    std_logic;                      -- 56,56 MHz Haupttakt
        RESET_N         : in    std_logic;                      -- System-Reset

        -- =============================================================
        -- 1. KERN-SCHNITTSTELLE ZUM CPU-BUS (TURBOKARTE-INNEN)
        -- =============================================================
        cpu_A           : in    std_logic_vector(31 downto 0);  -- Wunschadresse des Kerns
        cpu_D_out       : in    std_logic_vector(31 downto 0);  -- CPU-Schreibdaten (ALU)
        cpu_D_in        : out   std_logic_vector(31 downto 0);  -- Puffer-Lesedaten an den Core
        cpu_AS_N        : in    std_logic;                      -- Address Strobe
        cpu_DS_N        : in    std_logic;                      -- Data Strobe
        cpu_RW          : in    std_logic;                      -- '1'=Read, '0'=Write
        
        -- Burst- und Kontrollbahnen vom sanierten L1-Cache-Subsystem
        cache_req       : in    std_logic;                      
        cache_burst_en  : in    std_logic;                      
        
        -- Synchrone Quittungsleitung zurück an das CPU-Gehäuse
        cpu_sterm_n     : out   std_logic;                      

        -- =============================================================
        -- 2. EXPRESS-INTERFACE ZUM SPEICHER-POOL (DDR-RAM)
        -- =============================================================
        ddr_req         : out   std_logic;                      -- Anforderung an Controller
        ddr_rnw         : out   std_logic;                      -- DDR Richtung (1=Read, 0=Write)
        ddr_addr        : out   std_logic_vector(25 downto 0);  -- 26-Bit Wortadresse für 256 MB
        ddr_data_w      : out   std_logic_vector(31 downto 0);  -- Schreibdaten an den DDR-Bus
        ddr_data_r      : in    std_logic_vector(31 downto 0);  -- Live-Lesedaten aus dem DDR
        ddr_ready       : in    std_logic;                      -- Controller meldet: Daten stabil
        ddr_burst_ack   : in    std_logic                       -- Controller bestätigt fortlaufenden Stream
    );
end cpu_030_fastram_bridge;

architecture behavioral of cpu_030_fastram_bridge is

    -- Zustandstypen für die DDR-Protokoll-FSM
    type bridge_state_type is (
        DDR_IDLE,           -- Warten auf CPU- oder Cache-Anforderung
        DDR_START_CYCLE,    -- Anforderung an DE10-Nano Controller absetzen
        DDR_WAIT_READY,     -- Warten auf die ddr_ready Quittung des Controllers
        DDR_BURST_STREAM,   -- Fortlaufender 4-Word-Einzug für den L1-Cache
        DDR_TERMINATE       -- cpu_sterm_n zünden und Zyklus sauber schließen
    );

    signal current_state   : bridge_state_type := DDR_IDLE;
    signal burst_cnt       : unsigned(1 downto 0) := "00";
    signal fastram_hit     : std_logic;

begin

    -- =====================================================================
    -- UNBESTECHLICHER ADRESS-DECODER: LÜCKENLOSE ANBINDUNG AN DAS SDRAM!
    -- =====================================================================
    -- fastram_hit zündet nahtlos ab $08000000 bis $17FFFFFF (256 MB DDR-Space).
    -- Der Bereich darunter ($00000000 bis $07FFFFFF = 128 MB) bleibt für Ihr SDRAM völlig frei!
    process(cpu_A)
        variable high_byte : unsigned(7 downto 0);
    begin
        high_byte := unsigned(cpu_A(31 downto 24));
        if (high_byte >= x"08") and (high_byte <= x"17") then
            fastram_hit <= '1';
        else
            fastram_hit <= '0';
        end if;
    end process;

    -- =====================================================================
    -- ZYKLUSTREUE FAST-RAM ABLAUF-STEUERUNG (FSM)
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            current_state   <= DDR_IDLE;
            cpu_sterm_n     <= '1';
            ddr_req         <= '0';
            ddr_rnw         <= '1';
            ddr_addr        <= (others => '0');
            ddr_data_w      <= (others => '0');
            cpu_D_in        <= (others => '0');
            burst_cnt       <= "00";
            
        elsif rising_edge(CLK) then
            cpu_sterm_n <= '1';
            ddr_req     <= '0';

            case current_state is

                when DDR_IDLE =>
                    burst_cnt <= "00";
                    if cpu_AS_N = '0' and fastram_hit = '1' then
                        ddr_addr      <= cpu_A(27 downto 2) & "00"; 
                        ddr_rnw       <= cpu_RW;
                        ddr_data_w    <= cpu_D_out;
                        ddr_req       <= '1';
                        current_state <= DDR_START_CYCLE;
                    end if;

                when DDR_START_CYCLE =>
                    ddr_req <= '1';
                    if ddr_ready = '1' then
                        if cache_burst_en = '1' and cpu_RW = '1' then
                            -- KORREKTUR: Richtigen Zielport cpu_D_in füttern!
                            cpu_D_in      <= ddr_data_r; 
                            current_state <= DDR_BURST_STREAM;
                        else
                            current_state <= DDR_TERMINATE;
                        end if;
                    else
                        current_state <= DDR_WAIT_READY;
                    end if;

                when DDR_WAIT_READY =>
                    ddr_req <= '1';
                    if ddr_ready = '1' then
                        cpu_D_in <= ddr_data_r;
                        if cache_burst_en = '1' and cpu_RW = '1' then
                            burst_cnt     <= "01";
                            current_state <= DDR_BURST_STREAM;
                        else
                            current_state <= DDR_TERMINATE;
                        end if;
                    end if;

                when DDR_BURST_STREAM =>
                    ddr_req <= '1';
                    if ddr_ready = '1' or ddr_burst_ack = '1' then
                        cpu_D_in <= ddr_data_r;
                        if burst_cnt = "11" then
                            current_state <= DDR_TERMINATE;
                        else
                            burst_cnt <= burst_cnt + 1;
                        end if;
                    end if;

                when DDR_TERMINATE =>
                    cpu_sterm_n <= '0'; -- Synchronous Termination Impuls zünden [14.1]
                    if cpu_AS_N = '1' then
                        current_state <= DDR_IDLE;
                    end if;

                when others =>
                    current_state <= DDR_IDLE;
            end case;
        end if;
    end process;

end behavioral;
