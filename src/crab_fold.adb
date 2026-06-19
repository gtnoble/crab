package body Crab_Fold is

   function Fold (S : String) return String is
      Result : String (1 .. S'Length);
   begin
      for I in S'Range loop
         declare
            C : constant Character := S (I);
         begin
            if C in 'A' .. 'Z' then
               Result (I - S'First + 1) :=
                 Character'Val (Character'Pos (C) + 32);
            else
               Result (I - S'First + 1) := C;
            end if;
         end;
      end loop;
      return Result;
   end Fold;

end Crab_Fold;
