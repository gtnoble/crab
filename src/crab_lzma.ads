--  Crab_LZMA — Streaming Ada binding to liblzma with dictionary support

with Crab_Zlib;
with System;

package Crab_LZMA is

   LZMA_Error : exception;

   function Compress_Bound (Input_Size : Natural) return Natural;
   --  Upper bound (bytes) for the compressed size of Input_Size bytes.

   type LZMA_Ctx is limited private;
   --  An LZMA streaming compression context.
   --  Limited to prevent copying; managed via Init_Stream / Free_Stream.

   function Init_Stream
     (Level     : Integer;
      Dict_Size : Natural) return LZMA_Ctx;
   --  Allocate and initialise a new LZMA stream with the given
   --  compression level (0–9) and explicit dictionary size in bytes.
   --  Uses lzma_stream_encoder with lzma_lzma_preset for level-derived
   --  settings, overriding dict_size.
   --  Raises LZMA_Error on failure.

   procedure Load_Dict (S : in out LZMA_Ctx; Dict : String);
   --  Prime the encoder by compressing Dict through it (LZMA_RUN).
   --  This populates the internal LZMA dictionary structures.
   --  Must be called after Init_Stream and after each re-init cycle.
   --  Raises LZMA_Error on failure.

   procedure Compress_Stream
     (S        : in out LZMA_Ctx;
      Source   : String;
      Dest     : in out Crab_Zlib.Byte_Array;
      Dest_Len : out Natural);
   --  Compress Source using the primed encoder state (LZMA_FINISH).
   --  Dest must be at least Compress_Bound (Source'Length) bytes.
   --  After compression the encoder is consumed; Load_Dict must be
   --  called again before the next Compress_Stream.
   --  Raises LZMA_Error on failure.

   procedure Free_Stream (S : in out LZMA_Ctx);
   --  Deallocate the stream (lzma_end).
   --  After this call the stream is invalid and must not be used.

   function Compress_Bare
     (Source    : String;
      Level     : Integer;
      Dict_Size : Natural;
      Dict      : String) return Natural;
   --  Convenience: Init_Stream → Load_Dict → Compress_Stream →
   --  Free_Stream.  Used for tests and one-shot operations.

private

   type LZMA_Ctx is limited record
      Handle : System.Address;
   end record;

end Crab_LZMA;
