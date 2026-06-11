-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle.vhd
-- Funktion: Das strukturelle Gehäuse (Shell) des Gayle-Chips.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle is
    -- Keine physischen Ports nach außen (interne Kapselung).
end gayle;

architecture structural of gayle is

    -- =========================================================================
    -- KOMPONENTEN-DEKLARATIONEN (Klassischer, sicherer VHDL-Standard)
    -- =========================================================================
    component gayle_regs is
        Port (
            i_clk_sys    : in  std_logic;
            i_clk_cck    : in  std_logic;
            i_rst_n      : in  std_logic;
            i_as_n       : in  std_logic;
            i_rw         : in  std_logic;
            i_reg_addr   : in  std_logic_vector(15 downto 0);
            i_reg_data   : in  std_logic_vector(7 downto 0);
            o_reg_data   : out std_logic_vector(7 downto 0);
            i_ide_irq    : in  std_logic;
            i_pcmcia_irq : in  std_logic;
            o_gayle_irq  : out std_logic
        );
    end component;

    component gayle_ide is
        Port (
            i_clk_sys     : in  std_logic;
            i_rst_n       : in  std_logic;
            i_as_n        : in  std_logic;
            i_rw          : in  std_logic;
            i_ds_n        : in  std_logic_vector(1 downto 0);
            i_ide_addr    : in  std_logic_vector(5 downto 0);
            i_ide_data    : in  std_logic_vector(15 downto 0);
            o_ide_data    : out std_logic_vector(15 downto 0);
            o_ide_irq     : out std_logic
        );
    end component;

    component gayle_pcmcia is
        Port (
            i_clk_sys      : in  std_logic;
            i_rst_n        : in  std_logic;
            i_as_n         : in  std_logic;
            i_rw           : in  std_logic;
            i_pcm_addr     : in  std_logic_vector(15 downto 0);
            i_pcm_data     : in  std_logic_vector(7 downto 0);
            o_pcm_data     : out std_logic_vector(7 downto 0);
            o_pcmcia_irq   : out std_logic
        );
    end component;

    component gayle_reset is
        Port (
            i_clk_sys       : in  std_logic;
            i_clk_cck       : in  std_logic;
            i_rst_n         : in  std_logic;
            i_kbrst_n       : in  std_logic;
            o_sys_rst_n     : out std_logic
        );
    end component;

    -- =========================================================================
    -- INTERNE SIGNALE (Verdrahtung innerhalb des Gehäuses)
    -- =========================================================================
    signal s_clk_sys       : std_logic := '0';
    signal s_clk_cck       : std_logic := '0';
    signal s_master_rst_n  : std_logic := '1';
    
    signal s_bus_as_n      : std_logic := '1';
    signal s_bus_rw        : std_logic := '1';
    signal s_bus_ds_n      : std_logic_vector(1 downto 0) := "11";
    
    signal s_bus_addr      : std_logic_vector(23 downto 0) := (others => '0');
    signal s_bus_data_w32  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_bus_data_r32  : std_logic_vector(31 downto 0) := (others => '0');

    signal s_ide_irq       : std_logic;
    signal s_pcmcia_irq    : std_logic;
    signal s_gayle_global_irq : std_logic;
    
    signal s_kbrst_n       : std_logic := '1';
    signal s_generated_rst_n : std_logic;
    
    signal s_data_from_regs   : std_logic_vector(7 downto 0);
    signal s_data_from_ide    : std_logic_vector(15 downto 0);
    signal s_data_from_pcmcia : std_logic_vector(7 downto 0);

begin

    -- =========================================================================
    -- DATA ROUTING MULTIPLEXER
    -- =========================================================================
    process(s_bus_as_n, s_bus_rw, s_bus_addr, s_data_from_regs, s_data_from_ide, s_data_from_pcmcia)
    begin
        s_bus_data_r32 <= (others => '1');
        
        if s_bus_as_n = '0' and s_bus_rw = '1' then
            if s_bus_addr(23 downto 16) = x"DA" then
                case s_bus_addr(15 downto 12) is
                    when x"0" | x"1" | x"2" | x"3" =>
                        s_bus_data_r32(15 downto 0) <= s_data_from_ide;
                    when x"8" | x"9" | x"A" | x"B" =>
                        s_bus_data_r32(7 downto 0) <= s_data_from_regs;
                    when others =>
                        s_bus_data_r32(7 downto 0) <= s_data_from_pcmcia;
                end case;
            elsif s_bus_addr(23 downto 16) = x"DE" then
                s_bus_data_r32(7 downto 0) <= s_data_from_pcmcia;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- INSTANZEN DER UNTERMODULE
    -- =========================================================================

    -- 1. Register-Verwaltung
    u_gayle_regs : gayle_regs
        port map (
            i_clk_sys    => s_clk_sys,
            i_clk_cck    => s_clk_cck,
            i_rst_n      => s_generated_rst_n,
            i_as_n       => s_bus_as_n,
            i_rw         => s_bus_rw,
            i_reg_addr   => s_bus_addr(15 downto 0),
            i_reg_data   => s_bus_data_w32(7 downto 0),
            o_reg_data   => s_data_from_regs,
            i_ide_irq    => s_ide_irq,
            i_pcmcia_irq => s_pcmcia_irq,
            o_gayle_irq  => s_gayle_global_irq
        );

    -- 2. IDE/ATA-Controller
    u_gayle_ide : gayle_ide
        port map (
            i_clk_sys    => s_clk_sys,
            i_rst_n      => s_generated_rst_n,
            i_as_n       => s_bus_as_n,
            i_rw         => s_bus_rw,
            i_ds_n       => s_bus_ds_n,
            i_ide_addr   => s_bus_addr(5 downto 0),
            i_ide_data   => s_bus_data_w32(15 downto 0),
            o_ide_data   => s_data_from_ide,
            o_ide_irq    => s_ide_irq
        );

    -- 3. PCMCIA-Schnittstelle
    u_gayle_pcmcia : gayle_pcmcia
        port map (
            i_clk_sys    => s_clk_sys,
            i_rst_n      => s_generated_rst_n,
            i_as_n       => s_bus_as_n,
            i_rw         => s_bus_rw,
            i_pcm_addr   => s_bus_addr(15 downto 0),
            i_pcm_data   => s_bus_data_w32(7 downto 0),
            o_pcm_data   => s_data_from_pcmcia,
            o_pcmcia_irq => s_pcmcia_irq
        );

    -- 4. Reset-Logik
    u_gayle_reset : gayle_reset
        port map (
            i_clk_sys    => s_clk_sys,
            i_clk_cck    => s_clk_cck,
            i_rst_n      => s_master_rst_n,
            i_kbrst_n    => s_kbrst_n,
            o_sys_rst_n  => s_generated_rst_n
        );

end structural;
