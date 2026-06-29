with Ada.Command_Line;
with Ada.Directories;
with GNAT.Traceback;
with GNAT.Traceback.Symbolic;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
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
      Show_Help       : Boolean := False;
      Show_Version    : Boolean := False;
      Query           : Unbounded_String;
      Algorithm       : Crab_Compression.Algorithm := Crab_Compression.Deflate;
      Level           : Integer := Crab_Compression.Level_Default
                                     (Crab_Compression.Deflate);
      Chunk_Size      : Natural := 0;   --  0 = not set
      Chunk_Lines     : Natural := 0;   --  0 = not set;
      Overlap         : Natural := 0;
      Top_K           : Positive := 10;
      Recursive       : Boolean := False;
      Ignore_Case     : Boolean := False;
      Invert          : Boolean := False;
      File_Mode       : Boolean := False;
      LZMA_Dict_Size  : Natural := 8_388_608;  -- 8 MB default
      LZW_Max_Codes   : Natural := 0;           -- 0 = unbounded
      Max_Depth       : Natural := Natural'Last;
      Include_Pats    : Crab_Glob.Pattern_List;
      Exclude_Pats    : Crab_Glob.Pattern_List;
      Paths           : Crab_Scanner.String_Vectors.Vector;
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
        ("  -a, --algorithm ALGO    Compression: deflate (default), lz4, lzw, lzma");
      Ada.Text_IO.Put_Line
        ("  -l, --level N           Compression level"
         & " (deflate: -1..9, lz4: 1..65537, lzw: ignored, lzma: 0..9)");
      Ada.Text_IO.Put_Line
        ("  -D, --dict-size N       LZMA dictionary size in bytes"
         & " (default 8M)");
      Ada.Text_IO.Put_Line
        ("      --lzw-max-codes N    Max LZW string-table codes"
         & " (default 0 = unbounded)");
      Ada.Text_IO.Put_Line
        ("  -s, --chunk-size N      Chunk size in bytes ");
      Ada.Text_IO.Put_Line
        ("  -L, --chunk-lines N     Chunk size in lines");
      Ada.Text_IO.Put_Line
        ("  -o, --overlap P         Overlap percentage 0-99"
         & " (default 0)");
      Ada.Text_IO.Put_Line
        ("  -k, --top N             Number of results to return"
         & " (default 10)");
      Ada.Text_IO.Put_Line
        ("  -r, --recursive         Search directories recursively");
      Ada.Text_IO.Put_Line
        ("  -i, --ignore-case       Case-insensitive matching");
      Ada.Text_IO.Put_Line
        ("  -v, --invert            Return least-similar results");
      Ada.Text_IO.Put_Line
        ("  -f, --file-mode         Compare query file against target files");
      Ada.Text_IO.Put_Line
        ("                        (no chunking; one score per file)");
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
                  elsif Val = "lzw" or else Val = "LZW" then
                     Cfg.Algorithm := Crab_Compression.LZW;
                  elsif Val = "lzma" or else Val = "LZMA" then
                     Cfg.Algorithm := Crab_Compression.LZMA;
                  else
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: unknown algorithm '" & Val
                        & "'; use deflate, lz4, lzw, or lzma");
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
            elsif Arg = "-D" or else Arg = "--dict-size" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --dict-size requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.LZMA_Dict_Size := Natural'Value (Argument (I));
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: invalid dict size '"
                        & Argument (I) & "'");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
               end;
            elsif Arg = "--lzw-max-codes" then
               I := I + 1;
               if I > Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: --lzw-max-codes requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.LZW_Max_Codes := Natural'Value (Argument (I));
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: invalid lzw-max-codes '"
                        & Argument (I) & "'");
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
            elsif Arg = "-f" or else Arg = "--file-mode" then
               Cfg.File_Mode := True;
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

      if not Cfg.File_Mode then
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
      end if;

      if Cfg.Algorithm = Crab_Compression.Deflate then
         if Cfg.Level < -1 or else Cfg.Level > 9 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: deflate level must be in range -1..9");
            Ada.Command_Line.Set_Exit_Status (1);
            raise Program_Error;
         end if;
      elsif Cfg.Algorithm = Crab_Compression.LZ4 then
         if Cfg.Level < 1 or else Cfg.Level > 65_537 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: lz4 level must be in range 1..65537");
            Ada.Command_Line.Set_Exit_Status (1);
            raise Program_Error;
         end if;
      elsif Cfg.Algorithm = Crab_Compression.LZMA then
         if Cfg.Level < 0 or else Cfg.Level > 9 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: lzma level must be in range 0..9");
            Ada.Command_Line.Set_Exit_Status (1);
            raise Program_Error;
         end if;
         if Cfg.LZMA_Dict_Size = 0 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: lzma dict size must be positive");
            Ada.Command_Line.Set_Exit_Status (1);
            raise Program_Error;
         end if;
      end if;

      if Cfg.LZW_Max_Codes > 0
        and then Cfg.Algorithm /= Crab_Compression.LZW
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crab: --lzw-max-codes is only valid with --algorithm lzw");
         Ada.Command_Line.Set_Exit_Status (1);
         raise Program_Error;
      end if;
   end Parse_Args;

   --  =================================================================
   --  File Processing
   --  =================================================================

   procedure Process_One_File
     (Path   : String;
      Data   : Unbounded_String;
      Heap   : in out Crab_TopK.Heap;
      Scorer : in out Crab_Scorer.State;
      Cfg    : Config)
   is
      Scoring_Str : constant String :=
        (if Cfg.Ignore_Case
         then Crab_Fold.Fold_Heap (To_String (Data))
         else To_String (Data));
      Data_Str    : constant String := To_String (Data);
      Win_Size : constant Natural :=
        (if Cfg.Algorithm = Crab_Compression.LZMA
         then Cfg.LZMA_Dict_Size
         else Crab_Compression.Window_Size (Cfg.Algorithm));
      procedure Process_Chunk
        (Chunk_Slice  : String;
         Byte_Offset  : Natural;
         Output_Offset : Natural)
      is
      begin
         Crab_TopK.Insert
           (Heap      => Heap,
            Score     => Crab_Scorer.Score (Scorer, Chunk_Slice),
            File_Path => Path,
            Offset    => Output_Offset,
            Data      => Data_Str
              (Data_Str'First + Byte_Offset ..
               Data_Str'First + Byte_Offset + Chunk_Slice'Length - 1));
      end Process_Chunk;
   begin
      if Win_Size < Natural'Last
        and then Data_Str'Length > Win_Size
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crab: warning: '" & Path
            & "' (" & Natural'Image (Data_Str'Length)
            & " bytes) exceeds "
            & Crab_Compression.Algorithm'Image (Cfg.Algorithm)
            & " window size ("
            & Natural'Image (Win_Size)
            & " bytes); scoring accuracy may be reduced");
      end if;

      if Cfg.Chunk_Lines > 0 then
         declare
            Chunker : Crab_Chunker.Line_State :=
              Crab_Chunker.Start_Lines
                (Scoring_Str, Cfg.Chunk_Lines, Cfg.Overlap);
         begin
            while Crab_Chunker.Has_Next (Chunker) loop
               declare
                  Chunk_Slice : constant String :=
                    Crab_Chunker.Next (Chunker);
                  Byte_Offset  : constant Natural :=
                    Chunk_Slice'First - Scoring_Str'First;
                  Line_Offset  : constant Natural :=
                    Crab_Chunker.Start_Line (Chunker);
               begin
                  Process_Chunk (Chunk_Slice, Byte_Offset, Line_Offset);
               end;
            end loop;
         end;
      else
         declare
            Chunker : Crab_Chunker.State :=
              Crab_Chunker.Start
                (Scoring_Str, Cfg.Chunk_Size, Cfg.Overlap);
         begin
            while Crab_Chunker.Has_Next (Chunker) loop
               declare
                  Chunk_Slice : constant String :=
                    Crab_Chunker.Next (Chunker);
                  Offset : constant Natural :=
                    Chunk_Slice'First - Scoring_Str'First;
               begin
                  Process_Chunk (Chunk_Slice, Offset, Offset);
               end;
            end loop;
         end;
      end if;
   end Process_One_File;

   --  =================================================================
   --  I/O Helpers
   --  =================================================================

   function Read_Stdin return Unbounded_String is
      F      : Ada.Streams.Stream_IO.File_Type;
      Buf    : Ada.Streams.Stream_Element_Array (1 .. 65536);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Unbounded_String;
      use type Ada.Streams.Stream_Element_Offset;
   begin
      Ada.Streams.Stream_IO.Open
        (F, Ada.Streams.Stream_IO.In_File, "/dev/stdin");
      loop
         Ada.Streams.Stream_IO.Read (F, Buf, Last);
         declare
            Chunk : String (1 .. Natural (Last));
         begin
            for I in 1 .. Last loop
               Chunk (Natural (I)) := Character'Val (Buf (I));
            end loop;
            Append (Result, Chunk);
         end;
         exit when Last < Buf'Last;
      end loop;
      Ada.Streams.Stream_IO.Close (F);
      return Result;
   end Read_Stdin;

   function Read_File (Path : String) return Unbounded_String is
      F      : Ada.Streams.Stream_IO.File_Type;
      Buf    : Ada.Streams.Stream_Element_Array (1 .. 65536);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Unbounded_String;
      use type Ada.Streams.Stream_Element_Offset;
   begin
      Ada.Streams.Stream_IO.Open
        (F, Ada.Streams.Stream_IO.In_File, Path);
      loop
         Ada.Streams.Stream_IO.Read (F, Buf, Last);
         declare
            Chunk : String (1 .. Natural (Last));
         begin
            for I in 1 .. Last loop
               Chunk (Natural (I)) := Character'Val (Buf (I));
            end loop;
            Append (Result, Chunk);
         end;
         exit when Last < Buf'Last;
      end loop;
      Ada.Streams.Stream_IO.Close (F);
      return Result;
   exception
      when Ada.Streams.Stream_IO.Name_Error |
           Ada.Streams.Stream_IO.Use_Error =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         raise;
   end Read_File;

   procedure Print_Traceback is
      Tb  : GNAT.Traceback.Tracebacks_Array (1 .. 100);
      Len : Natural;
   begin
      GNAT.Traceback.Call_Chain (Tb, Len);
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         GNAT.Traceback.Symbolic.Symbolic_Traceback (Tb (1 .. Len)));
   end Print_Traceback;

   --  =================================================================
   --  Window-size helper for LZMA
   --  =================================================================

   function Effective_Window_Size (Cfg : Config) return Natural is
   begin
      if Cfg.Algorithm = Crab_Compression.LZMA then
         return Cfg.LZMA_Dict_Size;
      elsif Cfg.Algorithm = Crab_Compression.LZW
        and then Cfg.LZW_Max_Codes > 0
      then
         return Cfg.LZW_Max_Codes;
      else
         return Crab_Compression.Window_Size (Cfg.Algorithm);
      end if;
   end Effective_Window_Size;

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

   --  ===============================================================
   --  File-mode: compare query file against target files
   --  ===============================================================

   if Cfg.File_Mode then
      declare
         Query_Path : constant String := To_String (Cfg.Query);
         Query_Data : constant Unbounded_String := Read_File (Query_Path);
         Query_Str  : constant String := To_String (Query_Data);
         Scorer     : Crab_Scorer.State (Algo => Cfg.Algorithm);
         Top_Heap   : Crab_TopK.Heap (K => Cfg.Top_K) :=
           Crab_TopK.Create (K => Cfg.Top_K, Invert => Cfg.Invert);
         Win_Size   : constant Natural := Effective_Window_Size (Cfg);
         Has_Dirs   : Boolean := False;
      begin
         Crab_Scorer.Init
           (Scorer,
            (if Cfg.Ignore_Case
             then Crab_Fold.Fold_Heap (Query_Str)
             else Query_Str),
            Length (Query_Data),
            Cfg.Level,
            Dict_Size     => Cfg.LZMA_Dict_Size,
            LZW_Max_Codes => Cfg.LZW_Max_Codes);

         if Win_Size < Natural'Last
           and then Length (Query_Data) > Win_Size
         then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: warning: query file '" & Query_Path
               & "' (" & Natural'Image (Length (Query_Data))
               & " bytes) exceeds "
               & Crab_Compression.Algorithm'Image (Cfg.Algorithm)
               & " window size ("
               & Natural'Image (Win_Size)
               & " bytes); scoring accuracy may be reduced");
         end if;

         for P of Cfg.Paths loop
            begin
               if Ada.Directories.Kind (P) = Ada.Directories.Directory then
                  Has_Dirs := True;
               end if;
            exception
               when others => null;
            end;
         end loop;

         if Cfg.Recursive or else Has_Dirs then
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
               for W of Scanner_Warnings loop
                  Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, W);
               end loop;
               if Files.Is_Empty then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: no files found or readable");
                  Print_Traceback;
                  Ada.Command_Line.Set_Exit_Status (2);
                  return;
               end if;
               for F of Files loop
                  declare
                     Path : constant String := To_String (F.Path);
                  begin
                     if Path = Query_Path then
                        null;
                     else
                        declare
                           Data : constant Unbounded_String := Read_File (Path);
                           Data_Str : constant String := To_String (Data);
                        begin
                           if Win_Size < Natural'Last
                             and then Length (Data) > Win_Size
                           then
                              Ada.Text_IO.Put_Line
                                (Ada.Text_IO.Standard_Error,
                                 "crab: warning: '" & Path
                                 & "' (" & Natural'Image (Length (Data))
                                 & " bytes) exceeds "
                                 & Crab_Compression.Algorithm'Image
                                    (Cfg.Algorithm)
                                 & " window size ("
                                 & Natural'Image (Win_Size)
                                 & " bytes); scoring accuracy may be reduced");
                           end if;
                           Crab_TopK.Insert
                             (Heap      => Top_Heap,
                              Score     =>
                                Crab_Scorer.Score
                                  (Scorer,
                                   (if Cfg.Ignore_Case
                                    then Crab_Fold.Fold_Heap (Data_Str)
                                    else Data_Str)),
                              File_Path => Path,
                              Offset    => 0,
                              Data      => "");
                        end;
                     end if;
                  exception
                     when E : Ada.Streams.Stream_IO.Name_Error |
                              Ada.Streams.Stream_IO.Use_Error =>
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "crab: " & Path & ": "
                           & Ada.Exceptions.Exception_Message (E));
                        Print_Traceback;
                        Ada.Command_Line.Set_Exit_Status (2);
                        return;
                  end;
               end loop;
            end;
         elsif not Cfg.Paths.Is_Empty then
            for P of Cfg.Paths loop
               declare
                  Path : constant String := P;
               begin
                  if Ada.Directories.Kind (Path) =
                    Ada.Directories.Directory
                  then
                     null;
                  elsif Path = Query_Path then
                     null;
                  else
                     declare
                        Data : constant Unbounded_String := Read_File (Path);
                        Data_Str : constant String := To_String (Data);
                     begin
                        if Win_Size < Natural'Last
                          and then Length (Data) > Win_Size
                        then
                           Ada.Text_IO.Put_Line
                             (Ada.Text_IO.Standard_Error,
                              "crab: warning: '" & Path
                              & "' (" & Natural'Image (Length (Data))
                              & " bytes) exceeds "
                              & Crab_Compression.Algorithm'Image
                                 (Cfg.Algorithm)
                              & " window size ("
                              & Natural'Image (Win_Size)
                              & " bytes); scoring accuracy may be reduced");
                        end if;
                        Crab_TopK.Insert
                          (Heap      => Top_Heap,
                           Score     =>
                             Crab_Scorer.Score
                               (Scorer,
                                (if Cfg.Ignore_Case
                                 then Crab_Fold.Fold_Heap (Data_Str)
                                 else Data_Str)),
                           File_Path => Path,
                           Offset    => 0,
                           Data      => "");
                     end;
                  end if;
               exception
                  when E : Ada.Streams.Stream_IO.Name_Error |
                           Ada.Streams.Stream_IO.Use_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: " & Path & ": "
                        & Ada.Exceptions.Exception_Message (E));
                     Print_Traceback;
                     Ada.Command_Line.Set_Exit_Status (2);
                     return;
               end;
            end loop;

            if Crab_TopK.Is_Empty (Top_Heap) then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crab: no target files processed");
               Print_Traceback;
               Ada.Command_Line.Set_Exit_Status (4);
               return;
            end if;

         else
            declare
               Data : constant Unbounded_String := Read_Stdin;
               Data_Str : constant String := To_String (Data);
            begin
               if Length (Data) = 0 then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: empty input -- no data");
                  Print_Traceback;
                  Ada.Command_Line.Set_Exit_Status (4);
                  return;
               end if;
               if Win_Size < Natural'Last
                 and then Length (Data) > Win_Size
               then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: warning: stdin input ("
                     & Natural'Image (Length (Data))
                     & " bytes) exceeds "
                     & Crab_Compression.Algorithm'Image (Cfg.Algorithm)
                     & " window size ("
                     & Natural'Image (Win_Size)
                     & " bytes); scoring accuracy may be reduced");
               end if;
               Crab_TopK.Insert
                 (Heap      => Top_Heap,
                  Score     =>
                    Crab_Scorer.Score
                      (Scorer,
                       (if Cfg.Ignore_Case
                        then Crab_Fold.Fold_Heap (Data_Str)
                        else Data_Str)),
                  File_Path => "(stdin)",
                  Offset    => 0,
                  Data      => "");
            end;
         end if;

         if Crab_TopK.Is_Empty (Top_Heap) then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: no target files processed");
            Print_Traceback;
            Ada.Command_Line.Set_Exit_Status (4);
            return;
         end if;
         Crab_TopK.Print_File_Scores (Top_Heap);
         Ada.Command_Line.Set_Exit_Status (0);
      exception
         when E : Ada.Streams.Stream_IO.Name_Error |
                  Ada.Streams.Stream_IO.Use_Error =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: " & To_String (Cfg.Query) & ": "
               & Ada.Exceptions.Exception_Message (E));
            Print_Traceback;
            Ada.Command_Line.Set_Exit_Status (2);
      end;
      return;
   end if;

   --  ===============================================================
   --  Chunk-mode: compare query string against chunked input
   --  ===============================================================

   declare
      Query_Str : constant String := To_String (Cfg.Query);
      Scorer    : Crab_Scorer.State (Algo => Cfg.Algorithm);
      Top_Heap  : Crab_TopK.Heap (K => Cfg.Top_K) :=
        Crab_TopK.Create (K => Cfg.Top_K, Invert => Cfg.Invert);
      Has_Dirs  : Boolean := False;
   begin
      Crab_Scorer.Init
        (Scorer,
         (if Cfg.Ignore_Case
          then Crab_Fold.Fold_Heap (Query_Str)
          else Query_Str),
         (if Cfg.Chunk_Lines > 0 then 1 else Cfg.Chunk_Size),
         Cfg.Level,
         Dict_Size     => Cfg.LZMA_Dict_Size,
         LZW_Max_Codes => Cfg.LZW_Max_Codes);

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

      if Cfg.Recursive or else Has_Dirs then
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
            for W of Scanner_Warnings loop
               Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, W);
            end loop;

            if Files.Is_Empty then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crab: no files found or readable");
               Print_Traceback;
               Ada.Command_Line.Set_Exit_Status (2);
               return;
            end if;

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
                  when E : Ada.Streams.Stream_IO.Name_Error |
                           Ada.Streams.Stream_IO.Use_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crab: " & Path & ": "
                        & Ada.Exceptions.Exception_Message (E));
                     Print_Traceback;
                     Ada.Command_Line.Set_Exit_Status (2);
                     return;
               end;
            end loop;
         end;

      elsif not Cfg.Paths.Is_Empty then
         for P of Cfg.Paths loop
            declare
               Path : constant String := P;
            begin
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
               when E : Ada.Streams.Stream_IO.Name_Error |
                        Ada.Streams.Stream_IO.Use_Error =>
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crab: " & Path & ": "
                     & Ada.Exceptions.Exception_Message (E));
                  Print_Traceback;
                  Ada.Command_Line.Set_Exit_Status (2);
                  return;
            end;
         end loop;

         if Crab_TopK.Is_Empty (Top_Heap) then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crab: empty input -- no chunks");
            Print_Traceback;
            Ada.Command_Line.Set_Exit_Status (4);
            return;
         end if;

      else
         declare
            Data : constant Unbounded_String := Read_Stdin;
         begin
            if Length (Data) = 0 then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crab: empty input -- no chunks");
               Print_Traceback;
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

      if Crab_TopK.Is_Empty (Top_Heap) then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crab: empty input -- no chunks");
         Print_Traceback;
         Ada.Command_Line.Set_Exit_Status (4);
         return;
      end if;

      Crab_TopK.Print (Top_Heap);
      Ada.Command_Line.Set_Exit_Status (0);
   end;

exception
   when Program_Error =>
      Print_Traceback;
      null;
   when Crab_Compression.Compression_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "crab: compression error");
      Print_Traceback;
      Ada.Command_Line.Set_Exit_Status (3);
   when E : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "crab: " & Ada.Exceptions.Exception_Message (E));
      Print_Traceback;
      Ada.Command_Line.Set_Exit_Status (1);
end Crab;
