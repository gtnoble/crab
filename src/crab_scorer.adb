with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Crab_Zlib;
with Crab_LZ4;
with Crab_LZW;
with Crab_LZMA;

package body Crab_Scorer is

   package UBS renames Ada.Strings.Unbounded;

   --  Backend-specific stream access types (body-only)
   type Zlib_Stream_Access  is access all Crab_Zlib.ZStream;
   type LZ4_Stream_Access   is access all Crab_LZ4.LZ4_Stream;
   type LZMA_Ctx_Access     is access all Crab_LZMA.LZMA_Ctx;

   --  Conversions between Stream_Handle and backend access types
   function To_Zlib is new Ada.Unchecked_Conversion
     (Stream_Handle, Zlib_Stream_Access);
   function To_LZ4 is new Ada.Unchecked_Conversion
     (Stream_Handle, LZ4_Stream_Access);
   function To_LZW is new Ada.Unchecked_Conversion
     (Stream_Handle, Crab_LZW.LZW_Stream_Access);
   function To_LZMA is new Ada.Unchecked_Conversion
     (Stream_Handle, LZMA_Ctx_Access);

   function From_Zlib is new Ada.Unchecked_Conversion
     (Zlib_Stream_Access, Stream_Handle);
   function From_LZ4 is new Ada.Unchecked_Conversion
     (LZ4_Stream_Access, Stream_Handle);
   function From_LZW is new Ada.Unchecked_Conversion
     (Crab_LZW.LZW_Stream_Access, Stream_Handle);
   function From_LZMA is new Ada.Unchecked_Conversion
     (LZMA_Ctx_Access, Stream_Handle);

   procedure Free_Byte_Buffer is
     new Ada.Unchecked_Deallocation
       (Crab_Buffers.Byte_Buffer, Byte_Buffer_Access);

   procedure Free_Zlib_Stream is
     new Ada.Unchecked_Deallocation
       (Crab_Zlib.ZStream, Zlib_Stream_Access);

   procedure Free_LZ4_Stream is
     new Ada.Unchecked_Deallocation
       (Crab_LZ4.LZ4_Stream, LZ4_Stream_Access);

   procedure Free_LZMA_Ctx is
     new Ada.Unchecked_Deallocation
       (Crab_LZMA.LZMA_Ctx, LZMA_Ctx_Access);

   Null_Handle : constant Stream_Handle :=
     Stream_Handle (System.Null_Address);

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
      S.Chunk_Buf  := new Crab_Buffers.Byte_Buffer
        (1 .. Crab_Compression.Compress_Bound (Algo, Chunk_Size));
      S.Query_Str  := UBS.To_Unbounded_String (Query);
      S.Query_Bare_CS := 0;
      S.Dict_Stream := Null_Handle;
      S.Bare_Stream := Null_Handle;

      case Algo is
         when Crab_Compression.Deflate =>
            declare
               Dict_Z : Zlib_Stream_Access :=
                 new Crab_Zlib.ZStream'
                   (Crab_Zlib.Init_Stream (Level));
               Bare_Z : Zlib_Stream_Access :=
                 new Crab_Zlib.ZStream'
                   (Crab_Zlib.Init_Stream (Level));
            begin
               Crab_Zlib.Set_Dict (Dict_Z.all, Query);
               Crab_Zlib.Set_Dict (Bare_Z.all, "");
               S.Dict_Stream := From_Zlib (Dict_Z);
               S.Bare_Stream := From_Zlib (Bare_Z);
            end;
         when Crab_Compression.LZ4 =>
            declare
               Dict_L : LZ4_Stream_Access :=
                 new Crab_LZ4.LZ4_Stream'
                   (Crab_LZ4.Init_Stream);
               Bare_L : LZ4_Stream_Access :=
                 new Crab_LZ4.LZ4_Stream'
                   (Crab_LZ4.Init_Stream);
            begin
               Crab_LZ4.Load_Dict (Dict_L.all, Query);
               Crab_LZ4.Load_Dict (Bare_L.all, "");
               S.Dict_Stream := From_LZ4 (Dict_L);
               S.Bare_Stream := From_LZ4 (Bare_L);
            end;
         when Crab_Compression.LZW =>
            declare
               Dict_LZW : Crab_LZW.LZW_Stream_Access :=
                 Crab_LZW.Init_Stream;
               Bare_LZW : Crab_LZW.LZW_Stream_Access :=
                 Crab_LZW.Init_Stream;
            begin
               --  Streams are created empty; dictionaries are loaded
               --  per-call in Score to avoid simultaneous memory usage.
               S.Dict_Stream := From_LZW (Dict_LZW);
               S.Bare_Stream := From_LZW (Bare_LZW);
            end;
         when Crab_Compression.LZMA =>
            declare
               Dict_LZMA : LZMA_Ctx_Access :=
                 new Crab_LZMA.LZMA_Ctx'
                   (Crab_LZMA.Init_Stream (Level, Dict_Size, ""));
               Bare_LZMA : LZMA_Ctx_Access :=
                 new Crab_LZMA.LZMA_Ctx'
                   (Crab_LZMA.Init_Stream (Level, Dict_Size, ""));
            begin
               --  Streams are created empty; dictionaries are loaded
               --  per-call in Score to avoid simultaneous memory usage.
               S.Dict_Stream := From_LZMA (Dict_LZMA);
               S.Bare_Stream := From_LZMA (Bare_LZMA);
            end;
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
               Old : Byte_Buffer_Access := S.Chunk_Buf;
            begin
               S.Chunk_Buf := new Crab_Buffers.Byte_Buffer
                 (1 .. Positive'Max (Needed, S.Chunk_Buf'Length * 2));
               Free_Byte_Buffer (Old);
            end;
         end if;
      end;

      case S.Algo is
         when Crab_Compression.Deflate =>
            declare
               Bare_Z : Zlib_Stream_Access := To_Zlib (S.Bare_Stream);
               Dict_Z : Zlib_Stream_Access := To_Zlib (S.Dict_Stream);
            begin
               Crab_Zlib.Compress_Stream
                 (Bare_Z.all, Chunk, S.Chunk_Buf.all, Bare_CS);
               Crab_Zlib.Compress_Stream
                 (Dict_Z.all, Chunk, S.Chunk_Buf.all, Dict_CS);
               Query_Dict_CS := Crab_Zlib.Compress_Bare
                 (UBS.To_String (S.Query_Str), S.Level, Chunk);
            end;
         when Crab_Compression.LZ4 =>
            declare
               Bare_L : LZ4_Stream_Access := To_LZ4 (S.Bare_Stream);
               Dict_L : LZ4_Stream_Access := To_LZ4 (S.Dict_Stream);
            begin
               --  LZ4_resetStream_fast discards the dictionary, so
               --  we must reload it before each compression.
               Crab_LZ4.Load_Dict (Bare_L.all, "");
               Crab_LZ4.Compress_Stream
                 (Bare_L.all, Chunk, S.Chunk_Buf.all,
                  S.Level, Bare_CS);
               Crab_LZ4.Load_Dict (Dict_L.all,
                 UBS.To_String (S.Query_Str));
               Crab_LZ4.Compress_Stream
                 (Dict_L.all, Chunk, S.Chunk_Buf.all,
                  S.Level, Dict_CS);
               Query_Dict_CS := Crab_LZ4.Compress_Bare
                 (UBS.To_String (S.Query_Str), S.Level, Chunk);
            end;
         when Crab_Compression.LZW =>
            declare
               Old_Bare : Crab_LZW.LZW_Stream_Access :=
                 To_LZW (S.Bare_Stream);
               Old_Dict : Crab_LZW.LZW_Stream_Access :=
                 To_LZW (S.Dict_Stream);
               Stream   : Crab_LZW.LZW_Stream_Access;
            begin
               --  Free old streams from previous call (or from Init)
               Crab_LZW.Free_Stream (Old_Bare);
               Crab_LZW.Free_Stream (Old_Dict);

               --  Pass 1: compress Chunk with empty dictionary
               Stream := Crab_LZW.Init_Stream;
               Crab_LZW.Load_Dict (Stream.all, "");
               Crab_LZW.Compress_Stream
                 (Stream.all, Chunk, S.Chunk_Buf.all,
                  S.Level, Bare_CS);
               Crab_LZW.Free_Stream (Stream);

               --  Pass 2: compress Chunk with Query as dictionary
               Stream := Crab_LZW.Init_Stream;
               Crab_LZW.Load_Dict
                 (Stream.all, UBS.To_String (S.Query_Str));
               Crab_LZW.Compress_Stream
                 (Stream.all, Chunk, S.Chunk_Buf.all,
                  S.Level, Dict_CS);
               Crab_LZW.Free_Stream (Stream);

               --  Pass 3: compress Query with Chunk as dictionary
               --  (Compress_Bare creates and frees its own stream)
               Query_Dict_CS := Crab_LZW.Compress_Bare
                 (UBS.To_String (S.Query_Str), Chunk);

               --  Store fresh empty streams for next call
               S.Bare_Stream := From_LZW (Crab_LZW.Init_Stream);
               S.Dict_Stream := From_LZW (Crab_LZW.Init_Stream);
            end;
         when Crab_Compression.LZMA =>
            declare
               Old_Bare : LZMA_Ctx_Access := To_LZMA (S.Bare_Stream);
               Old_Dict : LZMA_Ctx_Access := To_LZMA (S.Dict_Stream);
               Stream   : LZMA_Ctx_Access;
            begin
               --  Free old streams from previous call (or from Init)
               Crab_LZMA.Free_Stream (Old_Bare.all);
               Crab_LZMA.Free_Stream (Old_Dict.all);
               Free_LZMA_Ctx (Old_Bare);
               Free_LZMA_Ctx (Old_Dict);

               --  Pass 1: compress Chunk with empty dictionary
               Stream := new Crab_LZMA.LZMA_Ctx'
                 (Crab_LZMA.Init_Stream (S.Level, S.Dict_Size, ""));
               Crab_LZMA.Compress_Stream
                 (Stream.all, Chunk, S.Chunk_Buf.all, Bare_CS);
               Crab_LZMA.Free_Stream (Stream.all);
               Free_LZMA_Ctx (Stream);

               --  Pass 2: compress Chunk with Query as dictionary
               Stream := new Crab_LZMA.LZMA_Ctx'
                 (Crab_LZMA.Init_Stream
                    (S.Level, S.Dict_Size, UBS.To_String (S.Query_Str)));
               Crab_LZMA.Compress_Stream
                 (Stream.all, Chunk, S.Chunk_Buf.all, Dict_CS);
               Crab_LZMA.Free_Stream (Stream.all);
               Free_LZMA_Ctx (Stream);

               --  Pass 3: compress Query with Chunk as dictionary
               --  (Compress_Bare creates and frees its own stream)
               Query_Dict_CS := Crab_LZMA.Compress_Bare
                 (UBS.To_String (S.Query_Str), S.Level, S.Dict_Size, Chunk);

               --  Store fresh empty streams for next call
               S.Bare_Stream := From_LZMA
                 (new Crab_LZMA.LZMA_Ctx'
                    (Crab_LZMA.Init_Stream (S.Level, S.Dict_Size, "")));
               S.Dict_Stream := From_LZMA
                 (new Crab_LZMA.LZMA_Ctx'
                    (Crab_LZMA.Init_Stream
                       (S.Level, S.Dict_Size, UBS.To_String (S.Query_Str))));
            end;
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
   begin
      case S.Algo is
         when Crab_Compression.Deflate =>
            if S.Dict_Stream /= Null_Handle then
               declare
                  Ptr : Zlib_Stream_Access := To_Zlib (S.Dict_Stream);
               begin
                  Crab_Zlib.Free_Stream (Ptr.all);
                  Free_Zlib_Stream (Ptr);
               end;
            end if;
            if S.Bare_Stream /= Null_Handle then
               declare
                  Ptr : Zlib_Stream_Access := To_Zlib (S.Bare_Stream);
               begin
                  Crab_Zlib.Free_Stream (Ptr.all);
                  Free_Zlib_Stream (Ptr);
               end;
            end if;
         when Crab_Compression.LZ4 =>
            if S.Dict_Stream /= Null_Handle then
               declare
                  Ptr : LZ4_Stream_Access := To_LZ4 (S.Dict_Stream);
               begin
                  Crab_LZ4.Free_Stream (Ptr.all);
                  Free_LZ4_Stream (Ptr);
               end;
            end if;
            if S.Bare_Stream /= Null_Handle then
               declare
                  Ptr : LZ4_Stream_Access := To_LZ4 (S.Bare_Stream);
               begin
                  Crab_LZ4.Free_Stream (Ptr.all);
                  Free_LZ4_Stream (Ptr);
               end;
            end if;
         when Crab_Compression.LZW =>
            if S.Dict_Stream /= Null_Handle then
               declare
                  Ptr : Crab_LZW.LZW_Stream_Access :=
                    To_LZW (S.Dict_Stream);
               begin
                  Crab_LZW.Free_Stream (Ptr);
               end;
            end if;
            if S.Bare_Stream /= Null_Handle then
               declare
                  Ptr : Crab_LZW.LZW_Stream_Access :=
                    To_LZW (S.Bare_Stream);
               begin
                  Crab_LZW.Free_Stream (Ptr);
               end;
            end if;
         when Crab_Compression.LZMA =>
            if S.Dict_Stream /= Null_Handle then
               declare
                  Ptr : LZMA_Ctx_Access := To_LZMA (S.Dict_Stream);
               begin
                  Crab_LZMA.Free_Stream (Ptr.all);
                  Free_LZMA_Ctx (Ptr);
               end;
            end if;
            if S.Bare_Stream /= Null_Handle then
               declare
                  Ptr : LZMA_Ctx_Access := To_LZMA (S.Bare_Stream);
               begin
                  Crab_LZMA.Free_Stream (Ptr.all);
                  Free_LZMA_Ctx (Ptr);
               end;
            end if;
      end case;

      if S.Chunk_Buf /= null then
         Free_Byte_Buffer (S.Chunk_Buf);
      end if;
   end Finalize;

end Crab_Scorer;
