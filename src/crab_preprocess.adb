with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.Expect;
with GNAT.OS_Lib;

package body Crab_Preprocess is

   function Preprocess_Data
     (Raw_Data : String;
      Command  : String) return Ada.Strings.Unbounded.Unbounded_String
   is
      Status : aliased Integer;
      Result : constant String :=
        GNAT.Expect.Get_Command_Output
          (Command    => "/bin/sh",
           Arguments  => GNAT.OS_Lib.Argument_List'
             (1 => new String'("-c"),
              2 => new String'(Command)),
           Input      => Raw_Data,
           Status     => Status'Access,
           Err_To_Out => True);
   begin
      if Status /= 0 then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crab: preprocess command '" & Command
            & "' exited with status" & Integer'Image (Status));
         Ada.Command_Line.Set_Exit_Status (2);
         raise Program_Error;
      end if;
      return Ada.Strings.Unbounded.To_Unbounded_String (Result);
   end Preprocess_Data;

end Crab_Preprocess;
