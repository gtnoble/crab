--  Crab_Fold — ASCII case folding for --ignore-case

with Ada.Strings.Unbounded;

package Crab_Fold is

   function Fold (S : String)
      return Ada.Strings.Unbounded.Unbounded_String;
   --  Return a copy of S with ASCII uppercase letters (A..Z) folded
   --  to lowercase.  Non-ASCII bytes pass through unchanged.
   --  Result is allocated on the heap via Unbounded_String.

end Crab_Fold;
