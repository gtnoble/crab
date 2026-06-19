with Interfaces.C;
with Interfaces.C.Strings;

package body Crab_Fnmatch is

   use type Interfaces.C.int;

   function c_fnmatch
     (Pattern : Interfaces.C.Strings.chars_ptr;
      Name    : Interfaces.C.Strings.chars_ptr;
      Flags   : Interfaces.C.int) return Interfaces.C.int
      with Import, Convention => C, External_Name => "fnmatch";

   --  ------------------------------------------------------------------

   function Match
     (Pattern   : String;
      Name      : String;
      Flags     : Integer) return Boolean
   is
      C_Pat  : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Pattern);
      C_Name : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Name);
      Result : Interfaces.C.int;
   begin
      Result := c_fnmatch (C_Pat, C_Name, Interfaces.C.int (Flags));
      Interfaces.C.Strings.Free (C_Pat);
      Interfaces.C.Strings.Free (C_Name);
      return Result = 0;
   end Match;

end Crab_Fnmatch;
