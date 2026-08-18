library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity copper_dec is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt von Alice
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTER-PFAD (VON COPPER.VHD)
        -- =============================================================
        reg_addr      : in    std_logic_vector(11 downto 0); -- Custom-Reg-Adresse ($DFFXXX)
        reg_data_w    : in    std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten der CPU
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Copper-Register
        
        -- =============================================================
        -- 3. INTERNE CO-PROZESSOR INTERFACES (VON/ZU COPPER_FSM.VHD)
        -- =============================================================
        dma_inst_word : in    std_logic_vector(31 downto 0); -- Das aktuelle Befehlswort aus dem RAM
        load_inst_en  : in    std_logic;                     -- FSM signalisiert: "Neues Wort decodieren!"
        
        -- Dekodierte Befehls-Typen zurück an das Kontrollwerk melden
        inst_is_move  : out   std_logic;                     
        inst_is_wait  : out   std_logic;                     
        inst_is_skip  : out   std_logic;                     
        
        -- Bereitgestellte Datenbahnen für den Ausführungsschritt
        move_target_reg: out  std_logic_vector(11 downto 0); 
        move_data_out  : out  std_logic_vector(15 downto 0); 
        move_illegal   : out  std_logic;                     
        
        -- Gekapselte Koordinaten-Bahnen direkt für die Synchronisations-Matrix
        wait_h_coord   : out  unsigned(8 downto 0);          
        wait_v_coord   : out  unsigned(8 downto 0);          
        wait_mask_h    : out  std_logic_vector(8 downto 0);  
        wait_mask_v    : out  std_logic_vector(8 downto 0);
        
        -- Pointer-Ausgänge zurück zur FSM für den Befehls-Fetch
        cop_active_pc  : out  unsigned(31 downto 0);         
        fsm_jump_trigger: out std_logic                      
    );
end copper_dec;

architecture Behavioral of copper_dec is

    -- Die originalen beiden 32-Bit Hardware-Programmlisten-Pointer des Amigas
    signal reg_cop1lc : unsigned(31 downto 0) := (others => '0'); 
    signal reg_cop2lc : unsigned(31 downto 0) := (others => '0'); 
    
    -- Das originale COPCON-Sicherheitsregister ($DFF08E)
    signal reg_copcon : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Der aktuelle operative interne Programmzähler des Coppers
    signal copper_pc  : unsigned(31 downto 0) := (others => '0');
    
    -- Interner Puffer für das geladene Instruktionswort
    signal instruction_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal int_jump_trig   : std_logic := '0';

    -- Hilfssignale für die Auswertung
    signal int_wait_h      : unsigned(8 downto 0);
    signal target_addr_raw : std_logic_vector(11 downto 0);

begin

    -- Die aktuelle Adresse für den Speicher-Fetch der FSM bereitstellen
    cop_active_pc    <= copper_pc;
    fsm_jump_trigger <= int_jump_trig;

    -- =================================================================
    -- 1. PHYSIKALISCHER CPU-REGISTERZUGRIFF UND PC-STEUERUNG
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_cop1lc      <= (others => '0');
            reg_cop2lc      <= (others => '0');
            reg_copcon      <= (others => '0');
            copper_pc       <= (others => '0');
            instruction_reg <= (others => '0');
            int_jump_trig   <= '0';
        elsif rising_edge(clk_amiga) then
            int_jump_trig <= '0'; 

            if reg_write_en = '1' then
                case reg_addr is
                    when x"080" => reg_cop1lc(31 downto 16) <= unsigned(reg_data_w(15 downto 0)); -- COP1LCH
                    when x"082" => reg_cop1lc(15 downto 0)  <= unsigned(reg_data_w(15 downto 0)); -- COP1LCL
                    when x"084" => reg_cop2lc(31 downto 16) <= unsigned(reg_data_w(15 downto 0)); -- COP2LCH
                    when x"086" => reg_cop2lc(15 downto 0)  <= unsigned(reg_data_w(15 downto 0)); -- COP2LCL
                    when x"08E" => reg_copcon               <= reg_data_w(15 downto 0);          -- COPCON
                    
                    when x"088" => 
                        copper_pc     <= reg_cop1lc; -- Strobel-Zündung: Springe auf Liste 1
                        int_jump_trig <= '1';
                    when x"08A" => 
                        copper_pc     <= reg_cop2lc; -- Strobel-Zündung: Springe auf Liste 2
                        int_jump_trig <= '1';
                    when others => null;
                end case;

            elsif load_inst_en = '1' then
                instruction_reg <= dma_inst_word;
                copper_pc       <= copper_pc + 4; -- Befehlszeiger um ein volles 32-Bit Longword vorrücken
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. ORIGINALGETREUER KOMBINATORISCHER BEFEHLS-DECODER
    -- =================================================================
    process(instruction_reg)
    begin
        inst_is_move <= '0'; inst_is_wait <= '0'; inst_is_skip <= '0';
        
        -- Bit 0 des ersten Befehlsworts bestimmt unbestechlich das Schicksal [14.1]
        if instruction_reg(0) = '0' then
            inst_is_move <= '1'; -- MOVE-Befehl deklariert
        else
            if instruction_reg(1) = '0' then
                inst_is_wait <= '1'; -- WAIT-Befehl deklariert
            else
                inst_is_skip <= '1'; -- SKIP-Befehl deklariert
            end if;
        end if;
    end process;

    -- =================================================================
    -- 3. REPARATUR: SIGNALAUSRICHTUNG NACH DEM ECHTEN CHIPSATZ-RASTER
    -- =================================================================
    -- KORREKTUR: Mappt die Registeradresse fehlerfrei unter Berücksichtigung der impliziten Geraden-Null (A0=0) [14.1]
	 target_addr_raw <= "000" & instruction_reg(8 downto 1) & '0';
    move_target_reg <= target_addr_raw;
    move_data_out   <= instruction_reg(31 downto 16); -- Die oberen 16 Bit enthalten die MOVE-Schreibdaten

    wait_v_coord <= unsigned(instruction_reg(15) & instruction_reg(15 downto 8)); -- V-Strahlabgleich (AGA-Ready)
    wait_mask_v     <= instruction_reg(15 downto 15) & instruction_reg(31 downto 24);
	 wait_mask_h     <= instruction_reg(23 downto 17) & "00"; -- Horizontale Maskierungs-Bits

    -- Saubere, prozessbasierte Zuweisung der horizontalen Strahlkoordinate
    process(instruction_reg)
    begin
        if instruction_reg(7 downto 2) = "000000" then
            int_wait_h <= (others => '0'); 
        else
				int_wait_h <= unsigned('0' & instruction_reg(7 downto 2) & "00");
        end if;
    end process;
    
    wait_h_coord <= int_wait_h;

    -- EISERNER HARDWARE-PROTEKTOR (COPCON PROTECTION-LOGIC)
    process(target_addr_raw, reg_copcon)
    begin
        -- Wenn COPCON Bit 1 gelöscht ist, darf der Copper NIEMALS in den gefährlichen 
        -- Registerbereich unterhalb von $DFF07E (Blitter, Gayle, CIAs) schreiben! [14.1]
        if unsigned(target_addr_raw) < x"07E" and reg_copcon(1) = '0' then
            move_illegal <= '1'; -- Harte Schreibblockade zünden!
        else
            move_illegal <= '0'; -- Freigabe erteilt
        end if;
    end process;

end Behavioral;
