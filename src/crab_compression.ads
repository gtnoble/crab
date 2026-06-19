--  Crab_Compression — Uniform compression interface over DEFLATE / LZ4

with Crab_Zlib;

package Crab_Compression is

   type Algorithm is (Deflate, LZ4);

   subtype Byte_Array is Crab_Zlib.Byte_Array;
   --  Re-exported from Crab_Zlib for convenience.

   Compression_Error : exception;
   --  Raised when a backend returns an error code.

   function Level_Default (Algo : Algorithm) return Integer;
   --  The default compression level for the given algorithm.

   function Level_Min (Algo : Algorithm) return Integer;
   --  The minimum valid compression level for the given algorithm.

   function Level_Max (Algo : Algorithm) return Integer;
   --  The maximum valid compression level for the given algorithm.

   function Compress_Bound
     (Algo       : Algorithm;
      Source_Len : Natural) return Natural;
   --  Upper bound (bytes) for the compressed size.

   procedure Compress_Into
     (Algo     : Algorithm;
      Source   : String;
      Level    : Integer;
      Dest     : in out Byte_Array;
      Dest_Len : out Natural);
   --  Compress Source into the pre-allocated Dest buffer.
   --  Dispatches to Zlib or LZ4 backend based on Algo.

   function Compress
     (Algo   : Algorithm;
      Source : String;
      Level  : Integer) return Natural;
   --  Convenience wrapper: auto-allocates, compresses,
   --  returns compressed size.

end Crab_Compression;
