-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_a_io.vhd
-- Funktion: Das I/O-Portwerk des Complex Interface Adapters A (CIA-A).
--           Verwaltet die Parallelports PRA/PRB und Datenrichtung DDRA/DDRB.
-- IMPLEMENTIERUNG SCHRITT 1:
--   - Native 8-Bit DDR-Registersteuerung (DDRA=$2, DDRB=$3) integriert. [14.1]
--   - Taktgenaue Tristate-Ausgangstreiber für physische Pins im Systemtakt. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_a_io is
    Port (
        -- =============================================================
        -- 1. CLOCK, RESET UND TIMING-ENABLE
        -- =============================================================
        clk_sys       : in    std_logic; -- Der schnelle Basistakt des Gesamtsystems
        reset         : in    std_logic; -- Globaler System-Reset
        e_clock_ce    : in    std_logic; -- Das verlangsamte E-Clock Takt-Enable (~0,71 MHz)
        
        -- =============================================================
        -- 2. INTERNE STEUERBAHNEN ZUR CIA-HAUPTDATEI
        -- =============================================================
        reg_addr      : in    std_logic_vector(31 downto 0); -- Ausrichtung auf den 32-Bit-Busrahmen
        chip_sel      : in    std_logic;                     -- Internes Aktivierungssignal (Aktiv '1')
        read_en       : in    std_logic;                     -- Lese-Anforderung der CPU
        write_en      : in    std_logic;                     -- Schreib-Anforderung der CPU
        
        -- Der chipinterne 8-Bit-Datenbus
        data_in       : in    std_logic_vector(7 downto 0);  -- Daten von der CPU zum Register
        data_out      : out   std_logic_vector(7 downto 0);  -- Daten vom Register zur CPU
        
        -- =============================================================
        -- 3. AUSSENWELT: PHYSISCHE PORTS (Direkt zur Chip-Entity)
        -- =============================================================
        cia_port_a    : inout std_logic_vector(7 downto 0);  -- Mausknöpfe, Joy-Feuer
        cia_port_b    : inout std_logic_vector(7 downto 0)   -- Disketten-Laufwerkssteuerung
    );
end cia_a_io;

architecture Behavioral of cia_a_io is

    -- Echte, historische Amiga Hardware-Register
    signal reg_pra   : std_logic_vector(7 downto 0) := (others => '0'); -- Port A Daten
    signal reg_prb   : std_logic_vector(7 downto 0) := (others => '0'); -- Port B Daten
    signal reg_ddra  : std_logic_vector(7 downto 0) := (others => '0'); -- Datenrichtung A (1=Out, 0=In)
    signal reg_ddrb  : std_logic_vector(7 downto 0) := (others => '0'); -- Datenrichtung B (1=Out, 0=In)

    -- Synchrone Registerpuffer für den Bus-Lesepfad (Schutz vor Glitches)
    signal reg_data_out_sync : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Die getakteten Lesedaten permanent an den Gehäusebus melden
    data_out <= reg_data_out_sync;

    -- =========================================================================
    -- 1. PHYSIKALISCHE TRISTATE-TREIBER FÜR DIE AUSSENWELT-PINS [14.1]
    -- =========================================================================
    -- Wenn das DDR-Bit gelöscht ist ('0'), schaltet der FPGA-Pin auf Hochohmig ('Z'),
    -- damit externe Signale (z.B. der Feuerknopf) fehlerfrei eingelesen werden können [14.1].
    gen_tristate_io: for i in 0 to 7 generate
    begin
        cia_port_a(i) <= reg_pra(i) when reg_ddra(i) = '1' else 'Z';
        cia_port_b(i) <= reg_prb(i) when reg_ddrb(i) = '1' else 'Z';
    end generate;

    -- =========================================================================
    -- 2. TAFKTFLANKENSYNCHRONER RECHENSCHRITT (Schreiben und Lesen)
    -- =========================================================================
    process(clk_sys, reset)
    begin
        if reset = '1' then
            reg_pra           <= (others => '0');
            reg_prb           <= (others => '0');
            reg_ddra          <= (others => '0');
            reg_ddrb          <= (others => '0');
            reg_data_out_sync <= (others => '0');
        elsif rising_edge(clk_sys) then
            
            -- Standard-Lesepfad im Leerlauf nullen
            reg_data_out_sync <= (others => '0');

            -- BUS-SCHREIBZUGRIFFE (Synchron zum verlangsamten E-Clock Taktgitter) [14.1]
            if chip_sel = '1' and write_en = '1' and e_clock_ce = '1' then
                case reg_addr(3 downto 0) is
                    when x"0" => reg_pra  <= data_in; -- $PRA ($DFF000-Offset) [14.1]
                    when x"1" => reg_prb  <= data_in; -- $PRB [14.1]
                    when x"2" => reg_ddra <= data_in; -- $DDRA [14.1]
                    when x"3" => reg_ddrb <= data_in; -- $DDRB [14.1]
                    when others => null;
                end case;
            end if;

            -- BUS-LESEZUGRIFFE (CPU holt Daten ab) [14.1]
            if chip_sel = '1' and read_en = '1' then
                case reg_addr(3 downto 0) is
                    -- Beim Lesen eines Ports liefert die Hardware den aktuellen Live-Zustand 
                    -- der physischen Leitungen (Eingangspins spiegeln), nicht den Inhalt von reg_pra! [14.1]
                    when x"0" => reg_data_out_sync <= cia_port_a;
                    when x"1" => reg_data_out_sync <= cia_port_b;
                    when x"2" => reg_data_out_sync <= reg_ddra;
                    when x"3" => reg_data_out_sync <= reg_ddrb;
                    when others => reg_data_out_sync <= (others => '0');
                end case;
            end if;

        end if;
    end process;

end Behavioral;
