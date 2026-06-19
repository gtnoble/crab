with Crab_Fnmatch;

package body Crab_Glob is

   function Matches_Any
     (List        : Pattern_List;
      Name        : String;
      Ignore_Case : Boolean) return Boolean
   is
      Flags : constant Integer :=
        (if Ignore_Case then Crab_Fnmatch.FNM_CASEFOLD else 0);
   begin
      for Pat of List loop
         if Crab_Fnmatch.Match (Pat, Name, Flags) then
            return True;
         end if;
      end loop;
      return False;
   end Matches_Any;

   function Is_Empty (List : Pattern_List) return Boolean is
      (List.Is_Empty);

   function Should_Process
     (Name         : String;
      Include_Pats : Pattern_List;
      Exclude_Pats : Pattern_List;
      Ignore_Case  : Boolean) return Boolean
   is
   begin
      --  Excludes override includes
      if not Is_Empty (Exclude_Pats)
        and then Matches_Any (Exclude_Pats, Name, Ignore_Case)
      then
         return False;
      end if;
      --  If no includes specified, everything passes
      if Is_Empty (Include_Pats) then
         return True;
      end if;
      --  Must match at least one include pattern
      return Matches_Any (Include_Pats, Name, Ignore_Case);
   end Should_Process;

end Crab_Glob;
