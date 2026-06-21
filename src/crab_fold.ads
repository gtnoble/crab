--  Crab_Fold — ASCII case folding for --ignore-case

package Crab_Fold is

   type String_Access is access String;

   Not_Folded : exception;
   --  Raised when Fold_Heap cannot allocate storage.

   function Fold_Heap (S : String) return String_Access;
   --  Return a heap-allocated copy of S with ASCII uppercase
   --  letters (A..Z) folded to lowercase.  Non-ASCII bytes
   --  pass through unchanged.  Raises Not_Folded on failure.

end Crab_Fold;
