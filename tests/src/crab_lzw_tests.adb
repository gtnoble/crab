with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Buffers;
with Crab_LZW;

package body Crab_LZW_Tests is

   procedure Test_Roundtrip_Simple (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String := "hello world";
      Buf   : Crab_Buffers.Byte_Buffer;
      Dlen  : Natural;
      S     : Crab_LZW.LZW_Stream;
   begin
      Crab_Buffers.Resize (Buf, 64);
      Crab_LZW.Init_Roots (S);
      Crab_LZW.Load_Dict (S, "");
      Crab_LZW.Compress_Stream (S, Input, Buf, 0, Dlen);

      declare
         Result : constant String :=
           Crab_LZW.Decompress (Buf, Dlen);
      begin
         AUnit.Assertions.Assert (Result = Input,
            "decompressed '" & Result & "' should match input '"
            & Input & "'");
      end;
   end Test_Roundtrip_Simple;

   procedure Test_Roundtrip_Empty (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String := "";
      Buf   : Crab_Buffers.Byte_Buffer;
      Dlen  : Natural;
      S     : Crab_LZW.LZW_Stream;
   begin
      Crab_Buffers.Resize (Buf, 16);
      Crab_LZW.Init_Roots (S);
      Crab_LZW.Load_Dict (S, "");
      Crab_LZW.Compress_Stream (S, Input, Buf, 0, Dlen);

      declare
         Result : constant String :=
           Crab_LZW.Decompress (Buf, Dlen);
      begin
         AUnit.Assertions.Assert (Result = Input,
            "empty string should roundtrip: got length" &
            Natural'Image (Result'Length));
      end;
   end Test_Roundtrip_Empty;

   procedure Test_Roundtrip_Repeated (T : in out Test) is
      pragma Unreferenced (T);
      Input : constant String := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
      Buf   : Crab_Buffers.Byte_Buffer;
      Dlen  : Natural;
      S     : Crab_LZW.LZW_Stream;
   begin
      Crab_Buffers.Resize (Buf, Crab_LZW.Compress_Bound (Input'Length));
      Crab_LZW.Init_Roots (S);
      Crab_LZW.Load_Dict (S, "");
      Crab_LZW.Compress_Stream (S, Input, Buf, 0, Dlen);

      declare
         Result : constant String :=
           Crab_LZW.Decompress (Buf, Dlen);
      begin
         AUnit.Assertions.Assert (Result = Input,
            "repeated string should roundtrip");
         AUnit.Assertions.Assert (Dlen < Input'Length,
            "repeated string should compress");
      end;
   end Test_Roundtrip_Repeated;

   procedure Test_Roundtrip_Long (T : in out Test) is
      pragma Unreferenced (T);
      --  Build a longer, more varied string
      Input : constant String :=
        "The quick brown fox jumps over the lazy dog. " &
        "The quick brown fox jumps over the lazy dog again. " &
        "Pack my box with five dozen liquor jugs.";
      Buf : Crab_Buffers.Byte_Buffer;
      Dlen : Natural;
      S    : Crab_LZW.LZW_Stream;
   begin
      Crab_Buffers.Resize (Buf, Crab_LZW.Compress_Bound (Input'Length));
      Crab_LZW.Init_Roots (S);
      Crab_LZW.Load_Dict (S, "");
      Crab_LZW.Compress_Stream (S, Input, Buf, 0, Dlen);

      declare
         Result : constant String :=
           Crab_LZW.Decompress (Buf, Dlen);
      begin
         AUnit.Assertions.Assert (Result = Input,
            "long string should roundtrip");
      end;
   end Test_Roundtrip_Long;

   procedure Test_Dict_Compression (T : in out Test) is
      pragma Unreferenced (T);
      Dict   : constant String := "hello world";
      Chunk  : constant String := "hello world";
      --  Compress Chunk with matching dict
      Cs_Dict : Natural;
      --  Compress Chunk with empty dict
      Cs_Bare : Natural;
   begin
      Cs_Dict := Crab_LZW.Compress_Bare (Chunk, Dict);
      Cs_Bare := Crab_LZW.Compress_Bare (Chunk, "");

      AUnit.Assertions.Assert (Cs_Dict <= Cs_Bare,
         "dictionary should not increase compressed size:"
         & " dict=" & Natural'Image (Cs_Dict)
         & " bare=" & Natural'Image (Cs_Bare));
   end Test_Dict_Compression;

   procedure Test_Dict_Unrelated (T : in out Test) is
      pragma Unreferenced (T);
      Dict   : constant String := "abcdefghijklmnop";
      Chunk  : constant String := "0000000000000000000000000000";
      Cs_Dict : constant Natural :=
        Crab_LZW.Compress_Bare (Chunk, Dict);
      Cs_Bare : constant Natural :=
        Crab_LZW.Compress_Bare (Chunk, "");
   begin
      --  Both should succeed; just verify no crash
      AUnit.Assertions.Assert (Cs_Dict > 0,
         "unrelated dict compression should produce output");
      AUnit.Assertions.Assert (Cs_Bare > 0,
         "bare compression should produce output");
   end Test_Dict_Unrelated;

   procedure Test_Compress_Bound (T : in out Test) is
      pragma Unreferenced (T);
      Bound : constant Natural := Crab_LZW.Compress_Bound (100);
   begin
      AUnit.Assertions.Assert (Bound >= 100,
         "Compress_Bound should be >= input size:"
         & Natural'Image (Bound));
   end Test_Compress_Bound;

   procedure Test_Compress_Bare (T : in out Test) is
      pragma Unreferenced (T);
      Size : constant Natural :=
        Crab_LZW.Compress_Bare ("test string", "");
   begin
      AUnit.Assertions.Assert (Size > 0,
         "Compress_Bare should return non-zero size");
   end Test_Compress_Bare;

   procedure Test_Bounded_Roundtrip (T : in out Test) is
      pragma Unreferenced (T);
      --  Roundtrip with a small code limit (100 codes).
      --  The input is long enough to force eviction.
      Input : constant String :=
        "abcdefghijklmnopqrstuvwxyz" &
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" &
        "0123456789!@#$%^&*()" &
        "abcdefghijklmnopqrstuvwxyz" &
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" &
        "0123456789!@#$%^&*()";
      Buf   : Crab_Buffers.Byte_Buffer;
      Dlen  : Natural;
      S     : Crab_LZW.LZW_Stream;
   begin
      Crab_Buffers.Resize (Buf, Crab_LZW.Compress_Bound (Input'Length));
      Crab_LZW.Init_Roots (S);
      Crab_LZW.Set_Max_Codes (S, 100);
      Crab_LZW.Load_Dict (S, "");
      Crab_LZW.Compress_Stream (S, Input, Buf, 0, Dlen);

      declare
         Result : constant String :=
           Crab_LZW.Decompress (Buf, Dlen);
      begin
         AUnit.Assertions.Assert (Result = Input,
            "bounded roundtrip should match: expected length" &
            Natural'Image (Input'Length) &
            " got" & Natural'Image (Result'Length));
      end;
   end Test_Bounded_Roundtrip;

   procedure Test_Bounded_Compression (T : in out Test) is
      pragma Unreferenced (T);
      --  Verify that bounded mode still compresses repeated data
      Input : constant String :=
        "hello world hello world hello world hello world " &
        "hello world hello world hello world hello world " &
        "hello world hello world hello world hello world";
      Buf   : Crab_Buffers.Byte_Buffer;
      Dlen  : Natural;
      S     : Crab_LZW.LZW_Stream;
   begin
      Crab_Buffers.Resize (Buf, Crab_LZW.Compress_Bound (Input'Length));
      Crab_LZW.Init_Roots (S);
      Crab_LZW.Set_Max_Codes (S, 50);
      Crab_LZW.Load_Dict (S, "");
      Crab_LZW.Compress_Stream (S, Input, Buf, 0, Dlen);

      AUnit.Assertions.Assert (Dlen > 0,
         "bounded compression should produce output");
      AUnit.Assertions.Assert (Dlen < Input'Length,
         "bounded compression should compress repeated text:"
         & " input=" & Natural'Image (Input'Length)
         & " compressed=" & Natural'Image (Dlen));
   end Test_Bounded_Compression;

   procedure Test_Set_Max_Codes (T : in out Test) is
      pragma Unreferenced (T);
      S : Crab_LZW.LZW_Stream;
   begin
      Crab_LZW.Init_Roots (S);
      --  Default should be 0 (unbounded)
      Crab_LZW.Set_Max_Codes (S, 1000);
      --  Should not raise; just verify it compiles and runs
      AUnit.Assertions.Assert (True,
         "Set_Max_Codes should not raise");
   end Test_Set_Max_Codes;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      package Caller is new AUnit.Test_Caller (Test);
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
      S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
   begin
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW roundtrip simple",
         Test_Roundtrip_Simple'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW roundtrip empty",
         Test_Roundtrip_Empty'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW roundtrip repeated",
         Test_Roundtrip_Repeated'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW roundtrip long",
         Test_Roundtrip_Long'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW dict compression",
         Test_Dict_Compression'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW dict unrelated",
         Test_Dict_Unrelated'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW compress bound",
         Test_Compress_Bound'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW compress bare",
         Test_Compress_Bare'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW bounded roundtrip",
         Test_Bounded_Roundtrip'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW bounded compression",
         Test_Bounded_Compression'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("LZW set max codes",
         Test_Set_Max_Codes'Access));
      return Result;
   end Suite;

end Crab_LZW_Tests;
