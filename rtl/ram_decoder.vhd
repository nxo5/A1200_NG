-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   ram_decoder.vhd
-- Funktion: Der übergeordnete Adress-Übersetzer für das Mainboard.
-- KORREKTUREN:
--   - Weitet Zorro-II Fast-RAM lückenlos auf volle 8 MB auf (PCMCIA abgestellt). [14.1]
--   - Mapt das Kickstart-ROM im SDRAM starr auf die 10,0-Megabyte-Marke! [14.1]
--   - Übergibt der Bridge die exakt berechnete Wortadresse (sb_addr). [14.1]
--   - Befreit das On-Chip-BRAM komplett vom 512-KB ROM-Ballast. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ram_decoder is
    Port (
        -- =============================================================
        -- 1. EINGÄNGE VOM CPU-BUS (ÜBER DIE EXT_BUS_BRIDGE)
        -- =============================================================
        cpu_A           : in    std_logic_vector(31 downto 0);  -- CPU-Wunschadresse
        cpu_as_n        : in    std_logic;                      -- Address Strobe der CPU
        
        -- =============================================================
        -- 2. AUSGÄNGE AN DIE SDRAM_BRIDGE (UMGERECHNET & LÜCKENLOS)
        -- =============================================================
        sb_addr         : out   std_logic_vector(26 downto 2);  -- Exakte Wortadresse für 128 MB SDRAM [14.1]
        sb_req          : out   std_logic;                      -- Aktivierungssignal für die sdram_bridge
        sb_is_chipram   : out   std_logic                       -- Signalisiert der Bridge ein aktives Chip-RAM
    );
end ram_decoder;

architecture behavioral of ram_decoder is
    -- Die unbestechliche 10,0-Megabyte-Basisadresse im SDRAM (10 * 1024 * 1024 = 10.485.760 Bytes)
    constant KICKSTART_SDRAM_BASE : unsigned(26 downto 0) := to_unsigned(10485760, 27);
begin

    -- =====================================================================
    -- REIN KOMBINAOTORISCHES ADRESS-STELLWERK (0 WAIT-STATES)
    -- =====================================================================
    process(cpu_A, cpu_as_n)
        variable v_addr       : unsigned(31 downto 0);
        variable v_rom_offset : unsigned(26 downto 0);
        variable v_final_addr : unsigned(26 downto 0);
    begin
        -- Standard-Voreinstellungen: Im Ruhezustand alles starr abschalten
        sb_addr       <= (others => '0');
        sb_req        <= '0';
        sb_is_chipram <= '0';
        
        v_addr := unsigned(cpu_A);

        if cpu_as_n = '0' then
            
            -- -----------------------------------------------------------------
            -- ZONE 1: Das klassische Amiga-Chip-RAM (0 bis 2 Megabyte) [14.1]
            -- -----------------------------------------------------------------
            if v_addr >= x"00000000" and v_addr <= x"001FFFFF" then
                -- Wortadressen-Ausgabe: Schneidet die untersten 2 Bits (Byte-Lanes) ab [14.1]
                sb_addr       <= std_logic_vector(v_addr(26 downto 2)); 
                sb_req        <= '1';
                sb_is_chipram <= '1'; -- Alice erhält die DMA-Hoheit
                
            -- -----------------------------------------------------------------
            -- ZONE 2: Erweitertes Zorro-II Fast-RAM (2 bis 10 Megabyte lückenlos!) [14.1]
            -- -----------------------------------------------------------------
            elsif v_addr >= x"00200000" and v_addr <= x"009FFFFF" then
                -- Das RAM wird vollkommen lochfrei im SDRAM fortgeführt [14.1]
                sb_addr       <= std_logic_vector(v_addr(26 downto 2)); 
                sb_req        <= '1';
                sb_is_chipram <= '0'; -- Reines schnelles CPU-RAM
                
            -- -----------------------------------------------------------------
            -- ZONE 3: REPARATUR-BYPASS FÜR DAS KICKSTART-ROM ($F80000 - $FFFFFF) [14.1]
            -- -----------------------------------------------------------------
            elsif v_addr >= x"00F80000" and v_addr <= x"00FFFFFF" then
                -- Isoliert den 19-Bit Offset des 512-KB ROMs (0 bis 524.287) [14.1]
                v_rom_offset := "00000000" & v_addr(18 downto 0);
                
                -- Setzt das ROM absolut lochfrei genau hinter die 10,0 MB Grenze! [14.1]
                v_final_addr := KICKSTART_SDRAM_BASE + v_rom_offset;
                
                sb_addr       <= std_logic_vector(v_final_addr(26 downto 2)); -- Übergabe als Wortadresse! [14.1]
                sb_req        <= '1'; -- Zündet den SDRAM-Zugriff waitstatefrei! [14.1]
                sb_is_chipram <= '0';
                
            -- -----------------------------------------------------------------
            -- ZONE 4: CHIPSATZ- UND REGISTER-SPERRZONE (SDRAM SCHWEIGT STILL)
            -- -----------------------------------------------------------------
            elsif v_addr >= x"00A00000" and v_addr <= x"00EFFFFF" then
                sb_addr       <= (others => '0');
                sb_req        <= '0'; -- Totale SDRAM-Abschaltung für Gayle/CIAs!
                sb_is_chipram <= '0';
            end if;
            
        end if;
    end process;

end behavioral;
