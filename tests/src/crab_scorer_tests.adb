with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Compression;
with Crab_Scorer;

package body Crab_Scorer_Tests is

   procedure Test_Scorer_Init (T : in out Test) is
      pragma Unreferenced (T);
      S : constant Crab_Scorer.State :=
        Crab_Scorer.Init ("hello", 10,
          Crab_Compression.Deflate, 6);
   begin
      AUnit.Assertions.Assert (True,
         "Init should not raise an exception");
      pragma Unreferenced (S);
   end Test_Scorer_Init;

   procedure Test_Scorer_Score_Same (T : in out Test) is
      pragma Unreferenced (T);
      S : constant Crab_Scorer.State :=
        Crab_Scorer.Init ("hello world", 20,
          Crab_Compression.Deflate, 6);
      Score : constant Integer :=
        Crab_Scorer.Score (S, "hello world");
   begin
      AUnit.Assertions.Assert (Score > 0,
         "identical strings should have positive MI score");
   end Test_Scorer_Score_Same;

   procedure Test_Scorer_Score_Different (T : in out Test) is
      pragma Unreferenced (T);
      S : constant Crab_Scorer.State :=
        Crab_Scorer.Init ("hello", 20, Crab_Compression.Deflate, 6);
      Score : constant Integer :=
        Crab_Scorer.Score (S, "xxxxxxxxxxxxxxxxxxxx");
   begin
      AUnit.Assertions.Assert (True,
         "different strings should not crash");
      pragma Unreferenced (Score);
   end Test_Scorer_Score_Different;

   procedure Test_Scorer_Negative_Score (T : in out Test) is
      pragma Unreferenced (T);
      S : constant Crab_Scorer.State :=
        Crab_Scorer.Init ("abcdefghij", 10,
          Crab_Compression.Deflate, 6);
      Score1 : constant Integer :=
        Crab_Scorer.Score (S, "abcdefghij");
      Score2 : constant Integer :=
        Crab_Scorer.Score (S, "0000000000");
   begin
      AUnit.Assertions.Assert (Score1 > Score2,
         "similar string should score higher than random");
   end Test_Scorer_Negative_Score;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      package Caller is new AUnit.Test_Caller (Test);
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
      S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
   begin
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Scorer init",
         Test_Scorer_Init'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Score same string",
         Test_Scorer_Score_Same'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Score different strings",
         Test_Scorer_Score_Different'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Score ordering",
         Test_Scorer_Negative_Score'Access));
      return Result;
   end Suite;

end Crab_Scorer_Tests;
