library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Einbindung des globalen CPU-Wörterbuchs
use work.M68020_pkg.all;

entity M68020_sdram_bridge is
    Port (
        -- =============================================================
        -- 1. TAKT- UND SYSTEMBASIS
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der langsame Amiga-Systemtakt (~14 MHz)
        clk_sdram     : in    std_logic; -- Der schnelle Express-Speichertakt (114 MHz)
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. INNENWELT: SCHNITTSTELLE FÜR DEN SPÄTEREN CHIPSATZ (ALICE)
        -- =============================================================
        am_addr       : in    std_logic_vector(31 downto 0); -- Volle 32-Bit Adresse
        am_data_w     : in    std_logic_vector(31 downto 0); -- Schreibdaten vom Amiga-Bus
        am_data_r     : out   std_logic_vector(31 downto 0); -- Lesedaten zurück zum Amiga-Bus
        am_as_n       : in    std_logic;                     -- Address Strobe
        am_ds_n       : in    std_logic;                     -- Data Strobe
        am_rw         : in    std_logic;                     -- Read (1) / Write (0)
        
        -- Signale für das intelligente, dynamische 32/16/8-Bit Bus-Sizing
        am_siz0       : in    std_logic;                     -- Size Bit 0
        am_siz1       : in    std_logic;                     -- Size Bit 1
        
        -- Handshake-Antworten (Werden später von Alice freigegeben)
        am_dsack0_n   : out   std_logic;                     
        am_dsack1_n   : out   std_logic;                     
        
        -- =============================================================
        -- 3. AUSSENWELT: FIXE PHYSISCHE PINS ZUM MISTER-SDRAM-BOARD
        -- =============================================================
        sdram_clk     : out   std_logic;                     -- Dedizierter Takt-Pin fürs Board
        sdram_data    : inout std_logic_vector(15 downto 0); -- Physischer 16-Bit-Tristate-Bus
        sdram_addr    : out   std_logic_vector(12 downto 0); -- SDRAM Adressleitungen (A0-A12)
        sdram_ba      : out   std_logic_vector(1 downto 0);  -- Bank Select (BA0, BA1)
        
        -- Die rohen Hardware-Handshake-Steuerleitungen des SDR-SDRAMs
        sdram_ras_n   : out   std_logic;                     -- Row Address Strobe
        sdram_cas_n   : out   std_logic;                     -- Column Address Strobe
        sdram_we_n    : out   std_logic;                     -- Write Enable
        
        -- Byte-Auswahlmasken für gezielte Hardware-Byte-Selektion
        sdram_dqm_lo  : out   std_logic;                     -- Data Mask unteres Byte (D0-D7)
        sdram_dqm_hi  : out   std_logic                      -- Data Mask oberes Byte (D8-D15)
    );
end M68020_sdram_bridge;

architecture Behavioral of M68020_sdram_bridge is

    -- Interne Signale für die kombinatorische Datenbus-Weiche
    signal internal_sdram_out : std_logic_vector(15 downto 0);
    signal select_width       : std_logic_vector(3 downto 0);

