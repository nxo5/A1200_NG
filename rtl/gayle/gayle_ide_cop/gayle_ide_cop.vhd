-- =========================================================================
-- Projekt: A1200_NG
-- Ordner:  gayle_ide_cop
-- Datei:   gayle_ide_cop.vhd
-- Funktion: Der übergeordnete Sub-Top-Wrapper des IDE-Coprozessors.
--           Ermöglicht Quartus eine perfekte physische Routing-Gruppierung.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_ide_cop is
    Port (
        -- Takte und Reset von gayle_ide
        i_clk_sys           : in  std_logic; 
        i_rst_n             : in  std_logic; 
        
        -- Bus-Spione von gayle_ide
        i_as_n              : in  std_logic; 
        i_rw                : in  std_logic; 
        i_ide_reg_addr      : in  std_logic_vector(3 downto 0); -- Adressbits 5 downto 2
        i_current_phase     : in  std_logic_vector(1 downto 0); -- Phasenstatus der ATA-FSM
        
        -- Fertiger, timingsicherer Adressausgang zum BRAM-Sektorpuffer
        o_cop_sector_addr   : out std_logic_vector(8 downto 0)
    );
end gayle_ide_cop;

architecture structural of gayle_ide_cop is

    -- Schablone für den dedizierten Hardware-Zähler
    component gayle_ide_cop_cnt is
        Port (
            i_clk_sys           : in  std_logic;
            i_rst_n             : in  std_logic;
            i_as_n              : in  std_logic;
            i_rw                : in  std_logic;
            i_ide_reg_addr      : in  std_logic_vector(3 downto 0);
            i_current_phase     : in  std_logic_vector(1 downto 0);
            o_sector_ptr        : out unsigned(8 downto 0)
        );
    end component;

    signal s_internal_ptr : unsigned(8 downto 0);

begin

    -- Den berechneten Zeiger starr als Vektor nach außen an gayle_ide/BRAM ausgeben
    o_cop_sector_addr <= std_logic_vector(s_internal_ptr);

    -- Instanziierung des geschützten Hardware-Zählkerns
    u_gayle_ide_cop_cnt : gayle_ide_cop_cnt
        port map (
            i_clk_sys       => i_clk_sys,
            i_rst_n         => i_rst_n,
            i_as_n          => i_as_n,
            i_rw            => i_rw,
            i_ide_reg_addr  => i_ide_reg_addr,
            i_current_phase => i_current_phase,
            o_sector_ptr    => s_internal_ptr
        );

end structural;
