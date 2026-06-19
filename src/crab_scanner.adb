with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Directories;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Crab_Glob;
with GNAT.OS_Lib;

package body Crab_Scanner is

   use Ada.Directories;
   use Ada.Strings.Unbounded;

   --  Path set for symlink-cycle detection
   package Path_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type => String,
      Hash         => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   function Canonical (Path : String) return String is
      use GNAT.OS_Lib;
   begin
      return Normalize_Pathname
        (Path,
         Directory      => "",
         Resolve_Links  => True,
         Case_Sensitive => True);
   end Canonical;

   procedure Walk
     (Dir_Path     : String;
      Depth        : Natural;
      Max_Depth    : Natural;
      Include_Pats : Crab_Glob.Pattern_List;
      Exclude_Pats : Crab_Glob.Pattern_List;
      Ignore_Case  : Boolean;
      Visited      : in out Path_Sets.Set;
      Files        : in out File_Lists.Vector;
      Warnings     : in out String_Vectors.Vector)
   is
      Search : Search_Type;
      Ent    : Directory_Entry_Type;

      --  Collect names as Unbounded_String for sorting
      package Name_Vectors is new Ada.Containers.Indefinite_Vectors
        (Positive, Unbounded_String);

      Name : Name_Vectors.Vector;

      package Name_Sorting is new Name_Vectors.Generic_Sorting;
   begin
      --  Cycle check via canonical path
      declare
         Canon : constant String := Canonical (Dir_Path);
      begin
         if Canon /= "" and then Visited.Contains (Canon) then
            return;
         end if;
         if Canon /= "" then
            Visited.Insert (Canon);
         end if;
      end;

      begin
         Start_Search (Search, Dir_Path, "");
      exception
         when Name_Error | Use_Error =>
            Warnings.Append
              ("crab: " & Dir_Path & ": unable to read directory");
            return;
      end;

      --  Collect entries
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Ent);
         declare
            Simple : constant String := Simple_Name (Ent);
         begin
            if Simple /= "." and then Simple /= ".." then
               Name.Append (To_Unbounded_String (Full_Name (Ent)));
            end if;
         end;
      end loop;
      End_Search (Search);

      --  Sort entries by path (byte-value ordering)
      Name_Sorting.Sort (Name);

      --  Process entries in sorted order
      for I in 1 .. Natural (Name.Length) loop
         declare
            Full : constant String :=
              To_String (Name.Element (Positive (I)));
         begin
            case Kind (Full) is
               when Ordinary_File =>
                  if Crab_Glob.Should_Process
                    (Simple_Name (Full),
                     Include_Pats, Exclude_Pats, Ignore_Case)
                  then
                     Files.Append
                       ((Path      => To_Unbounded_String (Full),
                         Byte_Size => Size (Full)));
                  end if;
               when Directory =>
                  if Depth < Max_Depth then
                     Walk (Full, Depth + 1,
                           Max_Depth,
                           Include_Pats, Exclude_Pats,
                           Ignore_Case,
                           Visited, Files, Warnings);
                  end if;
               when others =>
                  null;  --  skip special files
            end case;
         exception
            when Name_Error | Use_Error =>
               Warnings.Append
                 ("crab: " & Full & ": unable to access");
         end;
      end loop;
   end Walk;

   --  ------------------------------------------------------------------

   function Scan
     (Root_Paths   : String_Vectors.Vector;
      Recursive    : Boolean;
      Max_Depth    : Natural;
      Include_Pats : Crab_Glob.Pattern_List;
      Exclude_Pats : Crab_Glob.Pattern_List;
      Ignore_Case  : Boolean;
      Warnings     : out String_Vectors.Vector)
      return File_Lists.Vector
   is
      Visited : Path_Sets.Set;
      Files   : File_Lists.Vector;
      Roots   : String_Vectors.Vector := Root_Paths;
   begin
      Warnings := String_Vectors.Empty_Vector;

      --  Default to current directory if no paths given
      if Roots.Is_Empty then
         Roots.Append (".");
      end if;

      --  Sort root paths for determinism
      declare
         package Root_Vectors is new Ada.Containers.Indefinite_Vectors
           (Positive, String);
         Sorted_Roots : Root_Vectors.Vector;
      begin
         for R of Roots loop
            Sorted_Roots.Append (R);
         end loop;
         declare
            package Root_Sorting is new Root_Vectors.Generic_Sorting;
         begin
            Root_Sorting.Sort (Sorted_Roots);
         end;

         for R of Sorted_Roots loop
            begin
               case Kind (R) is
                  when Ordinary_File =>
                     if Crab_Glob.Should_Process
                       (Simple_Name (R),
                        Include_Pats, Exclude_Pats, Ignore_Case)
                     then
                        Files.Append
                          ((Path      => To_Unbounded_String (R),
                            Byte_Size => Size (R)));
                     end if;
                  when Directory =>
                     if not Recursive then
                        Warnings.Append
                          ("crab: " & R
                           & ": directories require -r; skipping");
                     else
                        Walk (R, 0, Max_Depth,
                              Include_Pats, Exclude_Pats,
                              Ignore_Case,
                              Visited, Files, Warnings);
                     end if;
                  when others =>
                     null;
               end case;
            exception
               when Name_Error | Use_Error =>
                  Warnings.Append
                    ("crab: " & R & ": unable to access");
            end;
         end loop;
      end;

      return Files;
   end Scan;

end Crab_Scanner;
