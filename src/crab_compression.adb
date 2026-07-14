with Crab_Zlib;
with Crab_LZ4;
with Crab_ELZ;
with Crab_LZMA;
with Ada.Exceptions;

package body Crab_Compression is

   --  ------------------------------------------------------------------
   --  Level defaults and ranges
   --  ------------------------------------------------------------------

   function Level_Default (Algo : Algorithm) return Integer is
   begin
      case Algo is
         when Deflate => return 6;
         when LZ4     => return 1;
         when ELZ     => return 0;
         when LZMA    => return 6;
      end case;
   end Level_Default;

   function Level_Min (Algo : Algorithm) return Integer is
   begin
      case Algo is
         when Deflate => return -1;
         when LZ4     => return 1;
         when ELZ     => return 0;
         when LZMA    => return 0;
      end case;
   end Level_Min;

   function Level_Max (Algo : Algorithm) return Integer is
   begin
      case Algo is
         when Deflate => return 9;
         when LZ4     => return 65_537;
         when ELZ     => return 0;
         when LZMA    => return 9;
      end case;
   end Level_Max;

   --  ------------------------------------------------------------------
   --  Window_Size dispatch
   --  ------------------------------------------------------------------

   function Window_Size (Algo : Algorithm) return Natural is
   begin
      case Algo is
         when Deflate => return 32_768;   --  32 KB (MAX_WBITS = 15)
         when LZ4     => return 65_536;   --  64 KB
         when ELZ     => return Natural'Last;  --  unbounded
         when LZMA    => return 8_388_608;  --  8 MB (default);
         --  actual size is user-specified via --dict-size
      end case;
   end Window_Size;

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
         when ELZ =>
            return Crab_ELZ.Compress_Bound (Source_Len);
         when LZMA =>
            return Crab_LZMA.Compress_Bound (Source_Len);
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
         when ELZ =>
            return Crab_ELZ.Compress_Bare (Source, Dict);
         when LZMA =>
            return Crab_LZMA.Compress_Bare
              (Source, Level, 8_388_608, Dict);
      end case;
   exception
      when E : Crab_Zlib.Zlib_Error |
               Crab_LZ4.LZ4_Error |
               Crab_ELZ.ELZ_Error |
               Crab_LZMA.LZMA_Error =>
         raise Compression_Error
           with Ada.Exceptions.Exception_Message (E);
   end Compress_Bare;

end Crab_Compression;
