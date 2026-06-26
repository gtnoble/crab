--  Crab_LZMA -- Streaming Ada binding to liblzma with dictionary support

with Crab_Buffers;
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
      Dict_Size : Natural;
      Dict      : String := "") return LZMA_Ctx;
   --  Allocate and initialise a new LZMA stream with the given
   --  compression level (0..9) and explicit dictionary size in bytes.
   --  Dict is loaded as a preset dictionary (LZMA match-finding only;
   --  probability model starts fresh).  This provides clean mutual-
   --  information signal without corrupting the model.
   --  Raises LZMA_Error on failure.

   procedure Load_Dict (S : in out LZMA_Ctx; Dict : String);
   --  Deprecated.  Dictionary is now specified at Init_Stream time.
   --  This procedure does nothing and is kept for API compatibility.

   procedure Compress_Stream
     (S        : in out LZMA_Ctx;
      Source   : String;
      Dest     : in out Crab_Buffers.Byte_Buffer;
      Dest_Len : out Natural);
   --  Compress Source using the primed encoder state (LZMA_FINISH).
   --  Dest must be at least Compress_Bound (Source'Length) bytes.
   --  After compression the encoder is consumed.  Re-init to change
   --  the dictionary; Load_Dict is a no-op.
   --  Raises LZMA_Error on failure.

   procedure Free_Stream (S : in out LZMA_Ctx);
   --  Deallocate the stream (lzma_end).
   --  After this call the stream is invalid and must not be used.

   function Compress_Bare
     (Source    : String;
      Level     : Integer;
      Dict_Size : Natural;
      Dict      : String) return Natural;
   --  Convenience: Init_Stream (with optional Dict) -> Compress_Stream ->
   --  Free_Stream.  Used for tests and one-shot operations.

private

   type LZMA_Ctx is limited record
      Handle : System.Address;
   end record;

end Crab_LZMA;
