-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   sdram_bridge.vhd
-- Teil:    1 von 3 (Schnittstelle mit Decoder-Kopplung)
-- Funktion: Die getaktete 114-MHz SDR-SDRAM-Schnittstelle des Mainboards.
--           Verwaltet das 32-Bit-auf-16-Bit Dynamic Bus Sizing für das
--           physische 16-Bit MISTer-SDRAM-Board ohne Datenverlust.
-- ANPASSUNG:
--   - Gekoppelt an die sanierten Signale der ram_decoder.vhd (dec_sb_addr/req).
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sdram_bridge is
    Port (
        -- =============================================================
        -- 1. TAKT- UND SYSTEMBASIS
        -- =============================================================
        clk_amiga       : in    std_logic;                      -- Langsamer Amiga-Systemtakt (~14.18 MHz)
        clk_sdram       : in    std_logic;                      -- Schneller Express-Speichertakt (114.24 MHz)
        reset           : in    std_logic;                      -- Globaler System-Reset
        
        -- =============================================================
        -- 2. INNENWELT: GEKOPPELT AN DEN RAM-DECODER & EXT_BUS_BRIDGE
        -- =============================================================
        -- ANPASSUNG: Nimmt die umgerechnete, 128-MB-konforme Adresse entgegen
        dec_sb_addr     : in    std_logic_vector(26 downto 0);  -- Lückenlose Adresse für das SDRAM
        dec_sb_req      : in    std_logic;                      -- Aktivierungssignal vom RAM-Decoder
        dec_sb_is_chip  : in    std_logic;                      -- Kennung für Chip-RAM-Zugriff (Alice-DMA)
        
        -- Datenbus-Lanes von der ext_bus_bridge
        am_data_w       : in    std_logic_vector(31 downto 0);  -- Schreibdaten vom Amiga-Bus
        am_data_r       : out   std_logic_vector(31 downto 0);  -- Lesedaten zurück zum Amiga-Bus
        am_as_n         : in    std_logic;                      -- Address Strobe zur Zyklusüberwachung
        am_ds_n         : in    std_logic;                      -- Data Strobe für das Byte-Timing
        am_rw           : in    std_logic;                      -- Read (1) / Write (0)
        
        -- Motorola-Kontrollsignale für das dynamische 32/16/8-Bit Bus-Sizing
        am_siz0         : in    std_logic;                      
        am_siz1         : in    std_logic;                      
        
        -- Handshake-Antworten direkt an das Gehäusepforte (ext_bus_bridge)
        am_dsack0_n     : out   std_logic;                     
        am_dsack1_n     : out   std_logic;                     
        
        -- =============================================================
        -- 3. AUSSENWELT: FIXE PHYSISCHE PINS ZUM MISTER-SDRAM-BOARD
        -- =============================================================
        sdram_clk       : out   std_logic;                      -- Dedizierter Takt-Pin fürs Board
        sdram_data      : inout std_logic_vector(15 downto 0);  -- Physischer 16-Bit-Tristate-Bus
        sdram_addr      : out   std_logic_vector(12 downto 0);  -- SDRAM Adressleitungen (A0-A12)
        sdram_ba        : out   std_logic_vector(1 downto 0);   -- Bank Select (BA0, BA1)
        sdram_ras_n     : out   std_logic;                      -- Row Address Strobe
        sdram_cas_n     : out   std_logic;                      -- Column Address Strobe
        sdram_we_n      : out   std_logic;                      -- Write Enable
        sdram_dqm_lo    : out   std_logic;                      -- Data Mask unteres Byte (D0-D7)
        sdram_dqm_hi    : out   std_logic                      -- Data Mask oberes Byte (D8-D15)
    );
end sdram_bridge;

