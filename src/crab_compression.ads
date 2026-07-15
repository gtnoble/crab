--  Crab_Compression — Uniform compression interface over
--  DEFLATE / LZ4 / ELZ / LZMA

package Crab_Compression is

   type Algorithm is (Deflate, LZ4, ELZ, LZMA);

   Compression_Error : exception;
   --  Raised when a backend returns an error code.

   function Level_Default (Algo : Algorithm) return Integer;
   --  The default compression level.  All algorithms use 6.
   --  Retained for parameterisation but always returns 6.

   function Level_Min (Algo : Algorithm) return Integer;
   --  The minimum valid compression level.  All algorithms use 0.

   function Level_Max (Algo : Algorithm) return Integer;
   --  The maximum valid compression level.  All algorithms use 9.

   function Window_Size (Algo : Algorithm) return Natural;
   --  Sliding-window / dictionary size limit in bytes.
   --  Deflate -> 32768 (32 KB), LZ4 -> 65536 (64 KB),
   --  ELZ -> Natural'Last (unbounded),
   --  LZMA -> 8_388_608 (8 MB default; actual size is user-specified
   --          via --dict-size).

   function Default_Dict_Size (Algo : Algorithm) return Natural;
   --  Default dictionary-size parameter:
   --    Deflate, LZ4 -> 0 (not applicable)
   --    ELZ           -> ELZ_Max_Codes_For_Level (6)  (1,000,000 codes)
   --    LZMA          -> 8_388_608 (8 MB)

   function ELZ_Max_Codes_For_Level (Level : Natural) return Natural;
   --  Map the normalised level (0..9) to the ELZ max-codes limit.
   --  0 = 1,000 codes (fastest), 9 = 0 codes (unbounded, best).
   --  Exponential scaling: floor (10^(3 + Level/2)), with L9 = 0.

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
