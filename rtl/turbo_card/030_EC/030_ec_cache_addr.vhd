-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_cache_addr.vhd
-- Funktion: Der isolierte Hardware-Adress-Multiplexer (Mux) des 68EC030.
--           Schaltet die 19-Bit BRAM-Zieladressen für den Cache-Zugriff
--           und den 16-Byte-Burst-Einzug fehlerfrei durch.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_cache_addr is
    Port (
        -- Adress-Eingänge von der CPU und dem internen Basis-Register
        cpu_A               : in  std_logic_vector(31 downto 0);  -- Gesuchte CPU-Adresse
        internal_bram_addr  : in  unsigned(18 downto 0);         -- Gespeicherte Zeilen-Basisadresse
        
        -- Steuersignale vom Haupt-Controller
        burst_counter       : in  unsigned(1 downto 0);           -- Aktueller Burst-Schritt (00 bis 11)
        use_burst_addr      : in  std_logic;                      -- '1' = Nutze Burst-Adresse, '0' = Normaler Hit-Pfad
        cpu_is_code         : in  std_logic;                      -- '1' = Instruction-Cache, '0' = Data-Cache

        -- Physikalische Ausgangsleitung direkt an Port B des FPGA-BRAMs
        bram_b_addr         : out std_logic_vector(18 downto 0)   -- Die unmissverständliche 19-Bit-Adresse
    );
end cpu_030_ec_cache_addr;

architecture behavioral of cpu_030_ec_cache_addr is

    -- Festgelegte BRAM-Basis-Präfixe als starre Bit-Vektoren (Exakte Hardware-Verdrahtung)
    constant I_CACHE_PREFIX : std_logic_vector(2 downto 0) := "100"; -- Block ab 0x80000
    constant D_CACHE_PREFIX : std_logic_vector(2 downto 0) := "101"; -- Block ab 0x90000

begin

    -- =====================================================================
    -- KOMBINAOTORISCHES BIT-MUTIPLEXING (REINES HARDWARE-ROUTING)
    -- =====================================================================
    process(cpu_A, internal_bram_addr, burst_counter, use_burst_addr, cpu_is_code)
        variable normal_hit_addr : std_logic_vector(18 downto 0);
        variable burst_fill_addr : std_logic_vector(18 downto 0);
    begin
        
        -- 1. PFAD: NORMALE TREFFER-ADRESSE (DIREKTE VERDRAHTUNG DER CPU-PINS)
        -- Setzt sich starr zusammen aus: 3-Bit Cache-Präfix & 14-Bit Wortadresse & 2-Bit Nullen = 19 Bits.
        if cpu_is_code = '1' then
            normal_hit_addr := I_CACHE_PREFIX & cpu_A(15 downto 2) & "00";
        else
            normal_hit_addr := D_CACHE_PREFIX & cpu_A(15 downto 2) & "00";
        end if;

        -- 2. PFAD: BURST-NACHLADE-ADRESSE (REINES BIT-INJEKTIEREN OHNE ARITHMETIK)
        -- Nimmt die oberen 17 Bits der geladenen Zeilenbasis und injiziert den burst_counter in die Bits 3 und 2.
        burst_fill_addr := std_logic_vector(internal_bram_addr(18 downto 4)) & std_logic_vector(burst_counter) & "00";

        -- 3. WEICHE: AUSGABE AN DAS BRAM-INTERFACE ENTSCHEIDEN
        if use_burst_addr = '1' then
            bram_b_addr <= burst_fill_addr;
        else
            bram_b_addr <= normal_hit_addr;
        end if;

    end process;

end behavioral;
