-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   cia_b_timer.vhd
-- Teil:    1 von 2 (Schnittstelle & Register-Deklarationen)
-- Funktion: Das Zeitmessgetriebe des Complex Interface Adapters B (CIA-B).
--           Verwaltet die 16-Bit-Intervalltimer A und B mit Latch-Nachladung.
-- IMPLEMENTIERUNG SCHRITT 2 (A):
--   - Native 16-Bit Timer-Struktur (TA_LO=$4, TA_HI=$5, TB_LO=$6, TB_HI=$7). [14.1]
--   - Kontrollregister CRA ($E) und CRB ($F) für Modus-Auswertungen. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cia_b_timer is
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
        data_in       : in    std_logic_vector(7 downto 0);  -- Daten von der CPU zum Timer
        data_out      : out   std_logic_vector(7 downto 0);  -- Daten vom Timer zur CPU
        
        -- =============================================================
        -- 3. INTERNE ALARM-AUSGÄNGE ZUM CIA-INTERRUPTMODUL
        -- =============================================================
        timer_a_irq   : out   std_logic; -- Impuls bei Unterlauf von Timer A
        timer_b_irq   : out   std_logic; -- Impuls bei Unterlauf von Timer B
        
        -- =============================================================
        -- 4. AUSSENWELT: PHYSISCHE SCHALTPINS (Direkt zur Chip-Entity)
        -- =============================================================
        cia_tod       : in    std_logic; -- Time of Day Netztakt-Eingang
        cia_cnt       : in    std_logic  -- Manueller Zähl-Eingang für Timer B
    );
end cia_b_timer;

