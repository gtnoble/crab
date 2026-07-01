--  Crab_Preprocess — Pipe raw input through a shell command

with Ada.Strings.Unbounded;

package Crab_Preprocess is

   function Preprocess_Data
     (Raw_Data : String;
      Command  : String) return Ada.Strings.Unbounded.Unbounded_String;
   --  Spawn /bin/sh -c Command, pipe Raw_Data to stdin, capture stdout.
   --  stderr is merged into stdout (Err_To_Out => True).
   --  Raises Program_Error if the command exits with a non-zero status.

end Crab_Preprocess;
