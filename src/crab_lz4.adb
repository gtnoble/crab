with Interfaces.C;
with System;

package body Crab_LZ4 is

   use type Interfaces.C.int;

   function LZ4_compress_fast
     (Src          : System.Address;
      Dst          : System.Address;
      Src_Size     : Interfaces.C.int;
      Dst_Capacity : Interfaces.C.int;
      Acceleration : Interfaces.C.int) return Interfaces.C.int
      with Import, Convention => C, External_Name => "LZ4_compress_fast";

   function LZ4_compressBound
     (Input_Size : Interfaces.C.int) return Interfaces.C.int
      with Import, Convention => C, External_Name => "LZ4_compressBound";

   --  ------------------------------------------------------------------

   function Compress_Bound (Input_Size : Natural) return Natural is
   begin
      return Natural
        (LZ4_compressBound (Interfaces.C.int (Input_Size)));
   end Compress_Bound;

   --  ------------------------------------------------------------------

   procedure Compress_Into
     (Source       : String;
      Acceleration : Integer;
      Dest         : in out Crab_Zlib.Byte_Array;
      Dest_Len     : out Natural)
   is
      Src_Size : constant Interfaces.C.int :=
        Interfaces.C.int (Source'Length);
      Dst_Cap  : constant Interfaces.C.int :=
        Interfaces.C.int (Dest'Length);
      Result   : Interfaces.C.int;
   begin
      Result := LZ4_compress_fast
        (Source'Address, Dest'Address, Src_Size, Dst_Cap,
         Interfaces.C.int (Acceleration));
      if Result <= 0 then
         raise LZ4_Error;
      end if;
      Dest_Len := Natural (Result);
   end Compress_Into;

   --  ------------------------------------------------------------------

   function Compress
     (Source       : String;
      Acceleration : Integer) return Natural
   is
      Dst_Buf : Crab_Zlib.Byte_Array
        (1 .. Compress_Bound (Source'Length));
      Dst_Len : Natural;
   begin
      Compress_Into (Source, Acceleration, Dst_Buf, Dst_Len);
      return Dst_Len;
   end Compress;

end Crab_LZ4;
