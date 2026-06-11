-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_alu_regs.vhd
-- Teil:    1 von 2 (Entity und SFC/DFC Register-Deklaration)
-- Funktion: Die zentrale Hauptregisterbank des 68EC030 (D0-D7, A0-A7).
--           PUNKT 2: Vollständiger Ausbau der 3-Bit Motorola Sonderregister
--                    SFC (Source Function Code) und DFC (Destination Function Code)
--                    für unbestechliche MOVES/MOVEC-Kompatibilität!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_alu_regs is
    Port (
        -- Takt und System-Zustand
        CLK             : in    std_logic;
        RESET_N         : in    std_logic;

        -- Schnittstelle zum Steuerwerk / Decoder
        reg_src_sel     : in    std_logic_vector(3 downto 0);  -- Quellregister (Bit 3: 0=Dn, 1=An)
        reg_dst_sel     : in    std_logic_vector(3 downto 0);  -- Zielregister  (Bit 3: 0=Dn, 1=An)
        reg_size        : in    std_logic_vector(1 downto 0);  -- Operationsbreite (00=B, 01=W, 10=L)
        
        -- Fortschaltung des Programmzählers (PC)
        pc_advance      : in    std_logic;                      
        pc_load         : in    std_logic;                      
        pc_new_val      : in    std_logic_vector(31 downto 0);  
        
        -- Synchrone Write-Back-Schnittstelle vom Rechenkern
        wb_en           : in    std_logic;                      
        wb_data         : in    std_logic_vector(31 downto 0);  
        wb_flags        : in    std_logic_vector(15 downto 0);  
        wb_flags_en     : in    std_logic;                      
        
        -- NEU PUNKT 2: MOVEC-Schreibkanäle für die Steuerregister SFC und DFC
        ctrl_sfc_wren   : in    std_logic;                      -- '1' = Schreibt Steuerdaten in das SFC
        ctrl_dfc_wren   : in    std_logic;                      -- '1' = Schreibt Steuerdaten in das DFC
        ctrl_reg_data   : in    std_logic_vector(2 downto 0);   -- Die vom Core anzulegenden 3-Bit Funktionscodes
        
        -- Universelle Hardware-Schnittstelle von der Master-Ablaufsteuerung (FSM)
        boot_pc_load    : in    std_logic;                      
        boot_pc_new     : in    std_logic_vector(31 downto 0);  
        fsm_a7_load     : in    std_logic;                      
        fsm_a7_new      : in    std_logic_vector(31 downto 0);  
        
        -- Direkte, parallele Ausgangsdaten an den mathematischen Rechenkern / MUX
        src_val_out     : out   std_logic_vector(31 downto 0);  
        dst_val_out     : out   std_logic_vector(31 downto 0);  
        pc_val_out      : out   std_logic_vector(31 downto 0);  
        flags_val_out   : out   std_logic_vector(4 downto 0);
        
        -- NEU PUNKT 2: Parallele 3-Bit-Ausgänge für das Bus-Weichenwerk (FC-Modulation)
        sfc_val_out     : out   std_logic_vector(2 downto 0);   -- Aktueller Inhalt SFC
        dfc_val_out     : out   std_logic_vector(2 downto 0)    -- Aktueller Inhalt DFC
    );
end cpu_030_ec_alu_regs;

architecture behavioral of cpu_030_ec_alu_regs is
    type reg_array is array (0 to 7) of unsigned(31 downto 0);
    signal reg_D : reg_array := (others => (others => '0')); 
    signal reg_A : reg_array := (others => (others => '0')); 

    signal reg_USP  : unsigned(31 downto 0) := (others => '0'); 
    signal reg_ISP  : unsigned(31 downto 0) := (others => '0'); 
    signal reg_MSP  : unsigned(31 downto 0) := (others => '0'); 

    signal reg_PC : unsigned(31 downto 0) := x"00000000";   
    signal reg_SR : std_logic_vector(15 downto 0) := x"2700"; 

    -- NEU PUNKT 2: Die beiden unbestechlichen 3-Bit Motorola Sonderregister
    signal reg_SFC : std_logic_vector(2 downto 0) := "000";     -- Source Function Code Register
    signal reg_DFC : std_logic_vector(2 downto 0) := "000";     -- Destination Function Code Register

    signal flag_S   : std_logic;
    signal flag_M   : std_logic;

