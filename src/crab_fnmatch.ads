--  Crab_Fnmatch — Thin Ada binding to libc fnmatch()

package Crab_Fnmatch is

   FNM_NOMATCH  : constant := 1;
   FNM_CASEFOLD : constant := 16;   --  (1 << 4) on glibc

   function Match
     (Pattern   : String;
      Name      : String;
      Flags     : Integer) return Boolean;
   --  True if Name matches Pattern per POSIX fnmatch() rules.
   --  Flags is a bitmask: or in FNM_CASEFOLD for case-insensitive match.
   --  Returns False (no match) on FNM_NOMATCH or any error.

end Crab_Fnmatch;