architecture Behavioral of cia_b_timer is

    -- Die originalen 16-Bit Hardware-Zählerregister (In Low- und High-Byte geteilt)
    signal counter_a : unsigned(15 downto 0) := (others => '1');
    signal counter_b : unsigned(15 downto 0) := (others => '1');

    -- Die originalen 16-Bit Hardware-Halte-Register (Latches für den Startwert)
    signal latch_a   : unsigned(15 downto 0) := (others => '1');
    signal latch_b   : unsigned(15 downto 0) := (others => '1');

    -- Die beiden originalen Amiga Kontrollregister CRA ($E) und CRB ($F)
    signal reg_cra   : std_logic_vector(7 downto 0) := (others => '0'); 
    signal reg_crb   : std_logic_vector(7 downto 0) := (others => '0'); 

    -- Synchroner Registerpuffer für den Bus-Lesepfad
    signal reg_data_out_sync : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Den getakteten Lese-Puffer permanent nach außen leiten
    data_out <= reg_data_out_sync;

	     -- =========================================================================
    -- OPERATIVER TIMER-VORSCHUB UND CPU-Schnittstelle (Synchroner Hauptprozess)
    -- =========================================================================
    process(clk_sys, reset)
    begin
        if reset = '1' then
            counter_a         <= (others => '1');
            counter_b         <= (others => '1');
            latch_a           <= (others => '1');
            latch_b           <= (others => '1');
            reg_cra           <= (others => '0');
            reg_crb           <= (others => '0');
            reg_data_out_sync <= (others => '0');
            timer_a_irq       <= '0';
            timer_b_irq       <= '0';
        elsif rising_edge(clk_sys) then
            
            -- Standard-Impulse bei jedem Takt standardmäßig zurücksetzen
            timer_a_irq <= '0';
            timer_b_irq <= '0';
            reg_data_out_sync <= (others => '0');

            -- -----------------------------------------------------------------
            -- RUN-LEVEL A: NATIVE TIMER-A DEKREMENTIERUNG (E-Clock getaktet) [14.1]
            -- -----------------------------------------------------------------
            if e_clock_ce = '1' then
                -- Timer A läuft nur herunter, wenn Bit 0 (Start) im CRA aktiv ist [14.1]
                if reg_cra(0) = '1' then
                    if counter_a = x"0000" then
                        timer_a_irq <= '1'; -- Unterlauf-Alarm zünden! [14.1]
                        
                        -- RunMode prüfen: Bit 3 = '1' zwingt Timer in den One-Shot Modus (Stopp) [14.1]
                        if reg_cra(3) = '1' then
                            reg_cra(0) <= '0'; -- Timer stoppen
                            counter_a  <= latch_a; -- Neu aufladen
                        else
                            counter_a <= latch_a; -- Continuous-Modus: Aus Latch nachladen [14.1]
                        end if;
                    else
                        counter_a <= counter_a - 1;
                    end if;
                end if;

                -- -----------------------------------------------------------------
                -- RUN-LEVEL B: NATIVE TIMER-B DEKREMENTIERUNG (E-Clock getaktet) [14.1]
                -- -----------------------------------------------------------------
                -- Timer B läuft hier im Standard-Modus (CRB(6..5) = "00") synchron mit
                if reg_crb(0) = '1' then
                    if counter_b = x"0000" then
                        timer_b_irq <= '1'; -- Unterlauf-Alarm zünden! [14.1]
                        
                        if reg_crb(3) = '1' then
                            reg_crb(0) <= '0'; -- One-Shot Stopp
                            counter_b  <= latch_b;
                        else
                            counter_b <= latch_b; -- Continuous-Nachladung [14.1]
                        end if;
                    else
                        counter_b <= counter_b - 1;
                    end if;
                end if;
            end if;

            -- -----------------------------------------------------------------
            -- BUS-SCHREIBZUGRIFFE DER CPU (Synchron zum E-Clock Timing) [14.1]
            -- -----------------------------------------------------------------
            if chip_sel = '1' and write_en = '1' and e_clock_ce = '1' then
                case reg_addr(3 downto 0) is
                    when x"4" => latch_a(7 downto 0)   <= unsigned(data_in); -- $TA_LO [14.1]
                    when x"5" => latch_a(15 downto 8)  <= unsigned(data_in); -- $TA_HI
                                 if reg_cra(0) = '0' then 
                                     counter_a <= unsigned(data_in) & latch_a(7 downto 0); -- Automatisches Laden im Stopp-Zustand [14.1]
                                 end if;
                                 
                    when x"6" => latch_b(7 downto 0)   <= unsigned(data_in); -- $TB_LO [14.1]
                    when x"7" => latch_b(15 downto 8)  <= unsigned(data_in); -- $TB_HI
                                 if reg_crb(0) = '0' then 
                                     counter_b <= unsigned(data_in) & latch_b(7 downto 0);
                                 end if;
                                 
                    when x"E" => reg_cra <= data_in; -- $CRA [14.1]
                                 if data_in(4) = '1' then 
                                     counter_a <= latch_a; -- Force-Load Strobe (Bit 4) emulieren [14.1]
                                 end if;
                    when x"F" => reg_crb <= data_in; -- $CRB [14.1]
                                 if data_in(4) = '1' then 
                                     counter_b <= latch_b; -- Force-Load Strobe (Bit 4) emulieren [14.1]
                                 end if;
                    when others => null;
                end case;
            end if;

            -- -----------------------------------------------------------------
            -- BUS-LESEZUGRIFFE DER CPU (Echtzeit-Registerausgabe) [14.1]
            -- -----------------------------------------------------------------
            if chip_sel = '1' and read_en = '1' then
                case reg_addr(3 downto 0) is
                    when x"4" => reg_data_out_sync <= std_logic_vector(counter_a(7 downto 0));   -- $TA_LO [14.1]
                    when x"5" => reg_data_out_sync <= std_logic_vector(counter_a(15 downto 8));  -- $TA_HI [14.1]
                    when x"6" => reg_data_out_sync <= std_logic_vector(counter_b(7 downto 0));   -- $TB_LO [14.1]
                    when x"7" => reg_data_out_sync <= std_logic_vector(counter_b(15 downto 8));  -- $TB_HI [14.1]
                    when x"E" => reg_data_out_sync <= reg_cra;                                   -- $CRA [14.1]
                    when x"F" => reg_data_out_sync <= reg_crb;                                   -- $CRB [14.1]
                    when others => reg_data_out_sync <= (others => '0');
                end case;
            end if;

        end if;
    end process;

end Behavioral;
