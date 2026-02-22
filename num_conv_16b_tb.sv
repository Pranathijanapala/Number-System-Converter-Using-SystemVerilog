// ============================================================
//  num_conv_16b_tb.sv
//  Interactive 16-bit Number Conversion Calculator
//  Corrected Version -- All 5 bugs fixed
//  Simulators : ModelSim / QuestaSim / VCS / Icarus Verilog
// ============================================================

module num_conv_16b_tb;

  // -- Bug 4 Fix: portable stdin handle ---------------------
  localparam integer STDIN = 32'h8000_0000;

  // -- ALL variables at MODULE level -------------------------
  // ModelSim 2020 does NOT allow variable declarations
  // inside procedural (initial) blocks -- must be here.
  logic [15:0]  v;           // 16-bit working vector
  string        line;        // raw input line buffer
  string        sign_type;   // "signed" or "unsigned"
  string        in_type;     // input format string
  string        num_str;     // number string typed by user
  string        out_type;    // output format string
  int           base;        // numeric base (2/8/10/16)
  longint signed parsed;     // wide enough for range check
  bit           ok;          // loop control flag

  // ============================================================
  //  HELPER FUNCTION 1: Strip trailing newline / carriage return
  // ============================================================
  // ============================================================
  //  HELPER FUNCTION 1: Strip newline, CR, and spaces
  //  Fix: trailing spaces after input caused match failures
  // ============================================================
  function automatic void strip_and_trim(ref string s);
    if (s.len() > 0 && s.getc(s.len()-1) == "\n")
      s = s.substr(0, s.len()-2);
    if (s.len() > 0 && s.getc(s.len()-1) == "\r")
      s = s.substr(0, s.len()-2);
    while (s.len() > 0 && s.getc(s.len()-1) == " ")
      s = s.substr(0, s.len()-2);
    while (s.len() > 0 && s.getc(0) == " ")
      s = s.substr(1, s.len()-1);
  endfunction

  // ============================================================
  //  HELPER FUNCTION: Detect exit commands
  // ============================================================
  function automatic bit is_exit(string s);
    s = s.tolower();
    return (s == "exit" || s == "quit" || s == "q" || s == "bye");
  endfunction

  // ============================================================
  //  HELPER FUNCTION 2: Get numeric base from type string
  //  Returns: 2=binary, 8=octal, 10=decimal, 16=hex, -1=invalid
  // ============================================================
  function automatic int base_from_type(string t);
    t = t.tolower();
    if (t == "bin" || t == "binary")                    return 2;
    if (t == "oct" || t == "octa" || t == "octal")      return 8;
    if (t == "hex" || t == "hexa" || t == "hexadecimal")return 16;
    if (t == "dec" || t == "decimal")                   return 10;
    return -1;
  endfunction

  // ============================================================
  //  HELPER FUNCTION 3: Validate output format choice
  // ============================================================
  function automatic bit valid_out_choice(string o);
    o = o.tolower();
    return ( o == "bin" || o == "binary"       ||
             o == "oct" || o == "octa"         ||
             o == "octal"                      ||
             o == "hex" || o == "hexa"         ||
             o == "hexadecimal"                ||
             o == "dec" || o == "decimal"      ||
             o == "all" );
  endfunction

  // ============================================================
  //  TASK: Print conversion results
  //  Bug 3 Fix: unsigned_dec changed to int unsigned
  //             shortint used for signed_dec (exact 16-bit match)
  // ============================================================
  task automatic print_results(
    input logic [15:0] v,
    input bit          treat_as_signed,
    input string       outsel
  );
    // Fix: use longint to safely hold 0..65535 unsigned
    // and shortint for -32768..32767 signed
    longint  unsigned_dec;   // holds 0..65535 without sign issues
    shortint signed_dec;     // 16-bit signed exact match

    unsigned_dec = {16'b0, v};   // zero-extend: safe 0..65535
    signed_dec   = shortint'(v); // reinterpret bits as signed

    outsel = outsel.tolower();

    $display("");
    $display("  +------------------------------------------+");
    $display("  |           CONVERSION RESULTS             |");
    $display("  +------------------------------------------+");

    if (outsel == "all") begin
      $display("  |  BIN  : %016b              |", v);
      $display("  |  OCT  : %06o                        |", v);
      $display("  |  HEX  : %04H                          |", v);
      $display("  |  UDEC : %-5d                          |", unsigned_dec);
      $display("  |  SDEC : %-6d                         |", signed_dec);
    end
    else if (outsel == "bin" || outsel == "binary") begin
      if (treat_as_signed)
        $display("  |  * BIN (signed)  : %016b  |", v);
      else
        $display("  |  * BIN (unsigned): %016b  |", v);
    end
    else if (outsel == "oct" || outsel == "octa" || outsel == "octal") begin
      $display("  |  * OCT : %06o                        |", v);
    end
    else if (outsel == "hex" || outsel == "hexa" || outsel == "hexadecimal") begin
      $display("  |  * HEX : %04H                          |", v);
    end
    else if (outsel == "dec" || outsel == "decimal") begin
      // Show priority output first based on signed/unsigned flag
      if (treat_as_signed) begin
        $display("  |  * SDEC (priority): %-6d             |", signed_dec);
        $display("  |    UDEC (also)    : %-5d              |", unsigned_dec);
      end else begin
        $display("  |  * UDEC (priority): %-5d              |", unsigned_dec);
        $display("  |    SDEC (also)    : %-6d             |", signed_dec);
      end
    end

    $display("  +------------------------------------------+");
    $display("");
  endtask

  // ============================================================
  //  TASK: Print separator line
  // ============================================================
  task print_separator();
    $display("  ============================================================");
  endtask

  // ============================================================
  //  MAIN INITIAL BLOCK
  //  Bug 1 Fix: ALL variable declarations moved to TOP of block
  //  Bug 2 Fix: logic'() cast replaced with parsed[15:0] slice
  //  Bug 4 Fix: stdin replaced with STDIN localparam
  // ============================================================
  initial begin

    // -- Startup banner ---------------------------------------
    print_separator();
    $display("       16-BIT NUMBER SYSTEM CONVERTER");
    $display("       Designed in SystemVerilog (Simulation)");
    $display("       Unsigned Range : 0 to 65535");
    $display("       Signed Range   : -32768 to 32767");
    print_separator();

    // ========================================================
    //  MAIN LOOP -- repeats until user types 'n'
    // ========================================================
    forever begin

      // -- STEP 1: Ask signed / unsigned ----------------------
      ok = 0;
      while (!ok) begin
        $write("\n  Is your number SIGNED or UNSIGNED? (signed/unsigned/exit): ");
        void'($fgets(line, STDIN));     // Bug 4 Fix: STDIN not stdin
        strip_and_trim(line);
        sign_type = line.tolower();

        if (is_exit(sign_type)) begin
          $display("\n  Exiting calculator. Goodbye!");
          $finish;
        end
        else if (sign_type == "signed"   || sign_type == "s")   ok = 1;
        else if (sign_type == "unsigned" || sign_type == "u") ok = 1;
        else $display("  [ERROR] Please type: signed / unsigned / exit");
      end

      // -- STEP 2: Ask input format ----------------------------
      ok = 0;
      while (!ok) begin
        $display("");
        $display("  SELECT INPUT FORMAT:");
        $display("    bin  -> Binary      (e.g. 1010111100001111)");
        $display("    oct  -> Octal       (e.g. 177777          )");
        $display("    hex  -> Hexadecimal (e.g. FFFF            )");
        $display("    dec  -> Decimal     (e.g. 65535           )");
        $write("  Your choice: ");
        void'($fgets(line, STDIN));
        strip_and_trim(line);
        in_type = line.tolower();

        base = base_from_type(in_type);
        if (base != -1) ok = 1;
        else $display("  [ERROR] Invalid. Use bin / oct / hex / dec.");
      end

      // -- STEP 3: Read the number -----------------------------
      $write("\n  Enter the number (no prefix): ");
      void'($fgets(line, STDIN));
      strip_and_trim(line);
      num_str = line;

      // -- STEP 4: Ask output format ---------------------------
      ok = 0;
      while (!ok) begin
        $display("");
        $display("  SELECT OUTPUT FORMAT:");
        $display("    bin / oct / hex / dec / all");
        $write("  Your choice: ");
        void'($fgets(line, STDIN));
        strip_and_trim(line);
        out_type = line.tolower();   // Bug 5 Fix: lowercase immediately

        if (valid_out_choice(out_type)) ok = 1;
        else $display("  [ERROR] Use bin / oct / hex / dec / all.");
      end

      // -- STEP 5: Parse the number ----------------------------
      parsed = 0;
      ok     = 0;

      case (base)
        16: if ($sscanf(num_str, "%h", parsed) == 1) ok = 1;
        10: if ($sscanf(num_str, "%d", parsed) == 1) ok = 1;
         8: if ($sscanf(num_str, "%o", parsed) == 1) ok = 1;
         2: if ($sscanf(num_str, "%b", parsed) == 1) ok = 1;
      endcase

      if (!ok) begin
        $display("\n  [ERROR] Could not parse '%s'. Please retry.", num_str);
        continue;
      end

      // -- STEP 6: Range validation ----------------------------
      if (sign_type == "unsigned" || sign_type == "u") begin
        if (parsed < 0 || parsed > 65535) begin
          $display("\n  [ERROR] Out of 16-bit UNSIGNED range (0 to 65535).");
          $display("          Your value = %0d", parsed);
          continue;
        end
      end else begin
        if (parsed < -32768 || parsed > 32767) begin
          $display("\n  [ERROR] Out of 16-bit SIGNED range (-32768 to 32767).");
          $display("          Your value = %0d", parsed);
          continue;
        end
      end

      // -- STEP 7: Pack into 16-bit vector ---------------------
      // Bug 2 Fix: simple slice -- no invalid logic'() cast
      v = parsed[15:0];

      // -- STEP 8: Display results ------------------------------
      print_separator();
      $display("  RAW 16-bit vector : %016b", v);
      $display("  RAW Hex           : 0x%04H", v);
      print_separator();

      print_results(v, (sign_type == "signed" || sign_type == "s"), out_type);

      // -- STEP 9: Repeat? --------------------------------------
      $write("  Convert another number? (y/n): ");
      void'($fgets(line, STDIN));
      strip_and_trim(line);
      line = line.tolower();

      if (!(line == "y" || line == "yes")) begin
        print_separator();
        $display("  Thank you. Simulation complete.");
        print_separator();
        $finish;
      end

    end // forever

  end // initial

endmodule