with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_Glob_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Exact_Match (T : in out Test);
   procedure Test_Wildcard_Match (T : in out Test);
   procedure Test_No_Match (T : in out Test);
   procedure Test_Case_Sensitive (T : in out Test);
   procedure Test_Case_Insensitive (T : in out Test);
   procedure Test_Exclude_Overrides (T : in out Test);
   procedure Test_Empty_Includes (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_Glob_Tests;
