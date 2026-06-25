--  Crab_Fold — ASCII case folding for --ignore-case

with Ada.Strings.Unbounded;

package Crab_Fold is

   function Fold_Heap (S : String)
                       return Ada.Strings.Unbounded.Unbounded_String;
   --  Return an Unbounded_String copy of S with ASCII uppercase
   --  letters (A..Z) folded to lowercase.  Non-ASCII bytes
   --  pass through unchanged.

end Crab_Fold;
