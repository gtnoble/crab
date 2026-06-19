with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Glob;

package body Crab_Glob_Tests is

   procedure Test_Exact_Match (T : in out Test) is
      pragma Unreferenced (T);
      Pat : Crab_Glob.Pattern_List;
   begin
      Pat.Append ("hello.txt");
      AUnit.Assertions.Assert
        (Crab_Glob.Matches_Any (Pat, "hello.txt", False),
         "exact match should return True");
   end Test_Exact_Match;

   procedure Test_Wildcard_Match (T : in out Test) is
      pragma Unreferenced (T);
      Pat : Crab_Glob.Pattern_List;
   begin
      Pat.Append ("*.txt");
      AUnit.Assertions.Assert
        (Crab_Glob.Matches_Any (Pat, "hello.txt", False),
         "*.txt should match hello.txt");
      AUnit.Assertions.Assert
        (not Crab_Glob.Matches_Any (Pat, "hello.md", False),
         "*.txt should not match hello.md");
   end Test_Wildcard_Match;

   procedure Test_No_Match (T : in out Test) is
      pragma Unreferenced (T);
      Pat : Crab_Glob.Pattern_List;
   begin
      Pat.Append ("*.rs");
      AUnit.Assertions.Assert
        (not Crab_Glob.Matches_Any (Pat, "hello.txt", False),
         "*.rs should not match hello.txt");
   end Test_No_Match;

   procedure Test_Case_Sensitive (T : in out Test) is
      pragma Unreferenced (T);
      Pat : Crab_Glob.Pattern_List;
   begin
      Pat.Append ("Hello.txt");
      AUnit.Assertions.Assert
        (not Crab_Glob.Matches_Any (Pat, "hello.txt", False),
         "case-sensitive should not match");
   end Test_Case_Sensitive;

   procedure Test_Case_Insensitive (T : in out Test) is
      pragma Unreferenced (T);
      Pat : Crab_Glob.Pattern_List;
   begin
      Pat.Append ("Hello.txt");
      AUnit.Assertions.Assert
        (Crab_Glob.Matches_Any (Pat, "hello.txt", True),
         "case-insensitive should match");
   end Test_Case_Insensitive;

   procedure Test_Exclude_Overrides (T : in out Test) is
      pragma Unreferenced (T);
      Inc : Crab_Glob.Pattern_List;
      Exc : Crab_Glob.Pattern_List;
   begin
      Inc.Append ("*.txt");
      Exc.Append ("secret*");
      AUnit.Assertions.Assert
        (Crab_Glob.Should_Process ("hello.txt", Inc, Exc, False),
         "hello.txt should pass include and exclude");
      AUnit.Assertions.Assert
        (not Crab_Glob.Should_Process
           ("secret.txt", Inc, Exc, False),
         "secret.txt should be excluded");
   end Test_Exclude_Overrides;

   procedure Test_Empty_Includes (T : in out Test) is
      pragma Unreferenced (T);
      Empty : Crab_Glob.Pattern_List;
      Exc   : Crab_Glob.Pattern_List;
   begin
      AUnit.Assertions.Assert
        (Crab_Glob.Is_Empty (Empty),
         "empty list should be empty");
      AUnit.Assertions.Assert
        (Crab_Glob.Should_Process ("any.txt", Empty, Exc, False),
         "empty includes should pass any file");
   end Test_Empty_Includes;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      package Caller is new AUnit.Test_Caller (Test);
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
      S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
   begin
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Exact match", Test_Exact_Match'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Wildcard match", Test_Wildcard_Match'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("No match", Test_No_Match'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Case sensitive", Test_Case_Sensitive'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Case insensitive",
         Test_Case_Insensitive'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Exclude overrides",
         Test_Exclude_Overrides'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Empty includes",
         Test_Empty_Includes'Access));
      return Result;
   end Suite;

end Crab_Glob_Tests;