begin

    flag_S <= reg_SR(13); 
    flag_M <= reg_SR(12); 

    -- PUNKT 2: Die aktuellen Inhalte der Sonderregister permanent für den Bus-Muxer spiegeln
    sfc_val_out <= reg_SFC;
    dfc_val_out <= reg_DFC;

    -- =====================================================================
    -- COMBINATORIAL REGISTER READ: Unbestechlicher Drei-Wege-A7-Muxer
    -- =====================================================================
    process(reg_src_sel, reg_dst_sel, reg_D, reg_A, reg_PC, reg_SR, 
            reg_USP, reg_ISP, reg_MSP, flag_S, flag_M)
        variable idx_src : integer range 0 to 7;
        variable idx_dst : integer range 0 to 7;
        variable active_A7 : unsigned(31 downto 0);
    begin
        idx_src := to_integer(unsigned(reg_src_sel(2 downto 0)));
        idx_dst := to_integer(unsigned(reg_dst_sel(2 downto 0)));

        if flag_S = '0' then
            active_A7 := reg_USP; 
        elsif flag_M = '1' then
            active_A7 := reg_MSP; 
        else
            active_A7 := reg_ISP; 
        end if;

        if reg_src_sel(3) = '0' then
            src_val_out <= std_logic_vector(reg_D(idx_src));
        else
            if idx_src = 7 then
                src_val_out <= std_logic_vector(active_A7);
            else
                src_val_out <= std_logic_vector(reg_A(idx_src));
            end if;
        end if;

        if reg_dst_sel(3) = '0' then
            dst_val_out <= std_logic_vector(reg_D(idx_dst));
        else
            if idx_dst = 7 then
                dst_val_out <= std_logic_vector(active_A7);
            else
                dst_val_out <= std_logic_vector(reg_A(idx_dst));
            end if;
        end if;
        
        pc_val_out    <= std_logic_vector(reg_PC);
        flags_val_out <= reg_SR(4 downto 0);
    end process;

    -- =====================================================================
    -- SYNCHRONOUS PROCESS: Registerschreiben mitsamt SFC/DFC-Einzug
    -- =====================================================================
    process(CLK, RESET_N)
        variable idx_dst : integer range 0 to 7;
    begin
        if RESET_N = '0' then
            reg_D   <= (others => (others => '0'));
            reg_A   <= (others => (others => '0'));
            reg_USP <= (others => '0');
            reg_ISP <= x"00F80000"; 
            reg_MSP <= (others => '0');
            reg_PC  <= x"00F80000"; 
            reg_SR  <= x"2700";    
            reg_SFC <= "000"; -- Reset starr auf User-Code-Space
            reg_DFC <= "000"; -- Reset starr auf User-Code-Space
            
        elsif rising_edge(CLK) then
            idx_dst := to_integer(unsigned(reg_dst_sel(2 downto 0)));

            -- 1. Programmzähler-Fortschaltung
            if boot_pc_load = '1' then
                reg_PC <= unsigned(boot_pc_new);
            elsif pc_load = '1' then
                reg_PC <= unsigned(pc_new_val);
            elsif pc_advance = '1' then
                reg_PC <= reg_PC + 2;
            end if;

            -- 2. PUNKT 2: Privilegierter MOVEC-Einzug für SFC und DFC
            if flag_S = '1' then -- Eiserner Supervisor-Schutzbelag
                if ctrl_sfc_wren = '1' then
                    reg_SFC <= ctrl_reg_data;
                end if;
                if ctrl_dfc_wren = '1' then
                    reg_DFC <= ctrl_reg_data;
                end if;
            end if;

            -- 3. Dynamische A7-Modulation via FSM
            if fsm_a7_load = '1' then
                if flag_S = '0' then
                    reg_USP <= unsigned(fsm_a7_new);
                elsif flag_M = '1' then
                    reg_MSP <= unsigned(fsm_a7_new);
                else
                    reg_ISP <= unsigned(fsm_a7_new);
                end if;
            end if;

            -- 4. Operanden-Writeback vom Rechenkern
            if wb_en = '1' then
                if reg_dst_sel(3) = '0' then
                    if reg_size = "10" then
                        reg_D(idx_dst) <= unsigned(wb_data);
                    elsif reg_size = "01" then
                        reg_D(idx_dst)(15 downto 0) <= unsigned(wb_data(15 downto 0));
                    else
                        reg_D(idx_dst)(7 downto 0) <= unsigned(wb_data(7 downto 0));
                    end if;
                else
                    if idx_dst /= 7 then
                        reg_A(idx_dst) <= unsigned(wb_data);
                    else
                        if fsm_a7_load = '0' then
                            if flag_S = '0' then
                                reg_USP <= unsigned(wb_data);
                            elsif flag_M = '1' then
                                reg_MSP <= unsigned(wb_data);
                            else
                                reg_ISP <= unsigned(wb_data);
                            end if;
                        end if;
                    end if;
                end if;
            end if;

            -- 5. Statusregister (SR) / CCR Flags
            if boot_pc_load = '1' and fsm_a7_load = '1' then
                reg_SR(15 downto 12) <= wb_flags(15 downto 12); 
                reg_SR(10 downto 8)  <= wb_flags(10 downto 8);  
            elsif wb_flags_en = '1' then
                if reg_dst_sel(3) = '0' then
                    reg_SR(15 downto 5) <= wb_flags(15 downto 5);
                    reg_SR(4 downto 0)  <= wb_flags(4 downto 0);
                else
                    reg_SR(15 downto 5) <= wb_flags(15 downto 5);
                end if;
            end if;

        end if;
    end process;

end behavioral;
