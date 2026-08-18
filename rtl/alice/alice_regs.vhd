-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   alice_regs.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle)
-- Funktion: Das Custom-Registerfeld und Interrupt-Management von ALICE.
-- KORREKTUR FULL-FIX:
--   - Vernichtet alle drei instabilen Latches (Warning 10631) restlos! [14.1]
--   - Trennt den CPU-Schreibpfad und den Blitter-Automatismus in reine, 
--     voneinander unabhängige synchrone Gatterblöcke auf. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice_regs is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der von alice_clk generierte 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. INTERNE SPEISEBAHNEN (EINGÄNGE VON DER ALICE-HAUPTDATEI)
        -- =============================================================
        internal_addr : in    std_logic_vector(11 downto 0); -- Custom-Register-Raum ($DFF000 bis $DFFFXX)
        internal_data_w: in   std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten von der CPU
        chip_sel      : in    std_logic;                     -- Aktivierungssignal für den Registerbereich
        read_en       : in    std_logic;                     -- Lese-Impuls
        write_en      : in    std_logic;                     -- Schreib-Impuls
        
        -- =============================================================
        -- 3. INTERNE SPEISEBAHNEN (AUSGÄNGE ZUR ALICE-HAUPTDATEI)
        -- =============================================================
        internal_data_r: out  std_logic_vector(31 downto 0); -- Synchronisierte Lesedaten zurück zur CPU
        
        -- =============================================================
        -- 4. INTERNE KONTROLL-REGISTER FÜR DIE ANDEREN ALICE-UNTERMODULE
        -- =============================================================
        dma_enable_reg: out   std_logic_vector(15 downto 0); -- Der Inhalt des DMACON-Registers
        int_enable_reg: out   std_logic_vector(15 downto 0); -- Der Inhalt des INTENA-Registers
        
        -- =============================================================
        -- 5. INTERNE CHIP-DATENZUBRINGER (EINGÄNGE VON ANDEREN UNTERMODULEN)
        -- =============================================================
        h_pos_tick    : in    unsigned(8 downto 0); -- Aktueller Videostrahl für Registerabfrage ($DFF004)
        v_pos_tick    : in    unsigned(8 downto 0); -- Aktuelle Videozeile für Registerabfrage ($DFF006)
        
        -- Status-Eingang vom Grafik-Beschleuniger
        blt_done      : in    std_logic                      -- '1' signalisiert, dass der Blitter fertig ist
    );
end alice_regs;

architecture Behavioral of alice_regs is

    -- Die originalen systemweiten Kontrollregister des Amigas
    signal reg_dmacon : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_intena : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_intreq : std_logic_vector(15 downto 0) := (others => '0'); 

    -- Synchroner Registerpuffer für den Bus-Lesepfad
    signal reg_data_out_sync : std_logic_vector(31 downto 0) := (others => '0');

    -- Pipeline-Register für die Koppelung der Blitter-Done-Flanke
    signal blt_done_r1        : std_logic := '1';
    signal blt_done_r2        : std_logic := '1';

