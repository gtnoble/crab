with Crab_LZMA;
with Ada.Exceptions;
package body Crab_Scorer is

   package UBS renames Ada.Strings.Unbounded;

   --  ==================================================================

   procedure Init
     (S             : in out State;
      Query         : String;
      Chunk_Size    : Positive;
      Level         : Integer;
      Dict_Size     : Natural := 0;
      Dict_Explicit : Boolean := False)
   is
   begin
      S.Level         := Level;
      S.Dict_Size     := Dict_Size;
      S.Dict_Explicit := Dict_Explicit;
      Crab_Buffers.Resize (S.Chunk_Buf,
        Crab_Compression.Compress_Bound (S.Algo, Chunk_Size));
      S.Query_Str   := UBS.To_Unbounded_String (Query);
      S.Query_Bare_CS := 0;

      case S.Algo is
         when Crab_Compression.Deflate =>
            S.Dict_Z := Crab_Zlib.Init_Stream (Level);
            S.Bare_Z := Crab_Zlib.Init_Stream (Level);
            Crab_Zlib.Set_Dict (S.Dict_Z, Query);
            Crab_Zlib.Set_Dict (S.Bare_Z, "");
         when Crab_Compression.LZ4 =>
            S.Dict_L4 := Crab_LZ4.Init_Stream;
            S.Bare_L4 := Crab_LZ4.Init_Stream;
            Crab_LZ4.Load_Dict (S.Dict_L4, Query);
            Crab_LZ4.Load_Dict (S.Bare_L4, "");
         when Crab_Compression.ELZ =>
            Crab_ELZ.Init_Roots (S.ELZ_S);
            declare
               MC : Natural;
            begin
               if Dict_Explicit then
                  MC := Dict_Size;
               else
                  MC := Crab_Compression.ELZ_Max_Codes_For_Level
                          (Level);
               end if;
               Crab_ELZ.Set_Max_Codes (S.ELZ_S, MC);
            end;
         when Crab_Compression.LZMA =>
            null;  -- streams created per Score call
      end case;

      --  Compute |compress(Q, ∅)| once — constant for all scoring calls
      declare
         Q_CS : Natural;
      begin
         case S.Algo is
            when Crab_Compression.Deflate =>
               Q_CS := Crab_Zlib.Compress_Bare (Query, Level, "");
            when Crab_Compression.LZ4 =>
               --  Translate normalised level to LZ4 acceleration
               declare
                  LZ4_Accel : constant Integer :=
                    Integer'Max (1, 2 ** (9 - Level));
               begin
                  Q_CS := Crab_LZ4.Compress_Bare
                    (Query, LZ4_Accel, "");
               end;
            when Crab_Compression.ELZ =>
               Q_CS := Crab_ELZ.Compress_Bare (Query, "");
            when Crab_Compression.LZMA =>
               Q_CS := Crab_LZMA.Compress_Bare
                 (Query, Level, Dict_Size, "");
         end case;
         S.Query_Bare_CS := Q_CS;
      end;
   exception
      when E : Crab_Zlib.Zlib_Error |
               Crab_LZ4.LZ4_Error |
               Crab_ELZ.ELZ_Error |
               Crab_LZMA.LZMA_Error =>
         raise Crab_Compression.Compression_Error
           with Ada.Exceptions.Exception_Message (E);
   end Init;

   --  ==================================================================

   function Score (S : in out State; Chunk : String) return Integer is
      Bare_CS : Natural;
      Dict_CS : Natural;
      Query_Dict_CS : Natural;
   begin
      --  Ensure Chunk_Buf is large enough (handles line-mode sizing)
      declare
         Q_Len : constant Natural :=
           Ada.Strings.Unbounded.Length (S.Query_Str);
         Needed : constant Natural :=
           (case S.Algo is
              when Crab_Compression.ELZ =>
                Natural'Max
                  (Crab_Compression.Compress_Bound
                     (Crab_Compression.ELZ, Chunk'Length),
                   Crab_Compression.Compress_Bound
                     (Crab_Compression.ELZ, Q_Len)),
              when others =>
                Crab_Compression.Compress_Bound (S.Algo, Chunk'Length));
      begin
         if Needed > Crab_Buffers.Length (S.Chunk_Buf) then
            Crab_Buffers.Resize (S.Chunk_Buf,
              Positive'Max (Needed, Crab_Buffers.Length (S.Chunk_Buf) * 2));
         end if;
      end;

      case S.Algo is
         when Crab_Compression.Deflate =>
            Crab_Zlib.Compress_Stream
              (S.Bare_Z, Chunk, S.Chunk_Buf, Bare_CS);
            Crab_Zlib.Compress_Stream
              (S.Dict_Z, Chunk, S.Chunk_Buf, Dict_CS);
            Query_Dict_CS := Crab_Zlib.Compress_Bare
              (UBS.To_String (S.Query_Str), S.Level, Chunk);

         when Crab_Compression.LZ4 =>
            --  Translate normalised level (0..9) to LZ4 acceleration.
            --  0 = fastest (accel 512), 9 = best (accel 1).
            --  LZ4_resetStream_fast discards the dictionary, so
            --  we must reload it before each compression.
            --  Important: LZ4_loadDict stores a pointer (not a copy)
            --  to the dictionary data, so the dict strings must remain
            --  alive across the Load_Dict and Compress_Stream calls.
            declare
               LZ4_Accel : constant Integer :=
                 Integer'Max (1, 2 ** (9 - S.Level));
               Query_Str : constant String :=
                 UBS.To_String (S.Query_Str);
               Empty_Dict : constant String := "";
            begin
               Crab_LZ4.Load_Dict (S.Bare_L4, Empty_Dict);
               Crab_LZ4.Compress_Stream
                 (S.Bare_L4, Chunk, S.Chunk_Buf,
                  LZ4_Accel, Bare_CS);
               Crab_LZ4.Load_Dict (S.Dict_L4, Query_Str);
               Crab_LZ4.Compress_Stream
                 (S.Dict_L4, Chunk, S.Chunk_Buf,
                  LZ4_Accel, Dict_CS);
               Query_Dict_CS := Crab_LZ4.Compress_Bare
                 (Query_Str, LZ4_Accel, Chunk);
            end;

         when Crab_Compression.ELZ =>
            --  Phase 1: compress Chunk with empty dict, producing
            --  Bare_CS while building the string table from Chunk.
            Crab_ELZ.Load_Dict (S.ELZ_S, "");
            Crab_ELZ.Compress_Stream
              (S.ELZ_S, Chunk, S.Chunk_Buf,
               S.Level, Bare_CS);

            --  Phase 2: compress Query reusing Chunk's string table
            --  for lookups.  Produces |Q|C| directly.
            Crab_ELZ.Compress_Stream
              (S.ELZ_S, UBS.To_String (S.Query_Str),
               S.Chunk_Buf, S.Level, Query_Dict_CS);

            --  Reset and prime with Query for |C|Q|.
            Crab_ELZ.Reset_Stream (S.ELZ_S);
            Crab_ELZ.Load_Dict
              (S.ELZ_S, UBS.To_String (S.Query_Str));
            Crab_ELZ.Compress_Stream
              (S.ELZ_S, Chunk, S.Chunk_Buf,
               S.Level, Dict_CS);

         when Crab_Compression.LZMA =>
            --  LZMA streams are created and destroyed per Score call
            --  to avoid simultaneous memory usage from large dictionaries.
            --  Use scoped access type with 'Storage_Size for automatic
            --  pool reclamation on scope exit (RM 13.11(18)).
            declare
               type LZMA_Arena is access all Crab_LZMA.LZMA_Ctx;
               for LZMA_Arena'Storage_Size
                 use 2 * Crab_LZMA.LZMA_Ctx'Max_Size_In_Storage_Elements;
               Stream : LZMA_Arena;
               DSize  : constant Natural :=
                 (if S.Dict_Size > 0 then S.Dict_Size else 8_388_608);
            begin
               --  Pass 1: compress Chunk with empty dictionary
               Stream := new Crab_LZMA.LZMA_Ctx'
                 (Crab_LZMA.Init_Stream (S.Level, DSize, ""));
               Crab_LZMA.Compress_Stream
                 (Stream.all, Chunk, S.Chunk_Buf, Bare_CS);
               Crab_LZMA.Free_Stream (Stream.all);

               --  Pass 2: compress Chunk with Query as dictionary
               Stream := new Crab_LZMA.LZMA_Ctx'
                 (Crab_LZMA.Init_Stream
                    (S.Level, DSize, UBS.To_String (S.Query_Str)));
               Crab_LZMA.Compress_Stream
                 (Stream.all, Chunk, S.Chunk_Buf, Dict_CS);
               Crab_LZMA.Free_Stream (Stream.all);

               --  Pass 3: compress Query with Chunk as dictionary
               --  (Compress_Bare creates and frees its own stream)
               Query_Dict_CS := Crab_LZMA.Compress_Bare
                 (UBS.To_String (S.Query_Str), S.Level, DSize, Chunk);
            end;
      end case;

      return (Integer (Bare_CS) - Integer (Dict_CS)
              + Integer (S.Query_Bare_CS) - Integer (Query_Dict_CS)) / 2;
   exception
      when E : Crab_Zlib.Zlib_Error |
               Crab_LZ4.LZ4_Error |
               Crab_ELZ.ELZ_Error |
               Crab_LZMA.LZMA_Error =>
         raise Crab_Compression.Compression_Error
           with Ada.Exceptions.Exception_Message (E);
   end Score;

   --  ==================================================================

   overriding procedure Finalize (S : in out State) is
   begin
      case S.Algo is
         when Crab_Compression.Deflate =>
            Crab_Zlib.Free_Stream (S.Dict_Z);
            Crab_Zlib.Free_Stream (S.Bare_Z);
         when Crab_Compression.LZ4 =>
            Crab_LZ4.Free_Stream (S.Dict_L4);
            Crab_LZ4.Free_Stream (S.Bare_L4);
         when Crab_Compression.ELZ =>
            null;  -- ELZ_S auto-finalizes (Limited_Controlled)
         when Crab_Compression.LZMA =>
            null;  -- no persistent streams
      end case;
   end Finalize;

end Crab_Scorer;
