library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_a_timer is
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
        data_in       : in    std_logic_vector(7 downto 0);  -- Daten von der CPU zum Timer
        data_out      : out   std_logic_vector(7 downto 0);  -- Daten vom Timer zur CPU
        
        -- =============================================================
        -- 3. INTERNE ALARM-AUSGÄNGE ZUM CIA-INTERRUPTMODUL
        -- =============================================================
        -- Diese Signale feuern im Moment des Unterlaufs (Aktiv für 1 Takt '1')
        timer_a_irq   : out   std_logic; -- Impuls bei Unterlauf von Timer A
        timer_b_irq   : out   std_logic; -- Impuls bei Unterlauf von Timer B
        
        -- =============================================================
        -- 4. AUSSENWELT: PHYSISCHE SCHALTPINS (Direkt zur Chip-Entity)
        -- =============================================================
        -- Im Original für externe Signal-Pulsung oder Umschaltungen genutzt
        cia_tod       : in    std_logic; -- Time of Day Netztakt-Eingang
        cia_cnt       : in    std_logic  -- Manueller Zähl-Eingang für Timer B
    );
end cia_a_timer;

architecture Behavioral of cia_a_timer is

    -- Hier werden wir im nächsten Schritt die vier 8-Bit-Zählerregister,
    -- die vier 8-Bit-Latchregister sowie die beiden Kontrollregister
    -- CRA (Timer A) und CRB (Timer B) flach und taktgenau implementieren.

begin

    -- Standardmäßig treiben wir den internen Bus im Leerlauf nicht an
    data_out    <= (others => '0');
    
    -- Die Alarm-Impulse im inaktiven Zustand auf Null halten
    timer_a_irq <= '0';
    timer_b_irq <= '0';

end Behavioral;
