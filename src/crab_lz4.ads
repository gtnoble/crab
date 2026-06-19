--  Crab_LZ4 — Thin Ada binding to liblz4 LZ4_compress_fast

with Crab_Zlib;

package Crab_LZ4 is

   LZ4_Error : exception;

   function Compress_Bound (Input_Size : Natural) return Natural;
   --  Upper bound (bytes) for the compressed size of Input_Size bytes.

   procedure Compress_Into
     (Source       : String;
      Acceleration : Integer;
      Dest         : in out Crab_Zlib.Byte_Array;
      Dest_Len     : out Natural);
   --  Compress Source into the pre-allocated Dest buffer using LZ4 fast
   --  mode with the given Acceleration.  Dest must be at least
   --  Compress_Bound (Source'Length) bytes.  Raises LZ4_Error on failure.

   function Compress
     (Source       : String;
      Acceleration : Integer) return Natural;
   --  Convenience wrapper: auto-allocates, compresses,
   --  returns compressed size.

end Crab_LZ4;
