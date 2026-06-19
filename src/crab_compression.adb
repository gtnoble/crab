with Crab_Zlib;
with Crab_LZ4;

package body Crab_Compression is

   --  ------------------------------------------------------------------
   --  Level defaults and ranges
   --  ------------------------------------------------------------------

   function Level_Default (Algo : Algorithm) return Integer is
   begin
      case Algo is
         when Deflate => return 6;
         when LZ4     => return 1;
      end case;
   end Level_Default;

   function Level_Min (Algo : Algorithm) return Integer is
   begin
      case Algo is
         when Deflate => return -1;
         when LZ4     => return 1;
      end case;
   end Level_Min;

   function Level_Max (Algo : Algorithm) return Integer is
   begin
      case Algo is
         when Deflate => return 9;
         when LZ4     => return 65_537;
      end case;
   end Level_Max;

   --  ------------------------------------------------------------------
   --  Compress_Bound dispatch
   --  ------------------------------------------------------------------

   function Compress_Bound
     (Algo       : Algorithm;
      Source_Len : Natural) return Natural
   is
   begin
      case Algo is
         when Deflate =>
            return Crab_Zlib.Compress_Bound (Source_Len);
         when LZ4 =>
            return Crab_LZ4.Compress_Bound (Source_Len);
      end case;
   end Compress_Bound;

   --  ------------------------------------------------------------------
   --  Compress_Bare dispatch
   --  ------------------------------------------------------------------

   function Compress_Bare
     (Algo   : Algorithm;
      Source : String;
      Level  : Integer;
      Dict   : String) return Natural
   is
   begin
      case Algo is
         when Deflate =>
            return Crab_Zlib.Compress_Bare (Source, Level, Dict);
         when LZ4 =>
            return Crab_LZ4.Compress_Bare (Source, Level, Dict);
      end case;
   exception
      when Crab_Zlib.Zlib_Error | Crab_LZ4.LZ4_Error =>
         raise Compression_Error;
   end Compress_Bare;

end Crab_Compression;
