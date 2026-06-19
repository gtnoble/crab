with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Fold;

package body Crab_Fold_Tests is

   procedure Test_Fold_Lowercase_Unchanged (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (Crab_Fold.Fold ("hello") = "hello",
         "lowercase should be unchanged");
   end Test_Fold_Lowercase_Unchanged;

   procedure Test_Fold_Uppercase (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (Crab_Fold.Fold ("HELLO") = "hello",
         "uppercase should be folded to lowercase");
   end Test_Fold_Uppercase;

   procedure Test_Fold_Mixed (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (Crab_Fold.Fold ("Hello World") = "hello world",
         "mixed case should be folded");
   end Test_Fold_Mixed;

   procedure Test_Fold_Non_ASCII (T : in out Test) is
      pragma Unreferenced (T);
      S : constant String :=
        Character'Val (128) & Character'Val (200) & Character'Val (255);
   begin
      AUnit.Assertions.Assert
        (Crab_Fold.Fold (S) = S,
         "non-ASCII bytes should pass through unchanged");
   end Test_Fold_Non_ASCII;

   procedure Test_Fold_Empty (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (Crab_Fold.Fold ("") = "",
         "empty string should return empty string");
   end Test_Fold_Empty;

   --  ------------------------------------------------------------------

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      package Caller is new AUnit.Test_Caller (Test);
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      declare
         S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
      begin
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Fold lowercase unchanged",
               Test_Fold_Lowercase_Unchanged'Access));
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Fold uppercase to lowercase",
               Test_Fold_Uppercase'Access));
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Fold mixed case",
               Test_Fold_Mixed'Access));
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Fold non-ASCII bytes unchanged",
               Test_Fold_Non_ASCII'Access));
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Fold empty string",
               Test_Fold_Empty'Access));
      end;
      return Result;
   end Suite;

end Crab_Fold_Tests;
