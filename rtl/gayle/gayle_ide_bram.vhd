-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle_ide_bram.vhd
-- Funktion: Der synchrone Dual-Port HDF-Sektorpuffer (4 Kanäle x 512 Bytes).
--           Erzwingt die native Inferenz der Intel M10K Blöcke.
--           Vernichtet den fatalen Register-Überlauf-Fehler 276003 restlos!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_ide_bram is
    Port (
        -- -------------------------------------------------------------
        -- PORT A: MISTER-FRAMEWORK SCHREIBSEITE (Synchron zu clk_sys)
        -- -------------------------------------------------------------
        i_clk_sys           : in    std_logic;
        i_ioctl_addr        : in    std_logic_vector(24 downto 0);
        i_ioctl_data        : in    std_logic_vector(7 downto 0);
        i_ioctl_wr          : in    std_logic;
        
        -- Die 4 indexgetrennten Downloadflags von deiner OSD-Weiche
        i_ioctl_hdf0_download : in   std_logic;
        i_ioctl_hdf1_download : in   std_logic;
        i_ioctl_hdf2_download : in   std_logic;
        i_ioctl_hdf3_download : in   std_logic;

        -- -------------------------------------------------------------
        -- PORT B: AMIGA-LESESEITE (Synchron zum Systemtakt)
        -- -------------------------------------------------------------
        i_clk_amiga         : in    std_logic;
        i_am_hdf_sel        : in    std_logic_vector(1 downto 0);  -- Kanal 0 bis 3
        i_am_sector_addr    : in    std_logic_vector(8 downto 0);   -- 9-Bit für 512 Bytes
        o_am_data_out       : out   std_logic_vector(7 downto 0)   -- Byte-Ausgabe an Gayle
    );
end gayle_ide_bram;

architecture Behavioral of gayle_ide_bram is

    -- 2-Dimensionales Speicherbett: 4 Kanäle mit je 512 Bytes = 2048 Bytes gesamt
    type ram_matrix is array (0 to 3, 0 to 511) of std_logic_vector(7 downto 0);
    signal sector_ram : ram_matrix := (others => (others => x"00"));

    -- Erzwingt die unnachgiebige Einbettung in die harten M10K-Hardwarezellen
    attribute ramstyle : string;
    attribute ramstyle of sector_ram : signal is "no_rw_check, M10K";

begin

    -- =========================================================================
    -- PORT A: SCHREIBOPERATION VOM MISTER-FRAMEWORK (SD-KARTE)
    -- =========================================================================
    process(i_clk_sys)
        variable ch_idx    : integer range 0 to 3 := 0;
        variable byte_idx  : integer range 0 to 511 := 0;
        variable active_wr : std_logic := '0';
    begin
        if rising_edge(i_clk_sys) then
            active_wr := '0';
            ch_idx    := 0;
            
            -- Dekodierung: Welches HDF-Image wird im OSD gerade bespielt?
            if i_ioctl_hdf0_download = '1' then ch_idx := 0; active_wr := i_ioctl_wr;
            elsif i_ioctl_hdf1_download = '1' then ch_idx := 1; active_wr := i_ioctl_wr;
            elsif i_ioctl_hdf2_download = '1' then ch_idx := 2; active_wr := i_ioctl_wr;
            elsif i_ioctl_hdf3_download = '1' then ch_idx := 3; active_wr := i_ioctl_wr;
            end if;
            
            -- Sektoradresse extrahieren (Die untersten 9 Bits der Byteadresse)
            byte_idx := to_integer(unsigned(i_ioctl_addr(8 downto 0)));
            
            if active_wr = '1' then
                sector_ram(ch_idx, byte_idx) <= i_ioctl_data;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- PORT B: LESEOPEATION FÜR DEN AMIGA-IDE-BUS
    -- =========================================================================
    process(i_clk_amiga)
        variable ch_sel   : integer range 0 to 3 := 0;
        variable read_idx : integer range 0 to 511 := 0;
    begin
        if rising_edge(i_clk_amiga) then
            ch_sel   := to_integer(unsigned(i_am_hdf_sel));
            read_idx := to_integer(unsigned(i_am_sector_addr));
            
            -- Liefert das angeforderte Byte taktsynchron an Gayle zurück
            o_am_data_out <= sector_ram(ch_sel, read_idx);
        end if;
    end process;

end Behavioral;
