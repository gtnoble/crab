with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_Scorer_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Scorer_Init (T : in out Test);
   procedure Test_Scorer_Score_Same (T : in out Test);
   procedure Test_Scorer_Score_Different (T : in out Test);
   procedure Test_Scorer_Negative_Score (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_Scorer_Tests;
