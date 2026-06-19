--  Crab_Glob — Multi-pattern include/exclude matching using fnmatch

with Ada.Containers.Indefinite_Vectors;

package Crab_Glob is

   package Pattern_Vectors is new
     Ada.Containers.Indefinite_Vectors
       (Index_Type   => Positive,
        Element_Type => String);

   subtype Pattern_List is Pattern_Vectors.Vector;

   Empty_Pattern_List : Pattern_List renames Pattern_Vectors.Empty_Vector;

   function Matches_Any
     (List        : Pattern_List;
      Name        : String;
      Ignore_Case : Boolean) return Boolean;
   --  True if Name matches any pattern in List.
   --  If List is empty, returns False.
   --  If Ignore_Case, FNM_CASEFOLD is passed to fnmatch.

   function Is_Empty (List : Pattern_List) return Boolean;
   --  True if List contains no patterns.

   function Should_Process
     (Name         : String;
      Include_Pats : Pattern_List;
      Exclude_Pats : Pattern_List;
      Ignore_Case  : Boolean) return Boolean;
   --  Decide whether a file should be processed based on include/exclude:
   --    - Excludes override: if Name matches any Exclude_Pats → False.
   --    - If Include_Pats is non-empty, Name must match at least one.
   --    - If Include_Pats is empty, all names pass (subject to excludes).

end Crab_Glob;
