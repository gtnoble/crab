with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Crab_Chunker;
with Crab_Compression;
with Crab_Config;
with Crab_Fold;
with Crab_Glob;
with Crab_Scanner;
with Crab_Scorer;
with Crab_TopK;

procedure Crab is

   use Ada.Strings.Unbounded;

   use type Ada.Directories.File_Kind;
   use type Crab_Compression.Algorithm;

   --  =================================================================
   --  Configuration
   --  =================================================================

   type Config is record
      Show_Help    : Boolean := False;
      Show_Version : Boolean := False;
      Query        : Unbounded_String;
      Algorithm    : Crab_Compression.Algorithm := Crab_Compression.Deflate;
      Level        : Integer := Crab_Compression.Level_Default
                                  (Crab_Compression.Deflate);
      Chunk_Size   : Natural := 0;   --  0 = not set
      Chunk_Lines  : Natural := 0;   --  0 = not set;
      Overlap      : Natural := 0;
      Top_K        : Positive := 10;
      Recursive    : Boolean := False;
      Ignore_Case  : Boolean := False;
      Invert       : Boolean := False;
      Max_Depth    : Natural := Natural'Last;
      Include_Pats : Crab_Glob.Pattern_List;
      Exclude_Pats : Crab_Glob.Pattern_List;
      Paths        : Crab_Scanner.String_Vectors.Vector;
   end record;

   --  =================================================================
   --  Usage
   --  =================================================================

   procedure Print_Usage is
   begin
      Ada.Text_IO.Put_Line
        ("Usage: crab [OPTIONS] QUERY [PATH...]");
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line ("Options:");
      Ada.Text_IO.Put_Line ("  -h, --help              Show this help");
      Ada.Text_IO.Put_Line ("  --version               Show version");
      Ada.Text_IO.Put_Line
        ("  -a, --algorithm ALGO    Compression: deflate (default) | lz4");
      Ada.Text_IO.Put_Line
        ("  -l, --level N           Compression level"
         & " (deflate: -1..9, lz4: 1..65537)");
      Ada.Text_IO.Put_Line
        ("  -s, --chunk-size N      Chunk size in bytes ");
      Ada.Text_IO.Put_Line
        ("  -L, --chunk-lines N     Chunk size in lines");
      Ada.Text_IO.Put_Line
        ("  -o, --overlap P         Overlap percentage 0-99"
         & " (default 0)");
      Ada.Text_IO.Put_Line
        ("  -k, --top N             Number of chunks to return"
         & " (default 10)");
      Ada.Text_IO.Put_Line
        ("  -r, --recursive         Search directories recursively");
      Ada.Text_IO.Put_Line
        ("  -i, --ignore-case       Case-insensitive matching");
      Ada.Text_IO.Put_Line
        ("  -v, --invert            Return least-similar chunks");
      Ada.Text_IO.Put_Line
        ("      --include GLOB      Include files matching glob"
         & " (repeatable)");
      Ada.Text_IO.Put_Line
        ("      --exclude GLOB      Exclude files matching glob"
         & " (repeatable)");
      Ada.Text_IO.Put_Line
        ("      --max-depth N       Max directory traversal depth");
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line
        ("If no PATHs are given and -r is not set, reads from stdin.");
   end Print_Usage;

   --  =================================================================
   --  Argument Parsing
   --  =================================================================

   procedure Parse_Args (Cfg : out Config) is
      use Ada.Command_Line;
      I : Natural := 1;
      Has_Query : Boolean := False;
   begin
      Cfg := (others => <>);
      Cfg.Level := Crab_Compression.Level_Default (Cfg.Algorithm);

      while I <= Argument_Count loop
         declare
            Arg : constant String := Argument (I);
         begin
            if Arg = "--help" or else Arg = "-h" then
               Cfg.Show_Help := True;
               return;
            elsif Arg = "--version" then
               Cfg.Show_Version := True;
               return;
            elsif Arg = "-a" or else Arg = "--algorithm" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --algorithm requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               declare
                  Val : constant String := Argument (I);
               begin
                  if Val = "deflate" or else Val = "DEFLATE" then
                     Cfg.Algorithm := Crab_Compression.Deflate;
                  elsif Val = "lz4" or else Val = "LZ4" then
                     Cfg.Algorithm := Crab_Compression.LZ4;
                  else
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: unknown algorithm '" & Val
                        & "'; use deflate or lz4");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
                  end if;
               end;
            elsif Arg = "-l" or else Arg = "--level" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --level requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.Level := Integer'Value (Argument (I));
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: invalid level '" & Argument (I) & "'");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
               end;
            elsif Arg = "-s" or else Arg = "--chunk-size" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --chunk-size requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.Chunk_Size := Natural'Value (Argument (I));
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: invalid chunk size '"
                        & Argument (I) & "'");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
               end;

            elsif Arg = "-L" or else Arg = "--chunk-lines" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --chunk-lines requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.Chunk_Lines := Natural'Value (Argument (I));
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: invalid chunk lines '"
                        & Argument (I) & "'");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
               end;
            elsif Arg = "-o" or else Arg = "--overlap" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --overlap requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.Overlap := Natural'Value (Argument (I));
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: invalid overlap '"
                        & Argument (I) & "'");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
               end;
            elsif Arg = "-k" or else Arg = "--top" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --top requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.Top_K := Positive'Value (Argument (I));
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: invalid top-k '"
                        & Argument (I) & "'");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
               end;
            elsif Arg = "-r" or else Arg = "--recursive" then
               Cfg.Recursive := True;
            elsif Arg = "-i" or else Arg = "--ignore-case" then
               Cfg.Ignore_Case := True;
            elsif Arg = "-v" or else Arg = "--invert" then
               Cfg.Invert := True;
            elsif Arg = "--include" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --include requires a pattern");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               Cfg.Include_Pats.Append (Argument (I));
            elsif Arg = "--exclude" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --exclude requires a pattern");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               Cfg.Exclude_Pats.Append (Argument (I));
            elsif Arg = "--max-depth" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --max-depth requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.Max_Depth := Natural'Value (Argument (I));
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: invalid max-depth '"
                        & Argument (I) & "'");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
               end;
            elsif Arg'Length > 0 and then Arg (Arg'First) = '-' then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crab: unknown flag '" & Arg & "'");
               Ada.Command_Line.Set_Exit_Status (1);
               raise Program_Error;
            else
               --  First non-flag arg is query; rest are paths
               if not Has_Query then
                  Cfg.Query := To_Unbounded_String (Arg);
                  Has_Query := True;
               else
                  Cfg.Paths.Append (Arg);
               end if;
            end if;
         end;
         I := I + 1;
      end loop;

      --  Validation
      if not Has_Query or else Length (Cfg.Query) = 0 then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crab: query string is required");
         Ada.Command_Line.Set_Exit_Status (1);
         raise Program_Error;
      end if;

      if not ((Cfg.Chunk_Size > 0) xor (Cfg.Chunk_Lines > 0)) then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crab: exactly one of --chunk-size or --chunk-lines"
            & " is required");
         Ada.Command_Line.Set_Exit_Status (1);
         raise Program_Error;
      end if;
      if Cfg.Overlap > 99 then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crab: overlap must be in range 0-99");
         Ada.Command_Line.Set_Exit_Status (1);
         raise Program_Error;
      end if;

      if Cfg.Algorithm = Crab_Compression.Deflate then
         if Cfg.Level < -1 or else Cfg.Level > 9 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: deflate level must be in range -1..9");
            Ada.Command_Line.Set_Exit_Status (1);
            raise Program_Error;
         end if;
      else
         if Cfg.Level < 1 or else Cfg.Level > 65_537 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: lz4 level must be in range 1..65537");
            Ada.Command_Line.Set_Exit_Status (1);
            raise Program_Error;
         end if;
      end if;
   end Parse_Args;

   --  =================================================================
   --  File Processing
   --  =================================================================

   procedure Process_One_File
     (Path   : String;
      Data   : String;
      Heap   : in out Crab_TopK.Heap;
      Scorer : in out Crab_Scorer.State;
      Cfg    : Config)
   is
      Scoring_Buf : constant String :=
        (if Cfg.Ignore_Case then Crab_Fold.Fold (Data) else Data);

      procedure Process_Chunk
        (Chunk_Slice : String; Offset : Natural)
      is
         Orig_Chunk : constant String :=
           Data (Data'First + Offset ..
                 Data'First + Offset + Chunk_Slice'Length - 1);
      begin
         Crab_TopK.Insert
           (Heap      => Heap,
            Score     => Crab_Scorer.Score (Scorer, Chunk_Slice),
            File_Path => Path,
            Offset    => Offset,
            Data      => Orig_Chunk);
      end Process_Chunk;

   begin
      if Cfg.Chunk_Lines > 0 then
         --  Line-mode
         declare
            Chunker : Crab_Chunker.Line_State :=
              Crab_Chunker.Start_Lines
                (Scoring_Buf, Cfg.Chunk_Lines, Cfg.Overlap);
         begin
            while Crab_Chunker.Has_Next (Chunker) loop
               declare
                  Chunk_Slice : constant String :=
                    Crab_Chunker.Next (Chunker);
                  Offset : constant Natural :=
                    Chunk_Slice'First - Scoring_Buf'First;
               begin
                  Process_Chunk (Chunk_Slice, Offset);
               end;
            end loop;
         end;
      else
         --  Byte-mode
         declare
            Chunker : Crab_Chunker.State :=
              Crab_Chunker.Start
                (Scoring_Buf, Cfg.Chunk_Size, Cfg.Overlap);
         begin
            while Crab_Chunker.Has_Next (Chunker) loop
               declare
                  Chunk_Slice : constant String :=
                    Crab_Chunker.Next (Chunker);
                  Offset : constant Natural :=
                    Chunk_Slice'First - Scoring_Buf'First;
               begin
                  Process_Chunk (Chunk_Slice, Offset);
               end;
            end loop;
         end;
      end if;
   end Process_One_File;

   --  =================================================================
   --  I/O Helpers
   --  =================================================================

   function Read_Stdin return String is
      use Ada.Text_IO;
      LF   : constant Character := Ada.Characters.Latin_1.LF;
      Buf  : Unbounded_String;
      Line : String (1 .. 4096);
      Last : Natural;
   begin
      loop
         begin
            Get_Line (Line, Last);
            Append (Buf, Line (1 .. Last));
            Append (Buf, LF);
         exception
            when End_Error =>
               exit;
         end;
      end loop;
      --  Remove trailing LF if we added one
      if Length (Buf) > 0 then
         declare
            S : constant String := To_String (Buf);
         begin
            return S (S'First .. S'Last - 1);
         end;
      end if;
      return To_String (Buf);
   end Read_Stdin;

   function Read_File (Path : String) return String is
      use Ada.Text_IO;
      LF   : constant Character := Ada.Characters.Latin_1.LF;
      F    : File_Type;
      Buf  : Unbounded_String;
      Line : String (1 .. 4096);
      Last : Natural;
   begin
      Open (F, In_File, Path);
      loop
         begin
            Get_Line (F, Line, Last);
            Append (Buf, Line (1 .. Last));
            Append (Buf, LF);
         exception
            when End_Error =>
               exit;
         end;
      end loop;
      Close (F);
      --  Remove trailing LF if we added one
      if Length (Buf) > 0 then
         declare
            S : constant String := To_String (Buf);
         begin
            return S (S'First .. S'Last - 1);
         end;
      end if;
      return To_String (Buf);
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error =>
         if Is_Open (F) then
            Close (F);
         end if;
         raise;
   end Read_File;

   --  =================================================================
   --  Main
   --  =================================================================

   Cfg : Config;

