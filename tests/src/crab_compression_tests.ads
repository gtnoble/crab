with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_Compression_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Deflate_Compress (T : in out Test);
   procedure Test_Deflate_Dict_Compress (T : in out Test);
   procedure Test_LZ4_Compress (T : in out Test);
   procedure Test_LZW_Compress (T : in out Test);
   procedure Test_LZW_Dict_Compress (T : in out Test);
   procedure Test_LZMA_Compress (T : in out Test);
   procedure Test_LZMA_Dict_Compress (T : in out Test);
   procedure Test_Deflate_Roundtrip (T : in out Test);
   procedure Test_Level_Defaults (T : in out Test);
   procedure Test_Level_Ranges (T : in out Test);
   procedure Test_Compress_Bound (T : in out Test);
   procedure Test_Window_Size (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_Compression_Tests;
