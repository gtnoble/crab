with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Compression;
with Crab_Scorer;

package body Crab_Scorer_Tests is

   procedure Test_Scorer_Init (T : in out Test) is
      pragma Unreferenced (T);
      S_Deflate : Crab_Scorer.State (Algo => Crab_Compression.Deflate);
      S_LZW     : Crab_Scorer.State (Algo => Crab_Compression.LZW);
   begin
      Crab_Scorer.Init (S_Deflate, "hello", 10, 6);
      Crab_Scorer.Init (S_LZW, "hello", 10, 0);
      AUnit.Assertions.Assert (True,
         "Init should not raise an exception");
   end Test_Scorer_Init;

   procedure Test_Scorer_Score_Same (T : in out Test) is
      pragma Unreferenced (T);
      S_Deflate : Crab_Scorer.State (Algo => Crab_Compression.Deflate);
      S_LZW     : Crab_Scorer.State (Algo => Crab_Compression.LZW);
      Score_Deflate : Integer;
      Score_LZW     : Integer;
   begin
      Crab_Scorer.Init (S_Deflate, "hello world", 20, 6);
      Score_Deflate := Crab_Scorer.Score (S_Deflate, "hello world");
      Crab_Scorer.Init (S_LZW, "hello world", 20, 0);
      Score_LZW := Crab_Scorer.Score (S_LZW, "hello world");
      AUnit.Assertions.Assert (Score_Deflate > 0,
         "deflate: identical strings should have positive MI score");
      AUnit.Assertions.Assert (Score_LZW > 0,
         "lzw: identical strings should have positive MI score");
   end Test_Scorer_Score_Same;

   procedure Test_Scorer_Score_Different (T : in out Test) is
      pragma Unreferenced (T);
      S : Crab_Scorer.State (Algo => Crab_Compression.LZW);
      Score : Integer;
   begin
      Crab_Scorer.Init (S, "hello", 20, 0);
      Score := Crab_Scorer.Score (S, "xxxxxxxxxxxxxxxxxxxx");
      AUnit.Assertions.Assert (True,
         "different strings should not crash");
      pragma Unreferenced (Score);
   end Test_Scorer_Score_Different;

   procedure Test_Scorer_Negative_Score (T : in out Test) is
      pragma Unreferenced (T);
      S : Crab_Scorer.State (Algo => Crab_Compression.LZW);
      Score1 : Integer;
      Score2 : Integer;
   begin
      Crab_Scorer.Init (S, "abcdefghij", 10, 0);
      Score1 := Crab_Scorer.Score (S, "abcdefghij");
      Score2 := Crab_Scorer.Score (S, "0000000000");
      AUnit.Assertions.Assert (Score1 > Score2,
         "similar string should score higher than random");
   end Test_Scorer_Negative_Score;

   procedure Test_Scorer_LZMA_Score (T : in out Test) is
      pragma Unreferenced (T);
      S : Crab_Scorer.State (Algo => Crab_Compression.LZMA);
      Score_Same : Integer;
      Score_Diff : Integer;
   begin
      Crab_Scorer.Init (S, "hello world hello world",
        30, 6, Dict_Size => 65536);
      Score_Same := Crab_Scorer.Score (S, "hello world hello world");
      Score_Diff := Crab_Scorer.Score (S, "xxxxxxxxxxxxxxxxxxxxxxxxxx");
      AUnit.Assertions.Assert (Score_Same > 0,
         "LZMA: identical strings should have positive MI score");
      AUnit.Assertions.Assert (Score_Same > Score_Diff,
         "LZMA: same should score higher than different");
   end Test_Scorer_LZMA_Score;

   procedure Test_Scorer_Binary_Data (T : in out Test) is
      pragma Unreferenced (T);
      --  Verify that scoring binary data (bytes 0x00..0xFF) does not
      --  crash and produces a valid score.  The scorer must handle
      --  arbitrary octets without corruption.
      S : Crab_Scorer.State (Algo => Crab_Compression.LZW);
      Binary_Query : constant String :=
        Character'Val (0) & Character'Val (128) & Character'Val (255)
        & Character'Val (64) & Character'Val (32);
      Binary_Chunk : constant String :=
        Character'Val (0) & Character'Val (128) & Character'Val (255)
        & Character'Val (64) & Character'Val (32);
      Score : Integer;
   begin
      Crab_Scorer.Init (S, Binary_Query, 10, 0);
      Score := Crab_Scorer.Score (S, Binary_Chunk);
      --  Identical binary data should produce a positive MI score
      AUnit.Assertions.Assert (Score > 0,
         "identical binary data should have positive MI score");
   end Test_Scorer_Binary_Data;

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
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZMA scorer",
         Test_Scorer_LZMA_Score'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Binary data scoring",
         Test_Scorer_Binary_Data'Access));
      return Result;
   end Suite;

end Crab_Scorer_Tests;
