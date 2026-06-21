package body Crab_Scorer is

   package UBS renames Ada.Strings.Unbounded;

   --  ==================================================================

   function Init
     (Query      : String;
      Chunk_Size : Positive;
      Algo       : Crab_Compression.Algorithm;
      Level      : Integer;
      Dict_Size  : Natural := 8_388_608) return State
   is
      S : State :=
        (Algo       => Algo,
         Level      => Level,
         Dict_Size  => Dict_Size,
         Chunk_Buf  => new Crab_Zlib.Byte_Array
           (1 .. Crab_Compression.Compress_Bound (Algo, Chunk_Size)),
         Query_Str  => UBS.To_Unbounded_String (Query),
         Dict_Z     => null,
         Bare_Z     => null,
         Dict_L     => null,
         Bare_L     => null,
         Dict_LZW   => null,
         Bare_LZW   => null,
         Dict_LZMA  => null,
         Bare_LZMA  => null);
   begin
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
              (Crab_LZMA.Init_Stream (Level, Dict_Size));
            S.Bare_LZMA := new Crab_LZMA.LZMA_Ctx'
              (Crab_LZMA.Init_Stream (Level, Dict_Size));
            Crab_LZMA.Load_Dict (S.Dict_LZMA.all, Query);
            Crab_LZMA.Load_Dict (S.Bare_LZMA.all, "");
      end case;
      return S;
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
   begin
      --  Ensure Chunk_Buf is large enough (handles line-mode sizing)
      declare
         Needed : constant Natural :=
           Crab_Compression.Compress_Bound (S.Algo, Chunk'Length);
      begin
         if Needed > S.Chunk_Buf'Length then
            S.Chunk_Buf := new Crab_Zlib.Byte_Array
              (1 .. Positive'Max (Needed, S.Chunk_Buf'Length * 2));
         end if;
      end;

      case S.Algo is
         when Crab_Compression.Deflate =>
            Crab_Zlib.Compress_Stream
              (S.Bare_Z.all, Chunk, S.Chunk_Buf.all, Bare_CS);
            Crab_Zlib.Compress_Stream
              (S.Dict_Z.all, Chunk, S.Chunk_Buf.all, Dict_CS);
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
         when Crab_Compression.LZMA =>
            --  LZMA streams are consumed by Compress_Stream
            --  (LZMA_FINISH); must re-init and re-prime each call.
            Crab_LZMA.Free_Stream (S.Bare_LZMA.all);
            Crab_LZMA.Free_Stream (S.Dict_LZMA.all);
            S.Bare_LZMA := new Crab_LZMA.LZMA_Ctx'
              (Crab_LZMA.Init_Stream (S.Level, S.Dict_Size));
            S.Dict_LZMA := new Crab_LZMA.LZMA_Ctx'
              (Crab_LZMA.Init_Stream (S.Level, S.Dict_Size));
            Crab_LZMA.Load_Dict (S.Bare_LZMA.all, "");
            Crab_LZMA.Compress_Stream
              (S.Bare_LZMA.all, Chunk, S.Chunk_Buf.all, Bare_CS);
            Crab_LZMA.Load_Dict
              (S.Dict_LZMA.all, UBS.To_String (S.Query_Str));
            Crab_LZMA.Compress_Stream
              (S.Dict_LZMA.all, Chunk, S.Chunk_Buf.all, Dict_CS);
      end case;

      return Integer (Bare_CS) - Integer (Dict_CS);
   exception
      when Crab_Zlib.Zlib_Error |
           Crab_LZ4.LZ4_Error |
           Crab_LZW.LZW_Error |
           Crab_LZMA.LZMA_Error =>
         raise Crab_Compression.Compression_Error;
   end Score;

end Crab_Scorer;
