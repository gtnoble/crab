--  Crab_Compression — Uniform compression interface over
--  DEFLATE / LZ4 / ELZ / LZMA

package Crab_Compression is

   type Algorithm is (Deflate, LZ4, ELZ, LZMA);

   Compression_Error : exception;
   --  Raised when a backend returns an error code.

   function Level_Default (Algo : Algorithm) return Integer;
   --  The default compression level for the given algorithm.

   function Level_Min (Algo : Algorithm) return Integer;
   --  The minimum valid compression level for the given algorithm.

   function Level_Max (Algo : Algorithm) return Integer;
   --  The maximum valid compression level for the given algorithm.

   function Window_Size (Algo : Algorithm) return Natural;
   --  Sliding-window / dictionary size limit in bytes.
   --  Deflate -> 32768 (32 KB), LZ4 -> 65536 (64 KB),
   --  ELZ -> Natural'Last (unbounded),
   --  LZMA -> 8_388_608 (8 MB default; actual size is user-specified
   --          via --dict-size).

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
   --  Note: for LZMA, this uses the default 8 MB dictionary size.
   --  Raises Compression_Error on failure.

end Crab_Compression;
