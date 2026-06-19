--  Crab_Scorer — Stateful mutual-information scorer
--  Uses dictionary-preloaded streaming compression

with Ada.Strings.Unbounded;
with Crab_Compression;
with Crab_Zlib;
with Crab_LZ4;

package Crab_Scorer is

   type State is limited private;
   --  Cached scorer state including persistent streaming compressor
   --  objects and output buffer.

   function Init
     (Query      : String;
      Chunk_Size : Positive;
      Algo       : Crab_Compression.Algorithm;
      Level      : Integer) return State;
   --  Create two persistent streaming compressor objects:
   --    Dict_Stream  — pre-loaded with Query as dictionary
   --    Bare_Stream  — loaded with empty dictionary (baseline)
   --  Also pre-allocates Chunk_Buf (size = Compress_Bound (Chunk_Size)).
   --  Raises Crab_Compression.Compression_Error on failure.

   function Score (S : in out State; Chunk : String) return Integer;
   --  Compute MI-approx = |compress(C, dict=∅)| − |compress(C, dict=Q)|
   --  Returns Integer; may be negative (REQ-025).
   --  Raises Crab_Compression.Compression_Error on failure.

private

   type Zlib_Stream_Access is access all Crab_Zlib.ZStream;

   type LZ4_Stream_Access is access all Crab_LZ4.LZ4_Stream;

   type Byte_Array_Access is access all Crab_Zlib.Byte_Array;

   type State is record
      Algo       : Crab_Compression.Algorithm;
      Level      : Integer;
      Chunk_Buf  : Byte_Array_Access;
      Query_Str  : Ada.Strings.Unbounded.Unbounded_String;
      Dict_Z     : Zlib_Stream_Access;   -- valid when Algo = Deflate
      Bare_Z     : Zlib_Stream_Access;   -- valid when Algo = Deflate
      Dict_L     : LZ4_Stream_Access;    -- valid when Algo = LZ4
      Bare_L     : LZ4_Stream_Access;    -- valid when Algo = LZ4
   end record;

end Crab_Scorer;
