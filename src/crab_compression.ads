--  Crab_Compression — Uniform compression interface over DEFLATE / LZ4

package Crab_Compression is

   type Algorithm is (Deflate, LZ4);

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

   function Compress_Bare
     (Algo   : Algorithm;
      Source : String;
      Level  : Integer;
      Dict   : String) return Natural;
   --  Convenience wrapper: init stream, set dictionary, compress,
   --  free stream, return compressed size.  Used for tests and
   --  one-shot operations.
   --  Raises Compression_Error on failure.

end Crab_Compression;
