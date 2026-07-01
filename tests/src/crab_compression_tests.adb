with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Compression;

package body Crab_Compression_Tests is

   package Caller is new AUnit.Test_Caller (Test);

   procedure Test_Deflate_Compress (T : in out Test) is
      pragma Unreferenced (T);
      CS : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.Deflate,
           "hello world hello world", 6, "");
   begin
      AUnit.Assertions.Assert (CS > 0,
         "deflate should produce non-zero output");
      AUnit.Assertions.Assert (CS < 24,
         "deflate should compress repeated text");
   end Test_Deflate_Compress;

   procedure Test_LZ4_Compress (T : in out Test) is
      pragma Unreferenced (T);
      CS : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.LZ4,
           "hello world hello world", 1, "");
   begin
      AUnit.Assertions.Assert (CS > 0,
         "lz4 should produce non-zero output");
   end Test_LZ4_Compress;

   procedure Test_LZW_Compress (T : in out Test) is
      pragma Unreferenced (T);
      CS : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.LZW,
           "hello world hello world", 0, "");
   begin
      AUnit.Assertions.Assert (CS > 0,
         "lzw should produce non-zero output");
   end Test_LZW_Compress;

   procedure Test_LZMA_Compress (T : in out Test) is
      pragma Unreferenced (T);
      Data : constant String := "hello world hello world";
      CS : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.LZMA, Data, 6, "");
   begin
      AUnit.Assertions.Assert (CS > 0,
         "lzma should produce non-zero output");
      AUnit.Assertions.Assert (CS < Data'Length,
         "lzma should compress repeated text");
   end Test_LZMA_Compress;

   procedure Test_LZMA_Dict_Compress (T : in out Test) is
      pragma Unreferenced (T);
      Bare : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.LZMA, "hello world", 6, "");
      Dict : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.LZMA, "hello world", 6,
           "hello world");
   begin
      AUnit.Assertions.Assert (Bare > 0,
         "bare compression should produce output");
      AUnit.Assertions.Assert (Dict > 0,
         "dictionary compression should produce output");
   end Test_LZMA_Dict_Compress;

   procedure Test_LZW_Dict_Compress (T : in out Test) is
      pragma Unreferenced (T);
      Bare : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.LZW, "hello world", 0, "");
      Dict : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.LZW, "hello world", 0,
           "hello world");
   begin
      AUnit.Assertions.Assert (Bare > 0,
         "bare compression should produce output");
      AUnit.Assertions.Assert (Dict > 0,
         "dictionary compression should produce output");
   end Test_LZW_Dict_Compress;

   procedure Test_Deflate_Roundtrip (T : in out Test) is
      pragma Unreferenced (T);
      A : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.Deflate, "test", 6, "");
      B : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.Deflate, "test", 6, "");
   begin
      AUnit.Assertions.Assert (A = B,
         "deflate should be deterministic for same input");
   end Test_Deflate_Roundtrip;

   procedure Test_Deflate_Dict_Compress (T : in out Test) is
      pragma Unreferenced (T);
      Bare : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.Deflate, "hello world", 6, "");
      Dict : constant Natural :=
        Crab_Compression.Compress_Bare
          (Crab_Compression.Deflate, "hello world", 6,
           "hello world");
   begin
      AUnit.Assertions.Assert (Bare > 0,
         "bare compression should produce output");
      AUnit.Assertions.Assert (Dict > 0,
         "dictionary compression should produce output");
   end Test_Deflate_Dict_Compress;

   procedure Test_Level_Defaults (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Default
           (Crab_Compression.Deflate) = 6,
         "deflate default should be 6");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Default
           (Crab_Compression.LZ4) = 1,
         "lz4 default should be 1");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Default
           (Crab_Compression.LZW) = 0,
         "lzw default should be 0");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Default
           (Crab_Compression.LZMA) = 6,
         "lzma default should be 6");
   end Test_Level_Defaults;

   procedure Test_Level_Ranges (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Min
           (Crab_Compression.Deflate) = -1,
         "deflate min should be -1");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Max
           (Crab_Compression.Deflate) = 9,
         "deflate max should be 9");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Min
           (Crab_Compression.LZ4) = 1,
         "lz4 min should be 1");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Max
           (Crab_Compression.LZ4) = 65_537,
         "lz4 max should be 65537");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Min
           (Crab_Compression.LZW) = 0,
         "lzw min should be 0");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Max
           (Crab_Compression.LZW) = 0,
         "lzw max should be 0");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Min
           (Crab_Compression.LZMA) = 0,
         "lzma min should be 0");
      AUnit.Assertions.Assert
        (Crab_Compression.Level_Max
           (Crab_Compression.LZMA) = 9,
         "lzma max should be 9");
   end Test_Level_Ranges;

   procedure Test_Compress_Bound (T : in out Test) is
      pragma Unreferenced (T);
      B_Deflate : constant Natural :=
        Crab_Compression.Compress_Bound
          (Crab_Compression.Deflate, 1000);
      B_LZW : constant Natural :=
        Crab_Compression.Compress_Bound
          (Crab_Compression.LZW, 1000);
      B_LZMA : constant Natural :=
        Crab_Compression.Compress_Bound
          (Crab_Compression.LZMA, 1000);
   begin
      AUnit.Assertions.Assert (B_Deflate > 1000,
         "deflate compress bound should be >= input size");
      AUnit.Assertions.Assert (B_LZW > 1000,
         "lzw compress bound should be >= input size");
      AUnit.Assertions.Assert (B_LZMA > 1000,
         "lzma compress bound should be >= input size");
   end Test_Compress_Bound;

   procedure Test_Window_Size (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (Crab_Compression.Window_Size
           (Crab_Compression.Deflate) = 32_768,
         "deflate window should be 32768");
      AUnit.Assertions.Assert
        (Crab_Compression.Window_Size
           (Crab_Compression.LZ4) = 65_536,
         "lz4 window should be 65536");
      AUnit.Assertions.Assert
        (Crab_Compression.Window_Size
           (Crab_Compression.LZW) = Natural'Last,
         "lzw window should be unbounded");
      AUnit.Assertions.Assert
        (Crab_Compression.Window_Size
           (Crab_Compression.LZMA) = 8_388_608,
         "lzma window should be 8388608");
   end Test_Window_Size;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
      S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
   begin
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Deflate compress",
         Test_Deflate_Compress'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZ4 compress",
         Test_LZ4_Compress'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW compress",
         Test_LZW_Compress'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZMA compress",
         Test_LZMA_Compress'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW dictionary compress",
         Test_LZW_Dict_Compress'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZMA dictionary compress",
         Test_LZMA_Dict_Compress'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Deflate roundtrip",
         Test_Deflate_Roundtrip'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Deflate dictionary",
         Test_Deflate_Dict_Compress'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Level defaults",
         Test_Level_Defaults'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Level ranges",
         Test_Level_Ranges'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Compress bound",
         Test_Compress_Bound'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Window size",
         Test_Window_Size'Access));
      return Result;
   end Suite;

end Crab_Compression_Tests;
