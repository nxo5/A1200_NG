library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- use work.M68020_pkg.all;

entity lisa is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE (VON DER HAUPTPLATINE)
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        ce_pix        : in    std_logic; -- Pixelclock-Enable für den Zeichnungs-Vorschub
        
        -- =============================================================
        -- 2. INTERNES REGISTER-INTERFACE (VON DER SYSTEM-WEICHE)
        -- =============================================================
        am_addr       : in    std_logic_vector(11 downto 0); -- Custom-Registeradresse
        am_data_w     : in    std_logic_vector(31 downto 0); -- Schreibdaten der CPU/Copper
        am_reg_write  : in    std_logic;                     -- Register-Schreibimpuls
        
        -- =============================================================
        -- 3. INTERNE GRAPHIK- UND TIMING-ZUBRINGER (EINGÄNGE)
        -- =============================================================
        beam_h_pos    : in    unsigned(8 downto 0);          
        beam_v_pos    : in    unsigned(8 downto 0);          
        hblank        : in    std_logic;                     
        vblank        : in    std_logic;                     
        
        bpl_data_in   : in    std_logic_vector(31 downto 0); 
        bpl_chan_load : in    std_logic_vector(2 downto 0);  
        bpl_write_en  : in    std_logic;                     
        
        -- =============================================================
        -- 4. FINALER DIGITALER TRUECOLOR-AUSGANGSBUS (ZUM VIDEO-DAC)
        -- =============================================================
        vid_rgb_r     : out   std_logic_vector(7 downto 0);  -- 8 Bit Rot
        vid_rgb_g     : out   std_logic_vector(7 downto 0);  -- 8 Bit Grün
        vid_rgb_b     : out   std_logic_vector(7 downto 0)   -- 8 Bit Blau
    );
end lisa;

architecture Behavioral of lisa is

    -- -----------------------------------------------------------------
    -- DEKLARATION DER VIER INTERNEN LISA-FUNKTIONSBLÖCKE
    -- -----------------------------------------------------------------
    component lisa_palette is
        Port (
            clk_amiga       : in    std_logic;
            reset           : in    std_logic;
            reg_addr        : in    std_logic_vector(11 downto 0);
            reg_data_w      : in    std_logic_vector(31 downto 0);
            reg_write_en    : in    std_logic;
            pixel_color_idx : in    std_logic_vector(7 downto 0);
            palette_rgb_r   : out   std_logic_vector(7 downto 0);
            palette_rgb_g   : out   std_logic_vector(7 downto 0);
            palette_rgb_b   : out   std_logic_vector(7 downto 0)
        );
    end component;

    component lisa_shifter is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            ce_pix        : in    std_logic;
            reg_addr      : in    std_logic_vector(11 downto 0);
            reg_data_w    : in    std_logic_vector(31 downto 0);
            reg_write_en  : in    std_logic;
            bpl_data_in   : in    std_logic_vector(31 downto 0);
            bpl_chan_load : in    std_logic_vector(2 downto 0);
            bpl_write_en  : in    std_logic;
            hblank        : in    std_logic;
            vblank        : in    std_logic;
            bpl_pixel_idx : out   std_logic_vector(7 downto 0)
        );
    end component;

    component lisa_sprites is
        Port (
            clk_amiga        : in    std_logic;
            reset            : in    std_logic;
            ce_pix           : in    std_logic;
            reg_addr         : in    std_logic_vector(11 downto 0);
            reg_data_w       : in    std_logic_vector(31 downto 0);
            reg_write_en     : in    std_logic;
            beam_h_pos       : in    unsigned(8 downto 0);
            beam_v_pos       : in    unsigned(8 downto 0);
            sprite_pixel_idx : out   std_logic_vector(3 downto 0);
            sprite_bank_offset: out  std_logic_vector(1 downto 0); -- Neu deklariert
            sprite_active    : out   std_logic
        );
    end component;

    component lisa_video_mux is
        Port (
            reg_addr         : in    std_logic_vector(11 downto 0);
            reg_data_w       : in    std_logic_vector(31 downto 0);
            reg_write_en     : in    std_logic;
            bpl_pixel_idx    : in    std_logic_vector(7 downto 0);
            sprite_pixel_idx : in    std_logic_vector(3 downto 0);
            sprite_active    : in    std_logic;
            sprite_bank_offset: in   std_logic_vector(1 downto 0); -- Neu deklariert
            final_color_idx  : out   std_logic_vector(7 downto 0);
            hblank           : in    std_logic;
            vblank           : in    std_logic
        );
    end component;

    -- -----------------------------------------------------------------
    -- CHIPINTERNE GRAPHIKBAHNEN (SIGNALE)
    -- -----------------------------------------------------------------
    signal int_bpl_pixel_idx   : std_logic_vector(7 downto 0);
    signal int_sprite_pixel_idx : std_logic_vector(3 downto 0);
    signal int_sprite_active    : std_logic;
    
    -- NEU: Interne Kupferader zur Weiterleitung der SPRES-Banksteuerung
    signal int_sprite_bank_offset: std_logic_vector(1 downto 0);
    
    signal int_final_color_idx : std_logic_vector(7 downto 0);

