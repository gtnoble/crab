with Interfaces.C;
with System;

package body Crab_Zlib is

   use type Interfaces.C.int;

   Z_OK : constant Interfaces.C.int := 0;

   function c_compressBound
     (Source_Len : Interfaces.C.unsigned_long)
      return Interfaces.C.unsigned_long
      with Import, Convention => C, External_Name => "compressBound";

   function c_compress2
     (Dest       : System.Address;
      Dest_Len   : access Interfaces.C.unsigned_long;
      Source     : System.Address;
      Source_Len : Interfaces.C.unsigned_long;
      Level      : Interfaces.C.int) return Interfaces.C.int
      with Import, Convention => C, External_Name => "compress2";

   --  ------------------------------------------------------------------

   function Compress_Bound (Source_Len : Natural) return Natural is
   begin
      return Natural
        (c_compressBound (Interfaces.C.unsigned_long (Source_Len)));
   end Compress_Bound;

   --  ------------------------------------------------------------------

   procedure Compress_Into
     (Source   : String;
      Level    : Integer;
      Dest     : in out Byte_Array;
      Dest_Len : out Natural)
   is
      --  Map crab's level semantics to zlib's:
      --    crab -1 = no compression  -> zlib  0
      --    crab  0 = default (6)     -> zlib -1
      --    crab 1-9 = pass through
      Zlib_Level : constant Integer :=
        (if Level = -1 then 0
         elsif Level = 0 then -1
         else Level);

      Src_Len : constant Interfaces.C.unsigned_long :=
        Interfaces.C.unsigned_long (Source'Length);
      Dst_Cap : aliased Interfaces.C.unsigned_long :=
        Interfaces.C.unsigned_long (Dest'Length);
      Result  : Interfaces.C.int;
   begin
      Result := c_compress2
        (Dest'Address, Dst_Cap'Access, Source'Address,
         Src_Len, Interfaces.C.int (Zlib_Level));
      if Result /= Z_OK then
         raise Zlib_Error;
      end if;
      Dest_Len := Natural (Dst_Cap);
   end Compress_Into;

   --  ------------------------------------------------------------------

   function Compress (Source : String; Level : Integer) return Natural is
      Dst_Buf : Byte_Array (1 .. Compress_Bound (Source'Length));
      Dst_Len : Natural;
   begin
      Compress_Into (Source, Level, Dst_Buf, Dst_Len);
      return Dst_Len;
   end Compress;

end Crab_Zlib;