architecture Behavioral of sdram_bridge is

    -- Zustands-Typen für das unbestechliche 16-Bit SDRAM-Sizing-Protokoll
    type sdram_fsm_type is (
        SD_IDLE,            -- Wartestation, überwacht am_as_n via Synchronizer
        SD_PRECHARGE,       -- Schließt offene Bänke vor neuem Zugriff
        SD_ACTIVATE,        -- Zeilen-Aktivierung (Row Address)
        SD_CMD_1,           -- Schritt 1: Erstes 16-Bit Fragment (Oberes Word/Byte)
        SD_WAIT_1,          -- Wartet auf CAS-Latenz / Daten-Einrasten
        SD_CMD_2,           -- Schritt 2: Zweites 16-Bit Fragment (NUR BEI 32-BIT LONGWORD!)
        SD_WAIT_2,          -- Wartet auf zweites CAS-Daten-Häppchen
        SD_ACK_PULSE,       -- Quittungs-Zündung: Zieht DSACKx auf Low für die CPU
        SD_CLEANUP          -- Wartet, bis die CPU AS_N wieder fallen lässt
    );

    signal current_state : sdram_fsm_type := SD_IDLE;

    -- Metastabile Synchronisations-Pipeline für die asynchronen Amiga-Strobes
    signal as_n_r1, as_n_r2 : std_logic := '1';
    signal ds_n_r1, ds_n_r2 : std_logic := '1';

    -- Synchronisierte Puffer-Register zur Datenerhaltung vor dem Auslöschen
    -- ANPASSUNG: Das Adressregister ist auf die 27-Bit-Decoder-Breite angepasst
    signal reg_read_accumulator : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_write_buffer     : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_latched_addr     : std_logic_vector(26 downto 0) := (others => '0');

    -- Interne physische Kontroll-Signale
    signal internal_sdram_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal select_width         : std_logic_vector(3 downto 0);
    signal sdram_oe             : std_logic := '0'; -- Eiserner Protektor gegen Bus Contention!

    -- Synchronisierte Registerstufen für sauberes Open-Drain Handshaking
    signal reg_dsack0_n         : std_logic := '1';
    signal reg_dsack1_n         : std_logic := '1';

