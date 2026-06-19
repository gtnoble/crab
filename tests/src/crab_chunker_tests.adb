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
      return Result;
   end Suite;

end Crab_Chunker_Tests;
