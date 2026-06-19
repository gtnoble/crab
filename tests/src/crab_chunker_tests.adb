with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_Chunker;

package body Crab_Chunker_Tests is

   procedure Test_Single_Chunk (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "abcdefghij";
      C   : Crab_Chunker.State := Crab_Chunker.Start (Buf, 10, 0);
   begin
      AUnit.Assertions.Assert (Crab_Chunker.Has_Next (C),
         "should have a chunk");
      declare
         Chunk : constant String := Crab_Chunker.Next (C);
      begin
         AUnit.Assertions.Assert (Chunk = Buf,
            "chunk should equal whole buffer");
         AUnit.Assertions.Assert (not Crab_Chunker.Has_Next (C),
            "should have no more chunks");
      end;
   end Test_Single_Chunk;

   procedure Test_Multiple_Chunks (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "abcdefghijklmnop";
      C   : Crab_Chunker.State := Crab_Chunker.Start (Buf, 5, 0);
      Count : Natural := 0;
   begin
      while Crab_Chunker.Has_Next (C) loop
         declare
            Chunk : constant String := Crab_Chunker.Next (C);
         begin
            Count := Count + 1;
            AUnit.Assertions.Assert (Chunk'Length > 0,
               "chunk should not be empty");
         end;
      end loop;
      AUnit.Assertions.Assert (Count = 4,
         "should have 4 chunks of size 5 from 16 bytes");
   end Test_Multiple_Chunks;

   procedure Test_Last_Chunk_Shorter (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "abcdefghij";
      C   : Crab_Chunker.State := Crab_Chunker.Start (Buf, 6, 0);
      First : constant String := Crab_Chunker.Next (C);
      Last  : constant String := Crab_Chunker.Next (C);
   begin
      AUnit.Assertions.Assert (First'Length = 6,
         "first chunk should be full size");
      AUnit.Assertions.Assert (Last'Length = 4,
         "last chunk should be shorter");
   end Test_Last_Chunk_Shorter;

   procedure Test_Zero_Overlap (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "abcdefghijklmnop";
      C   : constant Crab_Chunker.State :=
        Crab_Chunker.Start (Buf, 5, 0);
      C2  : Crab_Chunker.State := C;
      Count : Natural := 0;
      C1, C3, C4 : String (1 .. 5);
   begin
      C1 := Crab_Chunker.Next (C2);
      Count := Count + 1;
      while Crab_Chunker.Has_Next (C2) loop
         declare
            Ch : constant String := Crab_Chunker.Next (C2);
         begin
            Count := Count + 1;
            if Count = 3 then
               C3 := Ch;
            elsif Count = 4 then
               C4 (1 .. Ch'Length) := Ch;
            end if;
         end;
      end loop;
      AUnit.Assertions.Assert (Count = 4, "should have 4 chunks");
      AUnit.Assertions.Assert (C1 = "abcde", "chunk 1 wrong");
      AUnit.Assertions.Assert (C3 = "klmno", "chunk 3 wrong");
   end Test_Zero_Overlap;
   procedure Test_Fifty_Pct_Overlap (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "abcdefghij";
      C   : Crab_Chunker.State := Crab_Chunker.Start (Buf, 6, 50);
      Ch1 : constant String := Crab_Chunker.Next (C);
      Ch2 : constant String := Crab_Chunker.Next (C);
      Ch3 : constant String := Crab_Chunker.Next (C);
   begin
      AUnit.Assertions.Assert (Ch1 = "abcdef", "chunk 1 wrong");
      AUnit.Assertions.Assert (Ch2 = "defghi", "chunk 2 wrong");
      AUnit.Assertions.Assert (Ch3 = "ghij",   "chunk 3 wrong (short)");
   end Test_Fifty_Pct_Overlap;

   procedure Test_Empty_Buffer (T : in out Test) is
      pragma Unreferenced (T);
      C : Crab_Chunker.State := Crab_Chunker.Start ("", 5, 0);
   begin
      AUnit.Assertions.Assert (not Crab_Chunker.Has_Next (C),
         "empty buffer should have no chunks");
   end Test_Empty_Buffer;

   procedure Test_Buffer_Shorter_Than_Chunk (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "abc";
      C   : Crab_Chunker.State := Crab_Chunker.Start (Buf, 10, 0);
   begin
      AUnit.Assertions.Assert (Crab_Chunker.Has_Next (C),
         "should have one chunk");
      declare
         Chunk : constant String := Crab_Chunker.Next (C);
      begin
         AUnit.Assertions.Assert (Chunk = "abc",
            "chunk should be entire buffer");
         AUnit.Assertions.Assert (not Crab_Chunker.Has_Next (C),
            "should have no more chunks");
      end;
   end Test_Buffer_Shorter_Than_Chunk;

   --  =================================================================
   --  Line-mode tests
   --  =================================================================

   procedure Test_Lines_Single_Chunk (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "line one" & ASCII.LF
                             & "line two" & ASCII.LF
                             & "line three";
      C   : Crab_Chunker.Line_State :=
        Crab_Chunker.Start_Lines (Buf, 3, 0);
   begin
      AUnit.Assertions.Assert (Crab_Chunker.Has_Next (C),
         "should have a chunk");
      declare
         Chunk : constant String := Crab_Chunker.Next (C);
      begin
         AUnit.Assertions.Assert (Chunk = Buf,
            "chunk should equal whole 3-line buffer");
         AUnit.Assertions.Assert (not Crab_Chunker.Has_Next (C),
            "should have no more chunks");
      end;
   end Test_Lines_Single_Chunk;

   procedure Test_Lines_Multiple_Chunks (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "a" & ASCII.LF
                             & "b" & ASCII.LF
                             & "c" & ASCII.LF
                             & "d" & ASCII.LF
                             & "e" & ASCII.LF
                             & "f";
      C   : Crab_Chunker.Line_State :=
        Crab_Chunker.Start_Lines (Buf, 2, 0);
      Count : Natural := 0;
   begin
      while Crab_Chunker.Has_Next (C) loop
         declare
            Chunk : constant String := Crab_Chunker.Next (C);
         begin
            Count := Count + 1;
            AUnit.Assertions.Assert (Chunk'Length > 0,
               "chunk should not be empty");
         end;
      end loop;
      AUnit.Assertions.Assert (Count = 3,
         "6 lines, 2 per chunk => 3 chunks");
   end Test_Lines_Multiple_Chunks;

   procedure Test_Lines_Last_Shorter (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "line a" & ASCII.LF
                             & "line b" & ASCII.LF
                             & "line c" & ASCII.LF
                             & "line d" & ASCII.LF
                             & "line e";
      C   : Crab_Chunker.Line_State :=
        Crab_Chunker.Start_Lines (Buf, 3, 0);
      Ch1 : constant String := Crab_Chunker.Next (C);
      Ch2 : constant String := Crab_Chunker.Next (C);
   begin
      AUnit.Assertions.Assert (Ch1'Length > 0,
         "first chunk should not be empty");
      AUnit.Assertions.Assert (Ch2'Length > 0,
         "second chunk (last, shorter) should not be empty");
      --  Ch1 has 3 lines, Ch2 has 2 lines — Ch1 should be longer
      AUnit.Assertions.Assert (Ch1'Length > Ch2'Length,
         "first chunk should be longer than last");
   end Test_Lines_Last_Shorter;

   procedure Test_Lines_Overlap (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "1" & ASCII.LF
                             & "2" & ASCII.LF
                             & "3" & ASCII.LF
                             & "4" & ASCII.LF
                             & "5";
      C   : Crab_Chunker.Line_State :=
        Crab_Chunker.Start_Lines (Buf, 3, 50);
      Ch1 : constant String := Crab_Chunker.Next (C);
      Ch2 : constant String := Crab_Chunker.Next (C);
   begin
      --  50% overlap of 3 lines => step = max(1, 3*50/100) = 1
      --  Chunk 1: lines 1-3 => "1\n2\n3"
      --  Chunk 2: lines 2-4 => "2\n3\n4"
      AUnit.Assertions.Assert (Ch1 = "1" & ASCII.LF
                                   & "2" & ASCII.LF
                                   & "3" & ASCII.LF,
         "chunk 1 should be lines 1-3");
      AUnit.Assertions.Assert (Ch2 = "2" & ASCII.LF
                                   & "3" & ASCII.LF
                                   & "4" & ASCII.LF,
         "chunk 2 should be lines 2-4");
   end Test_Lines_Overlap;

   procedure Test_Lines_Empty_Buffer (T : in out Test) is
      pragma Unreferenced (T);
      C : Crab_Chunker.Line_State :=
        Crab_Chunker.Start_Lines ("", 5, 0);
   begin
      AUnit.Assertions.Assert (Crab_Chunker.Has_Next (C),
         "empty buffer still has one (empty) line");
      declare
         Chunk : constant String := Crab_Chunker.Next (C);
      begin
         AUnit.Assertions.Assert (Chunk'Length = 0,
            "chunk from empty buffer should be empty string");
      end;
   end Test_Lines_Empty_Buffer;

   procedure Test_Lines_Single_Line (T : in out Test) is
      pragma Unreferenced (T);
      Buf : constant String := "only one line";
      C   : Crab_Chunker.Line_State :=
        Crab_Chunker.Start_Lines (Buf, 3, 0);
   begin
      AUnit.Assertions.Assert (Crab_Chunker.Has_Next (C),
         "should have one chunk");
      declare
         Chunk : constant String := Crab_Chunker.Next (C);
      begin
         AUnit.Assertions.Assert (Chunk = Buf,
            "chunk should be the entire buffer");
         AUnit.Assertions.Assert (not Crab_Chunker.Has_Next (C),
            "should have no more chunks");
      end;
   end Test_Lines_Single_Line;

   procedure Test_Lines_Trailing_Bytes (T : in out Test) is
      pragma Unreferenced (T);
      --  Final line is not newline-terminated
      Buf : constant String := "line1" & ASCII.LF
                             & "line2_no_newline";
      C   : Crab_Chunker.Line_State :=
        Crab_Chunker.Start_Lines (Buf, 1, 0);
      Ch1 : constant String := Crab_Chunker.Next (C);
      Ch2 : constant String := Crab_Chunker.Next (C);
   begin
      AUnit.Assertions.Assert (Ch1 = "line1" & ASCII.LF,
         "chunk 1 should be first line without LF");
      AUnit.Assertions.Assert (Ch2 = "line2_no_newline",
         "chunk 2 should be trailing bytes");
   end Test_Lines_Trailing_Bytes;



   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      package Caller is new AUnit.Test_Caller (Test);
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
      S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
   begin
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Single chunk", Test_Single_Chunk'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Multiple chunks", Test_Multiple_Chunks'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Last chunk shorter",
         Test_Last_Chunk_Shorter'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Zero overlap", Test_Zero_Overlap'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("50% overlap", Test_Fifty_Pct_Overlap'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Empty buffer", Test_Empty_Buffer'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Buffer shorter than chunk",
         Test_Buffer_Shorter_Than_Chunk'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Lines single chunk",
         Test_Lines_Single_Chunk'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Lines multiple chunks",
         Test_Lines_Multiple_Chunks'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Lines last shorter",
         Test_Lines_Last_Shorter'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Lines overlap",
         Test_Lines_Overlap'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Lines empty buffer",
         Test_Lines_Empty_Buffer'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Lines single line",
         Test_Lines_Single_Line'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Lines trailing bytes",
         Test_Lines_Trailing_Bytes'Access));
      return Result;
   end Suite;

end Crab_Chunker_Tests;
