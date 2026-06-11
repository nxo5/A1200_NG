-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_bus_mux.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle des Bus-Multiplexers)
-- Funktion: Der kombinatorische Daten-, Adress- und Kontrollbus-Muxer.
--           PUNKT 2: Trennung von AS_N und DS_N! Der Pin ext_DS_N wird nun
--                    unbestechlich vom atmenden FSM-Register gesteuert, um
--                    die Motorola-Hold-Times am Mainboard zu garantieren!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_bus_mux is
    Port (
        -- Kontrollleitungen aus der übergeordneten Bus-FSM
        fsm_tristate_en     : in    std_logic;                      -- '1' = Alle Ausgänge auf Tri-State ('Z')
        fsm_strobe_en       : in    std_logic;                      -- Schaltet den Adress-Strobe AS_N frei
        fsm_ds_en           : in    std_logic;                      -- NEU PUNKT 2: Schaltet das Daten-Strobe DS_N frei
        fsm_write_en        : in    std_logic;                      -- Richtungssteuerung für RW-Pin
        fsm_burst_cnt       : in    std_logic_vector(1 downto 0);   -- Burst-Zählerstand zur Cachezeilen-Modulation
        fsm_sizing_offset   : in    std_logic_vector(1 downto 0);   -- Sizing-Offset zur Adress-Inkrementierung
        fsm_irq_level       : in    std_logic_vector(2 downto 0);   -- Quittierter Prioritätslevel für CPU-Space
        
        -- Interne Signalbahnen aus dem Core
        internal_A          : in    std_logic_vector(31 downto 0);  -- Vom Core generierte Basisadresse
        internal_D_out      : in    std_logic_vector(31 downto 0);  -- Vom Core generierte Schreibdaten
        cycle_size          : in    std_logic_vector(1 downto 0);   -- Transfergröße (00=B, 01=W, 10=L)
        cycle_type          : in    std_logic_vector(2 downto 0);   -- Funktionscodes (FC2-FC0, "111"=CPU-Space)
        
        -- Externe Signalbahnen zu den physischen Gehäuse-Pins (Turbokarte)
        ext_A               : out   std_logic_vector(31 downto 0);  -- Adressbus-Ausgangpins
        ext_D_out           : out   std_logic_vector(31 downto 0);  -- Datenbus-Schreibaustrittspins
        ext_AS_N            : out   std_logic;                      -- Address Strobe Pin (Bleibt starr bei Sizing)
        ext_DS_N            : out   std_logic;                      -- Data Strobe Pin (Atmet rhythmisch bei Sizing)
        ext_RW              : out   std_logic;                      -- Read/Write-Pin
        ext_SIZ             : out   std_logic_vector(1 downto 0);   -- SIZ1/SIZ0 Ausgangspins
        ext_FC              : out   std_logic_vector(2 downto 0)    -- FC2-FC0 Funktionscodepins
    );
end cpu_030_ec_bus_mux;

architecture behavioral of cpu_030_ec_bus_mux is

begin

    -- =====================================================================
    -- REINE KOMBINATORISCHE MUTIPLEXER-TREIBERMATIX (0 WAIT-STATES)
    -- Trennt Address Strobe (AS) und Data Strobe (DS) für perfektes Timing!
    -- =====================================================================
    process(fsm_tristate_en, fsm_strobe_en, fsm_ds_en, fsm_write_en, fsm_burst_cnt, 
            fsm_sizing_offset, fsm_irq_level, internal_A, internal_D_out, 
            cycle_size, cycle_type)
        variable base_addr_u   : unsigned(31 downto 0);
        variable total_offset  : unsigned(31 downto 0);
        variable modulated_A   : std_logic_vector(31 downto 0);
    begin
        -- Basisadresse aus dem Core laden
        base_addr_u  := unsigned(internal_A);
        total_offset := (others => '0');
        
        -- A: INTERNER VORSCHUB FÜR L1-CACHE-BURSTING (A3..A2)
        if fsm_burst_cnt = "01" then
            total_offset := total_offset + x"00000004"; -- +4 Bytes
        elsif fsm_burst_cnt = "10" then
            total_offset := total_offset + x"00000008"; -- +8 Bytes
        elsif fsm_burst_cnt = "11" then
            total_offset := total_offset + x"0000000C"; -- +12 Bytes
        end if;
        
        -- B: PHYSISCHER VORSCHUB FÜR DYNAMIC BUS SIZING (A1..A0)
        if fsm_sizing_offset = "01" then
            total_offset := total_offset + x"00000001"; -- +1 Byte (8-Bit Bus)
        elsif fsm_sizing_offset = "10" then
            total_offset := total_offset + x"00000002"; -- +2 Bytes (16/8-Bit Bus)
        elsif fsm_sizing_offset = "11" then
            total_offset := total_offset + x"00000003"; -- +3 Bytes (8-Bit Bus)
        end if;
        
        -- Gesamtsumme der Adressmodulation bilden
        modulated_A := std_logic_vector(base_addr_u + total_offset);

        -- C: UNBESTECHLICHE CPU-SPACE-WEICHE (FC = "111")
        if cycle_type = "111" then
            modulated_A(31 downto 20) := (others => '1'); 
            modulated_A(19 downto 16) := "1111";         -- Typ-Indikator: Interrupt Ack!
            modulated_A(15 downto 4)  := (others => '0'); 
            modulated_A(3 downto 1)   := fsm_irq_level;   -- Quittierter Prioritätslevel
            modulated_A(0)            := '1';             
        end if;

        -- D: PHYSISCHE PINS MIT TRI-STATE-SICHERUNG AUSGEBEN
        if fsm_tristate_en = '1' then
            ext_A        <= (others => 'Z');
            ext_D_out    <= (others => 'Z');
            ext_AS_N     <= 'Z';
            ext_DS_N     <= 'Z';
            ext_RW       <= 'Z';
            ext_SIZ      <= (others => 'Z');
            ext_FC       <= (others => 'Z');
            
        else
            ext_A     <= modulated_A;
            ext_D_out <= internal_D_out;
            ext_SIZ   <= cycle_size;
            ext_FC    <= cycle_type;
            
            if fsm_write_en = '1' then
                ext_RW <= '0'; -- Write
            else
                ext_RW <= '1'; -- Read
            end if;

            -- KORREKTUR PUNKT 2: Getrennte Ansteuerung der Strobe-Pins!
            if fsm_strobe_en = '1' then
                ext_AS_N <= '0'; -- Address Strobe bleibt starr aktiv ('0') bei Sizing
            else
                ext_AS_N <= '1'; 
            end if;

            if fsm_ds_en = '1' then
                ext_DS_N <= '0'; -- Data Strobe atmet rhythmisch im Takt der FSM-Pausen
            else
                ext_DS_N <= '1'; -- Geht in den Sizing-Zwischenphasen auf inaktiv ('1')
            end if;
            
        end if;
    end process;

end behavioral;
