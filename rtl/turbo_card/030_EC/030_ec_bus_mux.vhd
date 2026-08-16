-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_bus_mux.vhd
-- Teil:    1 von 2 (Vollständige Entity-Schnittstelle)
-- Funktion: Der physikalische Signal-Multiplexer und Bus-Wähler der BIU.
--           SCHRITT 2 SANIERUNG:
--           - Eiserne Tristate-Verriegelung des Datenbus im Lesebetrieb!
--           - Verhindert Bus-Kollisionen gegen die 114-MHz-SDRAM-Bridge.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_bus_mux is
    Port (
        -- Kontrollkanäle von der soeben sanierten Bus-Zustandsmaschine
        fsm_tristate_en     : in    std_logic;                      -- '1' erzwingt globale Hochohmigkeit
        fsm_strobe_en       : in    std_logic;                      -- Steuert die AS_N Aktivierung
        fsm_ds_en           : in    std_logic;                      -- Steuert die DS_N Taktung
        fsm_write_en        : in    std_logic;                      -- '1' = Schreibzyklus, '0' = Lesezyklus
        fsm_burst_cnt       : in    std_logic_vector(1 downto 0);   -- Aktueller Burst-Offset
        fsm_sizing_offset   : in    std_logic_vector(1 downto 0);   -- Aktueller Sizing-Adress-Offset
        fsm_irq_level       : in    std_logic_vector(2 downto 0);   -- Einzuschleifender Interrupt-Level bei IACK
        
        -- Interne Signalbahnen aus dem Core-Haupthaus
        internal_A          : in    std_logic_vector(31 downto 0);  -- Ursprungadresse des Fließbands
        internal_D_out      : in    std_logic_vector(31 downto 0);  -- Auszugebende Schreibdaten des Sizers
        cycle_size          : in    std_logic_vector(1 downto 0);   -- Geforderte Breite (00=L, 01=B, 10=W)
        cycle_type          : in    std_logic_vector(2 downto 0);   -- Funktionscode (Befehl/Daten/CPU-Space)

        -- Physikalische Ausgangs-Pins zur Außenhaut der Turbokarte
        ext_A               : out   std_logic_vector(31 downto 0);  
        ext_D_out           : out   std_logic_vector(31 downto 0);  -- Bidirektionaler Datenpfad (Ausgangs-Spur)
        ext_AS_N            : out   std_logic;                      
        ext_DS_N            : out   std_logic;                      
        ext_RW              : out   std_logic;                      
        ext_SIZ             : out   std_logic_vector(1 downto 0);   
        ext_FC              : out   std_logic_vector(2 downto 0)    
    );
end cpu_030_ec_bus_mux;

architecture behavioral of cpu_030_ec_bus_mux is
    signal reg_addr_offset : unsigned(31 downto 0);
begin

    -- =====================================================================
    -- 1. PHYSIKALISCHE ADRESS- UND FUNKTIONSCODE-AUSGABE (0 WAIT-STATES)
    -- =====================================================================
    -- Berechnet im Flug den Adress-Vorschub für Sizing- und Burst-Sequenzen
    reg_addr_offset <= unsigned(internal_A) + 
                       unsigned(resize(unsigned(fsm_sizing_offset), 32)) + 
                       unsigned(resize(unsigned(fsm_burst_cnt) * 4, 32));

    -- Adressbus treiben: Bei IACK-Zyklen (Interrupt Acknowledge) wird der 
    -- Level laut Motorola-Standard in die Bits A3..A1 eingekoppelt [14.1].
    ext_A <= std_logic_vector(reg_addr_offset) when (cycle_type /= "111") else
             internal_A(31 downto 4) & fsm_irq_level & internal_A(0);

    -- Funktionscodes und Transferbreite unverzögert durchschleifen
    ext_FC  <= cycle_type;
    ext_SIZ <= cycle_size;

    -- =====================================================================
    -- 2. KORREKTUR: TRISTATE-STEUERUNG FÜR DEN AUSGANGS-DATENBUS
    -- =====================================================================
    -- REPARATUR: Greift nun unbestechlich auf das echte internal_D_out zu!
    -- Die Pins werden NUR bei einem echten Schreibbefehl aktiv gefüttert.
    ext_D_out <= internal_D_out when (fsm_tristate_en = '0' and fsm_write_en = '1') else 
                 (others => 'Z');

    -- Richtungssignal an die Außenwelt (1 = Lesen, 0 = Schreiben)
    ext_RW <= '0' when (fsm_write_en = '1') else '1';

    -- =====================================================================
    -- 3. TAKT- UND STROBE-AUSGABE (REINES SYSTEMTIEMING)
    -- =====================================================================
    -- Das Address Strobe (AS_N) wird exklusiv von der Bus-FSM freigegeben
    ext_AS_N <= '0' when (fsm_strobe_en = '1') else '1';

    -- Das Data Strobe (DS_N) atmet synchron im Takt der Sizing-Zustände
    ext_DS_N <= '0' when (fsm_ds_en = '1') else '1';

end behavioral;
