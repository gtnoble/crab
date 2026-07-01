with AUnit.Assertions;
with AUnit.Test_Caller;
with Ada.Strings.Unbounded;
with Crab_Preprocess;

package body Crab_Preprocess_Tests is

   function H (Raw_Data : String; Command : String) return String is
     (Ada.Strings.Unbounded.To_String
        (Crab_Preprocess.Preprocess_Data (Raw_Data, Command)));

   procedure Do_Preprocess_Nonzero is
   begin
      declare
         Ignored : constant String := H ("data", "exit 1");
         pragma Unreferenced (Ignored);
      begin
         null;
      end;
   end Do_Preprocess_Nonzero;

   package Caller is new AUnit.Test_Caller (Test);

   procedure Test_Pass_Through_Noop (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (H ("hello world", "cat") = "hello world",
         "cat should pass data through unchanged");
   end Test_Pass_Through_Noop;

   procedure Test_Non_Zero_Exit (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert_Exception
        (Do_Preprocess_Nonzero'Access,
         "non-zero exit should raise Program_Error");
   end Test_Non_Zero_Exit;

   procedure Test_Empty_Input (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (H ("", "cat") = "",
         "empty input should produce empty output via cat");
   end Test_Empty_Input;

   procedure Test_Transform (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert
        (H ("Hello World", "tr '[:upper:]' '[:lower:]'") = "hello world",
         "tr should lowercase the input");
   end Test_Transform;

   --  ------------------------------------------------------------------

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      declare
         S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
      begin
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Preprocess pass-through with cat",
               Test_Pass_Through_Noop'Access));
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Preprocess non-zero exit",
               Test_Non_Zero_Exit'Access));
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Preprocess empty input",
               Test_Empty_Input'Access));
         AUnit.Test_Suites.Add_Test
           (S, Caller.Create
              ("Preprocess transform with tr",
               Test_Transform'Access));
      end;
      return Result;
   end Suite;

end Crab_Preprocess_Tests;
