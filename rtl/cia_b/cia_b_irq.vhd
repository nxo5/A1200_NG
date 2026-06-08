library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_b_irq is
    Port (
        -- =============================================================
        -- 1. CLOCK, RESET UND TIMING-ENABLE
        -- =============================================================
        clk_sys       : in    std_logic; -- Der schnelle Basistakt des Gesamtsystems
        reset         : in    std_logic; -- Globaler System-Reset
        e_clock_ce    : in    std_logic; -- Der verlangsamte E-Clock Takt-Enable (~0,71 MHz)
        
        -- =============================================================
        -- 2. INTERNE STEUERBAHNEN ZUR CIA-HAUPTDATEI
        -- =============================================================
        -- Direkte Adressierung für verzögerungsfreie Register-Auswahl
        reg_addr      : in    std_logic_vector(31 downto 0); -- Ausrichtung auf den 32-Bit-Busrahmen
        chip_sel      : in    std_logic;                     -- Internes Aktivierungssignal (Aktiv '1')
        read_en       : in    std_logic;                     -- Lese-Anforderung der CPU
        write_en      : in    std_logic;                     -- Schreib-Anforderung der CPU
        
        -- Der chipinterne 8-Bit-Datenbus (Kombinatorische Erfassung)
        data_in       : in    std_logic_vector(7 downto 0);  -- Daten von der CPU zur Maskierungs-Logik
        data_out      : out   std_logic_vector(7 downto 0);  -- Daten vom ICR-Status zur CPU
        
        -- =============================================================
        -- 3. INTERNE CHIP-ALARM-EINGÄNGE (Die Signal-Zubringer)
        -- =============================================================
        timer_a_irq   : in    std_logic; -- Signalisiert den Unterlauf von Timer A
        timer_b_irq   : in    std_logic; -- Signalisiert den Unterlauf von Timer B
        serial_irq    : in    std_logic; -- Signalisiert die Schieberegister-Meldung
        
        -- =============================================================
        -- 4. AUSGÄNGE ZUR PLATINE (Direkt zur Chip-Entity)
        -- =============================================================
        -- Das reale Interrupt-Signal, das an den Paula-Chip geht (Aktiv Low INT2)
        cia_irq_n     : out   std_logic  -- Zentraler Interrupt-Ausgang (Aktiv Low '0')
    );
end cia_b_irq;

architecture Behavioral of cia_b_irq is

    -- Hier werden wir im nächsten Schritt das 5-Bit-Statusschnittstellen-Register,
    -- die Interrupt-Maskenbit-Logik (Scharfschalten von Alarmen) und das
    -- automatische Rücksetzen (Clear-on-Read) flach und taktgenau implementieren.

begin

    -- Standardmäßig treiben wir den internen Bus im Leerlauf nicht an
    data_out  <= (others => '0');
    
    -- Das Ausgangssignal im inaktiven Zustand (Open-Drain-Simulation) auf '1' halten
    cia_irq_n <= '1';

end Behavioral;
