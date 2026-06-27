--  Crab_LZ4 — Streaming Ada binding to liblz4 with dictionary support

with Crab_Buffers;
with System;

package Crab_LZ4 is

   LZ4_Error : exception;

   function Compress_Bound (Input_Size : Natural) return Natural;
   --  Upper bound (bytes) for the compressed size of Input_Size bytes.

   type LZ4_Stream is private;
   --  An LZ4 streaming compression context.
   --  Limited to prevent copying; managed via Init_Stream / Free_Stream.

   function Init_Stream return LZ4_Stream;
   --  Allocate a new LZ4 stream (LZ4_createStream).
   --  Raises LZ4_Error if allocation fails.

   procedure Load_Dict (S : in out LZ4_Stream; Dict : String);
   --  Load Dict into the stream's dictionary (LZ4_loadDict).
   --  Must be called after Init_Stream and after each
   --  Reset_Stream cycle if a new dictionary is needed.
   --  Raises LZ4_Error if not all bytes could be loaded.

   procedure Compress_Stream
     (S            : in out LZ4_Stream;
      Source       : String;
      Dest         : in out Crab_Buffers.Byte_Buffer;
      Acceleration : Integer;
      Dest_Len     : out Natural);
   --  Compress Source using the stream's current state (dictionary,
   --  acceleration) via LZ4_compress_fast_continue.
   --  Dest must be at least Compress_Bound (Source'Length) bytes.
   --  After compression, the stream is reset via LZ4_resetStream_fast,
   --  which preserves the dictionary — Load_Dict does not need to be
   --  called again for the same dictionary.
   --  Raises LZ4_Error if compression fails.

   procedure Free_Stream (S : in out LZ4_Stream);
   --  Deallocate the stream (LZ4_freeStream).
   --  After this call the stream is invalid and must not be used.

   function Compress_Bare
     (Source       : String;
      Acceleration : Integer;
      Dict         : String) return Natural;
   --  Convenience: Init_Stream → Load_Dict → Compress_Stream →
   --  Free_Stream.  Used for tests and one-shot operations.

private

   type LZ4_Stream is record
      Handle : System.Address;
   end record;

end Crab_LZ4;
