library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_a_serial is
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
        -- Direkte Adressierung für verzögerungsfreie Register-Auswahl
        reg_addr      : in    std_logic_vector(31 downto 0); -- Ausrichtung auf den 32-Bit-Busrahmen
        chip_sel      : in    std_logic;                     -- Internes Aktivierungssignal (Aktiv '1')
        read_en       : in    std_logic;                     -- Lese-Anforderung der CPU
        write_en      : in    std_logic;                     -- Schreib-Anforderung der CPU
        
        -- Der chipinterne 8-Bit-Datenbus (Kombinatorische Verbindungen)
        data_in       : in    std_logic_vector(7 downto 0);  -- Daten von der CPU zum Schieberegister
        data_out      : out   std_logic_vector(7 downto 0);  -- Daten vom Schieberegister zur CPU
        
        -- =============================================================
        -- 3. INTERNER ALARM-AUSGANG ZUM CIA-INTERRUPTMODUL
        -- =============================================================
        -- Feuert, wenn ein Byte vollständig ein- oder ausgelesen wurde
        serial_irq    : out   std_logic; -- Impuls bei vollem/leerem Schieberegister
        
        -- =============================================================
        -- 4. AUSSENWELT: PHYSISCHE SCHALTPINS (Direkt zur Chip-Entity)
        -- =============================================================
        -- Die originalen Hardware-Leitungen für den Amiga-Tastaturbus
        cia_cnt       : in    std_logic; -- Taktleitung der Tastatur (Keyboard Clock)
        cia_sp        : inout std_logic  -- Datenleitung der Tastatur (Keyboard Data)
    );
end cia_a_serial;

architecture Behavioral of cia_a_serial is

    -- Hier werden wir im nächsten Schritt das 8-Bit-Seriendatenregister (SDR),
    -- die Bit-Abzähler sowie die bidirektionale Tristate-Logik für den SP-Pin
    -- flach und taktgenau implementieren.

begin

    -- Standardmäßig treiben wir den internen Bus im Leerlauf nicht an
    data_out   <= (others => '0');
    
    -- Der Alarm-Impuls im inaktiven Zustand auf Null halten
    serial_irq <= '0';

end Behavioral;
