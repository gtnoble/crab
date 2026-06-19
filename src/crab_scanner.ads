--  Crab_Scanner — Directory traversal with glob filtering & depth limiting

with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Crab_Glob;

package Crab_Scanner is

   type File_Entry is record
      Path      : Ada.Strings.Unbounded.Unbounded_String;
      Byte_Size : Ada.Directories.File_Size;
   end record;

   package File_Lists is new Ada.Containers.Indefinite_Vectors
     (Positive, File_Entry);

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);

   function Scan
     (Root_Paths   : String_Vectors.Vector;
      Recursive    : Boolean;
      Max_Depth    : Natural;
      Include_Pats : Crab_Glob.Pattern_List;
      Exclude_Pats : Crab_Glob.Pattern_List;
      Ignore_Case  : Boolean;
      Warnings     : out String_Vectors.Vector)
      return File_Lists.Vector;
   --  Walk directory trees starting from Root_Paths, collect regular
   --  files filtered by globs and depth.  Symlinks are followed.
   --  Directories are traversed depth-first in sorted order.
   --  Warnings collects non-fatal error messages (e.g. permission denied).

end Crab_Scanner;
