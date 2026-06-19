with AUnit;
with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Crab_Fold_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Fold_Lowercase_Unchanged (T : in out Test);
   procedure Test_Fold_Uppercase (T : in out Test);
   procedure Test_Fold_Mixed (T : in out Test);
   procedure Test_Fold_Non_ASCII (T : in out Test);
   procedure Test_Fold_Empty (T : in out Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Crab_Fold_Tests;
