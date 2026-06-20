with AUnit.Reporter.Text;
with AUnit.Run;
with AUnit.Test_Suites;

with Crab_Chunker_Tests;
with Crab_Compression_Tests;
with Crab_Fold_Tests;
with Crab_Glob_Tests;
with Crab_LZW_Tests;
with Crab_Scorer_Tests;
with Crab_TopK_Tests;

procedure Crab_Tests is

   function Combined_Suite return AUnit.Test_Suites.Access_Test_Suite;

   procedure Run is new AUnit.Run.Test_Runner (Combined_Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;

   function Combined_Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      AUnit.Test_Suites.Add_Test (Result, Crab_Chunker_Tests.Suite);
      AUnit.Test_Suites.Add_Test (Result, Crab_Compression_Tests.Suite);
      AUnit.Test_Suites.Add_Test (Result, Crab_Fold_Tests.Suite);
      AUnit.Test_Suites.Add_Test (Result, Crab_Glob_Tests.Suite);
      AUnit.Test_Suites.Add_Test (Result, Crab_LZW_Tests.Suite);
      AUnit.Test_Suites.Add_Test (Result, Crab_Scorer_Tests.Suite);
      AUnit.Test_Suites.Add_Test (Result, Crab_TopK_Tests.Suite);
      return Result;
   end Combined_Suite;

begin
   Run (Reporter);
end Crab_Tests;
