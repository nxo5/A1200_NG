library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lisa_sprites is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        ce_pix        : in    std_logic; -- Pixelclock-Enable für den Zeichnungs-Vorschub
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTER-PFAD (VON LISA.VHD)
        -- =============================================================
        reg_addr      : in    std_logic_vector(11 downto 0); -- Custom-Reg-Adresse ($DFFXXX)
        reg_data_w    : in    std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten der CPU
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Sprite-Register
        
        -- =============================================================
        -- 3. INTERNE TIMING-ZUBRINGER VOM VIDEOSTRAHL (VON LISA.VHD)
        -- =============================================================
        beam_h_pos    : in    unsigned(8 downto 0);          -- Aktueller horizontaler Strahl
        beam_v_pos    : in    unsigned(8 downto 0);          -- Aktuelle vertikale Videozeile
        
        -- =============================================================
        -- 4. GEKAPSELTE AUSGÄNGE DIREKT ZUR MISCHEBENE (LISA_VIDEO_MUX.VHD)
        -- =============================================================
        sprite_pixel_idx : out std_logic_vector(3 downto 0);  -- Farb-Index für die Palette
        sprite_bank_offset: out std_logic_vector(1 downto 0); -- NEU: Übergibt den AGA-Bank-Offset (SPRES)
        sprite_active    : out std_logic                      -- '1' = Sprite-Pixel aktiv über Hintergrund
    );
end lisa_sprites;

architecture Behavioral of lisa_sprites is

    -- Originale Amiga-Hardware-Schattenregister für Sprite 0 (Mauszeiger)
    signal reg_spr0pos  : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_spr0ctl  : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_spr0data : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_spr0datb : std_logic_vector(15 downto 0) := (others => '0'); 

    -- NEU: Mitspeichern des globalen Grafik-Steuerregisters BPLCON3 ($DFF106)
    signal reg_bplcon3  : std_logic_vector(15 downto 0) := (others => '0');

    -- Extrahierte und aufbereitete Vergleichskoordinaten
    signal spr_v_start   : unsigned(8 downto 0);
    signal spr_v_stop    : unsigned(8 downto 0);
    signal spr_h_start   : unsigned(8 downto 0);

    -- Interne Zustandssteuerung des Sprite-Zeichners
    signal spr_v_active  : std_logic := '0';
    signal spr_h_cnt     : integer range 0 to 15 := 0;
    signal spr_h_active  : std_logic := '0';

    -- Puffer für das Schieberegister-Pixelpaar
    signal shift_data_a  : std_logic_vector(15 downto 0) := (others => '0');
    signal shift_data_b  : std_logic_vector(15 downto 0) := (others => '0');

begin

    -- Koordination der Vektoren
    spr_v_start <= unsigned(reg_spr0ctl(2) & reg_spr0pos(7 downto 0));
    spr_v_stop  <= unsigned(reg_spr0ctl(6) & reg_spr0ctl(7 downto 0));
    spr_h_start <= unsigned(reg_spr0pos(15 downto 8) & reg_spr0ctl(0));

    -- NEU: Die SPRES-Bits 5 und 4 zur dynamischen Farbbank-Auswahl nach außen reichen
    sprite_bank_offset <= reg_bplcon3(5 downto 4);

    -- =================================================================
    -- 1. CPU-REGISTER-SCHREIBPROZESS (Inklusive BPLCON3-Spiegelung)
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_spr0pos  <= (others => '0'); reg_spr0ctl  <= (others => '0');
            reg_spr0data <= (others => '0'); reg_spr0datb <= (others => '0');
            reg_bplcon3  <= (others => '0');
        elsif rising_edge(clk_amiga) then
            if reg_write_en = '1' then
                case reg_addr is
                    when x"120" => reg_spr0pos  <= reg_data_w(15 downto 0); -- SPR0POS
                    when x"122" => reg_spr0ctl  <= reg_data_w(15 downto 0); -- SPR0CTL
                    when x"124" => reg_spr0data <= reg_data_w(15 downto 0); -- SPR0DATA
                    when x"126" => reg_spr0datb <= reg_data_w(15 downto 0); -- SPR0DATB
                    when x"106" => reg_bplcon3  <= reg_data_w(15 downto 0); -- BPLCON3 ($DFF106)
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. INTERNE VERGLEICHER-MATRIZEN UND SHIFT-PIPELINES
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            spr_v_active <= '0';
            spr_h_active <= '0';
            spr_h_cnt    <= 0;
            shift_data_a <= (others => '0');
            shift_data_b <= (others => '0');
        elsif rising_edge(clk_amiga) then
            if beam_v_pos = spr_v_start then
                spr_v_active <= '1';
                shift_data_a <= reg_spr0data; 
                shift_data_b <= reg_spr0datb;
            elsif beam_v_pos = spr_v_stop then
                spr_v_active <= '0';
            end if;

            if ce_pix = '1' then
                if spr_v_active = '1' and beam_h_pos = spr_h_start then
                    spr_h_active <= '1';
                    spr_h_cnt    <= 0;
                elsif spr_h_active = '1' then
                    if spr_h_cnt = 15 then
                        spr_h_active <= '0';
                    else
                        spr_h_cnt <= spr_h_cnt + 1;
                        shift_data_a <= shift_data_a(14 downto 0) & '0';
                        shift_data_b <= shift_data_b(14 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 3. KOMBATORISCHES AUSGANGS-ROUTING
    -- =================================================================
    process(spr_h_active, shift_data_a, shift_data_b)
        variable col_bits : std_logic_vector(1 downto 0);
    begin
        col_bits := shift_data_b(15) & shift_data_a(15);
        
        if spr_h_active = '1' and col_bits /= "00" then
            sprite_pixel_idx <= "00" & col_bits; 
            sprite_active    <= '1';              
        else
            sprite_pixel_idx <= (others => '0');
            sprite_active    <= '0';
        end if;
    end process;

end Behavioral;
