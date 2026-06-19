with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Compression;

package body Crab_Compression_Tests is

   procedure Test_Deflate_Compress (T : in out Test) is
      pragma Unreferenced (T);
      CS : constant Natural :=
        Crab_Compression.Compress
          (Crab_Compression.Deflate, "hello world hello world", 6);
   begin
      AUnit.Assertions.Assert (CS > 0,
         "deflate should produce non-zero output");
      AUnit.Assertions.Assert (CS < 24,
         "deflate should compress repeated text");
   end Test_Deflate_Compress;

   procedure Test_LZ4_Compress (T : in out Test) is
      pragma Unreferenced (T);
      CS : constant Natural :=
        Crab_Compression.Compress
          (Crab_Compression.LZ4, "hello world hello world", 1);
   begin
      AUnit.Assertions.Assert (CS > 0,
         "lz4 should produce non-zero output");
   end Test_LZ4_Compress;

   procedure Test_Deflate_Roundtrip (T : in out Test) is
      pragma Unreferenced (T);
      A : constant Natural :=
        Crab_Compression.Compress
          (Crab_Compression.Deflate, "test", 6);
      B : constant Natural :=
        Crab_Compression.Compress
          (Crab_Compression.Deflate, "test", 6);
   begin
      AUnit.Assertions.Assert (A = B,
         "deflate should be deterministic for same input");
   end Test_Deflate_Roundtrip;

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
   end Test_Level_Ranges;

   procedure Test_Compress_Bound (T : in out Test) is
      pragma Unreferenced (T);
      B : constant Natural :=
        Crab_Compression.Compress_Bound
          (Crab_Compression.Deflate, 1000);
   begin
      AUnit.Assertions.Assert (B > 1000,
         "compress bound should be >= input size");
   end Test_Compress_Bound;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      package Caller is new AUnit.Test_Caller (Test);
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
        (S, Caller.Create ("Deflate roundtrip",
         Test_Deflate_Roundtrip'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Level defaults",
         Test_Level_Defaults'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Level ranges",
         Test_Level_Ranges'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Compress bound",
         Test_Compress_Bound'Access));
      return Result;
   end Suite;

end Crab_Compression_Tests;
