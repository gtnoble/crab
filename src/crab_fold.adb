
package body Crab_Fold is

   function Fold (S : String)
      return Ada.Strings.Unbounded.Unbounded_String
   is
      use Ada.Strings.Unbounded;
      Result    : Unbounded_String;
      Run_Start : Natural := S'First;
   begin
      for I in S'Range loop
         if S (I) in 'A' .. 'Z' then
            --  Flush the run of unchanged characters
            if I > Run_Start then
               Append (Result, S (Run_Start .. I - 1));
            end if;
            --  Append the folded character
            Append
              (Result,
               Character'Val (Character'Pos (S (I)) + 32));
            Run_Start := I + 1;
         end if;
      end loop;
      --  Flush the final run
      if Run_Start <= S'Last then
         Append (Result, S (Run_Start .. S'Last));
      end if;
      return Result;
   end Fold;

end Crab_Fold;
