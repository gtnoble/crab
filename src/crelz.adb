with Ada.Command_Line;
with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Crab_Buffers;
with Crab_Config;
with Crab_ELZ;

procedure Crelz is

   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Kind;
   use type Ada.Streams.Stream_Element_Offset;

   --  =================================================================
   --  Types
   --  =================================================================

   subtype Byte is Ada.Streams.Stream_Element;
   use type Byte;

   type Word64 is mod 2**64;
   type Word32 is mod 2**32;

   --  17-byte fixed .ez header
   Header_Size : constant := 17;
   Magic_CRELZ  : constant String := "CREL";

   package String_Vectors is
     new Ada.Containers.Indefinite_Vectors (Positive, String);

   --  =================================================================
   --  Configuration
   --  =================================================================

   type Config is record
      Show_Help      : Boolean := False;
      Show_Version   : Boolean := False;
      Decompress     : Boolean := False;
      Stdout_Mode    : Boolean := False;
      Keep           : Boolean := False;
      Force          : Boolean := False;
      Verbose        : Boolean := False;
      Test_Integrity : Boolean := False;
      Quiet          : Boolean := False;
      Recursive      : Boolean := False;
      Level          : Natural := 6;         -- 1..9 preset
      Max_Codes      : Natural := 1_000_000; -- preset by Level
      Max_Set        : Boolean := False;     -- True when --max-codes given
      Suffix         : Unbounded_String;
      Paths          : String_Vectors.Vector;
   end record;

   --  =================================================================
   --  Level to Max_Codes mapping (REQ-086)
   --  =================================================================

   function Level_To_Max_Codes (Level : Natural) return Natural is
   begin
      case Level is
         when 1      => return 1_000;
         when 2      => return 5_000;
         when 3      => return 10_000;
         when 4      => return 50_000;
         when 5      => return 250_000;
         when 6      => return 1_000_000;
         when 7      => return 2_500_000;
         when 8      => return 5_000_000;
         when 9      => return 0;  -- unbounded
         when others => return 0;  -- unbounded
      end case;
   end Level_To_Max_Codes;

   --  =================================================================
   --  Usage
   --  =================================================================

   procedure Print_Usage is
   begin
      Ada.Text_IO.Put_Line
        ("Usage: crelz [OPTIONS] [FILE...]");
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line
        ("Compress or decompress files using ELZ compression.");
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line ("Options:");
      Ada.Text_IO.Put_Line
        ("  -h, --help              Show this help");
      Ada.Text_IO.Put_Line
        ("  --version               Show version");
      Ada.Text_IO.Put_Line
        ("  -d, --decompress        Decompress");
      Ada.Text_IO.Put_Line
        ("  -c, --stdout            Write to standard output,"
         & " keep original files");
      Ada.Text_IO.Put_Line
        ("  -k, --keep              Keep input files"
         & " (do not delete)");
      Ada.Text_IO.Put_Line
        ("  -f, --force             Overwrite existing output files");
      Ada.Text_IO.Put_Line
        ("  -v, --verbose           Print compression ratio");
      Ada.Text_IO.Put_Line
        ("  -t, --test              Test compressed file integrity");
      Ada.Text_IO.Put_Line
        ("  -q, --quiet             Suppress warnings");
      Ada.Text_IO.Put_Line
        ("  -r, --recursive         Process directories recursively");
      Ada.Text_IO.Put_Line
        ("  -S, --suffix SUF        Use SUF as suffix (default .ez)");
      Ada.Text_IO.Put_Line
        ("  -1..-9                  Compression level"
         & " (default -6)");
      Ada.Text_IO.Put_Line
        ("      --fast              Fastest compression (same as -1)");
      Ada.Text_IO.Put_Line
        ("      --best              Best compression (same as -9)");
      Ada.Text_IO.Put_Line
        ("      --max-codes N        Maximum ELZ codes"
         & " (0 = unbounded)");
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line
        ("If no FILEs are given, or FILE is -, read from"
         & " standard input.");
   end Print_Usage;

   --  =================================================================
   --  Argument Parsing
   --  =================================================================

   procedure Parse_Args (Cfg : out Config) is
      I : Natural := 1;
   begin
      Cfg := (others => <>);
      Cfg.Suffix := To_Unbounded_String (".ez");
      Cfg.Max_Codes := Level_To_Max_Codes (Cfg.Level);

      while I <= Ada.Command_Line.Argument_Count loop
         declare
            Arg : constant String := Ada.Command_Line.Argument (I);
         begin
            if Arg = "--help" or else Arg = "-h" then
               Cfg.Show_Help := True;
               return;
            elsif Arg = "--version" then
               Cfg.Show_Version := True;
               return;
            elsif Arg = "-d" or else Arg = "--decompress" then
               Cfg.Decompress := True;
            elsif Arg = "-c" or else Arg = "--stdout" then
               Cfg.Stdout_Mode := True;
            elsif Arg = "-k" or else Arg = "--keep" then
               Cfg.Keep := True;
            elsif Arg = "-f" or else Arg = "--force" then
               Cfg.Force := True;
            elsif Arg = "-v" or else Arg = "--verbose" then
               Cfg.Verbose := True;
            elsif Arg = "-t" or else Arg = "--test" then
               Cfg.Test_Integrity := True;
            elsif Arg = "-q" or else Arg = "--quiet" then
               Cfg.Quiet := True;
            elsif Arg = "-r" or else Arg = "--recursive" then
               Cfg.Recursive := True;
            elsif Arg = "--fast" then
               Cfg.Level := 1;
               if not Cfg.Max_Set then
                  Cfg.Max_Codes := Level_To_Max_Codes (1);
               end if;
            elsif Arg = "--best" then
               Cfg.Level := 9;
               if not Cfg.Max_Set then
                  Cfg.Max_Codes := Level_To_Max_Codes (9);
               end if;
            elsif Arg'Length = 2 and then Arg (1) = '-'
              and then Arg (2) in '1' .. '9'
            then
               Cfg.Level := Character'Pos (Arg (2))
                 - Character'Pos ('0');
               if not Cfg.Max_Set then
                  Cfg.Max_Codes :=
                    Level_To_Max_Codes (Cfg.Level);
               end if;
            elsif Arg = "-S" or else Arg = "--suffix" then
               I := I + 1;
               if I > Ada.Command_Line.Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crelz: --suffix requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               Cfg.Suffix :=
                 To_Unbounded_String
                   (Ada.Command_Line.Argument (I));
            elsif Arg = "--max-codes" then
               I := I + 1;
               if I > Ada.Command_Line.Argument_Count then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crelz: --max-codes requires a value");
                  Ada.Command_Line.Set_Exit_Status (1);
                  raise Program_Error;
               end if;
               begin
                  Cfg.Max_Codes :=
                    Natural'Value
                      (Ada.Command_Line.Argument (I));
                  Cfg.Max_Set := True;
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crelz: invalid max-codes '"
                        & Ada.Command_Line.Argument (I) & "'");
                     Ada.Command_Line.Set_Exit_Status (1);
                     raise Program_Error;
               end;
            elsif Arg'Length > 0
              and then Arg (Arg'First) = '-'
            then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crelz: unknown flag '" & Arg & "'");
               Ada.Command_Line.Set_Exit_Status (1);
               raise Program_Error;
            else
               String_Vectors.Append (Cfg.Paths, Arg);
            end if;
         end;
         I := I + 1;
      end loop;

      --  If no paths are given, stdin is implied
      if String_Vectors.Is_Empty (Cfg.Paths) then
         String_Vectors.Append (Cfg.Paths, "-");
      end if;
   end Parse_Args;

   --  =================================================================
   --  I/O Helpers
   --  =================================================================

   function Read_Stdin return Unbounded_String is
      F      : Ada.Streams.Stream_IO.File_Type;
      Buf    : Ada.Streams.Stream_Element_Array (1 .. 65536);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Unbounded_String;
   begin
      Ada.Streams.Stream_IO.Open
        (F, Ada.Streams.Stream_IO.In_File, "/dev/stdin");
      loop
         Ada.Streams.Stream_IO.Read (F, Buf, Last);
         declare
            Chunk : String (1 .. Natural (Last));
         begin
            for J in 1 .. Last loop
               Chunk (Natural (J)) := Character'Val (Buf (J));
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
   begin
      Ada.Streams.Stream_IO.Open
        (F, Ada.Streams.Stream_IO.In_File, Path);
      loop
         Ada.Streams.Stream_IO.Read (F, Buf, Last);
         declare
            Chunk : String (1 .. Natural (Last));
         begin
            for J in 1 .. Last loop
               Chunk (Natural (J)) := Character'Val (Buf (J));
            end loop;
            Append (Result, Chunk);
         end;
         exit when Last < Buf'Last;
      end loop;
      Ada.Streams.Stream_IO.Close (F);
      return Result;
   end Read_File;

   --  Buffer size for chunked file/stdout writes (avoids stack overflow).
   Write_Chunk_Size : constant := 65536;

   procedure Write_File
     (Path : String;
      Data : String)
   is
      F : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create
        (F, Ada.Streams.Stream_IO.Out_File, Path);
      declare
         Pos : Natural := Data'First;
      begin
         while Pos <= Data'Last loop
            declare
               Remaining : constant Natural := Data'Last - Pos + 1;
               Len       : constant Ada.Streams.Stream_Element_Offset :=
                 Ada.Streams.Stream_Element_Offset'Min
                   (Ada.Streams.Stream_Element_Offset
                      (Write_Chunk_Size),
                    Ada.Streams.Stream_Element_Offset (Remaining));
               S : Ada.Streams.Stream_Element_Array (1 .. Len);
            begin
               for J in 1 .. Len loop
                  S (J) :=
                    Byte (Character'Pos
                      (Data (Pos + Natural (J) - 1)));
               end loop;
               Ada.Streams.Stream_IO.Write (F, S);
            end;
            Pos := Pos + Write_Chunk_Size;
         end loop;
      end;
      Ada.Streams.Stream_IO.Close (F);
   end Write_File;

   procedure Write_Stdout (Data : String) is
      F : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Open
        (F, Ada.Streams.Stream_IO.Out_File, "/dev/stdout");
      declare
         Pos : Natural := Data'First;
      begin
         while Pos <= Data'Last loop
            declare
               Remaining : constant Natural := Data'Last - Pos + 1;
               Len       : constant Ada.Streams.Stream_Element_Offset :=
                 Ada.Streams.Stream_Element_Offset'Min
                   (Ada.Streams.Stream_Element_Offset
                      (Write_Chunk_Size),
                    Ada.Streams.Stream_Element_Offset (Remaining));
               S : Ada.Streams.Stream_Element_Array (1 .. Len);
            begin
               for J in 1 .. Len loop
                  S (J) :=
                    Byte (Character'Pos
                      (Data (Pos + Natural (J) - 1)));
               end loop;
               Ada.Streams.Stream_IO.Write (F, S);
            end;
            Pos := Pos + Write_Chunk_Size;
         end loop;
      end;
      Ada.Streams.Stream_IO.Close (F);
   end Write_Stdout;

   --  =================================================================
   --  .ez Header Serialization (REQ-091)
   --  =================================================================

   subtype Header_Bytes is
     Ada.Streams.Stream_Element_Array (1 .. Header_Size);

   procedure Write_Header
     (H             : out Header_Bytes;
      Original_Size : Word64;
      Max_Codes     : Natural)
   is
      MC : constant Word32 := Word32 (Max_Codes);
   begin
      --  Magic "CRELZ"
      for J in Magic_CRELZ'Range loop
         H (Ada.Streams.Stream_Element_Offset (J)) :=
           Byte (Character'Pos (Magic_CRELZ (J)));
      end loop;
      --  Version = 2
      H (5) := 2;
      --  Original_Size (little-endian 64-bit)
      for J in 0 .. 7 loop
         H (6 + Ada.Streams.Stream_Element_Offset (J)) :=
           Byte (Original_Size / (2**(8 * J)) and 16#FF#);
      end loop;
      --  Max_Codes (little-endian 32-bit)
      for J in 0 .. 3 loop
         H (14 + Ada.Streams.Stream_Element_Offset (J)) :=
           Byte (MC / (2**(8 * J)) and 16#FF#);
      end loop;
   end Write_Header;

   procedure Read_Header
     (H             : Header_Bytes;
      Original_Size : out Word64;
      Max_Codes     : out Natural;
      OK            : out Boolean)
   is
   begin
      --  Verify magic
      for J in Magic_CRELZ'Range loop
         if Character'Val
              (H (Ada.Streams.Stream_Element_Offset (J)))
           /= Magic_CRELZ (J)
         then
            OK := False;
            return;
         end if;
      end loop;
      --  Verify version
      if H (5) /= 2 then
         OK := False;
         return;
      end if;
      --  Read Original_Size (little-endian 64-bit)
      Original_Size := 0;
      for J in reverse 0 .. 7 loop
         Original_Size :=
           Original_Size * 256
           + Word64
               (H (6 + Ada.Streams.Stream_Element_Offset (J)));
      end loop;
      --  Read Max_Codes (little-endian 32-bit)
      declare
         MC : Word32 := 0;
      begin
         for J in reverse 0 .. 3 loop
            MC :=
              MC * 256
              + Word32
                  (H (14 + Ada.Streams.Stream_Element_Offset (J)));
         end loop;
         Max_Codes := Natural (MC);
      end;
      OK := True;
   end Read_Header;

   --  =================================================================
   --  Suffix Detection (REQ-092)
   --  =================================================================

   function To_Lower (C : Character) return Character is
   begin
      if C in 'A' .. 'Z' then
         return Character'Val
           (Character'Pos (C)
            - Character'Pos ('A')
            + Character'Pos ('a'));
      end if;
      return C;
   end To_Lower;

   function To_Lower (S : String) return String is
      Result : String (S'Range);
   begin
      for J in S'Range loop
         Result (J) := To_Lower (S (J));
      end loop;
      return Result;
   end To_Lower;

   function Ends_With_Suffix
     (Name   : String;
      Suffix : String) return Boolean
   is
      Lower_Name   : constant String := To_Lower (Name);
      Lower_Suffix : constant String := To_Lower (Suffix);
   begin
      if Lower_Name'Length < Lower_Suffix'Length then
         return False;
      end if;
      --  Check for custom suffix as direct extension
      if Lower_Suffix'Length > 0
        and then Lower_Name'Length >= Lower_Suffix'Length
      then
         declare
            Tail : constant String :=
              Lower_Name
                (Lower_Name'Last - Lower_Suffix'Length + 1
                 .. Lower_Name'Last);
         begin
            if Tail = Lower_Suffix then
               return True;
            end if;
         end;
      end if;
      --  Check known .ez variants (when default suffix)
      if Suffix = ".ez" then
         if Lower_Name'Length >= 3
           and then Lower_Name (Lower_Name'Last - 2 .. Lower_Name'Last)
                    = ".ez"
         then
            return True;
         end if;
         if Lower_Name'Length >= 3
           and then Lower_Name (Lower_Name'Last - 2 .. Lower_Name'Last)
                    = "-cz"
         then
            return True;
         end if;
         if Lower_Name'Length >= 3
           and then Lower_Name (Lower_Name'Last - 2 .. Lower_Name'Last)
                    = "_cz"
         then
            return True;
         end if;
      end if;
      return False;
   end Ends_With_Suffix;

   function Strip_Suffix
     (Name   : String;
      Suffix : String) return String
   is
      Lower_Name   : constant String := To_Lower (Name);
      Lower_Suffix : constant String := To_Lower (Suffix);
      Suffix_Len   : Natural := 0;
   begin
      --  Determine which suffix variant matched
      if Lower_Suffix'Length > 0
        and then Lower_Name'Length >= Lower_Suffix'Length
      then
         declare
            Tail : constant String :=
              Lower_Name
                (Lower_Name'Last - Lower_Suffix'Length + 1
                 .. Lower_Name'Last);
         begin
            if Tail = Lower_Suffix then
               Suffix_Len := Lower_Suffix'Length;
            end if;
         end;
      end if;
      if Suffix_Len = 0 and then Suffix = ".ez" then
         if Lower_Name'Length >= 3
           and then Lower_Name (Lower_Name'Last - 2 .. Lower_Name'Last)
                    = ".ez"
         then
            Suffix_Len := 3;
         elsif Lower_Name'Length >= 3
           and then Lower_Name (Lower_Name'Last - 2 .. Lower_Name'Last)
                    = "-cz"
         then
            Suffix_Len := 3;
         elsif Lower_Name'Length >= 3
           and then Lower_Name (Lower_Name'Last - 2 .. Lower_Name'Last)
                    = "_cz"
         then
            Suffix_Len := 3;
         end if;
      end if;
      if Suffix_Len = 0 then
         --  No suffix matched; strip nothing
         return Name;
      end if;
      return Name (Name'First .. Name'Last - Suffix_Len);
   end Strip_Suffix;

   --  =================================================================
   --  File Existence & Overwrite Check (REQ-080)
   --  =================================================================

   function Is_Terminal return Boolean is
      TTY : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Open
        (TTY, Ada.Streams.Stream_IO.In_File, "/dev/tty");
      Ada.Streams.Stream_IO.Close (TTY);
      return True;
   exception
      when others =>
         return False;
   end Is_Terminal;

   function Confirm_Overwrite (Path : String) return Boolean is
      Answer : String (1 .. 10);
      Last   : Natural;
   begin
      if not Is_Terminal then
         return False;  -- non-interactive: refuse
      end if;
      Ada.Text_IO.Put
        (Ada.Text_IO.Standard_Error,
         "crelz: " & Path
         & " already exists; overwrite? (y/n) ");
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
      Ada.Text_IO.Get_Line (Answer, Last);
      return Last >= 1
        and then (Answer (1) = 'y' or else Answer (1) = 'Y');
   exception
      when others =>
         return False;
   end Confirm_Overwrite;

   --  =================================================================
   --  Compression (REQ-076)
   --  =================================================================

   procedure Compress_One
     (Input_Path : String;
      Input_Data : String;
      Cfg        : Config)
   is
      Stream     : Crab_ELZ.ELZ_Stream;
      Cbuf       : Crab_Buffers.Byte_Buffer;
      Dlen       : Natural;
      Hdr        : Header_Bytes;
      Out_Data   : Unbounded_String;
      Suffix_Str : constant String := To_String (Cfg.Suffix);
      Out_Path   : constant String := Input_Path & Suffix_Str;
      Orig_Size  : constant Word64 := Word64 (Input_Data'Length);
   begin
      --  Check output file exists
      if not Cfg.Stdout_Mode and then Input_Path /= "-" then
         if Ada.Directories.Exists (Out_Path) then
            if Cfg.Force then
               Ada.Directories.Delete_File (Out_Path);
            elsif not Confirm_Overwrite (Out_Path) then
               if not Cfg.Quiet then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "crelz: " & Out_Path
                     & " already exists; skipping");
               end if;
               return;
            else
               Ada.Directories.Delete_File (Out_Path);
            end if;
         end if;
      end if;

      --  Compress
      Crab_Buffers.Resize
        (Cbuf, Crab_ELZ.Compress_Bound (Input_Data'Length));
      Crab_ELZ.Init_Roots (Stream);
      Crab_ELZ.Set_Max_Codes (Stream, Cfg.Max_Codes);
      Crab_ELZ.Load_Dict (Stream, "");
      Crab_ELZ.Compress_Stream
        (Stream, Input_Data, Cbuf, 0, Dlen);

      --  Build header + compressed data
      Write_Header (Hdr, Orig_Size, Cfg.Max_Codes);
      for J in 1 .. Header_Size loop
         Append
           (Out_Data,
            Character'Val (Hdr (Ada.Streams.Stream_Element_Offset (J))));
      end loop;
      for J in 1 .. Dlen loop
         Append
           (Out_Data,
            Character'Val
              (Crab_Buffers.Raw_Data (Cbuf) (J)));
      end loop;

      --  Output
      if Cfg.Stdout_Mode or else Input_Path = "-" then
         Write_Stdout (To_String (Out_Data));
      else
         Write_File (Out_Path, To_String (Out_Data));
         --  Delete original if not keeping
         if not Cfg.Keep then
            Ada.Directories.Delete_File (Input_Path);
         end if;
      end if;

      --  Verbose
      if Cfg.Verbose then
         declare
            Orig_Len : constant Natural := Input_Data'Length;
            Comp_Len : constant Natural :=
              Header_Size + Dlen;
            Ratio    : constant Float :=
              (1.0 - Float (Comp_Len) / Float (Orig_Len)) * 100.0;
            Whole    : constant Integer := Integer (Ratio);
            Frac     : constant Integer :=
              Integer (Ratio * 10.0) rem 10;
         begin
            Ada.Text_IO.Put
              (Ada.Text_IO.Standard_Error,
               Input_Path & ": ");
            if not Cfg.Stdout_Mode
              and then Input_Path /= "-"
            then
               Ada.Text_IO.Put
                 (Ada.Text_IO.Standard_Error,
                  Natural'Image (Orig_Len)
                  & " -> "
                  & Natural'Image (Comp_Len));
            end if;
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "  "
               & Ada.Strings.Fixed.Trim
                   (Integer'Image (Whole),
                    Ada.Strings.Left)
               & "."
               & Integer'Image (Frac) (2 .. 2)
               & "%");
         end;
      end if;
   end Compress_One;

   --  =================================================================
   --  Decompression (REQ-077)
   --  =================================================================

   procedure Decompress_One
     (Input_Path : String;
      Input_Data : String;
      Cfg        : Config)
   is
      Hdr            : Header_Bytes;
      Orig_Size      : Word64;
      Max_Codes      : Natural;
      OK             : Boolean;
      Suffix_Str     : constant String := To_String (Cfg.Suffix);
      Out_Path       : Unbounded_String;
      Cbuf           : Crab_Buffers.Byte_Buffer;
      Result         : Unbounded_String;
      Compressed_Len : Natural;
   begin
      --  Check minimum size for header
      if Input_Data'Length < Header_Size then
         if not Cfg.Quiet then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crelz: " & Input_Path
               & ": file too small for .ez header");
         end if;
         return;
      end if;

      --  Parse header
      for J in 1 .. Header_Size loop
         Hdr (Ada.Streams.Stream_Element_Offset (J)) :=
           Byte
             (Character'Pos
                (Input_Data
                   (Input_Data'First + J - 1)));
      end loop;
      Read_Header (Hdr, Orig_Size, Max_Codes, OK);
      if not OK then
         if not Cfg.Quiet then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crelz: " & Input_Path
               & ": not in .ez format");
         end if;
         return;
      end if;

      --  Determine output path
      if Cfg.Stdout_Mode or else Input_Path = "-" then
         Out_Path := Null_Unbounded_String;
      else
         Out_Path :=
           To_Unbounded_String
             (Strip_Suffix (Input_Path, Suffix_Str));
      end if;

      --  Check output file exists
      if not Cfg.Stdout_Mode
        and then Input_Path /= "-"
      then
         declare
            OP : constant String := To_String (Out_Path);
         begin
            if Ada.Directories.Exists (OP) then
               if Cfg.Force then
                  Ada.Directories.Delete_File (OP);
               elsif not Confirm_Overwrite (OP) then
                  if not Cfg.Quiet then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crelz: " & OP
                        & " already exists; skipping");
                  end if;
                  return;
               else
                  Ada.Directories.Delete_File (OP);
               end if;
            end if;
         end;
      end if;

      --  Decompress
      Compressed_Len := Input_Data'Length - Header_Size;
      Crab_Buffers.Resize (Cbuf, Compressed_Len);
      for J in 1 .. Compressed_Len loop
         Crab_Buffers.Raw_Data (Cbuf) (J) :=
           Byte
             (Character'Pos
                (Input_Data
                   (Input_Data'First + Header_Size + J - 1)));
      end loop;

      begin
         Result :=
           To_Unbounded_String
             (Crab_ELZ.Decompress (Cbuf, Compressed_Len, Max_Codes));
      exception
         when Crab_ELZ.ELZ_Error =>
            if Cfg.Test_Integrity then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crelz: " & Input_Path
                  & ": decompression failed");
            else
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crelz: " & Input_Path
                  & ": decompression error");
            end if;
            Ada.Command_Line.Set_Exit_Status (3);
            return;
      end;

      --  Test integrity: verify size
      if Cfg.Test_Integrity then
         if Length (Result) = Natural (Orig_Size) then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               Input_Path & ": OK");
         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crelz: " & Input_Path
               & ": size mismatch (expected "
               & Word64'Image (Orig_Size)
               & ", got "
               & Natural'Image (Length (Result))
               & ")");
            Ada.Command_Line.Set_Exit_Status (3);
         end if;
         return;
      end if;

      --  Output
      if Cfg.Stdout_Mode or else Input_Path = "-" then
         Write_Stdout (To_String (Result));
      else
         Write_File (To_String (Out_Path), To_String (Result));
         --  Delete compressed file if not keeping
         if not Cfg.Keep then
            Ada.Directories.Delete_File (Input_Path);
         end if;
      end if;

      --  Verbose
      if Cfg.Verbose then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            Input_Path & ": "
            & Natural'Image (Input_Data'Length)
            & " -> "
            & Natural'Image (Length (Result)));
      end if;
   end Decompress_One;

   --  =================================================================
   --  Process One Input (dispatch)
   --  =================================================================

   procedure Process_Input
     (Input_Path : String;
      Cfg        : Config)
   is
      Data : Unbounded_String;
   begin
      if Input_Path = "-" then
         Data := Read_Stdin;
      else
         Data := Read_File (Input_Path);
      end if;

      if Length (Data) = 0 then
         if not Cfg.Quiet then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "crelz: " & Input_Path
               & ": empty input");
         end if;
         return;
      end if;

      if Cfg.Decompress or else Cfg.Test_Integrity then
         Decompress_One
           (Input_Path, To_String (Data), Cfg);
      else
         Compress_One
           (Input_Path, To_String (Data), Cfg);
      end if;
   exception
      when Ada.Streams.Stream_IO.Name_Error |
           Ada.Streams.Stream_IO.Use_Error =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "crelz: " & Input_Path
            & ": cannot open file");
         Ada.Command_Line.Set_Exit_Status (2);
         raise Program_Error;
   end Process_Input;

   --  =================================================================
   --  Recursive Traversal (REQ-084)
   --  =================================================================

   procedure Sort_Entries
     (Entries : in out String_Vectors.Vector)
   is
      N     : constant Natural :=
        Natural (String_Vectors.Length (Entries));
      Temp  : Unbounded_String;
      Swapped : Boolean;
   begin
      if N <= 1 then
         return;
      end if;
      loop
         Swapped := False;
         for I in 1 .. N - 1 loop
            if String_Vectors.Element (Entries, I)
              > String_Vectors.Element (Entries, I + 1)
            then
               Temp :=
                 To_Unbounded_String
                   (String_Vectors.Element (Entries, I));
               String_Vectors.Replace_Element
                 (Entries, I,
                  String_Vectors.Element (Entries, I + 1));
               String_Vectors.Replace_Element
                 (Entries, I + 1, To_String (Temp));
               Swapped := True;
            end if;
         end loop;
         exit when not Swapped;
      end loop;
   end Sort_Entries;

   procedure Process_Directory
     (Dir_Path : String;
      Cfg      : Config);

   procedure Process_Directory
     (Dir_Path : String;
      Cfg      : Config)
   is
      Search     : Ada.Directories.Search_Type;
      Ent        : Ada.Directories.Directory_Entry_Type;
      Entries    : String_Vectors.Vector;
      Suffix_Str : constant String := To_String (Cfg.Suffix);
   begin
      Ada.Directories.Start_Search
        (Search, Dir_Path, "",
         (Ada.Directories.Ordinary_File => True,
          Ada.Directories.Directory     => True,
          Ada.Directories.Special_File  => False));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         declare
            Name : constant String :=
              Ada.Directories.Simple_Name (Ent);
         begin
            if Name /= "." and then Name /= ".." then
               String_Vectors.Append
                 (Entries,
                  Ada.Directories.Full_Name (Ent));
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);

      --  Sort for deterministic order
      Sort_Entries (Entries);

      --  Process entries depth-first
      declare
         N         : constant Natural :=
           Natural (String_Vectors.Length (Entries));
         Full_Path : Unbounded_String;
      begin
         for I in 1 .. N loop
            Full_Path :=
              To_Unbounded_String
                (String_Vectors.Element (Entries, I));
            declare
               FP : constant String := To_String (Full_Path);
            begin
               if Ada.Directories.Kind (FP)
                 = Ada.Directories.Directory
               then
                  Process_Directory (FP, Cfg);
               elsif Ada.Directories.Kind (FP)
                 = Ada.Directories.Ordinary_File
               then
                  --  In decompress mode, only process .ez files
                  if Cfg.Decompress or else Cfg.Test_Integrity then
                     if Suffix_Str = ""
                       or else Ends_With_Suffix
                         (Ada.Directories.Simple_Name (FP),
                          Suffix_Str)
                     then
                        Process_Input (FP, Cfg);
                     end if;
                  else
                     Process_Input (FP, Cfg);
                  end if;
               end if;
            exception
               when Program_Error =>
                  raise;
               when others =>
                  if not Cfg.Quiet then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "crelz: warning: " & FP
                        & ": cannot access");
                  end if;
            end;
         end loop;
      end;
   end Process_Directory;

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

   --  Process all paths
   declare
      N : constant Natural :=
        Natural (String_Vectors.Length (Cfg.Paths));
   begin
      for I in 1 .. N loop
         declare
            Path : constant String :=
              String_Vectors.Element (Cfg.Paths, I);
         begin
            if Path = "-" then
               Process_Input (Path, Cfg);
            elsif Cfg.Recursive
              and then Ada.Directories.Exists (Path)
              and then Ada.Directories.Kind (Path)
                = Ada.Directories.Directory
            then
               Process_Directory (Path, Cfg);
            else
               Process_Input (Path, Cfg);
            end if;
         exception
            when Program_Error =>
               --  Error already reported; propagate exit code
               return;
            when E : others =>
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "crelz: " & Path & ": "
                  & Ada.Exceptions.Exception_Message (E));
               Ada.Command_Line.Set_Exit_Status (2);
               return;
         end;
      end loop;
   end;

   Ada.Command_Line.Set_Exit_Status (0);

exception
   when Program_Error =>
      null;  -- exit code already set
   when E : Crab_ELZ.ELZ_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "crelz: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (3);
   when E : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "crelz: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (1);
end Crelz;
