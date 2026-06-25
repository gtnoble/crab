with Ada.Unchecked_Deallocation;

package body Crab_Scorer is

   package UBS renames Ada.Strings.Unbounded;

   procedure Free_Byte_Array is
     new Ada.Unchecked_Deallocation
       (Crab_Zlib.Byte_Array, Byte_Array_Access);

   procedure Free_Zlib_Stream is
     new Ada.Unchecked_Deallocation
       (Crab_Zlib.ZStream, Zlib_Stream_Access);

   procedure Free_LZ4_Stream is
     new Ada.Unchecked_Deallocation
       (Crab_LZ4.LZ4_Stream, LZ4_Stream_Access);

   procedure Free_LZMA_Ctx is
     new Ada.Unchecked_Deallocation
       (Crab_LZMA.LZMA_Ctx, LZMA_Ctx_Access);

   --  ==================================================================

   procedure Init
     (S          : out State;
      Query      : String;
      Chunk_Size : Positive;
      Algo       : Crab_Compression.Algorithm;
      Level      : Integer;
      Dict_Size  : Natural := 8_388_608)
   is
   begin
      S.Algo       := Algo;
      S.Level      := Level;
      S.Dict_Size  := Dict_Size;
      S.Chunk_Buf  := new Crab_Zlib.Byte_Array
        (1 .. Crab_Compression.Compress_Bound (Algo, Chunk_Size));
      S.Query_Str  := UBS.To_Unbounded_String (Query);
      S.Query_Bare_CS := 0;
      S.Dict_Z     := null;
      S.Bare_Z     := null;
      S.Dict_L     := null;
      S.Bare_L     := null;
      S.Dict_LZW   := null;
      S.Bare_LZW   := null;
      S.Dict_LZMA  := null;
      S.Bare_LZMA  := null;

      case Algo is
         when Crab_Compression.Deflate =>
            S.Dict_Z := new Crab_Zlib.ZStream'
              (Crab_Zlib.Init_Stream (Level));
            S.Bare_Z := new Crab_Zlib.ZStream'
              (Crab_Zlib.Init_Stream (Level));
            Crab_Zlib.Set_Dict (S.Dict_Z.all, Query);
            Crab_Zlib.Set_Dict (S.Bare_Z.all, "");
         when Crab_Compression.LZ4 =>
            S.Dict_L := new Crab_LZ4.LZ4_Stream'
              (Crab_LZ4.Init_Stream);
            S.Bare_L := new Crab_LZ4.LZ4_Stream'
              (Crab_LZ4.Init_Stream);
            Crab_LZ4.Load_Dict (S.Dict_L.all, Query);
            Crab_LZ4.Load_Dict (S.Bare_L.all, "");
         when Crab_Compression.LZW =>
            S.Dict_LZW := Crab_LZW.Init_Stream;
            S.Bare_LZW := Crab_LZW.Init_Stream;
            Crab_LZW.Load_Dict (S.Dict_LZW.all, Query);
            Crab_LZW.Load_Dict (S.Bare_LZW.all, "");
         when Crab_Compression.LZMA =>
            S.Dict_LZMA := new Crab_LZMA.LZMA_Ctx'
              (Crab_LZMA.Init_Stream (Level, Dict_Size, Query));
            S.Bare_LZMA := new Crab_LZMA.LZMA_Ctx'
              (Crab_LZMA.Init_Stream (Level, Dict_Size, ""));
      end case;

      --  Compute |compress(Q, ∅)| once — constant for all scoring calls
      declare
         Q_CS : Natural;
      begin
         case Algo is
            when Crab_Compression.Deflate =>
               Q_CS := Crab_Zlib.Compress_Bare (Query, Level, "");
            when Crab_Compression.LZ4 =>
               Q_CS := Crab_LZ4.Compress_Bare (Query, Level, "");
            when Crab_Compression.LZW =>
               Q_CS := Crab_LZW.Compress_Bare (Query, "");
            when Crab_Compression.LZMA =>
               Q_CS := Crab_LZMA.Compress_Bare
                 (Query, Level, Dict_Size, "");
         end case;
         S.Query_Bare_CS := Q_CS;
      end;
   exception
      when Crab_Zlib.Zlib_Error |
           Crab_LZ4.LZ4_Error |
           Crab_LZW.LZW_Error |
           Crab_LZMA.LZMA_Error =>
         raise Crab_Compression.Compression_Error;
   end Init;

   --  ==================================================================

   function Score (S : in out State; Chunk : String) return Integer is
      Bare_CS : Natural;
      Dict_CS : Natural;
      Query_Dict_CS : Natural;
   begin
      --  Ensure Chunk_Buf is large enough (handles line-mode sizing)
      declare
         Needed : constant Natural :=
           Crab_Compression.Compress_Bound (S.Algo, Chunk'Length);
      begin
         if Needed > S.Chunk_Buf'Length then
            declare
               Old : Byte_Array_Access := S.Chunk_Buf;
            begin
               S.Chunk_Buf := new Crab_Zlib.Byte_Array
                 (1 .. Positive'Max (Needed, S.Chunk_Buf'Length * 2));
               Free_Byte_Array (Old);
            end;
         end if;
      end;

      case S.Algo is
         when Crab_Compression.Deflate =>
            Crab_Zlib.Compress_Stream
              (S.Bare_Z.all, Chunk, S.Chunk_Buf.all, Bare_CS);
            Crab_Zlib.Compress_Stream
              (S.Dict_Z.all, Chunk, S.Chunk_Buf.all, Dict_CS);
            Query_Dict_CS := Crab_Zlib.Compress_Bare
              (UBS.To_String (S.Query_Str), S.Level, Chunk);
         when Crab_Compression.LZ4 =>
            --  LZ4_resetStream_fast discards the dictionary, so
            --  we must reload it before each compression.
            Crab_LZ4.Load_Dict (S.Bare_L.all, "");
            Crab_LZ4.Compress_Stream
              (S.Bare_L.all, Chunk, S.Chunk_Buf.all,
               S.Level, Bare_CS);
            Crab_LZ4.Load_Dict (S.Dict_L.all,
              UBS.To_String (S.Query_Str));
            Crab_LZ4.Compress_Stream
              (S.Dict_L.all, Chunk, S.Chunk_Buf.all,
               S.Level, Dict_CS);
            Query_Dict_CS := Crab_LZ4.Compress_Bare
              (UBS.To_String (S.Query_Str), S.Level, Chunk);
         when Crab_Compression.LZW =>
            --  LZW streams are consumed by Compress_Stream;
            --  must re-init and re-prime dictionary each call.
            Crab_LZW.Free_Stream (S.Bare_LZW);
            Crab_LZW.Free_Stream (S.Dict_LZW);
            S.Bare_LZW := Crab_LZW.Init_Stream;
            S.Dict_LZW := Crab_LZW.Init_Stream;
            Crab_LZW.Load_Dict (S.Bare_LZW.all, "");
            Crab_LZW.Compress_Stream
              (S.Bare_LZW.all, Chunk, S.Chunk_Buf.all,
               S.Level, Bare_CS);
            Crab_LZW.Load_Dict
              (S.Dict_LZW.all, UBS.To_String (S.Query_Str));
            Crab_LZW.Compress_Stream
              (S.Dict_LZW.all, Chunk, S.Chunk_Buf.all,
               S.Level, Dict_CS);
            Query_Dict_CS := Crab_LZW.Compress_Bare
              (UBS.To_String (S.Query_Str), Chunk);
         when Crab_Compression.LZMA =>
            --  LZMA streams are consumed by Compress_Stream
            --  (LZMA_FINISH); must re-init and re-prime each call.
            declare
               Old_Bare : LZMA_Ctx_Access := S.Bare_LZMA;
               Old_Dict : LZMA_Ctx_Access := S.Dict_LZMA;
            begin
               Crab_LZMA.Free_Stream (Old_Bare.all);
               Crab_LZMA.Free_Stream (Old_Dict.all);
               Free_LZMA_Ctx (Old_Bare);
               Free_LZMA_Ctx (Old_Dict);
            end;
            S.Bare_LZMA := new Crab_LZMA.LZMA_Ctx'
              (Crab_LZMA.Init_Stream (S.Level, S.Dict_Size, ""));
            S.Dict_LZMA := new Crab_LZMA.LZMA_Ctx'
              (Crab_LZMA.Init_Stream
                 (S.Level, S.Dict_Size, UBS.To_String (S.Query_Str)));
            Crab_LZMA.Compress_Stream
              (S.Bare_LZMA.all, Chunk, S.Chunk_Buf.all, Bare_CS);
            Crab_LZMA.Compress_Stream
              (S.Dict_LZMA.all, Chunk, S.Chunk_Buf.all, Dict_CS);
            Query_Dict_CS := Crab_LZMA.Compress_Bare
              (UBS.To_String (S.Query_Str), S.Level, S.Dict_Size, Chunk);
      end case;

      return (Integer (Bare_CS) - Integer (Dict_CS)
              + Integer (S.Query_Bare_CS) - Integer (Query_Dict_CS)) / 2;
   exception
      when Crab_Zlib.Zlib_Error |
           Crab_LZ4.LZ4_Error |
           Crab_LZW.LZW_Error |
           Crab_LZMA.LZMA_Error =>
         raise Crab_Compression.Compression_Error;
   end Score;

   --  ==================================================================

   overriding procedure Finalize (S : in out State) is
      use type Crab_LZW.LZW_Stream_Access;
   begin
      case S.Algo is
         when Crab_Compression.Deflate =>
            if S.Dict_Z /= null then
               Crab_Zlib.Free_Stream (S.Dict_Z.all);
               Free_Zlib_Stream (S.Dict_Z);
            end if;
            if S.Bare_Z /= null then
               Crab_Zlib.Free_Stream (S.Bare_Z.all);
               Free_Zlib_Stream (S.Bare_Z);
            end if;
         when Crab_Compression.LZ4 =>
            if S.Dict_L /= null then
               Crab_LZ4.Free_Stream (S.Dict_L.all);
               Free_LZ4_Stream (S.Dict_L);
            end if;
            if S.Bare_L /= null then
               Crab_LZ4.Free_Stream (S.Bare_L.all);
               Free_LZ4_Stream (S.Bare_L);
            end if;
         when Crab_Compression.LZW =>
            if S.Dict_LZW /= null then
               Crab_LZW.Free_Stream (S.Dict_LZW);
            end if;
            if S.Bare_LZW /= null then
               Crab_LZW.Free_Stream (S.Bare_LZW);
            end if;
         when Crab_Compression.LZMA =>
            if S.Dict_LZMA /= null then
               Crab_LZMA.Free_Stream (S.Dict_LZMA.all);
               Free_LZMA_Ctx (S.Dict_LZMA);
            end if;
            if S.Bare_LZMA /= null then
               Crab_LZMA.Free_Stream (S.Bare_LZMA.all);
               Free_LZMA_Ctx (S.Bare_LZMA);
            end if;
      end case;

      if S.Chunk_Buf /= null then
         Free_Byte_Array (S.Chunk_Buf);
      end if;
   end Finalize;

end Crab_Scorer;
