-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   turbo_clk.vhd
-- Funktion: Der separate Takt-Manager (Clock Unit) der Turbokarte.
--           Nimmt die 14,14 MHz von Alice und bereitet das 4x-Skelett vor.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity turbo_clk is
    Port (
        clk_in_14m  : in    std_logic;  -- Originaler Systemtakt von Alice
        clk_out_56m : out   std_logic   -- Multiplizierter CPU-Takt für den Core
    );
end turbo_clk;

architecture behavioral of turbo_clk is

    -- Hier wird später die FPGA-eigene PLL (Phase-Locked Loop) eingebettet,
    -- um aus den 14,14 MHz absolut phasenstarre 56,56 MHz zu erzeugen.

begin

    -- Provisorischer Takt-Dummy für diese Synthesephase:
    -- Reicht den Takt vorerst direkt durch, damit Quartus terminieren kann.
    clk_out_56m <= clk_in_14m;

end behavioral;
