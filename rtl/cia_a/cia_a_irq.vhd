-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_a_irq.vhd
-- Funktion: Die Interrupt-Zentrale (ICR) des Complex Interface Adapters A.
--           Verwaltet das ICR-Register ($D) für Timer und serielle Alarme.
-- IMPLEMENTIERUNG SCHRITT 4:
--   - Native ICR-Status- und Maskierungssteuerung ($D) integriert. [14.1]
--   - Amiga-konforme SET/CLR-Schreiblogik über Bit 7 für die Interruptmaske. [14.1]
--   - Autonomer Clear-on-Read Mechanismus löscht den Status beim Auslesen. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_a_irq is
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
        cia_irq_n     : out   std_logic  -- Zentraler Interrupt-Ausgang (Aktiv Low '0')
    );
end cia_a_irq;

architecture Behavioral of cia_a_irq is

    -- Das originale Amiga Interrupt-Anforderungsregister (Status)
    -- Bit 7: IR_SET (Irgendein freigegebener Interrupt steht an)
    -- Bit 2: Serial IRQ Status, Bit 1: Timer B Status, Bit 0: Timer A Status
    signal reg_icr_status : std_logic_vector(7 downto 0) := (others => '0');

    -- Das originale Amiga Interrupt-Maskenregister (Scharfschaltung)
    -- Bit mappt exakt auf das dazugehörige Status-Bit
    signal reg_icr_mask   : std_logic_vector(7 downto 0) := (others => '0');

    -- Synchroner Registerpuffer für den Bus-Lesepfad
    signal reg_data_out_sync : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Den getakteten Lese-Puffer permanent an den Gehäusebus melden
    data_out <= reg_data_out_sync;

    -- =========================================================================
    -- CENTRAL INTERRUPT GENERATION (Zentraler Alarm-Ausgang) [14.1]
    -- =========================================================================
    -- Ein Interrupt geht aktiv auf Masse ('0'), wenn irgendeine Anforderung aktiv ist
    -- UND dieses Bit zeitgleich im Maskenregister freigegeben wurde [14.1].
    cia_irq_n <= '0' when ((reg_icr_status(0) = '1' and reg_icr_mask(0) = '1') or  -- Timer A
                           (reg_icr_status(1) = '1' and reg_icr_mask(1) = '1') or  -- Timer B
                           (reg_icr_status(2) = '1' and reg_icr_mask(2) = '1'))    -- Serial Port
                 else '1';

    -- =========================================================================
    -- TAKTFLANKENSYNCHRONES ALARM-STEUERWERK UND BUS-INTERFACE
    -- =========================================================================
    process(clk_sys, reset)
    begin
        if reset = '1' then
            reg_icr_status    <= (others => '0');
            reg_icr_mask      <= (others => '0');
            reg_data_out_sync <= (others => '0');
        elsif rising_edge(clk_sys) then
            
            -- Standard-Lesepfad im Leerlauf nullen
            reg_data_out_sync <= (others => '0');

            -- 1. HARDWARE-AUTOMATISMUS: Eintreffende Alarm-Flanken einfangen [14.1]
            if timer_a_irq = '1' then reg_icr_status(0) <= '1'; end if;
            if timer_b_irq = '1' then reg_icr_status(1) <= '1'; end if;
            if serial_irq  = '1' then reg_icr_status(2) <= '1'; end if;

            -- 2. DYNAMISCHE MATRIX-ZUSAMMENFASSUNG (Das globale IR_SET Bit 7) [14.1]
            if ((reg_icr_status(0) = '1' and reg_icr_mask(0) = '1') or
                (reg_icr_status(1) = '1' and reg_icr_mask(1) = '1') or
                (reg_icr_status(2) = '1' and reg_icr_mask(2) = '1')) then
                reg_icr_status(7) <= '1'; -- Signalisiert der CPU das Bestehen eines aktiven IRQs
            else
                reg_icr_status(7) <= '0';
            end if;

            -- 3. BUS-SCHREIBZUGRIFFE DER CPU (Synchron zum E-Clock Timing) [14.1]
            if chip_sel = '1' and write_en = '1' and e_clock_ce = '1' then
                if reg_addr(3 downto 0) = x"D" then
                    -- AMIGA SET/CLR MECHANISMUS: 
                    -- Ist Bit 7 der CPU-Schreibdaten '1', werden alle geschriebenen '1'en in die Maske ÜBERNOMMEN (Set) [14.1].
                    -- Ist Bit 7 der CPU-Schreibdaten '0', werden alle geschriebenen '1'en aus der Maske GELÖSCHT (Clear) [14.1].
                    for i in 0 to 4 loop
                        if data_in(i) = '1' then
                            reg_icr_mask(i) <= data_in(7); 
                        end if;
                    end loop;
                end if;
            end if;

            -- 4. BUS-LESEZUGRIFFE DER CPU WITH AUTOMATIC CLEAR-ON-READ [14.1]
            if chip_sel = '1' and read_en = '1' then
                if reg_addr(3 downto 0) = x"D" then
                    -- Das Auslesen liefert den aktuellen Anforderungsstatus inklusive Bit 7 [14.1]
                    reg_data_out_sync <= reg_icr_status;
                    
                    -- NATIVE REPARATUR: Der unbestechliche Clear-on-Read Hardware-Automatismus!
                    -- Im exakten Moment des Auslesens werden die Statusbits sofort gelöscht [14.1].
                    reg_icr_status(0) <= '0';
                    reg_icr_status(1) <= '0';
                    reg_icr_status(2) <= '0';
                    reg_icr_status(7) <= '0';
                end if;
            end if;

        end if;
    end process;

end Behavioral;
