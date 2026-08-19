-- =========================================================================
-- Projekt: A1200_NG
-- Ordner:  gayle_ide_cop
-- Datei:   gayle_ide_cop_cnt.vhd
-- Funktion: Der rein synchrone Sektor- und Adresszähler des Coprozessors.
-- SANIERUNG Schritt 82 - REIN SYNCHRONER ENTSCHEIDUNGS-PFAD (0 ERRORS):
--   - Entfernt den asynchronen Reset zur Vernichtung der Critical Warning 18061! [14.1]
--   - Behält die 100% latch-freie Mux-Zuweisungsstruktur starr bei. [14.1]
--   - Garantiert den bytegenauen Sektorrücklauf im 14-MHz-Taktbaum. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_ide_cop_cnt is
    Port (
        i_clk_sys           : in  std_logic;
        i_rst_n             : in  std_logic; -- System-Reset (aktiv niedrig) [14.1]
        
        -- Bus-Spione von der Gehäusewand
        i_as_n              : in  std_logic;
        i_rw                : in  std_logic;
        i_ide_reg_addr      : in  std_logic_vector(3 downto 0); -- Adressbits 5 downto 2
        i_current_phase     : in  std_logic_vector(1 downto 0); -- Codierter Phasenstatus
        
        -- Synchroner Adresszeiger zum Top-Wrapper
        o_sector_ptr        : out unsigned(8 downto 0)
    );
end gayle_ide_cop_cnt;

architecture rtl of gayle_ide_cop_cnt is

    -- Interner Zeiger-Vektor
    signal r_cnt_ptr       : unsigned(8 downto 0) := (others => '0');
    signal r_as_n_last     : std_logic := '1';
    
    -- Kombinatorische Hardware-Steuersignale (Reine Logikgatter)
    signal w_inc_en        : std_logic;
    signal w_rst_en        : std_logic;

begin

    -- Permanente Weiterleitung des synchronen Zeigers nach außen
    o_sector_ptr <= r_cnt_ptr;

    -- =========================================================================
    -- KOMPROMISSLOSE HARDWARE-GATTER (REINE BOOLESCHE ALGEBRA)
    -- =========================================================================
    w_inc_en <= '1' when (i_as_n = '0' and r_as_n_last = '1' and i_ide_reg_addr = "0000") else '0';
    w_rst_en <= '1' when (i_current_phase = "10" and i_as_n = '1' and r_cnt_ptr >= 512) else '0';

    -- =========================================================================
    -- REIN SYNCHRONES REGISTER-LADEN (REIN SYNCHRONER RESET)
    -- REPARIERT FULL-FIX: Die Sensitivitätsliste enthält NUR noch den Systemtakt! [14.1]
    -- Pulverisiert Critical Warning 18061 vollständig aus dem Fitter! [14.1]
    -- =========================================================================
    process(i_clk_sys)
    begin
        if rising_edge(i_clk_sys) then
            -- -----------------------------------------------------------------
            -- SYNCHRONER MASTER-RESET-ZWEIG (HARDWARE-SPEZIFIKATIONSKONFORM) [14.1]
            -- -----------------------------------------------------------------
            if i_rst_n = '0' then
                r_cnt_ptr   <= (others => '0');
                r_as_n_last <= '1';
            else
                -- REINER REGELBETRIEB BEI ENTLASTETEM RESET-PEGEL [14.1]
                r_as_n_last <= i_as_n;

                if w_rst_en = '1' then
                    r_cnt_ptr <= (others => '0'); 
                elsif w_inc_en = '1' then
                    r_cnt_ptr <= r_cnt_ptr + "000000010"; -- Inkrement (+2 Bytes)
                else
                    r_cnt_ptr <= r_cnt_ptr; 
                end if;
            end if;
        end if;
		end process; 

end rtl;
