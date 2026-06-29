--  Crab_Scorer — Stateful mutual-information scorer
--  Uses dictionary-preloaded streaming compression.
--  State is a variant record discriminated by Algorithm — each
--  backend's stream types are stored directly, eliminating
--  System.Address type-erasure and Unchecked_Conversion.

with Ada.Finalization;
with Ada.Strings.Unbounded;
with Crab_Buffers;
with Crab_Compression;

private with Crab_Zlib;
private with Crab_LZ4;
private with Crab_LZW;

package Crab_Scorer is

   type State (Algo : Crab_Compression.Algorithm) is
     new Ada.Finalization.Limited_Controlled with private;
   --  Cached scorer state including persistent streaming compressor
   --  objects and output buffer.  Finalize frees all resources.

   procedure Init
     (S             : in out State;
      Query         : String;
      Chunk_Size    : Positive;
      Level         : Integer;
      Dict_Size     : Natural := 8_388_608;
      LZW_Max_Codes : Natural := 0);
   --  Create persistent streaming compressor objects:
   --    Deflate/LZ4: two streams (dict-preloaded + bare)
   --    LZW: single stream, reused across Score phases.
   --      When LZW_Max_Codes > 0, the string table is bounded to
   --      at most LZW_Max_Codes active codes via LRU leaf eviction.
   --    LZMA: no persistent streams (created/destroyed per Score call)
   --  Also pre-allocates Chunk_Buf (size = Compress_Bound (Chunk_Size)).
   --  Dict_Size is used only for LZMA; ignored for other algorithms.
   --  LZW_Max_Codes is used only for LZW; ignored for other algorithms.
   --  Raises Crab_Compression.Compression_Error on failure.

   function Score (S : in out State; Chunk : String) return Integer;
   --  Compute symmetric MI-approx = (h(C) - h(C|Q) + h(Q) - h(Q|C)) / 2
   --  Returns Integer; may be negative (REQ-025).
   --  Raises Crab_Compression.Compression_Error on failure.

   overriding procedure Finalize (S : in out State);
   --  Free all compressor streams and the output buffer.

private

   type State (Algo : Crab_Compression.Algorithm) is
     new Ada.Finalization.Limited_Controlled with record
      Level         : Integer;
      Dict_Size     : Natural;
      Chunk_Buf     : Crab_Buffers.Byte_Buffer;
      Query_Str     : Ada.Strings.Unbounded.Unbounded_String;
      Query_Bare_CS : Natural;
      case Algo is
         when Crab_Compression.Deflate =>
            Dict_Z : Crab_Zlib.ZStream;
            Bare_Z : Crab_Zlib.ZStream;
         when Crab_Compression.LZ4 =>
            Dict_L4 : Crab_LZ4.LZ4_Stream;
            Bare_L4 : Crab_LZ4.LZ4_Stream;
         when Crab_Compression.LZW =>
            LZW_S  : Crab_LZW.LZW_Stream;
         when Crab_Compression.LZMA =>
            null;  -- streams created/destroyed per Score call
      end case;
   end record;

end Crab_Scorer;
