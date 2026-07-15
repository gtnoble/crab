with Crab_Zlib;
with Crab_LZ4;
with Crab_ELZ;
with Crab_LZMA;
with Ada.Exceptions;

package body Crab_Compression is

   --  ------------------------------------------------------------------
   --  Level defaults and ranges — normalised to 0..9 for all algorithms
   --  ------------------------------------------------------------------

   function Level_Default (Algo : Algorithm) return Integer is
      pragma Unreferenced (Algo);
   begin
      return 6;
   end Level_Default;

   function Level_Min (Algo : Algorithm) return Integer is
      pragma Unreferenced (Algo);
   begin
      return 0;
   end Level_Min;

   function Level_Max (Algo : Algorithm) return Integer is
      pragma Unreferenced (Algo);
   begin
      return 9;
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
   --  Default_Dict_Size
   --  ------------------------------------------------------------------

   function Default_Dict_Size (Algo : Algorithm) return Natural is
   begin
      case Algo is
         when Deflate | LZ4 =>
            return 0;
         when ELZ =>
            return ELZ_Max_Codes_For_Level (6);
         when LZMA =>
            return 8_388_608;
      end case;
   end Default_Dict_Size;

   --  ------------------------------------------------------------------
   --  ELZ_Max_Codes_For_Level — exponential mapping
   --  ------------------------------------------------------------------

   ELZ_Max_Codes_Table : constant array (0 .. 9) of Natural :=
     (0 => 1_000,
      1 => 3_162,
      2 => 10_000,
      3 => 31_623,
      4 => 100_000,
      5 => 316_228,
      6 => 1_000_000,
      7 => 3_162_278,
      8 => 10_000_000,
      9 => 0);  --  unbounded

   function ELZ_Max_Codes_For_Level (Level : Natural) return Natural is
   begin
      if Level <= 9 then
         return ELZ_Max_Codes_Table (Level);
      else
         return 0;  --  unbounded for out-of-range
      end if;
   end ELZ_Max_Codes_For_Level;

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
