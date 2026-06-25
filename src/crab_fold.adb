package body Crab_Fold is

   function Fold_Heap (S : String) return String
   is
      Result : String (1 .. S'Length);
   begin
      for I in S'Range loop
         if S (I) in 'A' .. 'Z' then
            Result (I - S'First + 1) :=
              Character'Val (Character'Pos (S (I)) + 32);
         else
            Result (I - S'First + 1) := S (I);
         end if;
      end loop;
      return Result;
   end Fold_Heap;

end Crab_Fold;
