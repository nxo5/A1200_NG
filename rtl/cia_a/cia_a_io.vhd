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
        -- Die originalen 4 Adressbits werden direkt durchgereicht,
        -- um Verzögerungen in der Dekodierung zu verhindern!
        reg_addr      : in    std_logic_vector(31 downto 0); -- Ausrichtung auf den 32-Bit-Busrahmen
        chip_sel      : in    std_logic;                     -- Internes Aktivierungssignal (Aktiv '1')
        read_en       : in    std_logic;                     -- Lese-Anforderung der CPU
        write_en      : in    std_logic;                     -- Schreib-Anforderung der CPU
        
        -- Der chipinterne 8-Bit-Datenbus (Reine kombinatorische Kupferbahnen)
        data_in       : in    std_logic_vector(7 downto 0);  -- Daten von der CPU zum Register
        data_out      : out   std_logic_vector(7 downto 0);  -- Daten vom Register zur CPU
        
        -- =============================================================
        -- 3. AUSSENWELT: PHYSISCHE PORTS (Direkt durchgereicht zur Chip-Entity)
        -- =============================================================
        cia_port_a    : inout std_logic_vector(7 downto 0);  -- Mausknöpfe, Joy-Feuer
        cia_port_b    : inout std_logic_vector(7 downto 0)   -- Disketten-Laufwerkssteuerung
    );
end cia_a_io;

architecture Behavioral of cia_a_io is

    -- Hier werden wir im nächsten Schritt das Datenrichtungsregister A (DDRA),
    -- das Datenrichtungsregister B (DDRB) sowie die Tristate-Ausgangstreiber
    -- für die physischen Pins im 114-MHz-Raster implementieren.

begin

    -- Standardmäßig treiben wir den internen Bus im Leerlauf nicht an
    data_out <= (others => '0');

end Behavioral;
