package body Crab_Fold is

   function Fold_Heap (S : String)
                       return Ada.Strings.Unbounded.Unbounded_String
   is
      use Ada.Strings.Unbounded;
      Result : Unbounded_String;
   begin
      for I in S'Range loop
         if S (I) in 'A' .. 'Z' then
            Append (Result, Character'Val (Character'Pos (S (I)) + 32));
         else
            Append (Result, S (I));
         end if;
      end loop;
      return Result;
   end Fold_Heap;

end Crab_Fold;
