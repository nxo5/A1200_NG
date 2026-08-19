-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   kickstart.vhd
-- Funktion: Die Next-Gen SDRAM-Befüllungseinheit für das Kickstart-ROM.
-- KORREKTUR FULL-FIX:
--   - Reißt die interne 512-KB Speicher-Matrix (kickstart_bram) komplett ab! [14.1]
--   - Leitet den OSD-Ioctl-Ladestrom direkt an den SDRAM-Schreibbus weiter. [14.1]
--   - Setzt das ROM beim Booten starr bei der 10,0-Megabyte-Marke im SDRAM ab. [14.1]
--   - Reduziert den internen Block-RAM-Verbrauch für das ROM auf exakt 0 Bits! [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity kickstart is
    Port (
        -- Globaler Systemtakt (Voll-synchron in der CPU-Taktfamilie)
        CLK             : in    std_logic;                      

        -- INTERFACE FÜR DIE OSD-MENÜ-LADESEITE (IOCTL BEIM BOOT-UPLOAD)
        ioctl_addr      : in    std_logic_vector(24 downto 0);  -- HPS-Byteadresse von der SD-Karte
        ioctl_data      : in    std_logic_vector(7 downto 0);   -- 8-Bit Datenstrom vom OSD-Menü
        ioctl_wr        : in    std_logic;                      -- Schreibimpuls vom OSD-Controller
        ioctl_download  : in    std_logic;                      -- '1' = Datei-Upload läuft, CPU im Reset

        -- =============================================================
        -- NEU: DIREKTE TREIBER-SCHIENEN ZUM EXTERNEN SDRAM-CONTROLLER
        -- =============================================================
        o_sdram_addr    : out   std_logic_vector(26 downto 2);  -- Umgerechnete Wortadresse fürs SDRAM [14.1]
        o_sdram_data_w  : out   std_logic_vector(31 downto 0);  -- Gepacktes 32-Bit Longword an den Schreibbus
        o_sdram_we      : out   std_logic                       -- Direkter Schreib-Impuls für die SDRAM-Bridge
    );
end kickstart;

architecture behavioral of kickstart is

    -- Die unbestechliche 10,0-Megabyte-Basisadresse im physischen SDRAM
    constant KICKSTART_SDRAM_BASE : unsigned(26 downto 0) := to_unsigned(10485760, 27);

    -- Byte-Packer Register für den OSD-Download
    signal reg_byte_cnt   : unsigned(1 downto 0) := "00";
    signal reg_word_latch : std_logic_vector(31 downto 0) := (others => '0');

begin

    -- =====================================================================
    -- 1. ADRESS-UMRECHNUNG FÜR DEN IN-FLUG SDRAM DOWNLOAD [14.1]
    -- =====================================================================
    process(ioctl_download, ioctl_addr, reg_word_latch, ioctl_data, reg_byte_cnt, ioctl_wr)
        variable v_rom_offset : unsigned(26 downto 0);
        variable v_final_addr : unsigned(26 downto 0);
    begin
        -- Standard-Voreinstellungen zur Vermeidung von Latches im Leerlauf
        o_sdram_addr   <= (others => '0');
        o_sdram_data_w <= (others => '0');
        o_sdram_we     <= '0';

        if ioctl_download = '1' then
            -- Isoliert den Byte-Offset der SD-Karte innerhalb des 512-KB ROM-Fensters
            v_rom_offset := "00000000" & unsigned(ioctl_addr(18 downto 0));
            
            -- Berechnet die absolute, lochfreie Zieladresse im 128 MB SDRAM-Riegel [14.1]
            v_final_addr := KICKSTART_SDRAM_BASE + v_rom_offset;
            
            -- Ausgabe als saubere 32-Bit Wortadresse an den SDRAM-Controller [14.1]
            o_sdram_addr <= std_logic_vector(v_final_addr(26 downto 2));

            -- Packt 4 nacheinander eintreffende Bytes zu einem fertigen Amiga-Longword zusammen
            case reg_byte_cnt is
                when "00" => o_sdram_data_w <= ioctl_data & reg_word_latch(23 downto 0);
                when "01" => o_sdram_data_w <= reg_word_latch(31 downto 24) & ioctl_data & reg_word_latch(15 downto 0);
                when "10" => o_sdram_data_w <= reg_word_latch(31 downto 16) & ioctl_data & reg_word_latch(7 downto 0);
                when "11" => o_sdram_data_w <= reg_word_latch(31 downto  8) & ioctl_data;
                when others => null;
            end case;

            -- Der Schreibimpuls an das SDRAM zündet EXAKT NUR DANN, wenn das 4. Byte ansteht! [14.1]
            if ioctl_wr = '1' and reg_byte_cnt = "11" then
                o_sdram_we <= '1';
            else
                o_sdram_we <= '0';
            end if;
        end if;
    end process;

    -- =====================================================================
    -- 2. SYNCHRONER TACK-PROZESS FÜR DEN BYTE-SAMMLER
    -- =====================================================================
    process(CLK)
    begin
        if rising_edge(CLK) then
            if ioctl_download = '1' then
                if ioctl_wr = '1' then
                    -- Schaltet den Zähler für die 4 Byte-Lanes weiter
                    reg_byte_cnt <= reg_byte_cnt + 1;
                    
                    -- Sichert die eintreffenden Häppchen taktsynchron im Haltemuster ab
                    case reg_byte_cnt is
                        when "00" => reg_word_latch(31 downto 24) <= ioctl_data;
                        when "01" => reg_word_latch(23 downto 16) <= ioctl_data;
                        when "10" => reg_word_latch(15 downto  8) <= ioctl_data;
                        when "11" => reg_word_latch(7  downto  0) <= ioctl_data;
                        when others => null;
                    end case;
                end if;
            else
                -- Geordneter Reset des Sammlers nach Beendigung des OSD-Downloads
                reg_byte_cnt   <= "00";
                reg_word_latch <= (others => '0');
            end if;
        end if;
    end process;

end behavioral;