begin

    -- =================================================================
    -- 1. TAKT-DURCHLEITUNG (Fix verdrahtet nach außen)
    -- =================================================================
    sdram_clk <= clk_sdram;

    -- =================================================================
    -- 2. TRISTATE-STEUERUNG FÜR DEN PHYSISCHEN SD-RAM DATENBUS
    -- =================================================================
    -- Wenn der Amiga schreibt (am_rw = '0'), treiben wir die physischen Pins.
    -- Wenn der Amiga liest (am_rw = '1'), schalten wir die Pins hochohmig ('Z'),
    -- damit das externe SD-RAM-Modul seine Daten anlegen kann.
    sdram_data <= internal_sdram_out when am_rw = '0' else (others => 'Z');

    -- Vektor zur einfacheren Auswertung von Breiten- und Adresswünschen bündeln
    select_width <= am_siz1 & am_siz0 & am_addr(1 downto 0);

    -- =================================================================
    -- 3. INTERNER MULTIPLEXER: SCHREIBDATEN-ROUTING (Innen nach Außen)
    -- =================================================================
    process(select_width, am_data_w)
    begin
        -- Standardwerte setzen (Verhindert ungewollte Latches im FPGA-Silizium)
        internal_sdram_out <= (others => '0');
        sdram_dqm_hi       <= '1'; -- '1' bedeutet Byte blockiert
        sdram_dqm_lo       <= '1';

        case select_width is
            -- ---------------------------------------------------------
            -- FALL A: 32-BIT ZUGRIFF (Longword: SIZ = "00")
            -- ---------------------------------------------------------
            when "0000" | "0001" | "0010" | "0011" =>
                -- Bei 32-Bit werden beide Bytes des physischen Busses gefüttert.
                -- Hinweis: Die Aufteilung in oberes und unteres Word erfolgt später 
                -- synchron über die Alice-Zustandsmaschine. Vorerst legen wir das 
                -- obere Word als Standard an.
                internal_sdram_out <= am_data_w(31 downto 16);
                sdram_dqm_hi       <= '0'; -- Beide Bytes zum Schreiben freigeben
                sdram_dqm_lo       <= '0';

            -- ---------------------------------------------------------
            -- FALL B: 16-BIT ZUGRIFF (Word: SIZ = "10")
            -- ---------------------------------------------------------
            when "1000" | "1001" =>
                -- Ausrichtung auf obere 16-Bit Hälfte
                internal_sdram_out <= am_data_w(31 downto 16);
                sdram_dqm_hi       <= '0';
                sdram_dqm_lo       <= '0';
                
            when "1010" | "1011" =>
                -- Ausrichtung auf untere 16-Bit Hälfte
                internal_sdram_out <= am_data_w(15 downto 0);
                sdram_dqm_hi       <= '0';
                sdram_dqm_lo       <= '0';

            -- ---------------------------------------------------------
            -- FALL C: 8-BIT ZUGRIFF (Byte: SIZ = "01")
            -- ---------------------------------------------------------
            when "0100" => -- Byte 0 (D24-D31) -> Auf obere SDRAM-Hälfte spiegeln
                internal_sdram_out(15 downto 8) <= am_data_w(31 downto 24);
                sdram_dqm_hi                     <= '0'; -- Nur oberes physisches Byte schreiben
                sdram_dqm_lo                     <= '1'; -- Unteres sperren
                
            when "0101" => -- Byte 1 (D16-D23) -> Auf untere SDRAM-Hälfte spiegeln
                internal_sdram_out(7 downto 0) <= am_data_w(23 downto 16);
                sdram_dqm_hi                    <= '1';
                sdram_dqm_lo                    <= '0';
                
            when "0110" => -- Byte 2 (D8-D15) -> Auf obere SDRAM-Hälfte spiegeln
                internal_sdram_out(15 downto 8) <= am_data_w(15 downto 8);
                sdram_dqm_hi                     <= '0';
                sdram_dqm_lo                     <= '1';
                
            when "0111" => -- Byte 3 (D0-D7) -> Auf untere SDRAM-Hälfte spiegeln
                internal_sdram_out(7 downto 0) <= am_data_w(7 downto 0);
                sdram_dqm_hi                    <= '1';
                sdram_dqm_lo                    <= '0';

            when others =>
                null;
        end case;
    end process;

    -- =================================================================
    -- 4. INTERNER MULTIPLEXER: LESEDATEN-ROUTING (Außen nach Innen)
    -- =================================================================
    process(select_width, sdram_data)
    begin
        -- Standardwert für den 32-Bit-Bus der CPU
        am_data_r <= (others => '0');

        case select_width is
            -- 32-Bit Lesen: Das physische 16-Bit Word wird vorerst spiegelbildlich
            -- auf beide Hälften des internen Busses gelegt, damit keine offenen Leitungen hängen.
            when "0000" | "0001" | "0010" | "0011" =>
                am_data_r(31 downto 16) <= sdram_data;
                am_data_r(15 downto 0)  <= sdram_data;

            -- 16-Bit Lesen (Word)
            when "1000" | "1001" =>
                am_data_r(31 downto 16) <= sdram_data;
            when "1010" | "1011" =>
                am_data_r(15 downto 0)  <= sdram_data;

            -- 8-Bit Lesen (Byte) -> Das gelesene physische Byte wird auf die 
            -- exakt korrekte Position innerhalb des 32-Bit-Langwortes geroutet.
            when "0100" =>
                am_data_r(31 downto 24) <= sdram_data(15 downto 8);
            when "0101" =>
                am_data_r(23 downto 16) <= sdram_data(7 downto 0);
            when "0110" =>
                am_data_r(15 downto 8)  <= sdram_data(15 downto 8);
            when "0111" =>
                am_data_r(7 downto 0)   <= sdram_data(7 downto 0);

            when others =>
                null;
        end case;
    end process;

    -- =================================================================
    -- 5. PASSIVE STATUSSIGNALE (Feste Standardwerte für das Basiskonstrukt)
    -- =================================================================
    -- Da die Brücke passiv isoliert ist und erst mit Alice scharfgeschaltet wird,
    -- legen wir die Steuerleitungen vorerst auf sichere, inaktive Standardwerte.
    sdram_addr  <= (others => '0');
    sdram_ba    <= (others => '0');
    sdram_ras_n <= '1'; -- NOP-Kommando für das SDRAM im Leerlauf
    sdram_cas_n <= '1';
    sdram_we_n  <= '1';

    -- Das Handshake bleibt abgeklemmt, bis Alice die Ablaufsteuerung übernimmt
    am_dsack0_n <= 'Z'; 
    am_dsack1_n <= 'Z';

end Behavioral;
