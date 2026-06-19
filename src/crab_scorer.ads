--  Crab_Scorer — Stateful mutual-information scorer

with Ada.Strings.Unbounded;
with Crab_Compression;

package Crab_Scorer is

   type State is private;
   --  Cached scorer state including persistent compression buffers.

   function Init
     (Query      : String;
      Chunk_Size : Positive;
      Algo       : Crab_Compression.Algorithm;
      Level      : Integer) return State;
   --  Pre-compress the Query (one-shot), allocate persistent buffers
   --  for Chunk and Joint compression, cache everything in State.
   --  Raises Crab_Compression.Compression_Error on failure.

   function Score (S : in out State; Chunk : String) return Integer;
   --  Compute MI-approx = |compress(Q)| + |compress(C)| - |compress(Q||C)|
   --  using the persistent buffers in S.  Zero heap allocation.
   --  Score may be negative (REQ-025).
   --  Raises Crab_Compression.Compression_Error on failure.

private

   type Byte_Array_Access is access all Crab_Compression.Byte_Array;
   --  Heap-allocated, dynamically sized at Init time.

   type State is record
      Algo      : Crab_Compression.Algorithm;
      Level     : Integer;
      Query_Str : Ada.Strings.Unbounded.Unbounded_String;
      Query_CS  : Natural;
      Chunk_Buf : Byte_Array_Access;
      Joint_Buf : Byte_Array_Access;
   end record;

end Crab_Scorer;