begin

    -- =====================================================================
    -- 1. TAKT-DURCHLEITUNG UND BI-DIREKTIONALE TRISTATE-SICHERUNG
    -- =====================================================================
    -- Reicht den schnellen 114-MHz-Takt direkt an die physische I/O-Zelle weiter
    sdram_clk <= clk_sdram;

    -- Eiserner Schutzbelag: Das FPGA treibt die Datenpins NUR bei aktivem sdram_oe!
    -- Verhindert Bus-Kollisionen (Bus Contention), wenn das Board noch Daten anlegt.
    sdram_data <= internal_sdram_out when sdram_oe = '1' else (others => 'Z');

    -- KORREKTUR: Kombinatorischer Open-Drain-Auslass verhindert Rauschen und Geisterpegel
    am_dsack0_n <= '0' when reg_dsack0_n = '0' else 'Z';
    am_dsack1_n <= '0' when reg_dsack1_n = '0' else 'Z';

    -- KORREKTUR: Sizing-Vektor leitet die Byte-Ausrichtung nun aus dem stabilen Register ab
    select_width <= am_siz1 & am_siz0 & reg_latched_addr(1 downto 0);

    -- =====================================================================
    -- 2. KOMBINAOTORISCHER LESE-MULTIPLEXER (OUTBOUND AN ALICE / CORE-BUS)
    -- =====================================================================
    -- Reicht den Inhalt des im 114-MHz-Takt befüllten Akkumulators an das Mainboard weiter.
    am_data_r <= reg_read_accumulator;

    -- =====================================================================
    -- 3. INTERNER MULTIPLEXER: PHYSISCHES OUTBOUND-SCHREIB-ROUTING
    -- =====================================================================
    -- Regelt die Byte-Ausrichtung und die Spur-Spiegelung für das SDR-SDRAM.
    process(select_width, reg_write_buffer, current_state)
    begin
        internal_sdram_out <= (others => '0');
        sdram_dqm_hi       <= '1'; -- Standardmäßig Byte-Spur starr blockieren
        sdram_dqm_lo       <= '1';

        -- Das Treiben der Signale ist logisch an die Datenphasen gekoppelt
        if current_state = SD_CMD_1 or current_state = SD_CMD_2 then
            case select_width is
                
                -- FALL A: 32-BIT ZUGRIFF (Longword: SIZ = "00")
                when "0000" | "0001" | "0010" | "0011" =>
                    if current_state = SD_CMD_2 then
                        internal_sdram_out <= reg_write_buffer(15 downto 0);  -- Fragment 2: LSB
                    else
                        internal_sdram_out <= reg_write_buffer(31 downto 16); -- Fragment 1: MSB
                    end if;
                    sdram_dqm_hi <= '0'; sdram_dqm_lo <= '0'; -- Beide Byte-Bahnen öffnen

                -- FALL B: 16-BIT ZUGRIFF (Word: SIZ = "10")
                when "1000" | "1001" => -- Oberes Word (D31-D16)
                    internal_sdram_out <= reg_write_buffer(31 downto 16);
                    sdram_dqm_hi <= '0'; sdram_dqm_lo <= '0';
                when "1010" | "1011" => -- Unteres Word (D15-D0)
                    internal_sdram_out <= reg_write_buffer(15 downto 0);
                    sdram_dqm_hi <= '0'; sdram_dqm_lo <= '0';

                -- FALL C: 8-BIT ZUGRIFF (Byte: SIZ = "01")
                -- Duplizierung verhindert Rauschen und I/O-Umladespitzen
                when "0100" => -- Byte 0 (D31-D24)
                    internal_sdram_out <= reg_write_buffer(31 downto 24) & reg_write_buffer(31 downto 24);
                    sdram_dqm_hi <= '0'; sdram_dqm_lo <= '1'; -- Nur obere physische Spur schreiben
                when "0101" => -- Byte 1 (D23-D16)
                    internal_sdram_out <= reg_write_buffer(23 downto 16) & reg_write_buffer(23 downto 16);
                    sdram_dqm_hi <= '1'; sdram_dqm_lo <= '0'; -- Nur untere physische Spur schreiben
                when "0110" => -- Byte 2 (D15-D8)
                    internal_sdram_out <= reg_write_buffer(15 downto 8) & reg_write_buffer(15 downto 8);
                    sdram_dqm_hi <= '0'; sdram_dqm_lo <= '1';
                when "0111" => -- Byte 3 (D7-D0)
                    internal_sdram_out <= reg_write_buffer(7 downto 0) & reg_write_buffer(7 downto 0);
                    sdram_dqm_hi <= '1'; sdram_dqm_lo <= '0';

                when others => null;
            end case;
        end if;
    end process;
	 
	     -- =====================================================================
    -- 4. SYNCHRONER CONTROL-PROZESS: 114-MHZ SIZING- AND COMMAND-FSM
    -- =====================================================================
    process(clk_sdram, reset)
        variable row_addr : std_logic_vector(12 downto 0);
        variable col_addr : std_logic_vector(8 downto 0);
        variable bank_sel : std_logic_vector(1 downto 0);
    begin
        if reset = '1' then
            current_state        <= SD_IDLE;
            as_n_r1              <= '1'; as_n_r2 <= '1';
            ds_n_r1              <= '1'; ds_n_r2 <= '1';
            reg_read_accumulator <= (others => '0');
            reg_write_buffer     <= (others => '0');
            reg_latched_addr     <= (others => '0');
            sdram_oe             <= '0';
            sdram_addr           <= (others => '0');
            sdram_ba             <= (others => '0');
            sdram_ras_n          <= '1';
            sdram_cas_n          <= '1';
            sdram_we_n           <= '1';
            reg_dsack0_n         <= '1';
            reg_dsack1_n         <= '1';

        elsif rising_edge(clk_sdram) then
            -- Standardmäßig Hardware-Befehl auf NOP halten (SDR-SDRAM Default)
            sdram_ras_n <= '1';
            sdram_cas_n <= '1';
            sdram_we_n  <= '1';
            
            -- Quittungsregister standardmäßig passiv inaktiv halten (High / Open-Drain)
            reg_dsack0_n <= '1';
            reg_dsack1_n <= '1';

            -- 2-stufige Synchronisations-Pipeline gegen Metastabilität (Amiga-Bus-Einkopplung)
            as_n_r1 <= am_as_n;
            as_n_r2 <= as_n_r1;
            ds_n_r1 <= am_ds_n;
            ds_n_r2 <= ds_n_r1;

            -- KORREKTUR: Adress-Mapping zerlegt jetzt die lückenlose 27-Bit-Decoder-Adresse!
            row_addr := reg_latched_addr(21 downto 9);   -- Passend zur Geometrie Ihrer SDRAM-Zeilen
            col_addr := reg_latched_addr(8 downto 0);    -- Spaltenauswahl
            bank_sel := reg_latched_addr(23 downto 22);  -- Obere Bank-Auswahlbits

            case current_state is

                -- ---------------------------------------------------------
                -- SD_IDLE: WARTEN AUF Bereinigten SPEICHERREIZ VOM DECODER
                -- ---------------------------------------------------------
                when SD_IDLE =>
                    sdram_oe <= '0';
                    -- KORREKTUR: Die Bridge startet NUR, wenn der RAM-Decoder echtes RAM anfordert!
                    -- Ignoriert I/O-Bereiche und das Kickstart-BRAM krisensicher.
                    if as_n_r2 = '0' and dec_sb_req = '1' then
                        -- Adressen aus der lückenlosen Decoder-Lane einfrieren
                        reg_latched_addr <= dec_sb_addr;
                        reg_write_buffer <= am_data_w;
                        current_state    <= SD_PRECHARGE;
                    end if;

                -- ---------------------------------------------------------
                -- SD_PRECHARGE: ALLE OFFENEN BÄNKE SCHLIESSEN (PRECHARGE ALL)
                -- ---------------------------------------------------------
                when SD_PRECHARGE =>
                    sdram_ras_n <= '0';
                    sdram_cas_n <= '1';
                    sdram_we_n  <= '0'; -- Command: Precharge All (A10 = '1')
                    sdram_addr  <= "0010000000000"; -- Bit 10 setzen
                    current_state <= SD_ACTIVATE;

                -- ---------------------------------------------------------
                -- SD_ACTIVATE: LOGISCHE INSEL ÖFFNEN (ROW ACTIVE)
                -- ---------------------------------------------------------
                when SD_ACTIVATE =>
                    sdram_ras_n <= '0';
                    sdram_cas_n <= '1';
                    sdram_we_n  <= '1'; -- Command: Active
                    sdram_ba    <= bank_sel;
                    sdram_addr  <= row_addr;
                    current_state <= SD_CMD_1;

                -- ---------------------------------------------------------
                -- SD_CMD_1: COMMAND FRAGMENT 1 ABSETZEN (READ / WRITE 1)
                -- ---------------------------------------------------------
                when SD_CMD_1 =>
                    sdram_ras_n <= '1';
                    sdram_cas_n <= '0'; -- Command: Column Read/Write zünden
                    sdram_we_n  <= am_rw;
                    sdram_ba    <= bank_sel;
                    sdram_addr  <= "000" & col_addr; -- A10 = '0' (Kein Auto-Precharge)

                    if am_rw = '0' then
                        sdram_oe <= '1'; -- Schreibpuffer bei Write scharfschalten
                    end if;
                    current_state <= SD_WAIT_1;

                -- ---------------------------------------------------------
                -- SD_WAIT_1: LESE-AKKUMULATION ODER SPEICHER-EINRAST-ZEIT
                -- ---------------------------------------------------------
                when SD_WAIT_1 =>
                    if am_rw = '0' then
                        sdram_oe <= '1'; -- Schreibpuffer stabil aktiv halten
                    end if;

                    if am_rw = '1' then
                        -- Daten der externen Pins byte-genau im Akkumulator verrasten
                        case select_width is
                            when "0000" | "0001" | "0010" | "0011" => -- 32-Bit: Erstes Word sichern
                                reg_read_accumulator(31 downto 16) <= sdram_data;
                            when "1000" | "1001" => -- Word Oberes
                                reg_read_accumulator(31 downto 16) <= sdram_data;
                            when "1010" | "1011" => -- Word Unteres
                                reg_read_accumulator(15 downto 0)  <= sdram_data;
                            when "0100" => -- Byte 0
                                reg_read_accumulator(31 downto 24) <= sdram_data(15 downto 8);
                            when "0101" => -- Byte 1
                                reg_read_accumulator(23 downto 16) <= sdram_data(7 downto 0);
                            when "0110" => -- Byte 2
                                reg_read_accumulator(15 downto 8)  <= sdram_data(15 downto 8);
                            when "0111" => -- Byte 3
                                reg_read_accumulator(7 downto 0)   <= sdram_data(7 downto 0);
                            when others => null;
                        end case;
                    end if;

                    -- DYNAMIC BUS SIZING: Wenn 32-Bit (SIZ = "00"), ab in die zweite Runde! [14.1]
                    if select_width(3 downto 2) = "00" then
                        current_state <= SD_CMD_2;
                    else
                        current_state <= SD_ACK_PULSE;
                    end if;

                -- ---------------------------------------------------------
                -- SD_CMD_2: FRAGMENT 2 - ZWEITER ZYKLUS FÜR 32-BIT LONGWORDS (A+2)
                -- ---------------------------------------------------------
                when SD_CMD_2 =>
                    sdram_ras_n <= '1';
                    sdram_cas_n <= '0';
                    sdram_we_n  <= am_rw;
                    sdram_ba    <= bank_sel;
                    -- Spaltenadresse im SDRAM für das zweite 16-Bit Word vorschieben (+2 Bytes)
                    sdram_addr  <= "000" & std_logic_vector(unsigned(col_addr) + 2);
                    current_state <= SD_WAIT_2;

                -- ---------------------------------------------------------
                -- SD_WAIT_2: ZWEITES SPEICHER-HÄPPCHEN VERRASHEN (NUR 32-BIT)
                -- ---------------------------------------------------------
                when SD_WAIT_2 =>
                    if am_rw = '0' then
                        sdram_oe <= '1';
                    end if;
                    
                    if am_rw = '1' then
                        -- Unteres Word im 32-Bit-Lesepuffer ergänzen
                        reg_read_accumulator(15 downto 0) <= sdram_data;
                    end if;
                    current_state <= SD_ACK_PULSE;

                -- ---------------------------------------------------------
                -- SD_ACK_PULSE: CPU-QUITTUNG AKTIVIEREN
                -- ---------------------------------------------------------
                when SD_ACK_PULSE =>
                    -- Da diese Brücke als 16-Bit-Port agiert, ziehen wir das Register
                    -- für reg_dsack1_n auf Low, während reg_dsack0_n auf High bleibt [14.1].
                    reg_dsack0_n <= '1';
                    reg_dsack1_n <= '0';
                    current_state <= SD_CLEANUP;

                -- ---------------------------------------------------------
                -- SD_CLEANUP: ABSCHLUSS-HOLD (WARTEN BIS AS_N ANGEHOBEN WIRD)
                -- ---------------------------------------------------------
                when SD_CLEANUP =>
                    reg_dsack0_n <= '1';
                    reg_dsack1_n <= '0'; -- Quittung stabil halten
                    
                    if as_n_r2 = '1' then
                        -- CPU hat den Transfer beendet -> Quittungsregister abschalten
                        reg_dsack0_n <= '1';
                        reg_dsack1_n <= '1';
                        sdram_oe     <= '0';
                        current_state <= SD_IDLE;
                    end if;

                when others =>
                    current_state <= SD_IDLE;
            end case;
        end if;
    end process;

end Behavioral;
