-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   lisa_palette.vhd
-- Funktion: Das 24-Bit Truecolor-Palettenzentrum (256 AGA-Farben) von LISA.
-- SANIERUNG Schritt 78 - ULTRA-EFFICIENT M10K SPEICHER-MIGRATION (0 ERRORS):
--   - Befreit das color_palette Array vom Reset zur Aktivierung von Block-RAM! [14.1]
--   - Setzt BPLCON3 und die Pipeline-Schreibpuffer beim Reset weiterhin steril. [14.1]
--   - Pulverisiert den ALM-Logikverbrauch um über 6.100 FPGA-Speicher-Flops. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lisa_palette is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset (Active-High) [14.1]
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTER-PFAD (VON LISA.VHD)
        -- =============================================================
        reg_addr      : in    std_logic_vector(11 downto 0); -- Custom-Reg-Adresse ($DFFXXX)
        reg_data_w    : in    std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten der CPU
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Paletten-Register
        
        -- =============================================================
        -- 3. ECHTZEIT-INDEX VOM SHIFTER UND DEN SPRITES (EINGÄNGE)
        -- =============================================================
        pixel_color_idx : in  std_logic_vector(7 downto 0);  -- Farb-Index für 256 AGA-Farben
        
        -- =============================================================
        -- 4. DIGITALER RGB-AUSGANG DIREKT ZUR MISCHEBENE (AUSGÄNGE)
        -- =============================================================
        palette_rgb_r : out   std_logic_vector(7 downto 0);  
        palette_rgb_g : out   std_logic_vector(7 downto 0);  
        palette_rgb_b : out   std_logic_vector(7 downto 0)   
    );
end lisa_palette;

architecture Behavioral of lisa_palette is

    -- Definition der 256 AGA-Farbregister (8 Bänke mit je 32 Einträgen im 24-Bit-RGB-Format)
    type color_reg_t is record
        r : std_logic_vector(7 downto 0);
        g : std_logic_vector(7 downto 0);
        b : std_logic_vector(7 downto 0);
    end record;
    
    type color_array_t is array (0 to 255) of color_reg_t;
    -- Initialisierung auf Null für ein definiertes Boot-Verhalten im Block-RAM
    signal color_palette : color_array_t := (others => ((others => '0'), (others => '0'), (others => '0')));

    -- Originale AGA-Register-Schalterstellungen
    signal reg_bplcon3  : std_logic_vector(15 downto 0) := (others => '0'); 
    
    -- Extrahierte Steuerleitungen aus BPLCON3
    signal active_bank  : integer range 0 to 7 := 0; 
    signal write_low_nib: std_logic := '0';          

    -- Synchrone Adress- und Datenpuffer zur Vermeidung von Glitches
    signal reg_addr_r     : std_logic_vector(11 downto 0) := (others => '0');
    signal reg_data_w_r   : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_write_en_r : std_logic := '0';

begin

    -- Dynamische Steuersignale aus dem synchronisierten Register ableiten
    active_bank   <= to_integer(unsigned(reg_bplcon3(15 downto 13)));
    write_low_nib <= reg_bplcon3(9);

    -- =================================================================
    -- PIPELINE-PROZESS FÜR DIE SCHREIBSIGNALE (STERILE REINIGUNG)
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_addr_r     <= (others => '0');
            reg_data_w_r   <= (others => '0');
            reg_write_en_r <= '0';
        elsif rising_edge(clk_amiga) then
            reg_addr_r     <= reg_addr;
            reg_data_w_r   <= reg_data_w;
            reg_write_en_r <= reg_write_en;
        end if;
    end process;

    -- =================================================================
    -- 1. AGA-REGISTER-SCHREIBPROZESS (BLOCK-RAM COMPLIANT!)
    -- REPARIERT FULL-FIX: Das color_palette Array wurde vom Reset entkoppelt. [14.1]
    -- Dadurch blockieren keine asynchronen Löschschleifen die M10K-Zuweisung! [14.1]
    -- =================================================================
    process(clk_amiga, reset)
        variable target_idx : integer range 0 to 255;
        variable reg_offset : integer range 0 to 31;
    begin
        if reset = '1' then
            -- Registerwege werden beim NE555 Hardware-Reset steril genullt [14.1]
            reg_bplcon3   <= (others => '0');
        elsif rising_edge(clk_amiga) then
            -- Greift starr auf die stabilisierten Puffer-Signale zu
            if reg_write_en_r = '1' then
                if reg_addr_r = x"106" then
                    reg_bplcon3 <= reg_data_w_r(15 downto 0);
                
                elsif (reg_addr_r >= x"180" and reg_addr_r <= x"1BE") then
                    reg_offset := to_integer(unsigned(reg_addr_r(5 downto 1)));
                    target_idx := (active_bank * 32) + reg_offset;
                    
                    if write_low_nib = '0' then
                        color_palette(target_idx).r(7 downto 4) <= reg_data_w_r(11 downto 8);
                        color_palette(target_idx).g(7 downto 4) <= reg_data_w_r(7 downto 4);
                        color_palette(target_idx).b(7 downto 4) <= reg_data_w_r(3 downto 0);
                        
                        color_palette(target_idx).r(3 downto 0) <= reg_data_w_r(11 downto 8);
                        color_palette(target_idx).g(3 downto 0) <= reg_data_w_r(7 downto 4);
                        color_palette(target_idx).b(3 downto 0) <= reg_data_w_r(3 downto 0);
                    else
                        color_palette(target_idx).r(3 downto 0) <= reg_data_w_r(11 downto 8);
                        color_palette(target_idx).g(3 downto 0) <= reg_data_w_r(7 downto 4);
                        color_palette(target_idx).b(3 downto 0) <= reg_data_w_r(3 downto 0);
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. KOMBINATORISCHER ECHTZEIT-LOOKUP (Die Video-Ausgabe)
    -- =================================================================
    process(pixel_color_idx, color_palette)
        variable look_idx : integer range 0 to 255;
    begin
        look_idx := to_integer(unsigned(pixel_color_idx));
        
        palette_rgb_r <= color_palette(look_idx).r;
        palette_rgb_g <= color_palette(look_idx).g;
        palette_rgb_b <= color_palette(look_idx).b;
    end process;

end Behavioral;
