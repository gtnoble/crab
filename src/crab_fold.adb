package body Crab_Fold is

   function Fold_Heap (S : String) return String_Access is
      Result : constant String_Access := new String (1 .. S'Length);
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
   exception
      when Storage_Error =>
         raise Not_Folded;
   end Fold_Heap;

end Crab_Fold;
