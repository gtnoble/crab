with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_LZW_Crlzw_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Roundtrip tests (REQ-095)
   procedure Test_Roundtrip_Unbounded (T : in out Test);
   procedure Test_Roundtrip_Bounded (T : in out Test);
   procedure Test_Roundtrip_Empty (T : in out Test);
   procedure Test_Roundtrip_Single_Char (T : in out Test);
   procedure Test_Roundtrip_Level1 (T : in out Test);
   procedure Test_Roundtrip_Level9 (T : in out Test);

   --  File format tests (REQ-091)
   procedure Test_File_Format_Header (T : in out Test);
   procedure Test_File_Format_Magic (T : in out Test);
   procedure Test_File_Format_Version (T : in out Test);
   procedure Test_File_Format_Max_Codes (T : in out Test);

   --  Suffix detection tests (REQ-092)
   procedure Test_Suffix_Default_Cz (T : in out Test);
   procedure Test_Suffix_Case_Insensitive (T : in out Test);
   procedure Test_Suffix_Custom (T : in out Test);
   procedure Test_Suffix_Null (T : in out Test);

   --  Error handling (REQ-090)
   procedure Test_Malformed_Truncated (T : in out Test);
   procedure Test_Malformed_Bad_Magic (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_LZW_Crlzw_Tests;
