--  Crab_Fold — ASCII case folding for --ignore-case

package Crab_Fold is

   function Fold_Heap (S : String) return String;
   --  Return a String copy of S with ASCII uppercase
   --  letters (A..Z) folded to lowercase.  Non-ASCII bytes
   --  pass through unchanged.

end Crab_Fold;
