--  Crab_Zlib — Streaming Ada binding to libz with dictionary support

with Crab_Buffers;
with System;

package Crab_Zlib is

   Zlib_Error : exception;

   Z_OK         : constant := 0;
   Z_STREAM_END : constant := 1;

   function Compress_Bound (Source_Len : Natural) return Natural;
   --  Upper bound (bytes) for the compressed size of Source_Len bytes.

   type ZStream is private;
   --  A deflate stream.  Managed via Init_Stream / Free_Stream.

   function Init_Stream (Level : Integer) return ZStream;
   --  Allocate and initialise a new deflate stream.
   --  Level: crab -1=stored, 0=default(6), 1-9=pass-through.
   --  Raises Zlib_Error on failure.

   procedure Set_Dict (S : in out ZStream; Dict : String);
   --  Load Dict into stream's compression window.
   --  Raises Zlib_Error on failure.

   procedure Compress_Stream
     (S        : in out ZStream;
      Source   : String;
      Dest     : in out Crab_Buffers.Byte_Buffer;
      Dest_Len : out Natural);
   --  Compress Source; resets stream but keeps dictionary.
   --  Raises Zlib_Error on failure.

   procedure Free_Stream (S : in out ZStream);
   --  Deallocate the stream.

   function Compress_Bare
     (Source : String;
      Level  : Integer;
      Dict   : String) return Natural;
   --  Convenience: init → set-dict → compress → free.

private

   type ZStream is record
      Raw : System.Address;
   end record;

end Crab_Zlib;