begin

    -- =================================================================
    -- CHIP-INTERNE VERDRAHTUNG (PORT MAPS)
    -- =================================================================
    
    -- Block 1: Der Bitplane-Serializer und Datenpuffer
    u_lisa_shifter : lisa_shifter
    port map (
        clk_amiga     => clk_amiga,
        reset         => reset,
        ce_pix        => ce_pix,
        reg_addr      => am_addr,
        reg_data_w    => am_data_w,
        reg_write_en  => am_reg_write,
        bpl_data_in   => bpl_data_in,
        bpl_chan_load => bpl_chan_load,
        bpl_write_en  => bpl_write_en,
        hblank        => hblank,
        vblank        => vblank,
        bpl_pixel_idx => int_bpl_pixel_idx
    );

    -- Block 2: Der Sprite-Generator (Erweitert um AGA-Offset)
    u_lisa_sprites : lisa_sprites
    port map (
        clk_amiga         => clk_amiga,
        reset             => reset,
        ce_pix            => ce_pix,
        reg_addr          => am_addr,
        reg_data_w        => am_data_w,
        reg_write_en      => am_reg_write,
        beam_h_pos        => beam_h_pos,
        beam_v_pos        => beam_v_pos,
        sprite_pixel_idx  => int_sprite_pixel_idx,
        sprite_bank_offset => int_sprite_bank_offset, -- Neu verdrahtet
        sprite_active     => int_sprite_active
    );

    -- Block 3: Die Ausgabe-Mischebene (Erweitert um AGA-Offset)
    u_lisa_video_mux : lisa_video_mux
    port map (
        reg_addr           => am_addr,
        reg_data_w         => am_data_w,
        reg_write_en       => am_reg_write,
        bpl_pixel_idx      => int_bpl_pixel_idx,
        sprite_pixel_idx   => int_sprite_pixel_idx,
        sprite_active      => int_sprite_active,
        sprite_bank_offset => int_sprite_bank_offset, -- Neu verdrahtet
        final_color_idx    => int_final_color_idx,
        hblank             => hblank,
        vblank             => vblank
    );

    -- Block 4: Das Farb-Rechenzentrum
    u_lisa_palette : lisa_palette
    port map (
        clk_amiga       => clk_amiga,
        reset           => reset,
        reg_addr        => am_addr,
        reg_data_w      => am_data_w,
        reg_write_en    => am_reg_write,
        pixel_color_idx => int_final_color_idx,
        palette_rgb_r   => vid_rgb_r,
        palette_rgb_g   => vid_rgb_g,
        palette_rgb_b   => vid_rgb_b
    );

end Behavioral;
