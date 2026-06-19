with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_TopK_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Empty_Heap (T : in out Test);
   procedure Test_Insert_Below_Capacity (T : in out Test);
   procedure Test_Insert_At_Capacity (T : in out Test);
   procedure Test_Keep_Best_Scores (T : in out Test);
   procedure Test_Invert_Keeps_Worst (T : in out Test);
   procedure Test_Partial_Fill (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_TopK_Tests;
