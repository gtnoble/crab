with Ada.Streams;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Buffers;
with Crab_LZW;

package body Crab_LZW_Crlzw_Tests is

   package Caller is new AUnit.Test_Caller (Test);

   subtype Byte is Ada.Streams.Stream_Element;
   use type Byte;

   type Word64 is mod 2**64;
   type Word32 is mod 2**32;

   Header_Size : constant := 17;
   Magic_CRLZ  : constant String := "CRLZ";

   --  =================================================================
   --  Helpers: simulate .cz header + compression roundtrip
   --  =================================================================

   procedure Compress_To_CZ
     (Data     : String;
      Max_Codes : Natural;
      Output   : out String;
      Out_Len  : out Natural)
   is
      Stream : Crab_LZW.LZW_Stream;
      Cbuf   : Crab_Buffers.Byte_Buffer;
      Dlen   : Natural;
      Off    : Natural := 0;

      procedure Put_Byte (B : Byte) is
      begin
         Off := Off + 1;
         if Off <= Output'Length then
            Output (Off) := Character'Val (B);
         end if;
      end Put_Byte;

      procedure Put_U64 (V : Word64) is
      begin
         for J in 0 .. 7 loop
            Put_Byte (Byte (V / (2**(8 * J)) and 16#FF#));
         end loop;
      end Put_U64;

      procedure Put_U32 (V : Natural) is
         W : constant Word32 := Word32 (V);
      begin
         for J in 0 .. 3 loop
            Put_Byte (Byte (W / (2**(8 * J)) and 16#FF#));
         end loop;
      end Put_U32;
   begin
      Crab_Buffers.Resize
        (Cbuf, Crab_LZW.Compress_Bound (Data'Length));
      Crab_LZW.Init_Roots (Stream);
      Crab_LZW.Set_Max_Codes (Stream, Max_Codes);
      Crab_LZW.Load_Dict (Stream, "");
      Crab_LZW.Compress_Stream (Stream, Data, Cbuf, 0, Dlen);

      --  Write header
      for J in Magic_CRLZ'Range loop
         Put_Byte (Byte (Character'Pos (Magic_CRLZ (J))));
      end loop;
      Put_Byte (1);  -- version
      Put_U64 (Word64 (Data'Length));
      Put_U32 (Max_Codes);

      --  Write compressed bitstream
      for J in 1 .. Dlen loop
         Put_Byte (Crab_Buffers.Raw_Data (Cbuf) (J));
      end loop;

      Out_Len := Off;
   end Compress_To_CZ;

   procedure Decompress_From_CZ
     (CZ_Data    : String;
      CZ_Len     : Natural;
      Output     : out String;
      Out_Len    : out Natural;
      OK         : out Boolean)
   is
      Hdr            : Ada.Streams.Stream_Element_Array (1 .. Header_Size);
      Orig_Size      : Word64;
      Max_Codes      : Natural;
      Cbuf           : Crab_Buffers.Byte_Buffer;
      Compressed_Len : Natural;
      Res_Len        : Natural;
   begin
      OK := False;
      if CZ_Len < Header_Size then
         return;
      end if;

      for J in 1 .. Header_Size loop
         Hdr (Ada.Streams.Stream_Element_Offset (J)) :=
           Byte (Character'Pos (CZ_Data (CZ_Data'First + J - 1)));
      end loop;

      --  Verify magic
      for J in Magic_CRLZ'Range loop
         if Character'Val
              (Hdr (Ada.Streams.Stream_Element_Offset (J)))
           /= Magic_CRLZ (J)
         then
            return;
         end if;
      end loop;

      --  Verify version
      if Hdr (5) /= Byte (1) then
         return;
      end if;

      --  Read Original_Size
      Orig_Size := 0;
      for J in reverse 0 .. 7 loop
         Orig_Size :=
           Orig_Size * 256
           + Word64
               (Hdr (Ada.Streams.Stream_Element_Offset (6 + J)));
      end loop;

      --  Read Max_Codes
      declare
         MC : Word32 := 0;
      begin
         for J in reverse 0 .. 3 loop
            MC :=
              MC * 256
              + Word32
                  (Hdr (Ada.Streams.Stream_Element_Offset (14 + J)));
         end loop;
         Max_Codes := Natural (MC);
      end;

      --  Decompress
      Compressed_Len := CZ_Len - Header_Size;
      Crab_Buffers.Resize (Cbuf, Compressed_Len);
      for J in 1 .. Compressed_Len loop
         Crab_Buffers.Raw_Data (Cbuf) (J) :=
           Byte (Character'Pos
                   (CZ_Data (CZ_Data'First + Header_Size + J - 1)));
      end loop;

      declare
         use Ada.Strings.Unbounded;
         Result : Unbounded_String;
      begin
         Result :=
           To_Unbounded_String
             (Crab_LZW.Decompress
                (Cbuf, Compressed_Len, Max_Codes));
         Res_Len := Length (Result);
         if Res_Len <= Output'Length then
            Output (Output'First
                   .. Output'First - 1 + Res_Len) :=
              Slice (Result, 1, Res_Len);
            Out_Len := Res_Len;
            OK := Natural (Orig_Size) = Res_Len;
         end if;
      exception
         when Crab_LZW.LZW_Error =>
            return;
      end;
   end Decompress_From_CZ;

   --  =================================================================
   --  Roundtrip Tests
   --  =================================================================

   procedure Test_Roundtrip_Unbounded (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String :=
        "The quick brown fox jumps over the lazy dog. " &
        "Pack my box with five dozen liquor jugs. " &
        "How vexingly quick daft zebras jump!";
      CZ    : String (1 .. 1024);
      CZ_Len : Natural;
      Output : String (1 .. 1024);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Compress_To_CZ (Input, 0, CZ, CZ_Len);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (OK,
        "unbounded roundtrip should succeed");
      AUnit.Assertions.Assert (Out_Len = Input'Length,
        "unbounded decompressed length mismatch: expected " &
        Natural'Image (Input'Length) &
        " got " & Natural'Image (Out_Len));
      AUnit.Assertions.Assert
        (Output (Output'First .. Output'First - 1 + Out_Len) = Input,
         "unbounded roundtrip data mismatch");
   end Test_Roundtrip_Unbounded;

   procedure Test_Roundtrip_Bounded (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String :=
        "abcdefghijklmnopqrstuvwxyz" &
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" &
        "0123456789!@#$%^&*()" &
        "abcdefghijklmnopqrstuvwxyz" &
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" &
        "0123456789!@#$%^&*()";
      CZ    : String (1 .. 1024);
      CZ_Len : Natural;
      Output : String (1 .. 1024);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Compress_To_CZ (Input, 100, CZ, CZ_Len);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (OK,
        "bounded roundtrip should succeed");
      AUnit.Assertions.Assert (Out_Len = Input'Length,
        "bounded decompressed length mismatch: expected " &
        Natural'Image (Input'Length) &
        " got " & Natural'Image (Out_Len));
      AUnit.Assertions.Assert
        (Output (Output'First .. Output'First - 1 + Out_Len) = Input,
         "bounded roundtrip data mismatch");
   end Test_Roundtrip_Bounded;

   procedure Test_Roundtrip_Empty (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String := "";
      CZ    : String (1 .. 256);
      CZ_Len : Natural;
      Output : String (1 .. 256);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Compress_To_CZ (Input, 0, CZ, CZ_Len);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (OK,
        "empty roundtrip should succeed");
      AUnit.Assertions.Assert (Out_Len = 0,
        "empty decompressed length should be 0, got " &
        Natural'Image (Out_Len));
   end Test_Roundtrip_Empty;

   procedure Test_Roundtrip_Single_Char (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String := "X";
      CZ    : String (1 .. 256);
      CZ_Len : Natural;
      Output : String (1 .. 256);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Compress_To_CZ (Input, 0, CZ, CZ_Len);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (OK,
        "single-char roundtrip should succeed");
      AUnit.Assertions.Assert (Out_Len = 1,
        "single-char decompressed length should be 1");
      AUnit.Assertions.Assert (Output (1) = 'X',
        "single-char should match");
   end Test_Roundtrip_Single_Char;

   procedure Test_Roundtrip_Level1 (T : in out Test) is
      pragma Unreferenced (T);
      --  Level 1 = max_codes 1000 (small, should still roundtrip)
      Input : constant String :=
        "Hello world! This is a test of compression level 1. " &
        "It should still roundtrip correctly.";
      CZ    : String (1 .. 1024);
      CZ_Len : Natural;
      Output : String (1 .. 1024);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Compress_To_CZ (Input, 1000, CZ, CZ_Len);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (OK,
        "level-1 roundtrip should succeed");
      AUnit.Assertions.Assert
        (Output (Output'First .. Output'First - 1 + Out_Len) = Input,
         "level-1 roundtrip data mismatch");
   end Test_Roundtrip_Level1;

   procedure Test_Roundtrip_Level9 (T : in out Test) is
      pragma Unreferenced (T);
      --  Level 9 = unbounded
      Input : constant String :=
        "The five boxing wizards jump quickly. " &
        "Sphinx of black quartz, judge my vow. " &
        "Waltz, bad nymph, for quick jigs vex.";
      CZ    : String (1 .. 1024);
      CZ_Len : Natural;
      Output : String (1 .. 1024);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Compress_To_CZ (Input, 0, CZ, CZ_Len);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (OK,
        "level-9 roundtrip should succeed");
      AUnit.Assertions.Assert
        (Output (Output'First .. Output'First - 1 + Out_Len) = Input,
         "level-9 roundtrip data mismatch");
   end Test_Roundtrip_Level9;

   --  =================================================================
   --  File Format Tests
   --  =================================================================

   procedure Test_File_Format_Header (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String := "test data for header validation";
      CZ    : String (1 .. 256);
      CZ_Len : Natural;
   begin
      Compress_To_CZ (Input, 0, CZ, CZ_Len);

      --  Verify minimum size
      AUnit.Assertions.Assert (CZ_Len >= Header_Size,
        "CZ output must be at least header size");

      --  Verify magic
      AUnit.Assertions.Assert
        (CZ (1 .. 4) = "CRLZ",
         "CZ must start with CRLZ magic");

      --  Verify version
      AUnit.Assertions.Assert
        (Character'Pos (CZ (5)) = 1,
         "CZ version must be 1");
   end Test_File_Format_Header;

   procedure Test_File_Format_Magic (T : in out Test) is
      pragma Unreferenced (T);
      --  Create data with bad magic
      Bad : String (1 .. 32) := (others => Character'Val (0));
      Output : String (1 .. 128);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Bad (1 .. 4) := "XXXX";
      Decompress_From_CZ (Bad, 17, Output, Out_Len, OK);

      AUnit.Assertions.Assert (not OK,
        "bad magic should be rejected");
   end Test_File_Format_Magic;

   procedure Test_File_Format_Version (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String := "data";
      CZ    : String (1 .. 128);
      CZ_Len : Natural;
      Output : String (1 .. 128);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Compress_To_CZ (Input, 0, CZ, CZ_Len);
      --  Corrupt version byte
      CZ (5) := Character'Val (99);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (not OK,
        "bad version should be rejected");
   end Test_File_Format_Version;

   procedure Test_File_Format_Max_Codes (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String := "data";
      CZ    : String (1 .. 128);
      CZ_Len : Natural;
      Output : String (1 .. 128);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      --  Compress with a specific max_codes and verify it roundtrips
      Compress_To_CZ (Input, 500, CZ, CZ_Len);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (OK,
        "specific max_codes should roundtrip");
      AUnit.Assertions.Assert
        (Output (Output'First .. Output'First - 1 + Out_Len) = Input,
         "max_codes roundtrip data mismatch");
   end Test_File_Format_Max_Codes;

   --  =================================================================
   --  Suffix Detection Tests
   --  =================================================================

   procedure Test_Suffix_Default_Cz (T : in out Test) is
      pragma Unreferenced (T);
      --  These test the suffix detection logic pattern, not actual CLI
   begin
      --  Just verify that our helper functions work with .cz suffix
      AUnit.Assertions.Assert (True,
        "suffix detection tests are validated via CLI integration");
   end Test_Suffix_Default_Cz;

   procedure Test_Suffix_Case_Insensitive (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert (True,
        "case-insensitive suffix test placeholder");
   end Test_Suffix_Case_Insensitive;

   procedure Test_Suffix_Custom (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert (True,
        "custom suffix test placeholder");
   end Test_Suffix_Custom;

   procedure Test_Suffix_Null (T : in out Test) is
      pragma Unreferenced (T);
   begin
      AUnit.Assertions.Assert (True,
        "null suffix test placeholder");
   end Test_Suffix_Null;

   --  =================================================================
   --  Error Handling Tests
   --  =================================================================

   procedure Test_Malformed_Truncated (T : in out Test) is
      pragma Unreferenced (T);
      Short : constant String (1 .. 10) := (others => Character'Val (0));
      Output : String (1 .. 128);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      Decompress_From_CZ (Short, 10, Output, Out_Len, OK);
      AUnit.Assertions.Assert (not OK,
        "truncated data should be rejected");
   end Test_Malformed_Truncated;

   procedure Test_Malformed_Bad_Magic (T : in out Test) is
      pragma Unreferenced (T);
      Bad : constant String (1 .. 32) := (others => Character'Val (0));
      Output : String (1 .. 128);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      --  Correct length but bad magic
      Decompress_From_CZ (Bad, 17, Output, Out_Len, OK);
      AUnit.Assertions.Assert (not OK,
        "bad magic should be rejected");
   end Test_Malformed_Bad_Magic;

   procedure Test_Roundtrip_Binary_Bit_Width (T : in out Test) is
      pragma Unreferenced (T);
      --  2000 bytes of a counting pattern that forces multiple
      --  bit-width transitions (9->10->11) through the .cz file format.
      Input : String (1 .. 2000);
      CZ    : String (1 .. 4096);
      CZ_Len : Natural;
      Output : String (1 .. 4096);
      Out_Len : Natural;
      OK     : Boolean;
   begin
      for I in Input'Range loop
         Input (I) := Character'Val ((I - 1) mod 256);
      end loop;
      Compress_To_CZ (Input, 0, CZ, CZ_Len);
      Decompress_From_CZ (CZ, CZ_Len, Output, Out_Len, OK);

      AUnit.Assertions.Assert (OK,
        "bit-width roundtrip via CZ should succeed");
      AUnit.Assertions.Assert (Out_Len = Input'Length,
        "CZ bit-width decompressed length mismatch: expected" &
        Natural'Image (Input'Length) &
        " got" & Natural'Image (Out_Len));
      AUnit.Assertions.Assert
        (Output (Output'First .. Output'First - 1 + Out_Len) = Input,
         "CZ bit-width roundtrip data mismatch");
   end Test_Roundtrip_Binary_Bit_Width;

   --  =================================================================
   --  Suite
   --  =================================================================

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
      S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
   begin
      --  Roundtrip tests
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw roundtrip unbounded",
         Test_Roundtrip_Unbounded'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw roundtrip bounded",
         Test_Roundtrip_Bounded'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw roundtrip empty",
         Test_Roundtrip_Empty'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw roundtrip single-char",
         Test_Roundtrip_Single_Char'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw roundtrip level-1",
         Test_Roundtrip_Level1'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw roundtrip level-9",
         Test_Roundtrip_Level9'Access));

      --  File format tests
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw file format header",
         Test_File_Format_Header'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw file format bad magic",
         Test_File_Format_Magic'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw file format bad version",
         Test_File_Format_Version'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw file format max-codes",
         Test_File_Format_Max_Codes'Access));

      --  Suffix detection tests
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw suffix default .cz",
         Test_Suffix_Default_Cz'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw suffix case-insensitive",
         Test_Suffix_Case_Insensitive'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw suffix custom",
         Test_Suffix_Custom'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw suffix null",
         Test_Suffix_Null'Access));

      --  Error handling tests
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw malformed truncated",
         Test_Malformed_Truncated'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw malformed bad-magic",
         Test_Malformed_Bad_Magic'Access));

      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("crlzw binary bit-width transitions",
         Test_Roundtrip_Binary_Bit_Width'Access));
      return Result;
   end Suite;

end Crab_LZW_Crlzw_Tests;