begin

    -- Die Schalterstellungen permanent an die anderen internen Alice-Module weiterreichen
    dma_enable_reg <= reg_dmacon;
    int_enable_reg <= reg_intena;

    -- Physische Zuweisung des synchronisierten Puffers nach außen
    internal_data_r <= reg_data_out_sync;

    -- =================================================================
    -- 1. ORIGINAL AMIGA GATTER-LOGIK (KOMPROMISSLOS LATCH-FREI, 0% LOOPS)
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_dmacon  <= (others => '0');
            reg_intena  <= (others => '0');
            reg_intreq  <= (others => '0');
            blt_done_r1 <= '1';
            blt_done_r2 <= '1';
        elsif rising_edge(clk_amiga) then
            -- Flanken-Pipeline für den Blitter-Status fortschalten
            blt_done_r1 <= blt_done;
            blt_done_r2 <= blt_done_r1;

            -- HARDWARE-AUTOMATISMUS (Blitter-Interrupt) läuft permanent synchron mit!
            if blt_done_r1 = '1' and blt_done_r2 = '0' then
                reg_intreq(6) <= '1'; -- Bit 6: BLIT Interrupt anfordern!
            end if;

            -- PFAD A: CPU-SCHREIBZUGRIFFE ÜBER DIE NATIVE VEKTOR-MASKEN-LOGIK DES ORIGINAL-CHIPS
            if chip_sel = '1' and write_en = '1' then
                case internal_addr is
                    
                    -- DMACONW ($DFF096)
                    when x"096" =>
                        if internal_data_w(15) = '1' then
                            -- SET: Bestehende Bits behalten ODER neue CPU-Bits hinzusetzen (Bits 14..0)
                            reg_dmacon(14 downto 0) <= reg_dmacon(14 downto 0) or internal_data_w(14 downto 0);
                        else
                            -- CLEAR: Bestehende Bits behalten UND nur die CPU-Bits mit '1' ausknipsen (AND NOT)
                            reg_dmacon(14 downto 0) <= reg_dmacon(14 downto 0) and not internal_data_w(14 downto 0);
                        end if;
                        reg_dmacon(15) <= '0'; -- Bit 15 ist auf der Hardware ungenutzt / immer 0

                    -- INTENA ($DFF09A)
                    when x"09A" =>
                        if internal_data_w(15) = '1' then
                            reg_intena(14 downto 0) <= reg_intena(14 downto 0) or internal_data_w(14 downto 0);
                        else
                            reg_intena(14 downto 0) <= reg_intena(14 downto 0) and not internal_data_w(14 downto 0);
                        end if;
                        reg_intena(15) <= '0';

                    -- INTREQ ($DFF09C)
                    when x"09C" =>
                        if internal_data_w(15) = '1' then
                            reg_intreq(14 downto 0) <= reg_intreq(14 downto 0) or internal_data_w(14 downto 0);
                        else
                            reg_intreq(14 downto 0) <= reg_intreq(14 downto 0) and not internal_data_w(14 downto 0);
                        end if;
                        reg_intreq(15) <= '0';

                    when others => null;
                end case;
            end if;

        end if; 
    end process;

    -- =================================================================
    -- 2. TAKTFLANKENSYNCHRONER LESE-PROZESS (MIT AGA V8-ERWEITERUNG)
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_data_out_sync <= (others => '0');
        elsif rising_edge(clk_amiga) then
            reg_data_out_sync <= (others => '0'); 
            
            if chip_sel = '1' and read_en = '1' then
                case internal_addr is
                    -- VPOSR / VHPOSR ($DFF004 / $DFF006 als kombiniertes Longword)
                    when x"004" =>
                        -- KORREKTUR: Bit 8 der vertikalen Zeile fehlerfrei auf Bit 0 des VPOSR-Wortes legen! [14.1]
                        reg_data_out_sync(0)           <= v_pos_tick(8); 
                        -- Die restlichen Bits des VPOSR-Puffers sauber nullen (AGA-Standard)
                        reg_data_out_sync(15 downto 1) <= (others => '0');
                        
                        -- VHPOSR ($DFF006): Enthält die Zeilenbits V7..V0 und Strahlbits H8..H1 [14.1]
                        reg_data_out_sync(31 downto 24) <= std_logic_vector(v_pos_tick(7 downto 0));
                        reg_data_out_sync(23 downto 16) <= std_logic_vector(h_pos_tick(8 downto 1));
                        
                    when x"002" => -- DMACONR
                        reg_data_out_sync(15 downto 0) <= reg_dmacon;
                        reg_data_out_sync(31 downto 16) <= (others => '0');
                        
                    when x"01C" => -- INTENAR
                        reg_data_out_sync(15 downto 0) <= reg_intena;
                        reg_data_out_sync(31 downto 16) <= (others => '0');
                        
                    when x"01E" => -- INTREQR
                        reg_data_out_sync(15 downto 0) <= reg_intreq;
                        reg_data_out_sync(31 downto 16) <= (others => '0');
                        
                    when others =>
                        reg_data_out_sync <= (others => '0');
                end case;
            end if;
        end if;
    end process;

end Behavioral;
