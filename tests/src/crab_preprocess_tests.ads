with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_Preprocess_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Pass_Through_Noop (T : in out Test);
   procedure Test_Non_Zero_Exit (T : in out Test);
   procedure Test_Empty_Input (T : in out Test);
   procedure Test_Transform (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_Preprocess_Tests;
