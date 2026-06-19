with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_Chunker_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Single_Chunk (T : in out Test);
   procedure Test_Multiple_Chunks (T : in out Test);
   procedure Test_Last_Chunk_Shorter (T : in out Test);
   procedure Test_Zero_Overlap (T : in out Test);
   procedure Test_Fifty_Pct_Overlap (T : in out Test);
   procedure Test_Empty_Buffer (T : in out Test);
   procedure Test_Buffer_Shorter_Than_Chunk (T : in out Test);

   --  Line-mode tests
   procedure Test_Lines_Single_Chunk (T : in out Test);
   procedure Test_Lines_Multiple_Chunks (T : in out Test);
   procedure Test_Lines_Last_Shorter (T : in out Test);
   procedure Test_Lines_Overlap (T : in out Test);
   procedure Test_Lines_Empty_Buffer (T : in out Test);
   procedure Test_Lines_Single_Line (T : in out Test);
   procedure Test_Lines_Trailing_Bytes (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_Chunker_Tests;
