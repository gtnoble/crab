--  Crab_Scorer — Stateful mutual-information scorer
--  Uses dictionary-preloaded streaming compression

with Ada.Finalization;
with Ada.Strings.Unbounded;
with Crab_Buffers;
with Crab_Compression;
with System;

package Crab_Scorer is

   type State is new Ada.Finalization.Limited_Controlled with private;
   --  Cached scorer state including persistent streaming compressor
   --  objects and output buffer.  Finalize frees all resources.

   procedure Init
     (S          : out State;
      Query      : String;
      Chunk_Size : Positive;
      Algo       : Crab_Compression.Algorithm;
      Level      : Integer;
      Dict_Size  : Natural := 8_388_608);
   --  Create two persistent streaming compressor objects:
   --    Dict_Stream  — pre-loaded with Query as dictionary
   --    Bare_Stream  — loaded with empty dictionary (baseline)
   --  Also pre-allocates Chunk_Buf (size = Compress_Bound (Chunk_Size)).
   --  Dict_Size is used only for LZMA; ignored for other algorithms.
   --  Raises Crab_Compression.Compression_Error on failure.

   function Score (S : in out State; Chunk : String) return Integer;
   --  Compute symmetric MI-approx = (h(C) - h(C|Q) + h(Q) - h(Q|C)) / 2
   --  Returns Integer; may be negative (REQ-025).
   --  Raises Crab_Compression.Compression_Error on failure.

   overriding procedure Finalize (S : in out State);
   --  Free all compressor streams and the output buffer.

private

   type Byte_Buffer_Access is access all Crab_Buffers.Byte_Buffer;

   --  Opaque handle for backend-specific stream state.
   --  Each backend module provides its own stream type; we store
   --  them as System.Address and cast internally in the body.
   type Stream_Handle is new System.Address;

   type State is new Ada.Finalization.Limited_Controlled with record
      Algo          : Crab_Compression.Algorithm;
      Level         : Integer;
      Dict_Size     : Natural;
      Chunk_Buf     : Byte_Buffer_Access;
      Query_Str     : Ada.Strings.Unbounded.Unbounded_String;
      Query_Bare_CS : Natural;
      Dict_Stream   : Stream_Handle;
      Bare_Stream   : Stream_Handle;
   end record;

end Crab_Scorer;
