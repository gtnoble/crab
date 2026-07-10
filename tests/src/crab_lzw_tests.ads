with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_LZW_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Roundtrip_Simple (T : in out Test);
   procedure Test_Roundtrip_Empty (T : in out Test);
   procedure Test_Roundtrip_Repeated (T : in out Test);
   procedure Test_Roundtrip_Long (T : in out Test);
   procedure Test_Dict_Compression (T : in out Test);
   procedure Test_Dict_Unrelated (T : in out Test);
   procedure Test_Compress_Bound (T : in out Test);
   procedure Test_Compress_Bare (T : in out Test);
   procedure Test_Bounded_Roundtrip (T : in out Test);
   procedure Test_Bounded_Compression (T : in out Test);
   procedure Test_Set_Max_Codes (T : in out Test);
   procedure Test_Roundtrip_Bit_Width_9_10 (T : in out Test);
   procedure Test_Roundtrip_Bit_Width_Multi (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_LZW_Tests;