begin
   Parse_Args (Cfg);

   if Cfg.Show_Help then
      Print_Usage;
      Ada.Command_Line.Set_Exit_Status (0);
      return;
   end if;

   if Cfg.Show_Version then
      Ada.Text_IO.Put_Line (Crab_Config.Crate_Version);
      Ada.Command_Line.Set_Exit_Status (0);
      return;
   end if;

   --  Prepare query
   declare
      Query_Str : constant String := To_String (Cfg.Query);
      Scoring_Query : constant String :=
        (if Cfg.Ignore_Case
         then Crab_Fold.Fold (Query_Str)
         else Query_Str);
      Scorer : Crab_Scorer.State :=
        Crab_Scorer.Init
          (Scoring_Query, (if Cfg.Chunk_Lines > 0 then 1 else Cfg.Chunk_Size),
               Cfg.Algorithm, Cfg.Level);
      Top_Heap : Crab_TopK.Heap (K => Cfg.Top_K) :=
        Crab_TopK.Create (K => Cfg.Top_K, Invert => Cfg.Invert);

      Has_Dirs  : Boolean := False;
   begin
      --  Check if any given path is a directory
      for P of Cfg.Paths loop
         begin
            if Ada.Directories.Kind (P) = Ada.Directories.Directory then
               Has_Dirs := True;
            end if;
         exception
            when others =>
               null;
         end;
      end loop;

      --  Determine file list
      if Cfg.Recursive or else Has_Dirs then
         --  If directories are given without -r, warn and continue
         --  with regular files only
         if Has_Dirs and then not Cfg.Recursive then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: directories require -r; skipping directories");
         end if;

         declare
            Scanner_Warnings : Crab_Scanner.String_Vectors.Vector;
            Files : constant Crab_Scanner.File_Lists.Vector :=
              Crab_Scanner.Scan
                (Root_Paths   => Cfg.Paths,
                 Recursive    => Cfg.Recursive,
                 Max_Depth    => Cfg.Max_Depth,
                 Include_Pats => Cfg.Include_Pats,
                 Exclude_Pats => Cfg.Exclude_Pats,
                 Ignore_Case  => Cfg.Ignore_Case,
                 Warnings     => Scanner_Warnings);
         begin
            --  Print warnings
            for W of Scanner_Warnings loop
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, W);
            end loop;

            if Files.Is_Empty then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crab: no files found or readable");
               Ada.Command_Line.Set_Exit_Status (2);
               return;
            end if;

            --  Process each file
            for F of Files loop
               declare
                  Path : constant String := To_String (F.Path);
               begin
                  Process_One_File
                    (Path   => Path,
                     Data   => Read_File (Path),
                     Heap   => Top_Heap,
                     Scorer => Scorer,
                     Cfg    => Cfg);
               exception
                  when E : Ada.Text_IO.Name_Error |
                           Ada.Text_IO.Use_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: " & Path & ": "
                        & Ada.Exceptions.Exception_Message (E));
                     Ada.Command_Line.Set_Exit_Status (2);
                     return;
               end;
            end loop;
         end;

      elsif not Cfg.Paths.Is_Empty then
         --  Explicit file arguments, no recursion
         for P of Cfg.Paths loop
            declare
               Path : constant String := P;
            begin
               --  Silently skip directories when not recursive
               if Ada.Directories.Kind (Path) =
                 Ada.Directories.Directory
               then
                  null;
               else
                  Process_One_File
                    (Path   => Path,
                     Data   => Read_File (Path),
                     Heap   => Top_Heap,
                     Scorer => Scorer,
                     Cfg    => Cfg);
               end if;
            exception
               when E : Ada.Text_IO.Name_Error |
                        Ada.Text_IO.Use_Error =>
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: " & Path & ": "
                     & Ada.Exceptions.Exception_Message (E));
                  Ada.Command_Line.Set_Exit_Status (2);
                  return;
            end;
         end loop;

         if Crab_TopK.Is_Empty (Top_Heap) then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: empty input -- no chunks");
            Ada.Command_Line.Set_Exit_Status (4);
            return;
         end if;

      else
         --  Stdin input
         declare
            Data : constant String := Read_Stdin;
         begin
            if Data'Length = 0 then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crab: empty input -- no chunks");
               Ada.Command_Line.Set_Exit_Status (4);
               return;
            end if;
            Process_One_File
              (Path   => "(stdin)",
               Data   => Data,
               Heap   => Top_Heap,
               Scorer => Scorer,
               Cfg    => Cfg);
         end;
      end if;

      --  Output
      if Crab_TopK.Is_Empty (Top_Heap) then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crab: empty input -- no chunks");
         Ada.Command_Line.Set_Exit_Status (4);
         return;
      end if;

      Crab_TopK.Print (Top_Heap);
      Ada.Command_Line.Set_Exit_Status (0);
   end;

exception
   when Program_Error =>
      null;
   when Crab_Compression.Compression_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "crab: compression error");
      Ada.Command_Line.Set_Exit_Status (3);
   when E : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "crab: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (1);
end Crab;
